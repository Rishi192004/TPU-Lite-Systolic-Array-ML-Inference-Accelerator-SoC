// ============================================================================
// TPU-Lite Accelerator SoC - Synthesizable Dual-Port Block SRAM Bank
// File: rtl/memory/sram_bank.sv
// Description: Synchronous Dual-Port SRAM with Byte Enables.
//              Inferred as Xilinx Block RAM (BRAM36) by Vivado synthesis.
// ============================================================================

`timescale 1ns / 1ps

module sram_bank #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 11, // 2048 entries x 32-bit = 8 KB
    parameter int BYTE_ENABLES = DATA_WIDTH / 8
)(
    input  logic                    clk,
    
    // Port A (Host / AXI DMA Engine Interface)
    input  logic                    ena,
    input  logic [BYTE_ENABLES-1:0] wea,
    input  logic [ADDR_WIDTH-1:0]   addra,
    input  logic [DATA_WIDTH-1:0]   dina,
    output logic [DATA_WIDTH-1:0]   douta,
    
    // Port B (Systolic Array Compute Interface)
    input  logic                    enb,
    input  logic [BYTE_ENABLES-1:0] web,
    input  logic [ADDR_WIDTH-1:0]   addrb,
    input  logic [DATA_WIDTH-1:0]   dinb,
    output logic [DATA_WIDTH-1:0]   doutb
);

    // RAM Memory Array Block
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // Port A Read/Write Operations with Byte Masking
    genvar i;
    generate
        for (i = 0; i < BYTE_ENABLES; i++) begin : gen_port_a_write
            always_ff @(posedge clk) begin
                if (ena) begin
                    if (wea[i]) begin
                        ram[addra][(i+1)*8-1 : i*8] <= dina[(i+1)*8-1 : i*8];
                    end
                end
            end
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (ena) begin
            douta <= ram[addra];
        end
    end

    // Port B Read/Write Operations with Byte Masking
    generate
        for (i = 0; i < BYTE_ENABLES; i++) begin : gen_port_b_write
            always_ff @(posedge clk) begin
                if (enb) begin
                    if (web[i]) begin
                        ram[addrb][(i+1)*8-1 : i*8] <= dinb[(i+1)*8-1 : i*8];
                    end
                end
            end
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (enb) begin
            doutb <= ram[addrb];
        end
    end

endmodule
