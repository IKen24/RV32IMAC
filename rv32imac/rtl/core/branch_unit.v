//=============================================================================
// Module:      branch_unit
// File:        rtl/core/branch_unit.v
// Description: RV32I branch condition resolver. Pure combinational.
//              Maps branch funct3 + comparison flags to a single take line.
//              Comparators live in the ALU; this module only decides.
// Latency:     Combinational (0 cycles)
// Reset:       None (no state)
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module branch_unit (
    input  wire [2:0] funct3,
    input  wire       zero,
    input  wire       lt_s,
    input  wire       lt_u,
    output reg        take
);

    always @(*) begin
        case (funct3)
            `F3_BEQ:  take =  zero;
            `F3_BNE:  take = ~zero;
            `F3_BLT:  take =  lt_s;
            `F3_BGE:  take = ~lt_s;
            `F3_BLTU: take =  lt_u;
            `F3_BGEU: take = ~lt_u;
            default:  take = 1'b0;   // illegal funct3; decoder flags it
        endcase
    end

endmodule