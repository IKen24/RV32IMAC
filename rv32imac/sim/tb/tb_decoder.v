//=============================================================================
// Module:      tb_decoder
// File:        sim/tb/tb_decoder.v
// Description: Self-checking TB for decoder.
//              Packs all decoder outputs into a 44-bit vector and compares
//              against a per-instruction expected vector built from a
//              small set of defaults + field overrides.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_decoder;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 10000;

    reg clk;
    reg rst_n;
    integer cycles;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycles <= 0;
        else        cycles <= cycles + 1;
    end

    //------------------------------------------------------------------
    // DUT
    //------------------------------------------------------------------
    reg  [31:0] inst;

    wire [4:0]  rs1_addr, rs2_addr, rd_addr;
    wire [11:0] csr_addr;
    wire        use_rs1, use_rs2, reg_write;
    wire [2:0]  imm_sel;
    wire [4:0]  alu_op;
    wire        alu_src_a, alu_src_b;
    wire        mem_read, mem_write;
    wire [1:0]  mem_size;
    wire        mem_unsigned;
    wire [1:0]  wb_sel;
    wire        branch, jump;
    wire        csr_we;
    wire [1:0]  csr_op;
    wire        csr_imm;
    wire [3:0]  sys_op;
    wire        muldiv_sel;
    wire [3:0]  muldiv_op;
    wire        atomic_sel;
    wire [4:0]  amo_op;
    wire        is_lr, is_sc, illegal;

    decoder dut (
        .inst         (inst),
        .rs1_addr     (rs1_addr),
        .rs2_addr     (rs2_addr),
        .rd_addr      (rd_addr),
        .csr_addr     (csr_addr),
        .use_rs1      (use_rs1),
        .use_rs2      (use_rs2),
        .reg_write    (reg_write),
        .imm_sel      (imm_sel),
        .alu_op       (alu_op),
        .alu_src_a    (alu_src_a),
        .alu_src_b    (alu_src_b),
        .mem_read     (mem_read),
        .mem_write    (mem_write),
        .mem_size     (mem_size),
        .mem_unsigned (mem_unsigned),
        .wb_sel       (wb_sel),
        .branch       (branch),
        .jump         (jump),
        .csr_we       (csr_we),
        .csr_op       (csr_op),
        .csr_imm      (csr_imm),
        .sys_op       (sys_op),
        .muldiv_sel   (muldiv_sel),
        .muldiv_op    (muldiv_op),
        .atomic_sel   (atomic_sel),
        .amo_op       (amo_op),
        .is_lr        (is_lr),
        .is_sc        (is_sc),
        .illegal      (illegal)
    );

    //------------------------------------------------------------------
    // Pack DUT outputs into a 44-bit vector.
    // Bit layout (LSB first):
    //   [0]      reg_write
    //   [1]      use_rs1
    //   [2]      use_rs2
    //   [3]      alu_src_a
    //   [4]      alu_src_b
    //   [5]      mem_read
    //   [6]      mem_write
    //   [7]      mem_unsigned
    //   [8]      branch
    //   [9]      jump
    //   [10]     csr_we
    //   [11]     csr_imm
    //   [12]     muldiv_sel
    //   [13]     atomic_sel
    //   [14]     is_lr
    //   [15]     is_sc
    //   [16]     illegal
    //   [21:17]  alu_op
    //   [24:22]  imm_sel
    //   [26:25]  mem_size
    //   [28:27]  wb_sel
    //   [30:29]  csr_op
    //   [34:31]  sys_op
    //   [38:35]  muldiv_op
    //   [43:39]  amo_op
    //------------------------------------------------------------------
    wire [43:0] got;
    assign got = {
        amo_op, muldiv_op, sys_op, csr_op, wb_sel, mem_size,
        imm_sel, alu_op, illegal, is_sc, is_lr, atomic_sel,
        muldiv_sel, csr_imm, csr_we, jump, branch, mem_unsigned,
        mem_write, mem_read, alu_src_b, alu_src_a,
        use_rs2, use_rs1, reg_write
    };

    localparam B_REG_WRITE  = 0;
    localparam B_USE_RS1    = 1;
    localparam B_USE_RS2    = 2;
    localparam B_ALU_SRC_A  = 3;
    localparam B_ALU_SRC_B  = 4;
    localparam B_MEM_READ   = 5;
    localparam B_MEM_WRITE  = 6;
    localparam B_MEM_UNS    = 7;
    localparam B_BRANCH     = 8;
    localparam B_JUMP       = 9;
    localparam B_CSR_WE     = 10;
    localparam B_CSR_IMM    = 11;
    localparam B_MULDIV_SEL = 12;
    localparam B_ATOMIC_SEL = 13;
    localparam B_IS_LR      = 14;
    localparam B_IS_SC      = 15;
    localparam B_ILLEGAL    = 16;

    localparam LO_ALU_OP    = 17;
    localparam LO_IMM_SEL   = 22;
    localparam LO_MEM_SIZE  = 25;
    localparam LO_WB_SEL    = 27;
    localparam LO_CSR_OP    = 29;
    localparam LO_SYS_OP    = 31;
    localparam LO_MULDIV_OP = 35;
    localparam LO_AMO_OP    = 39;

    //------------------------------------------------------------------
    // Bookkeeping
    //------------------------------------------------------------------
    integer    errors;
    integer    tests_run;
    reg [43:0] exp;

    //------------------------------------------------------------------
    // Set expected vector to decoder defaults
    //------------------------------------------------------------------
    task set_default;
        begin
            exp = 44'b0;
            exp[LO_MEM_SIZE +: 2] = 2'b10;   // word
        end
    endtask

    //------------------------------------------------------------------
    // Compare helper
    //------------------------------------------------------------------
    task check;
        input [255:0] label;
        begin
            tests_run = tests_run + 1;
            if (got !== exp) begin
                $display("FAIL [%0s]", label);
                $display("  got = %h", got);
                $display("  exp = %h", exp);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Drive + settle
    //------------------------------------------------------------------
    task drive;
        input [31:0] i;
        begin
            @(negedge clk);
            inst = i;
            #1;
        end
    endtask

    //------------------------------------------------------------------
    // Instruction encoders for the TB
    //------------------------------------------------------------------
    function [31:0] r_type;
        input [6:0] f7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] f3;
        input [4:0] rd;
        input [6:0] opc;
        begin
            r_type = {f7, rs2, rs1, f3, rd, opc};
        end
    endfunction

    function [31:0] i_type;
        input [11:0] imm12;
        input [4:0]  rs1;
        input [2:0]  f3;
        input [4:0]  rd;
        input [6:0]  opc;
        begin
            i_type = {imm12, rs1, f3, rd, opc};
        end
    endfunction

    function [31:0] s_type;
        input [11:0] imm12;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [2:0]  f3;
        input [6:0]  opc;
        begin
            s_type = {imm12[11:5], rs2, rs1, f3, imm12[4:0], opc};
        end
    endfunction

    function [31:0] b_type;
        input [12:0] imm13;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [2:0]  f3;
        input [6:0]  opc;
        begin
            b_type = {imm13[12], imm13[10:5], rs2, rs1, f3,
                      imm13[4:1], imm13[11], opc};
        end
    endfunction

    function [31:0] u_type;
        input [31:0] imm;
        input [4:0]  rd;
        input [6:0]  opc;
        begin
            u_type = {imm[31:12], rd, opc};
        end
    endfunction

    function [31:0] j_type;
        input [20:0] imm21;
        input [4:0]  rd;
        input [6:0]  opc;
        begin
            j_type = {imm21[20], imm21[10:1], imm21[11],
                      imm21[19:12], rd, opc};
        end
    endfunction

    // 32-bit atomic encoder: funct5 | aq | rl | rs2 | rs1 | funct3 | rd | op
    function [31:0] a_type;
        input [4:0] f5;
        input       aq;
        input       rl;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] f3;
        input [4:0] rd;
        input [6:0] opc;
        begin
            a_type = {f5, aq, rl, rs2, rs1, f3, rd, opc};
        end
    endfunction

    //------------------------------------------------------------------
    // Directed tests
    //------------------------------------------------------------------
    task run_directed;
        begin
            // ---------------- LUI ----------------
            drive(u_type(32'hDEAD_B000, 5'd7, `OP_LUI));
            set_default;
            exp[B_REG_WRITE] = 1'b1;
            exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_IMM_SEL +: 3] = `IMM_U;
            exp[LO_ALU_OP  +: 5] = `ALU_PASS_B;
            check("LUI");

            // ---------------- AUIPC ----------------
            drive(u_type(32'h0000_1000, 5'd7, `OP_AUIPC));
            set_default;
            exp[B_REG_WRITE] = 1'b1;
            exp[B_ALU_SRC_A] = 1'b1;
            exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_IMM_SEL +: 3] = `IMM_U;
            check("AUIPC");

            // ---------------- JAL ----------------
            drive(j_type(21'h000004, 5'd7, `OP_JAL));
            set_default;
            exp[B_REG_WRITE] = 1'b1;
            exp[B_JUMP]      = 1'b1;
            exp[B_ALU_SRC_A] = 1'b1;
            exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_IMM_SEL +: 3] = `IMM_J;
            exp[LO_WB_SEL  +: 2] = `WB_PC4;
            check("JAL");

            // ---------------- JALR ----------------
            drive(i_type(12'h008, 5'd3, 3'b000, 5'd7, `OP_JALR));
            set_default;
            exp[B_REG_WRITE] = 1'b1;
            exp[B_USE_RS1]   = 1'b1;
            exp[B_JUMP]      = 1'b1;
            exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_WB_SEL +: 2] = `WB_PC4;
            check("JALR");

            // ---------------- Branches ----------------
            drive(b_type(13'h0004, 5'd2, 5'd1, `F3_BEQ, `OP_BRANCH));
            set_default;
            exp[B_USE_RS1]   = 1'b1;
            exp[B_USE_RS2]   = 1'b1;
            exp[B_BRANCH]    = 1'b1;
            exp[B_ALU_SRC_A] = 1'b1;
            exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_IMM_SEL +: 3] = `IMM_B;
            check("BEQ");

            drive(b_type(13'h0004, 5'd2, 5'd1, `F3_BNE, `OP_BRANCH));
            set_default;
            exp[B_USE_RS1] = 1'b1;  exp[B_USE_RS2] = 1'b1;
            exp[B_BRANCH]  = 1'b1;  exp[B_ALU_SRC_A] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_IMM_SEL +: 3] = `IMM_B;
            check("BNE");

            drive(b_type(13'h0004, 5'd2, 5'd1, `F3_BLT, `OP_BRANCH));
            set_default;
            exp[B_USE_RS1] = 1'b1;  exp[B_USE_RS2] = 1'b1;
            exp[B_BRANCH]  = 1'b1;  exp[B_ALU_SRC_A] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_IMM_SEL +: 3] = `IMM_B;
            check("BLT");

            drive(b_type(13'h0004, 5'd2, 5'd1, `F3_BGE, `OP_BRANCH));
            set_default;
            exp[B_USE_RS1] = 1'b1;  exp[B_USE_RS2] = 1'b1;
            exp[B_BRANCH]  = 1'b1;  exp[B_ALU_SRC_A] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_IMM_SEL +: 3] = `IMM_B;
            check("BGE");

            drive(b_type(13'h0004, 5'd2, 5'd1, `F3_BLTU, `OP_BRANCH));
            set_default;
            exp[B_USE_RS1] = 1'b1;  exp[B_USE_RS2] = 1'b1;
            exp[B_BRANCH]  = 1'b1;  exp[B_ALU_SRC_A] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_IMM_SEL +: 3] = `IMM_B;
            check("BLTU");

            drive(b_type(13'h0004, 5'd2, 5'd1, `F3_BGEU, `OP_BRANCH));
            set_default;
            exp[B_USE_RS1] = 1'b1;  exp[B_USE_RS2] = 1'b1;
            exp[B_BRANCH]  = 1'b1;  exp[B_ALU_SRC_A] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_IMM_SEL +: 3] = `IMM_B;
            check("BGEU");

            // ---------------- Loads ----------------
            drive(i_type(12'h004, 5'd1, `F3_LB, 5'd7, `OP_LOAD));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1;
            exp[B_MEM_READ]  = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_MEM_SIZE +: 2] = 2'b00;
            exp[LO_WB_SEL   +: 2] = `WB_MEM;
            check("LB");

            drive(i_type(12'h004, 5'd1, `F3_LH, 5'd7, `OP_LOAD));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1;
            exp[B_MEM_READ]  = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_MEM_SIZE +: 2] = 2'b01;
            exp[LO_WB_SEL   +: 2] = `WB_MEM;
            check("LH");

            drive(i_type(12'h004, 5'd1, `F3_LW, 5'd7, `OP_LOAD));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1;
            exp[B_MEM_READ]  = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_MEM_SIZE +: 2] = 2'b10;
            exp[LO_WB_SEL   +: 2] = `WB_MEM;
            check("LW");

            drive(i_type(12'h004, 5'd1, `F3_LBU, 5'd7, `OP_LOAD));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1;
            exp[B_MEM_READ]  = 1'b1; exp[B_MEM_UNS] = 1'b1;
            exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_MEM_SIZE +: 2] = 2'b00;
            exp[LO_WB_SEL   +: 2] = `WB_MEM;
            check("LBU");

            drive(i_type(12'h004, 5'd1, `F3_LHU, 5'd7, `OP_LOAD));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1;
            exp[B_MEM_READ]  = 1'b1; exp[B_MEM_UNS] = 1'b1;
            exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_MEM_SIZE +: 2] = 2'b01;
            exp[LO_WB_SEL   +: 2] = `WB_MEM;
            check("LHU");

            // ---------------- Stores ----------------
            drive(s_type(12'h004, 5'd2, 5'd1, `F3_SB, `OP_STORE));
            set_default;
            exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_MEM_WRITE] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_IMM_SEL +: 3] = `IMM_S;
            exp[LO_MEM_SIZE +: 2] = 2'b00;
            check("SB");

            drive(s_type(12'h004, 5'd2, 5'd1, `F3_SH, `OP_STORE));
            set_default;
            exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_MEM_WRITE] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_IMM_SEL +: 3] = `IMM_S;
            exp[LO_MEM_SIZE +: 2] = 2'b01;
            check("SH");

            drive(s_type(12'h004, 5'd2, 5'd1, `F3_SW, `OP_STORE));
            set_default;
            exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_MEM_WRITE] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_IMM_SEL +: 3] = `IMM_S;
            exp[LO_MEM_SIZE +: 2] = 2'b10;
            check("SW");

            // ---------------- OP-IMM ----------------
            drive(i_type(12'h001, 5'd1, `F3_ADDI, 5'd7, `OP_OP_IMM));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            check("ADDI");

            drive(i_type(12'h001, 5'd1, `F3_SLTI, 5'd7, `OP_OP_IMM));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_SLT;
            check("SLTI");

            drive(i_type(12'h001, 5'd1, `F3_SLTIU, 5'd7, `OP_OP_IMM));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_SLTU;
            check("SLTIU");

            drive(i_type(12'h001, 5'd1, `F3_XORI, 5'd7, `OP_OP_IMM));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_XOR;
            check("XORI");

            drive(i_type(12'h001, 5'd1, `F3_ORI, 5'd7, `OP_OP_IMM));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_OR;
            check("ORI");

            drive(i_type(12'h001, 5'd1, `F3_ANDI, 5'd7, `OP_OP_IMM));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_AND;
            check("ANDI");

            drive(i_type(12'h001, 5'd1, `F3_SLLI, 5'd7, `OP_OP_IMM));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_SLL;
            check("SLLI");

            drive(i_type(12'h001, 5'd1, `F3_SRI, 5'd7, `OP_OP_IMM));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_SRL;
            check("SRLI");

            drive({7'b0100000, 5'd1, 5'd1, `F3_SRI, 5'd7, `OP_OP_IMM});
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_ALU_SRC_B] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_SRA;
            check("SRAI");

            // ---------------- OP (register-register) ----------------
            drive(r_type(7'b0000000, 5'd2, 5'd1, `F3_ADD_SUB, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            check("ADD");

            drive(r_type(7'b0100000, 5'd2, 5'd1, `F3_ADD_SUB, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_SUB;
            check("SUB");

            drive(r_type(7'b0000000, 5'd2, 5'd1, `F3_SLL, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_SLL;
            check("SLL");

            drive(r_type(7'b0000000, 5'd2, 5'd1, `F3_SLT, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_SLT;
            check("SLT");

            drive(r_type(7'b0000000, 5'd2, 5'd1, `F3_SLTU, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_SLTU;
            check("SLTU");

            drive(r_type(7'b0000000, 5'd2, 5'd1, `F3_XOR, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_XOR;
            check("XOR");

            drive(r_type(7'b0000000, 5'd2, 5'd1, `F3_SR, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_SRL;
            check("SRL");

            drive(r_type(7'b0100000, 5'd2, 5'd1, `F3_SR, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_SRA;
            check("SRA");

            drive(r_type(7'b0000000, 5'd2, 5'd1, `F3_OR, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_OR;
            check("OR");

            drive(r_type(7'b0000000, 5'd2, 5'd1, `F3_AND, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[LO_ALU_OP +: 5] = `ALU_AND;
            check("AND");

            // ---------------- M extension ----------------
            drive(r_type(`FUNCT7_M, 5'd2, 5'd1, `F3_MUL, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_MULDIV_SEL] = 1'b1;
            exp[LO_MULDIV_OP +: 4] = `MD_MUL;
            check("MUL");

            drive(r_type(`FUNCT7_M, 5'd2, 5'd1, `F3_MULH, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_MULDIV_SEL] = 1'b1;
            exp[LO_MULDIV_OP +: 4] = `MD_MULH;
            check("MULH");

            drive(r_type(`FUNCT7_M, 5'd2, 5'd1, `F3_MULHSU, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_MULDIV_SEL] = 1'b1;
            exp[LO_MULDIV_OP +: 4] = `MD_MULHSU;
            check("MULHSU");

            drive(r_type(`FUNCT7_M, 5'd2, 5'd1, `F3_MULHU, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_MULDIV_SEL] = 1'b1;
            exp[LO_MULDIV_OP +: 4] = `MD_MULHU;
            check("MULHU");

            drive(r_type(`FUNCT7_M, 5'd2, 5'd1, `F3_DIV, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_MULDIV_SEL] = 1'b1;
            exp[LO_MULDIV_OP +: 4] = `MD_DIV;
            check("DIV");

            drive(r_type(`FUNCT7_M, 5'd2, 5'd1, `F3_DIVU, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_MULDIV_SEL] = 1'b1;
            exp[LO_MULDIV_OP +: 4] = `MD_DIVU;
            check("DIVU");

            drive(r_type(`FUNCT7_M, 5'd2, 5'd1, `F3_REM, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_MULDIV_SEL] = 1'b1;
            exp[LO_MULDIV_OP +: 4] = `MD_REM;
            check("REM");

            drive(r_type(`FUNCT7_M, 5'd2, 5'd1, `F3_REMU, 5'd7, `OP_OP));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_MULDIV_SEL] = 1'b1;
            exp[LO_MULDIV_OP +: 4] = `MD_REMU;
            check("REMU");

            // ---------------- MISC-MEM ----------------
            drive(32'h0FF0000F);   // FENCE
            set_default;
            exp[LO_SYS_OP +: 4] = `SYS_FENCE;
            check("FENCE");

            drive(32'h0000100F);   // FENCE.I
            set_default;
            exp[LO_SYS_OP +: 4] = `SYS_FENCE_I;
            check("FENCE.I");

            // ---------------- SYSTEM / Privileged ----------------
            drive(32'h00000073);
            set_default;
            exp[LO_SYS_OP +: 4] = `SYS_ECALL;
            check("ECALL");

            drive(32'h00100073);
            set_default;
            exp[LO_SYS_OP +: 4] = `SYS_EBREAK;
            check("EBREAK");

            drive(32'h30200073);
            set_default;
            exp[LO_SYS_OP +: 4] = `SYS_MRET;
            check("MRET");

            drive(32'h10200073);
            set_default;
            exp[LO_SYS_OP +: 4] = `SYS_SRET;
            check("SRET");

            drive(32'h10500073);
            set_default;
            exp[LO_SYS_OP +: 4] = `SYS_WFI;
            check("WFI");

            drive(32'h12000073);
            set_default;
            exp[LO_SYS_OP +: 4] = `SYS_SFENCE;
            check("SFENCE.VMA");

            // ---------------- SYSTEM / CSR ----------------
            drive(i_type(`CSR_MSTATUS, 5'd3, `F3_CSRRW, 5'd7, `OP_SYSTEM));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1;
            exp[B_CSR_WE]    = 1'b1;
            exp[LO_CSR_OP +: 2] = `CSR_OP_RW;
            exp[LO_WB_SEL +: 2] = `WB_CSR;
            check("CSRRW mstatus");

            drive(i_type(`CSR_MSTATUS, 5'd3, `F3_CSRRS, 5'd7, `OP_SYSTEM));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1;
            exp[B_CSR_WE]    = 1'b1;
            exp[LO_CSR_OP +: 2] = `CSR_OP_RS;
            exp[LO_WB_SEL +: 2] = `WB_CSR;
            check("CSRRS mstatus");

            drive(i_type(`CSR_MSTATUS, 5'd3, `F3_CSRRC, 5'd7, `OP_SYSTEM));
            set_default;
            exp[B_REG_WRITE] = 1'b1; exp[B_USE_RS1] = 1'b1;
            exp[B_CSR_WE]    = 1'b1;
            exp[LO_CSR_OP +: 2] = `CSR_OP_RC;
            exp[LO_WB_SEL +: 2] = `WB_CSR;
            check("CSRRC mstatus");

            drive(i_type(`CSR_MTVEC, 5'd5, `F3_CSRRWI, 5'd7, `OP_SYSTEM));
            set_default;
            exp[B_REG_WRITE] = 1'b1;
            exp[B_CSR_WE]    = 1'b1;
            exp[B_CSR_IMM]   = 1'b1;
            exp[LO_CSR_OP +: 2] = `CSR_OP_RW;
            exp[LO_WB_SEL +: 2] = `WB_CSR;
            check("CSRRWI mtvec");

            drive(i_type(`CSR_MTVEC, 5'd5, `F3_CSRRSI, 5'd7, `OP_SYSTEM));
            set_default;
            exp[B_REG_WRITE] = 1'b1;
            exp[B_CSR_WE]    = 1'b1;
            exp[B_CSR_IMM]   = 1'b1;
            exp[LO_CSR_OP +: 2] = `CSR_OP_RS;
            exp[LO_WB_SEL +: 2] = `WB_CSR;
            check("CSRRSI mtvec");

            drive(i_type(`CSR_MTVEC, 5'd5, `F3_CSRRCI, 5'd7, `OP_SYSTEM));
            set_default;
            exp[B_REG_WRITE] = 1'b1;
            exp[B_CSR_WE]    = 1'b1;
            exp[B_CSR_IMM]   = 1'b1;
            exp[LO_CSR_OP +: 2] = `CSR_OP_RC;
            exp[LO_WB_SEL +: 2] = `WB_CSR;
            check("CSRRCI mtvec");

            // ---------------- Atomics ----------------
            drive(a_type(`A_AMOADD, 1'b0, 1'b0, 5'd2, 5'd1,
                         3'b010, 5'd7, `OP_ATOMIC));
            set_default;
            exp[B_REG_WRITE]  = 1'b1;
            exp[B_USE_RS1]    = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_ATOMIC_SEL] = 1'b1;
            exp[B_MEM_READ]   = 1'b1; exp[B_MEM_WRITE] = 1'b1;
            exp[B_ALU_SRC_B]  = 1'b1;
            exp[LO_WB_SEL +: 2] = `WB_MEM;
            exp[LO_AMO_OP +: 5] = `A_AMOADD;
            check("AMOADD.W");

            drive(a_type(`A_AMOSWAP, 1'b0, 1'b0, 5'd2, 5'd1,
                         3'b010, 5'd7, `OP_ATOMIC));
            set_default;
            exp[B_REG_WRITE]  = 1'b1;
            exp[B_USE_RS1]    = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_ATOMIC_SEL] = 1'b1;
            exp[B_MEM_READ]   = 1'b1; exp[B_MEM_WRITE] = 1'b1;
            exp[B_ALU_SRC_B]  = 1'b1;
            exp[LO_WB_SEL +: 2] = `WB_MEM;
            exp[LO_AMO_OP +: 5] = `A_AMOSWAP;
            check("AMOSWAP.W");

            drive(a_type(`FUNCT5_LR, 1'b0, 1'b0, 5'd0, 5'd1,
                         3'b010, 5'd7, `OP_ATOMIC));
            set_default;
            exp[B_REG_WRITE]  = 1'b1;
            exp[B_USE_RS1]    = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_ATOMIC_SEL] = 1'b1;
            exp[B_MEM_READ]   = 1'b1; exp[B_MEM_WRITE] = 1'b1;
            exp[B_ALU_SRC_B]  = 1'b1;
            exp[B_IS_LR]      = 1'b1;
            exp[LO_WB_SEL +: 2] = `WB_MEM;
            exp[LO_AMO_OP +: 5] = `FUNCT5_LR;
            check("LR.W");

            drive(a_type(`FUNCT5_SC, 1'b0, 1'b0, 5'd2, 5'd1,
                         3'b010, 5'd7, `OP_ATOMIC));
            set_default;
            exp[B_REG_WRITE]  = 1'b1;
            exp[B_USE_RS1]    = 1'b1; exp[B_USE_RS2] = 1'b1;
            exp[B_ATOMIC_SEL] = 1'b1;
            exp[B_MEM_READ]   = 1'b1; exp[B_MEM_WRITE] = 1'b1;
            exp[B_ALU_SRC_B]  = 1'b1;
            exp[B_IS_SC]      = 1'b1;
            exp[LO_WB_SEL +: 2] = `WB_MEM;
            exp[LO_AMO_OP +: 5] = `FUNCT5_SC;
            check("SC.W");

            // ---------------- Illegal ----------------
            drive(32'h00000000);
            set_default;
            exp[B_ILLEGAL] = 1'b1;
            check("ILLEGAL opcode 0");

            drive(32'hFFFFFFFF);
            set_default;
            exp[B_ILLEGAL] = 1'b1;
            check("ILLEGAL all-ones");

            // illegal funct7 on OP
            drive(r_type(7'b1111111, 5'd2, 5'd1, `F3_ADD_SUB, 5'd7, `OP_OP));
            set_default;
            exp[B_ILLEGAL] = 1'b1;
            check("ILLEGAL funct7");

            // ATOMIC with wrong funct3
            drive(a_type(`A_AMOADD, 1'b0, 1'b0, 5'd2, 5'd1,
                         3'b011, 5'd7, `OP_ATOMIC));
            set_default;
            exp[B_ILLEGAL] = 1'b1;
            check("ILLEGAL atomic funct3");
        end
    endtask

    //------------------------------------------------------------------
    // Address wire-through check
    //------------------------------------------------------------------
    task run_addr_checks;
        begin
            drive(32'hDEAD_BEEF);
            #1;
            tests_run = tests_run + 1;
            if (rs1_addr !== 5'd27) begin
                $display("FAIL rs1_addr: got %0d exp 27", rs1_addr);
                errors = errors + 1;
            end
            if (rs2_addr !== 5'd10) begin
                $display("FAIL rs2_addr: got %0d exp 10", rs2_addr);
                errors = errors + 1;
            end
            if (rd_addr  !== 5'd29) begin
                $display("FAIL rd_addr : got %0d exp 29", rd_addr);
                errors = errors + 1;
            end
            if (csr_addr !== 12'hDEA) begin
                $display("FAIL csr_addr: got %h exp DEA", csr_addr);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_decoder);

        errors    = 0;
        tests_run = 0;
        inst      = 32'b0;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        run_directed;
        run_addr_checks;

        $display("---------------------------------------------");
        $display("tb_decoder: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_decoder");
        else
            $display("TEST FAILED: tb_decoder %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_decoder timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire