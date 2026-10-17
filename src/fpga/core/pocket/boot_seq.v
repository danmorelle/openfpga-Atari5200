//
// Boot / cold reset sequence for the Atari 5200 core
//
// Replaces reboot_5200() from the MiSTer ARM code:
//   1. pause the Atari
//   2. fill the 16K of RAM with the FF/00 power-on pattern via DMA
//   3. pulse the Atari reset
//   4. run
//
// SPDX-License-Identifier: GPL-2.0-or-later
//

`default_nettype none

module boot_seq (
    input  wire        clk,
    input  wire        run_ok,       // APF out of reset, data loaded, PLL locked
    input  wire        cold_reset,   // single cycle request (menu action)

    output reg         core_reset_n = 0,
    output reg         pause = 1,
    output reg         atari_reset = 1,

    output reg         dma_req = 0,
    output wire [25:0] dma_addr,
    output wire [7:0]  dma_data,
    input  wire        dma_ready,

    output wire        running
);

  localparam S_OFF   = 3'd0;
  localparam S_WAIT  = 3'd1;
  localparam S_INIT  = 3'd2;
  localparam S_GAP   = 3'd3;
  localparam S_RESET = 3'd4;
  localparam S_RUN   = 3'd5;

  reg [2:0]  state = S_OFF;
  reg [13:0] ram_addr = 0;
  reg [7:0]  count = 0;

  // ATARI_BASE (0x10000) puts the address in the Atari's own 64K map
  assign dma_addr = {9'd0, 1'b1, 2'b00, ram_addr};
  assign dma_data = ram_addr[0] ? 8'h00 : 8'hFF;
  assign running  = (state == S_RUN);

  always @(posedge clk) begin
    if (~run_ok) begin
      state        <= S_OFF;
      core_reset_n <= 0;
      pause        <= 1;
      atari_reset  <= 1;
      dma_req      <= 0;
    end else begin
      case (state)
        S_OFF: begin
          core_reset_n <= 0;
          pause        <= 1;
          atari_reset  <= 1;
          count        <= 0;
          state        <= S_WAIT;
        end

        S_WAIT: begin
          // Let the core come out of reset (paused) before using DMA
          core_reset_n <= 1;
          atari_reset  <= 0;
          pause        <= 1;
          count        <= count + 1'd1;
          if (count == 8'hFF) begin
            ram_addr <= 0;
            dma_req  <= 1;
            state    <= S_INIT;
          end
        end

        S_INIT: begin
          if (dma_ready) begin
            dma_req <= 0;
            if (ram_addr == 14'h3FFF) begin
              count <= 0;
              state <= S_RESET;
            end else begin
              ram_addr <= ram_addr + 1'd1;
              state    <= S_GAP;
            end
          end
        end

        S_GAP: begin
          dma_req <= 1;
          state   <= S_INIT;
        end

        S_RESET: begin
          atari_reset <= 1;
          count       <= count + 1'd1;
          if (count == 8'hFF) begin
            atari_reset <= 0;
            pause       <= 0;
            state       <= S_RUN;
          end
        end

        S_RUN: begin
          if (cold_reset) begin
            pause    <= 1;
            ram_addr <= 0;
            count    <= 0;
            state    <= S_WAIT;
          end
        end

        default: state <= S_OFF;
      endcase
    end
  end

endmodule
