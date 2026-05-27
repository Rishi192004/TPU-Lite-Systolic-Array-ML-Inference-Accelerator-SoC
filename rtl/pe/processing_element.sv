// ============================================================================
// TPU-Lite Accelerator SoC - Weight-Stationary Processing Element (PE)
// File: rtl/pe/processing_element.sv
// Description: Processing Element for Weight-Stationary Systolic Array.
//              Supports weight loading, horizontal activation streaming,
//              and vertical accumulation propagation.
// ============================================================================

`timescale 1ns / 1ps

module processing_element #(
    parameter int INT8_WIDTH = 8,
    parameter int ACC_WIDTH  = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Control Flags
    input  logic                    load_weight,   // Active high to capture wgt_in into weight register
    input  logic                    clear_acc,     // Resets internal accumulator
    input  logic                    enable,        // Processing enable flag
    
    // Data Inputs
    input  logic signed [INT8_WIDTH-1:0] act_in,    // Activation input (from left PE or SRAM)
    input  logic signed [INT8_WIDTH-1:0] wgt_in,    // Weight input (during preload phase)
    input  logic signed [ACC_WIDTH-1:0]  acc_in,    // Partial sum input (from upper PE)
    
    // Data Outputs
    output logic signed [INT8_WIDTH-1:0] act_out,   // Activation output (to right PE)
    output logic signed [ACC_WIDTH-1:0]  acc_out    // Accumulated result output (to lower PE)
);

    // ------------------------------------------------------------------------
    // Internal Registers
    // ------------------------------------------------------------------------
    logic signed [INT8_WIDTH-1:0] weight_reg;
    logic signed [INT8_WIDTH-1:0] act_reg;
    logic signed [ACC_WIDTH-1:0]  mac_acc_result;

    // Weight Preload logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_reg <= '0;
        end else if (load_weight) begin
            weight_reg <= wgt_in;
        end
    end

    // Horizontal Activation Pipeline Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            act_reg <= '0;
        end else if (enable) begin
            act_reg <= act_in;
        end
    end

    // Instantiation of Retimed CSA MAC Unit
    pe_mac_csa #(
        .INT8_WIDTH(INT8_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_mac_core (
        .clk       (clk),
        .rst_n     (rst_n),
        .clear_acc (clear_acc),
        .enable    (enable),
        .act_in    (act_in),
        .wgt_in    (weight_reg),
        .acc_out   (mac_acc_result)
    );

    // Combine upper partial sum with local MAC product output
    assign act_out = act_reg;
    assign acc_out = mac_acc_result + acc_in;

endmodule
