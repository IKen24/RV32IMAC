//=============================================================================
// Module:      imm_gen
// File:        rtl/core/imm_gen.v
// Description: RV32I immediate generator. Pure combinational.
//              Decodes opcode to select I/S/B/U/J format and sign-extends.
//              No state, no reset, no clock.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module imm_gen (
    input  wire [31:0] inst,
    output reg  [31:0] imm
);

    wire [6:0] opcode = inst[6:0];

    always @(*) begin
        case (opcode)
            // I-type: OP-IMM, LOAD, JALR, SYSTEM
            `OP_OP_IMM,
            `OP_LOAD,
            `OP_JALR,
            `OP_SYSTEM:  imm = {{20{inst[31]}}, inst[31:20]};

            // S-type: STORE
            `OP_STORE:   imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};

            // B-type: BRANCH
            `OP_BRANCH:  imm = {{19{inst[31]}}, inst[31], inst[7],
                                inst[30:25], inst[11:8], 1'b0};

            // U-type: LUI, AUIPC
            `OP_LUI,
            `OP_AUIPC:   imm = {inst[31:12], 12'b0};

            // J-type: JAL
            `OP_JAL:     imm = {{11{inst[31]}}, inst[31], inst[19:12],
                                inst[20], inst[30:21], 1'b0};

            // RV32A / MISC-MEM: no immediate
            default:     imm = 32'b0;
        endcase
    end

endmodule