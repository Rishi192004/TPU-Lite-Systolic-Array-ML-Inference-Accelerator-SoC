// ============================================================================
// TPU-Lite Accelerator SoC - SystemVerilog UVM Scoreboard
// File: sim/tb/tpu_scoreboard.sv
// Description: Compares TPU output matrix beat-by-beat against golden reference.
// ============================================================================

`timescale 1ns / 1ps

`include "axi_defines.svh"

class tpu_scoreboard;
    int match_count;
    int mismatch_count;

    function new();
        this.match_count    = 0;
        this.mismatch_count = 0;
    endfunction

    task compare_matrix(
        input int vector_id,
        input logic signed [ACC_WIDTH-1:0] actual [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1],
        input logic signed [ACC_WIDTH-1:0] expected [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1]
    );
        bit error_found = 0;

        for (int r = 0; r < ARRAY_SIZE; r++) begin
            for (int c = 0; c < ARRAY_SIZE; c++) begin
                if (actual[r][c] !== expected[r][c]) begin
                    $error("[SCOREBOARD MISMATCH] Vector #%0d Element [%0d][%0d] | Expected: %0d (0x%0h) | Got: %0d (0x%0h)",
                        vector_id, r, c, expected[r][c], expected[r][c], actual[r][c], actual[r][c]);
                    error_found = 1;
                    mismatch_count++;
                end else begin
                    match_count++;
                end
            end
        end

        if (!error_found) begin
            $display("[SCOREBOARD PASS] Vector #%0d Matrix 8x8 successfully verified with ZERO mismatches.", vector_id);
        end
    endtask

    function void print_summary();
        $display("\n==================================================");
        $display("          TPU-LITE UVM SCOREBOARD SUMMARY         ");
        $display("==================================================");
        $display("  Total Matches Checked  : %0d", match_count);
        $display("  Total Mismatches Found : %0d", mismatch_count);
        if (mismatch_count == 0) begin
            $display("  FINAL STATUS           : PASSED");
        end else begin
            $display("  FINAL STATUS           : FAILED");
        end
        $display("==================================================\n");
    endfunction
endclass
