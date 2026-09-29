//=============================================================================
// Module:      if_id
// File:        rtl/core/if_id.v
// Description: IF/ID pipeline register.
//              Carries the fetched instruction along with its own PC, the
//              precomputed next PC (pc+2 or pc+4, matching instruction
//              length), and a fetch-fault flag.
//              The instruction stored is the RVC-expanded 32-bit form, so
//              downstream stages never see compressed encodings.
//              On flush: contents become a NOP with zeroed metadata.
//              On stall: contents hold.
// Reset:       Synchronous active-low rst_n. Contents = NOP / zeros.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module if_id (
    input  wire        clk,
    input  wire        rst_n,

    // Controls
    input  wire        stall,
    input  wire        flush,

    // Inputs (from IF stage)
    input  wire [31:0] if_pc,
    input  wire [31:0] if_pc_next,
    input  wire [31:0] if_inst,
    input  wire        if_fetch_fault,

    // Outputs (to ID stage)
    output reg  [31:0] id_pc,
    output reg  [31:0] id_pc_next,
    output reg  [31:0] id_inst,
    output reg         id_fetch_fault
);

    localparam [31:0] NOP = 32'h0000_0013;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc          <= 32'b0;
            id_pc_next     <= 32'b0;
            id_inst        <= NOP;
            id_fetch_fault <= 1'b0;
        end else if (flush) begin
            id_pc          <= 32'b0;
            id_pc_next     <= 32'b0;
            id_inst        <= NOP;
            id_fetch_fault <= 1'b0;
        end else if (!stall) begin
            id_pc          <= if_pc;
            id_pc_next     <= if_pc_next;
            id_inst        <= if_inst;
            id_fetch_fault <= if_fetch_fault;
        end
    end

endmodule