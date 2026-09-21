// Cycle-window trace capture for cl_cva6_trackers.
//
// The host programs [start_i, end_i) in CPU cycles counted from cpu_run_i.
// While the cycle counter is inside that window, this module records:
//   - committed instructions (CVA6 RVFI probes)
//   - I$ DRAM AXI (ID LSB = 0)
//   - D$ DRAM AXI (ID LSB = 1)
//   - L1 I$/D$ tag lookups (hit and miss)
// Always-on (enable + cpu_run, not windowed): event FIFO + L1 hit/miss counters.
// Records sit in dual-clock BRAMs and are read back over OCL.

`include "rvfi_types.svh"

module cva6_trace_capture
  import cva6_trace_pkg::*;
  import ariane_pkg::*;
#(
  parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
  parameter type rvfi_probes_t = logic
) (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         cpu_run_i,

  input  rvfi_probes_t rvfi_probes_i,

  input  logic         ar_valid_i,
  input  logic         ar_ready_i,
  input  logic [3:0]   ar_id_i,
  input  logic [63:0]  ar_addr_i,
  input  logic [2:0]   ar_size_i,
  input  logic         r_valid_i,
  input  logic         r_ready_i,
  input  logic [3:0]   r_id_i,
  input  logic [63:0]  r_data_i,
  input  logic [1:0]   r_resp_i,
  input  logic         r_last_i,
  input  logic         aw_valid_i,
  input  logic         aw_ready_i,
  input  logic [3:0]   aw_id_i,
  input  logic [63:0]  aw_addr_i,
  input  logic [2:0]   aw_size_i,
  input  logic         w_valid_i,
  input  logic         w_ready_i,
  input  logic [63:0]  w_data_i,
  input  logic [7:0]   w_strb_i,
  input  logic         w_last_i,
  input  logic         b_valid_i,
  input  logic         b_ready_i,
  input  logic [3:0]   b_id_i,
  input  logic [1:0]   b_resp_i,

  input  logic         enable_i,
  input  logic [63:0]  start_i,
  input  logic [63:0]  end_i,
  input  logic         clear_i,
  input  logic         stop_on_excp_i,

  output logic [63:0]  cycle_o,
  output logic [31:0]  instr_count_o,
  output logic [31:0]  icache_count_o,
  output logic [31:0]  dcache_count_o,
  output logic [31:0]  event_count_o,
  output logic [31:0]  l1_count_o,
  output logic [31:0]  ic_hit_count_o,
  output logic [31:0]  ic_miss_count_o,
  output logic [31:0]  dc_hit_count_o,
  output logic [31:0]  dc_miss_count_o,
  output logic [31:0]  status_o,

  input  logic         rd_clk_i,
  input  logic [2:0]   rd_sel_i,
  input  logic [15:0]  rd_idx_i,
  input  logic [3:0]   rd_word_i,
  output logic [63:0]  rd_data_o
);

  logic enable_q, clear_q, clear_pulse, frozen_q;
  logic [63:0] cycle_q;
  logic in_window, window_done;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      clear_q  <= 1'b0;
    end else begin
      enable_q <= enable_i;
      clear_q  <= clear_i;
    end
  end
  assign clear_pulse = enable_q ? (clear_i & ~clear_q) : (clear_i & ~clear_q);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      cycle_q <= 64'd0;
    else if (clear_pulse || !cpu_run_i)
      cycle_q <= 64'd0;
    else
      cycle_q <= cycle_q + 64'd1;
  end

  assign cycle_o     = cycle_q;
  assign in_window   = enable_q && cpu_run_i && !frozen_q &&
                       (cycle_q >= start_i) && (cycle_q < end_i);
  assign window_done = enable_q && ((cycle_q >= end_i && end_i != 64'd0) || frozen_q);

  // ---------------------------------------------------------------------------
  // Pack one commit port. CVA6 has a scoreboard (trans_id), not a ROB.
  // Live LSU vaddr/paddr are NOT per-commit (they leak onto ALU ops) — omit.
  // Word map (host dump):
  //   w[0] cycle  w[1] pc
  //   w[2] {rs1[63:56], 8'd0, trans_id[47:40], op[39:32], rs2[15:8], rd[7:0]}
  //   w[3] flags  w[4] rd_wdata  w[13] instret
  // ---------------------------------------------------------------------------
  function automatic instr_rec_t pack_instr(input int unsigned port);
    logic [63:0] w [0:INSTR_WORDS-1];
    logic [63:0] flags;
    logic retire, rd_valid, irq;
    instr_rec_t rec;
    retire   = rvfi_probes_i.instr.commit_ack[port] && !rvfi_probes_i.instr.commit_drop[port];
    rd_valid = retire && (rvfi_probes_i.instr.commit_instr_rd[port] != '0);
    irq      = rvfi_probes_i.instr.ex_commit_cause[CVA6Cfg.XLEN-1];
    flags = 64'd0;
    flags[0]     = rvfi_probes_i.instr.commit_instr_valid[port];
    flags[1]     = rvfi_probes_i.instr.ex_commit_valid;
    flags[3]     = retire;
    flags[4]     = rd_valid;
    flags[8]     = irq;
    flags[10:9]  = rvfi_probes_i.instr.priv_lvl;
    flags[23:16] = rvfi_probes_i.instr.ex_commit_cause[7:0];
    flags[31]    = irq;
    w[0]  = cycle_q;
    w[1]  = {{64-CVA6Cfg.VLEN{1'b0}}, rvfi_probes_i.instr.commit_instr_pc[port]};
    w[2]  = {8'(rvfi_probes_i.instr.commit_instr_rs1[port]),
             8'd0,
             8'(rvfi_probes_i.instr.commit_pointer[port]),
             8'(rvfi_probes_i.instr.commit_instr_op[port]),
             16'd0,
             8'(rvfi_probes_i.instr.commit_instr_rs2[port]),
             8'(rvfi_probes_i.instr.commit_instr_rd[port])};
    w[3]  = flags;
    w[4]  = rvfi_probes_i.instr.wdata[port];
    w[5]  = 64'd0;
    w[6]  = 64'd0;
    w[7]  = rvfi_probes_i.instr.commit_instr_result[port];
    w[8]  = 64'd0;
    w[9]  = 64'd0;
    w[10] = rvfi_probes_i.instr.ex_commit_cause;
    w[11] = 64'd0;
    w[12] = 64'd0;
    w[13] = rvfi_probes_i.csr.instret_q;
    w[14] = 64'd0;
    w[15] = 64'd0;
    rec = '0;
    for (int i = 0; i < INSTR_WORDS; i++)
      rec[i*64 +: 64] = w[i];
    return rec;
  endfunction

  // Always-on event FIFO (not gated by the cycle window). One record per
  // trap / flush-rise / mispredict. Carries live LSU VA/PA and trap CSRs.
  function automatic event_rec_t pack_event();
    logic [63:0] w [0:EVENT_WORDS-1];
    logic [63:0] flags;
    event_rec_t rec;
    flags = 64'd0;
    flags[0]     = rvfi_probes_i.instr.ex_commit_valid;
    flags[1]     = rvfi_probes_i.instr.flush;
    flags[2]     = rvfi_probes_i.instr.branch_valid && rvfi_probes_i.instr.is_mispredict;
    flags[3]     = rvfi_probes_i.instr.is_taken;
    flags[4]     = rvfi_probes_i.instr.debug_mode;
    flags[6:5]   = rvfi_probes_i.instr.priv_lvl;
    flags[7]     = rvfi_probes_i.instr.ex_commit_cause[CVA6Cfg.XLEN-1];
    flags[15:8]  = 8'(rvfi_probes_i.instr.commit_instr_op[0]);
    flags[23:16] = 8'(rvfi_probes_i.instr.commit_pointer[0]);
    flags[31:24] = 8'(rvfi_probes_i.instr.commit_instr_rs1[0]);
    flags[39:32] = 8'(rvfi_probes_i.instr.lsu_ctrl_trans_id);
    flags[43:40] = 4'(rvfi_probes_i.instr.lsu_ctrl_fu);
    flags[44]    = rvfi_probes_i.instr.icache_miss;
    flags[45]    = rvfi_probes_i.instr.dcache_miss;
    w[0]  = cycle_q;
    w[1]  = {{64-CVA6Cfg.VLEN{1'b0}}, rvfi_probes_i.instr.commit_instr_pc[0]};
    w[2]  = flags;
    w[3]  = rvfi_probes_i.instr.ex_commit_cause;
    w[4]  = rvfi_probes_i.instr.tval;
    if (rvfi_probes_i.instr.icache_miss) begin
      w[5] = {{64-CVA6Cfg.VLEN{1'b0}}, rvfi_probes_i.instr.icache_vaddr};
      w[6] = {{64-CVA6Cfg.PLEN{1'b0}}, rvfi_probes_i.instr.icache_paddr};
    end else begin
      w[5] = {{64-CVA6Cfg.VLEN{1'b0}}, rvfi_probes_i.instr.lsu_ctrl_vaddr};
      w[6] = {{64-CVA6Cfg.PLEN{1'b0}}, rvfi_probes_i.instr.mem_paddr};
    end
    w[7]  = {{64-CVA6Cfg.VLEN{1'b0}}, rvfi_probes_i.instr.branch_target};
    w[8]  = rvfi_probes_i.csr.mstatus_extended;
    w[9]  = rvfi_probes_i.csr.mepc_q;
    w[10] = rvfi_probes_i.csr.mcause_q;
    w[11] = rvfi_probes_i.csr.mtval_q;
    w[12] = rvfi_probes_i.csr.mtvec_q;
    w[13] = rvfi_probes_i.csr.satp_q;
    w[14] = rvfi_probes_i.csr.mie_q;
    w[15] = rvfi_probes_i.csr.mip_q;
    rec = '0;
    for (int i = 0; i < EVENT_WORDS; i++)
      rec[i*64 +: 64] = w[i];
    return rec;
  endfunction

  function automatic cache_rec_t pack_cache(
      input logic [63:0] va,
      input logic [63:0] pa,
      input logic [63:0] data,
      input logic [3:0]  id,
      input logic [7:0]  strb,
      input logic [2:0]  size,
      input logic [1:0]  resp,
      input logic [3:0]  kind,
      input logic        we,
      input logic        last
  );
    logic [63:0] w [0:CACHE_WORDS-1];
    logic [63:0] flags;
    cache_rec_t rec;
    flags = 64'd0;
    flags[0]     = we;
    flags[1]     = last;
    flags[3:2]   = resp;
    flags[7:4]   = id;
    flags[15:8]  = strb;
    flags[18:16] = size;
    flags[23:20] = kind;
    w[0] = cycle_q;
    w[1] = va;
    w[2] = pa;
    w[3] = data;
    w[4] = flags;
    w[5] = 64'd0;
    w[6] = 64'd0;
    w[7] = 64'd0;
    rec = '0;
    for (int i = 0; i < CACHE_WORDS; i++)
      rec[i*64 +: 64] = w[i];
    return rec;
  endfunction

  logic v0, v1;
  assign v0 = in_window && (rvfi_probes_i.instr.commit_instr_valid[0] || rvfi_probes_i.instr.commit_ack[0]);
  assign v1 = in_window && (CVA6Cfg.NrCommitPorts > 1) &&
              (rvfi_probes_i.instr.commit_instr_valid[1] || rvfi_probes_i.instr.commit_ack[1]);

  instr_rec_t instr_skid;
  logic       instr_skid_v;
  logic       instr_we;
  instr_rec_t instr_wdata;
  logic [$clog2(INSTR_DEPTH)-1:0] instr_waddr;
  logic [31:0] instr_count_q;
  logic        instr_ovf_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      instr_skid_v  <= 1'b0;
      instr_skid    <= '0;
      instr_count_q <= 32'd0;
      instr_waddr   <= '0;
      instr_ovf_q   <= 1'b0;
      instr_we      <= 1'b0;
      instr_wdata   <= '0;
    end else if (clear_pulse) begin
      instr_skid_v  <= 1'b0;
      instr_count_q <= 32'd0;
      instr_waddr   <= '0;
      instr_ovf_q   <= 1'b0;
      instr_we      <= 1'b0;
    end else begin
      instr_we <= 1'b0;
      if (instr_count_q >= INSTR_DEPTH) begin
        if (v0 || v1 || instr_skid_v)
          instr_ovf_q <= 1'b1;
      end else if (instr_skid_v) begin
        instr_we      <= 1'b1;
        instr_wdata   <= instr_skid;
        instr_waddr   <= instr_count_q[$clog2(INSTR_DEPTH)-1:0];
        instr_count_q <= instr_count_q + 32'd1;
        if (v0) begin
          instr_skid <= pack_instr(0);
          if (v1)
            instr_ovf_q <= 1'b1;
        end else if (v1) begin
          instr_skid <= pack_instr(1);
        end else begin
          instr_skid_v <= 1'b0;
        end
      end else if (v0 && v1) begin
        instr_we      <= 1'b1;
        instr_wdata   <= pack_instr(0);
        instr_waddr   <= instr_count_q[$clog2(INSTR_DEPTH)-1:0];
        instr_count_q <= instr_count_q + 32'd1;
        instr_skid    <= pack_instr(1);
        instr_skid_v  <= 1'b1;
      end else if (v0 || v1) begin
        instr_we      <= 1'b1;
        instr_wdata   <= v0 ? pack_instr(0) : pack_instr(1);
        instr_waddr   <= instr_count_q[$clog2(INSTR_DEPTH)-1:0];
        instr_count_q <= instr_count_q + 32'd1;
      end
    end
  end

  instr_rec_t instr_rdata;
  cva6_trace_ram #(
    .DEPTH (INSTR_DEPTH),
    .WIDTH (INSTR_WORDS * 64)
  ) i_instr_ram (
    .wr_clk_i  (clk_i),
    .wr_en_i   (instr_we),
    .wr_addr_i (instr_waddr),
    .wr_data_i (instr_wdata),
    .rd_clk_i  (rd_clk_i),
    .rd_addr_i (rd_idx_i[$clog2(INSTR_DEPTH)-1:0]),
    .rd_data_o (instr_rdata)
  );

  // ---------------------------------------------------------------------------
  // Event FIFO: traps / flushes / mispredicts / L1 misses. Always on while enabled.
  // ---------------------------------------------------------------------------
  logic trap_d, flush_d, misp_d, ic_miss_d, dc_miss_d;
  logic trap_q, flush_q, misp_q, ic_miss_q, dc_miss_q;
  logic trap_evt, flush_evt, misp_evt, ic_miss_evt, dc_miss_evt, evt;
  assign trap_d    = rvfi_probes_i.instr.ex_commit_valid;
  assign flush_d   = rvfi_probes_i.instr.flush;
  assign misp_d    = rvfi_probes_i.instr.branch_valid && rvfi_probes_i.instr.is_mispredict;
  assign ic_miss_d = rvfi_probes_i.instr.icache_miss;
  assign dc_miss_d = rvfi_probes_i.instr.dcache_miss;
  assign trap_evt    = trap_d    && !trap_q;
  assign flush_evt   = flush_d   && !flush_q;
  assign misp_evt    = misp_d    && !misp_q;
  assign ic_miss_evt = ic_miss_d && !ic_miss_q;
  assign dc_miss_evt = dc_miss_d && !dc_miss_q;
  assign evt = enable_q && cpu_run_i &&
               (trap_evt || flush_evt || misp_evt || ic_miss_evt || dc_miss_evt);

  event_rec_t evt_wdata, evt_rdata;
  logic       evt_we;
  logic [$clog2(EVENT_DEPTH)-1:0] evt_waddr;
  logic [31:0] evt_count_q;
  logic        evt_ovf_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      trap_q      <= 1'b0;
      flush_q     <= 1'b0;
      misp_q      <= 1'b0;
      ic_miss_q   <= 1'b0;
      dc_miss_q   <= 1'b0;
      frozen_q    <= 1'b0;
      evt_we      <= 1'b0;
      evt_wdata   <= '0;
      evt_waddr   <= '0;
      evt_count_q <= 32'd0;
      evt_ovf_q   <= 1'b0;
    end else if (clear_pulse) begin
      trap_q      <= 1'b0;
      flush_q     <= 1'b0;
      misp_q      <= 1'b0;
      ic_miss_q   <= 1'b0;
      dc_miss_q   <= 1'b0;
      frozen_q    <= 1'b0;
      evt_we      <= 1'b0;
      evt_count_q <= 32'd0;
      evt_waddr   <= '0;
      evt_ovf_q   <= 1'b0;
    end else begin
      trap_q    <= trap_d;
      flush_q   <= flush_d;
      misp_q    <= misp_d;
      ic_miss_q <= ic_miss_d;
      dc_miss_q <= dc_miss_d;
      evt_we  <= 1'b0;
      if (stop_on_excp_i && trap_evt)
        frozen_q <= 1'b1;
      if (evt) begin
        if (evt_count_q >= EVENT_DEPTH)
          evt_ovf_q <= 1'b1;
        else begin
          evt_we      <= 1'b1;
          evt_wdata   <= pack_event();
          evt_waddr   <= evt_count_q[$clog2(EVENT_DEPTH)-1:0];
          evt_count_q <= evt_count_q + 32'd1;
        end
      end
    end
  end

  cva6_trace_ram #(
    .DEPTH (EVENT_DEPTH),
    .WIDTH (EVENT_WORDS * 64)
  ) i_event_ram (
    .wr_clk_i  (clk_i),
    .wr_en_i   (evt_we),
    .wr_addr_i (evt_waddr),
    .wr_data_i (evt_wdata),
    .rd_clk_i  (rd_clk_i),
    .rd_addr_i (rd_idx_i[$clog2(EVENT_DEPTH)-1:0]),
    .rd_data_o (evt_rdata)
  );

  // ---------------------------------------------------------------------------
  // AXI outstanding address table (ID is 4 bits).
  // ---------------------------------------------------------------------------
  logic [63:0] ar_addr_q [0:15];
  logic [63:0] aw_addr_q [0:15];
  logic [2:0]  ar_size_q [0:15];
  logic [2:0]  aw_size_q [0:15];
  logic [3:0]  last_aw_id;
  logic        ar_hs, aw_hs, r_hs, w_hs, b_hs;

  assign ar_hs = ar_valid_i && ar_ready_i;
  assign aw_hs = aw_valid_i && aw_ready_i;
  assign r_hs  = r_valid_i && r_ready_i;
  assign w_hs  = w_valid_i && w_ready_i;
  assign b_hs  = b_valid_i && b_ready_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      last_aw_id <= 4'd0;
      for (int i = 0; i < 16; i++) begin
        ar_addr_q[i] <= 64'd0;
        aw_addr_q[i] <= 64'd0;
        ar_size_q[i] <= 3'd0;
        aw_size_q[i] <= 3'd0;
      end
    end else begin
      if (ar_hs) begin
        ar_addr_q[ar_id_i] <= ar_addr_i;
        ar_size_q[ar_id_i] <= ar_size_i;
      end
      if (aw_hs) begin
        aw_addr_q[aw_id_i] <= aw_addr_i;
        aw_size_q[aw_id_i] <= aw_size_i;
        last_aw_id         <= aw_id_i;
      end
    end
  end

  logic ic_ar, ic_r, dc_ar, dc_r, dc_aw, dc_w, dc_b;
  assign ic_ar = in_window && ar_hs && (ar_id_i[0] == 1'b0);
  assign ic_r  = in_window && r_hs  && (r_id_i[0]  == 1'b0);
  assign dc_ar = in_window && ar_hs && (ar_id_i[0] == 1'b1);
  assign dc_r  = in_window && r_hs  && (r_id_i[0]  == 1'b1);
  assign dc_aw = in_window && aw_hs;
  assign dc_w  = in_window && w_hs;
  assign dc_b  = in_window && b_hs;

  // I$: prefer R, then AR. One record per cycle + 1-entry skid.
  cache_rec_t ic_skid, ic_wdata, ic_sel_rec;
  logic       ic_skid_v, ic_we, ic_any, ic_two;
  logic [$clog2(CACHE_DEPTH)-1:0] ic_waddr;
  logic [31:0] ic_count_q;
  logic        ic_ovf_q;

  cache_rec_t ic_ar_rec, ic_r_rec;
  assign ic_ar_rec = pack_cache(64'd0, ar_addr_i, 64'd0, ar_id_i, 8'd0, ar_size_i, 2'd0,
                                KIND_AR[3:0], 1'b0, 1'b0);
  assign ic_r_rec  = pack_cache(64'd0, ar_addr_q[r_id_i], r_data_i, r_id_i, 8'd0,
                                ar_size_q[r_id_i], r_resp_i, KIND_R[3:0], 1'b0, r_last_i);

  always_comb begin
    ic_any     = ic_r | ic_ar;
    ic_two     = ic_r & ic_ar;
    ic_sel_rec = ic_r ? ic_r_rec : ic_ar_rec;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ic_skid_v  <= 1'b0;
      ic_count_q <= 32'd0;
      ic_waddr   <= '0;
      ic_ovf_q   <= 1'b0;
      ic_we      <= 1'b0;
      ic_wdata   <= '0;
      ic_skid    <= '0;
    end else if (clear_pulse) begin
      ic_skid_v  <= 1'b0;
      ic_count_q <= 32'd0;
      ic_waddr   <= '0;
      ic_ovf_q   <= 1'b0;
      ic_we      <= 1'b0;
    end else begin
      ic_we <= 1'b0;
      if (ic_count_q >= CACHE_DEPTH) begin
        if (ic_any || ic_skid_v)
          ic_ovf_q <= 1'b1;
      end else if (ic_skid_v) begin
        ic_we      <= 1'b1;
        ic_wdata   <= ic_skid;
        ic_waddr   <= ic_count_q[$clog2(CACHE_DEPTH)-1:0];
        ic_count_q <= ic_count_q + 32'd1;
        if (ic_any) begin
          ic_skid <= ic_sel_rec;
          if (ic_two)
            ic_ovf_q <= 1'b1;
        end else begin
          ic_skid_v <= 1'b0;
        end
      end else if (ic_any) begin
        ic_we      <= 1'b1;
        ic_wdata   <= ic_sel_rec;
        ic_waddr   <= ic_count_q[$clog2(CACHE_DEPTH)-1:0];
        ic_count_q <= ic_count_q + 32'd1;
        if (ic_two) begin
          ic_skid_v <= 1'b1;
          ic_skid   <= ic_ar_rec;
        end
      end
    end
  end

  cache_rec_t ic_rdata;
  cva6_trace_ram #(
    .DEPTH (CACHE_DEPTH),
    .WIDTH (CACHE_WORDS * 64)
  ) i_icache_ram (
    .wr_clk_i  (clk_i),
    .wr_en_i   (ic_we),
    .wr_addr_i (ic_waddr),
    .wr_data_i (ic_wdata),
    .rd_clk_i  (rd_clk_i),
    .rd_addr_i (rd_idx_i[$clog2(CACHE_DEPTH)-1:0]),
    .rd_data_o (ic_rdata)
  );

  // D$: priority R, W, B, AR, AW.
  cache_rec_t dc_sel_rec, dc_skid, dc_wdata;
  logic       dc_any, dc_two, dc_skid_v, dc_we;
  logic [$clog2(CACHE_DEPTH)-1:0] dc_waddr;
  logic [31:0] dc_count_q;
  logic        dc_ovf_q;

  cache_rec_t dc_r_rec, dc_w_rec, dc_b_rec, dc_ar_rec, dc_aw_rec;
  assign dc_r_rec  = pack_cache(64'd0, ar_addr_q[r_id_i], r_data_i, r_id_i, 8'd0,
                                ar_size_q[r_id_i], r_resp_i, KIND_R[3:0], 1'b0, r_last_i);
  assign dc_w_rec  = pack_cache(64'd0, aw_addr_q[last_aw_id], w_data_i, last_aw_id, w_strb_i,
                                aw_size_q[last_aw_id], 2'd0, KIND_W[3:0], 1'b1, w_last_i);
  assign dc_b_rec  = pack_cache(64'd0, aw_addr_q[b_id_i], 64'd0, b_id_i, 8'd0,
                                aw_size_q[b_id_i], b_resp_i, KIND_B[3:0], 1'b1, 1'b1);
  assign dc_ar_rec = pack_cache(64'd0, ar_addr_i, 64'd0, ar_id_i, 8'd0, ar_size_i, 2'd0,
                                KIND_AR[3:0], 1'b0, 1'b0);
  assign dc_aw_rec = pack_cache(64'd0, aw_addr_i, 64'd0, aw_id_i, 8'd0, aw_size_i, 2'd0,
                                KIND_AW[3:0], 1'b1, 1'b0);

  logic [2:0]  dc_evt_n;

  always_comb begin
    dc_any     = dc_r | dc_w | dc_b | dc_ar | dc_aw;
    dc_sel_rec = '0;
    dc_evt_n   = 3'(dc_r) + 3'(dc_w) + 3'(dc_b) + 3'(dc_ar) + 3'(dc_aw);
    dc_two     = dc_evt_n > 3'd1;
    if (dc_r)
      dc_sel_rec = dc_r_rec;
    else if (dc_w)
      dc_sel_rec = dc_w_rec;
    else if (dc_b)
      dc_sel_rec = dc_b_rec;
    else if (dc_ar)
      dc_sel_rec = dc_ar_rec;
    else if (dc_aw)
      dc_sel_rec = dc_aw_rec;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dc_skid_v  <= 1'b0;
      dc_count_q <= 32'd0;
      dc_waddr   <= '0;
      dc_ovf_q   <= 1'b0;
      dc_we      <= 1'b0;
      dc_wdata   <= '0;
      dc_skid    <= '0;
    end else if (clear_pulse) begin
      dc_skid_v  <= 1'b0;
      dc_count_q <= 32'd0;
      dc_waddr   <= '0;
      dc_ovf_q   <= 1'b0;
      dc_we      <= 1'b0;
    end else begin
      dc_we <= 1'b0;
      if (dc_count_q >= CACHE_DEPTH) begin
        if (dc_any || dc_skid_v)
          dc_ovf_q <= 1'b1;
      end else if (dc_skid_v) begin
        dc_we      <= 1'b1;
        dc_wdata   <= dc_skid;
        dc_waddr   <= dc_count_q[$clog2(CACHE_DEPTH)-1:0];
        dc_count_q <= dc_count_q + 32'd1;
        if (dc_any) begin
          dc_skid <= dc_sel_rec;
          if (dc_two)
            dc_ovf_q <= 1'b1;
        end else begin
          dc_skid_v <= 1'b0;
        end
      end else if (dc_any) begin
        dc_we      <= 1'b1;
        dc_wdata   <= dc_sel_rec;
        dc_waddr   <= dc_count_q[$clog2(CACHE_DEPTH)-1:0];
        dc_count_q <= dc_count_q + 32'd1;
        if (dc_two)
          dc_ovf_q <= 1'b1;
      end
    end
  end

  cache_rec_t dc_rdata;
  cva6_trace_ram #(
    .DEPTH (CACHE_DEPTH),
    .WIDTH (CACHE_WORDS * 64)
  ) i_dcache_ram (
    .wr_clk_i  (clk_i),
    .wr_en_i   (dc_we),
    .wr_addr_i (dc_waddr),
    .wr_data_i (dc_wdata),
    .rd_clk_i  (rd_clk_i),
    .rd_addr_i (rd_idx_i[$clog2(CACHE_DEPTH)-1:0]),
    .rd_data_o (dc_rdata)
  );

  // ---------------------------------------------------------------------------
  // L1 hit/miss lookups (separate from DRAM AXI). Windowed records + always-on
  // counters. I$ tag hit vs miss_o; D$ load/PTW tag hit vs miss_o.
  // ---------------------------------------------------------------------------
  function automatic l1_rec_t pack_l1(input logic is_d, input logic is_hit);
    logic [63:0] w [0:L1_WORDS-1];
    logic [63:0] flags;
    l1_rec_t rec;
    flags = 64'd0;
    flags[0] = is_hit;
    flags[1] = ~is_hit;
    flags[2] = is_d;
    w[0] = cycle_q;
    if (is_d) begin
      w[1] = {{64-CVA6Cfg.VLEN{1'b0}}, rvfi_probes_i.instr.lsu_ctrl_vaddr};
      w[2] = {{64-CVA6Cfg.PLEN{1'b0}}, rvfi_probes_i.instr.mem_paddr};
    end else begin
      w[1] = {{64-CVA6Cfg.VLEN{1'b0}}, rvfi_probes_i.instr.icache_vaddr};
      w[2] = {{64-CVA6Cfg.PLEN{1'b0}}, rvfi_probes_i.instr.icache_paddr};
    end
    w[3] = flags;
    rec = '0;
    for (int i = 0; i < L1_WORDS; i++)
      rec[i*64 +: 64] = w[i];
    return rec;
  endfunction

  logic ic_hit, ic_miss, dc_hit, dc_miss;
  logic l1_i, l1_d, l1_any, l1_two;
  assign ic_hit  = rvfi_probes_i.instr.icache_hit;
  assign ic_miss = rvfi_probes_i.instr.icache_miss;
  assign dc_hit  = rvfi_probes_i.instr.dcache_hit;
  assign dc_miss = rvfi_probes_i.instr.dcache_miss;
  assign l1_i    = in_window && (ic_hit || ic_miss);
  assign l1_d    = in_window && (dc_hit || dc_miss);
  assign l1_any  = l1_i || l1_d;
  assign l1_two  = l1_i && l1_d;

  l1_rec_t l1_i_rec, l1_d_rec, l1_sel, l1_skid, l1_wdata, l1_rdata;
  assign l1_i_rec = pack_l1(1'b0, ic_hit);
  assign l1_d_rec = pack_l1(1'b1, dc_hit);
  assign l1_sel   = l1_i ? l1_i_rec : l1_d_rec;

  logic l1_skid_v, l1_we, l1_ovf_q;
  logic [$clog2(L1_DEPTH)-1:0] l1_waddr;
  logic [31:0] l1_count_q;
  logic [31:0] ic_hit_q, ic_miss_qcnt, dc_hit_q, dc_miss_qcnt;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      l1_skid_v    <= 1'b0;
      l1_we        <= 1'b0;
      l1_wdata     <= '0;
      l1_skid      <= '0;
      l1_waddr     <= '0;
      l1_count_q   <= 32'd0;
      l1_ovf_q     <= 1'b0;
      ic_hit_q     <= 32'd0;
      ic_miss_qcnt <= 32'd0;
      dc_hit_q     <= 32'd0;
      dc_miss_qcnt <= 32'd0;
    end else if (clear_pulse) begin
      l1_skid_v    <= 1'b0;
      l1_we        <= 1'b0;
      l1_count_q   <= 32'd0;
      l1_waddr     <= '0;
      l1_ovf_q     <= 1'b0;
      ic_hit_q     <= 32'd0;
      ic_miss_qcnt <= 32'd0;
      dc_hit_q     <= 32'd0;
      dc_miss_qcnt <= 32'd0;
    end else begin
      l1_we <= 1'b0;
      if (enable_q && cpu_run_i) begin
        if (ic_hit)  ic_hit_q     <= ic_hit_q + 32'd1;
        if (ic_miss) ic_miss_qcnt <= ic_miss_qcnt + 32'd1;
        if (dc_hit)  dc_hit_q     <= dc_hit_q + 32'd1;
        if (dc_miss) dc_miss_qcnt <= dc_miss_qcnt + 32'd1;
      end
      if (l1_count_q >= L1_DEPTH) begin
        if (l1_any || l1_skid_v)
          l1_ovf_q <= 1'b1;
      end else if (l1_skid_v) begin
        l1_we      <= 1'b1;
        l1_wdata   <= l1_skid;
        l1_waddr   <= l1_count_q[$clog2(L1_DEPTH)-1:0];
        l1_count_q <= l1_count_q + 32'd1;
        if (l1_any) begin
          l1_skid <= l1_sel;
          if (l1_two)
            l1_ovf_q <= 1'b1;
        end else begin
          l1_skid_v <= 1'b0;
        end
      end else if (l1_any) begin
        l1_we      <= 1'b1;
        l1_wdata   <= l1_sel;
        l1_waddr   <= l1_count_q[$clog2(L1_DEPTH)-1:0];
        l1_count_q <= l1_count_q + 32'd1;
        if (l1_two) begin
          l1_skid_v <= 1'b1;
          l1_skid   <= l1_d_rec;
        end
      end
    end
  end

  cva6_trace_ram #(
    .DEPTH (L1_DEPTH),
    .WIDTH (L1_WORDS * 64)
  ) i_l1_ram (
    .wr_clk_i  (clk_i),
    .wr_en_i   (l1_we),
    .wr_addr_i (l1_waddr),
    .wr_data_i (l1_wdata),
    .rd_clk_i  (rd_clk_i),
    .rd_addr_i (rd_idx_i[$clog2(L1_DEPTH)-1:0]),
    .rd_data_o (l1_rdata)
  );

  assign instr_count_o  = instr_count_q;
  assign icache_count_o = ic_count_q;
  assign dcache_count_o = dc_count_q;
  assign event_count_o  = evt_count_q;
  assign l1_count_o     = l1_count_q;
  assign ic_hit_count_o = ic_hit_q;
  assign ic_miss_count_o = ic_miss_qcnt;
  assign dc_hit_count_o = dc_hit_q;
  assign dc_miss_count_o = dc_miss_qcnt;
  assign status_o = {22'd0, frozen_q, window_done, 2'd0, l1_ovf_q, evt_ovf_q,
                     dc_ovf_q, ic_ovf_q, instr_ovf_q, in_window};

  logic [63:0] instr_word, ic_word, dc_word, evt_word, l1_word;
  assign instr_word = instr_rdata[{rd_word_i, 6'd0} +: 64];
  assign ic_word    = ic_rdata[{rd_word_i[2:0], 6'd0} +: 64];
  assign dc_word    = dc_rdata[{rd_word_i[2:0], 6'd0} +: 64];
  assign evt_word   = evt_rdata[{rd_word_i, 6'd0} +: 64];
  assign l1_word    = l1_rdata[{rd_word_i[1:0], 6'd0} +: 64];

  always_comb begin
    unique case (rd_sel_i)
      3'd0: rd_data_o = instr_word;
      3'd1: rd_data_o = ic_word;
      3'd2: rd_data_o = dc_word;
      3'd3: rd_data_o = evt_word;
      3'd4: rd_data_o = l1_word;
      default: rd_data_o = 64'd0;
    endcase
  end

endmodule
