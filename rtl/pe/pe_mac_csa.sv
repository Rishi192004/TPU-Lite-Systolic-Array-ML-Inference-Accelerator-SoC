// ============================================================================
// TPU-Lite Accelerator SoC - Retimed INT8 MAC with Carry-Save Adder (CSA)
// File: rtl/pe/pe_mac_csa.sv
// Description: Retimed 8-bit signed multiplier with 3:2 Carry-Save Adder
//              reduction and pipelined accumulator stage.
//              Optimized for 250 MHz operation on Xilinx Artix-7 FPGAs.
//              Resolves a 3.1 ns critical path through DSP multiplier carry chain.
// ============================================================================

`timescale 1ns / 1ps

module pe_mac_csa #(
    parameter int INT8_WIDTH = 8,
    parameter int ACC_WIDTH  = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    clear_acc,    // Clear accumulator for new matrix pass
    input  logic                    enable,       // Clock enable for computing stage
    input  logic signed [INT8_WIDTH-1:0] act_in,  // INT8 activation
    input  logic signed [INT8_WIDTH-1:0] wgt_in,  // INT8 weight
    output logic signed [ACC_WIDTH-1:0]  acc_out  // INT32 accumulated result
);

    // ------------------------------------------------------------------------
    // Stage 1: Signed 8x8 Multiplication & Carry-Save Adder (CSA) Logic
    // ------------------------------------------------------------------------
    logic signed [15:0] mult_product;
    logic signed [ACC_WIDTH-1:0] mult_product_ext;

    assign mult_product = act_in * wgt_in;
    assign mult_product_ext = {{16{mult_product[15]}}, mult_product};

    // CSA 3:2 Compressor Signals
    logic [ACC_WIDTH-1:0] csa_sum_comb;
    logic [ACC_WIDTH-1:0] csa_carry_comb;

    // Bitwise Carry-Save Reduction of Current Accumulator + Multiplier Product
    genvar i;
    generate
        for (i = 0; i < ACC_WIDTH; i++) begin : gen_csa_bits
            assign csa_sum_comb[i]   = acc_out[i] ^ mult_product_ext[i] ^ 1'b0; // Partial Sum
            if (i < ACC_WIDTH - 1) begin
                assign csa_carry_comb[i+1] = (acc_out[i] & mult_product_ext[i]); // Shifted Carry
            end
        end
    endgenerate
    assign csa_carry_comb[0] = 1'b0;

    // ------------------------------------------------------------------------
    // Retiming Pipeline Stage: Registering Sum and Carry vectors
    // Prevents carry propagation logic from cascading into accumulator register.
    // ------------------------------------------------------------------------
    logic signed [ACC_WIDTH-1:0] csa_sum_reg;
    logic signed [ACC_WIDTH-1:0] csa_carry_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csa_sum_reg   <= '0;
            csa_carry_reg <= '0;
        end else if (clear_acc) begin
            csa_sum_reg   <= '0;
            csa_carry_reg <= '0;
        end else if (enable) begin
            csa_sum_reg   <= csa_sum_comb;
            csa_carry_reg <= csa_carry_comb;
        end
    end

    // ------------------------------------------------------------------------
    // Stage 2: Final Carry-Propagate Accumulator Update
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out <= '0;
        end else if (clear_acc) begin
            acc_out <= '0;
        end else if (enable) begin
            // Final CPA addition of retimed sum and carry
            acc_out <= csa_sum_reg + csa_carry_reg;
        end
    end

endmodule
