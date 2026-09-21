// ============================================================================
// Amazon FPGA Hardware Development Kit
// ============================================================================

`ifndef CL_CVA6_TRACKERS_DEFINES
`define CL_CVA6_TRACKERS_DEFINES

`define CL_NAME cl_cva6_trackers

`define AXI_PROT_DEFAULT  3'h0
`define AXI_RESP_OKAY     2'b00
`define INVALID_ADDR_RESP 32'hDEADBEEF

// Host OCL register map (byte addresses on AppPF BAR0)
`define ADDR_CTRL      32'h00  // [0] cpu_run
`define ADDR_STATUS    32'h04
`define ADDR_UART_RX   32'h08
`define ADDR_MAGIC     32'h0C  // RO 0xC6A66402
`define ADDR_MEM_ADDR  32'h10
`define ADDR_MEM_WDATA 32'h14
`define ADDR_MEM_RDATA 32'h18
`define ADDR_MEM_CMD   32'h1C

`define ADDR_TRACE_CTRL      32'h20  // [0] enable, [1] clear, [2] stop-on-exception
`define ADDR_TRACE_STATUS    32'h24  // [0] in_window, [1:5] instr/ic/dc/evt/l1 ovf, [8] window_done, [9] frozen
`define ADDR_TRACE_START_LO  32'h28  // inclusive CPU-cycle window start (user defined)
`define ADDR_TRACE_START_HI  32'h2C
`define ADDR_TRACE_END_LO    32'h30  // exclusive CPU-cycle window end (user defined)
`define ADDR_TRACE_END_HI    32'h34
`define ADDR_TRACE_CYCLE_LO  32'h38
`define ADDR_TRACE_CYCLE_HI  32'h3C
`define ADDR_TRACE_INSTR_CNT 32'h40
`define ADDR_TRACE_IC_CNT    32'h44
`define ADDR_TRACE_DC_CNT    32'h48
`define ADDR_TRACE_SEL       32'h4C  // 0=instr, 1=icache, 2=dcache, 3=events, 4=l1
`define ADDR_TRACE_IDX       32'h50
`define ADDR_TRACE_WORD      32'h54
`define ADDR_TRACE_RDATA_LO  32'h58
`define ADDR_TRACE_RDATA_HI  32'h5C
`define ADDR_TRACE_EVT_CNT   32'h60
`define ADDR_TRACE_L1_CNT    32'h64
`define ADDR_TRACE_IC_HIT    32'h68
`define ADDR_TRACE_IC_MISS   32'h6C
`define ADDR_TRACE_DC_HIT    32'h70
`define ADDR_TRACE_DC_MISS   32'h74

`define MAGIC_VALUE    32'hC6A66402

`endif
