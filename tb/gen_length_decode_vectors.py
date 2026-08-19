#!/usr/bin/env python3
# Golden model for length_decode's prefix-byte count (pfx_len).
#
# This is the "python model" side of the SV<->python diff: it re-derives the
# expected prefix count from the SDM prefix-group bytes independently of the
# RTL, rather than calling into anything the DUT shares. No nasm/capstone
# dependency -- the byte values themselves are the spec (see the PFX_* /
# is_rex() definitions in pkg/isa_pkg.sv, which this mirrors).
#
# Usage: gen_length_decode_vectors.py OUT_PATH [--seed N] [--random N]

import argparse
import random
import sys

BYTE_WIDTH = 32  # must match length_decode's MAX_BYTE_WIDTH default

# [SDM 2A "2.1.1 Instruction Prefixes"] groups 1-4 -- values from pkg/isa_pkg.sv.
LEGACY_PREFIXES = {
    0xF0,  # LOCK        group 1
    0xF2,  # REPNE       group 1
    0xF3,  # REP         group 1
    0x66,  # OPSIZE      group 3
    0x67,  # ADDRSIZE    group 4
    0x26,  # SEG ES      group 2
    0x2E,  # SEG CS      group 2
    0x36,  # SEG SS      group 2
    0x3E,  # SEG DS      group 2
    0x64,  # SEG FS      group 2
    0x65,  # SEG GS      group 2
}

NON_PREFIX_BYTES = [b for b in range(0x100) if b not in LEGACY_PREFIXES and not (0x40 <= b <= 0x4F)]


def is_rex(b: int) -> bool:
    return 0x40 <= b <= 0x4F


def is_prefix(b: int) -> bool:
    return b in LEGACY_PREFIXES or is_rex(b)


def expected_pfx_len(byte_stream: list[int]) -> int:
    """Count leading prefix bytes. Mirrors a straight left-to-right scan
    that stops at the first non-prefix byte -- doesn't dedupe redundant or
    semantically-overridden prefixes (e.g. two REX bytes), since that's a
    validity question for a later stage, not a length question."""
    n = 0
    for b in byte_stream:
        if is_prefix(b):
            n += 1
        else:
            break
    return n


def pad(prefix_bytes: list[int], filler: int = 0x90) -> list[int]:
    body = list(prefix_bytes) + [filler]
    if len(body) > BYTE_WIDTH:
        body = body[:BYTE_WIDTH]
    else:
        body += [filler] * (BYTE_WIDTH - len(body))
    return body


def directed_cases():
    cases = []

    def add(name, prefix_bytes, filler=0x90):
        cases.append((name, expected_pfx_len(pad(prefix_bytes, filler)), pad(prefix_bytes, filler)))

    add("no_prefix_opcode_first", [])
    add("opcode_byte_00_not_mistaken_for_prefix", [], filler=0x00)
    add("single_lock", [0xF0])
    add("single_repne", [0xF2])
    add("single_rep", [0xF3])
    add("single_opsize_66", [0x66])
    add("single_addrsize_67", [0x67])
    add("single_seg_cs", [0x2E])
    add("single_rex_w", [0x48])
    add("opsize_then_rex", [0x66, 0x48])
    add("seg_then_rex", [0x2E, 0x4C])
    add("one_from_each_group", [0xF0, 0x66, 0x67, 0x26])
    add("redundant_opsize_x3", [0x66, 0x66, 0x66])
    add("two_rex_bytes_both_counted", [0x40, 0x41])
    add("lock_rep_conflict_still_counts_both", [0xF0, 0xF3])
    add("max_window_all_prefix", [0xF0] * BYTE_WIDTH)  # loop-bound check; no MAX_INSN_LEN cap yet
    add("prefix_run_then_stop_mid_window", [0x66, 0x67, 0xF0] + [0x90] * 5)

    return cases


def random_cases(n, rng):
    cases = []
    for i in range(n):
        run_len = rng.randint(0, 6)
        run = [rng.choice(list(LEGACY_PREFIXES) + list(range(0x40, 0x50))) for _ in range(run_len)]
        filler = rng.choice(NON_PREFIX_BYTES)
        bytes_ = pad(run, filler)
        cases.append((f"random_{i:03d}", expected_pfx_len(bytes_), bytes_))
    return cases


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_path")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--random", type=int, default=30)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    cases = directed_cases() + random_cases(args.random, rng)

    with open(args.out_path, "w") as f:
        f.write(f"{len(cases)}\n")
        for name, expected, byte_list in cases:
            byte_str = " ".join(f"{b:02x}" for b in byte_list)
            f.write(f"{name} {expected} {byte_str}\n")

    print(f"wrote {len(cases)} vectors to {args.out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
