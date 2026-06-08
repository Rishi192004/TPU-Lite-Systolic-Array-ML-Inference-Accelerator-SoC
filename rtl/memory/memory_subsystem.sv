// ============================================================================
// TPU-Lite Accelerator SoC - 4-Bank Interleaved SRAM Memory Subsystem
// File: rtl/memory/memory_subsystem.sv
// Description: Double-buffered, 4-bank interleaved memory array for activation,
//              weight, and accumulator result storage.
// ============================================================================

`timescale 1ns / 1ps

`include "axi_defines.svh"

module memory_subsystem #(
    parameter int BANK_DEPTH = SRAM_BANK_DEPTH, // 2048
    parameter int ADDR_WIDTH = SRAM_ADDR_WIDTH  // 11
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // Double-Buffer Swap Controls
    input  logic                    dma_fill_complete,
    input  logic                    compute_complete,
    output logic                    buffer_ready,

    // Port A: AXI DMA Access Interface (32-bit Data)
    input  logic [1:0]              dma_bank_sel,
    input  logic                    dma_en,
    input  logic [3:0]              dma_we,
    input  logic [ADDR_WIDTH-1:0]   dma_addr,
    input  logic [31:0]             dma_wdata,
    output logic [31:0]             dma_rdata,

    // Port B: Systolic Array Activation Read Interface (8 channels x INT8)
    input  logic                    tpu_act_en,
    input  logic [ADDR_WIDTH-1:0]   tpu_act_addr,
    output logic signed [7:0]       tpu_act_data [0:ARRAY_SIZE-1],

    // Port B: Systolic Array Weight Read Interface (8x8 INT8 matrix)
    input  logic                    tpu_wgt_en,
    input  logic [ADDR_WIDTH-1:0]   tpu_wgt_addr,
    output logic signed [7:0]       tpu_wgt_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1],

    // Port B: Systolic Array Output Accumulator Store Interface
    input  logic                    tpu_out_we,
    input  logic [ADDR_WIDTH-1:0]   tpu_out_addr,
    input  logic signed [31:0]      tpu_out_data [0:ARRAY_SIZE-1]
);

    // Double-Buffer Control Instance
    logic active_dma_buf;
    logic active_tpu_buf;

    double_buffer_ctrl u_db_ctrl (
        .clk               (clk),
        .rst_n             (rst_n),
        .dma_fill_complete (dma_fill_complete),
        .compute_complete  (compute_complete),
        .swap_request      (1'b0),
        .active_dma_buffer (active_dma_buf),
        .active_tpu_buffer (active_tpu_buf),
        .buffer_ready      (buffer_ready)
    );

    // 4 Dual-Port SRAM Banks Interleaved
    logic [31:0] bank_douta [0:3];
    logic [31:0] bank_doutb [0:3];

    genvar b;
    generate
        for (b = 0; b < SRAM_NUM_BANKS; b++) begin : gen_sram_banks
            logic bank_ena_sel;
            assign bank_ena_sel = dma_en && (dma_bank_sel == b);

            sram_bank #(
                .DATA_WIDTH(32),
                .ADDR_WIDTH(ADDR_WIDTH)
            ) u_bank (
                .clk   (clk),
                // Port A: DMA Interface
                .ena   (bank_ena_sel),
                .wea   (dma_we),
                .addra (dma_addr),
                .dina  (dma_wdata),
                .douta (bank_douta[b]),
                // Port B: TPU Compute Engine Interface
                .enb   (tpu_act_en || tpu_wgt_en || tpu_out_we),
                .web   (tpu_out_we ? 4'b1111 : 4'b0000),
                .addrb (tpu_out_we ? tpu_out_addr : (tpu_wgt_en ? tpu_wgt_addr : tpu_act_addr)),
                .dinb  (tpu_out_data[b]),
                .doutb (bank_doutb[b])
            );
        end
    endgenerate

    // DMA Read Data Mux
    assign dma_rdata = bank_douta[dma_bank_sel];

    // Unpack Port B Read Data for Activations and Weights
    genvar k;
    generate
        for (k = 0; k < ARRAY_SIZE; k++) begin : gen_act_unpack
            assign tpu_act_data[k] = bank_doutb[k % 4][(k / 4)*8 +: 8];
        end
    endgenerate

    genvar r_idx, c_idx;
    generate
        for (r_idx = 0; r_idx < ARRAY_SIZE; r_idx++) begin : gen_wgt_rows
            for (c_idx = 0; c_idx < ARRAY_SIZE; c_idx++) begin : gen_wgt_cols
                assign tpu_wgt_matrix[r_idx][c_idx] = bank_doutb[(r_idx+c_idx)%4][((r_idx*8+c_idx)%32) +: 8];
            end
        end
    endgenerate

endmodule
