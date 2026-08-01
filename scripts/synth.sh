#!/usr/bin/env bash
# Yosys synthesis targeting the SkyWater sky130 PDK.
#
# Runs inside the iic-osic-tools container (hpretl/iic-osic-tools), which
# bundles yosys (with the slang plugin for real SystemVerilog support -- our
# RTL uses packed structs/enums/packages that yosys's built-in Verilog
# frontend doesn't fully cover) and the sky130 PDK via volare/ciel.
#
# Not meant to be run directly -- see `make synth` in the top-level Makefile,
# which fills in TOP and the source file list.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $(basename "$0") TOP SRC_FILE..." >&2
  exit 1
fi

TOP="$1"
shift
SRC=("$@")

ROOT="$(git rev-parse --show-toplevel)"
DOCKER_IMAGE="${DOCKER_IMAGE:-hpretl/iic-osic-tools:latest}"
CONTAINER_ROOT="/foss/designs/x87"

# $PDK_ROOT/sky130A is a stable symlink to whatever version volare/ciel has
# checked out inside the image, so this path is fixed even though the
# version hash underneath it isn't.
LIBERTY="${LIBERTY:-/foss/pdks/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib}"

OUT_DIR="synth/out/${TOP}"
mkdir -p "${ROOT}/${OUT_DIR}"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker not found -- synthesis runs inside the iic-osic-tools container" >&2
  exit 1
fi

# --ignore-unknown-modules: this is a skeleton project under construction --
# blackbox any instantiated submodule that hasn't been written yet instead of
# hard-failing, so a single unit (e.g. rtl/ooo_engine/execute/alu.sv) can be
# synthesized on its own before its neighbors exist.
YOSYS_SCRIPT="
read_slang --top ${TOP} --ignore-unknown-modules $(printf '%s ' "${SRC[@]}");
synth -top ${TOP};
dfflibmap -liberty ${LIBERTY};
abc -liberty ${LIBERTY};
setundef -zero;
splitnets -ports;
opt_clean -purge;
stat -liberty ${LIBERTY};
write_verilog -noattr ${OUT_DIR}/${TOP}_synth.v;
write_json ${OUT_DIR}/${TOP}_synth.json;
"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "${ROOT}:${CONTAINER_ROOT}:rw" \
  -w "${CONTAINER_ROOT}" \
  "${DOCKER_IMAGE}" --skip yosys -m slang -p "${YOSYS_SCRIPT}"

echo "netlist:  ${OUT_DIR}/${TOP}_synth.v"
echo "json:     ${OUT_DIR}/${TOP}_synth.json"
