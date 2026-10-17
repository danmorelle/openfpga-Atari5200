# Atari 5200 for Analogue Pocket

An openFPGA core for the Analogue Pocket that recreates the Atari 5200
SuperSystem. It is a port of the [MiSTer Atari 5200 core](https://github.com/MiSTer-devel/Atari800_MiSTer),
which is based on Mark Watson's Atari 800XL FPGA core.

**Status: early test build (0.1.0).** It works in simulation; it has not been
tested on real hardware yet.

## Installing

1. Download the latest build (the `Atari5200-Pocket-build-…` zip from the
   Actions tab) and copy its contents to the root of your Pocket's SD card.
2. Put the Atari 5200 BIOS in `Assets/5200/common/5200.rom`. It must be the
   2048 byte BIOS. It is not included.
3. Put your cartridge images in `Assets/5200/common/` (or any subfolder).
   Supported: `.a52`, `.bin`, `.rom` and `.car`.

## Controls

| Pocket | Atari 5200 |
|---|---|
| D-pad | Joystick |
| A | Fire 1 (top buttons) |
| B | Fire 2 (bottom buttons) |
| Start | Start |
| Select (tap) | Pause |
| X / Y | Keypad 1 / 2 |
| L / R | Keypad * / # |
| Hold Select + X / Y / A / B | Keypad 3 / 4 / 5 / 6 |
| Hold Select + Up / Right / Down / Left | Keypad 7 / 8 / 9 / 0 |
| Hold Select + Start | Reset key |
| Dock L2 / R2 | Pause / Reset key |

Up to four controllers work in the Dock. Dock controllers with analog sticks
drive the 5200's analog joystick.

## Settings (Core Settings menu)

* **Reset**: restarts the game.
* **16K Cart Layout**: 16K cartridges were made in two different layouts.
  *Auto* works it out from the ROM; if a 16K game shows garbage, pick the
  other layout. Changing it restarts the game.
* **Swap Controllers 1+2**
* **Twin Stick (Robotron)**: for Robotron 2084 and Space Dungeon. X, Y, A and
  B (or a Dock controller's right stick) become the second joystick.

## Cartridge support

| Size | Type |
|---|---|
| 4K, 8K, 32K | Standard |
| 16K | One chip and two chip |
| 40K | Bounty Bob Strikes Back |
| 64K, 128K | Super cart (bank switched homebrew) |
| any | `.car` files with a cartridge type in the header |

256K and 512K super carts are not supported yet.

## How the port works

On MiSTer, the ARM processor loads cartridges into SDRAM, picks the cartridge
type, fills RAM at power-on and resets the machine. The Pocket has no such
processor, so this port does all of that in the FPGA:

* `src/fpga/core/pocket/cart_loader.v` receives the cartridge from the Pocket,
  strips `.car` headers and works out the cartridge type (including a
  one-chip/two-chip guess for 16K carts based on the code's jump targets).
* `src/fpga/core/pocket/cart_mem.v` keeps the cartridge in block RAM and
  translates addresses to reproduce MiSTer's mirrored SDRAM layout. It is
  checked byte for byte against MiSTer's loader for every cartridge type.
* `src/fpga/core/pocket/boot_seq.v` fills RAM with the power-on pattern and
  resets the Atari.
* `input_map.v`, `video_apf.v` and `audio_apf.v` adapt the controllers, video
  and sound to the Pocket.
* `src/fpga/core/pocket/atari5200_pocket.vhd` replaces MiSTer's top level.
  The Atari chips themselves (`src/fpga/core/atari/`) are unchanged copies
  from the MiSTer repository (commit `617ef94`).

## Building

The GitHub Actions workflow builds the core with Quartus Prime Lite 21.1 in
Docker and uploads an SD card ready zip. To build locally, open
`src/fpga/ap_core.qpf` in Quartus Prime Lite, compile, then run
`python3 tools/package.py` to create `release/sd/`.

## Simulation

`sim/` runs the whole core with GHDL and Verilator, loading a BIOS and test
cartridges over a simulated Pocket bridge and saving every frame as an image:

```
cd sim
python3 make_test_carts.py
./build.sh
./run_cart_tests.sh        # every cartridge layout shows the test picture
python3 mapper_test.py     # address mapping vs MiSTer, every type
iverilog -g2012 -o out/i.vvp input_test.v ../src/fpga/core/pocket/input_map.v && vvp out/i.vvp
```

The simulation needs a 5200 BIOS in `sim/roms/5200.rom` (not included).
A few core files need small simulation-only changes for GHDL; those copies
are in `sim/patched/` and are not used in the real build.

## Credits and licence

* Atari 800XL / 5200 FPGA core: Mark Watson
* MiSTer port: Sorgelig, Wojciech Mostowski and contributors
* Pocket port: this repository
* Audio I2S and helper design based on Analogue's openFPGA core template and
  Adam Gastineau's analogue-pocket-utils (MIT)

Released under the GNU GPL v3 (see `LICENSE`), like the MiSTer project. Mark
Watson's VHDL files carry his own notice (see `COPYRIGHT_NOTICE`): free for
non-commercial use; contact him for any commercial use.

This core does not include any Atari BIOS or game ROMs.
