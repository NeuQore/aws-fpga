// Synthesizable 16550-like APB UART for AWS F2.
// TX bytes are presented on a ready/valid interface for the host FIFO.
// LSR.THRE/TEMT stay set while the host FIFO can accept data so baremetal
// printf/uart loops do not stall.

module host_uart (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        penable_i,
    input  logic        pwrite_i,
    input  logic [31:0] paddr_i,
    input  logic        psel_i,
    input  logic [31:0] pwdata_i,
    output logic [31:0] prdata_o,
    output logic        pready_o,
    output logic        pslverr_o,
    output logic        irq_o,
    output logic        tx_valid_o,
    output logic [7:0]  tx_data_o,
    input  logic        tx_ready_i
);
  localparam THR = 0;
  localparam IER = 1;
  localparam IIR = 2;
  localparam FCR = 2;
  localparam LCR = 3;
  localparam MCR = 4;
  localparam LSR = 5;
  localparam MSR = 6;
  localparam SCR = 7;

  localparam THRE = 5;
  localparam TEMT = 6;

  logic [7:0] lcr, dlm, dll, mcr, lsr, ier, msr, scr;
  logic       fifo_enabled;

  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      lcr          <= '0;
      dlm          <= '0;
      dll          <= '0;
      mcr          <= '0;
      lsr          <= '0;
      ier          <= '0;
      msr          <= '0;
      scr          <= '0;
      fifo_enabled <= 1'b0;
      tx_valid_o   <= 1'b0;
      tx_data_o    <= '0;
    end else begin
      if (tx_valid_o && tx_ready_i)
        tx_valid_o <= 1'b0;

      if (psel_i && penable_i && pwrite_i) begin
        unique case ((paddr_i >> 2) & 32'h7)
          THR: begin
            if (lcr[7])
              dll <= pwdata_i[7:0];
            else begin
              tx_data_o  <= pwdata_i[7:0];
              tx_valid_o <= 1'b1;
            end
          end
          IER: begin
            if (lcr[7])
              dlm <= pwdata_i[7:0];
            else
              ier <= pwdata_i[7:0] & 8'h0F;
          end
          FCR: fifo_enabled <= pwdata_i[0];
          LCR: lcr <= pwdata_i[7:0];
          MCR: mcr <= pwdata_i[7:0] & 8'h1F;
          LSR: lsr <= pwdata_i[7:0];
          MSR: msr <= pwdata_i[7:0];
          SCR: scr <= pwdata_i[7:0];
          default: ;
        endcase
      end
    end
  end

  logic [7:0] lsr_rdata;
  always_comb begin
    lsr_rdata = lsr;
    if (tx_ready_i && !tx_valid_o) begin
      lsr_rdata[THRE] = 1'b1;
      lsr_rdata[TEMT] = 1'b1;
    end
  end

  // 16550 THRE interrupt (IER bit 1). Linux's 8250 driver uses this to drain
  // its software TX buffer; receive interrupts are not implemented because
  // this UART is console-output-only.
  assign irq_o = ier[1] && lsr_rdata[THRE];

  always_comb begin
    prdata_o = '0;
    if (psel_i && penable_i && !pwrite_i) begin
      unique case ((paddr_i >> 2) & 32'h7)
        THR: prdata_o = lcr[7] ? {24'b0, dll} : '0;
        IER: prdata_o = lcr[7] ? {24'b0, dlm} : {24'b0, ier};
        IIR: begin
          if (irq_o)
            prdata_o = fifo_enabled ? 32'h0000_00C2 : 32'h0000_0002;
          else
            prdata_o = fifo_enabled ? 32'h0000_00C1 : 32'h0000_0001;
        end
        LCR: prdata_o = {24'b0, lcr};
        MCR: prdata_o = {24'b0, mcr};
        LSR: prdata_o = {24'b0, lsr_rdata};
        MSR: prdata_o = {24'b0, msr};
        SCR: prdata_o = {24'b0, scr};
        default: ;
      endcase
    end
  end
endmodule
