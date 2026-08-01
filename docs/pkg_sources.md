# pkg_sources.md

Where the values in `pkg/isa_pkg.sv` and `pkg/cpu_pkg.sv` came from.

Last updated: 2026-08-01

The two packages look similar — both are lists of constants and structs — but they
have completely different authority behind them:

- **`isa_pkg.sv` is transcription.** These are x86-64 encodings. If a value here
  disagrees with the Intel SDM, it is a bug, full stop. Don't "tune" anything in
  this file.
- **`cpu_pkg.sv` is guesswork.** Every depth and width in it is a starting point
  someone picked, not a sourced value. Expect to change all of it once there's
  RTL to measure.

Read that distinction before touching either file.

---

## 1. `isa_pkg.sv` — verified against sources

These were checked directly against the references listed in §5 and matched
exactly:

| What | Where it comes from | Notes |
|---|---|---|
| `cond_e` — `CC_O=0x0` through `CC_G=0xF` | The `Jcc` short-form opcode table (`0x70 + cc`) | The enum value *is* the low nibble of the opcode, so the decoder can slice it straight out of the opcode byte. |
| Every branch of `cond_true()` | Same table's flag tests | Including the signed cases: `L` is `SF≠OF`, `LE` is `ZF=1 or SF≠OF`, `G` is `ZF=0 and SF=OF`. |
| `FLAG_CF=0, PF=2, AF=4, ZF=6, SF=7, TF=8, IF=9, DF=10, OF=11` | EFLAGS layout, SDM Vol 1 §3.4.3 | The gaps (bits 1, 3, 5) are reserved. Same positions in FLAGS/EFLAGS/RFLAGS. |
| `exc_vec_e` — `EXC_DE=0` through `EXC_MC=18` | Protected-mode exception vector table, SDM Vol 3A Ch. 6 | Vector **9** is deliberately absent: it's reserved (historically Coprocessor Segment Overrun). Don't "fill in the hole." |

## 2. `isa_pkg.sv` — from the spec, but not re-verified

Standard, uncontroversial, taken from the SDM Vol 2 Ch. 2 / AMD APM Vol 3 Ch. 1
instruction-format chapters. Worth a second pair of eyes against the PDFs if you
hit a decode bug in this area:

- **GPR numbering:** `RAX=0, RCX=1, RDX=2, RBX=3, RSP=4, RBP=5, RSI=6, RDI=7`,
  then `R8`–`R15`. This ordering looks arbitrary but it's the actual wire
  encoding — which is the whole point: `{rex.b, modrm.rm}` indexes `gpr_e`
  directly, no lookup table.
- **Prefix bytes:** `F0` LOCK, `F2` REPNE, `F3` REP, `66` operand-size,
  `67` address-size, segment overrides `26/2E/36/3E/64/65` (ES/CS/SS/DS/FS/GS),
  `0F` two-byte escape.
- **`is_rex()`** — a REX prefix is any byte matching `0100WRXB`, i.e.
  `b[7:4] == 4'h4`.
- **ModRM field layout:** `[7:6]=mod, [5:3]=reg, [2:0]=rm`.
  **SIB field layout:** `[7:6]=scale, [5:3]=index, [2:0]=base`.
  `modrm_t` and `sib_t` declare their fields in that MSB-to-LSB order, so a
  packed cast straight off the instruction stream works. **If you reorder those
  struct fields, decode breaks silently.**
- **Addressing-form escapes:** `rm=100` with `mod≠11` means a SIB byte follows;
  `rm=101` with `mod=00` means RIP-relative; `sib.index=100` means no index
  register.
- **`MAX_INSN_LEN = 15`** — the architectural instruction length limit. Longer
  than this is `#GP`, and the predecoder's length decoder needs to enforce it.

## 3. `isa_pkg.sv` — our decisions, *not* the spec

Three things in that file are ours. They're reasonable, but nobody can look them
up, so they're written down here instead:

- **`SEG_NONE = 3'd7`** — invented sentinel. The architectural 3-bit segment
  encoding only defines 0–5; 6 and 7 are reserved, so we squatted on 7 to mean
  "no segment override present."
- **`VADDR_WIDTH = 48`, `PADDR_WIDTH = 52`** — 48 is what 4-level paging gives
  (5-level paging would be 57). 52 is the architectural ceiling on
  `MAXPHYADDR`. Both are legal implementation choices, not fixed values.
- **`x86_op_e` — both its membership and its numbering.** The list is a subset of
  x86 we chose to support; the values auto-increment from `X86_INVALID = 0` and
  are arbitrary. Only the decoder's opcode tables have to match the spec — this
  enum is internal, so renumber it freely.

---

## 4. `cpu_pkg.sv` — we made these numbers up

**No document says a core should have 256 ROB entries.** Every value in the
sizing section is a plausible-looking default for a 4-wide out-of-order core.
Treat the whole file as provisional.

Two values are anchored to something at least, though not to a spec —
`tb/tb_top.sv` already assumed them before the packages existed:

| Value | Why |
|---|---|
| `RETIRE_WIDTH = 4` | `tb/tb_top.sv:28` declares a matching `RETIRE_WIDTH` localparam (the TB doesn't `import cpu_pkg` yet, see §6, so the two are kept in sync by hand). |
| `ROB_DEPTH = 256` | `tb/tb_top.sv:30` used an 8-bit ROB index. Power of two, so the index wraps for free — no comparator on the wrap path. |

### Calibration reference

For a sense of scale, here are Intel Skylake's real structure sizes (4-wide
core, from WikiChip / Chips and Cheese) next to ours. As of 2026-08-01 the
sizing below is matched directly to Skylake rather than scaled down, since
this core is now 4-wide like Skylake:

| Structure | Skylake | Ours | Comment |
|---|---|---|---|
| ROB entries | 224 | 256 | Ours is larger only because 256 is a power of two. |
| Integer PRF | 180 | 180 (`PREG_COUNT`) | Matched directly. |
| Scheduler entries | 97 (58 math + 39 AGU) | 48 + 32 + 17 = 97 (`IQ_INT`/`IQ_MEM`/`IQ_BR`) | Split queues per port class, same idea as Skylake; total matched, split kept at roughly the old 2-wide proportions. |
| Load buffer | 72 | 72 (`LQ_DEPTH`) | Matched directly. |
| Store buffer | 56 | 56 (`SQ_DEPTH`) | Matched directly. |

`BTB_ENTRIES=512`, `BHT_ENTRIES=1024`, `RAS_DEPTH=16`, `NUM_CHECKPOINTS=8`,
`FPREG_COUNT=64` have **no** justification beyond "small core, round number."
Size them from your own IPC experiments.
`FETCH_BUF_DEPTH=64` isn't Skylake-calibrated either; it's kept at 2x
`FETCH_WIDTH`, the same ratio the 2-wide version used.

### Microcode sequencer (added 2026-08-01)

`UOPS_PER_INSN` caps what the combinational hardware crack can produce in one
cycle. A few x86 instructions (`IRET`, `SYSCALL`, `SYSRET`, `INT`) do more
architectural work than that's worth building combinationally for and need a
multi-cycle sequencer stepping through a microcode ROM instead — this is the
same split real x86 cores make between simple hardware decode and an MS-ROM.

This is scaffolding only — no ROM contents, no `rtl/frontend` sequencer
module yet:

- `UCODE_ROM_DEPTH=128`, `UCODE_MAX_SEQ_LEN=8` — round-number guesses, same
  "no justification" bucket as the rest of §4's placeholders.
- `ucode_idx_t` — ROM entry index, width derived like every other `*_IDX_W`.
- `ucode_seq_state_e` (`UCODE_IDLE`/`UCODE_ACTIVE`) — frontend arbitration
  state: hardware cracker vs. sequencer driving the uop stream.
- `is_microcoded(x86_op_e)` — the decode-time classification function.
  **Deliberately lives in `cpu_pkg.sv`, not `isa_pkg.sv`**, even though it
  switches on `x86_op_e`: the SDM doesn't mandate microcoding anything, so
  which instructions get sequenced is an implementation choice like every
  other guess in this file, not architecture. `isa_pkg.sv` only carries a
  one-line comment next to `x86_op_e` pointing here.
- `dec_insn_t.ucode_valid` / `.ucode_entry` — decode's hand-off to the
  sequencer (set when `is_microcoded()` is true).
- `uop_t.ucode_valid` / `.ucode_last` — per-uop sequencer origin.
  `ucode_last` is kept distinct from `last_uop` (the ROB retire boundary):
  today's one-routine-per-instruction sequencer always sets both together,
  but a sequencer with call/return between shared routines wouldn't.

Not yet covered: REP-prefixed string ops (`MOVS`/`STOS`/`CMPS`/`SCAS`/`LODS`)
are classic microcode candidates but aren't in `x86_op_e` at all yet.

### Structural choices

The shape of `uop_t` / `rob_entry_t` follows textbook R10000-style out-of-order
design, not any particular implementation:

- Physical-register renaming with `dst_prev` carried through the pipe and freed
  at retire.
- Flags renamed as a **separate group** (`flags_t`, its own `fpreg_t` tag) rather
  than as part of the GPR file. This is what stops every flag-writing
  instruction from serializing on every flag-reading one.
- `br_tag` on each uop identifying the youngest branch it's speculative under,
  paired with `NUM_CHECKPOINTS` rename snapshots for single-cycle recovery.
- `uop_op_e` is deliberately separate from `x86_op_e` so one x86 instruction can
  crack into several uops — `add [mem], reg` becomes LOAD, ADD, STORE.

Canonical writeups: Yeager, *The MIPS R10000 Superscalar Microprocessor* (IEEE
Micro, 1996), and Shen & Lipasti, *Modern Processor Design*.

---

## 5. Sources

Architectural:

- [Manuals for Intel® 64 and IA-32 Architectures](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)
  — the index page. Vol 2A Ch. 2 = instruction format (prefixes, REX, ModRM,
  SIB); Vol 1 §3.4.3 = EFLAGS; Vol 3A Ch. 6 = exceptions.
  - [Vol 2A direct PDF](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf)
  - [Vol 3A direct PDF](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-3a-part-1-manual.pdf)
- [AMD64 APM Vol 3 (pub. 24594)](https://docs.amd.com/v/u/en-US/24594_3.37) —
  opcode maps; often clearer than Intel's on encoding.
- [felixcloutier.com/x86](https://www.felixcloutier.com/x86/) — searchable HTML
  mirror of the SDM Vol 2 instruction reference. Fastest way to check one
  instruction. ([Jcc page](https://www.felixcloutier.com/x86/jcc) is the
  condition-code table.)
- [OSDev: X86-64 Instruction Encoding](https://wiki.osdev.org/X86-64_Instruction_Encoding)
  — the ModRM/SIB tables in a more readable form than the SDM.
- [OSDev: Exceptions](https://wiki.osdev.org/Exceptions) — vector list.
- [FLAGS register (Wikipedia)](https://en.wikipedia.org/wiki/FLAGS_register) —
  quick bit-position check.
- [`ExceptionVector` in the Rust `x86_64` crate](https://docs.rs/x86_64/latest/x86_64/structures/idt/enum.ExceptionVector.html)
  — a machine-readable vector list, handy for cross-checking.

Microarchitectural:

- [Skylake (client) — WikiChip](https://en.wikichip.org/wiki/intel/microarchitectures/skylake_(client))
  and [Skylake: Intel's Longest Serving Architecture — Chips and Cheese](https://chipsandcheese.com/p/skylake-intels-longest-serving-architecture)
  — the structure sizes in §4.
- [Agner Fog, *The microarchitecture of Intel, AMD and VIA CPUs*](https://www.agner.org/optimize/microarchitecture.pdf)
  — measured table sizes and pipeline behaviour for real x86 parts.
- [RISCV-BOOM documentation](https://docs.boom-core.org/en/latest/) — the
  Parameterization section is the closest open-source analogue for choosing
  structure sizes.

---

## 6. Known open items

- **Duplicate package name.** `rtl/top/cpu_pkg.sv` is a leftover stub that also
  declares `package cpu_pkg`. Two files declaring the same package will
  collide — one of them has to go, and the parameters currently live in
  `pkg/cpu_pkg.sv`.
- **TB doesn't use the structs yet.** `tb/tb_top.sv` still uses hand-rolled
  parallel packed arrays with its own placeholder localparams. Once `cpu_top`
  has a port list it should `import cpu_pkg::*` and use
  `retire_pkt_t [RETIRE_WIDTH-1:0]` instead. See the TODO at `tb/tb_top.sv:40`.
- **Compile order.** `isa_pkg.sv` → `cpu_pkg.sv` → `mem_pkg.sv`. `cpu_pkg`
  imports `isa_pkg`; memory-side request/response structs belong in `mem_pkg`,
  not `cpu_pkg`.
- **Microcode sequencer has no ROM or RTL yet.** §4's "Microcode sequencer"
  section added the interface shape (`ucode_idx_t`, `ucode_seq_state_e`,
  `is_microcoded()`, the `dec_insn_t`/`uop_t` hand-off fields) but there's no
  `rtl/frontend` sequencer module consuming them and `UCODE_ROM_DEPTH` has no
  actual microcode routines behind it.
