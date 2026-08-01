// uop_t, rob_entry_t, cache_req_t etc. (all structs)
//
// Microarchitectural parameters and datapath structs. Architectural encodings
// (opcodes, prefixes, GPR numbering, flags) live in isa_pkg.sv; memory-side
// request/response structs live in mem_pkg.sv.
//
// Compile order: isa_pkg.sv -> cpu_pkg.sv -> mem_pkg.sv
//
// ---------------------------------------------------------------------------
// WHERE THESE NUMBERS CAME FROM: mostly nowhere. Read this before tuning.
//
// Unlike isa_pkg.sv, which transcribes the x86-64 spec, *nothing* in this file
// is dictated by a document. No manual says a core should have 256 ROB entries.
// Every depth and width below is a plausible-looking starting point for a
// 4-wide out-of-order core, chosen by us. Expect to change all of it once
// there's RTL to measure. Two values are at least anchored to something --
// see RETIRE_WIDTH and ROB_DEPTH, which tb/tb_top.sv assumed first (keep
// tb/tb_top.sv's own RETIRE_WIDTH localparam in sync if you change ours).
//
// Calibration reference used for the sizing below -- Intel Skylake, a 4-wide
// core, matched directly rather than scaled:
//   ROB 224 | int PRF 180 | scheduler 97 (58 math + 39 AGU)
//   load buffer 72 | store buffer 56
//   https://en.wikichip.org/wiki/intel/microarchitectures/skylake_(client)
//   https://chipsandcheese.com/p/skylake-intels-longest-serving-architecture
// Measured structure sizes for other real x86 parts, if you want more points
// to interpolate between:
//   https://www.agner.org/optimize/microarchitecture.pdf
// Closest open-source analogue for parameterising an OoO core:
//   https://docs.boom-core.org/en/latest/  (Usage -> Parameterization)
//
// Structural shape (physical-register renaming, dst_prev freed at retire,
// flags renamed as a separate group, br_tag + rename checkpoints) follows
// textbook R10000-style OoO, not any specific implementation:
//   Yeager, "The MIPS R10000 Superscalar Microprocessor", IEEE Micro, 1996
//   Shen & Lipasti, "Modern Processor Design"
//
// Full writeup: docs/pkg_sources.md
// ---------------------------------------------------------------------------

`ifndef CPU_PKG_SV
`define CPU_PKG_SV

package cpu_pkg;

  import isa_pkg::*;

  // --------------------------------------------------------------------
  // pipeline widths
  //
  // All picked by us. FETCH_WIDTH=32 is a full cache-line burst, sized to
  // feed a 4-wide decoder at the same ~8 bytes/insn headroom the earlier
  // 2-wide version had at 16 bytes.
  // --------------------------------------------------------------------
  localparam int FETCH_WIDTH     = 32;  // bytes fetched per cycle
  localparam int PREDECODE_WIDTH = 8;   // insns predecoded per cycle
  localparam int DECODE_WIDTH    = 4;   // insns decoded per cycle
  localparam int UOPS_PER_INSN   = 4;   // max uops one x86 insn cracks into
  localparam int RENAME_WIDTH    = 4;   // uops renamed per cycle
  localparam int DISPATCH_WIDTH  = 4;
  localparam int ISSUE_WIDTH     = 6;   // int(2) + mem(2, ld+st) + br(1) + csr(1)

  // ANCHORED: tb/tb_top.sv:28 declares a matching RETIRE_WIDTH localparam
  // (the TB doesn't import cpu_pkg yet -- see docs/pkg_sources.md item 6).
  // Keep both in sync if you change this.
  localparam int RETIRE_WIDTH    = 4;

  // --------------------------------------------------------------------
  // microcode sequencer
  //
  // [OURS], like everything else in this file. UOPS_PER_INSN above is the
  // ceiling for the combinational hardware crack (one x86 insn -> uops,
  // same cycle, no ROM). A handful of instructions do more architectural
  // work than that crack can produce in one shot -- privilege-level
  // switches and the like -- and need a multi-cycle sequencer stepping
  // through a microcode ROM instead. is_microcoded() below is the
  // decode-time decision of which path an instruction takes; it lives here
  // rather than in isa_pkg.sv because the ISA doesn't mandate microcoding
  // anything -- it's purely an implementation choice, same as every other
  // guess in this file.
  //
  // No ROM contents defined yet -- this is only the sequencer's interface
  // shape (entry index width, per-uop control bits) so rtl/frontend has
  // something to build against.
  // --------------------------------------------------------------------
  localparam int UCODE_ROM_DEPTH   = 128;  // total uop slots across all routines
  localparam int UCODE_MAX_SEQ_LEN = 8;    // longest single routine (IRET et al.)
  localparam int UCODE_IDX_W       = $clog2(UCODE_ROM_DEPTH);

  typedef logic [UCODE_IDX_W-1:0] ucode_idx_t;

  // Frontend arbitration state: who's driving the uop stream this cycle.
  typedef enum logic {
    UCODE_IDLE   = 1'b0,  // hardware cracker supplies uops
    UCODE_ACTIVE = 1'b1   // sequencer is stepping through a ROM routine
  } ucode_seq_state_e;

  // [OURS] starting guess at which x86_op_e members need the sequencer
  // instead of the hardware crack. IRET/SYSCALL/SYSRET pop and validate
  // more state (privilege level, stack/segment switch) than a same-cycle
  // crack is worth building combinationally for; INT pushes a comparable
  // amount going the other direction. Revisit once decode exists -- REP-
  // prefixed string ops (MOVS/STOS/CMPS/SCAS/LODS) are the other classic
  // microcode candidates but aren't in x86_op_e yet.
  function automatic logic is_microcoded(x86_op_e op);
    unique case (op)
      X86_IRET, X86_SYSCALL, X86_SYSRET, X86_INT: return 1'b1;
      default:                                    return 1'b0;
    endcase
  endfunction

  // --------------------------------------------------------------------
  // structure sizing -- every one of these is a guess
  // --------------------------------------------------------------------
  // ANCHORED: tb/tb_top.sv:30 used an 8-bit ROB index. Power of two so the
  // index wraps for free -- no comparator on the wrap path. (Skylake: 224,
  // which is *not* a power of two because they don't wrap this way.)
  localparam int ROB_DEPTH       = 256;

  localparam int PREG_COUNT      = 180;  // int PRF; matches Skylake at 4-wide
  localparam int FPREG_COUNT     = 64;   // flag-group PRF; no reference point
  localparam int LQ_DEPTH        = 72;   // matches Skylake load buffer
  localparam int SQ_DEPTH        = 56;   // matches Skylake store buffer
  localparam int IQ_INT_DEPTH    = 48;   // split queues per port class, as
  localparam int IQ_MEM_DEPTH    = 32;   //   Skylake does (58 math + 39 AGU);
  localparam int IQ_BR_DEPTH     = 17;   //   ours total 97, matching Skylake

  // No justification beyond "small core, round number". Size these from your
  // own IPC experiments -- they're the most likely to be wrong.
  localparam int FETCH_BUF_DEPTH  = 64;  // bytes; kept at 2x FETCH_WIDTH
  localparam int RAS_DEPTH        = 16;
  localparam int BTB_ENTRIES      = 512;
  localparam int BHT_ENTRIES      = 1024;
  localparam int NUM_CHECKPOINTS  = 8;   // rename snapshots for fast recovery

  // --------------------------------------------------------------------
  // derived index widths -- these follow from the above, don't hand-edit
  // --------------------------------------------------------------------
  localparam int ROB_IDX_W   = $clog2(ROB_DEPTH);
  localparam int PREG_IDX_W  = $clog2(PREG_COUNT);
  localparam int FPREG_IDX_W = $clog2(FPREG_COUNT);
  localparam int LQ_IDX_W    = $clog2(LQ_DEPTH);
  localparam int SQ_IDX_W    = $clog2(SQ_DEPTH);
  localparam int CKPT_IDX_W  = $clog2(NUM_CHECKPOINTS);
  localparam int BR_TAG_W    = CKPT_IDX_W;   // one tag per in-flight checkpoint

  typedef logic [ROB_IDX_W-1:0]   rob_idx_t;
  typedef logic [PREG_IDX_W-1:0]  preg_t;
  typedef logic [FPREG_IDX_W-1:0] fpreg_t;
  typedef logic [LQ_IDX_W-1:0]    lq_idx_t;
  typedef logic [SQ_IDX_W-1:0]    sq_idx_t;
  typedef logic [BR_TAG_W-1:0]    br_tag_t;

  // --------------------------------------------------------------------
  // functional units / uop opcodes
  //
  // Our partitioning. One FU class per issue queue, plus FU_NONE for uops
  // eliminated at rename (nops, and reg-reg movs if you implement move
  // elimination).
  // --------------------------------------------------------------------
  typedef enum logic [2:0] {
    FU_ALU  = 3'd0,
    FU_MUL  = 3'd1,
    FU_DIV  = 3'd2,
    FU_BR   = 3'd3,
    FU_LD   = 3'd4,
    FU_ST   = 3'd5,
    FU_CSR  = 3'd6,   // csr/msr access, serializing
    FU_NONE = 3'd7    // eliminated at rename
  } fu_e;

  // Internal uop operation. Deliberately NOT isa_pkg::x86_op_e: one x86
  // instruction can expand into several of these, e.g.
  //   add [mem], reg  ->  UOP_LOAD, UOP_ADD, UOP_STORE
  // which is the entire reason a CISC front end feeds a RISC-ish core. Values
  // are arbitrary and internal; renumber freely.
  typedef enum logic [5:0] {
    UOP_NOP = 6'd0,
    // alu
    UOP_ADD, UOP_ADC, UOP_SUB, UOP_SBB, UOP_CMP,
    UOP_AND, UOP_OR, UOP_XOR, UOP_TEST,
    UOP_NEG, UOP_NOT, UOP_MOV, UOP_MOVZX, UOP_MOVSX, UOP_LEA,
    UOP_SHL, UOP_SHR, UOP_SAR, UOP_ROL, UOP_ROR, UOP_RCL, UOP_RCR,
    UOP_SETCC, UOP_CMOVCC,
    // mul / div
    UOP_MUL, UOP_IMUL, UOP_DIV, UOP_IDIV,
    // memory
    UOP_LOAD, UOP_STORE, UOP_LOAD_EXCL, UOP_STORE_COND, UOP_FENCE,
    // control flow
    UOP_JCC, UOP_JMP, UOP_JMP_IND, UOP_CALL, UOP_RET,
    // system
    UOP_HLT, UOP_INT, UOP_IRET, UOP_CLI, UOP_STI,
    UOP_CSR_RD, UOP_CSR_WR, UOP_RDTSC, UOP_CPUID, UOP_UD
  } uop_op_e;

  // --------------------------------------------------------------------
  // operand descriptor
  // --------------------------------------------------------------------
  typedef struct packed {
    logic  valid;      // this source is architecturally read
    preg_t preg;       // physical register
    logic  ready;      // set at dispatch if the producer already wrote back
  } src_spec_t;

  // --------------------------------------------------------------------
  // uop -- the token that flows rename -> dispatch -> issue -> execute
  //
  // R10000-style: sources are physical register tags resolved at rename, and
  // each uop carries the *previous* mapping of its destination so retire can
  // return it to the free list. See Yeager 1996 (cited in the header) for why
  // dst_prev lives here rather than in a side table.
  // --------------------------------------------------------------------
  typedef struct packed {
    logic       valid;

    // identity / bookkeeping
    rob_idx_t   rob_idx;
    vaddr_t     pc;         // pc of the x86 insn this uop came from
    logic [3:0] insn_len;   // bytes; 4 bits covers isa_pkg::MAX_INSN_LEN (15)
    logic       last_uop;   // final uop of the x86 insn -> retire boundary

    // microcode sequencer origin -- see the "microcode sequencer" section
    // above. ucode_last hands frontend arbitration back to the hardware
    // cracker (UCODE_ACTIVE -> UCODE_IDLE); kept separate from last_uop
    // (the ROB retire boundary) because today's one-routine-per-instruction
    // sequencer always sets both together, but a sequencer with call/return
    // between shared routines wouldn't.
    logic       ucode_valid;
    logic       ucode_last;

    // operation
    uop_op_e    op;
    fu_e        fu;
    opsize_e    size;
    cond_e      cc;         // valid for UOP_JCC / SETCC / CMOVCC

    // register operands (post-rename)
    src_spec_t  src1;
    src_spec_t  src2;
    logic       dst_valid;
    preg_t      dst;
    preg_t      dst_prev;   // previous mapping, freed at retire

    // flag dependency -- renamed as one group, see isa_pkg::flags_t
    logic       flags_src_valid;
    fpreg_t     flags_src;
    logic       flags_dst_valid;
    fpreg_t     flags_dst;
    fpreg_t     flags_dst_prev;

    // immediate / displacement
    logic       imm_valid;
    reg64_t     imm;

    // memory addressing (base/index arrive via src1/src2)
    logic [1:0] addr_scale;  // matches isa_pkg::sib_t.scale encoding
    seg_e       seg;
    lq_idx_t    lq_idx;
    sq_idx_t    sq_idx;

    // speculation
    br_tag_t    br_tag;      // youngest branch this uop is speculative under
    logic       pred_taken;
    vaddr_t     pred_target;

    // exception detected before execute (decode #UD, fetch page fault, ...)
    logic       exc_valid;
    exc_vec_e   exc_vec;
  } uop_t;

  localparam int UOP_WIDTH = $bits(uop_t);

  // --------------------------------------------------------------------
  // decoded-but-not-renamed instruction (decode -> rename boundary)
  //
  // Mirrors the x86 instruction format field-for-field, so this struct is
  // basically isa_pkg's encoding structs plus what the decoder extracted.
  // Field meanings: see the citations in isa_pkg.sv.
  // --------------------------------------------------------------------
  typedef struct packed {
    logic       valid;
    vaddr_t     pc;
    logic [3:0] insn_len;
    x86_op_e    x86_op;
    prefixes_t  prefixes;
    rex_t       rex;
    modrm_t     modrm;
    logic       modrm_valid;
    sib_t       sib;
    logic       sib_valid;
    opsize_e    opsize;
    reg64_t     imm;
    logic       imm_valid;
    reg64_t     disp;
    logic       disp_valid;
    cond_e      cc;
    logic       exc_valid;
    exc_vec_e   exc_vec;

    // microcode hand-off -- set when is_microcoded(x86_op) is true. Decode
    // stalls the hardware cracker and starts the sequencer at ucode_entry
    // instead of producing uops directly this cycle.
    logic       ucode_valid;
    ucode_idx_t ucode_entry;
  } dec_insn_t;

  // --------------------------------------------------------------------
  // execute -> writeback / bypass
  // --------------------------------------------------------------------
  typedef struct packed {
    logic     valid;
    rob_idx_t rob_idx;
    logic     dst_valid;
    preg_t    dst;
    reg64_t   data;
    logic     flags_valid;
    fpreg_t   flags_dst;
    flags_t   flags;
    logic     exc_valid;
    exc_vec_e exc_vec;
  } wb_pkt_t;

  // --------------------------------------------------------------------
  // branch resolution / redirect
  // --------------------------------------------------------------------
  typedef struct packed {
    logic     valid;
    rob_idx_t rob_idx;
    br_tag_t  br_tag;    // selects which rename checkpoint to restore
    logic     taken;
    vaddr_t   target;
    logic     mispredict;
  } br_resolve_t;

  typedef struct packed {
    logic   valid;
    vaddr_t target;
  } redirect_t;

  // --------------------------------------------------------------------
  // ROB entry
  // --------------------------------------------------------------------
  typedef enum logic [1:0] {
    ROB_EMPTY  = 2'd0,
    ROB_ISSUED = 2'd1,
    ROB_DONE   = 2'd2
  } rob_state_e;

  typedef struct packed {
    rob_state_e state;
    vaddr_t     pc;
    logic [3:0] insn_len;
    logic       last_uop;
    uop_op_e    op;

    logic       dst_valid;
    preg_t      dst;
    preg_t      dst_prev;      // returned to the free list at retire
    logic       flags_dst_valid;
    fpreg_t     flags_dst;
    fpreg_t     flags_dst_prev;

    logic       is_branch;
    logic       is_store;
    sq_idx_t    sq_idx;        // store queue entry to commit
    logic       mispredict;

    logic       exc_valid;
    exc_vec_e   exc_vec;

    // Drain the pipe around this uop. Needed for CSR/MSR writes, IRET and HLT
    // -- x86 requires some of these to be serializing; the architectural list
    // is in [SDM 3A, "Serializing Instructions"] (section number moved between
    // revisions, search the title).
    logic       serializing;
  } rob_entry_t;

  // --------------------------------------------------------------------
  // retire bus -- consumed by the commit RAT and by tb/tb_top.sv's monitor
  //
  // NOTE: tb_top.sv currently hand-rolls parallel packed arrays with its own
  // placeholder localparams instead of using this struct. Once cpu_top has a
  // port list, the TB should import cpu_pkg and use
  // retire_pkt_t [RETIRE_WIDTH-1:0]. See the TODO at tb/tb_top.sv:40.
  // --------------------------------------------------------------------
  typedef struct packed {
    logic     valid;
    vaddr_t   pc;
    rob_idx_t rob_idx;
    logic     exception;
    exc_vec_e exc_vec;
    logic     mispredict;
  } retire_pkt_t;

  // --------------------------------------------------------------------
  // frontend fetch packet
  // --------------------------------------------------------------------
  typedef struct packed {
    logic                     valid;
    vaddr_t                   pc;
    logic [FETCH_WIDTH*8-1:0] bytes;
    logic                     page_fault;   // itlb/page-walk fault -> EXC_PF
  } fetch_pkt_t;

endpackage : cpu_pkg

`endif
