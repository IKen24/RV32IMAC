//=============================================================================
// Module:      tb_id_stage
// File:        sim/tb/tb_id_stage.v
// Description: Integration test for id_stage.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_id_stage;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 200000;
    localparam [31:0]  SEED       = 32'h1D1D_1234;

    reg clk, rst_n;
    integer cycles;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycles <= 0;
        else        cycles <= cycles + 1;
    end

    reg  [31:0] if_pc, if_pc_next, if_inst;
    reg         if_fetch_fault;
    reg         wb_reg_write;
    reg  [4:0]  wb_rd_addr;
    reg  [31:0] wb_rd_data;

    wire [31:0] id_pc, id_pc_next, id_rs1_data, id_rs2_data;
    wire [31:0] id_imm, id_csr_wdata;
    wire [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    wire [11:0] id_csr_addr;
    wire [4:0]  id_alu_op;
    wire        id_alu_src_a, id_alu_src_b;
    wire [2:0]  id_branch_funct3;
    wire        id_branch, id_jump;
    wire        id_use_rs1, id_use_rs2;
    wire        id_mem_read, id_mem_write, id_mem_unsigned;
    wire [1:0]  id_mem_size, id_wb_sel;
    wire        id_reg_write, id_csr_we, id_csr_imm;
    wire [1:0]  id_csr_op;
    wire [3:0]  id_sys_op;
    wire        id_muldiv_sel;
    wire [3:0]  id_muldiv_op;
    wire        id_atomic_sel;
    wire [4:0]  id_amo_op;
    wire        id_is_lr, id_is_sc;
    wire        id_illegal, id_fetch_fault;

    integer errors, tests_run, rng_seed, rng_dummy;

    id_stage dut (
        .clk(clk), .rst_n(rst_n),
        .if_pc(if_pc), .if_pc_next(if_pc_next),
        .if_inst(if_inst), .if_fetch_fault(if_fetch_fault),
        .wb_reg_write(wb_reg_write), .wb_rd_addr(wb_rd_addr), .wb_rd_data(wb_rd_data),
        .id_pc(id_pc), .id_pc_next(id_pc_next),
        .id_rs1_data(id_rs1_data), .id_rs2_data(id_rs2_data),
        .id_imm(id_imm), .id_csr_wdata(id_csr_wdata),
        .id_rs1_addr(id_rs1_addr), .id_rs2_addr(id_rs2_addr),
        .id_rd_addr(id_rd_addr), .id_csr_addr(id_csr_addr),
        .id_alu_op(id_alu_op), .id_alu_src_a(id_alu_src_a), .id_alu_src_b(id_alu_src_b),
        .id_branch_funct3(id_branch_funct3),
        .id_branch(id_branch), .id_jump(id_jump),
        .id_use_rs1(id_use_rs1), .id_use_rs2(id_use_rs2),
        .id_mem_read(id_mem_read), .id_mem_write(id_mem_write),
        .id_mem_size(id_mem_size), .id_mem_unsigned(id_mem_unsigned),
        .id_wb_sel(id_wb_sel), .id_reg_write(id_reg_write),
        .id_csr_we(id_csr_we), .id_csr_op(id_csr_op), .id_csr_imm(id_csr_imm),
        .id_sys_op(id_sys_op),
        .id_muldiv_sel(id_muldiv_sel), .id_muldiv_op(id_muldiv_op),
        .id_atomic_sel(id_atomic_sel), .id_amo_op(id_amo_op),
        .id_is_lr(id_is_lr), .id_is_sc(id_is_sc),
        .id_illegal(id_illegal), .id_fetch_fault(id_fetch_fault)
    );

    wire [263:0] got;
    assign got = {
        id_fetch_fault, id_illegal, id_is_sc, id_is_lr, id_atomic_sel,
        id_muldiv_sel, id_csr_imm, id_csr_we, id_reg_write,
        id_mem_unsigned, id_mem_write, id_mem_read,
        id_use_rs2, id_use_rs1, id_jump, id_branch,
        id_alu_src_b, id_alu_src_a,
        id_amo_op, id_muldiv_op, id_sys_op, id_branch_funct3,
        id_csr_op, id_wb_sel, id_mem_size, id_alu_op,
        id_csr_addr, id_rd_addr, id_rs2_addr, id_rs1_addr,
        id_csr_wdata, id_imm, id_rs2_data, id_rs1_data,
        id_pc_next, id_pc
    };

    reg [263:0] exp;

    localparam B_PC          = 0,   B_PC_NEXT     = 32,
               B_RS1_DATA    = 64,  B_RS2_DATA    = 96,
               B_IMM         = 128, B_CSR_WDATA   = 160,
               B_RS1_ADDR    = 192, B_RS2_ADDR    = 197,
               B_RD_ADDR     = 202, B_CSR_ADDR    = 207,
               B_ALU_OP      = 219, B_MEM_SIZE    = 224,
               B_WB_SEL      = 226, B_CSR_OP      = 228,
               B_BRANCH_F3   = 230, B_SYS_OP      = 233,
               B_MULDIV_OP   = 237, B_AMO_OP      = 241,
               B_ALU_SRC_A   = 246, B_ALU_SRC_B   = 247,
               B_BRANCH      = 248, B_JUMP        = 249,
               B_USE_RS1     = 250, B_USE_RS2     = 251,
               B_MEM_READ    = 252, B_MEM_WRITE   = 253,
               B_MEM_UNS     = 254, B_REG_WRITE   = 255,
               B_CSR_WE      = 256, B_CSR_IMM     = 257,
               B_MULDIV_SEL  = 258, B_ATOMIC_SEL  = 259,
               B_IS_LR       = 260, B_IS_SC       = 261,
               B_ILLEGAL     = 262, B_FETCH_FAULT = 263;

    function [31:0] r_type;
        input [6:0] f7; input [4:0] rs2; input [4:0] rs1;
        input [2:0] f3; input [4:0] rd; input [6:0] opc;
        begin r_type = {f7, rs2, rs1, f3, rd, opc}; end
    endfunction
    function [31:0] i_type;
        input [11:0] imm; input [4:0] rs1; input [2:0] f3;
        input [4:0] rd; input [6:0] opc;
        begin i_type = {imm, rs1, f3, rd, opc}; end
    endfunction
    function [31:0] s_type;
        input [11:0] imm; input [4:0] rs2; input [4:0] rs1;
        input [2:0] f3; input [6:0] opc;
        begin s_type = {imm[11:5], rs2, rs1, f3, imm[4:0], opc}; end
    endfunction
    function [31:0] b_type;
        input [12:0] imm; input [4:0] rs2; input [4:0] rs1;
        input [2:0] f3; input [6:0] opc;
        begin b_type = {imm[12], imm[10:5], rs2, rs1, f3,
                        imm[4:1], imm[11], opc}; end
    endfunction
    function [31:0] u_type;
        input [31:0] imm; input [4:0] rd; input [6:0] opc;
        begin u_type = {imm[31:12], rd, opc}; end
    endfunction
    function [31:0] j_type;
        input [20:0] imm; input [4:0] rd; input [6:0] opc;
        begin j_type = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opc}; end
    endfunction

    function [31:0] reg_val;
        input [4:0] idx;
        begin
            case (idx)
                5'd5: reg_val = 32'h1234_5678;
                5'd6: reg_val = 32'h8765_4321;
                5'd7: reg_val = 32'hDEAD_BEEF;
                default: reg_val = 32'h0;
            endcase
        end
    endfunction

    task set_defaults;
        begin
            exp = 264'b0;
            exp[B_MEM_SIZE +: 2] = 2'b10;
        end
    endtask

    // Purely wire-through fields, driven for every instruction regardless
    // of opcode. Control bits (use_rs*, branch, reg_write, ...) are set
    // by each individual test.
    task set_derived;
        input [31:0] ins;
        input        csr_imm_mode;
        begin
            exp[B_PC          +: 32] = if_pc;
            exp[B_PC_NEXT     +: 32] = if_pc_next;
            exp[B_RS1_ADDR    +: 5]  = ins[19:15];
            exp[B_RS1_DATA    +: 32] = reg_val(ins[19:15]);
            exp[B_RS2_ADDR    +: 5]  = ins[24:20];
            exp[B_RS2_DATA    +: 32] = reg_val(ins[24:20]);
            exp[B_RD_ADDR     +: 5]  = ins[11:7];
            exp[B_BRANCH_F3   +: 3]  = ins[14:12];  // wire-through
            exp[B_CSR_ADDR    +: 12] = ins[31:20];
            if (csr_imm_mode)
                exp[B_CSR_WDATA +: 32] = {27'b0, ins[19:15]};
            else
                exp[B_CSR_WDATA +: 32] = reg_val(ins[19:15]);
        end
    endtask

    task check;
        input [255:0] label;
        begin
            tests_run = tests_run + 1;
            if (got !== exp) begin
                $display("FAIL [%0s]", label);
                $display("  got = %0h", got);
                $display("  exp = %0h", exp);
                errors = errors + 1;
            end
        end
    endtask

    task preload_reg;
        input [4:0] rd; input [31:0] data;
        begin
            @(negedge clk);
            wb_reg_write = 1'b1; wb_rd_addr = rd; wb_rd_data = data;
            @(posedge clk);
            @(negedge clk);
            wb_reg_write = 1'b0; wb_rd_addr = 5'b0; wb_rd_data = 32'b0;
        end
    endtask

    task drive_inst;
        input [31:0] ins;
        begin
            @(negedge clk);
            if_inst = ins;
            #1;
        end
    endtask

    task run_directed;
        reg [31:0] ins;
        begin
            preload_reg(5'd5, 32'h1234_5678);
            preload_reg(5'd6, 32'h8765_4321);
            preload_reg(5'd7, 32'hDEAD_BEEF);

            // 1: ADDI x10, x5, 100
            ins = i_type(12'd100, 5'd5, `F3_ADDI, 5'd10, `OP_OP_IMM);
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b0);
            exp[B_IMM +: 32]   = 32'd100;
            exp[B_ALU_OP +: 5] = `ALU_ADD;
            exp[B_ALU_SRC_B]   = 1'b1;
            exp[B_USE_RS1]     = 1'b1;
            exp[B_REG_WRITE]   = 1'b1;
            check("ADDI x10, x5, 100");

            // 2: ADD x11, x5, x6
            ins = r_type(7'b0, 5'd6, 5'd5, `F3_ADD_SUB, 5'd11, `OP_OP);
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b0);
            exp[B_ALU_OP +: 5] = `ALU_ADD;
            exp[B_USE_RS1]     = 1'b1;
            exp[B_USE_RS2]     = 1'b1;
            exp[B_REG_WRITE]   = 1'b1;
            check("ADD x11, x5, x6");

            // 3: LW x12, 4(x5)
            ins = i_type(12'd4, 5'd5, `F3_LW, 5'd12, `OP_LOAD);
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b0);
            exp[B_IMM +: 32]   = 32'd4;
            exp[B_ALU_OP +: 5] = `ALU_ADD;
            exp[B_ALU_SRC_B]   = 1'b1;
            exp[B_USE_RS1]     = 1'b1;
            exp[B_MEM_READ]    = 1'b1;
            exp[B_WB_SEL +: 2] = `WB_MEM;
            exp[B_REG_WRITE]   = 1'b1;
            check("LW x12, 4(x5)");

            // 4: SW x6, 8(x5)
            ins = s_type(12'd8, 5'd6, 5'd5, `F3_SW, `OP_STORE);
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b0);
            exp[B_IMM +: 32]   = 32'd8;
            exp[B_ALU_OP +: 5] = `ALU_ADD;
            exp[B_ALU_SRC_B]   = 1'b1;
            exp[B_USE_RS1]     = 1'b1;
            exp[B_USE_RS2]     = 1'b1;
            exp[B_MEM_WRITE]   = 1'b1;
            check("SW x6, 8(x5)");

            // 5: BEQ x5, x6, +8
            ins = b_type(13'd8, 5'd6, 5'd5, `F3_BEQ, `OP_BRANCH);
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b0);
            exp[B_IMM +: 32]   = 32'd8;
            exp[B_ALU_OP +: 5] = `ALU_ADD;
            exp[B_ALU_SRC_A]   = 1'b1;
            exp[B_ALU_SRC_B]   = 1'b1;
            exp[B_BRANCH]      = 1'b1;
            exp[B_USE_RS1]     = 1'b1;
            exp[B_USE_RS2]     = 1'b1;
            check("BEQ x5, x6, +8");

            // 6: JAL x1, +100
            ins = j_type(21'd100, 5'd1, `OP_JAL);
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b0);
            exp[B_IMM +: 32]   = 32'd100;
            exp[B_ALU_OP +: 5] = `ALU_ADD;
            exp[B_ALU_SRC_A]   = 1'b1;
            exp[B_ALU_SRC_B]   = 1'b1;
            exp[B_JUMP]        = 1'b1;
            exp[B_REG_WRITE]   = 1'b1;
            exp[B_WB_SEL +: 2] = `WB_PC4;
            check("JAL x1, +100");

            // 7: LUI x7, 0xABCDE000
            ins = u_type(32'hABCD_E000, 5'd7, `OP_LUI);
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b0);
            exp[B_IMM +: 32]   = 32'hABCD_E000;
            exp[B_ALU_OP +: 5] = `ALU_PASS_B;
            exp[B_ALU_SRC_B]   = 1'b1;
            exp[B_REG_WRITE]   = 1'b1;
            check("LUI x7, 0xABCDE000");

            // 8: CSRRW x10, mstatus, x5
            ins = i_type(`CSR_MSTATUS, 5'd5, `F3_CSRRW, 5'd10, `OP_SYSTEM);
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b0);
            exp[B_IMM +: 32]   = {{20{ins[31]}}, ins[31:20]};
            exp[B_ALU_OP +: 5] = `ALU_ADD;
            exp[B_USE_RS1]     = 1'b1;
            exp[B_REG_WRITE]   = 1'b1;
            exp[B_CSR_WE]      = 1'b1;
            exp[B_CSR_OP +: 2] = `CSR_OP_RW;
            exp[B_WB_SEL +: 2] = `WB_CSR;
            check("CSRRW x10, mstatus, x5");

            // 9: CSRRSI x10, mtvec, 5
            ins = i_type(`CSR_MTVEC, 5'd5, `F3_CSRRSI, 5'd10, `OP_SYSTEM);
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b1);
            exp[B_IMM +: 32]   = {{20{ins[31]}}, ins[31:20]};
            exp[B_ALU_OP +: 5] = `ALU_ADD;
            exp[B_REG_WRITE]   = 1'b1;
            exp[B_CSR_WE]      = 1'b1;
            exp[B_CSR_OP +: 2] = `CSR_OP_RS;
            exp[B_CSR_IMM]     = 1'b1;
            exp[B_WB_SEL +: 2] = `WB_CSR;
            check("CSRRSI x10, mtvec, 5");

            // 10: MUL x10, x5, x6
            ins = r_type(`FUNCT7_M, 5'd6, 5'd5, `F3_MUL, 5'd10, `OP_OP);
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b0);
            exp[B_ALU_OP +: 5] = `ALU_ADD;
            exp[B_USE_RS1]     = 1'b1;
            exp[B_USE_RS2]     = 1'b1;
            exp[B_REG_WRITE]   = 1'b1;
            exp[B_MULDIV_SEL]  = 1'b1;
            exp[B_MULDIV_OP +: 4] = `MD_MUL;
            check("MUL x10, x5, x6");

            // 11: AMOADD.W x10, x5, (x6)
            ins = {`A_AMOADD, 2'b00, 5'd5, 5'd6, 3'b010, 5'd10, `OP_ATOMIC};
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b0);
            exp[B_ALU_OP +: 5] = `ALU_ADD;
            exp[B_ALU_SRC_B]   = 1'b1;
            exp[B_USE_RS1]     = 1'b1;
            exp[B_USE_RS2]     = 1'b1;
            exp[B_MEM_READ]    = 1'b1;
            exp[B_MEM_WRITE]   = 1'b1;
            exp[B_REG_WRITE]   = 1'b1;
            exp[B_WB_SEL +: 2] = `WB_MEM;
            exp[B_ATOMIC_SEL]  = 1'b1;
            exp[B_AMO_OP +: 5] = `A_AMOADD;
            check("AMOADD.W x10, x5, (x6)");

            // 12: illegal 0xFFFFFFFF
            ins = 32'hFFFF_FFFF;
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b0);
            exp[B_ILLEGAL]     = 1'b1;
            check("illegal all-ones");

            // 13: illegal branch funct3
            ins = b_type(13'd8, 5'd6, 5'd5, 3'b010, `OP_BRANCH);
            drive_inst(ins);
            set_defaults; set_derived(ins, 1'b0);
            exp[B_IMM +: 32]      = 32'd8;
            exp[B_ILLEGAL]        = 1'b1;
            check("illegal branch funct3");

            // 14: fetch fault pass-through
            @(negedge clk);
            if_inst        = i_type(12'd0, 5'd0, `F3_ADDI, 5'd0, `OP_OP_IMM);
            if_fetch_fault = 1'b1;
            #1;
            set_defaults;
            set_derived(if_inst, 1'b0);
            exp[B_ALU_OP +: 5] = `ALU_ADD;
            exp[B_ALU_SRC_B]   = 1'b1;
            exp[B_USE_RS1]     = 1'b1;    // ADDI uses rs1
            exp[B_REG_WRITE]   = 1'b1;
            exp[B_FETCH_FAULT] = 1'b1;
            check("fetch_fault pass-through");
            if_fetch_fault = 1'b0;
        end
    endtask

    integer k;
    reg [31:0] r_inst;

    task run_random;
        begin
            for (k = 0; k < 200; k = k + 1) begin
                r_inst = $urandom;
                r_inst[1:0] = 2'b11;
                drive_inst(r_inst);
                tests_run = tests_run + 1;
                if (^{id_pc, id_pc_next, id_rs1_data, id_rs2_data, id_imm,
                       id_csr_wdata, id_alu_op, id_mem_size, id_wb_sel,
                       id_csr_op, id_branch_funct3, id_sys_op, id_muldiv_op,
                       id_amo_op, id_rs1_addr, id_rs2_addr, id_rd_addr,
                       id_csr_addr, id_alu_src_a, id_alu_src_b, id_branch,
                       id_jump, id_use_rs1, id_use_rs2, id_mem_read,
                       id_mem_write, id_mem_unsigned, id_reg_write,
                       id_csr_we, id_csr_imm, id_muldiv_sel, id_atomic_sel,
                       id_is_lr, id_is_sc, id_illegal, id_fetch_fault} === 1'bx)
                begin
                    $display("FAIL [RAND] X with inst=%h", r_inst);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_id_stage);

        errors = 0; tests_run = 0;
        if_pc = 32'h1000; if_pc_next = 32'h1004;
        if_inst = 32'h0000_0013; if_fetch_fault = 1'b0;
        wb_reg_write = 1'b0; wb_rd_addr = 5'b0; wb_rd_data = 32'b0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_random;

        $display("---------------------------------------------");
        $display("tb_id_stage: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0) $display("TEST PASSED: tb_id_stage");
        else             $display("TEST FAILED: tb_id_stage %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_id_stage timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire