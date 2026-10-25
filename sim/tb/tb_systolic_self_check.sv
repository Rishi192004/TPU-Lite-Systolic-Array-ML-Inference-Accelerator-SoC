// ============================================================================
// TPU-Lite: Self-Checking Testbench for Processing Element & Systolic Array
// File: sim/tb/tb_systolic_self_check.sv
// ============================================================================

`timescale 1ns / 1ps

module tb_systolic_self_check;

    localparam int ARRAY_SIZE = 8;
    localparam int INT8_WIDTH = 8;
    localparam int ACC_WIDTH  = 32;

    logic clk;
    logic rst_n;
    always #5 clk = ~clk; // 100 MHz clock (10 ns period)

    // Global Test Counters
    int error_count = 0;
    int test_count  = 0;

    // ------------------------------------------------------------------------
    // Part 1: Single Processing Element Unit Test
    // ------------------------------------------------------------------------
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

    // ------------------------------------------------------------------------
    // Part 2: 8x8 Systolic Array DUT
    // ------------------------------------------------------------------------
    logic                                sys_load_wgt;
    logic                                sys_clear_acc;
    logic                                sys_enable;
    logic signed [INT8_WIDTH-1:0]        sys_wgt_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    logic signed [INT8_WIDTH-1:0]        sys_act_vector [0:ARRAY_SIZE-1];
    wire signed [ACC_WIDTH-1:0]          sys_acc_matrix_out [0:ARRAY_SIZE-1];
    logic                                sys_data_valid;

    systolic_array_8x8 #(
        .ARRAY_SIZE(ARRAY_SIZE),
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
        .acc_matrix_out(sys_acc_matrix_out),
        .data_valid    (sys_data_valid)
    );

    // Golden verification data
    logic signed [INT8_WIDTH-1:0] gold_A [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    logic signed [INT8_WIDTH-1:0] gold_W [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    logic signed [ACC_WIDTH-1:0]  gold_C [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    logic signed [ACC_WIDTH-1:0]  actual_C [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    // Compute golden C = A x W
    function void compute_golden();
        integer m, n, k;
        integer a_val, w_val;
        for (m = 0; m < ARRAY_SIZE; m = m + 1) begin
            for (n = 0; n < ARRAY_SIZE; n = n + 1) begin
                gold_C[m][n] = 0;
                for (k = 0; k < ARRAY_SIZE; k = k + 1) begin
                    a_val = gold_A[m][k];
                    w_val = gold_W[k][n];
                    gold_C[m][n] = gold_C[m][n] + (a_val * w_val);
                end
            end
        end
    endfunction

    // ------------------------------------------------------------------------
    // Main Test Stimulus
    // ------------------------------------------------------------------------
    initial begin
        $display("\n=======================================================");
        $display("   TPU-Lite: Processing Element & Systolic Array Test   ");
        $display("=======================================================\n");

        clk   = 0;
        rst_n = 0;

        // Initialize PE signals
        pe_load_wgt  = 0;
        pe_clear_acc = 0;
        pe_enable    = 0;
        pe_act_in    = 0;
        pe_wgt_in    = 0;
        pe_acc_in    = 0;

        // Initialize Array signals
        sys_load_wgt  = 0;
        sys_clear_acc = 0;
        sys_enable    = 0;
        for (int r = 0; r < ARRAY_SIZE; r++) begin
            sys_act_vector[r] = 0;
            for (int c = 0; c < ARRAY_SIZE; c++) begin
                sys_wgt_matrix[r][c] = 0;
            end
        end

        // Reset sequence
        #20 rst_n = 1;
        #20;

        // ====================================================================
        // TEST 1: Single Processing Element Verification
        // ====================================================================
        $display("[TEST 1] Verifying Single Processing Element...");
        @(posedge clk);
        // Step 1: Preload weight = 6
        pe_wgt_in   <= 8'sd6;
        pe_load_wgt <= 1'b1;
        @(posedge clk);
        pe_load_wgt <= 1'b0;

        // Step 2: Feed activation = 4, acc_in = 10
        // Expect: acc_out <= 10 + (4 * 6) = 34 on next clock
        pe_enable  <= 1'b1;
        pe_act_in  <= 8'sd4;
        pe_acc_in  <= 32'sd10;
        @(posedge clk);
        #1; // Sample after register update
        test_count++;
        if (pe_acc_out !== 32'sd34) begin
            $error("[FAIL] PE compute mismatch! Expected: 34, Got: %0d", pe_acc_out);
            error_count++;
        end else begin
            $display("  [PASS] PE compute: 10 + (4 * 6) = %0d", pe_acc_out);
        end

        // Check horizontal pipelining of act_out
        test_count++;
        if (pe_act_out !== 8'sd4) begin
            $error("[FAIL] PE act_out pipeline mismatch! Expected: 4, Got: %0d", pe_act_out);
            error_count++;
        end else begin
            $display("  [PASS] PE act_out registered pipeline = %0d", pe_act_out);
        end

        // Feed negative activation = -3, acc_in = -20
        // Expect: acc_out <= -20 + (-3 * 6) = -38
        pe_act_in <= -8'sd3;
        pe_acc_in <= -32'sd20;
        @(posedge clk);
        #1;
        test_count++;
        if (pe_acc_out !== -32'sd38) begin
            $error("[FAIL] PE signed compute mismatch! Expected: -38, Got: %0d", pe_acc_out);
            error_count++;
        end else begin
            $display("  [PASS] PE signed compute: -20 + (-3 * 6) = %0d", pe_acc_out);
        end

        pe_enable <= 1'b0;
        @(posedge clk);

        // ====================================================================
        // TEST 2: 8x8 Systolic Array - Identity Matrix Test (C = A * I = A)
        // ====================================================================
        $display("\n[TEST 2] Verifying 8x8 Systolic Array with Identity Weights (C = A * I = A)...");
        // Preload Identity Matrix W = I
        for (int r = 0; r < ARRAY_SIZE; r++) begin
            for (int c = 0; c < ARRAY_SIZE; c++) begin
                sys_wgt_matrix[r][c] = (r == c) ? 8'sd1 : 8'sd0;
                gold_W[r][c]         = sys_wgt_matrix[r][c];
                // Distinct test activation values
                gold_A[r][c]         = 8'sd10 * (r + 1) + (c + 1);
            end
        end
        compute_golden();

        @(posedge clk);
        sys_load_wgt  <= 1'b1;
        sys_clear_acc <= 1'b1;
        @(posedge clk);
        sys_load_wgt  <= 1'b0;
        sys_clear_acc <= 1'b0;

        // Stream activations row-by-row into array
        sys_enable <= 1'b1;
        fork
            // Thread A: Stream 8 activation rows (one vector per cycle)
            begin
                for (int m = 0; m < ARRAY_SIZE; m++) begin
                    for (int k = 0; k < ARRAY_SIZE; k++) begin
                        sys_act_vector[k] <= gold_A[m][k];
                    end
                    @(posedge clk);
                end
                // Clear input after 8 rows
                for (int k = 0; k < ARRAY_SIZE; k++) sys_act_vector[k] <= 8'sd0;
            end

            // Thread B: Capture and verify output rows when sys_data_valid is asserted
            begin
                integer row_captured;
                row_captured = 0;
                while (row_captured < ARRAY_SIZE) begin
                    @(posedge clk);
                    #1;
                    if (sys_data_valid) begin
                        for (int col = 0; col < ARRAY_SIZE; col++) begin
                            actual_C[row_captured][col] = sys_acc_matrix_out[col];
                            test_count++;
                            if (actual_C[row_captured][col] !== gold_C[row_captured][col]) begin
                                $error("  [FAIL] Row %0d Col %0d Mismatch! Expected: %0d, Got: %0d",
                                    row_captured, col, gold_C[row_captured][col], actual_C[row_captured][col]);
                                error_count++;
                            end
                        end
                        $display("  [PASS] Captured Row %0d: [%0d, %0d, %0d, %0d, %0d, %0d, %0d, %0d]",
                            row_captured,
                            actual_C[row_captured][0], actual_C[row_captured][1],
                            actual_C[row_captured][2], actual_C[row_captured][3],
                            actual_C[row_captured][4], actual_C[row_captured][5],
                            actual_C[row_captured][6], actual_C[row_captured][7]);
                        row_captured++;
                    end
                end
            end
        join

        sys_enable <= 1'b0;
        @(posedge clk);

        // ====================================================================
        // TEST 3: 8x8 Systolic Array - Signed Random Matrix Multiplication
        // ====================================================================
        $display("\n[TEST 3] Verifying 8x8 Systolic Array with Full Signed Random Matrices...");
        // Set up pseudo-random signed INT8 values (-128 to 127)
        for (int r = 0; r < ARRAY_SIZE; r++) begin
            for (int c = 0; c < ARRAY_SIZE; c++) begin
                gold_W[r][c]         = 8'sd3 * (r - 4) + (c - 3);
                gold_A[r][c]         = 8'sd2 * (r - 3) - 8'sd4 * (c - 2);
                sys_wgt_matrix[r][c] = gold_W[r][c];
            end
        end
        compute_golden();

        @(posedge clk);
        sys_load_wgt  <= 1'b1;
        sys_clear_acc <= 1'b1;
        @(posedge clk);
        sys_load_wgt  <= 1'b0;
        sys_clear_acc <= 1'b0;

        sys_enable <= 1'b1;
        fork
            begin
                for (int m = 0; m < ARRAY_SIZE; m++) begin
                    for (int k = 0; k < ARRAY_SIZE; k++) begin
                        sys_act_vector[k] <= gold_A[m][k];
                    end
                    @(posedge clk);
                end
                for (int k = 0; k < ARRAY_SIZE; k++) sys_act_vector[k] <= 8'sd0;
            end

            begin
                integer row_captured;
                row_captured = 0;
                while (row_captured < ARRAY_SIZE) begin
                    @(posedge clk);
                    #1;
                    if (sys_data_valid) begin
                        for (int col = 0; col < ARRAY_SIZE; col++) begin
                            actual_C[row_captured][col] = sys_acc_matrix_out[col];
                            test_count++;
                            if (actual_C[row_captured][col] !== gold_C[row_captured][col]) begin
                                $error("  [FAIL] Random Matrix Row %0d Col %0d Mismatch! Expected: %0d, Got: %0d",
                                    row_captured, col, gold_C[row_captured][col], actual_C[row_captured][col]);
                                error_count++;
                            end
                        end
                        $display("  [PASS] Captured Signed Row %0d: [%0d, %0d, %0d, %0d, %0d, %0d, %0d, %0d]",
                            row_captured,
                            actual_C[row_captured][0], actual_C[row_captured][1],
                            actual_C[row_captured][2], actual_C[row_captured][3],
                            actual_C[row_captured][4], actual_C[row_captured][5],
                            actual_C[row_captured][6], actual_C[row_captured][7]);
                        row_captured++;
                    end
                end
            end
        join

        sys_enable <= 1'b0;
        #50;

        // ====================================================================
        // Summary Report
        // ====================================================================
        $display("\n=======================================================");
        $display("                 VERIFICATION SUMMARY                  ");
        $display("=======================================================");
        $display("  Total Assertions / Elements Checked: %0d", test_count);
        $display("  Total Errors / Mismatches          : %0d", error_count);
        if (error_count == 0) begin
            $display("  FINAL VERDICT                      : PASSED ALL TESTS");
        end else begin
            $display("  FINAL VERDICT                      : FAILED (%0d errors)", error_count);
        end
        $display("=======================================================\n");

        if (error_count == 0) $finish;
        else $fatal(1, "Testbench encountered errors!");
    end

endmodule
