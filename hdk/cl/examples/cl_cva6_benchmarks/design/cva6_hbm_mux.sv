// Static, transaction-safe ownership mux for the single HBM AXI4 port.
// PCIS owns HBM while cpu_run_i is low. Ownership changes only with no
// accepted transactions, so responses can never be routed to the wrong master.
module cva6_hbm_mux (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       cpu_run_i,
  output logic       cpu_grant_o,
  axi_bus_t.master   pcis_axi,
  axi_bus_t.master   cpu_axi,
  axi_bus_t.slave    hbm_axi
);

  localparam logic [63:0] CPU_DRAM_BASE = 64'h0000_0000_8000_0000;
  localparam logic [63:0] PCIS_HBM_BASE = 64'h0000_0010_0000_0000;

  logic select_cpu_q;
  logic [8:0] writes_outstanding_q;
  logic [8:0] reads_outstanding_q;
  logic aw_fire, b_fire, ar_fire, rlast_fire;
  logic selected_awvalid, selected_wvalid, selected_arvalid;

  assign cpu_grant_o = select_cpu_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      select_cpu_q          <= 1'b0;
      writes_outstanding_q  <= '0;
      reads_outstanding_q   <= '0;
    end else begin
      if ((writes_outstanding_q == 0) && (reads_outstanding_q == 0) &&
          !selected_awvalid && !selected_wvalid && !selected_arvalid)
        select_cpu_q <= cpu_run_i;

      unique case ({aw_fire, b_fire})
        2'b10: writes_outstanding_q <= writes_outstanding_q + 1'b1;
        2'b01: writes_outstanding_q <= writes_outstanding_q - 1'b1;
        default: ;
      endcase
      unique case ({ar_fire, rlast_fire})
        2'b10: reads_outstanding_q <= reads_outstanding_q + 1'b1;
        2'b01: reads_outstanding_q <= reads_outstanding_q - 1'b1;
        default: ;
      endcase
    end
  end

  always_comb begin
    // HBM request defaults.
    hbm_axi.awid    = '0;
    hbm_axi.awaddr  = '0;
    hbm_axi.awlen   = '0;
    hbm_axi.awsize  = '0;
    hbm_axi.awburst = '0;
    hbm_axi.awvalid = 1'b0;
    hbm_axi.wid     = '0;
    hbm_axi.wdata   = '0;
    hbm_axi.wstrb   = '0;
    hbm_axi.wlast   = 1'b0;
    hbm_axi.wvalid  = 1'b0;
    hbm_axi.bready  = 1'b0;
    hbm_axi.arid    = '0;
    hbm_axi.araddr  = '0;
    hbm_axi.arlen   = '0;
    hbm_axi.arsize  = '0;
    hbm_axi.arburst = '0;
    hbm_axi.arvalid = 1'b0;
    hbm_axi.rready  = 1'b0;

    // Inactive masters are backpressured. In particular, PCIS is rejected
    // while the CPU owns HBM rather than silently accepting dropped traffic.
    pcis_axi.awready = 1'b0;
    pcis_axi.wready  = 1'b0;
    pcis_axi.bid     = '0;
    pcis_axi.bresp   = 2'b00;
    pcis_axi.bvalid  = 1'b0;
    pcis_axi.arready = 1'b0;
    pcis_axi.rid     = '0;
    pcis_axi.rdata   = '0;
    pcis_axi.rresp   = 2'b00;
    pcis_axi.rlast   = 1'b0;
    pcis_axi.rvalid  = 1'b0;

    cpu_axi.awready = 1'b0;
    cpu_axi.wready  = 1'b0;
    cpu_axi.bid     = '0;
    cpu_axi.bresp   = 2'b00;
    cpu_axi.bvalid  = 1'b0;
    cpu_axi.arready = 1'b0;
    cpu_axi.rid     = '0;
    cpu_axi.rdata   = '0;
    cpu_axi.rresp   = 2'b00;
    cpu_axi.rlast   = 1'b0;
    cpu_axi.rvalid  = 1'b0;

    if (select_cpu_q) begin
      hbm_axi.awid    = cpu_axi.awid;
      hbm_axi.awaddr  = cpu_axi.awaddr - CPU_DRAM_BASE;
      hbm_axi.awlen   = cpu_axi.awlen;
      hbm_axi.awsize  = cpu_axi.awsize;
      hbm_axi.awburst = cpu_axi.awburst;
      hbm_axi.awvalid = cpu_axi.awvalid;
      cpu_axi.awready = hbm_axi.awready;

      hbm_axi.wid     = cpu_axi.wid;
      hbm_axi.wdata   = cpu_axi.wdata;
      hbm_axi.wstrb   = cpu_axi.wstrb;
      hbm_axi.wlast   = cpu_axi.wlast;
      hbm_axi.wvalid  = cpu_axi.wvalid && (writes_outstanding_q != 0);
      cpu_axi.wready  = hbm_axi.wready && (writes_outstanding_q != 0);

      cpu_axi.bid     = hbm_axi.bid;
      cpu_axi.bresp   = hbm_axi.bresp;
      cpu_axi.bvalid  = hbm_axi.bvalid;
      hbm_axi.bready  = cpu_axi.bready;

      hbm_axi.arid    = cpu_axi.arid;
      hbm_axi.araddr  = cpu_axi.araddr - CPU_DRAM_BASE;
      hbm_axi.arlen   = cpu_axi.arlen;
      hbm_axi.arsize  = cpu_axi.arsize;
      hbm_axi.arburst = cpu_axi.arburst;
      hbm_axi.arvalid = cpu_axi.arvalid;
      cpu_axi.arready = hbm_axi.arready;

      cpu_axi.rid     = hbm_axi.rid;
      cpu_axi.rdata   = hbm_axi.rdata;
      cpu_axi.rresp   = hbm_axi.rresp;
      cpu_axi.rlast   = hbm_axi.rlast;
      cpu_axi.rvalid  = hbm_axi.rvalid;
      hbm_axi.rready  = cpu_axi.rready;
    end else begin
      // Preserve all 16 shell ID bits through the reference AXI4 SmartConnect.
      hbm_axi.awid    = pcis_axi.awid;
      hbm_axi.awaddr  = pcis_axi.awaddr - PCIS_HBM_BASE;
      hbm_axi.awlen   = pcis_axi.awlen;
      hbm_axi.awsize  = pcis_axi.awsize;
      hbm_axi.awburst = pcis_axi.awburst;
      hbm_axi.awvalid = pcis_axi.awvalid;
      pcis_axi.awready = hbm_axi.awready;

      hbm_axi.wid     = pcis_axi.wid;
      hbm_axi.wdata   = pcis_axi.wdata;
      hbm_axi.wstrb   = pcis_axi.wstrb;
      hbm_axi.wlast   = pcis_axi.wlast;
      hbm_axi.wvalid  = pcis_axi.wvalid && (writes_outstanding_q != 0);
      pcis_axi.wready = hbm_axi.wready && (writes_outstanding_q != 0);

      pcis_axi.bid    = hbm_axi.bid;
      pcis_axi.bresp  = hbm_axi.bresp;
      pcis_axi.bvalid = hbm_axi.bvalid;
      hbm_axi.bready  = pcis_axi.bready;

      hbm_axi.arid    = pcis_axi.arid;
      hbm_axi.araddr  = pcis_axi.araddr - PCIS_HBM_BASE;
      hbm_axi.arlen   = pcis_axi.arlen;
      hbm_axi.arsize  = pcis_axi.arsize;
      hbm_axi.arburst = pcis_axi.arburst;
      hbm_axi.arvalid = pcis_axi.arvalid;
      pcis_axi.arready = hbm_axi.arready;

      pcis_axi.rid    = hbm_axi.rid;
      pcis_axi.rdata  = hbm_axi.rdata;
      pcis_axi.rresp  = hbm_axi.rresp;
      pcis_axi.rlast  = hbm_axi.rlast;
      pcis_axi.rvalid = hbm_axi.rvalid;
      hbm_axi.rready  = pcis_axi.rready;
    end
  end

  assign selected_awvalid = select_cpu_q ? cpu_axi.awvalid : pcis_axi.awvalid;
  assign selected_wvalid  = select_cpu_q ? cpu_axi.wvalid  : pcis_axi.wvalid;
  assign selected_arvalid = select_cpu_q ? cpu_axi.arvalid : pcis_axi.arvalid;
  assign aw_fire    = hbm_axi.awvalid && hbm_axi.awready;
  assign b_fire     = hbm_axi.bvalid  && hbm_axi.bready;
  assign ar_fire    = hbm_axi.arvalid && hbm_axi.arready;
  assign rlast_fire = hbm_axi.rvalid  && hbm_axi.rready && hbm_axi.rlast;

endmodule
