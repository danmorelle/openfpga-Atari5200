//
// Clock generation for the Atari 5200 core
//
//   outclk_0  28.636363 MHz  core clock (8 x NTSC colour burst, 16 x 1.79 MHz)
//   outclk_1  28.636363 MHz  same, 90 degrees shifted (APF video_rgb_clock_90)
//
// Reference: clk_74a (74.25 MHz). Fractional PLL, VCO 687.27 MHz.
//
// SPDX-License-Identifier: GPL-2.0-or-later
//

`timescale 1ns/10ps

module pll_atari (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output wire locked
);

  altera_pll #(
      .fractional_vco_multiplier("true"),
      .reference_clock_frequency("74.25 MHz"),
      .operation_mode("direct"),
      .number_of_clocks(2),
      .output_clock_frequency0("28.636363 MHz"),
      .phase_shift0("0 ps"),
      .duty_cycle0(50),
      .output_clock_frequency1("28.636363 MHz"),
      .phase_shift1("8730 ps"),
      .duty_cycle1(50),
      .pll_type("General"),
      .pll_subtype("General")
  ) altera_pll_i (
      .rst     (rst),
      .outclk  ({outclk_1, outclk_0}),
      .locked  (locked),
      .fboutclk(),
      .fbclk   (1'b0),
      .refclk  (refclk)
  );

endmodule
