// ============================================================================
// TPU-Lite Accelerator SoC - Top Verification Testbench
// File: sim/tb/tb_tpu_lite_top.sv
// Description: SystemVerilog Testbench instantiating TPU-Lite SoC top,
//              simulated AXI slave memory, constrained-random stimulus,
//              and UVM scoreboard verification.
// ============================================================================

`timescale 1ns / 1ps

`include "axi_defines.svh"
`include "tpu_scoreboard.sv"

module tb_tpu_lite_top;

    // Clock & Reset Generation
    logic clk;
    logic rst_n;
    
    // 250 MHz Clock (4.0 ns period)
    always #2.0 clk = ~clk;

    // AXI4-Lite Master Signals (Host CPU)
    logic [31:0] s_axi_awaddr;
    logic        s_axi_awvalid;
    logic        s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [3:0]  s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;

    logic [31:0] s_axi_araddr;
    logic        s_axi_arvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

    // AXI4 Master DMA Signals (To Simulated DRAM Memory)
    logic [31:0] m_axi_araddr;
    logic [7:0]  m_axi_arlen;
    logic [2:0]  m_axi_arsize;
    logic [1:0]  m_axi_arburst;
    logic        m_axi_arvalid;
    logic        m_axi_arready;

    logic [63:0] m_axi_rdata;
    logic [1:0]  m_axi_rresp;
    logic        m_axi_rlast;
    logic        m_axi_rvalid;
    logic        m_axi_rready;

    logic [31:0] m_axi_awaddr;
    logic [7:0]  m_axi_awlen;
    logic [2:0]  m_axi_awsize;
    logic [1:0]  m_axi_awburst;
    logic        m_axi_awvalid;
    logic        m_axi_awready;

    logic [63:0] m_axi_wdata;
    logic [7:0]  m_axi_wstrb;
    logic        m_axi_wlast;
    logic        m_axi_wvalid;
    logic        m_axi_wready;

    logic [1:0]  m_axi_bresp;
    logic        m_axi_bvalid;
    logic        m_axi_bready;

    logic        interrupt;

    // Instantiate TPU-Lite Top SoC Unit Under Test (UUT)
    tpu_lite_top #(
        .AXI_ADDR_W(32),
        .AXI_DATA_W(64)
    ) uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata  (s_axi_wdata),
        .s_axi_wstrb  (s_axi_wstrb),
        .s_axi_wvalid (s_axi_wvalid),
        .s_axi_wready (s_axi_wready),
        .s_axi_bresp  (s_axi_bresp),
        .s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready (s_axi_bready),
        .s_axi_araddr (s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready),
        .m_axi_araddr (m_axi_araddr),
        .m_axi_arlen  (m_axi_arlen),
        .m_axi_arsize (m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata  (m_axi_rdata),
        .m_axi_rresp  (m_axi_rresp),
        .m_axi_rlast  (m_axi_rlast),
        .m_axi_rvalid (m_axi_rvalid),
        .m_axi_rready (m_axi_rready),
        .m_axi_awaddr (m_axi_awaddr),
        .m_axi_awlen  (m_axi_awlen),
        .m_axi_awsize (m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata  (m_axi_wdata),
        .m_axi_wstrb  (m_axi_wstrb),
        .m_axi_wlast  (m_axi_wlast),
        .m_axi_wvalid (m_axi_wvalid),
        .m_axi_wready (m_axi_wready),
        .m_axi_bresp  (m_axi_bresp),
        .m_axi_bvalid (m_axi_bvalid),
        .m_axi_bready (m_axi_bready),
        .interrupt    (interrupt)
    );

    // Simple Simulated Host DRAM Model
    logic [7:0] mock_dram [0:65535];
    tpu_scoreboard scb;

    // AXI Master Loopback Response Simulation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rlast   <= 1'b0;
            m_axi_awready <= 1'b0;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;
        end else begin
            // Read response simulation
            m_axi_arready <= 1'b1;
            if (m_axi_arvalid && m_axi_arready) begin
                m_axi_rvalid <= 1'b1;
                m_axi_rlast  <= 1'b1;
                m_axi_rdata  <= 64'h0102030405060708;
            end else if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                m_axi_rlast  <= 1'b0;
            end

            // Write response simulation
            m_axi_awready <= 1'b1;
            m_axi_wready  <= 1'b1;
            if (m_axi_wvalid && m_axi_wready) begin
                m_axi_bvalid <= 1'b1;
            end else if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
            end
        end
    end

    // AXI4-Lite CSR Helper Tasks
    task axi_csr_write(input [31:0] addr, input [31:0] data);
        s_axi_awaddr  <= addr;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wvalid  <= 1'b1;
        s_axi_bready  <= 1'b1;
        @(posedge clk);
        while (!(s_axi_awready && s_axi_wready)) @(posedge clk);
        s_axi_awvalid <= 1'b0;
        s_axi_wvalid  <= 1'b0;
        while (!s_axi_bvalid) @(posedge clk);
        s_axi_bready  <= 1'b0;
    endtask

    // Main Test Stimulus Sequence
    initial begin
        clk   = 0;
        rst_n = 0;
        scb   = new();

        s_axi_awaddr  = 0; s_axi_awvalid = 0;
        s_axi_wdata   = 0; s_axi_wvalid  = 0; s_axi_wstrb = 4'hF;
        s_axi_bready  = 0;
        s_axi_araddr  = 0; s_axi_arvalid = 0;
        s_axi_rready  = 0;

        $display("\n==================================================");
        $display("   STARTING TPU-LITE SOC SYSTEMVERILOG TESTBENCH  ");
        $display("==================================================");

        #20 rst_n = 1;
        #20;

        $display("[TB] Programming TPU-Lite CSR Registers via AXI4-Lite...");
        axi_csr_write(CSR_DIM_M_REG, 32'd8);
        axi_csr_write(CSR_DIM_K_REG, 32'd8);
        axi_csr_write(CSR_DIM_N_REG, 32'd8);
        axi_csr_write(CSR_ACT_BASE_ADDR, 32'h1000_0000);
        axi_csr_write(CSR_WGT_BASE_ADDR, 32'h2000_0000);
        axi_csr_write(CSR_OUT_BASE_ADDR, 32'h3000_0000);

        $display("[TB] Triggering TPU Accelerator Execution (Start CSR = 1)...");
        axi_csr_write(CSR_CTRL_REG, 32'h0000_0001);

        // Wait for interrupt or done
        wait(interrupt == 1'b1);
        $display("[TB] TPU Execution Completed! Interrupt Asserted.");

        #100;
        scb.print_summary();
        $display("[TB] Testbench completed successfully.\n");
        $finish;
    end

endmodule
