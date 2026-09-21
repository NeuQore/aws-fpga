// ============================================================================
// Amazon FPGA Hardware Development Kit
//
// Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Amazon Software License (the "License"). You may not use
// this file except in compliance with the License. A copy of the License is
// located at
//
//    http://aws.amazon.com/asl/
//
// or in the "license" file accompanying this file. This file is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
// implied. See the License for the specific language governing permissions and
// limitations under the License.
// ============================================================================


//====================================================================================
// Top level module file for cl_cva6_linux
//====================================================================================

module cl_cva6_linux
    #(
      parameter EN_DDR = 0,
      parameter EN_HBM = 1
    )
    (
      `include "cl_ports.vh"
    );

`include "cl_id_defines.vh" // CL ID defines required for all examples
`include "cl_cva6_linux_defines.vh"

  logic cpu_hbm_grant;
  logic hbm_ready;
  logic rst_main_n_sync;
  assign rst_main_n_sync = rst_main_n;

//=============================================================================
// GLOBALS
//=============================================================================

  always_comb begin
     cl_sh_flr_done    = 'b1;
     cl_sh_status0     = {30'b0, cpu_hbm_grant, hbm_ready};
     cl_sh_status1     = 'b0;
     cl_sh_status2     = 'b0;
     cl_sh_id0         = `CL_SH_ID0;
     cl_sh_id1         = `CL_SH_ID1;
     cl_sh_status_vled = {14'b0, cpu_hbm_grant, hbm_ready};
     cl_sh_dma_wr_full = 'b0;
     cl_sh_dma_rd_full = 'b0;
  end


//=============================================================================
// PCIM
//=============================================================================

  // Cause Protocol Violations
  always_comb begin
    cl_sh_pcim_awaddr  = 'b0;
    cl_sh_pcim_awsize  = 'b0;
    cl_sh_pcim_awburst = 'b0;
    cl_sh_pcim_awvalid = 'b0;

    cl_sh_pcim_wdata   = 'b0;
    cl_sh_pcim_wstrb   = 'b0;
    cl_sh_pcim_wlast   = 'b0;
    cl_sh_pcim_wvalid  = 'b0;

    cl_sh_pcim_araddr  = 'b0;
    cl_sh_pcim_arsize  = 'b0;
    cl_sh_pcim_arburst = 'b0;
    cl_sh_pcim_arvalid = 'b0;
  end

  // Remaining CL Output Ports
  always_comb begin
    cl_sh_pcim_awid    = 'b0;
    cl_sh_pcim_awlen   = 'b0;
    cl_sh_pcim_awcache = 'b0;
    cl_sh_pcim_awlock  = 'b0;
    cl_sh_pcim_awprot  = 'b0;
    cl_sh_pcim_awqos   = 'b0;
    cl_sh_pcim_awuser  = 'b0;

    cl_sh_pcim_wid     = 'b0;
    cl_sh_pcim_wuser   = 'b0;

    cl_sh_pcim_arid    = 'b0;
    cl_sh_pcim_arlen   = 'b0;
    cl_sh_pcim_arcache = 'b0;
    cl_sh_pcim_arlock  = 'b0;
    cl_sh_pcim_arprot  = 'b0;
    cl_sh_pcim_arqos   = 'b0;
    cl_sh_pcim_aruser  = 'b0;

    cl_sh_pcim_rready  = 'b0;
  end

//=============================================================================
// PCIS
//=============================================================================

  axi_bus_t pcis_axi();

  assign pcis_axi.awid             = sh_cl_dma_pcis_awid;
  assign pcis_axi.awaddr           = sh_cl_dma_pcis_awaddr;
  assign pcis_axi.awlen            = sh_cl_dma_pcis_awlen;
  assign pcis_axi.awsize           = sh_cl_dma_pcis_awsize;
  assign pcis_axi.awburst          = sh_cl_dma_pcis_awburst;
  assign pcis_axi.awvalid          = sh_cl_dma_pcis_awvalid;
  assign cl_sh_dma_pcis_awready    = pcis_axi.awready;
  assign pcis_axi.wid              = sh_cl_dma_pcis_wid;
  assign pcis_axi.wdata            = sh_cl_dma_pcis_wdata;
  assign pcis_axi.wstrb            = sh_cl_dma_pcis_wstrb;
  assign pcis_axi.wlast            = sh_cl_dma_pcis_wlast;
  assign pcis_axi.wvalid           = sh_cl_dma_pcis_wvalid;
  assign cl_sh_dma_pcis_wready     = pcis_axi.wready;
  assign cl_sh_dma_pcis_bid        = pcis_axi.bid;
  assign cl_sh_dma_pcis_bresp      = pcis_axi.bresp;
  assign cl_sh_dma_pcis_bvalid     = pcis_axi.bvalid;
  assign pcis_axi.bready           = sh_cl_dma_pcis_bready;
  assign pcis_axi.arid             = sh_cl_dma_pcis_arid;
  assign pcis_axi.araddr           = sh_cl_dma_pcis_araddr;
  assign pcis_axi.arlen            = sh_cl_dma_pcis_arlen;
  assign pcis_axi.arsize           = sh_cl_dma_pcis_arsize;
  assign pcis_axi.arburst          = sh_cl_dma_pcis_arburst;
  assign pcis_axi.arvalid          = sh_cl_dma_pcis_arvalid;
  assign cl_sh_dma_pcis_arready    = pcis_axi.arready;
  assign cl_sh_dma_pcis_rid        = pcis_axi.rid;
  assign cl_sh_dma_pcis_rdata      = pcis_axi.rdata;
  assign cl_sh_dma_pcis_rresp      = pcis_axi.rresp;
  assign cl_sh_dma_pcis_rlast      = pcis_axi.rlast;
  assign cl_sh_dma_pcis_rvalid     = pcis_axi.rvalid;
  assign cl_sh_dma_pcis_ruser      = '0;
  assign pcis_axi.rready           = sh_cl_dma_pcis_rready;

//=============================================================================
// OCL AXI-Lite (host control / UART / SRAM load)
//=============================================================================

  logic        sh_ocl_awvalid_q;
  logic [31:0] sh_ocl_awaddr_q;
  logic        sh_ocl_wvalid_q;
  logic [31:0] sh_ocl_wdata_q;
  logic [3:0]  sh_ocl_wstrb_q;
  logic        sh_ocl_bready_q;
  logic        sh_ocl_arvalid_q;
  logic [31:0] sh_ocl_araddr_q;
  logic        sh_ocl_rready_q;
  logic        ocl_sh_awready_q;
  logic        ocl_sh_wready_q;
  logic        ocl_sh_bvalid_q;
  logic [1:0]  ocl_sh_bresp_q;
  logic        ocl_sh_arready_q;
  logic        ocl_sh_rvalid_q;
  logic [31:0] ocl_sh_rdata_q;
  logic [1:0]  ocl_sh_rresp_q;

  axi_register_slice_light AXIL_OCL_REG_SLC (
    .aclk          (clk_main_a0),
    .aresetn       (rst_main_n),
    .s_axi_awaddr  (ocl_cl_awaddr),
    .s_axi_awprot  (`AXI_PROT_DEFAULT),
    .s_axi_awvalid (ocl_cl_awvalid),
    .s_axi_awready (cl_ocl_awready),
    .s_axi_wdata   (ocl_cl_wdata),
    .s_axi_wstrb   (ocl_cl_wstrb),
    .s_axi_wvalid  (ocl_cl_wvalid),
    .s_axi_wready  (cl_ocl_wready),
    .s_axi_bresp   (cl_ocl_bresp),
    .s_axi_bvalid  (cl_ocl_bvalid),
    .s_axi_bready  (ocl_cl_bready),
    .s_axi_araddr  (ocl_cl_araddr),
    .s_axi_arprot  (`AXI_PROT_DEFAULT),
    .s_axi_arvalid (ocl_cl_arvalid),
    .s_axi_arready (cl_ocl_arready),
    .s_axi_rdata   (cl_ocl_rdata),
    .s_axi_rresp   (cl_ocl_rresp),
    .s_axi_rvalid  (cl_ocl_rvalid),
    .s_axi_rready  (ocl_cl_rready),
    .m_axi_awaddr  (sh_ocl_awaddr_q),
    .m_axi_awprot  (),
    .m_axi_awvalid (sh_ocl_awvalid_q),
    .m_axi_awready (ocl_sh_awready_q),
    .m_axi_wdata   (sh_ocl_wdata_q),
    .m_axi_wstrb   (sh_ocl_wstrb_q),
    .m_axi_wvalid  (sh_ocl_wvalid_q),
    .m_axi_wready  (ocl_sh_wready_q),
    .m_axi_bresp   (ocl_sh_bresp_q),
    .m_axi_bvalid  (ocl_sh_bvalid_q),
    .m_axi_bready  (sh_ocl_bready_q),
    .m_axi_araddr  (sh_ocl_araddr_q),
    .m_axi_arvalid (sh_ocl_arvalid_q),
    .m_axi_arready (ocl_sh_arready_q),
    .m_axi_rdata   (ocl_sh_rdata_q),
    .m_axi_rresp   (ocl_sh_rresp_q),
    .m_axi_rvalid  (ocl_sh_rvalid_q),
    .m_axi_rready  (sh_ocl_rready_q)
  );

  typedef enum logic [2:0] {
    IDLE       = 3'd0,
    WRITE_WAIT = 3'd1,
    WRITE      = 3'd2,
    WRITE_RESP = 3'd3,
    READ       = 3'd4
  } axil_state_t;

  axil_state_t current_state, next_state;
  logic [31:0] write_addr;

  // The `ADDR_* macros are 32-bit literals; a part-select cannot be applied to
  // a literal, so narrow them here via assignment truncation instead.
  localparam logic [7:0] REG_CTRL      = `ADDR_CTRL;
  localparam logic [7:0] REG_STATUS    = `ADDR_STATUS;
  localparam logic [7:0] REG_UART_RX   = `ADDR_UART_RX;
  localparam logic [7:0] REG_MAGIC     = `ADDR_MAGIC;
  localparam logic [7:0] REG_MEM_ADDR  = `ADDR_MEM_ADDR;
  localparam logic [7:0] REG_MEM_WDATA = `ADDR_MEM_WDATA;
  localparam logic [7:0] REG_MEM_RDATA = `ADDR_MEM_RDATA;
  localparam logic [7:0] REG_MEM_CMD   = `ADDR_MEM_CMD;

  logic        cpu_run;
  logic [31:0] mem_addr, mem_wdata, mem_rdata_host;
  assign mem_rdata_host = 32'h0;
  logic        host_req_pulse;
  logic        host_we_level;

  logic        uart_rx_valid;
  logic [7:0]  uart_rx_data;
  logic        uart_rx_pop;
  logic [7:0]  uart_count;

  logic addr_wr_hs, data_wr_hs, bresp_hs, addr_rd_hs, data_rd_hs;
  assign addr_wr_hs = sh_ocl_awvalid_q & ocl_sh_awready_q;
  assign data_wr_hs = sh_ocl_wvalid_q  & ocl_sh_wready_q;
  assign bresp_hs   = ocl_sh_bvalid_q  & sh_ocl_bready_q;
  assign addr_rd_hs = sh_ocl_arvalid_q & ocl_sh_arready_q;
  assign data_rd_hs = ocl_sh_rvalid_q  & sh_ocl_rready_q;

  always_comb begin
    next_state = current_state;
    unique case (current_state)
      IDLE: begin
        if (addr_wr_hs && data_wr_hs) next_state = WRITE;
        else if (addr_wr_hs || data_wr_hs) next_state = WRITE_WAIT;
        else if (addr_rd_hs) next_state = READ;
      end
      WRITE_WAIT: if (addr_wr_hs || data_wr_hs) next_state = WRITE;
      WRITE:      next_state = WRITE_RESP;
      WRITE_RESP: if (bresp_hs) next_state = IDLE;
      READ:       if (data_rd_hs) next_state = IDLE;
      default:    next_state = IDLE;
    endcase
  end

  always_ff @(posedge clk_main_a0 or negedge rst_main_n) begin
    if (!rst_main_n)
      current_state <= IDLE;
    else
      current_state <= next_state;
  end

  // Drive AXI-Lite handshakes from state
  always_comb begin
    ocl_sh_awready_q = 1'b0;
    ocl_sh_wready_q  = 1'b0;
    ocl_sh_arready_q = 1'b0;
    unique case (current_state)
      IDLE: begin
        ocl_sh_awready_q = 1'b1;
        ocl_sh_wready_q  = 1'b1;
        ocl_sh_arready_q = 1'b1;
      end
      WRITE_WAIT: begin
        ocl_sh_awready_q = 1'b1;
        ocl_sh_wready_q  = 1'b1;
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk_main_a0 or negedge rst_main_n) begin
    if (!rst_main_n) begin
      write_addr       <= '0;
      cpu_run          <= 1'b0;
      mem_addr         <= '0;
      mem_wdata        <= '0;
      host_req_pulse   <= 1'b0;
      host_we_level    <= 1'b0;
      uart_rx_pop      <= 1'b0;
      ocl_sh_bvalid_q  <= 1'b0;
      ocl_sh_bresp_q   <= `AXI_RESP_OKAY;
      ocl_sh_rvalid_q  <= 1'b0;
      ocl_sh_rdata_q   <= '0;
      ocl_sh_rresp_q   <= `AXI_RESP_OKAY;
    end else begin
      host_req_pulse <= 1'b0;
      uart_rx_pop    <= 1'b0;

      if (addr_wr_hs)
        write_addr <= sh_ocl_awaddr_q;

      if (next_state == WRITE) begin
        unique case ((addr_wr_hs ? sh_ocl_awaddr_q[7:0] : write_addr[7:0]))
          REG_CTRL:      cpu_run   <= sh_ocl_wdata_q[0];
          REG_MEM_ADDR:  mem_addr  <= sh_ocl_wdata_q;
          REG_MEM_WDATA: mem_wdata <= sh_ocl_wdata_q;
          REG_MEM_CMD: begin
            host_we_level  <= sh_ocl_wdata_q[0];
            host_req_pulse <= 1'b1;
          end
          default: ;
        endcase
      end

      ocl_sh_bvalid_q <= (next_state == WRITE_RESP);

      if (addr_rd_hs) begin
        ocl_sh_rvalid_q <= 1'b1;
        unique case (sh_ocl_araddr_q[7:0])
          REG_CTRL:   ocl_sh_rdata_q <= {31'b0, cpu_run};
          REG_STATUS: ocl_sh_rdata_q <= {14'b0, cpu_hbm_grant, hbm_ready,
                                         uart_count, 7'b0, uart_rx_valid};
          REG_UART_RX: begin
            ocl_sh_rdata_q <= {24'b0, uart_rx_data};
            uart_rx_pop    <= uart_rx_valid;
          end
          REG_MAGIC:     ocl_sh_rdata_q <= `MAGIC_VALUE;
          REG_MEM_ADDR:  ocl_sh_rdata_q <= mem_addr;
          REG_MEM_WDATA: ocl_sh_rdata_q <= mem_wdata;
          REG_MEM_RDATA: ocl_sh_rdata_q <= mem_rdata_host;
          default:       ocl_sh_rdata_q <= `INVALID_ADDR_RESP;
        endcase
      end else if (data_rd_hs) begin
        ocl_sh_rvalid_q <= 1'b0;
      end
    end
  end

//=============================================================================
// CPU clock: clk_main_a0 / 4 = 62.5 MHz
//
// cv64a6_imafdc_sv39 is larger than the 32-bit FPGA config (FPU, 2 commit
// ports, 16/32 KiB caches). Divide-by-2 (125 MHz) closed for cv32a6; this
// example starts at 62.5 MHz to give the 64-bit core timing headroom.
//=============================================================================

  logic [1:0] clk_div_q;
  logic clk_cpu;
  logic rst_cpu_meta, rst_cpu_n;

  always_ff @(posedge clk_main_a0 or negedge rst_main_n) begin
    if (!rst_main_n)
      clk_div_q <= 2'b00;
    else
      clk_div_q <= clk_div_q + 2'b01;
  end

  BUFG i_clk_cpu_buf (
    .I (clk_div_q[1]),
    .O (clk_cpu)
  );

  always_ff @(posedge clk_cpu or negedge rst_main_n) begin
    if (!rst_main_n) begin
      rst_cpu_meta <= 1'b0;
      rst_cpu_n    <= 1'b0;
    end else begin
      rst_cpu_meta <= 1'b1;
      rst_cpu_n    <= rst_cpu_meta;
    end
  end

  // cpu_run is a level from OCL; two-flop it onto clk_cpu.
  logic cpu_run_m, cpu_run_s;
  logic cpu_grant_m, cpu_grant_s;
  logic hbm_ready_m, hbm_ready_s;
  always_ff @(posedge clk_cpu or negedge rst_cpu_n) begin
    if (!rst_cpu_n) begin
      cpu_run_m <= 1'b0;
      cpu_run_s <= 1'b0;
      cpu_grant_m <= 1'b0;
      cpu_grant_s <= 1'b0;
      hbm_ready_m <= 1'b0;
      hbm_ready_s <= 1'b0;
    end else begin
      cpu_run_m <= cpu_run;
      cpu_run_s <= cpu_run_m;
      cpu_grant_m <= cpu_hbm_grant;
      cpu_grant_s <= cpu_grant_m;
      hbm_ready_m <= hbm_ready;
      hbm_ready_s <= hbm_ready_m;
    end
  end

  // Stretch the 1-cycle OCL MEM_CMD pulse into a 1-cycle clk_cpu strobe.
  logic host_req_tog;
  logic host_req_tog_m, host_req_tog_s, host_req_tog_d;
  logic host_req_cpu;

  always_ff @(posedge clk_main_a0 or negedge rst_main_n) begin
    if (!rst_main_n)
      host_req_tog <= 1'b0;
    else if (host_req_pulse)
      host_req_tog <= ~host_req_tog;
  end

  always_ff @(posedge clk_cpu or negedge rst_cpu_n) begin
    if (!rst_cpu_n) begin
      host_req_tog_m <= 1'b0;
      host_req_tog_s <= 1'b0;
      host_req_tog_d <= 1'b0;
    end else begin
      host_req_tog_m <= host_req_tog;
      host_req_tog_s <= host_req_tog_m;
      host_req_tog_d <= host_req_tog_s;
    end
  end

  assign host_req_cpu = host_req_tog_s ^ host_req_tog_d;

//=============================================================================
// UART capture FIFO (write: clk_cpu, read: clk_main_a0)
//=============================================================================

  logic        uart_tx_valid, uart_tx_ready;
  logic [7:0]  uart_tx_data;
  logic        uart_fifo_empty, uart_fifo_full, uart_wr_rst_busy;
  logic [9:0]  uart_rd_count;

  xpm_fifo_async #(
    .CDC_SYNC_STAGES     (3),
    .FIFO_MEMORY_TYPE    ("distributed"),
    .FIFO_WRITE_DEPTH    (512),
    .WRITE_DATA_WIDTH    (8),
    .READ_DATA_WIDTH     (8),
    .READ_MODE           ("fwft"),
    .RD_DATA_COUNT_WIDTH (10),
    .WR_DATA_COUNT_WIDTH (10),
    .RELATED_CLOCKS      (0)
  ) i_uart_fifo (
    .rst           (~rst_main_n),
    .wr_clk        (clk_cpu),
    .wr_en         (uart_tx_valid),
    .din           (uart_tx_data),
    .full          (uart_fifo_full),
    .wr_rst_busy   (uart_wr_rst_busy),
    .rd_clk        (clk_main_a0),
    .rd_en         (uart_rx_pop),
    .dout          (uart_rx_data),
    .empty         (uart_fifo_empty),
    .rd_rst_busy   (),
    .rd_data_count (uart_rd_count),
    .wr_data_count (),
    .almost_empty  (),
    .almost_full   (),
    .data_valid    (),
    .dbiterr       (),
    .sbiterr       (),
    .overflow      (),
    .underflow     (),
    .prog_empty    (),
    .prog_full     (),
    .wr_ack        (),
    .sleep         (1'b0),
    .injectdbiterr (1'b0),
    .injectsbiterr (1'b0)
  );

  assign uart_rx_valid = ~uart_fifo_empty;
  assign uart_count    = uart_rd_count[7:0];

  // Backpressure the core's UART so characters are never dropped while the
  // host drains the FIFO over OCL.
  assign uart_tx_ready = ~uart_fifo_full & ~uart_wr_rst_busy;

  AXI_BUS #(
    .AXI_ADDR_WIDTH (64),
    .AXI_DATA_WIDTH (64),
    .AXI_ID_WIDTH   (4),
    .AXI_USER_WIDTH (64)
  ) cpu_dram_axi();

  AXI_BUS #(
    .AXI_ADDR_WIDTH (64),
    .AXI_DATA_WIDTH (512),
    .AXI_ID_WIDTH   (4),
    .AXI_USER_WIDTH (64)
  ) cpu_hbm_axi();
  axi_bus_t cpu_hbm_main_axi();

  logic cpu_start;
  assign cpu_start = cpu_run_s & cpu_grant_s & hbm_ready_s;

  cva6_f2_soc #(
    .DramBytes (64'h4000_0000)
  ) i_cva6_f2_soc (
    .clk_i            (clk_cpu),
    .rst_ni           (rst_cpu_n),
    .cpu_run_i        (cpu_start),
    .dram_axi         (cpu_dram_axi),
    .uart_tx_valid_o  (uart_tx_valid),
    .uart_tx_data_o   (uart_tx_data),
    .uart_tx_ready_i  (uart_tx_ready)
  );

  axi_dw_converter_intf #(
    .AXI_ID_WIDTH            (4),
    .AXI_ADDR_WIDTH          (64),
    .AXI_SLV_PORT_DATA_WIDTH (64),
    .AXI_MST_PORT_DATA_WIDTH (512),
    .AXI_USER_WIDTH          (64),
    .AXI_MAX_READS           (1)
  ) i_cpu_axi_dw_converter (
    .clk_i (clk_cpu),
    .rst_ni(rst_cpu_n),
    .slv   (cpu_dram_axi),
    .mst   (cpu_hbm_axi)
  );

  cva6_axi_clock_converter i_cpu_axi_clock_converter (
    .src_clk_i (clk_cpu),
    .src_rst_ni(rst_cpu_n),
    .dst_clk_i (clk_main_a0),
    .dst_rst_ni(rst_main_n),
    .src       (cpu_hbm_axi),
    .dst       (cpu_hbm_main_axi)
  );

//=============================================================================
// SDA
//=============================================================================

  // Cause Protocol Violations
  always_comb begin
    cl_sda_bresp   = 'b0;
    cl_sda_rresp   = 'b0;
    cl_sda_rvalid  = 'b0;
  end

  // Remaining CL Output Ports
  always_comb begin
    cl_sda_awready = 'b0;
    cl_sda_wready  = 'b0;

    cl_sda_bvalid = 'b0;

    cl_sda_arready = 'b0;

    cl_sda_rdata   = 'b0;
  end

//=============================================================================
// SH_DDR
//
// This design does not use the DDR interface. Tie off the shell's DDR ports
// with the AWS-provided template instead of instantiating sh_ddr, matching
// the cl_axil_reg_access example.
//=============================================================================

`include "unused_ddr_template.inc"

//=============================================================================
// USER-DEFIEND INTERRUPTS
//=============================================================================

  always_comb begin
    cl_sh_apppf_irq_req = 'b0;
  end

//=============================================================================
// VIRTUAL JTAG
//=============================================================================

  always_comb begin
    tdo = 'b0;
  end

//=============================================================================
// HBM MONITOR IO
//=============================================================================

  axi_bus_t hbm_axi();
  cfg_bus_t hbm_stat_bus();

  // One-shot HBM soft-reset after shell reset, matching cl_hbm_wrapper:
  // write 1 then 0 at CSR 0, then wait for o_hbm_ready.
  logic [1:0] hbm_init_st;
  always_ff @(posedge clk_main_a0 or negedge rst_main_n) begin
    if (!rst_main_n) begin
      hbm_init_st       <= 2'd0;
      hbm_stat_bus.wr   <= 1'b0;
      hbm_stat_bus.rd   <= 1'b0;
      hbm_stat_bus.addr <= '0;
      hbm_stat_bus.wdata<= '0;
      hbm_stat_bus.user <= '0;
    end else begin
      hbm_stat_bus.wr <= 1'b0;
      hbm_stat_bus.rd <= 1'b0;
      unique case (hbm_init_st)
        2'd0: begin
          hbm_stat_bus.wr    <= 1'b1;
          hbm_stat_bus.wdata <= 32'h1;
          hbm_init_st        <= 2'd1;
        end
        2'd1: begin
          hbm_stat_bus.wr    <= 1'b1;
          hbm_stat_bus.wdata <= 32'h0;
          hbm_init_st        <= 2'd2;
        end
        2'd2: if (hbm_ready)
          hbm_init_st <= 2'd3;
        default: ;
      endcase
    end
  end

  cva6_hbm_mux i_cva6_hbm_mux (
    .clk_i       (clk_main_a0),
    .rst_ni      (rst_main_n),
    .cpu_run_i   (cpu_run),
    .cpu_grant_o (cpu_hbm_grant),
    .pcis_axi    (pcis_axi),
    .cpu_axi     (cpu_hbm_main_axi),
    .hbm_axi     (hbm_axi)
  );

  cl_hbm_axi4 #(
    .HBM_PRESENT (EN_HBM)
  ) CL_HBM (
    .clk_hbm_ref          (clk_hbm_ref),
    .clk                  (clk_main_a0),
    .rst_n                (rst_main_n),
    .hbm_axi4_bus         (hbm_axi),
    .hbm_stat_bus         (hbm_stat_bus),
    .i_hbm_apb_preset_n_1 (hbm_apb_preset_n_1),
    .o_hbm_apb_paddr_1    (hbm_apb_paddr_1),
    .o_hbm_apb_pprot_1    (hbm_apb_pprot_1),
    .o_hbm_apb_psel_1     (hbm_apb_psel_1),
    .o_hbm_apb_penable_1  (hbm_apb_penable_1),
    .o_hbm_apb_pwrite_1   (hbm_apb_pwrite_1),
    .o_hbm_apb_pwdata_1   (hbm_apb_pwdata_1),
    .o_hbm_apb_pstrb_1    (hbm_apb_pstrb_1),
    .o_hbm_apb_pready_1   (hbm_apb_pready_1),
    .o_hbm_apb_prdata_1   (hbm_apb_prdata_1),
    .o_hbm_apb_pslverr_1  (hbm_apb_pslverr_1),
    .i_hbm_apb_preset_n_0 (hbm_apb_preset_n_0),
    .o_hbm_apb_paddr_0    (hbm_apb_paddr_0),
    .o_hbm_apb_pprot_0    (hbm_apb_pprot_0),
    .o_hbm_apb_psel_0     (hbm_apb_psel_0),
    .o_hbm_apb_penable_0  (hbm_apb_penable_0),
    .o_hbm_apb_pwrite_0   (hbm_apb_pwrite_0),
    .o_hbm_apb_pwdata_0   (hbm_apb_pwdata_0),
    .o_hbm_apb_pstrb_0    (hbm_apb_pstrb_0),
    .o_hbm_apb_pready_0   (hbm_apb_pready_0),
    .o_hbm_apb_prdata_0   (hbm_apb_prdata_0),
    .o_hbm_apb_pslverr_0  (hbm_apb_pslverr_0),
    .o_cl_sh_hbm_stat_int (),
    .o_hbm_ready          (hbm_ready)
  );

//=============================================================================
//
//=============================================================================

  always_comb begin
    PCIE_EP_TXP    = 'b0;
    PCIE_EP_TXN    = 'b0;

    PCIE_RP_PERSTN = 'b0;
    PCIE_RP_TXP    = 'b0;
    PCIE_RP_TXN    = 'b0;
  end

endmodule // cl_cva6_linux
