// ============================================================================
// Amazon FPGA Hardware Development Kit
// ============================================================================

`ifndef CL_CVA6_LINUX_DEFINES
`define CL_CVA6_LINUX_DEFINES

`define CL_NAME cl_cva6_linux

`define AXI_PROT_DEFAULT  3'h0
`define AXI_RESP_OKAY     2'b00
`define INVALID_ADDR_RESP 32'hDEADBEEF

// Host OCL register map (byte addresses on AppPF BAR0)
`define ADDR_CTRL      32'h00  // [0] cpu_run (1 = out of reset)
`define ADDR_STATUS    32'h04  // [0] uart_valid, [15:8] fifo count
`define ADDR_UART_RX   32'h08  // pop one TX character from CVA6
`define ADDR_MAGIC     32'h0C  // RO 0xC6A66401
`define ADDR_MEM_ADDR  32'h10  // byte offset from DRAM base 0x8000_0000
`define ADDR_MEM_WDATA 32'h14
`define ADDR_MEM_RDATA 32'h18
`define ADDR_MEM_CMD   32'h1C  // write 1 = store 32b, 2 = load 32b

`define MAGIC_VALUE    32'hC6A66401

`endif
