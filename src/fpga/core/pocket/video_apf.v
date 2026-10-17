//
// Atari video -> APF scaler signals
//
// The core runs at 28.636 MHz and produces one pixel every 4 clocks
// (VGA_PIXCE). APF wants exactly one latched pixel per visible pixel, so
// video_de covers the whole active line and video_skip masks the three
// clocks in between pixels.
//
// SPDX-License-Identifier: GPL-2.0-or-later
//

`default_nettype none

module video_apf #(
    parameter HS_ACTIVE_HIGH = 1,
    parameter VS_ACTIVE_HIGH = 1
) (
    input  wire        clk,
    input  wire        enable,       // core running; DE starts at the next frame
    input  wire        pixce,
    input  wire        hsync_in,
    input  wire        vsync_in,
    input  wire        hblank,
    input  wire        vblank,
    input  wire [7:0]  r,
    input  wire [7:0]  g,
    input  wire [7:0]  b,

    output wire [23:0] video_rgb,
    output wire        video_de,
    output wire        video_skip,
    output reg         video_hs = 0,
    output reg         video_vs = 0
);

  wire hs = HS_ACTIVE_HIGH ? hsync_in : ~hsync_in;
  wire vs = VS_ACTIVE_HIGH ? vsync_in : ~vsync_in;

  reg        hs_prev = 0;
  reg        vs_prev = 0;
  reg [3:0]  hs_delay = 0;

  reg        live    = 0;
  reg        cur_de  = 0;
  reg        newpix  = 0;
  reg [23:0] cur_rgb = 0;

  always @(posedge clk) begin
    hs_prev  <= hs;
    vs_prev  <= vs;
    video_hs <= 0;
    video_vs <= 0;

    // VS straight away, HS a few clocks later so it always follows VS
    if (vs & ~vs_prev) video_vs <= 1;

    // Only show pictures from whole frames once the Atari is running
    if (~enable) live <= 0;
    else if (vs & ~vs_prev) live <= 1;

    if (hs & ~hs_prev) hs_delay <= 4'd8;
    else if (hs_delay != 0) begin
      hs_delay <= hs_delay - 1'd1;
      if (hs_delay == 4'd1) video_hs <= 1;
    end

    newpix <= 0;
    if (pixce) begin
      cur_de  <= live & ~(hblank | vblank);
      cur_rgb <= {r, g, b};
      newpix  <= 1;
    end
  end

  assign video_de   = cur_de;
  assign video_skip = cur_de & ~newpix;
  assign video_rgb  = cur_de ? cur_rgb : 24'd0;

endmodule
