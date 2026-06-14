// ============================================================================
// TPU-Lite: Systolic-Array ML Inference Accelerator SoC (Top-Level)
// File: rtl/tpu_lite_top.sv
// Description: Top-level SoC integrating AXI4-Lite CSR slave, AXI4 Master DMA,
//              double-buffered 4-bank SRAM memory subsystem, 8x8 systolic array
//              compute core, and SystemVerilog Assertions (SVA) checkers.
// ============================================================================

`timescale 1ns / 1ps

`include "axi_defines.svh"

module tpu_lite_top #(
    parameter int AXI_ADDR_W = AXI_ADDR_WIDTH, // 32
    parameter int AXI_DATA_W = AXI_DATA_WIDTH  // 64
)(
    input  logic                 clk,
    input  logic                 rst_n,

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave Interface (Host Control & Status Registers)
    // ------------------------------------------------------------------------
    input  logic [AXI_ADDR_W-1:0] s_axi_awaddr,
    input  logic                 s_axi_awvalid,
    output logic                 s_axi_awready,
    input  logic [31:0]          s_axi_wdata,
    input  logic [3:0]           s_axi_wstrb,
    input  logic                 s_axi_wvalid,
    output logic                 s_axi_wready,
    output logic [1:0]           s_axi_bresp,
    output logic                 s_axi_bvalid,
    input  logic                 s_axi_bready,

    input  logic [AXI_ADDR_W-1:0] s_axi_araddr,
    input  logic                 s_axi_arvalid,
    output logic                 s_axi_arready,
    output logic [31:0]          s_axi_rdata,
    output logic [1:0]           s_axi_rresp,
    output logic                 s_axi_rvalid,
    input  logic                 s_axi_rready,

    // ------------------------------------------------------------------------
    // AXI4 Master DMA Interface (High Bandwidth Data Streaming)
    // ------------------------------------------------------------------------
    output logic [AXI_ADDR_W-1:0] m_axi_araddr,
    output logic [7:0]           m_axi_arlen,
    output logic [2:0]           m_axi_arsize,
    output logic [1:0]           m_axi_arburst,
    output logic                 m_axi_arvalid,
    input  logic                 m_axi_arready,

    input  logic [AXI_DATA_W-1:0] m_axi_rdata,
    input  logic [1:0]           m_axi_rresp,
    input  logic                 m_axi_rlast,
    input  logic                 m_axi_rvalid,
    output logic                 m_axi_rready,

    output logic [AXI_ADDR_W-1:0] m_axi_awaddr,
    output logic [7:0]           m_axi_awlen,
    output logic [2:0]           m_axi_awsize,
    output logic [1:0]           m_axi_awburst,
    output logic                 m_axi_awvalid,
    input  logic                 m_axi_awready,

    output logic [AXI_DATA_W-1:0] m_axi_wdata,
    output logic [7:0]           m_axi_wstrb,
    output logic                 m_axi_wlast,
    output logic                 m_axi_wvalid,
    input  logic                 m_axi_wready,

    input  logic [1:0]           m_axi_bresp,
    input  logic                 m_axi_bvalid,
    output logic                 m_axi_bready,

    // Interrupt Line
    output logic                 interrupt
);

    // ------------------------------------------------------------------------
    // Internal Wires & Hardware Signals
    // ------------------------------------------------------------------------
    logic tpu_start, tpu_soft_rst, tpu_busy, tpu_done;
    logic [31:0] dim_m, dim_k, dim_n;
    logic [31:0] act_base_addr, wgt_base_addr, out_base_addr;
    logic [63:0] cycle_counter, active_counter;

    // DMA Interconnect
    logic        dma_start_read, dma_start_write, dma_busy, dma_done;
    logic [31:0] dma_host_addr;
    logic [15:0] dma_transfer_bytes;
    logic        sram_we;
    logic [10:0] sram_addr;
    logic [31:0] sram_wdata, sram_rdata;

    // Memory Subsystem Connections
    logic        tpu_act_en, tpu_wgt_en, tpu_out_we;
    logic [10:0] tpu_act_addr, tpu_wgt_addr, tpu_out_addr;
    logic signed [7:0]  tpu_act_data [0:ARRAY_SIZE-1];
    logic signed [7:0]  tpu_wgt_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    logic signed [31:0] tpu_out_data [0:ARRAY_SIZE-1];
    logic               buffer_ready;

    // Systolic Array Connections
    logic        tpu_load_wgt, tpu_clear_acc, tpu_enable, tpu_data_valid;
    logic signed [ACC_WIDTH-1:0] sys_acc_out [0:ARRAY_SIZE-1];

    // Main SoC Controller FSM State
    tpu_state_e state, next_state;

    // Combined System Reset Signal
    logic sys_rst_n;
    assign sys_rst_n = rst_n && !tpu_soft_rst;

    // Interrupt asserted on completion
    assign interrupt = tpu_done;

    // Performance Counters
    always_ff @(posedge clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            cycle_counter  <= '0;
            active_counter <= '0;
        end else begin
            cycle_counter <= cycle_counter + 1'b1;
            if (tpu_busy) begin
                active_counter <= active_counter + 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Module Instantiations
    // ------------------------------------------------------------------------

    // 1. AXI4-Lite CSR Slave File
    axi4_lite_slave #(
        .ADDR_WIDTH(AXI_ADDR_W),
        .DATA_WIDTH(32)
    ) u_csr_slave (
        .clk             (clk),
        .rst_n           (sys_rst_n),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready),
        .tpu_start       (tpu_start),
        .tpu_soft_rst    (tpu_soft_rst),
        .tpu_busy        (tpu_busy),
        .tpu_done        (tpu_done),
        .matrix_m        (dim_m),
        .matrix_k        (dim_k),
        .matrix_n        (dim_n),
        .act_base_addr   (act_base_addr),
        .wgt_base_addr   (wgt_base_addr),
        .out_base_addr   (out_base_addr),
        .cycle_count     (cycle_counter),
        .active_count    (active_counter)
    );

    // 2. AXI4 Master Burst DMA Engine
    axi4_dma_engine #(
        .ADDR_WIDTH(AXI_ADDR_W),
        .DATA_WIDTH(AXI_DATA_W)
    ) u_dma_engine (
        .clk              (clk),
        .rst_n            (sys_rst_n),
        .dma_start_read   (dma_start_read),
        .dma_start_write  (dma_start_write),
        .host_base_addr   (dma_host_addr),
        .transfer_bytes   (dma_transfer_bytes),
        .dma_busy         (dma_busy),
        .dma_done         (dma_done),
        .sram_we          (sram_we),
        .sram_addr        (sram_addr),
        .sram_wdata       (sram_wdata),
        .sram_rdata       (sram_rdata),
        .m_axi_araddr     (m_axi_araddr),
        .m_axi_arlen      (m_axi_arlen),
        .m_axi_arsize     (m_axi_arsize),
        .m_axi_arburst    (m_axi_arburst),
        .m_axi_arvalid    (m_axi_arvalid),
        .m_axi_arready    (m_axi_arready),
        .m_axi_rdata      (m_axi_rdata),
        .m_axi_rresp      (m_axi_rresp),
        .m_axi_rlast      (m_axi_rlast),
        .m_axi_rvalid     (m_axi_rvalid),
        .m_axi_rready     (m_axi_rready),
        .m_axi_awaddr     (m_axi_awaddr),
        .m_axi_awlen      (m_axi_awlen),
        .m_axi_awsize     (m_axi_awsize),
        .m_axi_awburst    (m_axi_awburst),
        .m_axi_awvalid    (m_axi_awvalid),
        .m_axi_awready    (m_axi_awready),
        .m_axi_wdata      (m_axi_wdata),
        .m_axi_wstrb      (m_axi_wstrb),
        .m_axi_wlast      (m_axi_wlast),
        .m_axi_wvalid     (m_axi_wvalid),
        .m_axi_wready     (m_axi_wready),
        .m_axi_bresp      (m_axi_bresp),
        .m_axi_bvalid     (m_axi_bvalid),
        .m_axi_bready     (m_axi_bready)
    );

    // 3. Double-Buffered 4-Bank SRAM Memory Subsystem
    memory_subsystem u_memory (
        .clk              (clk),
        .rst_n            (sys_rst_n),
        .dma_fill_complete(dma_done),
        .compute_complete (tpu_data_valid),
        .buffer_ready     (buffer_ready),
        .dma_bank_sel     (sram_addr[1:0]),
        .dma_en           (sram_we || (state == TPU_STORE_OUT)),
        .dma_we           (sram_we ? 4'b1111 : 4'b0000),
        .dma_addr         (sram_addr),
        .dma_wdata        (sram_wdata),
        .dma_rdata        (sram_rdata),
        .tpu_act_en       (tpu_act_en),
        .tpu_act_addr     (tpu_act_addr),
        .tpu_act_data     (tpu_act_data),
        .tpu_wgt_en       (tpu_wgt_en),
        .tpu_wgt_addr     (tpu_wgt_addr),
        .tpu_wgt_matrix   (tpu_wgt_matrix),
        .tpu_out_we       (tpu_out_we),
        .tpu_out_addr     (tpu_out_addr),
        .tpu_out_data     (sys_acc_out)
    );

    // 4. 8x8 Systolic Array Compute Engine
    systolic_array_8x8 #(
        .ARRAY_SIZE (ARRAY_SIZE),
        .INT8_WIDTH (INT8_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) u_systolic_core (
        .clk            (clk),
        .rst_n          (sys_rst_n),
        .load_weight    (tpu_load_wgt),
        .clear_acc      (tpu_clear_acc),
        .enable         (tpu_enable),
        .wgt_matrix     (tpu_wgt_matrix),
        .act_vector     (tpu_act_data),
        .acc_matrix_out (sys_acc_out),
        .data_valid     (tpu_data_valid)
    );

    // ------------------------------------------------------------------------
    // Main TPU SoC Master FSM
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state <= TPU_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state          = state;
        dma_start_read      = 1'b0;
        dma_start_write     = 1'b0;
        dma_host_addr       = 32'h0;
        dma_transfer_bytes  = 16'h0;
        tpu_load_wgt        = 1'b0;
        tpu_clear_acc       = 1'b0;
        tpu_enable          = 1'b0;
        tpu_act_en          = 1'b0;
        tpu_wgt_en          = 1'b0;
        tpu_out_we          = 1'b0;
        tpu_busy            = 1'b1;
        tpu_done            = 1'b0;

        case (state)
            TPU_IDLE: begin
                tpu_busy = 1'b0;
                if (tpu_start) begin
                    next_state = TPU_FETCH_WGT;
                end
            end

            TPU_FETCH_WGT: begin
                dma_start_read     = 1'b1;
                dma_host_addr      = wgt_base_addr;
                dma_transfer_bytes = 16'd64; // 8x8 INT8 weights = 64 bytes
                if (dma_done) begin
                    next_state = TPU_LOAD_WGT;
                end
            end

            TPU_LOAD_WGT: begin
                tpu_wgt_en   = 1'b1;
                tpu_load_wgt = 1'b1;
                next_state   = TPU_FETCH_ACT;
            end

            TPU_FETCH_ACT: begin
                dma_start_read     = 1'b1;
                dma_host_addr      = act_base_addr;
                dma_transfer_bytes = 16'd64; // 8x8 INT8 activations = 64 bytes
                if (dma_done) begin
                    next_state = TPU_COMPUTE;
                end
            end

            TPU_COMPUTE: begin
                tpu_enable    = 1'b1;
                tpu_act_en    = 1'b1;
                if (tpu_data_valid) begin
                    tpu_out_we = 1'b1;
                    next_state = TPU_STORE_OUT;
                end
            end

            TPU_STORE_OUT: begin
                dma_start_write    = 1'b1;
                dma_host_addr      = out_base_addr;
                dma_transfer_bytes = 16'd256; // 8x8 INT32 results = 256 bytes
                if (dma_done) begin
                    next_state = TPU_DONE;
                end
            end

            TPU_DONE: begin
                tpu_done = 1'b1;
                tpu_busy = 1'b0;
                if (!tpu_start) begin
                    next_state = TPU_IDLE;
                end
            end

            default: next_state = TPU_IDLE;
        endcase
    end

    // ------------------------------------------------------------------------
    // Bind SystemVerilog Assertions (SVA) Checkers
    // ------------------------------------------------------------------------
    `ifndef SYNTHESIS
    sva_axi4_checker #(
        .ADDR_WIDTH(AXI_ADDR_W),
        .DATA_WIDTH(AXI_DATA_W)
    ) u_sva_axi_dma (
        .clk     (clk),
        .rst_n   (sys_rst_n),
        .awaddr  (m_axi_awaddr),
        .awvalid (m_axi_awvalid),
        .awready (m_axi_awready),
        .wdata   (m_axi_wdata),
        .wvalid  (m_axi_wvalid),
        .wready  (m_axi_wready),
        .araddr  (m_axi_araddr),
        .arvalid (m_axi_arvalid),
        .arready (m_axi_arready),
        .rdata   (m_axi_rdata),
        .rvalid  (m_axi_rvalid),
        .rready  (m_axi_rready)
    );

    sva_fsm_checker u_sva_fsm (
        .clk          (clk),
        .rst_n        (sys_rst_n),
        .current_state(state),
        .tpu_start    (tpu_start),
        .dma_done     (dma_done),
        .compute_done (tpu_data_valid)
    );

    sva_fifo_checker #(
        .DEPTH(SRAM_BANK_DEPTH)
    ) u_sva_sram (
        .clk       (clk),
        .rst_n     (sys_rst_n),
        .sram_addr (sram_addr),
        .write_en  (sram_we),
        .read_en   (tpu_act_en)
    );
    `endif

endmodule
