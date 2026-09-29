//=============================================================================
// Module:      tb_ex_stage
// File:        sim/tb/tb_ex_stage.v
// Description: Integration TB for ex_stage.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_ex_stage;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 500000;
    localparam [31:0]  SEED       = 32'hE5E5_9999;

    reg clk, rst_n;
    integer cycles;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycles <= 0;
        else        cycles <= cycles + 1;
    end

    reg [31:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm;
    reg [4:0]  ex_rs1_addr, ex_rs2_addr;
    reg [4:0]  ex_alu_op;
    reg        ex_alu_src_a, ex_alu_src_b;
    reg [2:0]  ex_branch_funct3;
    reg        ex_branch, ex_jump;
    reg        ex_use_rs1, ex_use_rs2;
    reg        ex_muldiv_sel;
    reg [3:0]  ex_muldiv_op;

    reg        mem_reg_write;
    reg [4:0]  mem_rd_addr;
    reg [31:0] mem_alu_result;
    reg        wb_reg_write;
    reg [4:0]  wb_rd_addr;
    reg [31:0] wb_rd_data;

    wire [31:0] alu_result, store_data, redirect_target;
    wire        branch_taken, redirect, muldiv_stall;

    integer errors, tests_run, rng_seed, rng_dummy;

    ex_stage dut (
        .clk(clk), .rst_n(rst_n),
        .ex_pc(ex_pc),
        .ex_rs1_data(ex_rs1_data), .ex_rs2_data(ex_rs2_data),
        .ex_imm(ex_imm),
        .ex_rs1_addr(ex_rs1_addr), .ex_rs2_addr(ex_rs2_addr),
        .ex_alu_op(ex_alu_op),
        .ex_alu_src_a(ex_alu_src_a), .ex_alu_src_b(ex_alu_src_b),
        .ex_branch_funct3(ex_branch_funct3),
        .ex_branch(ex_branch), .ex_jump(ex_jump),
        .ex_use_rs1(ex_use_rs1), .ex_use_rs2(ex_use_rs2),
        .ex_muldiv_sel(ex_muldiv_sel), .ex_muldiv_op(ex_muldiv_op),
        .mem_reg_write(mem_reg_write), .mem_rd_addr(mem_rd_addr),
        .mem_alu_result(mem_alu_result),
        .wb_reg_write(wb_reg_write), .wb_rd_addr(wb_rd_addr),
        .wb_rd_data(wb_rd_data),
        .alu_result(alu_result), .store_data(store_data),
        .branch_taken(branch_taken), .redirect(redirect),
        .redirect_target(redirect_target),
        .muldiv_stall(muldiv_stall)
    );

    task deassert_inputs;
        begin
            ex_pc=0; ex_rs1_data=0; ex_rs2_data=0; ex_imm=0;
            ex_rs1_addr=0; ex_rs2_addr=0; ex_alu_op=`ALU_ADD;
            ex_alu_src_a=0; ex_alu_src_b=0;
            ex_branch_funct3=0; ex_branch=0; ex_jump=0;
            ex_use_rs1=0; ex_use_rs2=0;
            ex_muldiv_sel=0; ex_muldiv_op=`MD_NONE;
            mem_reg_write=0; mem_rd_addr=0; mem_alu_result=0;
            wb_reg_write=0; wb_rd_addr=0; wb_rd_data=0;
        end
    endtask

    task check_comb;
        input [31:0] exp_alu, exp_store;
        input        exp_bt, exp_red;
        input [31:0] exp_tgt;
        input [255:0] label;
        begin
            tests_run = tests_run + 1;
            if (alu_result !== exp_alu) begin
                $display("FAIL [%0s] alu_result got=%h exp=%h",
                         label, alu_result, exp_alu);
                errors = errors + 1;
            end
            if (store_data !== exp_store) begin
                $display("FAIL [%0s] store_data got=%h exp=%h",
                         label, store_data, exp_store);
                errors = errors + 1;
            end
            if (branch_taken !== exp_bt) begin
                $display("FAIL [%0s] branch_taken got=%b exp=%b",
                         label, branch_taken, exp_bt);
                errors = errors + 1;
            end
            if (redirect !== exp_red) begin
                $display("FAIL [%0s] redirect got=%b exp=%b",
                         label, redirect, exp_red);
                errors = errors + 1;
            end
            if (redirect && (redirect_target !== exp_tgt)) begin
                $display("FAIL [%0s] redirect_target got=%h exp=%h",
                         label, redirect_target, exp_tgt);
                errors = errors + 1;
            end
        end
    endtask

    task run_directed;
        begin
            // 1: ADDI x10, x5, 100
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'h0000_0100; ex_rs2_data=0; ex_imm=32'd100;
            ex_rs1_addr=5'd5; ex_use_rs1=1;
            ex_alu_op=`ALU_ADD; ex_alu_src_b=1;
            #1;
            check_comb(32'h0000_0164, 32'h0, 1'b0, 1'b0, 0, "ADDI");

            // 2: ADD x11, x5, x6
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'h0000_0100; ex_rs2_data=32'h0000_0044;
            ex_rs1_addr=5'd5; ex_rs2_addr=5'd6;
            ex_use_rs1=1; ex_use_rs2=1;
            ex_alu_op=`ALU_ADD;
            #1;
            check_comb(32'h0000_0144, 32'h0000_0044, 1'b0, 1'b0, 0, "ADD");

            // 3: SUB
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'h0000_0100; ex_rs2_data=32'h0000_0040;
            ex_rs1_addr=5'd5; ex_rs2_addr=5'd6;
            ex_use_rs1=1; ex_use_rs2=1;
            ex_alu_op=`ALU_SUB;
            #1;
            check_comb(32'h0000_00C0, 32'h0000_0040, 1'b0, 1'b0, 0, "SUB");

            // 4: LW address = rs1 + imm
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'h0000_1000; ex_rs2_data=0; ex_imm=32'd16;
            ex_rs1_addr=5'd8; ex_use_rs1=1;
            ex_alu_op=`ALU_ADD; ex_alu_src_b=1;
            #1;
            check_comb(32'h0000_1010, 32'h0, 1'b0, 1'b0, 0, "LW addr");

            // 5: SW store_data = rs2
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'h0000_2000; ex_rs2_data=32'hCAFE_BABE;
            ex_imm=32'd4;
            ex_rs1_addr=5'd9; ex_rs2_addr=5'd10;
            ex_use_rs1=1; ex_use_rs2=1;
            ex_alu_op=`ALU_ADD; ex_alu_src_b=1;
            #1;
            check_comb(32'h0000_2004, 32'hCAFE_BABE, 1'b0, 1'b0, 0, "SW");

            // 6: BEQ taken (rs1 == rs2)
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'h0000_1000; ex_rs2_data=32'h0000_1000;
            ex_imm=32'd8; ex_pc=32'h0000_3000;
            ex_branch=1; ex_branch_funct3=`F3_BEQ;
            ex_alu_src_a=1; ex_alu_src_b=1; ex_alu_op=`ALU_ADD;
            #1;
            check_comb(32'h0000_3008, 32'h0000_1000, 1'b1, 1'b1,
                       32'h0000_3008, "BEQ taken");

            // 7: BNE not taken
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'h0000_1000; ex_rs2_data=32'h0000_1000;
            ex_imm=32'd8; ex_pc=32'h0000_3000;
            ex_branch=1; ex_branch_funct3=`F3_BNE;
            ex_alu_src_a=1; ex_alu_src_b=1; ex_alu_op=`ALU_ADD;
            #1;
            check_comb(32'h0000_3008, 32'h0000_1000, 1'b0, 1'b0,
                       32'h0000_3008, "BNE not taken");

            // 8: BLT signed -1 < 1 -> taken
            // store_data is ex_rs2_data = 0x0000_0001
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'hFFFF_FFFF; ex_rs2_data=32'h0000_0001;
            ex_imm=32'd8; ex_pc=32'h0000_4000;
            ex_branch=1; ex_branch_funct3=`F3_BLT;
            ex_alu_src_a=1; ex_alu_src_b=1; ex_alu_op=`ALU_ADD;
            #1;
            check_comb(32'h0000_4008, 32'h0000_0001, 1'b1, 1'b1,
                       32'h0000_4008, "BLT");

            // 9: BLTU -1 < 1 -> not taken
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'hFFFF_FFFF; ex_rs2_data=32'h0000_0001;
            ex_imm=32'd8; ex_pc=32'h0000_4000;
            ex_branch=1; ex_branch_funct3=`F3_BLTU;
            ex_alu_src_a=1; ex_alu_src_b=1; ex_alu_op=`ALU_ADD;
            #1;
            check_comb(32'h0000_4008, 32'h0000_0001, 1'b0, 1'b0,
                       32'h0000_4008, "BLTU");

            // 10: JAL: redirect always, target = pc + imm
            deassert_inputs;
            @(negedge clk);
            ex_imm=32'd40; ex_pc=32'h0000_5000;
            ex_jump=1; ex_alu_src_a=1; ex_alu_src_b=1; ex_alu_op=`ALU_ADD;
            #1;
            check_comb(32'h0000_5028, 32'h0, 1'b0, 1'b1,
                       32'h0000_5028, "JAL");

            // 11: JALR: alu_result = rs1 + imm = 0x6007
            //             redirect_target = alu_result & ~1 = 0x6006
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'h0000_6003; ex_imm=32'd4;
            ex_rs1_addr=5'd7; ex_use_rs1=1;
            ex_jump=1; ex_alu_src_b=1; ex_alu_op=`ALU_ADD;
            #1;
            check_comb(32'h0000_6007, 32'h0, 1'b0, 1'b1,
                       32'h0000_6006, "JALR");

            // 12: Forwarding from MEM (rs1 matches mem_rd)
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'h1111_1111; ex_rs2_data=32'h2222_2222;
            ex_rs1_addr=5'd5; ex_rs2_addr=5'd6;
            ex_use_rs1=1; ex_use_rs2=1;
            ex_alu_op=`ALU_ADD;
            mem_reg_write=1; mem_rd_addr=5'd5;
            mem_alu_result=32'hABCD_0000;
            #1;
            check_comb(32'hABCD_0000 + 32'h2222_2222, 32'h2222_2222,
                       1'b0, 1'b0, 0, "fwd MEM A");

            // 13: Forwarding from WB (rs2 matches wb_rd)
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'h1111_1111; ex_rs2_data=32'h2222_2222;
            ex_rs1_addr=5'd5; ex_rs2_addr=5'd6;
            ex_use_rs1=1; ex_use_rs2=1;
            ex_alu_op=`ALU_ADD;
            wb_reg_write=1; wb_rd_addr=5'd6; wb_rd_data=32'hDEAD_0000;
            #1;
            check_comb(32'h1111_1111 + 32'hDEAD_0000, 32'hDEAD_0000,
                       1'b0, 1'b0, 0, "fwd WB B");

            // 14: MEM beats WB on simultaneous hit
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'hAAAA_AAAA; ex_rs2_data=0;
            ex_rs1_addr=5'd5; ex_use_rs1=1; ex_alu_op=`ALU_PASS_A;
            mem_reg_write=1; mem_rd_addr=5'd5;
            mem_alu_result=32'h0000_1111;
            wb_reg_write=1;  wb_rd_addr=5'd5; wb_rd_data=32'h0000_2222;
            #1;
            check_comb(32'h0000_1111, 32'h0, 1'b0, 1'b0, 0, "MEM beats WB");
        end
    endtask

    // Muldiv handshake
    task run_muldiv_test;
        begin
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'd7; ex_rs2_data=32'd6;
            ex_rs1_addr=5'd5; ex_rs2_addr=5'd6;
            ex_use_rs1=1; ex_use_rs2=1;
            ex_alu_op=`ALU_ADD;
            ex_muldiv_sel=1; ex_muldiv_op=`MD_MUL;
            #1;
            tests_run = tests_run + 1;
            if (!muldiv_stall) begin
                $display("FAIL muldiv_stall not high on issue");
                errors = errors + 1;
            end
            wait (!muldiv_stall);
            tests_run = tests_run + 1;
            if (alu_result !== 32'd42) begin
                $display("FAIL MUL result got=%0d exp=42", alu_result);
                errors = errors + 1;
            end
            @(negedge clk);
            ex_muldiv_sel = 0;

            // DIV
            deassert_inputs;
            @(negedge clk);
            ex_rs1_data=32'd100; ex_rs2_data=32'd7;
            ex_rs1_addr=5'd5; ex_rs2_addr=5'd6;
            ex_use_rs1=1; ex_use_rs2=1;
            ex_alu_op=`ALU_ADD;
            ex_muldiv_sel=1; ex_muldiv_op=`MD_DIV;
            #1;
            wait (!muldiv_stall);
            tests_run = tests_run + 1;
            if (alu_result !== 32'd14) begin
                $display("FAIL DIV result got=%0d exp=14", alu_result);
                errors = errors + 1;
            end
            @(negedge clk);
            ex_muldiv_sel = 0;
            deassert_inputs;
        end
    endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_ex_stage);

        errors = 0; tests_run = 0;
        deassert_inputs;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_muldiv_test;

        $display("---------------------------------------------");
        $display("tb_ex_stage: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0) $display("TEST PASSED: tb_ex_stage");
        else             $display("TEST FAILED: tb_ex_stage %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_ex_stage timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire