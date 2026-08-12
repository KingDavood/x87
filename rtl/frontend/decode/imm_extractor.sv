// pulls immediates out of instruction stream
module imm_extractor #(
  parameter FETCH_WIDTH=4,
  parameter ROM_SIZE=64,
  parameter MAX_UOPS=4,
  parameter MAX_IMM_WIDTH=64
)(input logic clk, 
  input logic rst_n,
  input logic [FETCH_W*8-1:0] bytes,
  input imm_kind_t imm_kind,
  output logic [MAX_IMM_WIDTH-1:0] imm_bytes,
)


  // always_comb begin
  //   case(imm_kind)
  //     blank:  begin
  //       imm_bytes[0:7] = bytes[8:15];
  //       end
  //     blank2:
  //     blank3:
  //   endcase
  // end


endmodulde

// ### `x87_imm_extract`
// - **Role:** pull the immediate and size it.
// - **In:** bytes (post-disp), `imm_kind`, `operand_size`. **Out:** `imm` (extended), `imm_len`.
// - **Comb.** **Traps:** `iz` size flips with `66`/`REX.W`; `io` (imm64) only for `MOV r64, imm64`.