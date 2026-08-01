// opcode enums, prefix enums, reg encodings
//
// Architectural (x86-64) definitions only. Nothing in here should depend on
// microarchitectural choices (ROB depth, preg count, issue width) -- those
// live in cpu_pkg.sv.
//
// ---------------------------------------------------------------------------
// CITATION CONVENTION
//
// Refs are volume + section/table TITLE, deliberately not page numbers: Intel
// repaginates on every SDM revision, and the combined-volume PDF is numbered
// differently from the 10-volume split, so page numbers rot immediately.
// Section and table numbers have been stable for years; the titles are quoted
// so you can still find them if a number moves.
//
//   [SDM n ...]  Intel 64 and IA-32 Architectures Software Developer's Manual
//                https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html
//                Vol 2A Ch. 2  = instruction format (prefixes, REX, ModRM, SIB)
//                Vol 1  Ch. 3  = basic execution environment (EFLAGS)
//                Vol 3A Ch. 4  = paging;  Vol 3A Ch. 6 = interrupts/exceptions
//   [APM 3 ...]  AMD64 Architecture Programmer's Manual Vol 3 (pub. 24594)
//                https://docs.amd.com/v/u/en-US/24594_3.37
//                Often clearer than Intel on encoding; opcode maps in App. A.
//   [OURS]       A design decision with no spec behind it. Change freely, but
//                update docs/pkg_sources.md when you do.
//
// Table/section numbers checked 2026-08-01. Full writeup, including which
// items were verified against sources and which were taken from memory of the
// manuals: docs/pkg_sources.md
// ---------------------------------------------------------------------------

`ifndef ISA_PKG_SV
`define ISA_PKG_SV

package isa_pkg;

  // --------------------------------------------------------------------
  // architectural widths
  // --------------------------------------------------------------------
  localparam int XLEN         = 64;  // GPR / linear address width

  // [OURS] 48 == what 4-level paging gives. 5-level paging would make this 57.
  // Canonical-form requirement (bits 63:47 must all match) is in
  // [SDM 1 "3.3.7.1 Canonical Addressing"]; paging modes in [SDM 3A Ch. 4].
  localparam int VADDR_WIDTH  = 48;

  // Architectural ceiling, not a free choice: MAXPHYADDR is reported by
  // CPUID.80000008H:EAX[7:0] and is "at most 52" --
  // [SDM 3A "4.1.4 Enumeration of Paging Features by CPUID"]
  localparam int PADDR_WIDTH  = 52;

  // Instructions longer than this raise #GP. Listed among the #GP conditions
  // in [SDM 3A "6.15 Exception and Interrupt Reference", Interrupt 13]:
  // "the instruction length exceeds 15 bytes" (only reachable via redundant
  // prefixes). rtl/frontend/predecode/length_decoder.sv must enforce it.
  localparam int MAX_INSN_LEN = 15;

  typedef logic [XLEN-1:0]        reg64_t;
  typedef logic [XLEN-1:0]        vaddr_t;
  typedef logic [PADDR_WIDTH-1:0] paddr_t;

  // --------------------------------------------------------------------
  // architectural register encodings
  //
  // These are the on-the-wire encodings, which is the whole point: the
  // ordering looks arbitrary (RCX=1, RDX=2, RBX=3) but it means
  // {rex.b, modrm.rm} indexes gpr_e directly, with no translation table.
  //
  // reg/rm number -> register: [SDM 2A Table 2-2 "32-Bit Addressing Forms
  // with the ModR/M Byte"] (register columns).
  // Extension to r8-r15 via REX.R/X/B: [SDM 2A Table 2-4 "REX Prefix Fields
  // [BITS: 0100WRXB]"].  Equivalent: [APM 3 App. A opcode maps].
  // --------------------------------------------------------------------
  localparam int ARCH_GPR_COUNT = 16;
  localparam int GPR_IDX_W      = $clog2(ARCH_GPR_COUNT);

  typedef enum logic [GPR_IDX_W-1:0] {
    RAX = 4'd0,  RCX = 4'd1,  RDX = 4'd2,  RBX = 4'd3,
    RSP = 4'd4,  RBP = 4'd5,  RSI = 4'd6,  RDI = 4'd7,
    R8  = 4'd8,  R9  = 4'd9,  R10 = 4'd10, R11 = 4'd11,
    R12 = 4'd12, R13 = 4'd13, R14 = 4'd14, R15 = 4'd15
  } gpr_e;

  // ES/CS/SS/DS/FS/GS == 0..5 is the architectural 3-bit sreg encoding, from
  // [SDM 2 App. B, "Segment Register (sreg) Field"] (same encoding the MOV
  // to/from segment-register forms use).
  //
  // SEG_NONE = 7 is [OURS]: encodings 6 and 7 are reserved by the spec, so we
  // squat on 7 as a "no segment override present" sentinel.
  typedef enum logic [2:0] {
    SEG_ES   = 3'd0,
    SEG_CS   = 3'd1,
    SEG_SS   = 3'd2,
    SEG_DS   = 3'd3,
    SEG_FS   = 3'd4,
    SEG_GS   = 3'd5,
    SEG_NONE = 3'd7   // [OURS] not architectural -- reserved encoding reused
  } seg_e;

  // --------------------------------------------------------------------
  // operand / address sizes
  //
  // [OURS] -- this is our own 2-bit encoding, there is no such field in the
  // ISA. Effective operand size is computed by the decoder from default size
  // + the 66 prefix + REX.W; see [SDM 2A "More on REX Prefix Fields"] under
  // 2.2.1, and Table 2-4 (REX.W = 64-bit operand size).
  // --------------------------------------------------------------------
  typedef enum logic [1:0] {
    SZ_8  = 2'd0,
    SZ_16 = 2'd1,
    SZ_32 = 2'd2,
    SZ_64 = 2'd3
  } opsize_e;

  // byte count for an opsize_e -- immediate sizing, store masks, etc.
  function automatic int unsigned opsize_bytes(opsize_e sz);
    unique case (sz)
      SZ_8:    return 1;
      SZ_16:   return 2;
      SZ_32:   return 4;
      default: return 8;
    endcase
  endfunction

  // --------------------------------------------------------------------
  // prefixes
  //
  // All bytes below: [SDM 2A "2.1.1 Instruction Prefixes"], which groups them
  // as group 1 (lock/repeat), group 2 (segment override), group 3 (operand
  // size), group 4 (address size). Equivalent: [APM 3 Ch. 1 "Instruction
  // Prefixes"].
  // --------------------------------------------------------------------
  localparam logic [7:0] PFX_LOCK     = 8'hF0;  // group 1
  localparam logic [7:0] PFX_REPNE    = 8'hF2;  // group 1
  localparam logic [7:0] PFX_REP      = 8'hF3;  // group 1
  localparam logic [7:0] PFX_OPSIZE   = 8'h66;  // group 3
  localparam logic [7:0] PFX_ADDRSIZE = 8'h67;  // group 4
  localparam logic [7:0] PFX_SEG_ES   = 8'h26;  // group 2
  localparam logic [7:0] PFX_SEG_CS   = 8'h2E;  // group 2
  localparam logic [7:0] PFX_SEG_SS   = 8'h36;  // group 2
  localparam logic [7:0] PFX_SEG_DS   = 8'h3E;  // group 2
  localparam logic [7:0] PFX_SEG_FS   = 8'h64;  // group 2
  localparam logic [7:0] PFX_SEG_GS   = 8'h65;  // group 2
  localparam logic [7:0] ESC_0F       = 8'h0F;  // two-byte opcode escape

  // [OURS] -- struct layout is ours; the individual bits above are the spec's.
  // Produced by rtl/frontend/predecode/prefix_scanner.sv.
  typedef struct packed {
    logic lock;
    logic rep;        // F3
    logic repne;      // F2
    logic opsize;     // 66
    logic addrsize;   // 67
    logic seg_valid;  // a segment override was seen
    seg_e seg;
  } prefixes_t;

  // REX byte layout 0100WRXB:
  // [SDM 2A Table 2-4 "REX Prefix Fields [BITS: 0100WRXB]"], see also
  // [SDM 2A "2.2.1 REX Prefixes"].
  //   W = 64-bit operand size
  //   R = extends ModRM.reg
  //   X = extends SIB.index
  //   B = extends ModRM.rm / SIB.base / opcode reg field
  typedef struct packed {
    logic present;
    logic w;
    logic r;
    logic x;
    logic b;
  } rex_t;

  // Any byte of the form 0100xxxx is a REX prefix -- [SDM 2A Table 2-4].
  // Only the high nibble identifies it; the low nibble is the WRXB payload,
  // hence the lint waiver.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic is_rex(logic [7:0] b);
    return (b[7:4] == 4'h4);
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  // --------------------------------------------------------------------
  // ModRM / SIB
  //
  // Byte layouts from [SDM 2A "2.1 Instruction Format for Protected Mode,
  // Real-Address Mode, and Virtual-8086 Mode", Figure 2-1] and the addressing
  // tables below:
  //   ModRM: [7:6]=mod, [5:3]=reg, [2:0]=rm   -- [SDM 2A Table 2-2]
  //   SIB:   [7:6]=scale, [5:3]=index, [2:0]=base -- [SDM 2A Table 2-3
  //          "32-Bit Addressing Forms with the SIB Byte"]
  //
  // WARNING: field order below is MSB-to-LSB to match the byte layout, so a
  // packed cast straight off the instruction stream works. Reordering these
  // fields breaks decode silently -- no compile error, just wrong registers.
  // --------------------------------------------------------------------
  typedef struct packed {
    logic [1:0] mod;
    logic [2:0] reg_f;   // spec calls this "reg"; renamed, `reg` is reserved
    logic [2:0] rm;
  } modrm_t;

  typedef struct packed {
    logic [1:0] scale;   // 1/2/4/8 scaling of index -- [SDM 2A Table 2-3]
    logic [2:0] index;
    logic [2:0] base;
  } sib_t;

  // Addressing-form escapes, all from [SDM 2A Table 2-2] / [Table 2-3]:
  localparam logic [2:0] RM_SIB_ESCAPE = 3'b100;  // rm=100, mod!=11 -> SIB follows
  localparam logic [2:0] RM_RIP_REL    = 3'b101;  // rm=101, mod=00 -> RIP+disp32
                                                  //   (64-bit mode; Table 2-2 note)
  localparam logic [2:0] IDX_NO_INDEX  = 3'b100;  // sib.index=100 -> no index reg

  // --------------------------------------------------------------------
  // condition codes
  //
  // The enum value IS the low nibble of the Jcc opcode (0x70 + cc), so the
  // decoder slices it straight out of the opcode byte. Same nibble is reused
  // by SETcc (0F 90+cc) and CMOVcc (0F 40+cc).
  //
  // Source: [SDM 2A "Jcc -- Jump if Condition Is Met"] opcode table; the field
  // is named tttn in [SDM 2 App. B, "Condition Test (tttn) Field"].
  // Convenient HTML mirror: https://www.felixcloutier.com/x86/jcc
  // --------------------------------------------------------------------
  typedef enum logic [3:0] {
    CC_O  = 4'h0, CC_NO = 4'h1,   // 70/71  OF=1 / OF=0
    CC_B  = 4'h2, CC_AE = 4'h3,   // 72/73  CF=1 / CF=0
    CC_E  = 4'h4, CC_NE = 4'h5,   // 74/75  ZF=1 / ZF=0
    CC_BE = 4'h6, CC_A  = 4'h7,   // 76/77  CF|ZF / !(CF|ZF)
    CC_S  = 4'h8, CC_NS = 4'h9,   // 78/79  SF=1 / SF=0
    CC_P  = 4'hA, CC_NP = 4'hB,   // 7A/7B  PF=1 / PF=0
    CC_L  = 4'hC, CC_GE = 4'hD,   // 7C/7D  SF!=OF / SF=OF
    CC_LE = 4'hE, CC_G  = 4'hF    // 7E/7F  ZF|(SF!=OF) / !ZF&(SF=OF)
  } cond_e;

  // --------------------------------------------------------------------
  // EFLAGS / RFLAGS
  //
  // Bit positions: [SDM 1 "3.4.3 EFLAGS Register", Figure 3-8]. Positions are
  // identical across FLAGS/EFLAGS/RFLAGS for compatibility. Bits 1, 3 and 5
  // are reserved, which is why the numbering below has gaps.
  // --------------------------------------------------------------------
  localparam int FLAG_CF = 0;
  localparam int FLAG_PF = 2;
  localparam int FLAG_AF = 4;
  localparam int FLAG_ZF = 6;
  localparam int FLAG_SF = 7;
  localparam int FLAG_TF = 8;
  localparam int FLAG_IF = 9;
  localparam int FLAG_DF = 10;
  localparam int FLAG_OF = 11;

  // [OURS] -- the *subset* and the decision to rename these six as one unit
  // is a microarchitectural choice, not architectural. It's the standard one:
  // it keeps every flag-writing uop from serializing against every
  // flag-reading uop. Status flags per [SDM 1 "3.4.3.1 Status Flags"];
  // TF/IF/DF are system flags and live in the architectural RFLAGS at retire,
  // not in this renamed group.
  typedef struct packed {
    logic cf;
    logic pf;
    logic af;
    logic zf;
    logic sf;
    logic of;
  } flags_t;

  localparam int FLAGS_WIDTH = $bits(flags_t);

  // Flag tests transcribed from the Jcc descriptions in
  // [SDM 2A "Jcc -- Jump if Condition Is Met"]. Shared by branch_unit,
  // SETcc and CMOVcc so the three can't disagree.
  //
  // f.af is intentionally never read: no x86 condition code tests AF. AF only
  // feeds the BCD adjust instructions (AAA/AAS/DAA/DAS), which don't exist in
  // 64-bit mode. That's what the UNUSEDSIGNAL waiver below is for -- it is not
  // a missing case.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic cond_true(cond_e cc, flags_t f); //what the hell are these
    unique case (cc)
      CC_O:    return  f.of;              // OF=1
      CC_NO:   return ~f.of;              // OF=0
      CC_B:    return  f.cf;              // CF=1
      CC_AE:   return ~f.cf;              // CF=0
      CC_E:    return  f.zf;              // ZF=1
      CC_NE:   return ~f.zf;              // ZF=0
      CC_BE:   return  f.cf | f.zf;       // CF=1 or ZF=1
      CC_A:    return ~(f.cf | f.zf);     // CF=0 and ZF=0
      CC_S:    return  f.sf;              // SF=1
      CC_NS:   return ~f.sf;              // SF=0
      CC_P:    return  f.pf;              // PF=1
      CC_NP:   return ~f.pf;              // PF=0
      CC_L:    return  f.sf ^ f.of;       // SF != OF
      CC_GE:   return ~(f.sf ^ f.of);     // SF == OF
      CC_LE:   return (f.sf ^ f.of) | f.zf;    // ZF=1 or SF != OF
      default: return ~((f.sf ^ f.of) | f.zf); // CC_G: ZF=0 and SF == OF
    endcase
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  // --------------------------------------------------------------------
  // instruction classes emitted by the opcode decoder
  //
  // [OURS] -- both the membership of this list (a subset of x86 we intend to
  // support) and the numeric values (auto-incremented, arbitrary). This enum
  // is purely internal; only the decoder's opcode tables have to match the
  // spec. Renumber freely.
  //
  // Opcode maps to build those tables from: [SDM 2D App. A "Opcode Map"] or
  // [APM 3 App. A]. Searchable mirrors: https://www.felixcloutier.com/x86/
  // and http://ref.x86asm.net/
  //
  // ISA-level: one entry per instruction family, not one per uop. The uop
  // opcode enum is cpu_pkg::uop_op_e.
  //
  // Whether a given member here is produced by the single-cycle hardware
  // crack or the multi-cycle microcode sequencer is a microarchitectural
  // choice, not an architectural one -- that classification stays out of
  // this file, in cpu_pkg::is_microcoded().
  // --------------------------------------------------------------------
  typedef enum logic [7:0] {
    X86_INVALID = 8'd0,
    // data movement
    X86_MOV, X86_MOVZX, X86_MOVSX, X86_LEA, X86_XCHG,
    X86_PUSH, X86_POP,
    // arithmetic / logic
    X86_ADD, X86_ADC, X86_SUB, X86_SBB, X86_CMP,
    X86_AND, X86_OR, X86_XOR, X86_TEST,
    X86_INC, X86_DEC, X86_NEG, X86_NOT,
    X86_MUL, X86_IMUL, X86_DIV, X86_IDIV,
    // shifts / rotates
    X86_SHL, X86_SHR, X86_SAR, X86_ROL, X86_ROR, X86_RCL, X86_RCR,
    // control flow
    X86_JMP, X86_JCC, X86_CALL, X86_RET, X86_LOOP,
    X86_SETCC, X86_CMOVCC,
    // system
    X86_NOP, X86_HLT, X86_INT, X86_IRET, X86_CLI, X86_STI,
    X86_CPUID, X86_RDMSR, X86_WRMSR, X86_RDTSC,
    X86_SYSCALL, X86_SYSRET, X86_UD2
  } x86_op_e;

  // --------------------------------------------------------------------
  // exception vectors
  //
  // Vector numbers and mnemonics: [SDM 3A Table 6-1 "Protected-Mode
  // Exceptions and Interrupts"], in [SDM 3A Ch. 6 "Interrupt and Exception
  // Handling"]. Per-vector detail (including what pushes an error code) is in
  // [SDM 3A "6.15 Exception and Interrupt Reference"].
  //
  // Vector 9 is deliberately absent: reserved (was Coprocessor Segment
  // Overrun on the 386). Do not fill in the hole.
  // Vectors 19-21 (#XM, #VE, #CP) exist but aren't modelled yet.
  // --------------------------------------------------------------------
  typedef enum logic [7:0] {
    EXC_DE  = 8'd0,   // divide error
    EXC_DB  = 8'd1,   // debug
    EXC_NMI = 8'd2,   // non-maskable interrupt
    EXC_BP  = 8'd3,   // breakpoint (INT3)
    EXC_OF  = 8'd4,   // overflow (INTO)
    EXC_BR  = 8'd5,   // BOUND range exceeded
    EXC_UD  = 8'd6,   // invalid opcode
    EXC_NM  = 8'd7,   // device not available
    EXC_DF  = 8'd8,   // double fault
                      // 9 reserved -- see note above
    EXC_TS  = 8'd10,  // invalid TSS
    EXC_NP  = 8'd11,  // segment not present
    EXC_SS  = 8'd12,  // stack-segment fault
    EXC_GP  = 8'd13,  // general protection
    EXC_PF  = 8'd14,  // page fault
                      // 15 reserved
    EXC_MF  = 8'd16,  // x87 floating-point error
    EXC_AC  = 8'd17,  // alignment check
    EXC_MC  = 8'd18   // machine check
  } exc_vec_e;

  // --------------------------------------------------------------------
  // privilege / operating mode
  // --------------------------------------------------------------------
  // Current privilege level, held in CS[1:0] --
  // [SDM 3A Ch. 5 "Protection", "Privilege Levels"].
  typedef logic [1:0] cpl_t;

  // [OURS] encoding. The modes themselves are architectural --
  // [SDM 3A "2.2 Modes of Operation"] / [SDM 1 "3.1 Modes of Operation"].
  // Only MODE_LONG is a near-term target; the others are placeholders so the
  // reset path and seg_unit have something to name.
  typedef enum logic [1:0] {
    MODE_REAL = 2'd0,
    MODE_PROT = 2'd1,   // 32-bit protected
    MODE_LONG = 2'd2    // 64-bit
  } cpu_mode_e;

endpackage : isa_pkg

`endif
