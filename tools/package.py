#!/usr/bin/env python3
"""Turn the Quartus output into an SD card folder for the Analogue Pocket.

The Pocket loads bitstreams with the bit order of every byte reversed
(.rbf_r). The result goes to release/sd/, ready to copy onto the root of
the SD card.
"""
import glob
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RBF = os.path.join(ROOT, 'src', 'fpga', 'output_files', 'ap_core.rbf')
DIST = os.path.join(ROOT, 'dist')
OUT = os.path.join(ROOT, 'release', 'sd')

REVERSE = bytes(int(f'{i:08b}'[::-1], 2) for i in range(256))


def main():
    rbf = sys.argv[1] if len(sys.argv) > 1 else RBF
    data = open(rbf, 'rb').read()
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    shutil.copytree(DIST, OUT)
    cores = glob.glob(os.path.join(OUT, 'Cores', '*'))
    if len(cores) != 1:
        sys.exit(f'expected one core folder, found {cores}')
    target = os.path.join(cores[0], 'bitstream.rbf_r')
    open(target, 'wb').write(data.translate(REVERSE))
    print(f'{rbf}: {len(data)} bytes -> {os.path.relpath(target, ROOT)}')


if __name__ == '__main__':
    main()
