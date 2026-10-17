//
// Simulation stand-ins for Intel IP and the APF command handler
//

`timescale 1ns/1ps

// PLL: free running clocks at the requested frequency (28.636363 MHz)
module pll_atari (
    input  wire refclk,
    input  wire rst,
    output reg  outclk_0 = 0,
    output reg  outclk_1 = 0,
    output reg  locked = 0
);
  initial begin
    #1000 locked = 1;
  end
  always #17.4603 outclk_0 = ~outclk_0;
  initial begin
    #8.7302;
    forever #17.4603 outclk_1 = ~outclk_1;
  end
endmodule

// Minimal APF host command handler: the testbench controls reset_n by
// writing to 0xF8FF0000 over the bridge.
module core_bridge_cmd (
    input  wire        clk,
    output reg         reset_n = 0,
    input  wire        bridge_endian_little,
    input  wire [31:0] bridge_addr,
    input  wire        bridge_rd,
    output wire [31:0] bridge_rd_data,
    input  wire        bridge_wr,
    input  wire [31:0] bridge_wr_data,
    input  wire        status_boot_done,
    input  wire        status_setup_done,
    input  wire        status_running,
    output wire        dataslot_requestread,
    output wire [15:0] dataslot_requestread_id,
    input  wire        dataslot_requestread_ack,
    input  wire        dataslot_requestread_ok,
    output wire        dataslot_requestwrite,
    output wire [15:0] dataslot_requestwrite_id,
    output wire [31:0] dataslot_requestwrite_size,
    input  wire        dataslot_requestwrite_ack,
    input  wire        dataslot_requestwrite_ok,
    output wire        dataslot_update,
    output wire [15:0] dataslot_update_id,
    output wire [31:0] dataslot_update_size,
    output wire        dataslot_allcomplete,
    output wire [31:0] rtc_epoch_seconds,
    output wire [31:0] rtc_date_bcd,
    output wire [31:0] rtc_time_bcd,
    output wire        rtc_valid,
    input  wire        savestate_supported,
    input  wire [31:0] savestate_addr,
    input  wire [31:0] savestate_size,
    input  wire [31:0] savestate_maxloadsize,
    output wire        savestate_start,
    input  wire        savestate_start_ack,
    input  wire        savestate_start_busy,
    input  wire        savestate_start_ok,
    input  wire        savestate_start_err,
    output wire        savestate_load,
    input  wire        savestate_load_ack,
    input  wire        savestate_load_busy,
    input  wire        savestate_load_ok,
    input  wire        savestate_load_err,
    output wire        osnotify_inmenu,
    input  wire        target_dataslot_read,
    input  wire        target_dataslot_write,
    input  wire        target_dataslot_getfile,
    input  wire        target_dataslot_openfile,
    output wire        target_dataslot_ack,
    output wire        target_dataslot_done,
    output wire [2:0]  target_dataslot_err,
    input  wire [15:0] target_dataslot_id,
    input  wire [31:0] target_dataslot_slotoffset,
    input  wire [31:0] target_dataslot_bridgeaddr,
    input  wire [31:0] target_dataslot_length,
    input  wire [31:0] target_buffer_param_struct,
    input  wire [31:0] target_buffer_resp_struct,
    output wire [9:0]  datatable_addr,
    output wire        datatable_wren,
    output wire [31:0] datatable_data,
    input  wire [31:0] datatable_q
);
  always @(posedge clk)
    if (bridge_wr && bridge_addr == 32'hF8FF0000) reset_n <= bridge_wr_data[0];

  assign bridge_rd_data = 0;
  assign dataslot_requestread = 0;
  assign dataslot_requestread_id = 0;
  assign dataslot_requestwrite = 0;
  assign dataslot_requestwrite_id = 0;
  assign dataslot_requestwrite_size = 0;
  assign dataslot_update = 0;
  assign dataslot_update_id = 0;
  assign dataslot_update_size = 0;
  assign dataslot_allcomplete = 1;
  assign rtc_epoch_seconds = 0;
  assign rtc_date_bcd = 0;
  assign rtc_time_bcd = 0;
  assign rtc_valid = 0;
  assign savestate_start = 0;
  assign savestate_load = 0;
  assign osnotify_inmenu = 0;
  assign target_dataslot_ack = 0;
  assign target_dataslot_done = 0;
  assign target_dataslot_err = 0;
  assign datatable_addr = 0;
  assign datatable_wren = 0;
  assign datatable_data = 0;
endmodule
