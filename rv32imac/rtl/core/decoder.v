//=============================================================================
// Module:      decoder
// File:        rtl/core/decoder.v
// Description: RV32IMAC instruction decoder. Pure combinational.
//              Produces all pipeline control signals from a 32-bit
//              (already RVC-expanded) instruction word.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module decoder (
    input  wire [31:0] inst,

    // Register/CSR addresses (wire-through)
    output wire [4:0]  rs1_addr,
    output wire [4:0]  rs2_addr,
    output wire [4:0]  rd_addr,
    output wire [11:0] csr_addr,

    // Register usage
    output reg         use_rs1,
    output reg         use_rs2,
    output reg         reg_write,

    // Immediate format
    output reg  [2:0]  imm_sel,

    // ALU control
    output reg  [4:0]  alu_op,
    output reg         alu_src_a,
    output reg         alu_src_b,

    // Memory
    output reg         mem_read,
    output reg         mem_write,
    output reg  [1:0]  mem_size,
    output reg         mem_unsigned,

    // Writeback source
    output reg  [1:0]  wb_sel,

    // Branch / jump
    output reg         branch,
    output reg         jump,

    // CSR
    output reg         csr_we,
    output reg  [1:0]  csr_op,
    output reg         csr_imm,

    // System
    output reg  [3:0]  sys_op,

    // Muldiv
    output reg         muldiv_sel,
    output reg  [3:0]  muldiv_op,

    // Atomics
    output reg         atomic_sel,
    output reg  [4:0]  amo_op,
    output reg         is_lr,
    output reg         is_sc,

    // Illegal
    output reg         illegal
);

    wire [6:0]  opcode  = inst[6:0];
    wire [2:0]  funct3  = inst[14:12];
    wire [6:0]  funct7  = inst[31:25];
    wire [4:0]  funct5  = inst[31:27];
    wire [11:0] funct12 = inst[31:20];

    assign rs1_addr = inst[19:15];
    assign rs2_addr = inst[24:20];
    assign rd_addr  = inst[11:7];
    assign csr_addr = inst[31:20];

    always @(*) begin
        // ---- defaults ----
        use_rs1      = 1'b0;
        use_rs2      = 1'b0;
        reg_write    = 1'b0;
        imm_sel      = `IMM_I;
        alu_op       = `ALU_ADD;
        alu_src_a    = 1'b0;
        alu_src_b    = 1'b0;
        mem_read     = 1'b0;
        mem_write    = 1'b0;
        mem_size     = 2'b10;   // word
        mem_unsigned = 1'b0;
        wb_sel       = `WB_ALU;
        branch       = 1'b0;
        jump         = 1'b0;
        csr_we       = 1'b0;
        csr_op       = `CSR_OP_RW;
        csr_imm      = 1'b0;
        sys_op       = `SYS_NONE;
        muldiv_sel   = 1'b0;
        muldiv_op    = `MD_NONE;
        atomic_sel   = 1'b0;
        amo_op       = 5'b0;
        is_lr        = 1'b0;
        is_sc        = 1'b0;
        illegal      = 1'b0;

        case (opcode)
            //-------------------------------------------------------------
            `OP_LUI: begin
                reg_write = 1'b1;
                imm_sel   = `IMM_U;
                alu_op    = `ALU_PASS_B;
                alu_src_b = 1'b1;
            end

            `OP_AUIPC: begin
                reg_write = 1'b1;
                imm_sel   = `IMM_U;
                alu_op    = `ALU_ADD;
                alu_src_a = 1'b1;
                alu_src_b = 1'b1;
            end

            `OP_JAL: begin
                reg_write = 1'b1;
                jump      = 1'b1;
                imm_sel   = `IMM_J;
                wb_sel    = `WB_PC4;
                alu_op    = `ALU_ADD;
                alu_src_a = 1'b1;
                alu_src_b = 1'b1;
            end

            `OP_JALR: begin
                reg_write = 1'b1;
                use_rs1   = 1'b1;
                jump      = 1'b1;
                imm_sel   = `IMM_I;
                wb_sel    = `WB_PC4;
                alu_op    = `ALU_ADD;
                alu_src_b = 1'b1;
            end

            `OP_BRANCH: begin
                use_rs1   = 1'b1;
                use_rs2   = 1'b1;
                branch    = 1'b1;
                imm_sel   = `IMM_B;
                alu_op    = `ALU_ADD;   // target = pc + imm
                alu_src_a = 1'b1;
                alu_src_b = 1'b1;
                case (funct3)
                    `F3_BEQ, `F3_BNE, `F3_BLT, `F3_BGE,
                    `F3_BLTU, `F3_BGEU: ;
                    default: illegal = 1'b1;
                endcase
            end

            `OP_LOAD: begin
                reg_write = 1'b1;
                use_rs1   = 1'b1;
                mem_read  = 1'b1;
                imm_sel   = `IMM_I;
                alu_op    = `ALU_ADD;
                alu_src_b = 1'b1;
                wb_sel    = `WB_MEM;
                case (funct3)
                    `F3_LB:  begin mem_size = 2'b00; mem_unsigned = 1'b0; end
                    `F3_LH:  begin mem_size = 2'b01; mem_unsigned = 1'b0; end
                    `F3_LW:  begin mem_size = 2'b10; mem_unsigned = 1'b0; end
                    `F3_LBU: begin mem_size = 2'b00; mem_unsigned = 1'b1; end
                    `F3_LHU: begin mem_size = 2'b01; mem_unsigned = 1'b1; end
                    default: illegal = 1'b1;
                endcase
            end

            `OP_STORE: begin
                use_rs1   = 1'b1;
                use_rs2   = 1'b1;
                mem_write = 1'b1;
                imm_sel   = `IMM_S;
                alu_op    = `ALU_ADD;
                alu_src_b = 1'b1;
                case (funct3)
                    `F3_SB: mem_size = 2'b00;
                    `F3_SH: mem_size = 2'b01;
                    `F3_SW: mem_size = 2'b10;
                    default: illegal = 1'b1;
                endcase
            end

            `OP_OP_IMM: begin
                reg_write = 1'b1;
                use_rs1   = 1'b1;
                imm_sel   = `IMM_I;
                alu_src_b = 1'b1;
                case (funct3)
                    `F3_ADDI:  alu_op = `ALU_ADD;
                    `F3_SLTI:  alu_op = `ALU_SLT;
                    `F3_SLTIU: alu_op = `ALU_SLTU;
                    `F3_XORI:  alu_op = `ALU_XOR;
                    `F3_ORI:   alu_op = `ALU_OR;
                    `F3_ANDI:  alu_op = `ALU_AND;
                    `F3_SLLI: begin
                        alu_op = `ALU_SLL;
                        if (funct7 != 7'b0000000) illegal = 1'b1;
                    end
                    `F3_SRI: begin
                        if (funct7 == 7'b0000000)      alu_op = `ALU_SRL;
                        else if (funct7 == 7'b0100000) alu_op = `ALU_SRA;
                        else                           illegal = 1'b1;
                    end
                    default: illegal = 1'b1;
                endcase
            end

            `OP_OP: begin
                reg_write = 1'b1;
                use_rs1   = 1'b1;
                use_rs2   = 1'b1;
                case (funct7)
                    7'b0000000: begin
                        case (funct3)
                            `F3_ADD_SUB: alu_op = `ALU_ADD;
                            `F3_SLL:     alu_op = `ALU_SLL;
                            `F3_SLT:     alu_op = `ALU_SLT;
                            `F3_SLTU:    alu_op = `ALU_SLTU;
                            `F3_XOR:     alu_op = `ALU_XOR;
                            `F3_SR:      alu_op = `ALU_SRL;
                            `F3_OR:      alu_op = `ALU_OR;
                            `F3_AND:     alu_op = `ALU_AND;
                            default: illegal = 1'b1;
                        endcase
                    end
                    7'b0100000: begin
                        case (funct3)
                            `F3_ADD_SUB: alu_op = `ALU_SUB;
                            `F3_SR:      alu_op = `ALU_SRA;
                            default: illegal = 1'b1;
                        endcase
                    end
                    `FUNCT7_M: begin
                        muldiv_sel = 1'b1;
                        case (funct3)
                            `F3_MUL:    muldiv_op = `MD_MUL;
                            `F3_MULH:   muldiv_op = `MD_MULH;
                            `F3_MULHSU: muldiv_op = `MD_MULHSU;
                            `F3_MULHU:  muldiv_op = `MD_MULHU;
                            `F3_DIV:    muldiv_op = `MD_DIV;
                            `F3_DIVU:   muldiv_op = `MD_DIVU;
                            `F3_REM:    muldiv_op = `MD_REM;
                            `F3_REMU:   muldiv_op = `MD_REMU;
                            default: illegal = 1'b1;
                        endcase
                    end
                    default: illegal = 1'b1;
                endcase
            end

            `OP_MISC_MEM: begin
                case (funct3)
                    3'b000: sys_op = `SYS_FENCE;
                    3'b001: sys_op = `SYS_FENCE_I;
                    default: illegal = 1'b1;
                endcase
            end

            `OP_SYSTEM: begin
                case (funct3)
                    `F3_PRIV: begin
                        if      (funct12 == `FUNCT12_ECALL)  sys_op = `SYS_ECALL;
                        else if (funct12 == `FUNCT12_EBREAK) sys_op = `SYS_EBREAK;
                        else if (funct12 == `FUNCT12_MRET)   sys_op = `SYS_MRET;
                        else if (funct12 == `FUNCT12_SRET)   sys_op = `SYS_SRET;
                        else if (funct12 == `FUNCT12_WFI)    sys_op = `SYS_WFI;
                        else if (funct7  == 7'b0001001)      sys_op = `SYS_SFENCE;
                        else illegal = 1'b1;
                    end
                    `F3_CSRRW, `F3_CSRRS, `F3_CSRRC: begin
                        reg_write = 1'b1;
                        use_rs1   = 1'b1;
                        csr_we    = 1'b1;
                        wb_sel    = `WB_CSR;
                        case (funct3)
                            `F3_CSRRW: csr_op = `CSR_OP_RW;
                            `F3_CSRRS: csr_op = `CSR_OP_RS;
                            `F3_CSRRC: csr_op = `CSR_OP_RC;
                        endcase
                    end
                    `F3_CSRRWI, `F3_CSRRSI, `F3_CSRRCI: begin
                        reg_write = 1'b1;
                        csr_we    = 1'b1;
                        csr_imm   = 1'b1;
                        wb_sel    = `WB_CSR;
                        case (funct3)
                            `F3_CSRRWI: csr_op = `CSR_OP_RW;
                            `F3_CSRRSI: csr_op = `CSR_OP_RS;
                            `F3_CSRRCI: csr_op = `CSR_OP_RC;
                        endcase
                    end
                    default: illegal = 1'b1;
                endcase
            end

            `OP_ATOMIC: begin
                // RV32A: only funct3=010 (.W) is defined
                if (funct3 != 3'b010) begin
                    illegal = 1'b1;
                end else begin
                    reg_write  = 1'b1;
                    use_rs1    = 1'b1;
                    use_rs2    = 1'b1;
                    atomic_sel = 1'b1;
                    mem_read   = 1'b1;
                    mem_write  = 1'b1;
                    wb_sel     = `WB_MEM;
                    amo_op     = funct5;
                    alu_op     = `ALU_ADD;
                    alu_src_b  = 1'b1;   // imm = 0 (imm_gen returns 0 for ATOMIC)
                    case (funct5)
                        `FUNCT5_LR: is_lr = 1'b1;
                        `FUNCT5_SC: is_sc = 1'b1;
                        default:    ;      // regular AMO
                    endcase
                end
            end

            default: illegal = 1'b1;
        endcase

        // Illegal instructions must have no side effects visible to the
        // pipeline. Trap unit overrides PC; everything else stays quiet,
        // including register-read dependencies seen by hazard/forward units.
        if (illegal) begin
            reg_write  = 1'b0;
            use_rs1    = 1'b0;
            use_rs2    = 1'b0;
            mem_read   = 1'b0;
            mem_write  = 1'b0;
            csr_we     = 1'b0;
            csr_imm    = 1'b0;
            alu_src_a  = 1'b0;
            alu_src_b  = 1'b0;
            branch     = 1'b0;
            jump       = 1'b0;
            muldiv_sel = 1'b0;
            atomic_sel = 1'b0;
            is_lr      = 1'b0;
            is_sc      = 1'b0;
            sys_op     = 4'b0;
        end
    end

endmodule