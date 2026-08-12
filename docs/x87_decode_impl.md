# x87 — Decode Implementation Guide (RTL prep)

> A build-oriented companion to `x87_decode.md`. That doc explains the mechanism;
> **this doc is what to do to start writing RTL.** It gives you the *information*
> to declare your own module headers — the data contracts, each module's I/O and
> responsibility, and the gotchas — without dictating the port lists. You author
> the SystemVerilog; treat every field/signal list here as an inventory to react
> to, not a fixed interface. Design choices are flagged **[your call]**.
>
> Scope: cold (legacy) decode path first — it must be correct before the uop cache
> means anything. Protected-mode integer subset first, then widen. Targets a
> SKY130 + OpenLane tapeout.

---

## 1. Lock the contracts before any module

The single most important RTL-prep step: **freeze the shared types first.** Every
decode module reads or writes these, so if they churn you rewrite everything.
Put them in `pkg/` (`x87_pkg.sv`, `x87_uop_pkg.sv`). Below are the *fields each
contract must carry* — declare them as packed structs / enums however you like.

### 1.1 Enums

| Type | Values (at least) | Notes |
|---|---|---|
| `mode_e` | REAL, PROT, LONG | runtime mode input |
| `op_size_e` | B, W, D, Q | resolved operand size |
| `seg_id_t` | CS DS ES FS GS SS, NONE | override + default |
| `reg_id_t` | GPR 0–15, temp 0–T, special (RIP, flags) | **include a temp namespace** (see §4) |
| `uop_op_e` | LD, ST, ALU_ADD/SUB/AND/…, CMP, SHIFT, BR, MOV, LEA, MUL, DIV, MICRO_ENTRY, … | your op set |

### 1.2 `prefix_state_t` (output of prefix decode)

| Field | Width | Meaning |
|---|---|---|
| `seg_override` | `seg_id_t` | group-2 override, or NONE |
| `opsize_66` | 1 | `66` present |
| `addrsize_67` | 1 | `67` present |
| `lock` | 1 | `F0` present |
| `rep_kind` | 2 | none / REP(F3) / REPNE(F2) |
| `mand_pfx` | 2 | mandatory-prefix class (none/66/F2/F3) for opcode lookup |
| `rex_present` | 1 | any REX seen (needed for 8-bit reg rule) |
| `rex_w/r/x/b` | 1 each | REX bits |

### 1.3 `ea_t` (output of ModR/M·SIB — the AGU's input)

| Field | Width | Meaning |
|---|---|---|
| `is_mem` | 1 | 0 ⇒ register operand, skip AGU |
| `rip_rel` | 1 | 64-bit RIP-relative |
| `base` / `base_valid` | `reg_id_t` / 1 | base register |
| `index` / `index_valid` | `reg_id_t` / 1 | index register |
| `scale` | 2 | shift amount (1<<scale) |
| `disp` | 32 | sign-extended displacement |
| `segment` | `seg_id_t` | override, else default (SS for BP/RBP/RSP-based, else DS) |
| `addr_size` | 4 | 16/32/64 |

### 1.4 `uop_t` (the whole back-end contract — freeze this hardest)

| Field | Width | Meaning |
|---|---|---|
| `op` | `uop_op_e` | the single job |
| `size` | `op_size_e` | operand size |
| `dst` / `src1` / `src2` | `reg_id_t` | operands (dst may be a temp) |
| `src2_is_imm` | 1 | src2 is the immediate |
| `imm` | 64 | sign/zero-extended immediate |
| `ea` | `ea_t` | for LD/ST/LEA |
| `flags_wr` | mask | which RFLAGS bits this uop writes |
| `flags_rd` | 1 | reads flags (ADC/SBB/Jcc/CMOVcc/SETcc) |
| `is_micro` | 1 | from MSROM |
| `end_of_instr` | 1 | last uop of the x86 instruction |
| `pred_tag` | N | branch-mispredict recovery id |

### 1.5 Params (compile-time)

`FETCH_W` (fetch bytes/cycle), `MAX_ILEN=15`, `DEC_SLOTS` (cold-path width, ~2),
`MSROM_AW` (microcode addr width), `IQ_DEPTH`, temp-register count `NUM_TEMP`.

---

## 2. Cold-path module inventory (info to write headers)

For each module: **role**, what it **consumes** / **produces**, whether it's
**combinational or sequential**, and the traps. Ports/naming are yours.

### `x87_mode_ctrl` (context source)
- **Role:** resolve the three effective sizes from `mode_e` + prefixes + REX; single source of truth.
- **In:** `mode_e`, `prefix_state_t`, opcode attrs (`def64`). **Out:** operand_size, address_size, stack_size.
- **Comb.** Feeds length decode, opcode/imm sizing, and ModR/M table select.

### `x87_ilen_dec` (length decode)
- **Role:** find instruction boundaries in the byte window (~2 instructions/cycle).
- **In:** byte window (`FETCH_W*8`), effective sizes, opcode length attrs. **Out:** per-slot start offset + length + valid.
- **Comb, likely pipelined.** *Reuses the opcode table's length attributes* (`has_modrm`, `imm_kind`) — don't build a second decoder; share the table.
- **Traps:** sequential k→k+1 dependency; LCP (`66` changes imm length); 15-byte cap ⇒ `#GP`; must have ≥15 bytes buffered.

### `x87_prefix_dec`
- **Role:** consume legacy prefixes + REX, accumulate effects.
- **In:** bytes at instruction start, `mode_e`. **Out:** `prefix_state_t`, `pfx_len`.
- **Comb.** **Traps:** REX must be the byte immediately before opcode; consume redundant same-group prefixes; set `mand_pfx` for the opcode stage.

### `x87_decoder` / opcode lookup (top)
- **Role:** look up opcode attributes; orchestrate the sub-decoders; route simple vs complex.
- **In:** bytes (post-prefix), `prefix_state_t`, effective sizes. **Out:** opcode attrs (`has_modrm, group_id, imm_kind, def64, lock_ok, flags_wr, uop_template, is_complex`), `opcode_len`.
- **Comb + table (ROM/LUT).** **Traps:** 1/2/3-byte escapes (`0F`, `0F 38`, `0F 3A`); mandatory prefixes select the instruction; groups (reg field extends opcode).

### `x87_modrm_sib`
- **Role:** resolve addressing form → `ea_t`; extract reg/rm fields.
- **In:** modrm, sib, `addr_size`, `rex_x/b`, `prefix_state_t`. **Out:** `ea_t`, `need_sib`, `disp_len`, `reg_field`, `rm_reg`.
- **Comb, parameterized by `addr_size`** (16-bit table vs 32/64 — effectively two decoders). **Traps:** `mod=00,rm=101` (disp32 vs RIP-rel); SIB `index=100`/`base=101`; no SIB in 16-bit.

### `x87_imm_extract`
- **Role:** pull the immediate and size it.
- **In:** bytes (post-disp), `imm_kind`, `operand_size`. **Out:** `imm` (extended), `imm_len`.
- **Comb.** **Traps:** `iz` size flips with `66`/`REX.W`; `io` (imm64) only for `MOV r64, imm64`.

### `x87_simple_dec` (the cracker)
- **Role:** fill a fixed uop template with resolved operands → 1–~4 uops.
- **In:** opcode attrs + `uop_template` + resolved operands (`reg_field`, `rm_reg`, `ea_t`, `imm`). **Out:** `uop_t [0:DEC_SLOTS-1]`, valid mask, `end_of_instr` on last.
- **Comb (fixed templates).** **Traps:** allocate temp regs to chain LD→op→ST; correct ordering; materialize implicit operands (RSP, etc.); attach `flags_wr`. See §4.

### `x87_complex_dec`
- **Role:** detect "too big for hardware" → emit a microcode entry point; capture live operand context.
- **In:** opcode attrs (`is_complex`), resolved operands. **Out:** `micro_entry` (MSROM addr), `ctx` bundle for splice.
- **Comb.** **Traps:** capture *everything* splice will need; route the right instruction classes (§12 of `x87_decode.md`).

### `x87_msrom` + `x87_useq` + `x87_uop_splice` (microcode)
- **`x87_msrom`** — ROM of *templated* uops. In: micro addr. Out: templated uop + sequencer control (next/branch/terminate). Init from `scripts/uasm`. **ROM (synth logic or macro).**
- **`x87_useq`** — sequencer FSM. In: `micro_entry`, condition inputs. Out: stream of micro addrs, valid/done, backpressure. **Sequential.** Handles micro-branch/loop.
- **`x87_uop_splice`** — substitutes `ctx` operands into template blanks → final `uop_t`. **Comb.**

### `x87_uop_queue`
- **Role:** FIFO decoupling front-end from back-end; accepts 1–4 uops/cycle from the mux.
- **In:** uops + valid from the mux (cold-simple / micro / hot uop-cache). **Out:** uops to back-end + credits. **Sequential FIFO.** **Traps:** variable in-count; backpressure both ways.

---

## 3. The opcode table — the spine of decode

Almost every module above reads one attribute table. Build it once, generate it,
share it (length decode, opcode decode, imm sizing, cracking all consume it).

**Lookup key:** `{escape (1/2/3-byte), mand_pfx, opcode_byte}`, then a group
sub-decode on `ModR/M.reg` for group opcodes.

**Per-entry attributes (minimum):** `has_modrm`, `imm_kind` (none/ib/iw/id/iz/io),
`group_id`, `def64`, `lock_ok`, `flags_wr`, `flags_rd`, `is_complex`,
`uop_template` (id or micro entry). Add a `valid`/`#UD` flag for holes.

**Generate, don't hand-write.** Pull from a machine-readable encoding source
(`ref.x86asm.net` XML is the usual choice) with `scripts/gen_tables.py`, emit a SV
package or ROM-init. Start with a **protected-mode integer subset** (MOV, ADD/SUB/
logic, CMP/TEST, shifts, LEA, PUSH/POP, Jcc/JMP/CALL, INC/DEC) — a few dozen
entries gets you booting straight-line code.

---

## 4. Cracking mechanism (what `simple_dec` implements)

The count of uops = number of jobs hiding in the instruction. Memory is the
multiplier: **memory read → LD, compute → ALU, memory write → ST**, plus implicit
operands. Same opcode, different operand location, different uop count:

```
add rax, rbx     reg,reg   → 1: ADD rax = rax + rbx
add rax, [rbx]   reg←mem   → 2: LD t0=[rbx]; ADD rax = rax + t0
add [rbx], rax   mem←reg   → 3: LD t0=[rbx]; ADD t0=t0+rax; ST [rbx]=t0
push rax                   → 2: SUB rsp=rsp-8; ST [rsp]=rax   (implicit rsp)
```

**Templates + temps.** Each opcode-table entry carries a template (fixed uop
sequence with placeholders `%dst,%mem,%t`). `simple_dec` fills the blanks with the
resolved operands and allocates **temporary registers** (`t0…`) — scratch regs
outside the architectural set — to pass values between the split uops. Emit in
dependency order; mark the last with `end_of_instr`; attach `flags_wr`.

**Threshold [your call]:** crack up to ~4 uops in hardware; anything longer or
data-dependent (string ops, far control transfer, system) → `complex_dec` →
microcode. The MSROM does the same template-fill, but from a ROM with a sequencer
so it can loop/branch.

---

## 5. RTL build & test order

Write and unit-test in this order; each step is checkable against the golden model
(§6) before the next:

1. `pkg` types (§1) — nothing compiles without them.
2. `x87_mode_ctrl` + `x87_prefix_dec` — small, fully testable in isolation.
3. `gen_tables.py` + opcode table + `x87_decoder` lookup (integer subset).
4. `x87_modrm_sib` + `x87_imm_extract`.
5. `x87_ilen_dec` — build on the table's length attrs; verify length before fields.
6. `x87_simple_dec` cracking (subset) — check uop shape/order/flags.
7. `x87_complex_dec` + minimal `msrom`/`useq`/`splice` for a couple of ops.
8. `x87_uop_queue`.
9. Widen: real-mode (16-bit ModR/M), long-mode (REX, RIP-relative, `def64`).

Only *after* the cold path passes: add the uop-cache path.

---

## 6. Verification (golden model / oracle)

Decode's correct answer is fully defined by the ISA, so lean on a reference:

- **Golden decoder** — Intel **XED** (library) or an emulator's decoder (**Bochs**,
  **QEMU**) as the oracle. Diff RTL output against it: total length, ModR/M/SIB/disp/
  imm extents, register ids, segment, flags mask, uop count/order.
- **Oracle fuzzing** (your planned approach) — generate random + structured legal
  byte streams, run through RTL (Verilator/Icarus) and the oracle, diff. Assert
  illegal encodings fault identically (`#UD`/`#GP`).
- **Directed corner tests** — one per hard case in `x87_decode.md` §14 (the
  `40`–`4F` REX/INC split, 8-bit REX reg flip, `mod=00,rm=101`, SIB specials, LCP…).
- **Mode cross-product** — same encodings under real/prot/long.
- **Harness:** Verilator + **cocotb** (Python) makes the oracle diff easy since the
  reference is a C/Python library; GTKWave for waves.

---

## 7. SKY130 implementation notes for decode

Decode is **logic-heavy, not memory-heavy** — that's favorable on 130nm (you're
spending gates, not scarce SRAM macros). Two cautions:

- **Comb depth is your timing enemy.** prefix → opcode-table → ModR/M → imm →
  crack is a long combinational chain, and length decode's serial dependency adds
  more. On 130nm this won't close as one cycle — **pipeline it** (that's why the
  stages exist; register between sub-stages). Expect decode to be a few pipe
  stages, and let it set/limit fmax alongside the caches.
- **Tables as logic.** The opcode table and MSROM are small enough to synthesize as
  logic/ROM rather than SRAM macros — keep them out of the OpenRAM budget. If MSROM
  grows large, a single small macro is an option, but start with synthesized ROM.

---

## 8. Sources (annotated)

**ISA encoding — the authority for the tables and gotchas**
- Intel 64 & IA-32 SDM, **Vol. 2 (2A–2D)** — instruction set reference, opcode maps
  (App. A), ModR/M & SIB tables (App. B). Search "Intel SDM Volume 2":
  https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html
- AMD64 Architecture Programmer's Manual, **Vol. 3** — encodings, often clearer prose:
  https://www.amd.com/en/support/tech-docs (search "AMD64 APM Volume 3").
- **felixcloutier.com/x86** — fast, hyperlinked Intel SDM mirror: https://www.felixcloutier.com/x86/
- **sandpile.org** — the implementer's x86 encoding reference (opcode/ModR/M/prefix
  maps in dense tabular form): https://sandpile.org/
- **ref.x86asm.net** — machine-readable opcode tables (XML) — feed this to
  `gen_tables.py`: http://ref.x86asm.net/

**Reference decoders / emulators — golden model for verification**
- **Intel XED** (x86 encoder/decoder library): https://github.com/intelxed/xed
- **Bochs** (readable C++ x86 interpreter; ao486 was modeled on it): https://bochs.sourceforge.io/
- **QEMU** (fast oracle for fuzzing): https://www.qemu.org/

**Microarchitecture — cracking, uop cache, real-world behavior**
- **Agner Fog** — "The microarchitecture of Intel/AMD/VIA CPUs" and "Instruction
  tables" (uop counts, decode/DSB behavior): https://www.agner.org/optimize/

**Open reference cores — see how others did x86 decode in HDL**
- **ao486** — synthesizable 486SX in Verilog, decode + microcode modeled on Bochs;
  the closest open prior art to what you're building: https://github.com/alfikpl/ao486
- **zet** — open 16-bit x86 (8086-class) softcore, simpler decode to read first:
  https://github.com/marmolejo/zet

**Toolchain / PDK — the SKY130 tapeout flow**
- **OpenLane 2** (RTL→GDSII, Yosys/OpenROAD/Magic/Netgen; SKY130 + GF180):
  https://github.com/efabless/openlane2 · docs https://openlane2.readthedocs.io/
- **SkyWater SKY130 PDK** (sky130_fd_sc_hd cells, DRC/LVS rules):
  https://github.com/google/skywater-pdk · https://skywater-pdk.readthedocs.io/
- **OpenROAD**: https://theopenroadproject.org/
- **OpenRAM** (SRAM macro generator): https://github.com/VLSIDA/OpenRAM
- **DFFRAM** (flip-flop RAM compiler for small memories / register files):
  https://github.com/AUCOHL/DFFRAM

**HDL / simulation / verification tooling**
- **Verilator** (fast sim, pairs with C/Python oracle): https://www.veripool.org/verilator/
- **Icarus Verilog** (event sim, good for quick SV checks): https://steveicarus.github.io/iverilog/
- **cocotb** (Python testbenches — ideal for oracle diffing): https://www.cocotb.org/
- **GTKWave** (waveforms): https://gtkwave.sourceforge.net/
- SystemVerilog LRM: IEEE 1800-2017/2023. Practical refs: https://www.chipverify.com/ , https://hdlbits.01xz.net/

---

## 9. Open decisions to make before/while writing headers

- **`uop_op_e` set** — how fine-grained (one ADD vs per-flavor)?
- **`reg_id_t` layout** — how many temp regs; how special regs (RIP, flags) encode.
- **Crack-vs-microcode threshold** — the max uops you crack in hardware (~4 default).
- **Decode pipeline depth** — how many stages between prefix and crack (timing-driven).
- **Table-driven vs hardwired** opcode decode (recommend table-driven).
- **`DEC_SLOTS`** — cold-path width (~2) and how length decode fans into them.

These shape the headers, so decide them (even provisionally) before freezing `pkg`.
