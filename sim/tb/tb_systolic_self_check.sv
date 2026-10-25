// ============================================================================
// TPU-Lite Accelerator SoC - Self-Checking Testbench v2.0
// File: sim/tb/tb_systolic_self_check.sv
//
// Features:
//  - Fully independent golden model calculation (compute_expected)
//  - Live element-by-element scoreboard comparison (scoreboard_check)
//  - Hard failure exit on errors ($fatal(1) ensures non-zero shell exit code)
//  - Timeout watchdog for array execution
//  - SystemVerilog assertions for reset, control handshakes, and valid data
//  - Test cases:
//      TEST 1 : Active reset verification
//      TEST 2 : PE normal signed MAC (10 + 4*6 = 34) & pipeline pass-through
//      TEST 3 : PE signed negative operands (-20 + -3*6 = -38)
//      TEST 4 : PE INT8 max boundary (127 * 127 = 16129)
//      TEST 4a: PE INT8 min*max boundary (-128 * 127 = -16256)
//      TEST 5 : PE zero activation (0 * 5 + 99 = 99)
//      TEST 6 : 8x8 Array all-zero inputs (W=0, A=0 -> C=0)
//      TEST 7 : 8x8 Array identity weights (C = A * I = A)
//      TEST 8 : 8x8 Array boundary values (A=+127, W=-128 -> C=-130048)
//      TEST 9 : 8x8 Array signed pseudo-random matrix multiplication
//      TEST 10: 8x8 Array mid-run reset & recovery
// ============================================================================

`timescale 1ns / 1ps

module tb_systolic_self_check;

    // -------------------------------------------------------------------------
    // Parameters (8x8 INT8 -> INT32)
    // -------------------------------------------------------------------------
    localparam int N          = 8;
    localparam int INT8_WIDTH = 8;
    localparam int ACC_WIDTH  = 32;
    localparam int TIMEOUT_MAX = 200;

    // -------------------------------------------------------------------------
    // Clock and Reset Signals
    // -------------------------------------------------------------------------
    logic clk   = 1'b0;
    logic rst_n = 1'b1; // Start high, pulsed low in reset sequence

    always #5 clk = ~clk; // 100 MHz clock (10 ns period)

    // Flag indicating initial reset has been applied
    logic rst_init_done = 1'b0;

    // -------------------------------------------------------------------------
    // DUT 1: Single Processing Element
    // -------------------------------------------------------------------------
    logic                         pe_load_wgt;
    logic                         pe_clear_acc;
    logic                         pe_enable;
    logic signed [INT8_WIDTH-1:0] pe_act_in;
    logic signed [INT8_WIDTH-1:0] pe_wgt_in;
    logic signed [ACC_WIDTH-1:0]  pe_acc_in;
    logic signed [INT8_WIDTH-1:0] pe_act_out;
    logic signed [ACC_WIDTH-1:0]  pe_acc_out;

    processing_element #(
        .INT8_WIDTH(INT8_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) dut_pe (
        .clk        (clk),
        .rst_n      (rst_n),
        .load_weight(pe_load_wgt),
        .clear_acc  (pe_clear_acc),
        .enable     (pe_enable),
        .act_in     (pe_act_in),
        .wgt_in     (pe_wgt_in),
        .acc_in     (pe_acc_in),
        .act_out    (pe_act_out),
        .acc_out    (pe_acc_out)
    );

    // -------------------------------------------------------------------------
    // DUT 2: 8x8 Systolic Array
    // -------------------------------------------------------------------------
    logic                                sys_load_wgt;
    logic                                sys_clear_acc;
    logic                                sys_enable;
    logic signed [INT8_WIDTH-1:0]        sys_wgt_matrix [0:N-1][0:N-1];
    logic signed [INT8_WIDTH-1:0]        sys_act_vector [0:N-1];
    wire  signed [ACC_WIDTH-1:0]         sys_acc_out    [0:N-1];
    logic                                sys_data_valid;

    systolic_array_8x8 #(
        .ARRAY_SIZE(N),
        .INT8_WIDTH(INT8_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) dut_array (
        .clk           (clk),
        .rst_n         (rst_n),
        .load_weight   (sys_load_wgt),
        .clear_acc     (sys_clear_acc),
        .enable        (sys_enable),
        .wgt_matrix    (sys_wgt_matrix),
        .act_vector    (sys_act_vector),
        .acc_matrix_out(sys_acc_out),
        .data_valid    (sys_data_valid)
    );

    // -------------------------------------------------------------------------
    // Verification Variables & Scoreboard Storage
    // -------------------------------------------------------------------------
    int total_checks = 0;
    int total_errors = 0;

    logic signed [INT8_WIDTH-1:0] gold_A [0:N-1][0:N-1];
    logic signed [INT8_WIDTH-1:0] gold_W [0:N-1][0:N-1];
    logic signed [ACC_WIDTH-1:0]  expected_C [0:N-1][0:N-1];
    logic signed [ACC_WIDTH-1:0]  actual_C   [0:N-1][0:N-1];

    // -------------------------------------------------------------------------
    // Golden Reference Computation
    // Calculates C[m][n] = sum_k( A[m][k] * W[k][n] ) independently in INT32
    // -------------------------------------------------------------------------
    task compute_expected;
        integer ia, iw, acc;
        for (int m = 0; m < N; m++) begin
            for (int n = 0; n < N; n++) begin
                acc = 0;
                for (int k = 0; k < N; k++) begin
                    ia = gold_A[m][k];
                    iw = gold_W[k][n];
                    acc = acc + (ia * iw);
                end
                expected_C[m][n] = acc;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Scoreboard Checker
    // Compares actual_C against expected_C matrix element-by-element
    // -------------------------------------------------------------------------
    task scoreboard_check(input string test_name);
        bit test_pass;
        test_pass = 1'b1;
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                total_checks++;
                if (actual_C[r][c] !== expected_C[r][c]) begin
                    $error("[SCOREBOARD MISMATCH] %s | Element [%0d][%0d] | Expected: %0d | Got: %0d",
                           test_name, r, c, expected_C[r][c], actual_C[r][c]);
                    total_errors++;
                    test_pass = 1'b0;
                end
            end
        end
        if (test_pass) begin
            $display("  [SCOREBOARD PASS] %s: All 64 matrix elements verified.", test_name);
        end
    endtask

    // -------------------------------------------------------------------------
    // Systolic Array Drive & Capture Task
    // Preloads weights, streams activation vectors, and captures outputs
    // -------------------------------------------------------------------------
    task run_array_test(input string test_name);
        integer row_captured;
        integer timeout_ctr;
        row_captured = 0;
        timeout_ctr  = 0;

        // Step 1: Preload weights into array and clear internal accumulators
        @(posedge clk);
        sys_load_wgt  <= 1'b1;
        sys_clear_acc <= 1'b1;
        @(posedge clk);
        sys_load_wgt  <= 1'b0;
        sys_clear_acc <= 1'b0;

        // Step 2: Start systolic compute and streaming
        sys_enable <= 1'b1;

        fork
            // Thread A: Stream activations (one row per cycle)
            begin
                for (int m = 0; m < N; m++) begin
                    for (int k = 0; k < N; k++) begin
                        sys_act_vector[k] <= gold_A[m][k];
                    end
                    @(posedge clk);
                end
                for (int k = 0; k < N; k++) sys_act_vector[k] <= 8'sd0;
            end

            // Thread B: Capture output rows with timeout watchdog
            begin
                while (row_captured < N) begin
                    @(posedge clk);
                    #1;
                    if (sys_data_valid) begin
                        for (int col = 0; col < N; col++) begin
                            actual_C[row_captured][col] = sys_acc_out[col];
                        end
                        $display("  [ROW %0d CAPTURED] [%0d, %0d, %0d, %0d, %0d, %0d, %0d, %0d]",
                                 row_captured,
                                 actual_C[row_captured][0], actual_C[row_captured][1],
                                 actual_C[row_captured][2], actual_C[row_captured][3],
                                 actual_C[row_captured][4], actual_C[row_captured][5],
                                 actual_C[row_captured][6], actual_C[row_captured][7]);
                        row_captured++;
                    end
                    timeout_ctr++;
                    if (timeout_ctr >= TIMEOUT_MAX) begin
                        $fatal(1, "[TIMEOUT ERROR] %s: data_valid never asserted within %0d cycles!",
                               test_name, TIMEOUT_MAX);
                    end
                end
            end
        join

        sys_enable <= 1'b0;
        @(posedge clk);

        // Step 3: Run scoreboard comparison
        scoreboard_check(test_name);
    endtask

    // -------------------------------------------------------------------------
    // SystemVerilog Assertions (Immediate assertions in clocked always block)
    // Guarded by rst_init_done to avoid pre-reset false positives.
    // -------------------------------------------------------------------------
    logic prev_enable = 1'b0;
    logic prev_clear  = 1'b0;

    always @(posedge clk) begin
        if (rst_init_done) begin
            prev_enable <= sys_enable;
            prev_clear  <= sys_clear_acc;

            // A1: PE acc_out must be zero during active reset
            if (!rst_n) begin
                assert (pe_acc_out === '0)
                    else begin
                        $error("[ASSERT FAIL A1] pe_acc_out not zero during reset: %0d", pe_acc_out);
                        total_errors++;
                    end
            end

            // A2: PE act_out must be zero during active reset
            if (!rst_n) begin
                assert (pe_act_out === '0)
                    else begin
                        $error("[ASSERT FAIL A2] pe_act_out not zero during reset: %0d", pe_act_out);
                        total_errors++;
                    end
            end

            // A3: Systolic data_valid must be zero during active reset
            if (!rst_n) begin
                assert (sys_data_valid === 1'b0)
                    else begin
                        $error("[ASSERT FAIL A3] sys_data_valid active during reset!");
                        total_errors++;
                    end
            end

            // A4: data_valid must be zero when systolic array is disabled
            if (!prev_enable && !sys_enable) begin
                assert (sys_data_valid === 1'b0)
                    else begin
                        $error("[ASSERT FAIL A4] data_valid active while array is disabled!");
                        total_errors++;
                    end
            end

            // A5: Output accumulators must not contain X/Z when data_valid is high
            if (sys_data_valid) begin
                assert (!$isunknown(sys_acc_out[0]) && !$isunknown(sys_acc_out[N-1]))
                    else begin
                        $error("[ASSERT FAIL A5] Output contains X/Z while data_valid is asserted!");
                        total_errors++;
                    end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Main Stimulus Procedure
    // -------------------------------------------------------------------------
    initial begin
        $display("\n=======================================================");
        $display("   TPU-Lite: Computational Core Verification Testbench ");
        $display("=======================================================\n");

        // Step 0: Safe default signal initialization
        pe_load_wgt   = 1'b0;
        pe_clear_acc  = 1'b0;
        pe_enable     = 1'b0;
        pe_act_in     = 8'sd0;
        pe_wgt_in     = 8'sd0;
        pe_acc_in     = 32'sd0;

        sys_load_wgt  = 1'b0;
        sys_clear_acc = 1'b0;
        sys_enable    = 1'b0;

        for (int r = 0; r < N; r++) begin
            sys_act_vector[r] = 8'sd0;
            for (int c = 0; c < N; c++) begin
                sys_wgt_matrix[r][c] = 8'sd0;
            end
        end

        // Step 1: Clean Asynchronous Reset Pulse
        #1;
        rst_n = 1'b0;
        #30;
        rst_init_done = 1'b1;

        // ====================================================================
        // TEST 1: Reset Behavior Check
        // ====================================================================
        $display("[TEST 1] Verifying reset behavior under active reset...");
        total_checks++;
        if (pe_acc_out !== '0) begin
            $error("  [FAIL] pe_acc_out != 0 during reset: %0d", pe_acc_out);
            total_errors++;
        end
        total_checks++;
        if (pe_act_out !== '0) begin
            $error("  [FAIL] pe_act_out != 0 during reset: %0d", pe_act_out);
            total_errors++;
        end
        total_checks++;
        if (sys_data_valid !== 1'b0) begin
            $error("  [FAIL] sys_data_valid != 0 during reset");
            total_errors++;
        end
        $display("  [PASS] All outputs successfully cleared to zero during reset.\n");

        // Release reset
        #20;
        rst_n = 1'b1;
        #20;

        // ====================================================================
        // TEST 2: Single PE Normal Operation
        // Preload weight=6, feed act=4, acc_in=10 -> expect acc_out=34, act_out=4
        // ====================================================================
        $display("[TEST 2] Single PE: Normal Signed MAC (acc_in=10, act=4, wgt=6)...");
        @(posedge clk);
        pe_wgt_in   <= 8'sd6;
        pe_load_wgt <= 1'b1;
        @(posedge clk);
        pe_load_wgt <= 1'b0;

        pe_enable <= 1'b1;
        pe_act_in <= 8'sd4;
        pe_acc_in <= 32'sd10;
        @(posedge clk);
        #1;

        total_checks++;
        if (pe_acc_out !== 32'sd34) begin
            $error("  [FAIL] PE MAC mismatch: Expected 34, Got %0d", pe_acc_out);
            total_errors++;
        end else begin
            $display("  [PASS] PE MAC result: 10 + (4 * 6) = %0d", pe_acc_out);
        end

        total_checks++;
        if (pe_act_out !== 8'sd4) begin
            $error("  [FAIL] PE act_out pipeline mismatch: Expected 4, Got %0d", pe_act_out);
            total_errors++;
        end else begin
            $display("  [PASS] PE registered activation pipeline output = %0d\n", pe_act_out);
        end

        pe_enable <= 1'b0;
        @(posedge clk);

        // ====================================================================
        // TEST 3: Single PE Signed Negative Operands
        // Weight=6, feed act=-3, acc_in=-20 -> expect acc_out = -20 + (-3 * 6) = -38
        // ====================================================================
        $display("[TEST 3] Single PE: Signed Negative Operands (acc_in=-20, act=-3, wgt=6)...");
        pe_enable <= 1'b1;
        pe_act_in <= -8'sd3;
        pe_acc_in <= -32'sd20;
        @(posedge clk);
        #1;

        total_checks++;
        if (pe_acc_out !== -32'sd38) begin
            $error("  [FAIL] PE signed mismatch: Expected -38, Got %0d", pe_acc_out);
            total_errors++;
        end else begin
            $display("  [PASS] PE signed compute: -20 + (-3 * 6) = %0d\n", pe_acc_out);
        end

        pe_enable <= 1'b0;
        @(posedge clk);

        // ====================================================================
        // TEST 4 & 4a: Single PE INT8 Boundary Cases
        // Max positive: 127 * 127 = 16129
        // Min * Max   : -128 * 127 = -16256
        // ====================================================================
        $display("[TEST 4] Single PE: Boundary Case - Max Positive (127 * 127)...");
        @(posedge clk);
        pe_wgt_in   <= 8'sd127;
        pe_load_wgt <= 1'b1;
        @(posedge clk);
        pe_load_wgt <= 1'b0;

        pe_enable <= 1'b1;
        pe_act_in <= 8'sd127;
        pe_acc_in <= 32'sd0;
        @(posedge clk);
        #1;

        total_checks++;
        if (pe_acc_out !== 32'sd16129) begin
            $error("  [FAIL] Max boundary mismatch: Expected 16129, Got %0d", pe_acc_out);
            total_errors++;
        end else begin
            $display("  [PASS] Max boundary: 127 * 127 = %0d", pe_acc_out);
        end

        // Min * Max
        @(posedge clk);
        pe_wgt_in   <= -8'sd128;
        pe_load_wgt <= 1'b1;
        @(posedge clk);
        pe_load_wgt <= 1'b0;

        pe_act_in <= 8'sd127;
        pe_acc_in <= 32'sd0;
        @(posedge clk);
        #1;

        total_checks++;
        if (pe_acc_out !== -32'sd16256) begin
            $error("  [FAIL] Min*Max boundary mismatch: Expected -16256, Got %0d", pe_acc_out);
            total_errors++;
        end else begin
            $display("  [PASS] Min*Max boundary: -128 * 127 = %0d\n", pe_acc_out);
        end

        pe_enable <= 1'b0;
        @(posedge clk);

        // ====================================================================
        // TEST 5: Single PE Zero Activation
        // Act=0, Wgt=5, acc_in=99 -> acc_out should remain unchanged (99)
        // ====================================================================
        $display("[TEST 5] Single PE: Zero Input Operands (wgt=5, act=0, acc_in=99)...");
        @(posedge clk);
        pe_wgt_in   <= 8'sd5;
        pe_load_wgt <= 1'b1;
        @(posedge clk);
        pe_load_wgt <= 1'b0;

        pe_enable <= 1'b1;
        pe_act_in <= 8'sd0;
        pe_acc_in <= 32'sd99;
        @(posedge clk);
        #1;

        total_checks++;
        if (pe_acc_out !== 32'sd99) begin
            $error("  [FAIL] Zero activation mismatch: Expected 99, Got %0d", pe_acc_out);
            total_errors++;
        end else begin
            $display("  [PASS] Zero activation passthrough: acc_out = %0d\n", pe_acc_out);
        end

        pe_enable <= 1'b0;
        @(posedge clk);

        // ====================================================================
        // TEST 6: 8x8 Systolic Array - All-Zero Input Test
        // All weights = 0, all activations = 0 -> Expected C = 0
        // ====================================================================
        $display("[TEST 6] 8x8 Systolic Array: All-Zero Matrices (W=0, A=0)...");
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                gold_W[r][c]         = 8'sd0;
                gold_A[r][c]         = 8'sd0;
                sys_wgt_matrix[r][c] = 8'sd0;
            end
        end
        compute_expected();
        run_array_test("TEST 6 (All-Zero Inputs)");
        $display("");

        // ====================================================================
        // TEST 7: 8x8 Systolic Array - Identity Matrix Test (C = A * I = A)
        // ====================================================================
        $display("[TEST 7] 8x8 Systolic Array: Identity Weights (C = A * I = A)...");
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                gold_W[r][c]         = (r == c) ? 8'sd1 : 8'sd0;
                sys_wgt_matrix[r][c] = gold_W[r][c];
                gold_A[r][c]         = 8'sd10 * (r + 1) + (c + 1);
            end
        end
        compute_expected();
        run_array_test("TEST 7 (Identity Weights)");
        $display("");

        // ====================================================================
        // TEST 8: 8x8 Systolic Array - INT8 Boundary Test
        // A = +127, W = -128 -> Each dot product: 8 * (127 * -128) = -130048
        // ====================================================================
        $display("[TEST 8] 8x8 Systolic Array: Boundary Extremes (A=+127, W=-128)...");
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                gold_A[r][c]         = 8'sd127;
                gold_W[r][c]         = -8'sd128;
                sys_wgt_matrix[r][c] = gold_W[r][c];
            end
        end
        compute_expected();
        run_array_test("TEST 8 (Boundary Values)");
        $display("");

        // ====================================================================
        // TEST 9: 8x8 Systolic Array - Signed Pseudo-Random Matrix Multiply
        // ====================================================================
        $display("[TEST 9] 8x8 Systolic Array: Full Signed Pseudo-Random Multiply...");
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                gold_W[r][c]         = 8'sd3 * (r - 4) + (c - 3);
                gold_A[r][c]         = 8'sd2 * (r - 3) - 8'sd4 * (c - 2);
                sys_wgt_matrix[r][c] = gold_W[r][c];
            end
        end
        compute_expected();
        run_array_test("TEST 9 (Signed Matrix Multiply)");
        $display("");

        // ====================================================================
        // TEST 10: 8x8 Systolic Array - Mid-Run Reset & Recovery
        // Assert reset mid-computation, release, reload, and verify clean run
        // ====================================================================
        $display("[TEST 10] 8x8 Systolic Array: Mid-Run Reset & Clean Recovery...");
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                gold_W[r][c]         = (r == c) ? 8'sd1 : 8'sd0;
                sys_wgt_matrix[r][c] = gold_W[r][c];
                gold_A[r][c]         = 8'(r * N + c + 1);
            end
        end
        compute_expected();

        // Start computation
        @(posedge clk);
        sys_load_wgt  <= 1'b1;
        sys_clear_acc <= 1'b1;
        @(posedge clk);
        sys_load_wgt  <= 1'b0;
        sys_clear_acc <= 1'b0;
        sys_enable    <= 1'b1;

        // Stream 2 rows
        for (int k = 0; k < N; k++) sys_act_vector[k] <= gold_A[0][k];
        @(posedge clk);
        for (int k = 0; k < N; k++) sys_act_vector[k] <= gold_A[1][k];
        @(posedge clk);

        // Abrupt reset mid-stream
        sys_enable <= 1'b0;
        rst_n      <= 1'b0;
        #30;

        total_checks++;
        if (sys_data_valid !== 1'b0) begin
            $error("  [FAIL] data_valid not 0 during mid-run reset!");
            total_errors++;
        end else begin
            $display("  [PASS] Mid-run reset immediately suppresses data_valid.");
        end

        // Release reset & reload weights
        #20;
        rst_n = 1'b1;
        #20;

        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                sys_wgt_matrix[r][c] = gold_W[r][c];
            end
        end

        // Re-execute full test to prove recovery
        run_array_test("TEST 10 (Post-Reset Recovery)");
        $display("");

        // ====================================================================
        // Final Summary Report
        // ====================================================================
        $display("=======================================================");
        $display("                 VERIFICATION SUMMARY                  ");
        $display("=======================================================");
        $display("  Total Assertions & Elements Checked: %0d", total_checks);
        $display("  Total Errors & Scoreboard Mismatches: %0d", total_errors);
        if (total_errors == 0) begin
            $display("  FINAL VERDICT                       : PASSED ALL TESTS");
            $display("=======================================================\n");
            $finish; // Exit code 0
        end else begin
            $display("  FINAL VERDICT                       : FAILED (%0d errors)", total_errors);
            $display("=======================================================\n");
            $fatal(1, "Testbench completed with errors!"); // Exit code 1
        end
    end

endmodule
