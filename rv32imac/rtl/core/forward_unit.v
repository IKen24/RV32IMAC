//=============================================================================
// Module:      forward_unit
// File:        rtl/core/forward_unit.v
// Description: Operand forwarding control for the EX stage. Combinational.
//              Compares EX source addresses against the two in-flight
//              producers (MEM and WB). Emits a 2-bit select per operand.
//              Priority: MEM over WB (MEM holds the younger instruction).
//              x0 is excluded on both producer and consumer side.
//              Load-use stalls are handled by hazard_unit; this module
//              keeps asserting FW_MEM during the stall, which is harmless
//              because the stalled EX doesn't commit.
// Reset:       None (no state).
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module forward_unit (
    // EX stage consumer
    input  wire [4:0] ex_rs1_addr,
    input  wire [4:0] ex_rs2_addr,
    input  wire       ex_use_rs1,
    input  wire       ex_use_rs2,

    // MEM stage producer (EX/MEM register)
    input  wire       mem_reg_write,
    input  wire [4:0] mem_rd_addr,

    // WB stage producer (MEM/WB register)
    input  wire       wb_reg_write,
    input  wire [4:0] wb_rd_addr,

    // Selects
    output wire [1:0] forward_a_sel,
    output wire [1:0] forward_b_sel
);

    //------------------------------------------------------------------
    // rs1 (A) match detection
    //------------------------------------------------------------------
    wire a_mem_hit = ex_use_rs1 && mem_reg_write
                     && (mem_rd_addr != 5'd0)
                     && (mem_rd_addr == ex_rs1_addr);
    wire a_wb_hit  = ex_use_rs1 && wb_reg_write
                     && (wb_rd_addr != 5'd0)
                     && (wb_rd_addr == ex_rs1_addr);

    //------------------------------------------------------------------
    // rs2 (B) match detection
    //------------------------------------------------------------------
    wire b_mem_hit = ex_use_rs2 && mem_reg_write
                     && (mem_rd_addr != 5'd0)
                     && (mem_rd_addr == ex_rs2_addr);
    wire b_wb_hit  = ex_use_rs2 && wb_reg_write
                     && (wb_rd_addr != 5'd0)
                     && (wb_rd_addr == ex_rs2_addr);

    //------------------------------------------------------------------
    // Priority: MEM (younger) over WB (older)
    //------------------------------------------------------------------
    assign forward_a_sel = a_mem_hit ? `FW_MEM :
                           a_wb_hit  ? `FW_WB  : `FW_NONE;

    assign forward_b_sel = b_mem_hit ? `FW_MEM :
                           b_wb_hit  ? `FW_WB  : `FW_NONE;

endmodule