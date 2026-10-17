//
// Audio for the Pocket: low-pass filter, clock crossing and I2S output
//
// The POKEY output changes at up to 1.79 MHz. Before it is sampled at
// 48 kHz it goes through two first order low-pass stages (~18 kHz each)
// to keep the high pitched square waves from aliasing.
//
// The I2S generator follows Analogue's reference design (and Adam
// Gastineau's sound_i2s, MIT licence): MCLK 12.288 MHz, SCLK 3.072 MHz,
// 16 bit signed samples, LRCK low = left.
//
// SPDX-License-Identifier: GPL-2.0-or-later
//

`default_nettype none

module audio_apf (
    input  wire        clk_sys,      // 28.636 MHz
    input  wire        mute,
    input  wire [15:0] audio_l,      // signed
    input  wire [15:0] audio_r,

    input  wire        clk_74a,
    output reg         audio_mclk = 0,
    output reg         audio_lrck = 0,
    output reg         audio_dac  = 0
);

  // -------------------------------------------------------------------
  // Filter (clk_sys domain), updated at 1.79 MHz
  // -------------------------------------------------------------------
  reg  [3:0]  div = 0;
  // 16.4 fixed point, one extra bit so the differences cannot overflow
  reg  signed [20:0] l1 = 0, l2 = 0, r1 = 0, r2 = 0;

  wire signed [20:0] in_l = mute ? 21'sd0 : {audio_l[15], audio_l, 4'd0};
  wire signed [20:0] in_r = mute ? 21'sd0 : {audio_r[15], audio_r, 4'd0};

  always @(posedge clk_sys) begin
    div <= div + 1'd1;
    if (div == 0) begin
      l1 <= l1 + ((in_l - l1) >>> 4);
      r1 <= r1 + ((in_r - r1) >>> 4);
      l2 <= l2 + ((l1 - l2) >>> 4);
      r2 <= r2 + ((r1 - r2) >>> 4);
    end
  end

  // Hand a fresh sample to the 74 MHz domain roughly every 10 us
  reg  [8:0]  hold_cnt = 0;
  reg  [31:0] hold = 0;
  reg         hold_toggle = 0;

  always @(posedge clk_sys) begin
    hold_cnt <= hold_cnt + 1'd1;
    if (hold_cnt == 9'd297) begin
      hold_cnt    <= 0;
      hold        <= {r2[19:4], l2[19:4]};   // right in [31:16], left in [15:0]
                                             // (values stay within 16 bits)
      hold_toggle <= ~hold_toggle;
    end
  end

  // -------------------------------------------------------------------
  // Clock crossing: 'hold' is stable for ~300 clk_sys cycles after the
  // toggle changes, so it can be captured once the toggle is synced.
  // -------------------------------------------------------------------
  reg [2:0]  tog_s = 0;
  reg [31:0] sample = 0;

  always @(posedge clk_74a) begin
    tog_s <= {tog_s[1:0], hold_toggle};
    if (tog_s[2] != tog_s[1]) sample <= hold;
  end

  // -------------------------------------------------------------------
  // I2S (clk_74a domain)
  // -------------------------------------------------------------------
  reg [21:0] accum = 0;
  localparam [20:0] CYCLE_48KHZ = 21'd122880 * 2;

  always @(posedge clk_74a) begin
    accum <= accum + CYCLE_48KHZ;
    if (accum >= 21'd742500) begin
      audio_mclk <= ~audio_mclk;
      accum      <= accum - 21'd742500 + CYCLE_48KHZ;
    end
  end

  reg [1:0]  mclk_div = 0;
  reg        prev_mclk = 0;
  wire       sclk = mclk_div[1];
  reg        prev_sclk = 0;
  reg [4:0]  lrck_cnt = 0;
  reg [31:0] shift = 0;

  always @(posedge clk_74a) begin
    prev_mclk <= audio_mclk;
    if (audio_mclk & ~prev_mclk) mclk_div <= mclk_div + 1'd1;

    prev_sclk <= sclk;
    if (prev_sclk & ~sclk) begin
      audio_dac <= shift[31];
      lrck_cnt  <= lrck_cnt + 1'd1;
      if (lrck_cnt == 5'd31) begin
        audio_lrck <= ~audio_lrck;
        if (~audio_lrck) shift <= sample;
      end else if (lrck_cnt < 5'd16) begin
        shift <= {shift[30:0], 1'b0};
      end
    end
  end

endmodule
