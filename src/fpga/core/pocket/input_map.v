//
// Pocket / Dock controllers -> Atari 5200 controllers
//
// Output bit layout (active high, same as the MiSTer core):
//   0 right, 1 left, 2 down, 3 up, 4 fire 1, 5 fire 2, 6 *, 7 #,
//   8 start, 9 pause, 10 reset, 11..20 keypad 0..9
//
// Button layout (Pocket or Dock controller):
//   A = fire 1 (top)     B = fire 2 (bottom)    Start = Start
//   X = 1   Y = 2   L = *   R = #
//   Select tapped on its own = Pause
//   Select held as a shift key:
//     X = 3   Y = 4   A = 5   B = 6
//     Up = 7   Right = 8   Down = 9   Left = 0
//     Start = Reset (the 5200 keypad Reset key)
//   Dock extras: L2 = Pause, R2 = Reset
//
// Twin stick mode (Robotron 2084, Space Dungeon): player 1's face buttons
// (X up, B down, Y left, A right) and right analog stick drive the
// second joystick.
//
// SPDX-License-Identifier: GPL-2.0-or-later
//

`default_nettype none

module pad_map #(
    parameter PAUSE_CYCLES = 22'd2863636   // ~100 ms at 28.636 MHz
) (
    input  wire        clk,
    input  wire [31:0] key,
    input  wire [31:0] joy,
    input  wire        twin,               // face buttons become the 2nd stick

    output reg  [20:0] j,
    output wire [7:0]  ax,
    output wire [7:0]  ay,

    output wire [3:0]  twin_dirs,          // {up, down, left, right} as bits 3..0
    output wire [7:0]  twin_ax,
    output wire [7:0]  twin_ay
);

  wire up    = key[0];
  wire down  = key[1];
  wire left  = key[2];
  wire right = key[3];
  wire a     = key[4];
  wire b     = key[5];
  wire x     = key[6];
  wire y     = key[7];
  wire l1    = key[8];
  wire r1    = key[9];
  wire l2    = key[10];
  wire r2    = key[11];
  wire sel   = key[14];
  wire start = key[15];

  wire analog = (key[31:28] == 4'h3);

  // ---- Select: tap for Pause, hold as shift ----
  reg        sel_prev = 0;
  reg        sel_used = 0;
  reg [21:0] pause_cnt = 0;

  wire others = up | down | left | right | a | b | x | y | l1 | r1 | start;

  always @(posedge clk) begin
    sel_prev <= sel;
    if (sel & ~sel_prev) sel_used <= 0;
    else if (sel & others) sel_used <= 1;

    if (~sel & sel_prev & ~sel_used) pause_cnt <= PAUSE_CYCLES;
    else if (pause_cnt != 0) pause_cnt <= pause_cnt - 1'd1;
  end

  wire shift = sel;

  always @(*) begin
    j = 21'd0;
    if (!shift) begin
      j[0]  = right;
      j[1]  = left;
      j[2]  = down;
      j[3]  = up;
      j[4]  = a & ~twin;
      j[5]  = b & ~twin;
      j[6]  = l1;          // *
      j[7]  = r1;          // #
      j[8]  = start;
      j[12] = x & ~twin;   // 1
      j[13] = y & ~twin;   // 2
    end else begin
      j[14] = x;           // 3
      j[15] = y;           // 4
      j[16] = a;           // 5
      j[17] = b;           // 6
      j[18] = up;          // 7
      j[19] = right;       // 8
      j[20] = down;        // 9
      j[11] = left;        // 0
      j[10] = start;       // Reset
    end
    j[9]  = (pause_cnt != 0) | l2;
    j[10] = j[10] | r2;
  end

  // ---- Analog sticks (Dock controllers with analog support only) ----
  function [7:0] stick;
    input [7:0] v;          // unsigned, 0x80 = centre
    reg   [7:0] s;
    begin
      s = {~v[7], v[6:0]};  // to signed
      if ($signed(s) > -8'sd12 && $signed(s) < 8'sd12) stick = 8'd0;  // dead zone
      else stick = s;
    end
  endfunction

  assign ax = analog ? stick(joy[7:0])   : 8'd0;
  assign ay = analog ? stick(joy[15:8])  : 8'd0;

  assign twin_ax   = analog ? stick(joy[23:16]) : 8'd0;
  assign twin_ay   = analog ? stick(joy[31:24]) : 8'd0;
  assign twin_dirs = (twin & ~shift) ? {x, b, y, a} : 4'd0;

endmodule


module input_map (
    input  wire        clk,
    input  wire [31:0] cont1_key, cont2_key, cont3_key, cont4_key,
    input  wire [31:0] cont1_joy, cont2_joy, cont3_joy, cont4_joy,
    input  wire        swap12,
    input  wire        twin_stick,

    output wire [20:0] joy1, joy2, joy3, joy4,
    output wire [7:0]  joy1x, joy1y, joy2x, joy2y, joy3x, joy3y, joy4x, joy4y
);

  wire [20:0] p1, p2, p3, p4;
  wire [7:0]  p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y;
  wire [3:0]  tdirs;
  wire [7:0]  tax, tay;

  pad_map m1 (.clk(clk), .key(cont1_key), .joy(cont1_joy), .twin(twin_stick),
              .j(p1), .ax(p1x), .ay(p1y), .twin_dirs(tdirs), .twin_ax(tax), .twin_ay(tay));
  pad_map m2 (.clk(clk), .key(cont2_key), .joy(cont2_joy), .twin(1'b0),
              .j(p2), .ax(p2x), .ay(p2y), .twin_dirs(), .twin_ax(), .twin_ay());
  pad_map m3 (.clk(clk), .key(cont3_key), .joy(cont3_joy), .twin(1'b0),
              .j(p3), .ax(p3x), .ay(p3y), .twin_dirs(), .twin_ax(), .twin_ay());
  pad_map m4 (.clk(clk), .key(cont4_key), .joy(cont4_joy), .twin(1'b0),
              .j(p4), .ax(p4x), .ay(p4y), .twin_dirs(), .twin_ax(), .twin_ay());

  // Second stick: controller 2, plus player 1's face buttons in twin mode
  wire [20:0] p2_all = p2 | {17'd0, tdirs[3], tdirs[2], tdirs[1], tdirs[0]};
  wire        twin_analog = twin_stick && (tax != 8'd0 || tay != 8'd0);
  wire [7:0]  p2x_all = twin_analog ? tax : p2x;
  wire [7:0]  p2y_all = twin_analog ? tay : p2y;

  assign joy1  = swap12 ? p2_all  : p1;
  assign joy2  = swap12 ? p1      : p2_all;
  assign joy1x = swap12 ? p2x_all : p1x;
  assign joy1y = swap12 ? p2y_all : p1y;
  assign joy2x = swap12 ? p1x     : p2x_all;
  assign joy2y = swap12 ? p1y     : p2y_all;
  assign joy3  = p3;
  assign joy4  = p4;
  assign joy3x = p3x;
  assign joy3y = p3y;
  assign joy4x = p4x;
  assign joy4y = p4y;

endmodule
