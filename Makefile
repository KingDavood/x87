# ---------------------------------------------------------------------------
# synth: yosys synthesis against the SkyWater sky130 PDK (see scripts/synth.sh
# for the actual yosys/docker invocation -- runs inside the iic-osic-tools
# container, which has yosys+slang and the sky130 PDK preinstalled).
#
# pkg/*.sv is always included automatically: almost everything in rtl/
# imports cpu_pkg/isa_pkg, and there's no point making every invocation
# repeat that.
#
#   make synth                                     # whole design: TOP=cpu_top, all of rtl/
#   make synth SRC=rtl/ooo_engine/execute/alu.sv    # one file, TOP inferred as "alu"
#   make synth SRC="a.sv b.sv" TOP=foo              # explicit TOP for a multi-file group
#
# Unwritten submodules are blackboxed rather than erroring (see
# --ignore-unknown-modules in scripts/synth.sh), so a single unit can be
# synthesized on its own while the rest of the design is still stubs.
# ---------------------------------------------------------------------------
PKG_SRCS := $(wildcard pkg/*.sv)
RTL_SRCS := $(shell find rtl -name '*.sv' 2>/dev/null)

SRC ?= $(RTL_SRCS)

ifeq ($(origin TOP),command line)
  SYNTH_TOP := $(TOP)
else ifeq ($(origin SRC),command line)
  SYNTH_TOP := $(basename $(notdir $(lastword $(SRC))))
else
  SYNTH_TOP := cpu_top
endif

SYNTH_SRCS := $(PKG_SRCS) $(SRC)

.PHONY: synth synth-clean

synth:
	scripts/synth.sh $(SYNTH_TOP) $(SYNTH_SRCS)

synth-clean:
	rm -rf synth/out
