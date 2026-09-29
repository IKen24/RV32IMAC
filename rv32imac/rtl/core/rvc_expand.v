//=============================================================================
// Module:      rvc_expand
// File:        rtl/core/rvc_expand.v
// Description: RVC (compressed) -> RV32I instruction expander. Combinational.
//              Input is a 32-bit fetch word. If inst_in[1:0] != 2'b11 the low
//              16 bits are a compressed instruction and are expanded. Otherwise
//              the full 32-bit word passes through with is_compressed=0.
//              Only the RV32C subset is implemented (no D/F, no RV64C).
// Reset:       None (no state).
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module rvc_expand (
    input  wire [31:0] inst_in,
    output reg  [31:0] inst_out,
    output reg         is_compressed,
    output reg         illegal
);

    //------------------------------------------------------------------
    // Extracted fields
    //------------------------------------------------------------------
    wire [2:0] f3   = inst_in[15:13];
    wire       b12  = inst_in[12];
    wire [4:0] rd   = inst_in[11:7];
    wire [4:0] rs2  = inst_in[6:2];
    wire [2:0] rdc  = inst_in[4:2];   // 3-bit compressed reg selector
    wire [2:0] rs1c = inst_in[9:7];

    wire [4:0] rd_c  = {2'b01, rdc};   // x8..x15
    wire [4:0] rs1_c = {2'b01, rs1c};
    wire [4:0] rs2_c = {2'b01, rdc};   // shares position with rd'

    //------------------------------------------------------------------
    // Immediate constructions
    //------------------------------------------------------------------
    // C.ADDI4SPN: nzuimm[9:6]=inst[10:7], [5:4]=inst[12:11], [3]=inst[5], [2]=inst[6]
    wire [11:0] imm_caddi4spn = {2'b0, inst_in[10:7], inst_in[12:11],
                                 inst_in[5], inst_in[6], 2'b0};

    // C.LW / C.SW: uimm[5:3]=inst[12:10], [2]=inst[6], [6]=inst[5]
    wire [11:0] imm_clw = {5'b0, inst_in[5], inst_in[12:10],
                           inst_in[6], 2'b0};

    // C.ADDI / C.LI / C.ANDI: 6-bit signed immediate
    wire [11:0] imm_i6 = {{6{inst_in[12]}}, inst_in[12], inst_in[6:2]};

    // C.ADDI16SP: [9]=inst[12], [8:7]=inst[4:3], [6]=inst[5], [5]=inst[2],
    //             [4]=inst[6], [3:0]=0
    wire [11:0] imm_addi16sp = {{2{inst_in[12]}}, inst_in[12],
                                inst_in[4:3], inst_in[5], inst_in[2],
                                inst_in[6], 4'b0};

    // C.LUI: 20-bit value sign-extended into bits [31:12]
    wire [31:0] imm_clui = {{14{inst_in[12]}}, inst_in[12],
                            inst_in[6:2], 12'b0};

    // C.J / C.JAL: 21-bit signed offset for JAL
    wire [20:0] imm_cj = {{9{inst_in[12]}}, inst_in[12], inst_in[8],
                          inst_in[10:9], inst_in[6], inst_in[7],
                          inst_in[2], inst_in[11], inst_in[5:3], 1'b0};

    // C.BEQZ / C.BNEZ: 13-bit signed offset for branch
    wire [12:0] imm_cb = {{5{inst_in[12]}}, inst_in[6:5], inst_in[2],
                          inst_in[11:10], inst_in[4:3], 1'b0};

    // C.LWSP: uimm[5]=inst[12], [4:2]=inst[6:4], [7:6]=inst[3:2]
    wire [11:0] imm_clwsp = {4'b0, inst_in[3:2], inst_in[12],
                             inst_in[6:4], 2'b0};

    // C.SWSP: uimm[5:2]=inst[12:9], [7:6]=inst[8:7]
    wire [11:0] imm_cswsp = {4'b0, inst_in[8:7], inst_in[12:9], 2'b0};

    // Shift amount (5 bits used in RV32)
    wire [4:0] shamt = inst_in[6:2];

    //------------------------------------------------------------------
    // Encoders
    //------------------------------------------------------------------
    function [31:0] enc_i;
        input [11:0] imm; input [4:0] rs1; input [2:0] f; input [4:0] rd; input [6:0] op;
        begin enc_i = {imm, rs1, f, rd, op}; end
    endfunction

    function [31:0] enc_s;
        input [11:0] imm; input [4:0] rs2; input [4:0] rs1; input [2:0] f; input [6:0] op;
        begin enc_s = {imm[11:5], rs2, rs1, f, imm[4:0], op}; end
    endfunction

    function [31:0] enc_b;
        input [12:0] imm; input [4:0] rs2; input [4:0] rs1; input [2:0] f; input [6:0] op;
        begin enc_b = {imm[12], imm[10:5], rs2, rs1, f, imm[4:1], imm[11], op}; end
    endfunction

    function [31:0] enc_u;
        input [31:0] imm; input [4:0] rd; input [6:0] op;
        begin enc_u = {imm[31:12], rd, op}; end
    endfunction

    function [31:0] enc_j;
        input [20:0] imm; input [4:0] rd; input [6:0] op;
        begin enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, op}; end
    endfunction

    function [31:0] enc_r;
        input [6:0] f7; input [4:0] rs2; input [4:0] rs1; input [2:0] f; input [4:0] rd; input [6:0] op;
        begin enc_r = {f7, rs2, rs1, f, rd, op}; end
    endfunction

    //------------------------------------------------------------------
    // Expansion
    //------------------------------------------------------------------
    always @(*) begin
        inst_out      = inst_in;
        is_compressed = 1'b0;
        illegal       = 1'b0;

        if (inst_in[1:0] != 2'b11) begin
            is_compressed = 1'b1;
            inst_out      = 32'h00000013;   // default: NOP

            case (inst_in[1:0])
                //=====================================================
                2'b00: begin
                    case (f3)
                        3'b000: begin
                            // C.ADDI4SPN -> addi rd', x2, nzuimm
                            if (imm_caddi4spn == 12'b0)
                                illegal = 1'b1;
                            else
                                inst_out = enc_i(imm_caddi4spn, 5'd2, 3'b000,
                                                 rd_c, `OP_OP_IMM);
                        end
                        3'b010: begin
                            // C.LW -> lw rd', offset(rs1')
                            inst_out = enc_i(imm_clw, rs1_c, `F3_LW,
                                             rd_c, `OP_LOAD);
                        end
                        3'b110: begin
                            // C.SW -> sw rs2', offset(rs1')
                            inst_out = enc_s(imm_clw, rs2_c, rs1_c, `F3_SW,
                                             `OP_STORE);
                        end
                        default: illegal = 1'b1;
                    endcase
                end

                //=====================================================
                2'b01: begin
                    case (f3)
                        3'b000: begin
                            // C.ADDI / C.NOP -> addi rd, rd, imm
                            inst_out = enc_i(imm_i6, rd, `F3_ADDI,
                                             rd, `OP_OP_IMM);
                        end
                        3'b001: begin
                            // C.JAL (RV32) -> jal x1, offset
                            inst_out = enc_j(imm_cj, 5'd1, `OP_JAL);
                        end
                        3'b010: begin
                            // C.LI -> addi rd, x0, imm
                            inst_out = enc_i(imm_i6, 5'd0, `F3_ADDI,
                                             rd, `OP_OP_IMM);
                        end
                        3'b011: begin
                            if (rd == 5'd2) begin
                                // C.ADDI16SP -> addi x2, x2, nzimm
                                if (imm_addi16sp == 12'b0)
                                    illegal = 1'b1;
                                else
                                    inst_out = enc_i(imm_addi16sp, 5'd2,
                                                     `F3_ADDI, 5'd2,
                                                     `OP_OP_IMM);
                            end else if (rd != 5'd0) begin
                                // C.LUI -> lui rd, nzimm
                                if (imm_clui[31:12] == 20'b0)
                                    illegal = 1'b1;
                                else
                                    inst_out = enc_u(imm_clui, rd, `OP_LUI);
                            end else begin
                                illegal = 1'b1;
                            end
                        end
                        3'b100: begin
                            case (inst_in[11:10])
                                2'b00: begin
                                    // C.SRLI -> srli rd', rd', shamt
                                    if (inst_in[12])
                                        illegal = 1'b1;   // RV32C: shamt[5]=0
                                    else
                                        inst_out = enc_i({7'b0, shamt},
                                                         rs1_c, `F3_SRI,
                                                         rs1_c, `OP_OP_IMM);
                                end
                                2'b01: begin
                                    // C.SRAI -> srai rd', rd', shamt
                                    if (inst_in[12])
                                        illegal = 1'b1;
                                    else
                                        inst_out = enc_i({7'b0100000, shamt},
                                                         rs1_c, `F3_SRI,
                                                         rs1_c, `OP_OP_IMM);
                                end
                                2'b10: begin
                                    // C.ANDI -> andi rd', rd', imm
                                    inst_out = enc_i(imm_i6, rs1_c, `F3_ANDI,
                                                     rs1_c, `OP_OP_IMM);
                                end
                                2'b11: begin
                                    if (inst_in[12] == 1'b0) begin
                                        // C.SUB/C.XOR/C.OR/C.AND
                                        case (inst_in[6:5])
                                            2'b00: inst_out = enc_r(7'b0100000,
                                                                    rs2_c, rs1_c,
                                                                    `F3_ADD_SUB,
                                                                    rs1_c, `OP_OP);
                                            2'b01: inst_out = enc_r(7'b0000000,
                                                                    rs2_c, rs1_c,
                                                                    `F3_XOR,
                                                                    rs1_c, `OP_OP);
                                            2'b10: inst_out = enc_r(7'b0000000,
                                                                    rs2_c, rs1_c,
                                                                    `F3_OR,
                                                                    rs1_c, `OP_OP);
                                            2'b11: inst_out = enc_r(7'b0000000,
                                                                    rs2_c, rs1_c,
                                                                    `F3_AND,
                                                                    rs1_c, `OP_OP);
                                        endcase
                                    end else begin
                                        illegal = 1'b1;   // RV64C
                                    end
                                end
                            endcase
                        end
                        3'b101: begin
                            // C.J -> jal x0, offset
                            inst_out = enc_j(imm_cj, 5'd0, `OP_JAL);
                        end
                        3'b110: begin
                            // C.BEQZ -> beq rs1', x0, offset
                            inst_out = enc_b(imm_cb, 5'd0, rs1_c,
                                             `F3_BEQ, `OP_BRANCH);
                        end
                        3'b111: begin
                            // C.BNEZ -> bne rs1', x0, offset
                            inst_out = enc_b(imm_cb, 5'd0, rs1_c,
                                             `F3_BNE, `OP_BRANCH);
                        end
                        default: illegal = 1'b1;
                    endcase
                end

                //=====================================================
                2'b10: begin
                    case (f3)
                        3'b000: begin
                            // C.SLLI -> slli rd, rd, shamt
                            if (inst_in[12])
                                illegal = 1'b1;
                            else
                                inst_out = enc_i({7'b0, shamt}, rd,
                                                 `F3_SLLI, rd, `OP_OP_IMM);
                        end
                        3'b010: begin
                            // C.LWSP -> lw rd, offset(x2); rd != 0
                            if (rd == 5'd0)
                                illegal = 1'b1;
                            else
                                inst_out = enc_i(imm_clwsp, 5'd2, `F3_LW,
                                                 rd, `OP_LOAD);
                        end
                        3'b100: begin
                            if (inst_in[12] == 1'b0) begin
                                if (rs2 == 5'd0) begin
                                    // C.JR -> jalr x0, 0(rs1); rs1 != 0
                                    if (rd == 5'd0)
                                        illegal = 1'b1;
                                    else
                                        inst_out = enc_i(12'b0, rd,
                                                         `F3_JALR, 5'd0,
                                                         `OP_JALR);
                                end else begin
                                    // C.MV -> add rd, x0, rs2
                                    inst_out = enc_r(7'b0000000, rs2, 5'd0,
                                                     `F3_ADD_SUB, rd, `OP_OP);
                                end
                            end else begin
                                if (rd == 5'd0 && rs2 == 5'd0) begin
                                    // C.EBREAK
                                    inst_out = 32'h0010_0073;
                                end else if (rs2 == 5'd0) begin
                                    // C.JALR -> jalr x1, 0(rs1)
                                    inst_out = enc_i(12'b0, rd, `F3_JALR,
                                                     5'd1, `OP_JALR);
                                end else begin
                                    // C.ADD -> add rd, rd, rs2
                                    inst_out = enc_r(7'b0000000, rs2, rd,
                                                     `F3_ADD_SUB, rd, `OP_OP);
                                end
                            end
                        end
                        3'b110: begin
                            // C.SWSP -> sw rs2, offset(x2)
                            inst_out = enc_s(imm_cswsp, rs2, 5'd2, `F3_SW,
                                             `OP_STORE);
                        end
                        default: illegal = 1'b1;
                    endcase
                end

                default: illegal = 1'b1;
            endcase
        end
    end

endmodule