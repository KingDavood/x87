package predecode_pkg;

  // Which opcode table applies. Set on the opcode byte only, TBL_NONE elsewhere.
  typedef enum logic [2:0] {
    TBL_1BYTE = 3'd0,
    TBL_0F    = 3'd1,
    TBL_0F38  = 3'd2,
    TBL_0F3A  = 3'd3,
    TBL_VEX   = 3'd4   // VEX/XOP, real table chosen by map_select
  } opc_table_e;

  // 4 bits stored per I-cache byte.
  typedef struct packed {
    logic       start;      // an instruction begins on this byte
    opc_table_e opc_table;  // nonzero on the opcode byte
  } marker_t;

endpackage : predecode_pkg


package x86_decode_pkg;

  import predecode_pkg::*;

  typedef enum logic [0:0] {
    MODE_32 = 1'b0,
    MODE_64 = 1'b1
  } cpu_mode_e;

  // Immediate size class, one field of the opcode table result.
// Immediate kind, one field of the opcode table result (sizes in bytes).
  typedef enum logic [3:0] {
    IMM_NONE   = 4'd0,   // 0
    IMM_8      = 4'd1,   // 1
    IMM_16     = 4'd2,   // 2
    IMM_16_8   = 4'd3,   // 3, ENTER: Iw then Ib
    IMM_Z      = 4'd4,   // 2 if operand size 16, else 4 (REX.W still 4)
    IMM_JZ     = 4'd5,   // near branch rel16/32 (64-bit: 4, AMD honors 66 and uses 2)
    IMM_V      = 4'd6,   // 2 / 4 / 8 by operand size (8 only with REX.W)
    IMM_MOFFS  = 4'd7,   // address-size bytes (64-bit 8, with 67 4)
    IMM_PTR    = 4'd8,   // far pointer, operand size + 2 (legacy only)
    IMM_GRP3_8 = 4'd9,   // 1 if ModR/M.reg is 0 or 1 (TEST), else 0
    IMM_GRP3_Z = 4'd10,  // IMM_Z if ModR/M.reg is 0 or 1 (TEST), else 0
    IMM_32     = 4'd11   // 4 always (XOP map A)
  } imm_kind_e;


  // Tail fields after the opcode, in encoding order.
  typedef enum logic [1:0] {
    FLD_MODRM = 2'd0,
    FLD_SIB   = 2'd1,
    FLD_DISP  = 2'd2,
    FLD_IMM   = 2'd3
  } tail_field_e;

  // VEX/XOP map_select field. C5 (2-byte VEX) has no map field, so the
  // extractor forces MAP_VEX_01. Any other value is illegal (#UD).
  typedef enum logic [4:0] {
    MAP_VEX_01 = 5'h01,
    MAP_VEX_02 = 5'h02,
    MAP_VEX_03 = 5'h03,
    MAP_XOP_08 = 5'h08,
    MAP_XOP_09 = 5'h09,
    MAP_XOP_0A = 5'h0A
  } map_select_e;

  function automatic logic map_select_valid(logic [4:0] raw);
    return (raw inside {MAP_VEX_01, MAP_VEX_02, MAP_VEX_03,
                        MAP_XOP_08, MAP_XOP_09, MAP_XOP_0A});
  endfunction

endpackage : x86_decode_pkg