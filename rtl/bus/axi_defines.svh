// ============================================================================
// TPU-Lite Accelerator SoC - AXI4 Interface & System Definitions Header
// File: rtl/bus/axi_defines.svh
// Description: Defines global constants, CSR register maps, data widths,
//              and struct definitions for TPU-Lite.
// ============================================================================

`ifndef AXI_DEFINES_SVH
`define AXI_DEFINES_SVH

// System Parameters
parameter int ARRAY_SIZE      = 8;      // 8x8 Systolic Array
parameter int INT8_WIDTH      = 8;      // Data width for weights and activations
parameter int ACC_WIDTH       = 32;     // Data width for accumulated results
parameter int AXI_ADDR_WIDTH  = 32;     // AXI4 Address bus width
parameter int AXI_DATA_WIDTH  = 64;     // AXI4 Data bus width
parameter int AXI_STRB_WIDTH  = AXI_DATA_WIDTH / 8;

// Memory Parameters
parameter int SRAM_NUM_BANKS   = 4;      // 4-bank interleaved memory
parameter int SRAM_BANK_DEPTH = 2048;   // 2K entries per bank (32-bit width)
parameter int SRAM_ADDR_WIDTH = 11;     // log2(SRAM_BANK_DEPTH)

// CSR Register Map (Offset from AXI4-Lite Base Address)
localparam logic [7:0] CSR_CTRL_REG        = 8'h00; // [0]: Start, [1]: Soft Reset, [2]: Int Enable
localparam logic [7:0] CSR_STATUS_REG      = 8'h04; // [0]: Busy, [1]: Done, [2]: Error
localparam logic [7:0] CSR_DIM_M_REG       = 8'h08; // Matrix M dimension (Rows)
localparam logic [7:0] CSR_DIM_K_REG       = 8'h0C; // Matrix K dimension (Inner)
localparam logic [7:0] CSR_DIM_N_REG       = 8'h10; // Matrix N dimension (Cols)
localparam logic [7:0] CSR_ACT_BASE_ADDR   = 8'h14; // Activation Base Address in Host RAM
localparam logic [7:0] CSR_WGT_BASE_ADDR   = 8'h18; // Weight Base Address in Host RAM
localparam logic [7:0] CSR_OUT_BASE_ADDR   = 8'h1C; // Output Base Address in Host RAM
localparam logic [7:0] CSR_PERF_CYCLE_LO   = 8'h20; // Lower 32-bit execution cycle counter
localparam logic [7:0] CSR_PERF_CYCLE_HI   = 8'h24; // Upper 32-bit execution cycle counter
localparam logic [7:0] CSR_PERF_ACTIVE_LO  = 8'h28; // Active compute cycles counter

// FSM State Enums
typedef enum logic [2:0] {
    TPU_IDLE       = 3'b000,
    TPU_FETCH_WGT  = 3'b001,
    TPU_LOAD_WGT   = 3'b010,
    TPU_FETCH_ACT  = 3'b011,
    TPU_COMPUTE    = 3'b100,
    TPU_STORE_OUT  = 3'b101,
    TPU_DONE       = 3'b110,
    TPU_ERROR      = 3'b111
} tpu_state_e;

`endif // AXI_DEFINES_SVH
