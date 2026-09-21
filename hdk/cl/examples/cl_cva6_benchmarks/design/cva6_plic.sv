`include "register_interface/assign.svh"
`include "register_interface/typedef.svh"

// Minimal single-hart PLIC: UART is source 1, all other sources are tied low.
module cva6_plic #(
  parameter int unsigned AxiAddrWidth = 64,
  parameter int unsigned AxiDataWidth = 64,
  parameter int unsigned AxiIdWidth   = 4,
  parameter int unsigned AxiUserWidth = 1
) (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       uart_irq_i,
  output logic [1:0] irq_o,
  AXI_BUS.Slave      axi
);
  logic [ariane_soc::NumSources-1:0] irq_sources;
  assign irq_sources = {{(ariane_soc::NumSources-1){1'b0}}, uart_irq_i};

  REG_BUS #(
    .ADDR_WIDTH ( 32 ),
    .DATA_WIDTH ( 32 )
  ) reg_bus (clk_i);

  logic        penable, pwrite, psel, pready, pslverr;
  logic [31:0] paddr, pwdata, prdata;

  axi2apb_64_32 #(
    .AXI4_ADDRESS_WIDTH ( AxiAddrWidth  ),
    .AXI4_RDATA_WIDTH   ( AxiDataWidth  ),
    .AXI4_WDATA_WIDTH   ( AxiDataWidth  ),
    .AXI4_ID_WIDTH      ( AxiIdWidth    ),
    .AXI4_USER_WIDTH    ( AxiUserWidth  ),
    .BUFF_DEPTH_SLAVE   ( 2             ),
    .APB_ADDR_WIDTH     ( 32            )
  ) i_axi2apb (
    .ACLK       ( clk_i         ),
    .ARESETn    ( rst_ni        ),
    .test_en_i  ( 1'b0          ),
    .AWID_i     ( axi.aw_id     ),
    .AWADDR_i   ( axi.aw_addr   ),
    .AWLEN_i    ( axi.aw_len    ),
    .AWSIZE_i   ( axi.aw_size   ),
    .AWBURST_i  ( axi.aw_burst  ),
    .AWLOCK_i   ( axi.aw_lock   ),
    .AWCACHE_i  ( axi.aw_cache  ),
    .AWPROT_i   ( axi.aw_prot   ),
    .AWREGION_i ( axi.aw_region ),
    .AWUSER_i   ( axi.aw_user   ),
    .AWQOS_i    ( axi.aw_qos    ),
    .AWVALID_i  ( axi.aw_valid  ),
    .AWREADY_o  ( axi.aw_ready  ),
    .WDATA_i    ( axi.w_data    ),
    .WSTRB_i    ( axi.w_strb    ),
    .WLAST_i    ( axi.w_last    ),
    .WUSER_i    ( axi.w_user    ),
    .WVALID_i   ( axi.w_valid   ),
    .WREADY_o   ( axi.w_ready   ),
    .BID_o      ( axi.b_id      ),
    .BRESP_o    ( axi.b_resp    ),
    .BVALID_o   ( axi.b_valid   ),
    .BUSER_o    ( axi.b_user    ),
    .BREADY_i   ( axi.b_ready   ),
    .ARID_i     ( axi.ar_id     ),
    .ARADDR_i   ( axi.ar_addr   ),
    .ARLEN_i    ( axi.ar_len    ),
    .ARSIZE_i   ( axi.ar_size   ),
    .ARBURST_i  ( axi.ar_burst  ),
    .ARLOCK_i   ( axi.ar_lock   ),
    .ARCACHE_i  ( axi.ar_cache  ),
    .ARPROT_i   ( axi.ar_prot   ),
    .ARREGION_i ( axi.ar_region ),
    .ARUSER_i   ( axi.ar_user   ),
    .ARQOS_i    ( axi.ar_qos    ),
    .ARVALID_i  ( axi.ar_valid  ),
    .ARREADY_o  ( axi.ar_ready  ),
    .RID_o      ( axi.r_id      ),
    .RDATA_o    ( axi.r_data    ),
    .RRESP_o    ( axi.r_resp    ),
    .RLAST_o    ( axi.r_last    ),
    .RUSER_o    ( axi.r_user    ),
    .RVALID_o   ( axi.r_valid   ),
    .RREADY_i   ( axi.r_ready   ),
    .PENABLE    ( penable       ),
    .PWRITE     ( pwrite        ),
    .PADDR      ( paddr         ),
    .PSEL       ( psel          ),
    .PWDATA     ( pwdata        ),
    .PRDATA     ( prdata        ),
    .PREADY     ( pready        ),
    .PSLVERR    ( pslverr       )
  );

  apb_to_reg i_apb_to_reg (
    .clk_i     ( clk_i   ),
    .rst_ni    ( rst_ni  ),
    .penable_i ( penable ),
    .pwrite_i  ( pwrite  ),
    .paddr_i   ( paddr   ),
    .psel_i    ( psel    ),
    .pwdata_i  ( pwdata  ),
    .prdata_o  ( prdata  ),
    .pready_o  ( pready  ),
    .pslverr_o ( pslverr ),
    .reg_o     ( reg_bus )
  );

  `REG_BUS_TYPEDEF_ALL(plic, logic[31:0], logic[31:0], logic[3:0])
  plic_req_t plic_req;
  plic_rsp_t plic_rsp;
  `REG_BUS_ASSIGN_TO_REQ(plic_req, reg_bus)
  `REG_BUS_ASSIGN_FROM_RSP(reg_bus, plic_rsp)

  plic_top #(
    .N_SOURCE  ( ariane_soc::NumSources  ),
    .N_TARGET  ( ariane_soc::NumTargets  ),
    .MAX_PRIO  ( ariane_soc::MaxPriority ),
    .reg_req_t ( plic_req_t              ),
    .reg_rsp_t ( plic_rsp_t              )
  ) i_plic (
    .clk_i,
    .rst_ni,
    .req_i         ( plic_req    ),
    .resp_o        ( plic_rsp    ),
    .le_i          ( '0          ),
    .irq_sources_i ( irq_sources ),
    .eip_targets_o ( irq_o       )
  );
endmodule
