// Unit test for input_map: button combinations -> 5200 controller bits
`timescale 1ns/1ps
module input_test;
  reg clk = 0; always #5 clk = ~clk;
  reg  [31:0] k1 = 32'h1000_0000, k2 = 0, j1 = 32'h8080_8080;
  reg         swap = 0, twin = 0;
  wire [20:0] joy1, joy2, joy3, joy4;
  wire [7:0]  joy1x, joy1y, joy2x, joy2y, joy3x, joy3y, joy4x, joy4y;
  integer errors = 0;

  input_map #() dut (.clk(clk), .cont1_key(k1), .cont2_key(k2), .cont3_key(32'd0), .cont4_key(32'd0),
                 .cont1_joy(j1), .cont2_joy(32'd0), .cont3_joy(32'd0), .cont4_joy(32'd0),
                 .swap12(swap), .twin_stick(twin),
                 .joy1(joy1), .joy2(joy2), .joy3(joy3), .joy4(joy4),
                 .joy1x(joy1x), .joy1y(joy1y), .joy2x(joy2x), .joy2y(joy2y),
                 .joy3x(joy3x), .joy3y(joy3y), .joy4x(joy4x), .joy4y(joy4y));
  defparam dut.m1.PAUSE_CYCLES = 22'd20;

  // Pocket key bits
  localparam UP=0, DOWN=1, LEFT=2, RIGHT=3, A=4, B=5, X=6, Y=7, L=8, R=9, L2=10, R2=11, SEL=14, START=15;
  // 5200 bits
  localparam J_R=0, J_L=1, J_D=2, J_U=3, F1=4, F2=5, STAR=6, HASH=7, J_START=8, PAUSE=9, RESET=10;
  function [20:0] kp(input integer n); kp = 21'd1 << (11 + n); endfunction

  task press(input [31:0] keys, input [20:0] want, input string what);
    begin
      k1 = 32'h1000_0000 | keys;
      repeat (3) @(posedge clk);
      if (joy1 !== want) begin
        $display("FAIL %s: got %b want %b", what, joy1, want); errors = errors + 1;
      end else $display("ok   %s", what);
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    press(1<<UP,              1<<J_U,      "up");
    press(1<<RIGHT,           1<<J_R,      "right");
    press(1<<A,               1<<F1,       "A = fire 1");
    press(1<<B,               1<<F2,       "B = fire 2");
    press(1<<X,               kp(1),       "X = 1");
    press(1<<Y,               kp(2),       "Y = 2");
    press(1<<L,               1<<STAR,     "L = *");
    press(1<<R,               1<<HASH,     "R = #");
    press(1<<START,           1<<J_START,  "Start");
    press((1<<SEL),           0,           "Select held alone: nothing yet");
    press((1<<SEL)|(1<<X),    kp(3),       "Select+X = 3");
    press((1<<SEL)|(1<<Y),    kp(4),       "Select+Y = 4");
    press((1<<SEL)|(1<<A),    kp(5),       "Select+A = 5 (no fire)");
    press((1<<SEL)|(1<<B),    kp(6),       "Select+B = 6 (no fire)");
    press((1<<SEL)|(1<<UP),   kp(7),       "Select+Up = 7 (no stick)");
    press((1<<SEL)|(1<<RIGHT),kp(8),       "Select+Right = 8");
    press((1<<SEL)|(1<<DOWN), kp(9),       "Select+Down = 9");
    press((1<<SEL)|(1<<LEFT), kp(0),       "Select+Left = 0");
    press((1<<SEL)|(1<<START),1<<RESET,    "Select+Start = Reset");
    // releasing Select after a combo must not send Pause
    press(0,                  0,           "release after combo: no pause");
    // tapping Select alone sends Pause for PAUSE_CYCLES
    press(1<<SEL,             0,           "tap select (down)");
    press(0,                  1<<PAUSE,    "tap select (up) = Pause");
    repeat (25) @(posedge clk);
    press(0,                  0,           "pause released after timeout");
    press(1<<L2,              1<<PAUSE,    "Dock L2 = Pause");
    press(1<<R2,              1<<RESET,    "Dock R2 = Reset");
    // twin stick: face buttons drive joystick 2, not fire / keypad
    twin = 1;
    press((1<<X)|(1<<A),      0,           "twin: X/A not fire or keypad on joy1");
    if (joy2 !== ((1<<J_U)|(1<<J_R))) begin $display("FAIL twin joy2 %b", joy2); errors++; end
    else $display("ok   twin: X=up A=right on joy2");
    twin = 0;
    // swap
    swap = 1;
    press(1<<A, 0, "swap: P1 buttons leave joy1");
    if (joy2 !== (1<<F1)) begin $display("FAIL swap joy2 %b", joy2); errors++; end
    else $display("ok   swap: P1 fire appears on joy2");
    swap = 0;
    // analog only for Dock analog controllers (type 3)
    j1 = 32'h0000_F010;
    k1 = 32'h1000_0000; repeat (3) @(posedge clk);
    if (joy1x !== 8'd0 || joy1y !== 8'd0) begin $display("FAIL analog used on Pocket controls"); errors++; end
    else $display("ok   no analog from Pocket built-in controls");
    k1 = 32'h3000_0000; repeat (3) @(posedge clk);
    if (joy1x !== 8'h90 || joy1y !== 8'h70) begin $display("FAIL analog %h %h", joy1x, joy1y); errors++; end
    else $display("ok   Dock analog stick: x=%0d y=%0d", $signed(joy1x), $signed(joy1y));
    j1 = 32'h0000_8584;   // inside the dead zone
    repeat (3) @(posedge clk);
    if (joy1x !== 8'd0 || joy1y !== 8'd0) begin $display("FAIL dead zone"); errors++; end
    else $display("ok   dead zone");
    $display("input_map errors: %0d", errors);
    $finish;
  end
endmodule
