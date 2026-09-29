//=============================================================================
// Module:      tb_rvc_expand
// File:        sim/tb/tb_rvc_expand.v
// Description: Self-checking TB for rvc_expand.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_rvc_expand;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 10000;
    localparam [31:0]  SEED       = 32'hC0DE_9999;

    reg clk, rst_n;
    integer cycles;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycles <= 0;
        else        cycles <= cycles + 1;
    end

    reg  [31:0] inst_in;
    wire [31:0] inst_out;
    wire        is_compressed;
    wire        illegal;

    integer errors;
    integer tests_run;
    integer rng_seed;
    integer rng_dummy;

    rvc_expand dut (
        .inst_in       (inst_in),
        .inst_out      (inst_out),
        .is_compressed (is_compressed),
        .illegal       (illegal)
    );

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

    task check;
        input [31:0]  in_word;
        input [31:0]  exp_out;
        input         exp_comp;
        input         exp_ill;
        input [255:0] label;
        begin
            @(negedge clk);
            inst_in = in_word;
            #1;
            tests_run = tests_run + 1;
            if (inst_out !== exp_out) begin
                $display("FAIL [%0s] in=%h out=%h exp=%h",
                         label, in_word, inst_out, exp_out);
                errors = errors + 1;
            end
            if (is_compressed !== exp_comp) begin
                $display("FAIL [%0s] is_compressed got=%b exp=%b",
                         label, is_compressed, exp_comp);
                errors = errors + 1;
            end
            if (illegal !== exp_ill) begin
                $display("FAIL [%0s] illegal got=%b exp=%b",
                         label, illegal, exp_ill);
                errors = errors + 1;
            end
        end
    endtask

    task run_directed;
        reg [31:0] exp;
        begin
            // ---------- 32-bit pass-through ----------
            check(32'hDEADBEEF, 32'hDEADBEEF, 1'b0, 1'b0, "pass 32-bit");
            check(32'h00000013, 32'h00000013, 1'b0, 1'b0, "pass ADDI x0");
            check(32'hFFFFFFFF, 32'hFFFFFFFF, 1'b0, 1'b0, "pass all-ones");

            // ---------- C.NOP ----------
            check(32'h0000_0001, 32'h0000_0013, 1'b1, 1'b0, "C.NOP");

            // ---------- C.ADDI x5, 3 ----------
            exp = enc_i(12'h003, 5'd5, `F3_ADDI, 5'd5, `OP_OP_IMM);
            check(32'h0000_028D, exp, 1'b1, 1'b0, "C.ADDI x5,3");

            // ---------- C.ADDI4SPN x8, 4 ----------
            exp = enc_i(12'h004, 5'd2, `F3_ADDI, 5'd8, `OP_OP_IMM);
            check(32'h0000_0040, exp, 1'b1, 1'b0, "C.ADDI4SPN x8,4");

            // ---------- C.LW x8, 0(x9) ----------
            exp = enc_i(12'h000, 5'd9, `F3_LW, 5'd8, `OP_LOAD);
            check(32'h0000_4080, exp, 1'b1, 1'b0, "C.LW x8,0(x9)");

            // ---------- C.SW x8, 0(x9) ----------
            exp = enc_s(12'h000, 5'd8, 5'd9, `F3_SW, `OP_STORE);
            check(32'h0000_C080, exp, 1'b1, 1'b0, "C.SW x8,0(x9)");

            // ---------- C.LI x5, -1 ----------
            exp = enc_i(12'hFFF, 5'd0, `F3_ADDI, 5'd5, `OP_OP_IMM);
            check(32'h0000_52FD, exp, 1'b1, 1'b0, "C.LI x5,-1");

            // ---------- C.ADDI16SP x2, -16 ----------
            exp = enc_i(12'hFF0, 5'd2, `F3_ADDI, 5'd2, `OP_OP_IMM);
            check(32'h0000_717D, exp, 1'b1, 1'b0, "C.ADDI16SP -16");

            // ---------- C.LUI x5, 1 ----------
            exp = enc_u(32'h0000_1000, 5'd5, `OP_LUI);
            check(32'h0000_6285, exp, 1'b1, 1'b0, "C.LUI x5,1");

            // ---------- C.SRLI x8, 3 ----------
            exp = enc_i({7'b0000000, 5'd3}, 5'd8, `F3_SRI, 5'd8, `OP_OP_IMM);
            check(32'h0000_800D, exp, 1'b1, 1'b0, "C.SRLI x8,3");

            // ---------- C.SRAI x8, 3 ----------
            exp = enc_i({7'b0100000, 5'd3}, 5'd8, `F3_SRI, 5'd8, `OP_OP_IMM);
            check(32'h0000_840D, exp, 1'b1, 1'b0, "C.SRAI x8,3");

            // ---------- C.ANDI x8, 5 ----------
            exp = enc_i(12'h005, 5'd8, `F3_ANDI, 5'd8, `OP_OP_IMM);
            check(32'h0000_8815, exp, 1'b1, 1'b0, "C.ANDI x8,5");

            // ---------- C.SUB x8, x9 ----------
            exp = enc_r(7'b0100000, 5'd9, 5'd8, `F3_ADD_SUB, 5'd8, `OP_OP);
            check(32'h0000_8C05, exp, 1'b1, 1'b0, "C.SUB x8,x9");

            // ---------- C.XOR x8, x9 ----------
            exp = enc_r(7'b0000000, 5'd9, 5'd8, `F3_XOR, 5'd8, `OP_OP);
            check(32'h0000_8C25, exp, 1'b1, 1'b0, "C.XOR x8,x9");

            // ---------- C.OR x8, x9 ----------
            exp = enc_r(7'b0000000, 5'd9, 5'd8, `F3_OR, 5'd8, `OP_OP);
            check(32'h0000_8C45, exp, 1'b1, 1'b0, "C.OR x8,x9");

            // ---------- C.AND x8, x9 ----------
            exp = enc_r(7'b0000000, 5'd9, 5'd8, `F3_AND, 5'd8, `OP_OP);
            check(32'h0000_8C65, exp, 1'b1, 1'b0, "C.AND x8,x9");

            // ---------- C.J +4 ----------
            exp = enc_j(21'h000004, 5'd0, `OP_JAL);
            check(32'h0000_A011, exp, 1'b1, 1'b0, "C.J +4");

            // ---------- C.JAL +4 ----------
            exp = enc_j(21'h000004, 5'd1, `OP_JAL);
            check(32'h0000_2011, exp, 1'b1, 1'b0, "C.JAL +4");

            // ---------- C.BEQZ x8, +4 ----------
            exp = enc_b(13'h0004, 5'd0, 5'd8, `F3_BEQ, `OP_BRANCH);
            check(32'h0000_C011, exp, 1'b1, 1'b0, "C.BEQZ x8,+4");

            // ---------- C.BNEZ x8, +4 ----------
            exp = enc_b(13'h0004, 5'd0, 5'd8, `F3_BNE, `OP_BRANCH);
            check(32'h0000_E011, exp, 1'b1, 1'b0, "C.BNEZ x8,+4");

            // ---------- C.SLLI x5, 3 ----------
            exp = enc_i({7'b0, 5'd3}, 5'd5, `F3_SLLI, 5'd5, `OP_OP_IMM);
            check(32'h0000_028E, exp, 1'b1, 1'b0, "C.SLLI x5,3");

            // ---------- C.LWSP x5, 0 ----------
            exp = enc_i(12'h000, 5'd2, `F3_LW, 5'd5, `OP_LOAD);
            check(32'h0000_4282, exp, 1'b1, 1'b0, "C.LWSP x5,0");

            // ---------- C.SWSP x5, 0 ----------
            exp = enc_s(12'h000, 5'd5, 5'd2, `F3_SW, `OP_STORE);
            check(32'h0000_C016, exp, 1'b1, 1'b0, "C.SWSP x5,0");

            // ---------- C.MV x5, x6 ----------
            exp = enc_r(7'b0000000, 5'd6, 5'd0, `F3_ADD_SUB, 5'd5, `OP_OP);
            check(32'h0000_829A, exp, 1'b1, 1'b0, "C.MV x5,x6");

            // ---------- C.ADD x5, x6 ----------
            exp = enc_r(7'b0000000, 5'd6, 5'd5, `F3_ADD_SUB, 5'd5, `OP_OP);
            check(32'h0000_929A, exp, 1'b1, 1'b0, "C.ADD x5,x6");

            // ---------- C.JR x5 ----------
            exp = enc_i(12'h000, 5'd5, `F3_JALR, 5'd0, `OP_JALR);
            check(32'h0000_8282, exp, 1'b1, 1'b0, "C.JR x5");

            // ---------- C.JALR x5 ----------
            exp = enc_i(12'h000, 5'd5, `F3_JALR, 5'd1, `OP_JALR);
            check(32'h0000_9282, exp, 1'b1, 1'b0, "C.JALR x5");

            // ---------- C.EBREAK ----------
            check(32'h0000_9002, 32'h0010_0073, 1'b1, 1'b0, "C.EBREAK");

            // ---------- Illegal cases ----------
            check(32'h0000_0000, 32'h0000_0013, 1'b1, 1'b1, "illegal ADDI4SPN 0");
            check(32'h0000_6001, 32'h0000_0013, 1'b1, 1'b1, "illegal LUI rd=0");
            check(32'h0000_4002, 32'h0000_0013, 1'b1, 1'b1, "illegal LWSP rd=0");
            check(32'h0000_8002, 32'h0000_0013, 1'b1, 1'b1, "illegal JR rs1=0");
            check(32'h0000_910D, 32'h0000_0013, 1'b1, 1'b1, "illegal SRLI shamt[5]");
            check(32'h0000_9D09, 32'h0000_0013, 1'b1, 1'b1, "illegal C.SUBW (RV64C)");
        end
    endtask

    integer k;
    reg [15:0] r_lo;
    reg [31:0] r_word;

    task run_random_sanity;
        begin
            for (k = 0; k < 500; k = k + 1) begin
                r_lo   = $urandom;
                r_word = {16'b0, r_lo};
                if (r_lo[1:0] != 2'b11) begin
                    @(negedge clk);
                    inst_in = r_word;
                    #1;
                    tests_run = tests_run + 1;
                    if (^{inst_out, is_compressed, illegal} === 1'bx) begin
                        $display("FAIL [RAND X] in=%h out=%h comp=%b ill=%b",
                                 r_word, inst_out, is_compressed, illegal);
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_rvc_expand);

        errors    = 0;
        tests_run = 0;
        inst_in   = 32'b0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_random_sanity;

        $display("---------------------------------------------");
        $display("tb_rvc_expand: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_rvc_expand");
        else
            $display("TEST FAILED: tb_rvc_expand %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_rvc_expand timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire