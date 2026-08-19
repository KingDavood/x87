// Unit testbench for length_decode (rtl/frontend/decode/decode.sv).
//
// Diffs the DUT's prefix-byte count against tb/gen_length_decode_vectors.py,
// an independent Python re-derivation of the same count from the SDM prefix
// bytes (no nasm/cocotb in this sandbox -- see that script's header).
//
// DUT CONTRACT this testbench binds against -- length_decode does not
// expose this today (no outputs at all, plus a few syntax bugs), so wire it
// up to match before running this:
//
//   module length_decode #(
//     parameter MAX_BYTE_WIDTH = 32,
//     parameter MAX_OPCODE_LENGTH = 3
//   ) (
//     input  logic clk, rst_n,
//     input  logic [MAX_BYTE_WIDTH*8-1:0] bytes,   // flat bus, byte0 = bytes[7:0]
//     output logic [5:0]                  pfx_len  // count of leading prefix bytes
//   );
//
// Run via scripts/test_length_decode.sh.

`timescale 1ns / 1ps

module tb_length_decode;

  localparam int BYTE_WIDTH = 32;  // must match length_decode's MAX_BYTE_WIDTH default
                                    // and tb/gen_length_decode_vectors.py's BYTE_WIDTH

  logic clk, rst_n;
  initial clk = 1'b0;
  always #5 clk = ~clk;
  initial begin
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
  end

  logic [BYTE_WIDTH*8-1:0] dut_bytes;
  logic [5:0]              dut_pfx_len;

  length_decode #(
    .MAX_BYTE_WIDTH(BYTE_WIDTH)
  ) dut (
    .clk     (clk),
    .rst_n   (rst_n),
    .bytes   (dut_bytes),
    .pfx_len (dut_pfx_len)
  );

  int    fd;
  int    scan_ok;
  int    num_vectors;
  int    expected;
  string name;
  string vec_path;
  logic [7:0] byte_val;
  int    pass_count, fail_count;

  initial begin
    pass_count = 0;
    fail_count = 0;

    if (!$value$plusargs("VECTORS=%s", vec_path))
      vec_path = "tb/tests/vectors/length_decode_vectors.txt";

    fd = $fopen(vec_path, "r");
    if (fd == 0) begin
      $display("ERROR: could not open vector file %s", vec_path);
      $fatal(1);
    end

    scan_ok = $fscanf(fd, "%d", num_vectors);

    @(posedge rst_n);

    for (int v = 0; v < num_vectors; v++) begin
      scan_ok = $fscanf(fd, "%s", name);
      scan_ok = $fscanf(fd, "%d", expected);

      dut_bytes = '0;
      for (int i = 0; i < BYTE_WIDTH; i++) begin
        scan_ok = $fscanf(fd, "%h", byte_val);
        dut_bytes[8*i +: 8] = byte_val;
      end

      #1;

      if (dut_pfx_len === expected[5:0]) begin
        $display("PASS  %-40s expected=%0d got=%0d", name, expected, dut_pfx_len);
        pass_count++;
      end else begin
        $display("FAIL  %-40s expected=%0d got=%0d", name, expected, dut_pfx_len);
        fail_count++;
      end
    end

    $fclose(fd);

    $display("---");
    $display("%0d/%0d passed", pass_count, num_vectors);
    if (fail_count > 0) $display("RESULT: FAIL");
    else $display("RESULT: PASS");

    $finish;
  end

endmodule
