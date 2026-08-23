// ModRM/SIB byte parsing, addressing mode
// ### `x87_complex_dec`
// - **Role:** detect "too big for hardware" → emit a microcode entry point; capture live operand context.
// - **In:** opcode attrs (`is_complex`), resolved operands. **Out:** `micro_entry` (MSROM addr), `ctx` bundle for splice.
// - **Comb.** **Traps:** capture *everything* splice will need; route the right instruction classes (§12 of `x87_decode.md`).