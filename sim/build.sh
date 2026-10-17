#!/bin/bash
# Build the whole-core simulation (GHDL converts the VHDL core to Verilog,
# Verilator simulates everything together).
set -e
cd "$(dirname "$0")"

GHDL_FLAGS="--std=08 -fsynopsys -frelaxed --workdir=work"

# VHDL sources: the core files, with a few simulation-only copies in
# patched/ for constructs Quartus accepts but GHDL does not.
if [ ! -f atari5200_pocket_synth.v ] || [ "$1" == "vhdl" ]; then
  rm -rf work && mkdir work
  ghdl -i $GHDL_FLAGS $(cat vhdl_sim_files.txt)
  ghdl -m $GHDL_FLAGS atari5200_pocket > /dev/null
  ghdl --synth $GHDL_FLAGS --out=verilog atari5200_pocket > atari5200_pocket_synth.v 2> synth.log
  python3 fix_synth.py atari5200_pocket_synth.v
fi

POCKET=../src/fpga/core/pocket
verilator --binary --timing -j 2 -O2 +1364-2005ext+v \
  -Wno-fatal -Wno-WIDTH -Wno-PINMISSING -Wno-UNOPTFLAT -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD \
  -Wno-CASEINCOMPLETE -Wno-COMBDLY -Wno-INITIALDLY -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME \
  --top-module tb_top \
  tb_top.sv sim_stubs.v \
  ../src/fpga/apf/common.v \
  ../src/fpga/core/core_top.v \
  $POCKET/cart_loader.v $POCKET/cart_mem.v $POCKET/boot_seq.v $POCKET/input_map.v \
  $POCKET/video_apf.v $POCKET/audio_apf.v \
  atari5200_pocket_synth.v \
  -o Vtb_top 2>&1 | grep -v '^%Warning\|^  \|^ *: \|^ *|' | tail -20
echo "built obj_dir/Vtb_top"
