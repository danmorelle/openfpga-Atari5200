#!/usr/bin/env python3
"""Exhaustively compare cart_mem.v's address translation with the layout
MiSTer's ARM loader (support/atari8bit/atari5200.cpp) builds in SDRAM.

For each cart type, a random ROM is generated, the MiSTer layout L[] is
built exactly as atari5200_open_cartridge_file() does, and an iverilog
testbench reads every cartridge address through cart_mem and checks that
it returns L[addr - 0x4000].
"""
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'src', 'fpga', 'core', 'pocket', 'cart_mem.v')
TMP = os.path.join(HERE, 'out', 'mapper')
os.makedirs(TMP, exist_ok=True)


def mister_layout(rom, cart_type):
    """Reproduce atari5200_open_cartridge_file() (offset = 0, raw file)."""
    out = bytearray()
    size = len(rom)
    if cart_type == 0x06:            # two chip: A A B B
        for i in range(4):
            out += rom[(i // 2) * 0x2000:(i // 2) * 0x2000 + 0x2000]
    elif cart_type == 0x10:          # one chip: A B A B
        for i in range(4):
            out += rom[(i % 2) * 0x2000:(i % 2) * 0x2000 + 0x2000]
    elif cart_type in (0x13, 0x14):
        for _ in range(0x8000 // size):
            out += rom
    elif 0x47 <= cart_type <= 0x4A:
        for _ in range(0x80000 // size):
            out += rom
    elif cart_type == 0x07:
        bb1 = rom[0] == 0x2F
        p = 0 if bb1 else 0x2000
        out += rom[p:p + 0x2000]; out += rom[p + 0x2000:p + 0x4000]
        p = 0x8000 if bb1 else 0
        out += rom[p:p + 0x2000]; out += rom[p:p + 0x2000]
        p = 0x4000 if bb1 else 0x6000
        out += rom[p:p + 0x2000]; out += rom[p + 0x2000:p + 0x4000]
    elif cart_type == 0x04:
        out += rom
    return bytes(out)


TB = r'''
`timescale 1ns/1ps
module tb;
  reg clk = 0; always #5 clk = ~clk;
  reg        cart_we = 0; reg [16:0] cart_waddr; reg [7:0] cart_wdata;
  reg [7:0]  cart_type = %(type)d;
  reg        bb_type1 = %(bb1)d;
  reg        mem_request = 0;
  wire       mem_complete;
  reg [24:0] mem_addr;
  wire [7:0] mem_data;
  reg  [7:0] rom [0:131071];
  reg  [7:0] expv [0:524287];
  integer i, errors = 0, n;
  cart_mem dut(.clk_74a(clk), .cart_we(cart_we), .cart_waddr(cart_waddr), .cart_wdata(cart_wdata),
               .bios_we(1'b0), .bios_waddr(11'd0), .bios_wdata(8'd0),
               .clk_sys(clk), .cart_type(cart_type), .bb_type1(bb_type1),
               .mem_request(mem_request), .mem_complete(mem_complete), .mem_addr(mem_addr),
               .mem_data(mem_data), .rom_addr(11'd0), .rom_data());
  initial begin
    $readmemh("%(rom)s", rom);
    $readmemh("%(exp)s", expv);
    for (i = 0; i < %(romsize)d; i = i + 1) begin
      @(posedge clk); cart_we <= 1; cart_waddr <= i; cart_wdata <= rom[i];
    end
    @(posedge clk); cart_we <= 0;
    for (i = 0; i < %(expsize)d; i = i + 1) begin
      @(posedge clk); mem_addr <= 25'h4000 + i; mem_request <= 1;
      @(posedge clk); mem_request <= 0;
      while (!mem_complete) @(posedge clk);
      if (mem_data !== expv[i]) begin
        if (errors < 5) $display("mismatch at L=%%h: got %%h want %%h", i, mem_data, expv[i]);
        errors = errors + 1;
      end
    end
    $display("RESULT %%0d", errors);
    $finish;
  end
endmodule
'''


def run(cart_type, size, bb1=False, seed=1):
    rnd = random.Random(seed)
    rom = bytearray(rnd.getrandbits(8) for _ in range(size))
    if cart_type == 0x07:
        rom[0] = 0x2F if bb1 else 0x00
    lay = mister_layout(bytes(rom), cart_type)
    name = f'{cart_type:02x}_{size}_{int(bb1)}'
    romf = os.path.join(TMP, name + '.rom.hex')
    expf = os.path.join(TMP, name + '.exp.hex')
    open(romf, 'w').write('\n'.join(f'{b:02x}' for b in rom))
    open(expf, 'w').write('\n'.join(f'{b:02x}' for b in lay))
    tbf = os.path.join(TMP, name + '_tb.v')
    open(tbf, 'w').write(TB % dict(type=cart_type, bb1=int(bb1), rom=romf, exp=expf,
                                   romsize=size, expsize=len(lay)))
    exe = os.path.join(TMP, name + '.vvp')
    subprocess.check_call(['iverilog', '-g2012', '-o', exe, tbf, SRC])
    res = subprocess.run(['vvp', '-n', exe], capture_output=True, text=True).stdout
    errs = int(res.strip().split('RESULT ')[-1].split()[0])
    status = 'PASS' if errs == 0 else 'FAIL'
    print(f'{status} type {cart_type:02x} size {size:6d} bb1={int(bb1)}: '
          f'{len(lay)} addresses, {errs} mismatches')
    if errs:
        print(res)
    return errs == 0


ok = True
ok &= run(0x14, 0x1000)
ok &= run(0x13, 0x2000)
ok &= run(0x10, 0x4000)
ok &= run(0x06, 0x4000)
ok &= run(0x04, 0x8000)
ok &= run(0x07, 0xA000, bb1=True)
ok &= run(0x07, 0xA000, bb1=False)
ok &= run(0x47, 0x10000)
ok &= run(0x48, 0x20000)
sys.exit(0 if ok else 1)
