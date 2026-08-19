// opcode -> uop type, src/dst count
module opcode_rom#(
  parameter FETCH_WIDTH=4,
  parameter ROM_SIZE=64,
  parameter MAX_UOPS=4
)(
    input logic clk,
    input logic rst_n,
    input mode_t mode,
    input uop_metadata_t uops,
    output logic [FETCH_WIDTH-1:0]  instr_len,
    output uop_t [3:0] uop_out);


endmodule
