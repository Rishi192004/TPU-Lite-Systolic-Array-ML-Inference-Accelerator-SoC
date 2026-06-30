// ============================================================================
// TPU-Lite Accelerator SoC - SystemVerilog Assertions (SVA) AXI Protocol Checker
// File: rtl/assertions/sva_axi4_checker.sv
// Description: Formal temporal properties verifying AXI4 protocol compliance,
//              handshake stability, address alignment, and burst safety.
// ============================================================================

`timescale 1ns / 1ps

module sva_axi4_checker #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64
)(
    input logic                    clk,
    input logic                    rst_n,

    // AXI Write Address Channel
    input logic [ADDR_WIDTH-1:0]   awaddr,
    input logic                    awvalid,
    input logic                    awready,

    // AXI Write Data Channel
    input logic [DATA_WIDTH-1:0]   wdata,
    input logic                    wvalid,
    input logic                    wready,

    // AXI Read Address Channel
    input logic [ADDR_WIDTH-1:0]   araddr,
    input logic                    arvalid,
    input logic                    arready,

    // AXI Read Data Channel
    input logic [DATA_WIDTH-1:0]   rdata,
    input logic                    rvalid,
    input logic                    rready
);

    // ------------------------------------------------------------------------
    // SVA Property 1: AWVALID must remain HIGH until AWREADY is asserted
    // ------------------------------------------------------------------------
    property p_awvalid_stability;
        @(posedge clk) disable iff (!rst_n)
        (awvalid && !awready) |=> $stable(awvalid) && $stable(awaddr);
    endproperty
    assert_awvalid_stability: assert property (p_awvalid_stability)
        else $error("[SVA ERROR] AXI AWVALID dropped before AWREADY handshake!");

    // ------------------------------------------------------------------------
    // SVA Property 2: WVALID must remain HIGH until WREADY is asserted
    // ------------------------------------------------------------------------
    property p_wvalid_stability;
        @(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> $stable(wvalid) && $stable(wdata);
    endproperty
    assert_wvalid_stability: assert property (p_wvalid_stability)
        else $error("[SVA ERROR] AXI WVALID/WDATA dropped before WREADY handshake!");

    // ------------------------------------------------------------------------
    // SVA Property 3: ARVALID must remain HIGH until ARREADY is asserted
    // ------------------------------------------------------------------------
    property p_arvalid_stability;
        @(posedge clk) disable iff (!rst_n)
        (arvalid && !arready) |=> $stable(arvalid) && $stable(araddr);
    endproperty
    assert_arvalid_stability: assert property (p_arvalid_stability)
        else $error("[SVA ERROR] AXI ARVALID dropped before ARREADY handshake!");

    // ------------------------------------------------------------------------
    // SVA Property 4: Address must be 64-bit aligned (lower 3 bits == 0)
    // ------------------------------------------------------------------------
    property p_addr_alignment;
        @(posedge clk) disable iff (!rst_n)
        awvalid |-> (awaddr[2:0] == 3'b000);
    endproperty
    assert_addr_alignment: assert property (p_addr_alignment)
        else $warning("[SVA WARNING] AXI AWADDR is unaligned to 64-bit boundary!");

endmodule
