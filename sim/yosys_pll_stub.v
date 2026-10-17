module pll_atari (input wire refclk, input wire rst, output wire outclk_0, output wire outclk_1, output wire locked);
  assign outclk_0 = refclk; assign outclk_1 = refclk; assign locked = 1'b1;
endmodule
module mf_datatable (input [7:0] address_a, input [7:0] address_b, input clock_a, input clock_b,
  input [31:0] data_a, input [31:0] data_b, input wren_a, input wren_b, output reg [31:0] q_a, output reg [31:0] q_b);
  reg [31:0] m [0:255];
  always @(posedge clock_a) begin if (wren_a) m[address_a] <= data_a; q_a <= m[address_a]; end
  always @(posedge clock_b) begin q_b <= m[address_b]; end
endmodule
