//
// Atari 5200 cartridge memory for the Analogue Pocket
//
// Serves the core's "SDRAM" requests for the cartridge area from block
// RAM. On MiSTer, the ARM processor copied each cartridge into SDRAM with
// type specific mirroring. Here the ROM is stored once, exactly as it is
// in the file, and the mirroring is done by translating addresses.
//
// Core address map (SDRAM_ADDR, see address_decoder.vhdl, system 10):
//   0x04000 + L   cartridge byte L of the MiSTer layout
//   L runs to 0x7FFF (standard), 0xBFFF (Bounty Bob) or 0x7FFFF (super cart)
//
// SPDX-License-Identifier: GPL-2.0-or-later
//

`default_nettype none

module cart_mem (
    // Write side (APF loader)
    input  wire        clk_74a,
    input  wire        cart_we,
    input  wire [16:0] cart_waddr,
    input  wire [7:0]  cart_wdata,
    input  wire        bios_we,
    input  wire [10:0] bios_waddr,
    input  wire [7:0]  bios_wdata,

    // Read side (core)
    input  wire        clk_sys,
    input  wire [7:0]  cart_type,
    input  wire        bb_type1,

    input  wire        mem_request,
    output wire        mem_complete,
    input  wire [24:0] mem_addr,
    output reg  [7:0]  mem_data,

    input  wire [10:0] rom_addr,
    output reg  [7:0]  rom_data
);

  // ---------------------------------------------------------------------
  // Block RAMs (simple dual port, separate clocks)
  // ---------------------------------------------------------------------
  reg [7:0] cart_ram[0:131071];
  reg [7:0] bios_ram[0:2047];

  always @(posedge clk_74a) begin
    if (cart_we) cart_ram[cart_waddr] <= cart_wdata;
    if (bios_we) bios_ram[bios_waddr] <= bios_wdata;
  end

  always @(posedge clk_sys) begin
    rom_data <= bios_ram[rom_addr];
  end

  // ---------------------------------------------------------------------
  // Address translation
  // ---------------------------------------------------------------------
  wire [19:0] L = mem_addr[19:0] - 20'h04000;
  wire in_cart = (mem_addr[24:20] == 5'd0) && (mem_addr[19:0] >= 20'h04000) &&
                 (cart_type != 8'h00);

  reg [16:0] off;
  always @(*) begin
    case (cart_type)
      8'h14:   off = {5'd0, L[11:0]};               // 4K
      8'h13:   off = {4'd0, L[12:0]};               // 8K
      8'h10:   off = {3'd0, L[13:0]};               // 16K one chip  (A B A B)
      8'h06:   off = {3'd0, L[14], L[12:0]};        // 16K two chip  (A A B B)
      8'h04:   off = {2'd0, L[14:0]};               // 32K
      8'h07: begin                                  // 40K Bounty Bob
        if (bb_type1) begin
          if (L < 20'h04000)      off = L[16:0];
          else if (L < 20'h08000) off = {4'b0100, L[12:0]};       // 0x8000 + (L & 0x1FFF)
          else                    off = L[16:0] - 17'h04000;
        end else begin
          if (L < 20'h04000)      off = L[16:0] + 17'h02000;
          else if (L < 20'h08000) off = {4'b0000, L[12:0]};
          else                    off = L[16:0] - 17'h02000;
        end
      end
      8'h47:   off = {1'b0, L[15:0]};               // 64K super cart
      default: off = L[16:0];                       // 128K super cart (and larger, truncated)
    endcase
  end

  // ---------------------------------------------------------------------
  // Request / complete handshake (same semantics as sdram_statemachine:
  // COMPLETE is low from the request cycle until the data is ready)
  // ---------------------------------------------------------------------
  reg [16:0] rd_addr;
  reg        rd_cart;
  reg [1:0]  busy = 0;
  reg [7:0]  cart_q;

  assign mem_complete = (busy == 2'd0) && ~mem_request;

  always @(posedge clk_sys) begin
    cart_q <= cart_ram[rd_addr];

    case (busy)
      2'd0: if (mem_request) begin
        rd_addr <= off;
        rd_cart <= in_cart;
        busy    <= 2'd1;
      end
      2'd1: busy <= 2'd2;            // RAM is reading rd_addr
      2'd2: begin
        mem_data <= rd_cart ? cart_q : 8'hFF;
        busy     <= 2'd0;
      end
      default: busy <= 2'd0;
    endcase
  end

endmodule
