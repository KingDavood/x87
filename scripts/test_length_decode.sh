#!/usr/bin/env bash
# Generate vectors from the python golden model, verilate length_decode +
# its testbench, run it, and surface pass/fail. No nasm/cocotb -- see
# tb/gen_length_decode_vectors.py and tb/tb_length_decode.sv for why.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

VEC_DIR="tb/tests/vectors"
VEC_FILE="$VEC_DIR/length_decode_vectors.txt"
BUILD_DIR="obj_dir/length_decode"

mkdir -p "$VEC_DIR"
python3 tb/gen_length_decode_vectors.py "$VEC_FILE" "$@"

rm -rf "$BUILD_DIR"
verilator --binary --timing -Wall -Wno-fatal -j 0 \
  --top-module tb_length_decode \
  -Mdir "$BUILD_DIR" \
  pkg/isa_pkg.sv pkg/cpu_pkg.sv pkg/mem_pkg.sv \
  rtl/frontend/decode/decode.sv \
  tb/tb_length_decode.sv

"$BUILD_DIR/Vtb_length_decode" "+VECTORS=$VEC_FILE"
