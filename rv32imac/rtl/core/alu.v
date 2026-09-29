//=============================================================================
// Module:      alu
// File:        rtl/core/alu.v
// Description: 32-bit RISC-V integer ALU. Pure combinational.
//              Op encodings come from riscv_defs.vh (macro form).
// Latency:     Combinational (0 cycles)
// Reset:       None (no state)
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module alu (
    input  wire [31:0] op_a,
    input  wire [31:0] op_b,
    input  wire [4:0]  alu_op,
    output reg  [31:0] result,
    output wire        zero,
    output wire        lt_s,
    output wire        lt_u
);

    wire [31:0] sub_result = op_a - op_b;

    assign lt_s = ($signed(op_a) < $signed(op_b));
    assign lt_u = (op_a < op_b);

    always @(*) begin
        case (alu_op)
            `ALU_ADD:    result = op_a + op_b;
            `ALU_SUB:    result = sub_result;
            `ALU_SLL:    result = op_a << op_b[4:0];
            `ALU_SLT:    result = {31'b0, lt_s};
            `ALU_SLTU:   result = {31'b0, lt_u};
            `ALU_XOR:    result = op_a ^ op_b;
            `ALU_SRL:    result = op_a >> op_b[4:0];
            `ALU_SRA:    result = $signed(op_a) >>> op_b[4:0];
            `ALU_OR:     result = op_a | op_b;
            `ALU_AND:    result = op_a & op_b;
            `ALU_PASS_A: result = op_a;
            `ALU_PASS_B: result = op_b;
            default:     result = 32'b0;
        endcase
    end

    assign zero = (result == 32'b0);

endmodule