// Dual-clock block RAM: CPU-clock write, OCL-clock read.

module cva6_trace_ram #(
  parameter int unsigned DEPTH = 1024,
  parameter int unsigned WIDTH = 64
) (
  input  logic                     wr_clk_i,
  input  logic                     wr_en_i,
  input  logic [$clog2(DEPTH)-1:0] wr_addr_i,
  input  logic [WIDTH-1:0]         wr_data_i,
  input  logic                     rd_clk_i,
  input  logic [$clog2(DEPTH)-1:0] rd_addr_i,
  output logic [WIDTH-1:0]         rd_data_o
);

  (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

  always_ff @(posedge wr_clk_i) begin
    if (wr_en_i)
      mem[wr_addr_i] <= wr_data_i;
  end

  always_ff @(posedge rd_clk_i) begin
    rd_data_o <= mem[rd_addr_i];
  end

endmodule
