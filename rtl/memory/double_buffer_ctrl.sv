// ============================================================================
// TPU-Lite Accelerator SoC - Ping-Pong Double Buffer Controller
// File: rtl/memory/double_buffer_ctrl.sv
// Description: Manages active/idle memory ping-pong buffer pages.
//              Enables simultaneous DMA host streaming into Page 0 while
//              Systolic Array computes from Page 1, maximizing throughput.
// ============================================================================

`timescale 1ns / 1ps

module double_buffer_ctrl (
    input  logic clk,
    input  logic rst_n,
    
    // Status / Event Controls
    input  logic dma_fill_complete,   // DMA finished loading buffer
    input  logic compute_complete,    // Systolic Array finished compute step
    input  logic swap_request,        // Host CSR request to swap buffers
    
    // Active Buffer Pointers (0 or 1)
    output logic active_dma_buffer,   // Buffer assigned to DMA Engine
    output logic active_tpu_buffer,   // Buffer assigned to TPU Compute Engine
    output logic buffer_ready         // Flag indicating compute data is available
);

    // Ping-Pong Register Flag
    // 0: Buffer 0 = DMA, Buffer 1 = TPU
    // 1: Buffer 1 = DMA, Buffer 0 = TPU
    logic ping_pong_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ping_pong_state <= 1'b0;
            buffer_ready    <= 1'b0;
        end else begin
            if (swap_request || (dma_fill_complete && compute_complete)) begin
                ping_pong_state <= ~ping_pong_state;
                buffer_ready    <= 1'b1;
            end else if (dma_fill_complete) begin
                buffer_ready    <= 1'b1;
            end
        end
    end

    assign active_dma_buffer = ping_pong_state;
    assign active_tpu_buffer = ~ping_pong_state;

endmodule
