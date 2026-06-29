// top-level testbench
`timescale 1ns / 1ps

module tb_top;

  // --------------------------------------------------------------------
  // clock / reset
  // --------------------------------------------------------------------
  localparam time CLK_PERIOD = 10ns;

  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // --------------------------------------------------------------------
  // retire bus
  // widths are placeholders until pkg/cpu_pkg.sv defines the real uop/ROB
  // types -- update these and the DUT hookup below together.
  // --------------------------------------------------------------------
  localparam int RETIRE_WIDTH  = 2;   // retire ports (superscalar width)
  localparam int PC_WIDTH      = 64;
  localparam int ROB_IDX_WIDTH = 8;

  logic [RETIRE_WIDTH-1:0]                    retire_valid;
  logic [RETIRE_WIDTH-1:0][PC_WIDTH-1:0]      retire_pc;
  logic [RETIRE_WIDTH-1:0][ROB_IDX_WIDTH-1:0] retire_rob_idx;
  logic [RETIRE_WIDTH-1:0]                    retire_exception;
  logic [RETIRE_WIDTH-1:0]                    retire_mispredict;

  // --------------------------------------------------------------------
  // DUT
  // TODO: instantiate once cpu_top's port list exists; connect clk/rst_n
  // and the retire bus signals above to the matching DUT ports.
  // --------------------------------------------------------------------
  // cpu_top dut (
  //   .clk                (clk),
  //   .rst_n              (rst_n),
  //   .retire_valid       (retire_valid),
  //   .retire_pc          (retire_pc),
  //   .retire_rob_idx     (retire_rob_idx),
  //   .retire_exception   (retire_exception),
  //   .retire_mispredict  (retire_mispredict)
  // );

  // --------------------------------------------------------------------
  // retire bus monitor
  // --------------------------------------------------------------------
  longint unsigned retire_count;

  initial retire_count = 0;

  always @(posedge clk) begin
    if (rst_n) begin
      for (int i = 0; i < RETIRE_WIDTH; i++) begin
        if (retire_valid[i]) begin
          retire_count++;
          // TODO: hook scoreboard / reference-model comparison here
          $display("[%0t] retire: port=%0d pc=%0h rob_idx=%0d exc=%0b mispred=%0b",
                    $time, i, retire_pc[i], retire_rob_idx[i],
                    retire_exception[i], retire_mispredict[i]);
        end
      end
    end
  end

  // --------------------------------------------------------------------
  // test sequencing
  // --------------------------------------------------------------------
  initial begin
    // TODO: load program image / drive stimulus, then wait for completion
    @(posedge rst_n);
    #1000;
    $display("retired %0d instructions", retire_count);
    $finish;
  end

endmodule
