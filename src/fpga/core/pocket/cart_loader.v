//
// Atari 5200 cartridge / BIOS loader for the Analogue Pocket
//
// Receives data slot writes from the APF bridge (clk_74a domain) and
// stores them byte by byte in block RAM. While the file streams in it
// works out everything the MiSTer ARM code used to do in software:
//
//   * whether the file has a 16 byte CAR header (and its cart type)
//   * the size of the ROM data
//   * Bounty Bob layout flag (first ROM byte == 0x2F)
//   * a one-chip / two-chip guess for 16K carts, by looking at where
//     JMP/JSR instructions in the first 8K point to
//
// The ROM data is stored without the CAR header, starting at address 0.
//
// SPDX-License-Identifier: GPL-2.0-or-later
//

`default_nettype none

module cart_loader (
    input  wire        clk_74a,
    input  wire        reset_n,        // APF reset (low while loading starts)

    input  wire        bridge_wr,
    input  wire [31:0] bridge_addr,
    input  wire [31:0] bridge_wr_data,

    // Cartridge RAM write port (clk_74a domain)
    output reg         cart_we,
    output reg  [16:0] cart_waddr,
    output reg  [7:0]  cart_wdata,

    // BIOS RAM write port (clk_74a domain)
    output reg         bios_we,
    output reg  [10:0] bios_waddr,
    output reg  [7:0]  bios_wdata,

    // Results (stable once loading has finished)
    output reg         is_car,
    output reg  [7:0]  car_type,
    output reg  [19:0] data_size,      // bytes of ROM data (header excluded)
    output reg         bb_type1,
    output reg  [7:0]  vector_hi,      // file byte 0x3FFF (start vector high byte)
    output reg  [11:0] votes_two_chip,
    output reg  [11:0] votes_one_chip
);

  localparam [3:0] REGION_CART = 4'h1;
  localparam [3:0] REGION_BIOS = 4'h2;

  reg        prev_wr = 0;
  reg [31:0] word;
  reg [27:0] base;
  reg [3:0]  region;
  reg [2:0]  byte_idx;
  reg        busy = 0;

  // Byte currently being processed
  wire [7:0]  cur_byte = word[31:24];
  wire [27:0] cur_off  = base + byte_idx;

  // Header bytes 0..3 are kept to recognise "CART"
  reg [7:0] hdr0, hdr1, hdr2;

  // Two previous data bytes for the opcode scan
  reg [7:0] prev1, prev2;

  // Data offset of the current byte (header removed)
  wire        in_header = is_car && (cur_off < 28'd16);
  wire [27:0] data_off  = is_car ? (cur_off - 28'd16) : cur_off;

  // APF holds the core in reset while it loads the data slots, so the
  // results are cleared only on the falling edge of reset_n.
  reg prev_reset_n = 1;

  always @(posedge clk_74a) begin
    prev_wr <= bridge_wr;
    prev_reset_n <= reset_n;
    cart_we <= 0;
    bios_we <= 0;

    if (prev_reset_n && ~reset_n) begin
      // A new load is about to start
      busy           <= 0;
      is_car         <= 0;
      car_type       <= 0;
      data_size      <= 0;
      bb_type1       <= 0;
      vector_hi      <= 0;
      votes_two_chip <= 0;
      votes_one_chip <= 0;
      prev1          <= 0;
      prev2          <= 0;
    end

    if (bridge_wr && ~prev_wr &&
        (bridge_addr[31:28] == REGION_CART || bridge_addr[31:28] == REGION_BIOS)) begin
      // APF delivers file bytes big endian: first byte in [31:24]
      word     <= bridge_wr_data;
      base     <= bridge_addr[27:0];
      region   <= bridge_addr[31:28];
      byte_idx <= 0;
      busy     <= 1;
    end else if (busy) begin
      word     <= {word[23:0], 8'h00};
      byte_idx <= byte_idx + 1'd1;
      if (byte_idx == 3'd3) busy <= 0;

      if (region == REGION_BIOS) begin
        if (cur_off < 28'd2048) begin
          bios_we    <= 1;
          bios_waddr <= cur_off[10:0];
          bios_wdata <= cur_byte;
        end
      end else begin
        // ---- header detection ----
        if (cur_off == 28'd0) hdr0 <= cur_byte;
        if (cur_off == 28'd1) hdr1 <= cur_byte;
        if (cur_off == 28'd2) hdr2 <= cur_byte;
        if (cur_off == 28'd3)
          is_car <= (hdr0 == "C") && (hdr1 == "A") && (hdr2 == "R") && (cur_byte == "T");
        if (is_car && cur_off == 28'd7) car_type <= cur_byte;

        // ---- store ROM data ----
        // Bytes 0..15 of a CAR file are written to 0..15 at first and are
        // overwritten later by the real data, so no special case is needed.
        if (!in_header && data_off < 28'h20000) begin
          cart_we    <= 1;
          cart_waddr <= data_off[16:0];
          cart_wdata <= cur_byte;
        end

        if (!in_header) begin
          if (data_off + 1'd1 > data_size) data_size <= data_off[19:0] + 1'd1;

          if (data_off == 28'd0)     bb_type1  <= (cur_byte == 8'h2F);
          if (data_off == 28'h3FFF)  vector_hi <= cur_byte;

          // Opcode scan over the first 8K: JSR abs (20) / JMP abs (4C)
          if (data_off < 28'h2000 && data_off >= 28'd2 &&
              (prev2 == 8'h20 || prev2 == 8'h4C)) begin
            if (cur_byte >= 8'h40 && cur_byte <= 8'h7F && votes_two_chip != 12'hFFF)
              votes_two_chip <= votes_two_chip + 1'd1;
            if (cur_byte >= 8'h80 && cur_byte <= 8'h9F && votes_one_chip != 12'hFFF)
              votes_one_chip <= votes_one_chip + 1'd1;
          end
          prev2 <= prev1;
          prev1 <= cur_byte;
        end
      end
    end
  end

endmodule

//
// Pick the MiSTer cartridge type code from what the loader found.
//
module cart_type_select (
    input  wire        is_car,
    input  wire [7:0]  car_type,
    input  wire [19:0] data_size,
    input  wire [7:0]  vector_hi,
    input  wire [11:0] votes_two_chip,
    input  wire [11:0] votes_one_chip,
    input  wire [1:0]  mode16,        // 0 auto, 1 one chip, 2 two chip
    output reg  [7:0]  cart_type
);

  wire guess_two_chip = (vector_hi >= 8'h40 && vector_hi <= 8'h7F) ||
                        (votes_two_chip > votes_one_chip);

  wire [7:0] type16 = (mode16 == 2'd1) ? 8'h10 :
                      (mode16 == 2'd2) ? 8'h06 :
                      guess_two_chip   ? 8'h06 : 8'h10;

  reg [7:0] by_size;
  always @(*) begin
    if (data_size == 0)              by_size = 8'h00;  // no cartridge
    else if (data_size <= 20'h01000) by_size = 8'h14;  // 4K
    else if (data_size <= 20'h02000) by_size = 8'h13;  // 8K
    else if (data_size <= 20'h04000) by_size = type16; // 16K one/two chip
    else if (data_size <= 20'h08000) by_size = 8'h04;  // 32K
    else if (data_size <= 20'h0A000) by_size = 8'h07;  // 40K Bounty Bob
    else if (data_size <= 20'h10000) by_size = 8'h47;  // 64K super cart
    else                             by_size = 8'h48;  // 128K super cart
  end

  always @(*) begin
    cart_type = by_size;
    if (is_car) begin
      case (car_type)
        8'h04, 8'h06, 8'h07, 8'h10, 8'h13, 8'h14,
        8'h47, 8'h48, 8'h49, 8'h4A: cart_type = car_type;
        default: cart_type = by_size;
      endcase
    end
  end

endmodule
