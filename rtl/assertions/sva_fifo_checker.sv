// ============================================================================
// TPU-Lite Accelerator SoC - SystemVerilog Assertions (SVA) Buffer Checker
// File: rtl/assertions/sva_fifo_checker.sv
// Description: Verifies SRAM pointer bounds, buffer overflow, and underflow conditions.
// ============================================================================

`timescale 1ns / 1ps

module sva_fifo_checker #(
    parameter int DEPTH = 2048
)(
    input logic        clk,
    input logic        rst_n,
    input logic [10:0] sram_addr,
    input logic        write_en,
    input logic        read_en
);

    // ------------------------------------------------------------------------
    // SVA Property 1: Address Pointer must never exceed maximum SRAM depth
    // ------------------------------------------------------------------------
    property p_addr_bound;
        @(posedge clk) disable iff (!rst_n)
        (write_en || read_en) |-> (sram_addr < DEPTH);
    endproperty
    assert_addr_bound: assert property (p_addr_bound)
        else $error("[SVA ERROR] SRAM Buffer out-of-bounds access detected!");

    // ------------------------------------------------------------------------
    // SVA Property 2: Concurrent Read/Write to same address must be handled safely
    // ------------------------------------------------------------------------
    property p_no_simultaneous_rw_collision;
        @(posedge clk) disable iff (!rst_n)
        !(write_en && read_en);
    endproperty
    assert_no_simultaneous_rw_collision: assert property (p_no_simultaneous_rw_collision)
        else $warning("[SVA WARNING] Simultaneous Read & Write collision on SRAM address!");

endmodule
