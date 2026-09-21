// Minimal CVA6 SoC for AWS F2: core + external DRAM AXI @ 0x8000_0000,
// UART, CLINT, and PLIC.

`include "axi/assign.svh"
`include "rvfi_types.svh"

module cva6_f2_soc
  import ariane_soc::*;
#(
    parameter longint unsigned DramBytes = 64'h4000_0000 // 1 GiB
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        cpu_run_i,

  // CVA6 DRAM master, 64-bit AXI4 in the clk_i domain.
  AXI_BUS.Master      dram_axi,

  output logic        uart_tx_valid_o,
  output logic [7:0]  uart_tx_data_o,
  input  logic        uart_tx_ready_i,

  input  logic         trace_rd_clk_i,
  input  logic         trace_enable_i,
  input  logic [63:0]  trace_start_i,
  input  logic [63:0]  trace_end_i,
  input  logic         trace_clear_i,
  input  logic         trace_stop_on_excp_i,
  input  logic [2:0]   trace_sel_i,
  input  logic [15:0]  trace_idx_i,
  input  logic [3:0]   trace_word_i,
  output logic [63:0]  trace_rdata_o,
  output logic [63:0]  trace_cycle_o,
  output logic [31:0]  trace_instr_count_o,
  output logic [31:0]  trace_icache_count_o,
  output logic [31:0]  trace_dcache_count_o,
  output logic [31:0]  trace_event_count_o,
  output logic [31:0]  trace_l1_count_o,
  output logic [31:0]  trace_ic_hit_count_o,
  output logic [31:0]  trace_ic_miss_count_o,
  output logic [31:0]  trace_dc_hit_count_o,
  output logic [31:0]  trace_dc_miss_count_o,
  output logic [31:0]  trace_status_o
);

  function automatic config_pkg::cva6_cfg_t build_fpga_config(config_pkg::cva6_user_cfg_t CVA6UserCfg);
    config_pkg::cva6_user_cfg_t cfg = CVA6UserCfg;
    // Stock cv64a6_imafdc_sv39 is an ASIC/sim config (FpgaEn=0). Force FPGA
    // SRAM wrappers so Vivado infers BRAM instead of ASIC memory models.
    cfg.FpgaEn = bit'(1);
    cfg.CvxifEn = bit'(0);
    cfg.RVZiCond = bit'(0);
    cfg.NrCachedRegionRules = unsigned'(1);
    cfg.CachedRegionAddrBase = 1024'({ariane_soc::DRAMBase});
    cfg.CachedRegionLength = 1024'({64'(DramBytes)});
    cfg.ExecuteRegionLength =
        1024'({64'(DramBytes), 64'h1_0000, 64'h1000});
    cfg.NrNonIdempotentRules = unsigned'(1);
    cfg.NonIdempotentAddrBase = 1024'({64'b0});
    cfg.NonIdempotentLength = 1024'({ariane_soc::DRAMBase});
    return build_config_pkg::build_config(cfg);
  endfunction

  localparam config_pkg::cva6_cfg_t CVA6Cfg = build_fpga_config(cva6_config_pkg::cva6_cfg);

  localparam type rvfi_probes_instr_t = `RVFI_PROBES_INSTR_T(CVA6Cfg);
  localparam type rvfi_probes_csr_t = `RVFI_PROBES_CSR_T(CVA6Cfg);
  localparam type rvfi_probes_t = struct packed {
    rvfi_probes_csr_t csr;
    rvfi_probes_instr_t instr;
  };

  localparam int unsigned NBSlave        = 1;
  localparam int unsigned NBMaster       = 4;
  localparam int unsigned DRAM_IDX       = 0;
  localparam int unsigned UART_IDX       = 1;
  localparam int unsigned CLINT_IDX      = 2;
  localparam int unsigned PLIC_IDX       = 3;
  localparam int unsigned AxiAddrWidth   = 64;
  localparam int unsigned AxiDataWidth   = 64;
  localparam int unsigned AxiIdWidthM    = 4;
  localparam int unsigned AxiIdWidthS    = AxiIdWidthM;  // single slave port
  localparam int unsigned AxiUserWidth   = CVA6Cfg.AxiUserWidth;

  rvfi_probes_t rvfi_probes;

  logic rst_core_n;
  assign rst_core_n = rst_ni & cpu_run_i;

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth ),
    .AXI_DATA_WIDTH ( AxiDataWidth ),
    .AXI_ID_WIDTH   ( AxiIdWidthM  ),
    .AXI_USER_WIDTH ( AxiUserWidth )
  ) slave[NBSlave-1:0]();

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth ),
    .AXI_DATA_WIDTH ( AxiDataWidth ),
    .AXI_ID_WIDTH   ( AxiIdWidthS  ),
    .AXI_USER_WIDTH ( AxiUserWidth )
  ) master[NBMaster-1:0]();

  axi_pkg::xbar_rule_64_t [NBMaster-1:0] addr_map;
  assign addr_map = '{
    '{ idx: DRAM_IDX, start_addr: ariane_soc::DRAMBase, end_addr: ariane_soc::DRAMBase + DramBytes },
    '{ idx: UART_IDX, start_addr: ariane_soc::UARTBase, end_addr: ariane_soc::UARTBase + ariane_soc::UARTLength },
    '{ idx: CLINT_IDX, start_addr: ariane_soc::CLINTBase, end_addr: ariane_soc::CLINTBase + ariane_soc::CLINTLength },
    '{ idx: PLIC_IDX, start_addr: ariane_soc::PLICBase, end_addr: ariane_soc::PLICBase + ariane_soc::PLICLength }
  };

  localparam axi_pkg::xbar_cfg_t AXI_XBAR_CFG = '{
    NoSlvPorts:         unsigned'(NBSlave),
    NoMstPorts:         unsigned'(NBMaster),
    MaxMstTrans:        unsigned'(1),
    MaxSlvTrans:        unsigned'(1),
    FallThrough:        1'b0,
    LatencyMode:        axi_pkg::CUT_ALL_PORTS,
    AxiIdWidthSlvPorts: unsigned'(AxiIdWidthM),
    AxiIdUsedSlvPorts:  unsigned'(AxiIdWidthM),
    UniqueIds:          1'b0,
    AxiAddrWidth:       unsigned'(AxiAddrWidth),
    AxiDataWidth:       unsigned'(AxiDataWidth),
    NoAddrRules:        unsigned'(NBMaster)
  };

  axi_xbar_intf #(
    .AXI_USER_WIDTH ( AxiUserWidth            ),
    .Cfg            ( AXI_XBAR_CFG            ),
    .rule_t         ( axi_pkg::xbar_rule_64_t )
  ) i_axi_xbar (
    .clk_i                 ( clk_i      ),
    .rst_ni                ( rst_ni     ),
    .test_i                ( 1'b0       ),
    .slv_ports             ( slave      ),
    .mst_ports             ( master     ),
    .addr_map_i            ( addr_map   ),
    .en_default_mst_port_i ( '0         ),
    .default_mst_port_i    ( '0         )
  );

  ariane_axi::req_t  axi_ariane_req;
  ariane_axi::resp_t axi_ariane_resp;
  logic              timer_irq;
  logic              software_irq;
  logic [1:0]        external_irq;

  ariane #(
    .CVA6Cfg             ( CVA6Cfg             ),
    .rvfi_probes_instr_t ( rvfi_probes_instr_t ),
    .rvfi_probes_csr_t   ( rvfi_probes_csr_t   ),
    .rvfi_probes_t       ( rvfi_probes_t       ),
    .noc_req_t           ( ariane_axi::req_t   ),
    .noc_resp_t          ( ariane_axi::resp_t  )
  ) i_ariane (
    .clk_i         ( clk_i            ),
    .rst_ni        ( rst_core_n       ),
    .boot_addr_i   ( ariane_soc::DRAMBase ),
    .hart_id_i     ( '0               ),
    .irq_i         ( external_irq     ),
    .ipi_i         ( software_irq     ),
    .time_irq_i    ( timer_irq        ),
    .debug_req_i   ( 1'b0             ),
    .rvfi_probes_o ( rvfi_probes      ),
    .noc_req_o     ( axi_ariane_req   ),
    .noc_resp_i    ( axi_ariane_resp  )
  );

  `AXI_ASSIGN_FROM_REQ(slave[0], axi_ariane_req)
  `AXI_ASSIGN_TO_RESP(axi_ariane_resp, slave[0])

  // ---------------
  // CLINT
  // ---------------
  // The reference CVA6 FPGA platform toggles rtc every CPU cycle.  CLINT
  // increments mtime on rtc rising edges, so Linux timebase-frequency is
  // clk_cpu / 2 (31.25 MHz for the default 62.5 MHz CPU clock).
  logic rtc;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      rtc <= 1'b0;
    else
      rtc <= ~rtc;
  end

  ariane_axi::req_t  axi_clint_req;
  ariane_axi::resp_t axi_clint_resp;

  clint #(
    .CVA6Cfg        ( CVA6Cfg             ),
    .AXI_ADDR_WIDTH ( AxiAddrWidth        ),
    .AXI_DATA_WIDTH ( AxiDataWidth        ),
    .AXI_ID_WIDTH   ( AxiIdWidthS         ),
    .NR_CORES       ( 1                   ),
    .axi_req_t      ( ariane_axi::req_t   ),
    .axi_resp_t     ( ariane_axi::resp_t  )
  ) i_clint (
    .clk_i       ( clk_i          ),
    .rst_ni      ( rst_ni         ),
    .testmode_i  ( 1'b0           ),
    .axi_req_i   ( axi_clint_req  ),
    .axi_resp_o  ( axi_clint_resp ),
    .rtc_i       ( rtc            ),
    .timer_irq_o ( timer_irq      ),
    .ipi_o       ( software_irq   )
  );

  `AXI_ASSIGN_TO_REQ(axi_clint_req, master[CLINT_IDX])
  `AXI_ASSIGN_FROM_RESP(master[CLINT_IDX], axi_clint_resp)

  logic uart_irq;
  cva6_plic #(
    .AxiAddrWidth ( AxiAddrWidth ),
    .AxiDataWidth ( AxiDataWidth ),
    .AxiIdWidth   ( AxiIdWidthS  ),
    .AxiUserWidth ( AxiUserWidth )
  ) i_plic (
    .clk_i      ( clk_i            ),
    .rst_ni     ( rst_ni           ),
    .uart_irq_i ( uart_irq         ),
    .irq_o      ( external_irq     ),
    .axi        ( master[PLIC_IDX] )
  );

  // Export the complete DRAM AXI channel. Address translation to HBM offset
  // zero and clock/data-width conversion are performed in the CL wrapper.
  `AXI_ASSIGN(dram_axi, master[DRAM_IDX])

  // ---------------
  // UART
  // ---------------
  logic        uart_penable, uart_pwrite, uart_psel, uart_pready, uart_pslverr;
  logic [31:0] uart_paddr, uart_pwdata, uart_prdata;

  axi2apb_64_32 #(
    .AXI4_ADDRESS_WIDTH ( AxiAddrWidth ),
    .AXI4_RDATA_WIDTH   ( AxiDataWidth ),
    .AXI4_WDATA_WIDTH   ( AxiDataWidth ),
    .AXI4_ID_WIDTH      ( AxiIdWidthS  ),
    .AXI4_USER_WIDTH    ( AxiUserWidth ),
    .BUFF_DEPTH_SLAVE   ( 2            ),
    .APB_ADDR_WIDTH     ( 32           )
  ) i_axi2apb_uart (
    .ACLK       ( clk_i                 ),
    .ARESETn    ( rst_ni                ),
    .test_en_i  ( 1'b0                  ),
    .AWID_i     ( master[UART_IDX].aw_id     ),
    .AWADDR_i   ( master[UART_IDX].aw_addr   ),
    .AWLEN_i    ( master[UART_IDX].aw_len    ),
    .AWSIZE_i   ( master[UART_IDX].aw_size   ),
    .AWBURST_i  ( master[UART_IDX].aw_burst  ),
    .AWLOCK_i   ( master[UART_IDX].aw_lock   ),
    .AWCACHE_i  ( master[UART_IDX].aw_cache  ),
    .AWPROT_i   ( master[UART_IDX].aw_prot   ),
    .AWREGION_i ( master[UART_IDX].aw_region ),
    .AWUSER_i   ( master[UART_IDX].aw_user   ),
    .AWQOS_i    ( master[UART_IDX].aw_qos    ),
    .AWVALID_i  ( master[UART_IDX].aw_valid  ),
    .AWREADY_o  ( master[UART_IDX].aw_ready  ),
    .WDATA_i    ( master[UART_IDX].w_data    ),
    .WSTRB_i    ( master[UART_IDX].w_strb    ),
    .WLAST_i    ( master[UART_IDX].w_last    ),
    .WUSER_i    ( master[UART_IDX].w_user    ),
    .WVALID_i   ( master[UART_IDX].w_valid   ),
    .WREADY_o   ( master[UART_IDX].w_ready   ),
    .BID_o      ( master[UART_IDX].b_id      ),
    .BRESP_o    ( master[UART_IDX].b_resp    ),
    .BVALID_o   ( master[UART_IDX].b_valid   ),
    .BUSER_o    ( master[UART_IDX].b_user    ),
    .BREADY_i   ( master[UART_IDX].b_ready   ),
    .ARID_i     ( master[UART_IDX].ar_id     ),
    .ARADDR_i   ( master[UART_IDX].ar_addr   ),
    .ARLEN_i    ( master[UART_IDX].ar_len    ),
    .ARSIZE_i   ( master[UART_IDX].ar_size   ),
    .ARBURST_i  ( master[UART_IDX].ar_burst  ),
    .ARLOCK_i   ( master[UART_IDX].ar_lock   ),
    .ARCACHE_i  ( master[UART_IDX].ar_cache  ),
    .ARPROT_i   ( master[UART_IDX].ar_prot   ),
    .ARREGION_i ( master[UART_IDX].ar_region ),
    .ARUSER_i   ( master[UART_IDX].ar_user   ),
    .ARQOS_i    ( master[UART_IDX].ar_qos    ),
    .ARVALID_i  ( master[UART_IDX].ar_valid  ),
    .ARREADY_o  ( master[UART_IDX].ar_ready  ),
    .RID_o      ( master[UART_IDX].r_id      ),
    .RDATA_o    ( master[UART_IDX].r_data    ),
    .RRESP_o    ( master[UART_IDX].r_resp    ),
    .RLAST_o    ( master[UART_IDX].r_last    ),
    .RUSER_o    ( master[UART_IDX].r_user    ),
    .RVALID_o   ( master[UART_IDX].r_valid   ),
    .RREADY_i   ( master[UART_IDX].r_ready   ),
    .PENABLE    ( uart_penable          ),
    .PWRITE     ( uart_pwrite           ),
    .PADDR      ( uart_paddr            ),
    .PSEL       ( uart_psel             ),
    .PWDATA     ( uart_pwdata           ),
    .PRDATA     ( uart_prdata           ),
    .PREADY     ( uart_pready           ),
    .PSLVERR    ( uart_pslverr          )
  );

  host_uart i_host_uart (
    .clk_i       ( clk_i            ),
    .rst_ni      ( rst_ni           ),
    .penable_i   ( uart_penable     ),
    .pwrite_i    ( uart_pwrite      ),
    .paddr_i     ( uart_paddr       ),
    .psel_i      ( uart_psel        ),
    .pwdata_i    ( uart_pwdata      ),
    .prdata_o    ( uart_prdata      ),
    .pready_o    ( uart_pready      ),
    .pslverr_o   ( uart_pslverr     ),
    .irq_o       ( uart_irq         ),
    .tx_valid_o  ( uart_tx_valid_o  ),
    .tx_data_o   ( uart_tx_data_o   ),
    .tx_ready_i  ( uart_tx_ready_i  )
  );

  cva6_trace_capture #(
    .CVA6Cfg       ( CVA6Cfg       ),
    .rvfi_probes_t ( rvfi_probes_t )
  ) i_trace_capture (
    .clk_i            ( clk_i            ),
    .rst_ni           ( rst_ni           ),
    .cpu_run_i        ( cpu_run_i        ),
    .rvfi_probes_i    ( rvfi_probes      ),
    .ar_valid_i       ( master[DRAM_IDX].ar_valid ),
    .ar_ready_i       ( master[DRAM_IDX].ar_ready ),
    .ar_id_i          ( master[DRAM_IDX].ar_id[3:0] ),
    .ar_addr_i        ( master[DRAM_IDX].ar_addr ),
    .ar_size_i        ( master[DRAM_IDX].ar_size ),
    .r_valid_i        ( master[DRAM_IDX].r_valid  ),
    .r_ready_i        ( master[DRAM_IDX].r_ready  ),
    .r_id_i           ( master[DRAM_IDX].r_id[3:0] ),
    .r_data_i         ( master[DRAM_IDX].r_data   ),
    .r_resp_i         ( master[DRAM_IDX].r_resp   ),
    .r_last_i         ( master[DRAM_IDX].r_last   ),
    .aw_valid_i       ( master[DRAM_IDX].aw_valid ),
    .aw_ready_i       ( master[DRAM_IDX].aw_ready ),
    .aw_id_i          ( master[DRAM_IDX].aw_id[3:0] ),
    .aw_addr_i        ( master[DRAM_IDX].aw_addr ),
    .aw_size_i        ( master[DRAM_IDX].aw_size ),
    .w_valid_i        ( master[DRAM_IDX].w_valid  ),
    .w_ready_i        ( master[DRAM_IDX].w_ready  ),
    .w_data_i         ( master[DRAM_IDX].w_data   ),
    .w_strb_i         ( master[DRAM_IDX].w_strb   ),
    .w_last_i         ( master[DRAM_IDX].w_last   ),
    .b_valid_i        ( master[DRAM_IDX].b_valid  ),
    .b_ready_i        ( master[DRAM_IDX].b_ready  ),
    .b_id_i           ( master[DRAM_IDX].b_id[3:0] ),
    .b_resp_i         ( master[DRAM_IDX].b_resp   ),
    .enable_i         ( trace_enable_i   ),
    .start_i          ( trace_start_i    ),
    .end_i            ( trace_end_i      ),
    .clear_i          ( trace_clear_i    ),
    .stop_on_excp_i   ( trace_stop_on_excp_i ),
    .cycle_o          ( trace_cycle_o    ),
    .instr_count_o    ( trace_instr_count_o  ),
    .icache_count_o   ( trace_icache_count_o ),
    .dcache_count_o   ( trace_dcache_count_o ),
    .event_count_o    ( trace_event_count_o  ),
    .l1_count_o       ( trace_l1_count_o     ),
    .ic_hit_count_o   ( trace_ic_hit_count_o ),
    .ic_miss_count_o  ( trace_ic_miss_count_o ),
    .dc_hit_count_o   ( trace_dc_hit_count_o ),
    .dc_miss_count_o  ( trace_dc_miss_count_o ),
    .status_o         ( trace_status_o   ),
    .rd_clk_i         ( trace_rd_clk_i   ),
    .rd_sel_i         ( trace_sel_i      ),
    .rd_idx_i         ( trace_idx_i      ),
    .rd_word_i        ( trace_word_i     ),
    .rd_data_o        ( trace_rdata_o    )
  );

endmodule
