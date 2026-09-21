// Adapt CVA6's 4-bit-ID AXI interface to the AWS 16-bit-ID, 512-bit
// cl_axi_clock_converter. IDs are zero-extended before the CDC and restored
// from the low bits on return; the converter preserves the full value.
module cva6_axi_clock_converter (
  input  logic      src_clk_i,
  input  logic      src_rst_ni,
  input  logic      dst_clk_i,
  input  logic      dst_rst_ni,
  AXI_BUS.Slave     src,
  axi_bus_t.slave   dst
);

  logic [15:0] src_bid, src_rid;

  assign src.b_id   = src_bid[3:0];
  assign src.b_user = '0;
  assign src.r_id   = src_rid[3:0];
  assign src.r_user = '0;

  cl_axi_clock_converter i_axi_clock_converter (
    .s_axi_aclk    (src_clk_i),
    .s_axi_aresetn (src_rst_ni),
    .s_axi_awid    ({12'b0, src.aw_id}),
    .s_axi_awaddr  (src.aw_addr),
    .s_axi_awlen   (src.aw_len),
    .s_axi_awsize  (src.aw_size),
    .s_axi_awburst (src.aw_burst),
    .s_axi_awlock  (src.aw_lock),
    .s_axi_awcache (src.aw_cache),
    .s_axi_awprot  (src.aw_prot),
    .s_axi_awregion(src.aw_region),
    .s_axi_awqos   (src.aw_qos),
    .s_axi_awuser  (src.aw_user[18:0]),
    .s_axi_awvalid (src.aw_valid),
    .s_axi_awready (src.aw_ready),
    .s_axi_wdata   (src.w_data),
    .s_axi_wstrb   (src.w_strb),
    .s_axi_wlast   (src.w_last),
    .s_axi_wvalid  (src.w_valid),
    .s_axi_wready  (src.w_ready),
    .s_axi_bid     (src_bid),
    .s_axi_bresp   (src.b_resp),
    .s_axi_bvalid  (src.b_valid),
    .s_axi_bready  (src.b_ready),
    .s_axi_arid    ({12'b0, src.ar_id}),
    .s_axi_araddr  (src.ar_addr),
    .s_axi_arlen   (src.ar_len),
    .s_axi_arsize  (src.ar_size),
    .s_axi_arburst (src.ar_burst),
    .s_axi_arlock  (src.ar_lock),
    .s_axi_arcache (src.ar_cache),
    .s_axi_arprot  (src.ar_prot),
    .s_axi_arregion(src.ar_region),
    .s_axi_arqos   (src.ar_qos),
    .s_axi_aruser  (src.ar_user[18:0]),
    .s_axi_arvalid (src.ar_valid),
    .s_axi_arready (src.ar_ready),
    .s_axi_rid     (src_rid),
    .s_axi_rdata   (src.r_data),
    .s_axi_rresp   (src.r_resp),
    .s_axi_rlast   (src.r_last),
    .s_axi_rvalid  (src.r_valid),
    .s_axi_rready  (src.r_ready),

    .m_axi_aclk    (dst_clk_i),
    .m_axi_aresetn (dst_rst_ni),
    .m_axi_awid    (dst.awid),
    .m_axi_awaddr  (dst.awaddr),
    .m_axi_awlen   (dst.awlen),
    .m_axi_awsize  (dst.awsize),
    .m_axi_awburst (dst.awburst),
    .m_axi_awlock  (),
    .m_axi_awcache (),
    .m_axi_awprot  (),
    .m_axi_awregion(),
    .m_axi_awqos   (),
    .m_axi_awuser  (),
    .m_axi_awvalid (dst.awvalid),
    .m_axi_awready (dst.awready),
    .m_axi_wdata   (dst.wdata),
    .m_axi_wstrb   (dst.wstrb),
    .m_axi_wlast   (dst.wlast),
    .m_axi_wvalid  (dst.wvalid),
    .m_axi_wready  (dst.wready),
    .m_axi_bid     (dst.bid),
    .m_axi_bresp   (dst.bresp),
    .m_axi_bvalid  (dst.bvalid),
    .m_axi_bready  (dst.bready),
    .m_axi_arid    (dst.arid),
    .m_axi_araddr  (dst.araddr),
    .m_axi_arlen   (dst.arlen),
    .m_axi_arsize  (dst.arsize),
    .m_axi_arburst (dst.arburst),
    .m_axi_arlock  (),
    .m_axi_arcache (),
    .m_axi_arprot  (),
    .m_axi_arregion(),
    .m_axi_arqos   (),
    .m_axi_aruser  (),
    .m_axi_arvalid (dst.arvalid),
    .m_axi_arready (dst.arready),
    .m_axi_rid     (dst.rid),
    .m_axi_rdata   (dst.rdata),
    .m_axi_rresp   (dst.rresp),
    .m_axi_rlast   (dst.rlast),
    .m_axi_rvalid  (dst.rvalid),
    .m_axi_rready  (dst.rready)
  );

  assign dst.wid = '0;

endmodule
