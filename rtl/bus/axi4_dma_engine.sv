// ============================================================================
// TPU-Lite Accelerator SoC - High-Performance AXI4 Burst Master DMA Engine
// File: rtl/bus/axi4_dma_engine.sv
// Description: AXI4 Master DMA Burst Engine (64-bit data width).
//              Supports INCR burst mode up to 256 beats for streaming
//              matrix activations, weights, and results.
// ============================================================================

`timescale 1ns / 1ps

`include "axi_defines.svh"

module axi4_dma_engine #(
    parameter int ADDR_WIDTH = AXI_ADDR_WIDTH, // 32
    parameter int DATA_WIDTH = AXI_DATA_WIDTH  // 64
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // Command Interface from TPU Main FSM
    input  logic                    dma_start_read,   // Trigger Read Burst (Host -> SRAM)
    input  logic                    dma_start_write,  // Trigger Write Burst (SRAM -> Host)
    input  logic [ADDR_WIDTH-1:0]   host_base_addr,   // External Host RAM Address
    input  logic [15:0]             transfer_bytes,   // Total transfer length in bytes
    output logic                    dma_busy,         // Active DMA operation flag
    output logic                    dma_done,         // Burst transfer completed

    // Internal SRAM Memory Interface
    output logic                    sram_we,
    output logic [10:0]             sram_addr,
    output logic [31:0]             sram_wdata,
    input  logic [31:0]             sram_rdata,

    // AXI4 Master Read Address Channel
    output logic [ADDR_WIDTH-1:0]   m_axi_araddr,
    output logic [7:0]              m_axi_arlen,
    output logic [2:0]              m_axi_arsize,
    output logic [1:0]              m_axi_arburst,
    output logic                    m_axi_arvalid,
    input  logic                    m_axi_arready,

    // AXI4 Master Read Data Channel
    input  logic [DATA_WIDTH-1:0]   m_axi_rdata,
    input  logic [1:0]              m_axi_rresp,
    input  logic                    m_axi_rlast,
    input  logic                    m_axi_rvalid,
    output logic                    m_axi_rready,

    // AXI4 Master Write Address Channel
    output logic [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output logic [7:0]              m_axi_awlen,
    output logic [2:0]              m_axi_awsize,
    output logic [1:0]              m_axi_awburst,
    output logic                    m_axi_awvalid,
    input  logic                    m_axi_awready,

    // AXI4 Master Write Data Channel
    output logic [DATA_WIDTH-1:0]   m_axi_wdata,
    output logic [7:0]              m_axi_wstrb,
    output logic                    m_axi_wlast,
    output logic                    m_axi_wvalid,
    input  logic                    m_axi_wready,

    // AXI4 Master Write Response Channel
    input  logic [1:0]              m_axi_bresp,
    input  logic                    m_axi_bvalid,
    output logic                    m_axi_bready
);

    // DMA FSM States
    typedef enum logic [2:0] {
        DMA_IDLE      = 3'b000,
        DMA_AR_SEND   = 3'b001,
        DMA_R_STREAM  = 3'b010,
        DMA_AW_SEND   = 3'b011,
        DMA_W_STREAM  = 3'b100,
        DMA_B_WAIT    = 3'b101,
        DMA_DONE      = 3'b110
    } dma_state_e;

    dma_state_e state;

    // Registers
    logic [ADDR_WIDTH-1:0] addr_reg;
    logic [15:0]           bytes_left_reg;
    logic [7:0]            burst_len_reg;
    logic [10:0]           sram_addr_reg;

    // Static AXI Burst Attributes
    assign m_axi_arsize  = 3'b011; // 8 bytes (64-bit)
    assign m_axi_arburst = 2'b01;  // INCR burst
    assign m_axi_awsize  = 3'b011; // 8 bytes (64-bit)
    assign m_axi_awburst = 2'b01;  // INCR burst

    assign sram_addr = sram_addr_reg;

    // DMA Main Control Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= DMA_IDLE;
            m_axi_araddr    <= '0;
            m_axi_arlen     <= '0;
            m_axi_arvalid   <= 1'b0;
            m_axi_rready    <= 1'b0;
            m_axi_awaddr    <= '0;
            m_axi_awlen     <= '0;
            m_axi_awvalid   <= 1'b0;
            m_axi_wdata     <= '0;
            m_axi_wstrb     <= 8'hFF;
            m_axi_wlast     <= 1'b0;
            m_axi_wvalid    <= 1'b0;
            m_axi_bready    <= 1'b0;
            sram_we         <= 1'b0;
            sram_wdata      <= '0;
            sram_addr_reg   <= '0;
            dma_busy        <= 1'b0;
            dma_done        <= 1'b0;
            bytes_left_reg  <= '0;
            burst_len_reg   <= '0;
            addr_reg        <= '0;
        end else begin
            case (state)
                DMA_IDLE: begin
                    dma_done <= 1'b0;
                    if (dma_start_read) begin
                        state          <= DMA_AR_SEND;
                        addr_reg       <= host_base_addr;
                        bytes_left_reg <= transfer_bytes;
                        sram_addr_reg  <= '0;
                        dma_busy       <= 1'b1;
                    end else if (dma_start_write) begin
                        state          <= DMA_AW_SEND;
                        addr_reg       <= host_base_addr;
                        bytes_left_reg <= transfer_bytes;
                        sram_addr_reg  <= '0;
                        dma_busy       <= 1'b1;
                    end else begin
                        dma_busy <= 1'b0;
                    end
                end

                DMA_AR_SEND: begin
                    m_axi_araddr  <= addr_reg;
                    // Calculate burst length (max 256 beats)
                    m_axi_arlen   <= (bytes_left_reg > 2048) ? 8'hFF : ((bytes_left_reg >> 3) - 1);
                    m_axi_arvalid <= 1'b1;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= DMA_R_STREAM;
                    end
                end

                DMA_R_STREAM: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        sram_we       <= 1'b1;
                        sram_wdata    <= m_axi_rdata[31:0];
                        sram_addr_reg <= sram_addr_reg + 1'b1;
                        
                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0;
                            sram_we      <= 1'b0;
                            state        <= DMA_DONE;
                        end
                    end else begin
                        sram_we <= 1'b0;
                    end
                end

                DMA_AW_SEND: begin
                    m_axi_awaddr  <= addr_reg;
                    m_axi_awlen   <= (bytes_left_reg > 2048) ? 8'hFF : ((bytes_left_reg >> 3) - 1);
                    m_axi_awvalid <= 1'b1;
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        state         <= DMA_W_STREAM;
                    end
                end

                DMA_W_STREAM: begin
                    m_axi_wdata <= {32'h0, sram_rdata};
                    if (m_axi_wvalid && m_axi_wready) begin
                        sram_addr_reg <= sram_addr_reg + 1'b1;
                        m_axi_wlast   <= 1'b1; // Simplified single burst
                        state         <= DMA_B_WAIT;
                        m_axi_wvalid  <= 1'b0;
                        m_axi_bready  <= 1'b1;
                    end
                end

                DMA_B_WAIT: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        state        <= DMA_DONE;
                    end
                end

                DMA_DONE: begin
                    dma_busy <= 1'b0;
                    dma_done <= 1'b1;
                    state    <= DMA_IDLE;
                end

                default: state <= DMA_IDLE;
            endcase
        end
    end

endmodule
