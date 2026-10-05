// x86_opcode_tables_pkg.sv
// Opcode attribute tables for the field extractor. Index with the opcode byte
// at the opcode-position marker; pick the table with the predecode table id.
//
//   table id 0 : OPC_MAP0      one-byte map
//   table id 1 : OPC_MAP0F     0F xx
//   table id 2 : OPC_MAP0F38   0F 38 xx
//   table id 3 : OPC_MAP0F3A   0F 3A xx
//   table id 4 : VEX / XOP, table chosen by the mmmmm field of the prefix
//                  VEX.mmmmm = 1 : OPC_VEX_0F
//                  VEX.mmmmm = 2 : OPC_VEX_0F38
//                  VEX.mmmmm = 3 : OPC_VEX_0F3A
//                  XOP.mmmmm = 8 : OPC_XOP_8
//                  XOP.mmmmm = 9 : OPC_XOP_9
//                  XOP.mmmmm = A : OPC_XOP_A
//                EVEX is not in this file.
//   GRP_ATTR[grp][ModR/M.reg] : secondary table for the group opcodes.
//
// Entry fields (opc_attr_t)
//   valid : opcode is defined. 0 = #UD, or a prefix/escape byte that can never
//           sit at the opcode position.
//   inv64 : defined in legacy/compat mode but #UD (or reused as REX/VEX/EVEX)
//           in 64-bit mode. Always 0 in the VEX and XOP tables.
//   modrm : a ModR/M byte follows the opcode.
//   group : ModR/M.reg extends the opcode. Same as (grp != GRP_NONE).
//   imm   : immediate kind, sized by the rules below.
//   grp   : row of GRP_ATTR to use when group is set.
//
// Immediate kinds (sizes in bytes)
//   IMM_NONE   0
//   IMM_8      1
//   IMM_16     2
//   IMM_16_8   3   ENTER: Iw then Ib
//   IMM_Z      2 if effective operand size is 16, else 4 (REX.W still gives 4)
//   IMM_JZ     near branch rel16/32. 64-bit mode: 4, except AMD honors 66 and
//              uses 2 (Intel ignores 66). Legacy: same as IMM_Z.
//   IMM_V      2 / 4 / 8 by operand size (8 only with REX.W, MOV r64,imm64)
//   IMM_MOFFS  address-size bytes: 8 in 64-bit mode, 4 with 67 (legacy 4 / 2)
//   IMM_PTR    far pointer, operand size + 2 (legacy only)
//   IMM_GRP3_8 1 if ModR/M.reg is 0 or 1 (TEST), else 0
//   IMM_GRP3_Z IMM_Z if ModR/M.reg is 0 or 1 (TEST), else 0
//   IMM_32     4, always (XOP map A)
//
// Undefined entries in the 0F38, 0F3A, VEX and XOP maps keep that map's
// uniform modrm/imm attributes so the length matches whatever predecode
// assumed. Undefined VEX 0F entries are given modrm = 1, no immediate.
//
// VEX and XOP tables
//   An entry is valid if any pp / L / W form of that opcode is defined; the
//   table does not check pp, L, W or vvvv. The row comment lists the mnemonics
//   that share the opcode.
//   Extensions included: AVX, AVX2 (with gathers), FMA, F16C, BMI1, BMI2,
//   VEX AES, VAES, VPCLMULQDQ, GFNI, AVX-VNNI, FMA4, XOP, TBM, LWP.
//   Extensions left out (marked undefined): AVX-512 opmask (K*) instructions,
//   AVX-IFMA, AVX-VNNI-INT8/INT16, AVX-NE-CONVERT, CMPccXADD, SHA512, SM3,
//   SM4, AMX.
//   The x87 escapes D8-DF are not treated as groups and have no GRP_ATTR row.
//
// Sources
//   Intel XED instruction database (datafiles/*), parsed from the repo:
//       https://github.com/intelxed/xed
//     The VEX and XOP tables are generated from it. The four legacy tables
//     and GRP_ATTR were written by hand and then compared against it entry
//     by entry (valid, modrm, immediate, and per-reg mem/reg validity).
//   x86reference.xml, the data behind ref.x86asm.net, second cross-check of
//   the legacy tables:
//       https://github.com/Barebit/x86reference
//       http://ref.x86asm.net/coder64.html
//   Authoritative opcode maps, not opened during generation:
//     AMD64 Architecture Programmer's Manual Vol 3, pub 24594, Appendix A
//       https://www.amd.com/content/dam/amd/en/documents/processor-tech-docs/programmer-references/24594.pdf
//     Intel SDM Vol 2, Appendix A
//       https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html
//     sandpile.org opcode maps
//       https://www.sandpile.org/x86/opc_1.htm
//
// Where the tables deliberately differ from XED (AMD-style core assumed)
//   Marked invalid although XED defines them:
//     0F 37 (GETSEC), 0F A6 / 0F A7 (VIA PadLock), 0F38 8A / 8B (MOVRS),
//     0F38 D8 / FA / FB (Key Locker), 0F38 FC (RAO-INT), 0F3A F0 (HRESET),
//     C6 /7 and C7 /7 (XABORT, XBEGIN), 0F 00 /6 (LKGS),
//     0F 01 /0 register forms (VMX, SGX), 0F C7 /6 and /7 memory forms (VMX),
//     0F AE /4 register form (PTWRITE).
//   0F 34 / 0F 35 (SYSENTER, SYSEXIT) are inv64: AMD raises #UD in long mode.
//   0F 0F (3DNow!) counts the suffix opcode byte as an imm8.
//   0F FF (UD0) has no ModR/M here; Intel consumes one.
//   0F 78 does not cover the SSE4a EXTRQ / INSERTQ forms with two imm8 bytes.
//   8F is POP Ev; the XOP escape check has to happen before the lookup.
//   0F 24 / 0F 26 (MOV to and from test registers, 386/486 only) are invalid.

package x86_opcode_tables_pkg;

  typedef enum logic [3:0] {
    IMM_NONE   = 4'd0,
    IMM_8      = 4'd1,
    IMM_16     = 4'd2,
    IMM_16_8   = 4'd3,
    IMM_Z      = 4'd4,
    IMM_JZ     = 4'd5,
    IMM_V      = 4'd6,
    IMM_MOFFS  = 4'd7,
    IMM_PTR    = 4'd8,
    IMM_GRP3_8 = 4'd9,
    IMM_GRP3_Z = 4'd10,
    IMM_32     = 4'd11
  } imm_kind_e;

  // Group ids. GRP_1 .. GRP_17 and GRP_P follow the AMD/Intel group numbering.
  // GRP_15V is VEX 0F AE. GRP_X9_01, GRP_X9_02, GRP_X9_12 and GRP_XA_12 are the
  // XOP map 9 / map A opcodes whose reg field selects the instruction.
  typedef enum logic [4:0] {
    GRP_NONE   = 5'd0,
    GRP_1      = 5'd1,
    GRP_1A     = 5'd2,
    GRP_2      = 5'd3,
    GRP_3      = 5'd4,
    GRP_4      = 5'd5,
    GRP_5      = 5'd6,
    GRP_6      = 5'd7,
    GRP_7      = 5'd8,
    GRP_8      = 5'd9,
    GRP_9      = 5'd10,
    GRP_10     = 5'd11,
    GRP_11     = 5'd12,
    GRP_12     = 5'd13,
    GRP_13     = 5'd14,
    GRP_14     = 5'd15,
    GRP_15     = 5'd16,
    GRP_16     = 5'd17,
    GRP_P      = 5'd18,
    GRP_17     = 5'd19,
    GRP_15V    = 5'd20,
    GRP_X9_01  = 5'd21,
    GRP_X9_02  = 5'd22,
    GRP_X9_12  = 5'd23,
    GRP_XA_12  = 5'd24
  } grp_e;

  localparam int GRP_NUM = 25;

  typedef struct packed {
    logic      valid;
    logic      inv64;
    logic      modrm;
    logic      group;
    imm_kind_e imm;
    grp_e      grp;
  } opc_attr_t;

  typedef struct packed {
    logic valid_mem;
    logic valid_reg;
    logic rm_ext;
    logic imm;
  } grp_attr_t;

  // Table id 0: one-byte opcode map
  //             valid inv64 modrm group imm          grp
  localparam opc_attr_t OPC_MAP0 [256] = '{
    8'h00: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ADD Eb,Gb
    8'h01: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ADD Ev,Gv
    8'h02: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ADD Gb,Eb
    8'h03: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ADD Gv,Ev
    8'h04: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // ADD AL,Ib
    8'h05: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_Z,       GRP_NONE},       // ADD rAX,Iz
    8'h06: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH ES
    8'h07: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP ES
    8'h08: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // OR Eb,Gb
    8'h09: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // OR Ev,Gv
    8'h0A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // OR Gb,Eb
    8'h0B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // OR Gv,Ev
    8'h0C: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // OR AL,Ib
    8'h0D: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_Z,       GRP_NONE},       // OR rAX,Iz
    8'h0E: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH CS
    8'h0F: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // escape to 0F map (never at opcode position)
    8'h10: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ADC Eb,Gb
    8'h11: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ADC Ev,Gv
    8'h12: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ADC Gb,Eb
    8'h13: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ADC Gv,Ev
    8'h14: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // ADC AL,Ib
    8'h15: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_Z,       GRP_NONE},       // ADC rAX,Iz
    8'h16: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH SS
    8'h17: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP SS
    8'h18: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SBB Eb,Gb
    8'h19: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SBB Ev,Gv
    8'h1A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SBB Gb,Eb
    8'h1B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SBB Gv,Ev
    8'h1C: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // SBB AL,Ib
    8'h1D: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_Z,       GRP_NONE},       // SBB rAX,Iz
    8'h1E: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH DS
    8'h1F: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP DS
    8'h20: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // AND Eb,Gb
    8'h21: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // AND Ev,Gv
    8'h22: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // AND Gb,Eb
    8'h23: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // AND Gv,Ev
    8'h24: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // AND AL,Ib
    8'h25: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_Z,       GRP_NONE},       // AND rAX,Iz
    8'h26: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // ES prefix (never at opcode position)
    8'h27: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // DAA
    8'h28: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SUB Eb,Gb
    8'h29: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SUB Ev,Gv
    8'h2A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SUB Gb,Eb
    8'h2B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SUB Gv,Ev
    8'h2C: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // SUB AL,Ib
    8'h2D: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_Z,       GRP_NONE},       // SUB rAX,Iz
    8'h2E: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // CS prefix (never at opcode position)
    8'h2F: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // DAS
    8'h30: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // XOR Eb,Gb
    8'h31: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // XOR Ev,Gv
    8'h32: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // XOR Gb,Eb
    8'h33: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // XOR Gv,Ev
    8'h34: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // XOR AL,Ib
    8'h35: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_Z,       GRP_NONE},       // XOR rAX,Iz
    8'h36: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // SS prefix (never at opcode position)
    8'h37: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // AAA
    8'h38: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMP Eb,Gb
    8'h39: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMP Ev,Gv
    8'h3A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMP Gb,Eb
    8'h3B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMP Gv,Ev
    8'h3C: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // CMP AL,Ib
    8'h3D: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_Z,       GRP_NONE},       // CMP rAX,Iz
    8'h3E: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // DS prefix (never at opcode position)
    8'h3F: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // AAS
    8'h40: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INC rAX (REX prefix in 64-bit)
    8'h41: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INC rCX (REX prefix in 64-bit)
    8'h42: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INC rDX (REX prefix in 64-bit)
    8'h43: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INC rBX (REX prefix in 64-bit)
    8'h44: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INC rSP (REX prefix in 64-bit)
    8'h45: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INC rBP (REX prefix in 64-bit)
    8'h46: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INC rSI (REX prefix in 64-bit)
    8'h47: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INC rDI (REX prefix in 64-bit)
    8'h48: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // DEC rAX (REX prefix in 64-bit)
    8'h49: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // DEC rCX (REX prefix in 64-bit)
    8'h4A: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // DEC rDX (REX prefix in 64-bit)
    8'h4B: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // DEC rBX (REX prefix in 64-bit)
    8'h4C: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // DEC rSP (REX prefix in 64-bit)
    8'h4D: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // DEC rBP (REX prefix in 64-bit)
    8'h4E: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // DEC rSI (REX prefix in 64-bit)
    8'h4F: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // DEC rDI (REX prefix in 64-bit)
    8'h50: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH rAX
    8'h51: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH rCX
    8'h52: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH rDX
    8'h53: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH rBX
    8'h54: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH rSP
    8'h55: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH rBP
    8'h56: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH rSI
    8'h57: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH rDI
    8'h58: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP rAX
    8'h59: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP rCX
    8'h5A: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP rDX
    8'h5B: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP rBX
    8'h5C: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP rSP
    8'h5D: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP rBP
    8'h5E: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP rSI
    8'h5F: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP rDI
    8'h60: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSHA
    8'h61: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POPA
    8'h62: '{1'b1, 1'b1, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // BOUND Gv,Ma (EVEX in 64-bit)
    8'h63: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVSXD Gv,Ed (ARPL Ew,Gw in legacy)
    8'h64: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // FS prefix (never at opcode position)
    8'h65: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // GS prefix (never at opcode position)
    8'h66: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // operand-size prefix (never at opcode position)
    8'h67: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // address-size prefix (never at opcode position)
    8'h68: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_Z,       GRP_NONE},       // PUSH Iz
    8'h69: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_Z,       GRP_NONE},       // IMUL Gv,Ev,Iz
    8'h6A: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // PUSH Ib
    8'h6B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // IMUL Gv,Ev,Ib
    8'h6C: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INSB
    8'h6D: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INSW/D
    8'h6E: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // OUTSB
    8'h6F: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // OUTSW/D
    8'h70: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JO Jb
    8'h71: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JNO Jb
    8'h72: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JB Jb
    8'h73: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JNB Jb
    8'h74: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JZ Jb
    8'h75: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JNZ Jb
    8'h76: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JBE Jb
    8'h77: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JNBE Jb
    8'h78: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JS Jb
    8'h79: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JNS Jb
    8'h7A: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JP Jb
    8'h7B: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JNP Jb
    8'h7C: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JL Jb
    8'h7D: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JNL Jb
    8'h7E: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JLE Jb
    8'h7F: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JNLE Jb
    8'h80: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_8,       GRP_1},          // Grp1 Eb,Ib
    8'h81: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_Z,       GRP_1},          // Grp1 Ev,Iz
    8'h82: '{1'b1, 1'b1, 1'b1, 1'b1, IMM_8,       GRP_1},          // Grp1 Eb,Ib (alias of 80)
    8'h83: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_8,       GRP_1},          // Grp1 Ev,Ib
    8'h84: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // TEST Eb,Gb
    8'h85: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // TEST Ev,Gv
    8'h86: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // XCHG Eb,Gb
    8'h87: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // XCHG Ev,Gv
    8'h88: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOV Eb,Gb
    8'h89: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOV Ev,Gv
    8'h8A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOV Gb,Eb
    8'h8B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOV Gv,Ev
    8'h8C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOV Ev,Sw
    8'h8D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // LEA Gv,M
    8'h8E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOV Sw,Ew
    8'h8F: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_1A},         // Grp1A POP Ev (XOP escape if next byte[4:0] >= 8)
    8'h90: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // NOP / PAUSE
    8'h91: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // XCHG rCX,rAX
    8'h92: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // XCHG rDX,rAX
    8'h93: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // XCHG rBX,rAX
    8'h94: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // XCHG rSP,rAX
    8'h95: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // XCHG rBP,rAX
    8'h96: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // XCHG rSI,rAX
    8'h97: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // XCHG rDI,rAX
    8'h98: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // CBW/CWDE/CDQE
    8'h99: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // CWD/CDQ/CQO
    8'h9A: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_PTR,     GRP_NONE},       // CALL Ap (far)
    8'h9B: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // FWAIT
    8'h9C: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSHF
    8'h9D: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POPF
    8'h9E: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // SAHF
    8'h9F: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // LAHF
    8'hA0: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_MOFFS,   GRP_NONE},       // MOV AL,Ob
    8'hA1: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_MOFFS,   GRP_NONE},       // MOV rAX,Ov
    8'hA2: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_MOFFS,   GRP_NONE},       // MOV Ob,AL
    8'hA3: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_MOFFS,   GRP_NONE},       // MOV Ov,rAX
    8'hA4: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // MOVSB
    8'hA5: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // MOVSW/D/Q
    8'hA6: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // CMPSB
    8'hA7: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // CMPSW/D/Q
    8'hA8: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // TEST AL,Ib
    8'hA9: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_Z,       GRP_NONE},       // TEST rAX,Iz
    8'hAA: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // STOSB
    8'hAB: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // STOSW/D/Q
    8'hAC: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // LODSB
    8'hAD: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // LODSW/D/Q
    8'hAE: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // SCASB
    8'hAF: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // SCASW/D/Q
    8'hB0: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // MOV r8,Ib
    8'hB1: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // MOV r8,Ib
    8'hB2: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // MOV r8,Ib
    8'hB3: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // MOV r8,Ib
    8'hB4: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // MOV r8,Ib
    8'hB5: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // MOV r8,Ib
    8'hB6: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // MOV r8,Ib
    8'hB7: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // MOV r8,Ib
    8'hB8: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_V,       GRP_NONE},       // MOV rAX,Iv
    8'hB9: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_V,       GRP_NONE},       // MOV rCX,Iv
    8'hBA: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_V,       GRP_NONE},       // MOV rDX,Iv
    8'hBB: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_V,       GRP_NONE},       // MOV rBX,Iv
    8'hBC: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_V,       GRP_NONE},       // MOV rSP,Iv
    8'hBD: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_V,       GRP_NONE},       // MOV rBP,Iv
    8'hBE: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_V,       GRP_NONE},       // MOV rSI,Iv
    8'hBF: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_V,       GRP_NONE},       // MOV rDI,Iv
    8'hC0: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_8,       GRP_2},          // Grp2 Eb,Ib
    8'hC1: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_8,       GRP_2},          // Grp2 Ev,Ib
    8'hC2: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_16,      GRP_NONE},       // RET Iw
    8'hC3: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // RET
    8'hC4: '{1'b1, 1'b1, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // LES Gz,Mp (VEX3 in 64-bit)
    8'hC5: '{1'b1, 1'b1, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // LDS Gz,Mp (VEX2 in 64-bit)
    8'hC6: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_8,       GRP_11},         // Grp11 MOV Eb,Ib
    8'hC7: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_Z,       GRP_11},         // Grp11 MOV Ev,Iz
    8'hC8: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_16_8,    GRP_NONE},       // ENTER Iw,Ib
    8'hC9: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // LEAVE
    8'hCA: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_16,      GRP_NONE},       // RETF Iw
    8'hCB: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // RETF
    8'hCC: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INT3
    8'hCD: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // INT Ib
    8'hCE: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INTO
    8'hCF: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // IRET
    8'hD0: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_2},          // Grp2 Eb,1
    8'hD1: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_2},          // Grp2 Ev,1
    8'hD2: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_2},          // Grp2 Eb,CL
    8'hD3: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_2},          // Grp2 Ev,CL
    8'hD4: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // AAM Ib
    8'hD5: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // AAD Ib
    8'hD6: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // SALC (undocumented)
    8'hD7: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // XLAT
    8'hD8: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // x87 escape D8
    8'hD9: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // x87 escape D9
    8'hDA: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // x87 escape DA
    8'hDB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // x87 escape DB
    8'hDC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // x87 escape DC
    8'hDD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // x87 escape DD
    8'hDE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // x87 escape DE
    8'hDF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // x87 escape DF
    8'hE0: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // LOOPNE Jb
    8'hE1: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // LOOPE Jb
    8'hE2: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // LOOP Jb
    8'hE3: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JrCXZ Jb
    8'hE4: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // IN AL,Ib
    8'hE5: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // IN eAX,Ib
    8'hE6: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // OUT Ib,AL
    8'hE7: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // OUT Ib,eAX
    8'hE8: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // CALL Jz
    8'hE9: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JMP Jz
    8'hEA: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_PTR,     GRP_NONE},       // JMP Ap (far)
    8'hEB: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_8,       GRP_NONE},       // JMP Jb
    8'hEC: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // IN AL,DX
    8'hED: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // IN eAX,DX
    8'hEE: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // OUT DX,AL
    8'hEF: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // OUT DX,eAX
    8'hF0: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // LOCK prefix (never at opcode position)
    8'hF1: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INT1 / ICEBP
    8'hF2: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // REPNE prefix (never at opcode position)
    8'hF3: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // REP prefix (never at opcode position)
    8'hF4: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // HLT
    8'hF5: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // CMC
    8'hF6: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_GRP3_8,  GRP_3},          // Grp3 Eb (Ib when reg = 0 or 1)
    8'hF7: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_GRP3_Z,  GRP_3},          // Grp3 Ev (Iz when reg = 0 or 1)
    8'hF8: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // CLC
    8'hF9: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // STC
    8'hFA: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // CLI
    8'hFB: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // STI
    8'hFC: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // CLD
    8'hFD: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // STD
    8'hFE: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_4},          // Grp4 INC/DEC Eb
    8'hFF: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_5}           // Grp5 INC/DEC/CALL/JMP/PUSH Ev
  };

  // Table id 1: 0F two-byte opcode map
  //             valid inv64 modrm group imm          grp
  localparam opc_attr_t OPC_MAP0F [256] = '{
    8'h00: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_6},          // Grp6 SLDT/STR/LLDT/LTR/VERR/VERW
    8'h01: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_7},          // Grp7 SGDT/SIDT/LGDT/LIDT/SMSW/LMSW/INVLPG + reg-form ops
    8'h02: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // LAR Gv,Ew
    8'h03: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // LSL Gv,Ew
    8'h04: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h05: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // SYSCALL
    8'h06: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // CLTS
    8'h07: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // SYSRET
    8'h08: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // INVD
    8'h09: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // WBINVD
    8'h0A: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0B: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // UD2
    8'h0C: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0D: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_P},          // GrpP PREFETCH/PREFETCHW
    8'h0E: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // FEMMS (3DNow!)
    8'h0F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // 3DNow! (suffix opcode byte as Ib)
    8'h10: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVUPS/MOVUPD/MOVSS/MOVSD V,W
    8'h11: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVUPS/MOVUPD/MOVSS/MOVSD W,V
    8'h12: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVLPS/MOVHLPS/MOVLPD/MOVSLDUP/MOVDDUP
    8'h13: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVLPS/MOVLPD M,V
    8'h14: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // UNPCKLPS/PD
    8'h15: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // UNPCKHPS/PD
    8'h16: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVHPS/MOVLHPS/MOVHPD/MOVSHDUP
    8'h17: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVHPS/MOVHPD M,V
    8'h18: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_16},         // Grp16 PREFETCHNTA/T0/T1/T2
    8'h19: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // hint NOP Ev
    8'h1A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // hint NOP Ev
    8'h1B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // hint NOP Ev
    8'h1C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // hint NOP Ev
    8'h1D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // hint NOP Ev
    8'h1E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // hint NOP Ev (ENDBR/RDSSP with F3)
    8'h1F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // NOP Ev
    8'h20: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOV Rd,Cd
    8'h21: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOV Rd,Dd
    8'h22: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOV Cd,Rd
    8'h23: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOV Dd,Rd
    8'h24: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h25: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h26: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h27: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h28: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVAPS/MOVAPD V,W
    8'h29: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVAPS/MOVAPD W,V
    8'h2A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CVTPI2PS/CVTSI2SS/CVTPI2PD/CVTSI2SD
    8'h2B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVNTPS/MOVNTPD (MOVNTSS/SD SSE4a)
    8'h2C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CVTTPS2PI/CVTTSS2SI/CVTTPD2PI/CVTTSD2SI
    8'h2D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CVTPS2PI/CVTSS2SI/CVTPD2PI/CVTSD2SI
    8'h2E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // UCOMISS/UCOMISD
    8'h2F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // COMISS/COMISD
    8'h30: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // WRMSR
    8'h31: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // RDTSC
    8'h32: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // RDMSR
    8'h33: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // RDPMC
    8'h34: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // SYSENTER (AMD: #UD in long mode)
    8'h35: '{1'b1, 1'b1, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // SYSEXIT (AMD: #UD in long mode)
    8'h36: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h37: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined; GETSEC on Intel)
    8'h38: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // escape to 0F38 map (never at opcode position)
    8'h39: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3A: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // escape to 0F3A map (never at opcode position)
    8'h3B: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3C: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3D: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3E: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3F: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h40: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVO Gv,Ev
    8'h41: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVNO Gv,Ev
    8'h42: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVB Gv,Ev
    8'h43: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVNB Gv,Ev
    8'h44: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVZ Gv,Ev
    8'h45: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVNZ Gv,Ev
    8'h46: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVBE Gv,Ev
    8'h47: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVNBE Gv,Ev
    8'h48: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVS Gv,Ev
    8'h49: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVNS Gv,Ev
    8'h4A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVP Gv,Ev
    8'h4B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVNP Gv,Ev
    8'h4C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVL Gv,Ev
    8'h4D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVNL Gv,Ev
    8'h4E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVLE Gv,Ev
    8'h4F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMOVNLE Gv,Ev
    8'h50: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVMSKPS/PD
    8'h51: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SQRTxx
    8'h52: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // RSQRTPS/SS
    8'h53: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // RCPPS/SS
    8'h54: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ANDPS/PD
    8'h55: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ANDNPS/PD
    8'h56: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ORPS/PD
    8'h57: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // XORPS/PD
    8'h58: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ADDxx
    8'h59: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MULxx
    8'h5A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CVTPS2PD/PD2PS/SS2SD/SD2SS
    8'h5B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CVTDQ2PS/PS2DQ/TTPS2DQ
    8'h5C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SUBxx
    8'h5D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MINxx
    8'h5E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // DIVxx
    8'h5F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MAXxx
    8'h60: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PUNPCKLBW
    8'h61: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PUNPCKLWD
    8'h62: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PUNPCKLDQ
    8'h63: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PACKSSWB
    8'h64: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PCMPGTB
    8'h65: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PCMPGTW
    8'h66: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PCMPGTD
    8'h67: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PACKUSWB
    8'h68: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PUNPCKHBW
    8'h69: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PUNPCKHWD
    8'h6A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PUNPCKHDQ
    8'h6B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PACKSSDW
    8'h6C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PUNPCKLQDQ (66)
    8'h6D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PUNPCKHQDQ (66)
    8'h6E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVD/MOVQ P/V,Ey
    8'h6F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVQ/MOVDQA/MOVDQU P/V,Q/W
    8'h70: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PSHUFW/PSHUFD/PSHUFHW/PSHUFLW Ib
    8'h71: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_8,       GRP_12},         // Grp12 PSRLW/PSRAW/PSLLW Ib
    8'h72: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_8,       GRP_13},         // Grp13 PSRLD/PSRAD/PSLLD Ib
    8'h73: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_8,       GRP_14},         // Grp14 PSRLQ/PSRLDQ/PSLLQ/PSLLDQ Ib
    8'h74: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PCMPEQB
    8'h75: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PCMPEQW
    8'h76: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PCMPEQD
    8'h77: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // EMMS
    8'h78: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMREAD (SSE4a EXTRQ/INSERTQ Ib,Ib forms not covered)
    8'h79: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMWRITE (SSE4a EXTRQ/INSERTQ reg forms)
    8'h7A: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7B: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // HADDPD/HADDPS (66/F2)
    8'h7D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // HSUBPD/HSUBPS (66/F2)
    8'h7E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVD/MOVQ Ey,P/V, MOVQ V,W (F3)
    8'h7F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVQ/MOVDQA/MOVDQU Q/W,P/V
    8'h80: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JO Jz
    8'h81: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JNO Jz
    8'h82: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JB Jz
    8'h83: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JNB Jz
    8'h84: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JZ Jz
    8'h85: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JNZ Jz
    8'h86: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JBE Jz
    8'h87: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JNBE Jz
    8'h88: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JS Jz
    8'h89: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JNS Jz
    8'h8A: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JP Jz
    8'h8B: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JNP Jz
    8'h8C: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JL Jz
    8'h8D: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JNL Jz
    8'h8E: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JLE Jz
    8'h8F: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_JZ,      GRP_NONE},       // JNLE Jz
    8'h90: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETO Eb
    8'h91: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETNO Eb
    8'h92: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETB Eb
    8'h93: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETNB Eb
    8'h94: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETZ Eb
    8'h95: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETNZ Eb
    8'h96: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETBE Eb
    8'h97: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETNBE Eb
    8'h98: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETS Eb
    8'h99: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETNS Eb
    8'h9A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETP Eb
    8'h9B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETNP Eb
    8'h9C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETL Eb
    8'h9D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETNL Eb
    8'h9E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETLE Eb
    8'h9F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SETNLE Eb
    8'hA0: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH FS
    8'hA1: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP FS
    8'hA2: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // CPUID
    8'hA3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // BT Ev,Gv
    8'hA4: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // SHLD Ev,Gv,Ib
    8'hA5: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SHLD Ev,Gv,CL
    8'hA6: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA7: '{1'b0, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA8: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // PUSH GS
    8'hA9: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // POP GS
    8'hAA: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // RSM
    8'hAB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // BTS Ev,Gv
    8'hAC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // SHRD Ev,Gv,Ib
    8'hAD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SHRD Ev,Gv,CL
    8'hAE: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_15},         // Grp15 FXSAVE/FXRSTOR/LDMXCSR/STMXCSR/XSAVE/fences/CLFLUSH
    8'hAF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // IMUL Gv,Ev
    8'hB0: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMPXCHG Eb,Gb
    8'hB1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CMPXCHG Ev,Gv
    8'hB2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // LSS Gz,Mp
    8'hB3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // BTR Ev,Gv
    8'hB4: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // LFS Gz,Mp
    8'hB5: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // LGS Gz,Mp
    8'hB6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVZX Gv,Eb
    8'hB7: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVZX Gv,Ew
    8'hB8: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // POPCNT Gv,Ev (F3 required)
    8'hB9: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_10},         // Grp10 UD1
    8'hBA: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_8,       GRP_8},          // Grp8 BT/BTS/BTR/BTC Ev,Ib
    8'hBB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // BTC Ev,Gv
    8'hBC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // BSF / TZCNT (F3)
    8'hBD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // BSR / LZCNT (F3)
    8'hBE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVSX Gv,Eb
    8'hBF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVSX Gv,Ew
    8'hC0: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // XADD Eb,Gb
    8'hC1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // XADD Ev,Gv
    8'hC2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // CMPPS/PD/SS/SD Ib
    8'hC3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVNTI My,Gy
    8'hC4: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PINSRW Ib
    8'hC5: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PEXTRW Ib
    8'hC6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // SHUFPS/SHUFPD Ib
    8'hC7: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_9},          // Grp9 CMPXCHG8B/16B, RDRAND, RDSEED, RDPID
    8'hC8: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // BSWAP rAX
    8'hC9: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // BSWAP rCX
    8'hCA: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // BSWAP rDX
    8'hCB: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // BSWAP rBX
    8'hCC: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // BSWAP rSP
    8'hCD: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // BSWAP rBP
    8'hCE: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // BSWAP rSI
    8'hCF: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // BSWAP rDI
    8'hD0: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ADDSUBPD/PS (66/F2)
    8'hD1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSRLW
    8'hD2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSRLD
    8'hD3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSRLQ
    8'hD4: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PADDQ
    8'hD5: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMULLW
    8'hD6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVQ W,V / MOVQ2DQ / MOVDQ2Q
    8'hD7: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVMSKB
    8'hD8: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSUBUSB
    8'hD9: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSUBUSW
    8'hDA: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMINUB
    8'hDB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PAND
    8'hDC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PADDUSB
    8'hDD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PADDUSW
    8'hDE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMAXUB
    8'hDF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PANDN
    8'hE0: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PAVGB
    8'hE1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSRAW
    8'hE2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSRAD
    8'hE3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PAVGW
    8'hE4: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMULHUW
    8'hE5: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMULHW
    8'hE6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // CVTTPD2DQ/CVTDQ2PD/CVTPD2DQ
    8'hE7: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVNTQ/MOVNTDQ
    8'hE8: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSUBSB
    8'hE9: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSUBSW
    8'hEA: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMINSW
    8'hEB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // POR
    8'hEC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PADDSB
    8'hED: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PADDSW
    8'hEE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMAXSW
    8'hEF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PXOR
    8'hF0: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // LDDQU (F2)
    8'hF1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSLLW
    8'hF2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSLLD
    8'hF3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSLLQ
    8'hF4: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMULUDQ
    8'hF5: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMADDWD
    8'hF6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSADBW
    8'hF7: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MASKMOVQ/MASKMOVDQU
    8'hF8: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSUBB
    8'hF9: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSUBW
    8'hFA: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSUBD
    8'hFB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSUBQ
    8'hFC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PADDB
    8'hFD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PADDW
    8'hFE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PADDD
    8'hFF: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE}        // UD0
  };

  // Table id 2: 0F 38 three-byte opcode map
  //             valid inv64 modrm group imm          grp
  localparam opc_attr_t OPC_MAP0F38 [256] = '{
    8'h00: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSHUFB
    8'h01: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PHADDW
    8'h02: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PHADDD
    8'h03: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PHADDSW
    8'h04: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMADDUBSW
    8'h05: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PHSUBW
    8'h06: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PHSUBD
    8'h07: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PHSUBSW
    8'h08: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSIGNB
    8'h09: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSIGNW
    8'h0A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PSIGND
    8'h0B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMULHRSW
    8'h0C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h10: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PBLENDVB
    8'h11: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h12: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h13: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h14: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // BLENDVPS
    8'h15: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // BLENDVPD
    8'h16: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h17: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PTEST
    8'h18: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h19: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PABSB
    8'h1D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PABSW
    8'h1E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PABSD
    8'h1F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h20: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVSXBW
    8'h21: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVSXBD
    8'h22: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVSXBQ
    8'h23: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVSXWD
    8'h24: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVSXWQ
    8'h25: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVSXDQ
    8'h26: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h27: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h28: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMULDQ
    8'h29: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PCMPEQQ
    8'h2A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVNTDQA
    8'h2B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PACKUSDW
    8'h2C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h2D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h2E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h2F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h30: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVZXBW
    8'h31: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVZXBD
    8'h32: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVZXBQ
    8'h33: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVZXWD
    8'h34: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVZXWQ
    8'h35: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMOVZXDQ
    8'h36: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h37: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PCMPGTQ
    8'h38: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMINSB
    8'h39: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMINSD
    8'h3A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMINUW
    8'h3B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMINUD
    8'h3C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMAXSB
    8'h3D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMAXSD
    8'h3E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMAXUW
    8'h3F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMAXUD
    8'h40: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PMULLD
    8'h41: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PHMINPOSUW
    8'h42: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h43: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h44: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h45: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h46: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h47: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h48: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h49: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h50: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h51: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h52: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h53: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h54: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h55: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h56: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h57: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h58: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h59: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h60: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h61: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h62: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h63: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h64: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h65: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h66: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h67: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h68: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h69: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h70: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h71: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h72: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h73: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h74: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h75: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h76: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h77: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h78: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h79: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h80: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // INVEPT
    8'h81: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // INVVPID
    8'h82: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // INVPCID
    8'h83: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h84: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h85: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h86: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h87: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h88: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h89: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h90: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h91: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h92: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h93: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h94: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h95: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h96: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h97: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h98: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h99: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC8: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SHA1NEXTE
    8'hC9: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SHA1MSG1
    8'hCA: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SHA1MSG2
    8'hCB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SHA256RNDS2
    8'hCC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SHA256MSG1
    8'hCD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // SHA256MSG2
    8'hCE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // GF2P8MULB
    8'hD0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hDA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hDB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // AESIMC
    8'hDC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // AESENC
    8'hDD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // AESENCLAST
    8'hDE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // AESDEC
    8'hDF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // AESDECLAST
    8'hE0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hED: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF0: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVBE Gv,Mv / CRC32 Gd,Eb (F2)
    8'hF1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVBE Mv,Gv / CRC32 Gd,Ev (F2)
    8'hF2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF5: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // WRUSS (66)
    8'hF6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ADCX (66) / ADOX (F3) / WRSS
    8'hF7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF8: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVDIR64B (66)
    8'hF9: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MOVDIRI
    8'hFA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE}        // (undefined)
  };

  // Table id 3: 0F 3A three-byte opcode map
  //             valid inv64 modrm group imm          grp
  localparam opc_attr_t OPC_MAP0F3A [256] = '{
    8'h00: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h01: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h02: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h03: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h04: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h05: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h06: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h07: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h08: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // ROUNDPS Ib
    8'h09: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // ROUNDPD Ib
    8'h0A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // ROUNDSS Ib
    8'h0B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // ROUNDSD Ib
    8'h0C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // BLENDPS Ib
    8'h0D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // BLENDPD Ib
    8'h0E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PBLENDW Ib
    8'h0F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PALIGNR Ib
    8'h10: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h11: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h12: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h13: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h14: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PEXTRB Ib
    8'h15: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PEXTRW Ib
    8'h16: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PEXTRD/PEXTRQ Ib
    8'h17: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // EXTRACTPS Ib
    8'h18: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h19: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h20: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PINSRB Ib
    8'h21: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // INSERTPS Ib
    8'h22: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PINSRD/PINSRQ Ib
    8'h23: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h24: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h25: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h26: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h27: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h28: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h29: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h30: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h31: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h32: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h33: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h34: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h35: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h36: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h37: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h38: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h39: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h40: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // DPPS Ib
    8'h41: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // DPPD Ib
    8'h42: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // MPSADBW Ib
    8'h43: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h44: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PCLMULQDQ Ib
    8'h45: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h46: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h47: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h48: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h49: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h50: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h51: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h52: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h53: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h54: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h55: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h56: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h57: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h58: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h59: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h60: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PCMPESTRM Ib
    8'h61: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PCMPESTRI Ib
    8'h62: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PCMPISTRM Ib
    8'h63: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // PCMPISTRI Ib
    8'h64: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h65: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h66: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h67: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h68: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h69: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h6A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h6B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h6C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h6D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h6E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h6F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h70: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h71: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h72: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h73: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h74: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h75: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h76: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h77: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h78: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h79: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h7A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h7B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h7C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h7D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h7E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h7F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h80: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h81: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h82: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h83: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h84: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h85: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h86: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h87: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h88: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h89: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h90: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h91: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h92: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h93: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h94: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h95: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h96: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h97: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h98: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h99: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hCA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hCB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hCC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // SHA1RNDS4 Ib
    8'hCD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hCE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // GF2P8AFFINEQB Ib
    8'hCF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // GF2P8AFFINEINVQB Ib
    8'hD0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // AESKEYGENASSIST Ib
    8'hE0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hED: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE}        // (undefined)
  };

  // VEX map 1 (VEX.mmmmm = 1): VEX 0F
  //             valid inv64 modrm group imm          grp
  localparam opc_attr_t OPC_VEX_0F [256] = '{
    8'h00: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h01: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h02: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h03: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h04: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h05: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h06: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h07: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h08: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h09: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h10: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVSS/VMOVSD/VMOVUPD/VMOVUPS
    8'h11: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVSS/VMOVSD/VMOVUPD/VMOVUPS
    8'h12: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVDDUP/VMOVSLDUP/VMOVHLPS/VMOVLPD/VMOVLPS
    8'h13: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVLPD/VMOVLPS
    8'h14: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VUNPCKLPD/VUNPCKLPS
    8'h15: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VUNPCKHPD/VUNPCKHPS
    8'h16: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVSHDUP/VMOVLHPS/VMOVHPD/VMOVHPS
    8'h17: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVHPD/VMOVHPS
    8'h18: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h19: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h20: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h21: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h22: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h23: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h24: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h25: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h26: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h27: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h28: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVAPD/VMOVAPS
    8'h29: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVAPD/VMOVAPS
    8'h2A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VCVTSI2SD/VCVTSI2SS
    8'h2B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVNTPD/VMOVNTPS
    8'h2C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VCVTTSD2SI/VCVTTSS2SI
    8'h2D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VCVTSD2SI/VCVTSS2SI
    8'h2E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VUCOMISD/VUCOMISS
    8'h2F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VCOMISD/VCOMISS
    8'h30: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h31: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h32: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h33: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h34: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h35: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h36: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h37: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h38: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h39: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h40: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h41: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h42: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h43: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h44: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h45: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h46: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h47: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h48: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h49: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h50: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVMSKPD/VMOVMSKPS
    8'h51: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VSQRTPD/VSQRTPS/VSQRTSD/VSQRTSS
    8'h52: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VRSQRTPS/VRSQRTSS
    8'h53: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VRCPPS/VRCPSS
    8'h54: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VANDPD/VANDPS
    8'h55: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VANDNPD/VANDNPS
    8'h56: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VORPD/VORPS
    8'h57: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VXORPD/VXORPS
    8'h58: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VADDPD/VADDPS/VADDSD/VADDSS
    8'h59: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMULPD/VMULPS/VMULSD/VMULSS
    8'h5A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VCVTPD2PS/VCVTPS2PD/VCVTSD2SS/VCVTSS2SD
    8'h5B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VCVTDQ2PS/VCVTPS2DQ/VCVTTPS2DQ
    8'h5C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VSUBPD/VSUBPS/VSUBSD/VSUBSS
    8'h5D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMINPD/VMINPS/VMINSD/VMINSS
    8'h5E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VDIVPD/VDIVPS/VDIVSD/VDIVSS
    8'h5F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMAXPD/VMAXPS/VMAXSD/VMAXSS
    8'h60: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPUNPCKLBW
    8'h61: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPUNPCKLWD
    8'h62: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPUNPCKLDQ
    8'h63: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPACKSSWB
    8'h64: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPCMPGTB
    8'h65: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPCMPGTW
    8'h66: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPCMPGTD
    8'h67: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPACKUSWB
    8'h68: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPUNPCKHBW
    8'h69: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPUNPCKHWD
    8'h6A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPUNPCKHDQ
    8'h6B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPACKSSDW
    8'h6C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPUNPCKLQDQ
    8'h6D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPUNPCKHQDQ
    8'h6E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVD/VMOVQ
    8'h6F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVDQA/VMOVDQU
    8'h70: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPSHUFD/VPSHUFHW/VPSHUFLW Ib
    8'h71: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_8,       GRP_12},         // VPSLLW/VPSRAW/VPSRLW Ib
    8'h72: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_8,       GRP_13},         // VPSLLD/VPSRAD/VPSRLD Ib
    8'h73: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_8,       GRP_14},         // VPSRLDQ/VPSLLDQ/VPSLLQ/VPSRLQ Ib
    8'h74: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPCMPEQB
    8'h75: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPCMPEQW
    8'h76: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPCMPEQD
    8'h77: '{1'b1, 1'b0, 1'b0, 1'b0, IMM_NONE,    GRP_NONE},       // VZEROALL/VZEROUPPER
    8'h78: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h79: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VHADDPD/VHADDPS
    8'h7D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VHSUBPD/VHSUBPS
    8'h7E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVD/VMOVQ
    8'h7F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVDQA/VMOVDQU
    8'h80: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h81: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h82: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h83: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h84: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h85: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h86: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h87: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h88: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h89: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h90: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h91: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h92: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h93: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h94: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h95: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h96: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h97: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h98: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h99: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAE: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_15V},        // VLDMXCSR/VSTMXCSR
    8'hAF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VCMPPD/VCMPPS/VCMPSD/VCMPSS Ib
    8'hC3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC4: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPINSRW Ib
    8'hC5: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPEXTRW Ib
    8'hC6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VSHUFPD/VSHUFPS Ib
    8'hC7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD0: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VADDSUBPD/VADDSUBPS
    8'hD1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSRLW
    8'hD2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSRLD
    8'hD3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSRLQ
    8'hD4: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPADDQ
    8'hD5: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMULLW
    8'hD6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVQ
    8'hD7: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVMSKB
    8'hD8: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSUBUSB
    8'hD9: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSUBUSW
    8'hDA: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMINUB
    8'hDB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPAND
    8'hDC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPADDUSB
    8'hDD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPADDUSW
    8'hDE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMAXUB
    8'hDF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPANDN
    8'hE0: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPAVGB
    8'hE1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSRAW
    8'hE2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSRAD
    8'hE3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPAVGW
    8'hE4: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMULHUW
    8'hE5: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMULHW
    8'hE6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VCVTDQ2PD/VCVTPD2DQ/VCVTTPD2DQ
    8'hE7: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVNTDQ
    8'hE8: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSUBSB
    8'hE9: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSUBSW
    8'hEA: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMINSW
    8'hEB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPOR
    8'hEC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPADDSB
    8'hED: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPADDSW
    8'hEE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMAXSW
    8'hEF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPXOR
    8'hF0: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VLDDQU
    8'hF1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSLLW
    8'hF2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSLLD
    8'hF3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSLLQ
    8'hF4: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMULUDQ
    8'hF5: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMADDWD
    8'hF6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSADBW
    8'hF7: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMASKMOVDQU
    8'hF8: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSUBB
    8'hF9: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSUBW
    8'hFA: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSUBD
    8'hFB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSUBQ
    8'hFC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPADDB
    8'hFD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPADDW
    8'hFE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPADDD
    8'hFF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE}        // (undefined)
  };

  // VEX map 2 (VEX.mmmmm = 2): VEX 0F 38
  //             valid inv64 modrm group imm          grp
  localparam opc_attr_t OPC_VEX_0F38 [256] = '{
    8'h00: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSHUFB
    8'h01: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDW
    8'h02: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDD
    8'h03: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDSW
    8'h04: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMADDUBSW
    8'h05: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHSUBW
    8'h06: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHSUBD
    8'h07: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHSUBSW
    8'h08: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSIGNB
    8'h09: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSIGNW
    8'h0A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSIGND
    8'h0B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMULHRSW
    8'h0C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPERMILPS
    8'h0D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPERMILPD
    8'h0E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VTESTPS
    8'h0F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VTESTPD
    8'h10: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h11: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h12: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h13: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VCVTPH2PS
    8'h14: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h15: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h16: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPERMPS
    8'h17: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPTEST
    8'h18: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VBROADCASTSS
    8'h19: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VBROADCASTSD
    8'h1A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VBROADCASTF128
    8'h1B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPABSB
    8'h1D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPABSW
    8'h1E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPABSD
    8'h1F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h20: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVSXBW
    8'h21: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVSXBD
    8'h22: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVSXBQ
    8'h23: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVSXWD
    8'h24: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVSXWQ
    8'h25: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVSXDQ
    8'h26: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h27: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h28: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMULDQ
    8'h29: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPCMPEQQ
    8'h2A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMOVNTDQA
    8'h2B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPACKUSDW
    8'h2C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMASKMOVPS
    8'h2D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMASKMOVPD
    8'h2E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMASKMOVPS
    8'h2F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VMASKMOVPD
    8'h30: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVZXBW
    8'h31: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVZXBD
    8'h32: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVZXBQ
    8'h33: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVZXWD
    8'h34: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVZXWQ
    8'h35: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMOVZXDQ
    8'h36: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPERMD
    8'h37: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPCMPGTQ
    8'h38: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMINSB
    8'h39: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMINSD
    8'h3A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMINUW
    8'h3B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMINUD
    8'h3C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMAXSB
    8'h3D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMAXSD
    8'h3E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMAXUW
    8'h3F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMAXUD
    8'h40: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMULLD
    8'h41: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHMINPOSUW
    8'h42: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h43: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h44: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h45: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSRLVD/VPSRLVQ
    8'h46: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSRAVD
    8'h47: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSLLVD/VPSLLVQ
    8'h48: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h49: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h50: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPDPBUSD
    8'h51: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPDPBUSDS
    8'h52: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPDPWSSD
    8'h53: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPDPWSSDS
    8'h54: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h55: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h56: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h57: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h58: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPBROADCASTD
    8'h59: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPBROADCASTQ
    8'h5A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VBROADCASTI128
    8'h5B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h60: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h61: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h62: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h63: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h64: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h65: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h66: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h67: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h68: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h69: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h70: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h71: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h72: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h73: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h74: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h75: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h76: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h77: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h78: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPBROADCASTB
    8'h79: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPBROADCASTW
    8'h7A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h80: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h81: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h82: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h83: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h84: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h85: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h86: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h87: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h88: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h89: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMASKMOVD/VPMASKMOVQ
    8'h8D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPMASKMOVD/VPMASKMOVQ
    8'h8F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h90: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPGATHERDQ/VPGATHERDD
    8'h91: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPGATHERQQ/VPGATHERQD
    8'h92: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VGATHERDPD/VGATHERDPS
    8'h93: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VGATHERQPD/VGATHERQPS
    8'h94: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h95: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h96: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMADDSUB132PD/VFMADDSUB132PS
    8'h97: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMSUBADD132PD/VFMSUBADD132PS
    8'h98: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMADD132PD/VFMADD132PS
    8'h99: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMADD132SD/VFMADD132SS
    8'h9A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMSUB132PD/VFMSUB132PS
    8'h9B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMSUB132SD/VFMSUB132SS
    8'h9C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFNMADD132PD/VFNMADD132PS
    8'h9D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFNMADD132SD/VFNMADD132SS
    8'h9E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFNMSUB132PD/VFNMSUB132PS
    8'h9F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFNMSUB132SD/VFNMSUB132SS
    8'hA0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMADDSUB213PD/VFMADDSUB213PS
    8'hA7: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMSUBADD213PD/VFMSUBADD213PS
    8'hA8: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMADD213PD/VFMADD213PS
    8'hA9: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMADD213SD/VFMADD213SS
    8'hAA: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMSUB213PD/VFMSUB213PS
    8'hAB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMSUB213SD/VFMSUB213SS
    8'hAC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFNMADD213PD/VFNMADD213PS
    8'hAD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFNMADD213SD/VFNMADD213SS
    8'hAE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFNMSUB213PD/VFNMSUB213PS
    8'hAF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFNMSUB213SD/VFNMSUB213SS
    8'hB0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMADDSUB231PD/VFMADDSUB231PS
    8'hB7: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMSUBADD231PD/VFMSUBADD231PS
    8'hB8: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMADD231PD/VFMADD231PS
    8'hB9: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMADD231SD/VFMADD231SS
    8'hBA: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMSUB231PD/VFMSUB231PS
    8'hBB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFMSUB231SD/VFMSUB231SS
    8'hBC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFNMADD231PD/VFNMADD231PS
    8'hBD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFNMADD231SD/VFNMADD231SS
    8'hBE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFNMSUB231PD/VFNMSUB231PS
    8'hBF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFNMSUB231SD/VFNMSUB231SS
    8'hC0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VGF2P8MULB
    8'hD0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hDA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hDB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VAESIMC
    8'hDC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VAESENC
    8'hDD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VAESENCLAST
    8'hDE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VAESDEC
    8'hDF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VAESDECLAST
    8'hE0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hED: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // ANDN
    8'hF3: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_17},         // BLSR/BLSMSK/BLSI
    8'hF4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF5: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // PDEP/PEXT/BZHI
    8'hF6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // MULX
    8'hF7: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // BEXTR/SHLX/SARX/SHRX
    8'hF8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE}        // (undefined)
  };

  // VEX map 3 (VEX.mmmmm = 3): VEX 0F 3A
  //             valid inv64 modrm group imm          grp
  localparam opc_attr_t OPC_VEX_0F3A [256] = '{
    8'h00: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPERMQ Ib
    8'h01: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPERMPD Ib
    8'h02: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPBLENDD Ib
    8'h03: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h04: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPERMILPS Ib
    8'h05: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPERMILPD Ib
    8'h06: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPERM2F128 Ib
    8'h07: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h08: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VROUNDPS Ib
    8'h09: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VROUNDPD Ib
    8'h0A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VROUNDSS Ib
    8'h0B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VROUNDSD Ib
    8'h0C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VBLENDPS Ib
    8'h0D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VBLENDPD Ib
    8'h0E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPBLENDW Ib
    8'h0F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPALIGNR Ib
    8'h10: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h11: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h12: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h13: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h14: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPEXTRB Ib
    8'h15: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPEXTRW Ib
    8'h16: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPEXTRQ/VPEXTRD Ib
    8'h17: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VEXTRACTPS Ib
    8'h18: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VINSERTF128 Ib
    8'h19: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VEXTRACTF128 Ib
    8'h1A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VCVTPS2PH Ib
    8'h1E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h20: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPINSRB Ib
    8'h21: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VINSERTPS Ib
    8'h22: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPINSRD/VPINSRQ Ib
    8'h23: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h24: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h25: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h26: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h27: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h28: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h29: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h30: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h31: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h32: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h33: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h34: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h35: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h36: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h37: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h38: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VINSERTI128 Ib
    8'h39: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VEXTRACTI128 Ib
    8'h3A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h40: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VDPPS Ib
    8'h41: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VDPPD Ib
    8'h42: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VMPSADBW Ib
    8'h43: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h44: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCLMULQDQ Ib
    8'h45: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h46: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPERM2I128 Ib
    8'h47: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h48: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPERMIL2PS Ib
    8'h49: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPERMIL2PD Ib
    8'h4A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VBLENDVPS Ib
    8'h4B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VBLENDVPD Ib
    8'h4C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPBLENDVB Ib
    8'h4D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h50: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h51: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h52: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h53: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h54: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h55: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h56: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h57: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h58: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h59: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFMADDSUBPS Ib
    8'h5D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFMADDSUBPD Ib
    8'h5E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFMSUBADDPS Ib
    8'h5F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFMSUBADDPD Ib
    8'h60: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCMPESTRM/VPCMPESTRM64 Ib
    8'h61: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCMPESTRI/VPCMPESTRI64 Ib
    8'h62: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCMPISTRM Ib
    8'h63: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCMPISTRI/VPCMPISTRI64 Ib
    8'h64: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h65: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h66: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h67: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h68: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFMADDPS Ib
    8'h69: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFMADDPD Ib
    8'h6A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFMADDSS Ib
    8'h6B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFMADDSD Ib
    8'h6C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFMSUBPS Ib
    8'h6D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFMSUBPD Ib
    8'h6E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFMSUBSS Ib
    8'h6F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFMSUBSD Ib
    8'h70: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h71: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h72: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h73: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h74: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h75: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h76: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h77: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h78: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFNMADDPS Ib
    8'h79: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFNMADDPD Ib
    8'h7A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFNMADDSS Ib
    8'h7B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFNMADDSD Ib
    8'h7C: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFNMSUBPS Ib
    8'h7D: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFNMSUBPD Ib
    8'h7E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFNMSUBSS Ib
    8'h7F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VFNMSUBSD Ib
    8'h80: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h81: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h82: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h83: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h84: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h85: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h86: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h87: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h88: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h89: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h90: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h91: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h92: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h93: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h94: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h95: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h96: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h97: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h98: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h99: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hCA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hCB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hCC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hCD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hCE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VGF2P8AFFINEQB Ib
    8'hCF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VGF2P8AFFINEINVQB Ib
    8'hD0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VAESKEYGENASSIST Ib
    8'hE0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hED: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF0: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // RORX Ib
    8'hF1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE}        // (undefined)
  };

  // XOP map 8 (XOP.mmmmm = 8)
  //             valid inv64 modrm group imm          grp
  localparam opc_attr_t OPC_XOP_8 [256] = '{
    8'h00: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h01: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h02: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h03: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h04: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h05: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h06: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h07: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h08: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h09: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h0A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h0B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h0C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h0D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h0E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h0F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h10: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h11: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h12: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h13: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h14: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h15: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h16: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h17: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h18: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h19: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h1F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h20: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h21: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h22: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h23: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h24: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h25: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h26: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h27: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h28: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h29: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h2F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h30: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h31: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h32: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h33: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h34: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h35: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h36: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h37: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h38: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h39: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h3F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h40: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h41: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h42: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h43: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h44: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h45: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h46: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h47: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h48: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h49: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h4F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h50: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h51: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h52: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h53: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h54: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h55: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h56: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h57: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h58: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h59: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h5F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h60: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h61: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h62: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h63: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h64: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h65: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h66: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h67: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h68: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h69: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h6A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h6B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h6C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h6D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h6E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h6F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h70: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h71: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h72: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h73: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h74: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h75: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h76: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h77: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h78: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h79: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h7A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h7B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h7C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h7D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h7E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h7F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h80: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h81: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h82: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h83: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h84: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h85: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPMACSSWW Ib
    8'h86: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPMACSSWD Ib
    8'h87: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPMACSSDQL Ib
    8'h88: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h89: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h8E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPMACSSDD Ib
    8'h8F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPMACSSDQH Ib
    8'h90: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h91: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h92: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h93: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h94: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h95: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPMACSWW Ib
    8'h96: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPMACSWD Ib
    8'h97: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPMACSDQL Ib
    8'h98: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h99: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'h9E: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPMACSDD Ib
    8'h9F: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPMACSDQH Ib
    8'hA0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCMOV Ib
    8'hA3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPPERM Ib
    8'hA4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPMADCSSWD Ib
    8'hA7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hA9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hAF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPMADCSWD Ib
    8'hB7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hB9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hBF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC0: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPROTB Ib
    8'hC1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPROTW Ib
    8'hC2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPROTD Ib
    8'hC3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPROTQ Ib
    8'hC4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hC9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hCA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hCB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hCC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCOMB Ib
    8'hCD: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCOMW Ib
    8'hCE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCOMD Ib
    8'hCF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCOMQ Ib
    8'hD0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hD9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hDF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hE9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hEC: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCOMUB Ib
    8'hED: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCOMUW Ib
    8'hEE: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCOMUD Ib
    8'hEF: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // VPCOMUQ Ib
    8'hF0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hF9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE},       // (undefined)
    8'hFF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_8,       GRP_NONE}        // (undefined)
  };

  // XOP map 9 (XOP.mmmmm = 9)
  //             valid inv64 modrm group imm          grp
  localparam opc_attr_t OPC_XOP_9 [256] = '{
    8'h00: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h01: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_X9_01},      // BLCFILL/BLSFILL/BLCS/TZMSK/BLCIC ...
    8'h02: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_X9_02},      // BLCMSK/BLCI
    8'h03: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h04: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h05: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h06: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h07: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h08: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h09: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h0F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h10: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h11: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h12: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_NONE,    GRP_X9_12},      // LLWPCB/SLWPCB
    8'h13: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h14: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h15: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h16: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h17: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h18: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h19: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h1F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h20: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h21: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h22: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h23: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h24: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h25: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h26: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h27: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h28: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h29: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h2A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h2B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h2C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h2D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h2E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h2F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h30: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h31: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h32: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h33: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h34: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h35: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h36: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h37: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h38: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h39: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h3F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h40: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h41: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h42: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h43: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h44: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h45: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h46: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h47: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h48: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h49: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h4F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h50: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h51: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h52: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h53: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h54: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h55: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h56: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h57: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h58: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h59: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h5F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h60: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h61: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h62: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h63: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h64: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h65: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h66: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h67: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h68: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h69: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h6F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h70: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h71: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h72: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h73: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h74: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h75: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h76: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h77: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h78: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h79: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h7F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h80: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFRCZPS
    8'h81: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFRCZPD
    8'h82: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFRCZSS
    8'h83: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VFRCZSD
    8'h84: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h85: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h86: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h87: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h88: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h89: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h8F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h90: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPROTB
    8'h91: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPROTW
    8'h92: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPROTD
    8'h93: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPROTQ
    8'h94: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSHLB
    8'h95: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSHLW
    8'h96: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSHLD
    8'h97: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSHLQ
    8'h98: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSHAB
    8'h99: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSHAW
    8'h9A: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSHAD
    8'h9B: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPSHAQ
    8'h9C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'h9F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hA9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hAF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hB9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hBF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDBW
    8'hC2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDBD
    8'hC3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDBQ
    8'hC4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDWD
    8'hC7: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDWQ
    8'hC8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hC9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDDQ
    8'hCC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hCF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDUBW
    8'hD2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDUBD
    8'hD3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDUBQ
    8'hD4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD6: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDUWD
    8'hD7: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDUWQ
    8'hD8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hD9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hDA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hDB: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHADDUDQ
    8'hDC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hDD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hDE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hDF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE1: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHSUBBW
    8'hE2: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHSUBWD
    8'hE3: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // VPHSUBDQ
    8'hE4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hE9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hED: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hEF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hF9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE},       // (undefined)
    8'hFF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_NONE,    GRP_NONE}        // (undefined)
  };

  // XOP map A (XOP.mmmmm = 10)
  //             valid inv64 modrm group imm          grp
  localparam opc_attr_t OPC_XOP_A [256] = '{
    8'h00: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h01: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h02: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h03: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h04: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h05: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h06: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h07: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h08: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h09: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h0A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h0B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h0C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h0D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h0E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h0F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h10: '{1'b1, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // BEXTR Id
    8'h11: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h12: '{1'b1, 1'b0, 1'b1, 1'b1, IMM_32,      GRP_XA_12},      // LWPINS/LWPVAL Id
    8'h13: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h14: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h15: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h16: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h17: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h18: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h19: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h1A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h1B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h1C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h1D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h1E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h1F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h20: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h21: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h22: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h23: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h24: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h25: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h26: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h27: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h28: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h29: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h2A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h2B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h2C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h2D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h2E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h2F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h30: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h31: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h32: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h33: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h34: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h35: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h36: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h37: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h38: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h39: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h3A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h3B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h3C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h3D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h3E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h3F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h40: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h41: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h42: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h43: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h44: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h45: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h46: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h47: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h48: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h49: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h4A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h4B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h4C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h4D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h4E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h4F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h50: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h51: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h52: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h53: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h54: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h55: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h56: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h57: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h58: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h59: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h5A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h5B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h5C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h5D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h5E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h5F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h60: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h61: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h62: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h63: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h64: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h65: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h66: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h67: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h68: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h69: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h6A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h6B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h6C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h6D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h6E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h6F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h70: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h71: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h72: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h73: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h74: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h75: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h76: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h77: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h78: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h79: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h7A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h7B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h7C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h7D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h7E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h7F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h80: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h81: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h82: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h83: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h84: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h85: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h86: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h87: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h88: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h89: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h8A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h8B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h8C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h8D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h8E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h8F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h90: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h91: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h92: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h93: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h94: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h95: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h96: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h97: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h98: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h99: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h9A: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h9B: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h9C: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h9D: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h9E: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'h9F: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hA0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hA1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hA2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hA3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hA4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hA5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hA6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hA7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hA8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hA9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hAA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hAB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hAC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hAD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hAE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hAF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hB0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hB1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hB2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hB3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hB4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hB5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hB6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hB7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hB8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hB9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hBA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hBB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hBC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hBD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hBE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hBF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hC0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hC1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hC2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hC3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hC4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hC5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hC6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hC7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hC8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hC9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hCA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hCB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hCC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hCD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hCE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hCF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hD0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hD1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hD2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hD3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hD4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hD5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hD6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hD7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hD8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hD9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hDA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hDB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hDC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hDD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hDE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hDF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hE0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hE1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hE2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hE3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hE4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hE5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hE6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hE7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hE8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hE9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hEA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hEB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hEC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hED: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hEE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hEF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hF0: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hF1: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hF2: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hF3: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hF4: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hF5: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hF6: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hF7: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hF8: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hF9: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hFA: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hFB: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hFC: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hFD: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hFE: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE},       // (undefined)
    8'hFF: '{1'b0, 1'b0, 1'b1, 1'b0, IMM_32,      GRP_NONE}        // (undefined)
  };

  // Secondary group table: GRP_ATTR[grp][ModR/M.reg]
  //   valid_mem : defined when ModR/M.mod != 3
  //   valid_reg : defined when ModR/M.mod == 3
  //   rm_ext    : when mod == 3, ModR/M.rm selects the instruction
  //   imm       : this reg value takes the immediate. Only meaningful for
  //               GRP_3 (F6/F7, kinds IMM_GRP3_8 / IMM_GRP3_Z). For every other
  //               group the immediate comes from the main table entry.
  //               valid_mem valid_reg rm_ext imm
  localparam grp_attr_t GRP_ATTR [GRP_NUM][8] = '{
    // GRP_NONE
    '{default: '0},
    // GRP_1
    '{
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /0 ADD
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 OR
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /2 ADC
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /3 SBB
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /4 AND
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /5 SUB
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /6 XOR
      '{1'b1, 1'b1, 1'b0, 1'b0}    // /7 CMP
    },
    // GRP_1A
    '{
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /0 POP Ev
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /1 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /2 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /3 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /4 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /5 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /6 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0}    // /7 (undefined)
    },
    // GRP_2
    '{
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /0 ROL
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 ROR
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /2 RCL
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /3 RCR
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /4 SHL
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /5 SHR
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /6 SHL (SAL alias)
      '{1'b1, 1'b1, 1'b0, 1'b0}    // /7 SAR
    },
    // GRP_3
    '{
      '{1'b1, 1'b1, 1'b0, 1'b1},   // /0 TEST E,I
      '{1'b1, 1'b1, 1'b0, 1'b1},   // /1 TEST E,I (alias)
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /2 NOT
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /3 NEG
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /4 MUL
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /5 IMUL
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /6 DIV
      '{1'b1, 1'b1, 1'b0, 1'b0}    // /7 IDIV
    },
    // GRP_4
    '{
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /0 INC Eb
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 DEC Eb
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /2 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /3 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /4 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /5 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /6 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0}    // /7 (undefined)
    },
    // GRP_5
    '{
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /0 INC Ev
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 DEC Ev
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /2 CALL near Ev
      '{1'b1, 1'b0, 1'b0, 1'b0},   // /3 CALL far Mp
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /4 JMP near Ev
      '{1'b1, 1'b0, 1'b0, 1'b0},   // /5 JMP far Mp
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /6 PUSH Ev
      '{1'b0, 1'b0, 1'b0, 1'b0}    // /7 (undefined)
    },
    // GRP_6
    '{
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /0 SLDT
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 STR
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /2 LLDT
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /3 LTR
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /4 VERR
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /5 VERW
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /6 (undefined; LKGS on Intel FRED)
      '{1'b0, 1'b0, 1'b0, 1'b0}    // /7 (undefined)
    },
    // GRP_7
    '{
      '{1'b1, 1'b0, 1'b0, 1'b0},   // /0 SGDT (reg forms: Intel VMX/SGX only)
      '{1'b1, 1'b1, 1'b1, 1'b0},   // /1 SIDT; reg: MONITOR, MWAIT, CLAC, STAC
      '{1'b1, 1'b1, 1'b1, 1'b0},   // /2 LGDT; reg: XGETBV, XSETBV
      '{1'b1, 1'b1, 1'b1, 1'b0},   // /3 LIDT; reg: SVM VMRUN, VMMCALL, VMLOAD, VMSAVE, STGI, CLGI, SKINIT, INVLPGA
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /4 SMSW
      '{1'b1, 1'b1, 1'b1, 1'b0},   // /5 RSTORSSP (F3); reg: SETSSBSY, SAVEPREVSSP, RDPKRU, WRPKRU
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /6 LMSW
      '{1'b1, 1'b1, 1'b1, 1'b0}    // /7 INVLPG; reg: SWAPGS, RDTSCP, MONITORX, MWAITX, CLZERO, RDPRU, INVLPGB, TLBSYNC
    },
    // GRP_8
    '{
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /0 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /1 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /2 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /3 (undefined)
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /4 BT Ev,Ib
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /5 BTS Ev,Ib
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /6 BTR Ev,Ib
      '{1'b1, 1'b1, 1'b0, 1'b0}    // /7 BTC Ev,Ib
    },
    // GRP_9
    '{
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /0 (undefined)
      '{1'b1, 1'b0, 1'b0, 1'b0},   // /1 CMPXCHG8B / CMPXCHG16B (REX.W)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /2 (undefined)
      '{1'b1, 1'b0, 1'b0, 1'b0},   // /3 XRSTORS
      '{1'b1, 1'b0, 1'b0, 1'b0},   // /4 XSAVEC
      '{1'b1, 1'b0, 1'b0, 1'b0},   // /5 XSAVES
      '{1'b0, 1'b1, 1'b0, 1'b0},   // /6 RDRAND (mem forms: Intel VMX only)
      '{1'b0, 1'b1, 1'b0, 1'b0}    // /7 RDSEED / RDPID (F3) (mem form: Intel VMX only)
    },
    // GRP_10
    '{
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /0 UD1
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 UD1
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /2 UD1
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /3 UD1
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /4 UD1
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /5 UD1
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /6 UD1
      '{1'b1, 1'b1, 1'b0, 1'b0}    // /7 UD1
    },
    // GRP_11
    '{
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /0 MOV E,I
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /1 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /2 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /3 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /4 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /5 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /6 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0}    // /7 (undefined; XABORT/XBEGIN on Intel TSX)
    },
    // GRP_12
    '{
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /0 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /1 (undefined)
      '{1'b0, 1'b1, 1'b0, 1'b0},   // /2 PSRLW
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /3 (undefined)
      '{1'b0, 1'b1, 1'b0, 1'b0},   // /4 PSRAW
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /5 (undefined)
      '{1'b0, 1'b1, 1'b0, 1'b0},   // /6 PSLLW
      '{1'b0, 1'b0, 1'b0, 1'b0}    // /7 (undefined)
    },
    // GRP_13
    '{
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /0 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /1 (undefined)
      '{1'b0, 1'b1, 1'b0, 1'b0},   // /2 PSRLD
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /3 (undefined)
      '{1'b0, 1'b1, 1'b0, 1'b0},   // /4 PSRAD
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /5 (undefined)
      '{1'b0, 1'b1, 1'b0, 1'b0},   // /6 PSLLD
      '{1'b0, 1'b0, 1'b0, 1'b0}    // /7 (undefined)
    },
    // GRP_14
    '{
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /0 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /1 (undefined)
      '{1'b0, 1'b1, 1'b0, 1'b0},   // /2 PSRLQ
      '{1'b0, 1'b1, 1'b0, 1'b0},   // /3 PSRLDQ (66 only)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /4 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /5 (undefined)
      '{1'b0, 1'b1, 1'b0, 1'b0},   // /6 PSLLQ
      '{1'b0, 1'b1, 1'b0, 1'b0}    // /7 PSLLDQ (66 only)
    },
    // GRP_15
    '{
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /0 FXSAVE; reg: RDFSBASE (F3)
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 FXRSTOR; reg: RDGSBASE (F3)
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /2 LDMXCSR; reg: WRFSBASE (F3)
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /3 STMXCSR; reg: WRGSBASE (F3)
      '{1'b1, 1'b0, 1'b0, 1'b0},   // /4 XSAVE (reg: PTWRITE, Intel only)
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /5 XRSTOR; reg: LFENCE, INCSSP (F3)
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /6 XSAVEOPT, CLWB (66), CLRSSBSY (F3); reg: MFENCE
      '{1'b1, 1'b1, 1'b0, 1'b0}    // /7 CLFLUSH, CLFLUSHOPT (66); reg: SFENCE
    },
    // GRP_16
    '{
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /0 PREFETCHNTA; reg: NOP
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 PREFETCHT0; reg: NOP
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /2 PREFETCHT1; reg: NOP
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /3 PREFETCHT2; reg: NOP
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /4 reserved NOP
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /5 reserved NOP
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /6 reserved NOP
      '{1'b1, 1'b1, 1'b0, 1'b0}    // /7 reserved NOP
    },
    // GRP_P
    '{
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /0 PREFETCH; reg: NOP
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 PREFETCHW; reg: NOP
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /2 PREFETCH (reserved alias); reg: NOP
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /3 PREFETCHW (alias); reg: NOP
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /4 PREFETCH (reserved alias); reg: NOP
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /5 PREFETCH (reserved alias); reg: NOP
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /6 PREFETCH (reserved alias); reg: NOP
      '{1'b1, 1'b1, 1'b0, 1'b0}    // /7 PREFETCH (reserved alias); reg: NOP
    },
    // GRP_17
    '{
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /0 (undefined)
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 BLSR
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /2 BLSMSK
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /3 BLSI
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /4 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /5 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /6 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0}    // /7 (undefined)
    },
    // GRP_15V
    '{
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /0 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /1 (undefined)
      '{1'b1, 1'b0, 1'b0, 1'b0},   // /2 VLDMXCSR
      '{1'b1, 1'b0, 1'b0, 1'b0},   // /3 VSTMXCSR
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /4 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /5 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /6 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0}    // /7 (undefined)
    },
    // GRP_X9_01
    '{
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /0 (undefined)
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 BLCFILL
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /2 BLSFILL
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /3 BLCS
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /4 TZMSK
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /5 BLCIC
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /6 BLSIC
      '{1'b1, 1'b1, 1'b0, 1'b0}    // /7 T1MSKC
    },
    // GRP_X9_02
    '{
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /0 (undefined)
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 BLCMSK
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /2 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /3 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /4 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /5 (undefined)
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /6 BLCI
      '{1'b0, 1'b0, 1'b0, 1'b0}    // /7 (undefined)
    },
    // GRP_X9_12
    '{
      '{1'b0, 1'b1, 1'b0, 1'b0},   // /0 LLWPCB
      '{1'b0, 1'b1, 1'b0, 1'b0},   // /1 SLWPCB
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /2 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /3 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /4 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /5 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /6 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0}    // /7 (undefined)
    },
    // GRP_XA_12
    '{
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /0 LWPINS
      '{1'b1, 1'b1, 1'b0, 1'b0},   // /1 LWPVAL
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /2 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /3 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /4 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /5 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0},   // /6 (undefined)
      '{1'b0, 1'b0, 1'b0, 1'b0}    // /7 (undefined)
    }
  };

endpackage