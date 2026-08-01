# synth.md

How `make synth` works.

## What it is

`make synth` runs [Yosys](https://github.com/YosysHQ/yosys) synthesis against
the SkyWater `sky130_fd_sc_hd` standard cell library, targeting whichever
file(s) you point it at. It doesn't run natively — Yosys, its `slang`
SystemVerilog plugin, and the sky130 PDK all live inside the
`hpretl/iic-osic-tools` Docker image (already pulled on this machine). `make
synth` mounts the repo into that container and runs one Yosys invocation.

The actual work is in `scripts/synth.sh`; the `Makefile` target just works
out `TOP` and the source file list and calls it.

## Usage

```sh
make synth                                     # whole design: TOP=cpu_top, all of rtl/
make synth SRC=rtl/ooo_engine/execute/alu.sv   # one file, TOP inferred as "alu"
make synth SRC="a.sv b.sv" TOP=foo             # explicit TOP for a multi-file group
make synth-clean                               # rm -rf synth/out
```

`pkg/*.sv` is prepended to the source list automatically, every time — almost
every module imports `cpu_pkg`/`isa_pkg`, so there's no reason to make every
invocation repeat that. `TOP` resolution, in order:

1. `TOP=...` on the command line, if given.
2. Otherwise, if `SRC=...` was given, the basename of its last file
   (`rtl/.../alu.sv` → `alu`).
3. Otherwise, `cpu_top` (whole-design synthesis).

## What actually runs

```
read_slang --top <TOP> --ignore-unknown-modules <pkg/*.sv> <SRC>
synth -top <TOP>
dfflibmap -liberty <sky130 tt_025C_1v80.lib>
abc      -liberty <sky130 tt_025C_1v80.lib>
setundef -zero
splitnets -ports
opt_clean -purge
stat     -liberty <sky130 tt_025C_1v80.lib>
write_verilog -noattr synth/out/<TOP>/<TOP>_synth.v
write_json            synth/out/<TOP>/<TOP>_synth.json
```

**Why `read_slang` and not Yosys's built-in `read_verilog -sv`:** this RTL
leans on packed structs, enums, and package imports (`cpu_pkg`, `isa_pkg`)
throughout. Yosys's native frontend only covers a subset of SystemVerilog;
`slang` is a full frontend and handles all of that correctly.

**Why `--ignore-unknown-modules`:** most of `rtl/` is still one-line stub
files (see `git log` — the tree was laid down as a skeleton before RTL was
written). Without this flag, synthesizing one real module that instantiates
not-yet-written siblings would hard-fail. With it, missing submodules are
blackboxed instead, so a unit can be synthesized alone as it's written,
before the modules around it exist.

**Liberty corner:** defaults to `sky130_fd_sc_hd__tt_025C_1v80.lib` (typical
process, 25°C, 1.8V — the nominal corner). Override with `LIBERTY=/path/to/other.lib`
if you need a different corner (`ff`/`ss`, other temperature/voltage) for
timing exploration.

## Output

`synth/out/<TOP>/<TOP>_synth.v` (gate-level netlist) and
`synth/out/<TOP>/<TOP>_synth.json` (same, as Yosys JSON — useful for
`netlistsvg` or feeding into a P&R flow later). Yosys also prints a `stat`
area/cell-count report to stdout. Both are gitignored (`/synth/out/`).

## Requirements

- Docker, and the `hpretl/iic-osic-tools:latest` image available locally.
  Override the image with `DOCKER_IMAGE=...` if you need a different tag or
  a pinned version. If the image isn't present, pull it first —
  `scripts/synth.sh` doesn't do this for you.
- Nothing else — the PDK path (`$PDK_ROOT/sky130A`, a stable symlink inside
  the container regardless of which PDK version volare/ciel has checked out)
  and the sky130 liberty file are resolved inside the container, not on the
  host.

## Known gap

`rtl/top/cpu_pkg.sv` is a leftover stub that also declares `package cpu_pkg`
(see `docs/pkg_sources.md` §6) — it's harmless today because it's still just
a comment, but once it's filled in it'll collide with `pkg/cpu_pkg.sv` in any
synth run that includes both. Delete the stub before that happens.
