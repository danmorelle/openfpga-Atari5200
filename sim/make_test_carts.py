#!/usr/bin/env python3
"""Build small Atari 5200 test cartridges for the simulation.

Each cart sets up a display list of four vertical colour bars (ANTIC
mode E), starts a POKEY tone, and turns the background red while fire 1
is held. The layouts are chosen so that a wrong cartridge mapping gives a
wrong picture.
"""
import os
import struct

OUT = os.path.join(os.path.dirname(__file__), 'roms')

COLPF0, COLPF1, COLPF2, COLBK = 0xC016, 0xC017, 0xC018, 0xC01A
TRIG0 = 0xC010
DMACTL, DLISTL, DLISTH, NMIEN = 0xD400, 0xD402, 0xD403, 0xD40E
AUDF1, AUDC1, AUDCTL, SKCTL = 0xE800, 0xE801, 0xE808, 0xE80F


class Asm:
    def __init__(self, org):
        self.org = org
        self.b = bytearray()

    @property
    def pc(self):
        return self.org + len(self.b)

    def emit(self, *bs):
        self.b += bytes(bs)

    def lda_i(self, v): self.emit(0xA9, v & 0xFF)
    def ldx_i(self, v): self.emit(0xA2, v & 0xFF)
    def sta(self, a): self.emit(0x8D, a & 0xFF, a >> 8)
    def lda(self, a): self.emit(0xAD, a & 0xFF, a >> 8)
    def jmp(self, a): self.emit(0x4C, a & 0xFF, a >> 8)
    def bne(self, target):
        off = target - (self.pc + 2)
        self.emit(0xD0, off & 0xFF)
    def beq(self, target):
        off = target - (self.pc + 2)
        self.emit(0xF0, off & 0xFF)


def program(org, dl_addr):
    a = Asm(org)
    a.emit(0x78)            # SEI
    a.emit(0xD8)            # CLD
    a.ldx_i(0xFF); a.emit(0x9A)   # TXS
    a.lda_i(0); a.sta(NMIEN); a.sta(DMACTL)
    a.lda_i(0x94); a.sta(COLBK)   # blue
    a.lda_i(0x28); a.sta(COLPF0)  # orange
    a.lda_i(0xC8); a.sta(COLPF1)  # green
    a.lda_i(0x0E); a.sta(COLPF2)  # white
    a.lda_i(dl_addr & 0xFF); a.sta(DLISTL)
    a.lda_i(dl_addr >> 8); a.sta(DLISTH)
    a.lda_i(0x22); a.sta(DMACTL)
    a.lda_i(3); a.sta(SKCTL)
    a.lda_i(0); a.sta(AUDCTL)
    a.lda_i(0x50); a.sta(AUDF1)
    a.lda_i(0xA8); a.sta(AUDC1)
    loop = a.pc
    a.lda(TRIG0)                  # 0 = fire pressed
    skip = None
    # if pressed -> red, else blue
    a.bne(loop + 3 + 2 + 2 + 3 + 3)   # to 'blue'
    a.lda_i(0x34); a.sta(COLBK); a.jmp(loop)
    blue = a.pc
    a.lda_i(0x94); a.sta(COLBK); a.jmp(loop)
    assert blue == loop + 3 + 2 + 2 + 3 + 3, hex(blue)
    return bytes(a.b)


def display_list(dl_addr, row_addr):
    d = bytearray([0x70, 0x70, 0x70])
    for _ in range(192):
        d += bytes([0x4E, row_addr & 0xFF, row_addr >> 8])
    d += bytes([0x41, dl_addr & 0xFF, dl_addr >> 8])
    return bytes(d)


ROW = bytes([0x00] * 10 + [0x55] * 10 + [0xAA] * 10 + [0xFF] * 10)


def header(start):
    title = bytes(range(0x21, 0x21 + 20))
    return title + bytes([0x00, 0xFF]) + struct.pack('<H', start)   # $BFE8..$BFFF ($BFFD=FF skips the logo)


def put(img, off, data):
    img[off:off + len(data)] = data


def cart(size, layout):
    """layout: list of (file offset, bytes)"""
    img = bytearray(size)
    for off, data in layout:
        put(img, off, data)
    return bytes(img)


carts = {}

# 32K: file 0 = $4000. DL at $4000, row at $4300, code at $A000, header $BFE8
carts['test32.a52'] = cart(0x8000, [
    (0x0000, display_list(0x4000, 0x4300)),
    (0x0300, ROW),
    (0x6000, program(0xA000, 0x4000)),
    (0x7FE8, header(0xA000)),
])

# 16K two chip: chip A (file 0-8K) at $4000 and $6000, chip B at $8000/$A000.
# Code in chip A at $4000, DL in chip A seen through the $6000 mirror.
carts['test16two.a52'] = cart(0x4000, [
    (0x0000, program(0x4000, 0x6400)),
    (0x0400, display_list(0x6400, 0x6700)),
    (0x0700, ROW),
    (0x3FE8, header(0x4000)),
])

# 16K one chip: file 0 = $8000 (mirrored at $4000). Code at $8000,
# DL at $9100 (file 0x1100; a two chip mapping would read file 0x3100).
carts['test16one.a52'] = cart(0x4000, [
    (0x0000, program(0x8000, 0x9100)),
    (0x1100, display_list(0x9100, 0x9400)),
    (0x1400, ROW),
    (0x3FE8, header(0x8000)),
])

# 8K: mirrored everywhere, file 0 = $A000
carts['test8.a52'] = cart(0x2000, [
    (0x0000, program(0xA000, 0xA400)),
    (0x0400, display_list(0xA400, 0xA700)),
    (0x0700, ROW),
    (0x1FE8, header(0xA000)),
])

# 4K: mirrored every 4K, file 0 = $B000
carts['test4.a52'] = cart(0x1000, [
    (0x0000, program(0xB000, 0xB400)),
    (0x0400, display_list(0xB400, 0xB700)),
    (0x0700, ROW),
    (0x0FE8, header(0xB000)),
])

# CAR file: 16 byte header + the 32K cart, type 4
car_hdr = b'CART' + struct.pack('>I', 4) + struct.pack('>I', 0) + b'\0\0\0\0'
carts['test32.car'] = car_hdr + carts['test32.a52']

# Same 16K two chip cart wrapped as CAR type 6
car_hdr6 = b'CART' + struct.pack('>I', 6) + struct.pack('>I', 0) + b'\0\0\0\0'
carts['test16two.car'] = car_hdr6 + carts['test16two.a52']

os.makedirs(OUT, exist_ok=True)
for name, data in carts.items():
    open(os.path.join(OUT, name), 'wb').write(data)
    print(f'{name}: {len(data)} bytes')
