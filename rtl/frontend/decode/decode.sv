// top of decode, produces uop bundles
module decode #(
  parameter FETCH_WIDTH=4,
  parameter ROM_SIZE=64,
  parameter MAX_UOPS=4
)
(
    input logic                     clk, rst_n,
    input logic [FETCH_W*8-1:0]     bytes,
    input prefix_state_t            prefix,  // need to find this aswell
    input mode_e                    mode,   
    output uop_metadata_t [MAX_UOPS-1:0]     uops,    // Need to define this in pkts
    output logic [MAX_UOPS-1:0]     uop_valid,
    output logic [FETCH_WIDTH-1:0]  instr_len // TODO: Parameter sizing
);

endmodule


module prefix_decode #(
  parameter FETCH_WIDTH=4  
)
(
  input logic                     clk, rst_n,
  input mode_e                    mode,
  output logic [FETCH_WIDTH-1:0]  pfx_len, // TODO: Parameter sizing
  output prefix_state_t           prefix
);


endmodule

module length_decode
#( parameter MAX_BYTE_WIDTH = 32,
   parameter MAX_OPCODE_LENGTH = 3)
(
  input  logic clk,
  input  logic rst_n,
  input  mode_t mode,
  input  logic [MAX_BYTE_WIDTH*8-1:0]bytes, // TODO: Fix sizing eventually
  output logic op_code,
  output logic op_code_len,
  output logic pfx_len
  output logic interrupt,
);

  localparam OPCODE_LENGTH = 8 * MAX_OPCODE_LENGTH;
  logic [5:0] byte_pos;
  logic not_done;
  logic [OPCODE_LENGTH-1:0] op_code;

  // https://wiki.osdev.org/X86-64_Instruction_Encoding
  function automatic logic is_legacy_prefix(logic [7:0] byte);
    case (byte)
      PFX_LOCK, PFX_REPNE, PFX_REP, PFX_OPSIZE, PFX_ADDRSIZE,
      PFX_SEG_ES, PFX_SEG_CS, PFX_SEG_SS, PFX_SEG_DS, PFX_SEG_FS, PFX_SEG_GS: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  // find amd thingy
  function automatic logic is_prefix(logic [7:0] byte);
  // need some more inputs
    always_comb begin
      if(mode == REAL)begin
        
      end else if(mode == PROTECTED) begin
        
      end else if(mode == BIT_64)begin
        
      end else if(mode == VIRTUAL8086) begin
        
      end else if(mode == COMPATIBILITY) begin
        
      end
      
    end
  endfunction

  always_comb begin
    byte_pos = 0;
    not_done = 1;

    for(int i = 0; i < MAX_BYTE_WIDTH; i++) begin
      if(not_done && 
      (is_prefix(bytes[i]) || is_legacy_prefix(bytes[(i+1)*8:i*8]))) begin
        bytes_pos += 1;
      end
      else begin
        not_done = 0;
      end
    end
  end

endmodule
// ### `x87_imm_extract`
// - **Role:** pull the immediate and size it.
// - **In:** bytes (post-disp), `imm_kind`, `operand_size`. **Out:** `imm` (extended), `imm_len`.
// - **Comb.** **Traps:** `iz` size flips with `66`/`REX.W`; `io` (imm64) only for `MOV r64, imm64`.