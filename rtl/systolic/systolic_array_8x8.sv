// ============================================================================
// TPU-Lite Accelerator SoC - 8x8 Systolic Array Grid
// File: rtl/systolic/systolic_array_8x8.sv
// Description: 8x8 Weight-Stationary Systolic Array Core.
//              Features built-in activation skewing registers, 64 retimed PEs,
//              and vertical accumulation reduction chains.
// ============================================================================

`timescale 1ns / 1ps

module systolic_array_8x8 #(
    parameter int ARRAY_SIZE = 8,
    parameter int INT8_WIDTH = 8,
    parameter int ACC_WIDTH  = 32
)(
    input  logic                                clk,
    input  logic                                rst_n,
    
    // Global Array Controls
    input  logic                                load_weight,  // Preload weights into array
    input  logic                                clear_acc,    // Reset internal accumulators
    input  logic                                enable,       // Active compute enable
    
    // Input Interfaces
    input  logic signed [INT8_WIDTH-1:0]       wgt_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1], // Preload weights
    input  logic signed [INT8_WIDTH-1:0]       act_vector [0:ARRAY_SIZE-1],                 // Stream activations
    
    // Output Interface
    output logic signed [ACC_WIDTH-1:0]        acc_matrix_out [0:ARRAY_SIZE-1],             // Bottom row outputs
    output logic                                data_valid                                  // Valid compute result flag
);

    // ------------------------------------------------------------------------
    // Activation Input Skewing Registers
    // Row 'i' is delayed by 'i' clock cycles for systolic alignment.
    // ------------------------------------------------------------------------
    logic signed [INT8_WIDTH-1:0] act_skewed [0:ARRAY_SIZE-1];

    genvar r;
    generate
        for (r = 0; r < ARRAY_SIZE; r++) begin : gen_skew_rows
            if (r == 0) begin
                assign act_skewed[0] = act_vector[0];
            end else begin
                // Shift register of depth 'r'
                logic signed [INT8_WIDTH-1:0] shift_reg [0:r-1];
                
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        for (int k = 0; k < r; k++) shift_reg[k] <= '0;
                    end else if (enable) begin
                        shift_reg[0] <= act_vector[r];
                        for (int k = 1; k < r; k++) begin
                            shift_reg[k] <= shift_reg[k-1];
                        end
                    end
                end
                assign act_skewed[r] = shift_reg[r-1];
            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Inter-PE Routing Wires
    // ------------------------------------------------------------------------
    logic signed [INT8_WIDTH-1:0] pe_act_wire [0:ARRAY_SIZE-1][0:ARRAY_SIZE];
    logic signed [ACC_WIDTH-1:0]  pe_acc_wire [0:ARRAY_SIZE][0:ARRAY_SIZE-1];

    // Connect leftmost activation inputs
    genvar row_idx;
    generate
        for (row_idx = 0; row_idx < ARRAY_SIZE; row_idx++) begin : gen_act_inputs
            assign pe_act_wire[row_idx][0] = act_skewed[row_idx];
        end
    endgenerate

    // Connect topmost accumulator inputs to ZERO
    genvar col_idx;
    generate
        for (col_idx = 0; col_idx < ARRAY_SIZE; col_idx++) begin : gen_acc_inputs
            assign pe_acc_wire[0][col_idx] = '0;
        end
    endgenerate

    // ------------------------------------------------------------------------
    // 8x8 PE Grid Instantiation
    // ------------------------------------------------------------------------
    genvar i, j;
    generate
        for (i = 0; i < ARRAY_SIZE; i++) begin : gen_pe_matrix_rows
            for (j = 0; j < ARRAY_SIZE; j++) begin : gen_pe_matrix_cols
                processing_element #(
                    .INT8_WIDTH(INT8_WIDTH),
                    .ACC_WIDTH (ACC_WIDTH)
                ) u_pe (
                    .clk         (clk),
                    .rst_n       (rst_n),
                    .load_weight (load_weight),
                    .clear_acc   (clear_acc),
                    .enable      (enable),
                    .act_in      (pe_act_wire[i][j]),
                    .wgt_in      (wgt_matrix[i][j]),
                    .acc_in      (pe_acc_wire[i][j]),
                    .act_out     (pe_act_wire[i][j+1]),
                    .acc_out     (pe_acc_wire[i+1][j])
                );
            end
        end
    endgenerate

    // Connect bottom row accumulator wires to outputs
    generate
        for (col_idx = 0; col_idx < ARRAY_SIZE; col_idx++) begin : gen_outputs
            assign acc_matrix_out[col_idx] = pe_acc_wire[ARRAY_SIZE][col_idx];
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Compute Pipeline Valid Latency Counter
    // Systolic latency for 8x8 array is 3*ARRAY_SIZE - 2 cycles.
    // ------------------------------------------------------------------------
    logic [7:0] compute_counter;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compute_counter <= '0;
            data_valid      <= 1'b0;
        end else if (clear_acc) begin
            compute_counter <= '0;
            data_valid      <= 1'b0;
        end else if (enable) begin
            if (compute_counter < (3 * ARRAY_SIZE)) begin
                compute_counter <= compute_counter + 1'b1;
                data_valid      <= (compute_counter >= (2 * ARRAY_SIZE - 1));
            end
        end
    end

endmodule
