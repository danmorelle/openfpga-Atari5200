#!/usr/bin/env python3
"""Clean up two GHDL --synth naming quirks so Verilator accepts the netlist:
 * a VHDL signal named <inst>_<port> collides with the net GHDL creates for
   the port of instance <inst>, giving duplicate declarations and self
   assignments ("assign x = x;"). Both names refer to the same net.
 * escaped port names glued to a prefix ("foo_\\output ").
"""
import re
import sys

path = sys.argv[1]
src = open(path).read()
src = re.sub(r'([A-Za-z0-9_]+)_\\output ', r'\1_output_net ', src)

out = []
declared = set()
ports = set()
decl_re = re.compile(r'^\s*wire\s*(\[[^\]]*\]\s*)?([A-Za-z_][A-Za-z0-9_$]*)\s*;')
port_re = re.compile(r'^\s*(\(\s*)?(input|output|inout)\s*(\[[^\]]*\]\s*)?([A-Za-z_][A-Za-z0-9_$]*)')
self_re = re.compile(r'^\s*assign\s+([A-Za-z_][A-Za-z0-9_$]*)\s*=\s*\1\s*;')
removed = 0
for line in src.split('\n'):
    if line.startswith('module '):
        declared = set()
        ports = set()
    m = port_re.match(line)
    if m:
        ports.add(m.group(4))
    m = decl_re.match(line)
    if m:
        name = m.group(2)
        if name in declared or name in ports:
            removed += 1
            continue
        declared.add(name)
    if self_re.match(line):
        removed += 1
        continue
    out.append(line)
open(path, 'w').write('\n'.join(out))
print(f"fix_synth: removed {removed} duplicate lines")
