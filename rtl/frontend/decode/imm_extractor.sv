import isa_pkg::*;
 
typedef enum logic [2:0] {
  IMM_NONE,
  IMM_IB,   // 8-bit
  IMM_IW,   // 16-bit
  IMM_ID,   // 32-bit
  IMM_IZ,   // 16 or 32 -- TODO: flips with 66/REX.W (the LCP hazard)
  IMM_IO    // 64-bit -- (MOV r64, imm64 only)
} imm_kind_e;


// pulls immediates out of instruction stream
module imm_extractor #(
  parameter FETCH_WIDTH=4,
  parameter ROM_SIZE=64,
  parameter MAX_UOPS=4,
  parameter MAX_IMM_WIDTH=64
)(input logic clk, 
  input logic rst_n,
  input logic [FETCH_WIDTH*8-1:0] bytes,
  input imm_kind_t imm_kind,
  output logic [MAX_IMM_WIDTH-1:0] imm_bytes,
  output logic [FETCH_WIDTH-1:0]  imm_len
)


  always_comb begin
    imm = '0;
    imm_len = '0;

    case(imm_mind)
      IMM_NONE: begin
      end
      
      IMM_IB: begin
        imm = {{56{bytes[7]}}, bytes[7:0]};
        imm_len = 4'd1;
      end

      IMM_IW: begin
        imm = {{48{bytes[15]}}, bytes[15:0]};
        imm_len = 4'd2;
      end

      IMM_ID: begin
        // TODO
      end

      IMM_IZ: begin
        // TODO
      end

      IMM_IO: begin
        // TODO
      end

      default: begin
      end
    endcase
  end

endmodulde

// ### `x87_imm_extract`
// - **Role:** pull the immediate and size it.
// - **In:** bytes (post-disp), `imm_kind`, `operand_size`. **Out:** `imm` (extended), `imm_len`.
// - **Comb.** **Traps:** `iz` size flips with `66`/`REX.W`; `io` (imm64) only for `MOV r64, imm64`.