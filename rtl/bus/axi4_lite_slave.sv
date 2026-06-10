// ============================================================================
// TPU-Lite Accelerator SoC - AXI4-Lite CSR Register Interface
// File: rtl/bus/axi4_lite_slave.sv
// Description: Standard AXI4-Lite slave interface for host CSR configuration
//              and status monitoring.
// ============================================================================

`timescale 1ns / 1ps

`include "axi_defines.svh"

module axi4_lite_slave #(
    parameter int ADDR_WIDTH = AXI_ADDR_WIDTH,
    parameter int DATA_WIDTH = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // AXI4-Lite Write Address Channel
    input  logic [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  logic                    s_axi_awvalid,
    output logic                    s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  logic [DATA_WIDTH-1:0]   s_axi_wdata,
    input  logic [3:0]              s_axi_wstrb,
    input  logic                    s_axi_wvalid,
    output logic                    s_axi_wready,

    // AXI4-Lite Write Response Channel
    output logic [1:0]              s_axi_bresp,
    output logic                    s_axi_bvalid,
    input  logic                    s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  logic [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  logic                    s_axi_arvalid,
    output logic                    s_axi_arready,

    // AXI4-Lite Read Data Channel
    output logic [DATA_WIDTH-1:0]   s_axi_rdata,
    output logic [1:0]              s_axi_rresp,
    output logic                    s_axi_rvalid,
    input  logic                    s_axi_rready,

    // Hardware Register Interfaces to TPU Top FSM
    output logic                    tpu_start,
    output logic                    tpu_soft_rst,
    input  logic                    tpu_busy,
    input  logic                    tpu_done,
    output logic [31:0]             matrix_m,
    output logic [31:0]             matrix_k,
    output logic [31:0]             matrix_n,
    output logic [31:0]             act_base_addr,
    output logic [31:0]             wgt_base_addr,
    output logic [31:0]             out_base_addr,
    input  logic [63:0]             cycle_count,
    input  logic [63:0]             active_count
);

    // Internal CSR Registers
    logic [31:0] reg_ctrl;
    logic [31:0] reg_status;
    logic [31:0] reg_dim_m;
    logic [31:0] reg_dim_k;
    logic [31:0] reg_dim_n;
    logic [31:0] reg_act_base;
    logic [31:0] reg_wgt_base;
    logic [31:0] reg_out_base;

    // AXI Handshake Registers
    logic awready_reg, wready_reg, bvalid_reg, arready_reg, rvalid_reg;
    logic [ADDR_WIDTH-1:0] axi_awaddr_latched;
    logic [ADDR_WIDTH-1:0] axi_araddr_latched;
    logic [DATA_WIDTH-1:0] rdata_reg;

    assign s_axi_awready = awready_reg;
    assign s_axi_wready  = wready_reg;
    assign s_axi_bresp   = 2'b00; // OKAY
    assign s_axi_bvalid  = bvalid_reg;
    assign s_axi_arready = arready_reg;
    assign s_axi_rdata   = rdata_reg;
    assign s_axi_rresp   = 2'b00; // OKAY
    assign s_axi_rvalid  = rvalid_reg;

    // Control assignments
    assign tpu_start     = reg_ctrl[0];
    assign tpu_soft_rst  = reg_ctrl[1];
    assign matrix_m      = reg_dim_m;
    assign matrix_k      = reg_dim_k;
    assign matrix_n      = reg_dim_n;
    assign act_base_addr = reg_act_base;
    assign wgt_base_addr = reg_wgt_base;
    assign out_base_addr = reg_out_base;

    // Status register composition
    always_comb begin
        reg_status      = 32'h0;
        reg_status[0]   = tpu_busy;
        reg_status[1]   = tpu_done;
    end

    // AXI4-Lite Write Channel FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awready_reg <= 1'b0;
            wready_reg  <= 1'b0;
            bvalid_reg  <= 1'b0;
            axi_awaddr_latched <= '0;
            reg_ctrl      <= '0;
            reg_dim_m     <= 32'd8;
            reg_dim_k     <= 32'd8;
            reg_dim_n     <= 32'd8;
            reg_act_base  <= 32'h1000_0000;
            reg_wgt_base  <= 32'h2000_0000;
            reg_out_base  <= 32'h3000_0000;
        end else begin
            // Clear auto-start pulse
            if (reg_ctrl[0]) reg_ctrl[0] <= 1'b0;

            if (~awready_reg && s_axi_awvalid && s_axi_wvalid) begin
                awready_reg <= 1'b1;
                wready_reg  <= 1'b1;
                axi_awaddr_latched <= s_axi_awaddr;
            end else begin
                awready_reg <= 1'b0;
                wready_reg  <= 1'b0;
            end

            if (awready_reg && s_axi_awvalid && wready_reg && s_axi_wvalid) begin
                bvalid_reg <= 1'b1;
                case (axi_awaddr_latched[7:0])
                    CSR_CTRL_REG:      reg_ctrl     <= s_axi_wdata;
                    CSR_DIM_M_REG:     reg_dim_m    <= s_axi_wdata;
                    CSR_DIM_K_REG:     reg_dim_k    <= s_axi_wdata;
                    CSR_DIM_N_REG:     reg_dim_n    <= s_axi_wdata;
                    CSR_ACT_BASE_ADDR: reg_act_base <= s_axi_wdata;
                    CSR_WGT_BASE_ADDR: reg_wgt_base <= s_axi_wdata;
                    CSR_OUT_BASE_ADDR: reg_out_base <= s_axi_wdata;
                    default: ;
                endcase
            end else if (bvalid_reg && s_axi_bready) begin
                bvalid_reg <= 1'b0;
            end
        end
    end

    // AXI4-Lite Read Channel FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arready_reg <= 1'b0;
            rvalid_reg  <= 1'b0;
            rdata_reg   <= '0;
            axi_araddr_latched <= '0;
        end else begin
            if (~arready_reg && s_axi_arvalid) begin
                arready_reg <= 1'b1;
                axi_araddr_latched <= s_axi_araddr;
            end else begin
                arready_reg <= 1'b0;
            end

            if (arready_reg && s_axi_arvalid && ~rvalid_reg) begin
                rvalid_reg <= 1'b1;
                case (axi_araddr_latched[7:0])
                    CSR_CTRL_REG:       rdata_reg <= reg_ctrl;
                    CSR_STATUS_REG:     rdata_reg <= reg_status;
                    CSR_DIM_M_REG:      rdata_reg <= reg_dim_m;
                    CSR_DIM_K_REG:      rdata_reg <= reg_dim_k;
                    CSR_DIM_N_REG:      rdata_reg <= reg_dim_n;
                    CSR_ACT_BASE_ADDR:  rdata_reg <= reg_act_base;
                    CSR_WGT_BASE_ADDR:  rdata_reg <= reg_wgt_base;
                    CSR_OUT_BASE_ADDR:  rdata_reg <= reg_out_base;
                    CSR_PERF_CYCLE_LO:  rdata_reg <= cycle_count[31:0];
                    CSR_PERF_CYCLE_HI:  rdata_reg <= cycle_count[63:32];
                    CSR_PERF_ACTIVE_LO: rdata_reg <= active_count[31:0];
                    default:            rdata_reg <= 32'hDEAD_BEEF;
                endcase
            end else if (rvalid_reg && s_axi_rready) begin
                rvalid_reg <= 1'b0;
            end
        end
    end

endmodule
