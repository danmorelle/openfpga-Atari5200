//
// Whole-core simulation: loads BIOS + cartridge over the APF bridge,
// runs the Atari and dumps the frames the Pocket scaler would see.
//
// Plusargs:
//   +bios=<file>   +cart=<file>   +frames=<n>   +out=<prefix>
//   +mode16=<0|1|2>   +swap=<0|1>
//   +press=<frame>,<frames>,<keymask hex>   (controller 1, may repeat once)
//

`timescale 1ns/1ps

module tb_top;

  reg clk_74a = 0;
  always #6.734 clk_74a = ~clk_74a;

  reg  [31:0] bridge_addr = 0;
  reg         bridge_rd = 0;
  reg         bridge_wr = 0;
  reg  [31:0] bridge_wr_data = 0;
  wire [31:0] bridge_rd_data;

  reg  [31:0] cont1_key = 32'h1000_0000;   // Pocket built-in controls
  wire [23:0] video_rgb;
  wire        video_rgb_clock, video_rgb_clock_90, video_de, video_skip, video_vs, video_hs;
  wire        audio_mclk, audio_dac, audio_lrck;

  wire [7:0]  cart_tran_bank2, cart_tran_bank3, cart_tran_bank1;
  wire [7:4]  cart_tran_bank0;
  wire        cart_tran_pin30, cart_tran_pin31;
  wire        port_tran_si, port_tran_so, port_tran_sck, port_tran_sd;
  wire [15:0] cram0_dq, cram1_dq, dram_dq, sram_dq;
  wire        aux_sda;

  core_top dut (
    .clk_74a(clk_74a), .clk_74b(clk_74a),
    .cart_tran_bank2(cart_tran_bank2), .cart_tran_bank2_dir(),
    .cart_tran_bank3(cart_tran_bank3), .cart_tran_bank3_dir(),
    .cart_tran_bank1(cart_tran_bank1), .cart_tran_bank1_dir(),
    .cart_tran_bank0(cart_tran_bank0), .cart_tran_bank0_dir(),
    .cart_tran_pin30(cart_tran_pin30), .cart_tran_pin30_dir(), .cart_pin30_pwroff_reset(),
    .cart_tran_pin31(cart_tran_pin31), .cart_tran_pin31_dir(),
    .port_ir_rx(1'b0), .port_ir_tx(), .port_ir_rx_disable(),
    .port_tran_si(port_tran_si), .port_tran_si_dir(),
    .port_tran_so(port_tran_so), .port_tran_so_dir(),
    .port_tran_sck(port_tran_sck), .port_tran_sck_dir(),
    .port_tran_sd(port_tran_sd), .port_tran_sd_dir(),
    .cram0_a(), .cram0_dq(cram0_dq), .cram0_wait(1'b0), .cram0_clk(), .cram0_adv_n(), .cram0_cre(),
    .cram0_ce0_n(), .cram0_ce1_n(), .cram0_oe_n(), .cram0_we_n(), .cram0_ub_n(), .cram0_lb_n(),
    .cram1_a(), .cram1_dq(cram1_dq), .cram1_wait(1'b0), .cram1_clk(), .cram1_adv_n(), .cram1_cre(),
    .cram1_ce0_n(), .cram1_ce1_n(), .cram1_oe_n(), .cram1_we_n(), .cram1_ub_n(), .cram1_lb_n(),
    .dram_a(), .dram_ba(), .dram_dq(dram_dq), .dram_dqm(), .dram_clk(), .dram_cke(),
    .dram_ras_n(), .dram_cas_n(), .dram_we_n(),
    .sram_a(), .sram_dq(sram_dq), .sram_oe_n(), .sram_we_n(), .sram_ub_n(), .sram_lb_n(),
    .vblank(1'b0), .dbg_tx(), .dbg_rx(1'b0), .user1(), .user2(1'b0),
    .aux_sda(aux_sda), .aux_scl(), .vpll_feed(),
    .video_rgb(video_rgb), .video_rgb_clock(video_rgb_clock), .video_rgb_clock_90(video_rgb_clock_90),
    .video_de(video_de), .video_skip(video_skip), .video_vs(video_vs), .video_hs(video_hs),
    .audio_mclk(audio_mclk), .audio_adc(1'b0), .audio_dac(audio_dac), .audio_lrck(audio_lrck),
    .bridge_endian_little(), .bridge_addr(bridge_addr), .bridge_rd(bridge_rd),
    .bridge_rd_data(bridge_rd_data), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
    .cont1_key(cont1_key), .cont2_key(32'h0), .cont3_key(32'h0), .cont4_key(32'h0),
    .cont1_joy(32'h8080_8080), .cont2_joy(32'h0), .cont3_joy(32'h0), .cont4_joy(32'h0),
    .cont1_trig(16'h0), .cont2_trig(16'h0), .cont3_trig(16'h0), .cont4_trig(16'h0)
  );

  // ------------------------------------------------------------------
  // APF bridge helpers
  // ------------------------------------------------------------------
  task automatic bridge_write(input [31:0] addr, input [31:0] data);
    begin
      @(posedge clk_74a);
      bridge_addr    <= addr;
      bridge_wr_data <= data;
      bridge_wr      <= 1;
      @(posedge clk_74a);
      bridge_wr      <= 0;
      repeat (12) @(posedge clk_74a);
    end
  endtask

  task automatic load_file(input string name, input [31:0] base, output int size);
    int fd, c, n;
    reg [31:0] w;
    begin
      fd = $fopen(name, "rb");
      if (fd == 0) begin
        $display("cannot open %s", name);
        $finish;
      end
      n = 0;
      w = 0;
      while (1) begin
        c = $fgetc(fd);
        if (c < 0) break;
        w = {w[23:0], c[7:0]};
        n = n + 1;
        if ((n % 4) == 0) bridge_write(base + n - 4, w);
      end
      if ((n % 4) != 0) begin
        w = w << (8 * (4 - (n % 4)));
        bridge_write(base + (n & ~3), w);
      end
      $fclose(fd);
      size = n;
    end
  endtask

  // ------------------------------------------------------------------
  // Frame capture (what the APF scaler would latch)
  // ------------------------------------------------------------------
  string out_prefix = "out/frame";
  int    frames_to_run = 4;
  int    frame = 0;
  int    line = 0;
  int    x = 0;
  int    maxx = 0;
  int    de_lines = 0;
  int    minw = 9999, maxw = 0;
  int    hs_count = 0;
  bit    line_had_de = 0;
  reg [23:0] fb [0:720*800-1];

  task automatic dump_frame();
    int fd;
    string fname;
    begin
      fname = $sformatf("%s_%03d.ppm", out_prefix, frame);
      fd = $fopen(fname, "wb");
      $fwrite(fd, "P6\n%0d %0d\n255\n", (maxw > 0 ? maxw : 1), (de_lines > 0 ? de_lines : 1));
      for (int yy = 0; yy < (de_lines > 0 ? de_lines : 1); yy++)
        for (int xx = 0; xx < (maxw > 0 ? maxw : 1); xx++) begin
          reg [23:0] p;
          p = fb[yy*800 + xx];
          $fwrite(fd, "%c%c%c", p[23:16], p[15:8], p[7:0]);
        end
      $fclose(fd);
    end
  endtask

  always @(posedge video_rgb_clock) begin
    if (video_vs) begin
      if (de_lines > 0) begin
        $display("[%0t] frame %0d: hs=%0d de_lines=%0d width min=%0d max=%0d",
                 $time, frame, hs_count, de_lines, minw, maxw);
        dump_frame();
        frame = frame + 1;
        if (frame >= frames_to_run) $finish;
      end
      de_lines = 0; minw = 9999; maxw = 0; hs_count = 0; line = 0;
      for (int i = 0; i < 720*800; i++) fb[i] = 0;
    end
    if (video_hs) begin
      if (line_had_de) begin
        if (x < minw) minw = x;
        if (x > maxw) maxw = x;
        de_lines = de_lines + 1;
      end
      hs_count = hs_count + 1;
      x = 0;
      line_had_de = 0;
    end
    if (video_de && !video_skip) begin
      if (x < 800 && de_lines < 720) fb[de_lines*800 + x] = video_rgb;
      x = x + 1;
      line_had_de = 1;
    end
    if (!video_de && video_rgb != 0) $display("[%0t] rgb not zero outside de", $time);
  end

  // ------------------------------------------------------------------
  // APF video protocol checks (bus-communication docs)
  // ------------------------------------------------------------------
  int since_vs = 1000, since_hs = 1000, since_de_fall = 1000, proto_errors = 0;
  bit prev_de = 0, prev_vs_o = 0, prev_hs_o = 0;
  always @(posedge video_rgb_clock) begin
    if (video_vs && prev_vs_o) begin proto_errors++; $display("VS longer than one cycle"); end
    if (video_hs && prev_hs_o) begin proto_errors++; $display("HS longer than one cycle"); end
    if (video_hs && since_vs < 3) begin proto_errors++; $display("HS within 3 cycles of VS"); end
    if (video_de && !prev_de && since_hs < 1) begin proto_errors++; $display("DE right after HS"); end
    if (video_hs && since_de_fall < 1) begin proto_errors++; $display("HS right after DE"); end
    if (video_hs && video_de) begin proto_errors++; $display("HS during DE"); end
    if (video_skip && !video_de) begin proto_errors++; $display("SKIP without DE"); end
    since_vs = video_vs ? 0 : since_vs + 1;
    since_hs = video_hs ? 0 : since_hs + 1;
    since_de_fall = (prev_de && !video_de) ? 0 : since_de_fall + 1;
    prev_de = video_de; prev_vs_o = video_vs; prev_hs_o = video_hs;
  end
  final $display("APF video protocol errors: %0d", proto_errors);

  // ------------------------------------------------------------------
  // Raw video sync polarity report (first frame only)
  // ------------------------------------------------------------------
  int hs_hi = 0, hs_lo = 0, vs_hi = 0, vs_lo = 0, pol_done = 0;
  always @(posedge video_rgb_clock) begin
    if (dut.atari_running && pol_done == 0) begin
      if (dut.vga_hs) hs_hi++; else hs_lo++;
      if (dut.vga_vs) vs_hi++; else vs_lo++;
      if (hs_hi + hs_lo == 2_000_000) begin
        $display("sync duty: hs high %0d low %0d, vs high %0d low %0d", hs_hi, hs_lo, vs_hi, vs_lo);
        pol_done = 1;
      end
    end
  end

  // ------------------------------------------------------------------
  // Audio: record the core's left channel at 48 kHz (16 bit raw)
  // ------------------------------------------------------------------
  int afd = 0;
  int acnt = 0;
  always @(posedge video_rgb_clock) begin
    if (afd != 0 && dut.atari_running) begin
      acnt = acnt + 1;
      if (acnt >= 597) begin
        acnt = 0;
        $fwrite(afd, "%c%c", dut.audio_l[7:0], dut.audio_l[15:8]);
      end
    end
  end

  // ------------------------------------------------------------------
  // Controller presses: +press=<start frame>,<length>,<mask>
  // ------------------------------------------------------------------
  int press_at = -1, press_len = 0;
  reg [31:0] press_mask = 0;
  always @(posedge clk_74a) begin
    if (press_at >= 0 && frame >= press_at && frame < press_at + press_len)
      cont1_key <= 32'h1000_0000 | press_mask;
    else
      cont1_key <= 32'h1000_0000;
  end

  // ------------------------------------------------------------------
  // Settings writes during the run: +poke=<frame>,<addr>,<data> and
  // +poke2=... (addresses/data in hex)
  // ------------------------------------------------------------------
  int poke_at = -1, poke2_at = -1;
  reg [31:0] poke_addr, poke_data, poke2_addr, poke2_data;
  bit poke_done = 0, poke2_done = 0;
  always @(posedge clk_74a) begin
    if (!poke_done && poke_at >= 0 && frame >= poke_at) begin
      poke_done = 1;
      $display("[frame %0d] bridge write %08x = %08x", frame, poke_addr, poke_data);
      bridge_write(poke_addr, poke_data);
    end
    if (!poke2_done && poke2_at >= 0 && frame >= poke2_at) begin
      poke2_done = 1;
      $display("[frame %0d] bridge write %08x = %08x", frame, poke2_addr, poke2_data);
      bridge_write(poke2_addr, poke2_data);
    end
  end

  // ------------------------------------------------------------------
  // Main sequence
  // ------------------------------------------------------------------
  initial begin
    string bios, cart, press;
    int sz, mode16, swap;
    if (!$value$plusargs("bios=%s", bios)) bios = "roms/5200.rom";
    if (!$value$plusargs("cart=%s", cart)) cart = "";
    if (!$value$plusargs("frames=%d", frames_to_run)) frames_to_run = 4;
    if (!$value$plusargs("out=%s", out_prefix)) out_prefix = "out/frame";
    if (!$value$plusargs("mode16=%d", mode16)) mode16 = 0;
    if (!$value$plusargs("swap=%d", swap)) swap = 0;
    if ($value$plusargs("press=%s", press)) begin
      int a, l;
      reg [31:0] m;
      void'($sscanf(press, "%d,%d,%h", a, l, m));
      press_at = a; press_len = l; press_mask = m;
    end
    if ($value$plusargs("poke=%s", press)) begin
      int a; reg [31:0] ad, d;
      void'($sscanf(press, "%d,%h,%h", a, ad, d));
      poke_at = a; poke_addr = ad; poke_data = d;
    end
    if ($value$plusargs("poke2=%s", press)) begin
      int a; reg [31:0] ad, d;
      void'($sscanf(press, "%d,%h,%h", a, ad, d));
      poke2_at = a; poke2_addr = ad; poke2_data = d;
    end
    afd = $fopen({out_prefix, "_audio.raw"}, "wb");

    repeat (200) @(posedge clk_74a);
    // APF: core held in reset while the data slots load
    load_file(bios, 32'h2000_0000, sz);
    $display("BIOS loaded: %0d bytes", sz);
    if (cart != "") begin
      load_file(cart, 32'h1000_0000, sz);
      $display("cart loaded: %0d bytes", sz);
    end
    bridge_write(32'h4000_0004, mode16);
    bridge_write(32'h4000_0008, swap);
    $display("loader: is_car=%0d car_type=%02x size=%0d bb1=%0d vec_hi=%02x votes two=%0d one=%0d -> type %02x",
             dut.ld_is_car, dut.ld_car_type, dut.ld_size, dut.ld_bb_type1, dut.ld_vector_hi,
             dut.ld_votes2, dut.ld_votes1, dut.ld_cart_type);
    // Reset exit
    bridge_write(32'hF8FF_0000, 32'h1);
  end

  // safety timeout
  initial begin
    #2_000_000_000;
    $display("timeout");
    $finish;
  end

endmodule
