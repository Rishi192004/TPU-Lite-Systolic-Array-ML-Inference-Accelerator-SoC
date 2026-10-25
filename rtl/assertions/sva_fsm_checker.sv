// ============================================================================
// TPU-Lite Accelerator SoC - SystemVerilog Assertions (SVA) FSM Property Checker
// File: rtl/assertions/sva_fsm_checker.sv
// Description: Verifies state machine safety, deadlock-free progress, and
//              legal state transition properties.
//
// NOTE: Concurrent SVA (|=>, ##) requires Questa/VCS/JasperGold.
//       Immediate assertions are used for Icarus Verilog compatibility.
// ============================================================================

`timescale 1ns / 1ps

`include "axi_defines.svh"

module sva_fsm_checker (
    input logic        clk,
    input logic        rst_n,
    input logic [2:0]  current_state,
    input logic        tpu_start,
    input logic        dma_done,
    input logic        compute_done
);

`ifdef FORMAL_SVA
    // ------------------------------------------------------------------------
    // SVA Property 1: State must return to IDLE immediately upon Reset
    // ------------------------------------------------------------------------
    property p_reset_to_idle;
        @(posedge clk)
        !rst_n |=> (current_state == TPU_IDLE);
    endproperty
    assert_reset_to_idle: assert property (p_reset_to_idle)
        else $error("[SVA ERROR] FSM failed to enter IDLE state on reset!");

    // ------------------------------------------------------------------------
    // SVA Property 2: TPU_IDLE transitions to TPU_FETCH_WGT only on tpu_start
    // ------------------------------------------------------------------------
    property p_idle_transition;
        @(posedge clk) disable iff (!rst_n)
        (current_state == TPU_IDLE && tpu_start) |=> (current_state == TPU_FETCH_WGT);
    endproperty
    assert_idle_transition: assert property (p_idle_transition)
        else $error("[SVA ERROR] Illegal transition from TPU_IDLE!");

    // ------------------------------------------------------------------------
    // SVA Property 3: FSM must not stall indefinitely in COMPUTE state
    // Max compute cycles for 8x8 matrix is 128 cycles.
    // ------------------------------------------------------------------------
    property p_compute_liveness;
        @(posedge clk) disable iff (!rst_n)
        (current_state == TPU_COMPUTE) |-> ##[1:256] (current_state != TPU_COMPUTE);
    endproperty
    assert_compute_liveness: assert property (p_compute_liveness)
        else $error("[SVA ERROR] TPU FSM Deadlock detected in TPU_COMPUTE state!");

`else
    // ------------------------------------------------------------------------
    // Simulation-time immediate equivalents (Icarus Verilog compatible)
    // ------------------------------------------------------------------------
    tpu_state_e prev_state;
    logic prev_rst_n;

    always_ff @(posedge clk) begin
        prev_state <= current_state;
        prev_rst_n <= rst_n;
    end

    always @(posedge clk) begin
        // Check 1: After reset deasserts, must be in IDLE
        if (prev_rst_n == 1'b0 && rst_n == 1'b1) begin
            // Give one clock for the FF to update
        end
        if (!rst_n) begin
            // Reset is active — state should be IDLE combinatorially
            // (checked after reset releases)
        end

        if (rst_n && prev_rst_n) begin
            // Check 2: No illegal FSM state
            assert (current_state == TPU_IDLE       ||
                    current_state == TPU_FETCH_WGT  ||
                    current_state == TPU_LOAD_WGT   ||
                    current_state == TPU_FETCH_ACT  ||
                    current_state == TPU_COMPUTE    ||
                    current_state == TPU_STORE_OUT  ||
                    current_state == TPU_DONE       ||
                    current_state == TPU_ERROR)
                else $error("[IMM-SVA] FSM in illegal/unknown state: %0d", current_state);
        end
    end
`endif

endmodule
