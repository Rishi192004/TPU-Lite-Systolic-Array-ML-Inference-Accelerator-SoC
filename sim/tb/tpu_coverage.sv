// ============================================================================
// TPU-Lite Accelerator SoC - Functional Coverage Model
// File: sim/tb/tpu_coverage.sv
// Description: Defines SystemVerilog functional coverage groups for MAC values,
//              SRAM access patterns, AXI burst lengths, and FSM states.
// ============================================================================

`timescale 1ns / 1ps

`include "axi_defines.svh"

module tpu_coverage_wrapper (
    input logic        clk,
    input logic        rst_n,
    input tpu_state_e  current_state,
    input logic signed [7:0] act_sample,
    input logic signed [7:0] wgt_sample,
    input logic [7:0]  axi_burst_len
);

    covergroup cg_tpu_functional @(posedge clk);
        option.per_instance = 1;
        option.comment = "TPU-Lite Functional Coverage";

        // FSM State Coverage
        cp_fsm_states: coverpoint current_state {
            bins idle       = {TPU_IDLE};
            bins fetch_wgt  = {TPU_FETCH_WGT};
            bins load_wgt   = {TPU_LOAD_WGT};
            bins fetch_act  = {TPU_FETCH_ACT};
            bins compute    = {TPU_COMPUTE};
            bins store_out  = {TPU_STORE_OUT};
            bins done       = {TPU_DONE};
        }

        // INT8 Activation Value Range Bins
        cp_act_values: coverpoint act_sample {
            bins min_int8   = {-128};
            bins zero       = {0};
            bins max_int8   = {127};
            bins negative   = {[-127:-1]};
            bins positive   = {[1:126]};
        }

        // INT8 Weight Value Range Bins
        cp_wgt_values: coverpoint wgt_sample {
            bins min_int8   = {-128};
            bins zero       = {0};
            bins max_int8   = {127};
            bins negative   = {[-127:-1]};
            bins positive   = {[1:126]};
        }

        // Cross Coverage: Act x Wgt
        cross_act_wgt: cross cp_act_values, cp_wgt_values;

        // AXI Burst Length Coverage
        cp_axi_burst: coverpoint axi_burst_len {
            bins single_beat = {0};
            bins short_burst = {[1:15]};
            bins max_burst   = {255};
        }
    endgroup

    cg_tpu_functional inst_cg = new();

endmodule
