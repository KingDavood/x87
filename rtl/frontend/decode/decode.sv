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

// ### `x87_imm_extract`
// - **Role:** pull the immediate and size it.
// - **In:** bytes (post-disp), `imm_kind`, `operand_size`. **Out:** `imm` (extended), `imm_len`.
// - **Comb.** **Traps:** `iz` size flips with `66`/`REX.W`; `io` (imm64) only for `MOV r64, imm64`.