//=============================================================================
// Module:      tb_imm_gen
// File:        sim/tb/tb_imm_gen.v
// Description: Self-checking TB for imm_gen.
//              Directed vectors for I/S/B/U/J formats including sign edges,
//              plus randomized encode->extract round trip.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_imm_gen;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 10000;
    localparam integer NUM_RANDOM = 500;
    localparam [31:0]  SEED       = 32'hCAFE_F00D;

    //------------------------------------------------------------------
    // Clock / reset
    //------------------------------------------------------------------
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
    // DUT signals
    //------------------------------------------------------------------
    reg  [31:0] inst;
    wire [31:0] imm;

    integer errors;
    integer tests_run;
    integer rng_seed;
    integer rng_dummy;

    imm_gen dut (
        .inst (inst),
        .imm  (imm)
    );

    //------------------------------------------------------------------
    // Encoders (mirror ISA manual figures 2.4 / 2.5)
    //------------------------------------------------------------------
    function [31:0] enc_i;
        input [31:0] imm_in;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [4:0]  rd;
        input [6:0]  opc;
        begin
            enc_i = {imm_in[11:0], rs1, funct3, rd, opc};
        end
    endfunction

    function [31:0] enc_s;
        input [31:0] imm_in;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [4:0]  rs2;
        input [6:0]  opc;
        begin
            enc_s = {imm_in[11:5], rs2, rs1, funct3,
                     imm_in[4:0], opc};
        end
    endfunction

    function [31:0] enc_b;
        input [31:0] imm_in;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [4:0]  rs2;
        input [6:0]  opc;
        begin
            enc_b = {imm_in[12], imm_in[10:5], rs2, rs1, funct3,
                     imm_in[4:1], imm_in[11], opc};
        end
    endfunction

    function [31:0] enc_u;
        input [31:0] imm_in;
        input [4:0]  rd;
        input [6:0]  opc;
        begin
            enc_u = {imm_in[31:12], rd, opc};
        end
    endfunction

    function [31:0] enc_j;
        input [31:0] imm_in;
        input [4:0]  rd;
        input [6:0]  opc;
        begin
            enc_j = {imm_in[20], imm_in[10:1], imm_in[11],
                     imm_in[19:12], rd, opc};
        end
    endfunction

    //------------------------------------------------------------------
    // Checker
    //------------------------------------------------------------------
    task check;
        input [31:0]  inst_in;
        input [31:0]  expected;
        input [127:0] label;
        begin
            @(negedge clk);
            inst = inst_in;
            #1;
            tests_run = tests_run + 1;
            if (imm !== expected) begin
                $display("FAIL [%0s] inst=%h imm=%h exp=%h",
                         label, inst_in, imm, expected);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Directed
    //------------------------------------------------------------------
    task run_directed;
        begin
            // ---- I-type via ADDI ----
            check(enc_i(32'h0000_0000, 5'd1, `F3_ADDI, 5'd2, `OP_OP_IMM),
                  32'h0000_0000, "I zero");
            check(enc_i(32'h0000_0001, 5'd1, `F3_ADDI, 5'd2, `OP_OP_IMM),
                  32'h0000_0001, "I +1");
            check(enc_i(32'h0000_07FF, 5'd1, `F3_ADDI, 5'd2, `OP_OP_IMM),
                  32'h0000_07FF, "I max pos");
            check(enc_i(32'h0000_0800, 5'd1, `F3_ADDI, 5'd2, `OP_OP_IMM),
                  32'hFFFF_F800, "I neg edge 0x800");
            check(enc_i(32'h0000_0FFF, 5'd1, `F3_ADDI, 5'd2, `OP_OP_IMM),
                  32'hFFFF_FFFF, "I -1");
            check(enc_i(32'h0000_0800, 5'd1, `F3_ADDI, 5'd2, `OP_OP_IMM),
                  32'hFFFF_F800, "I min neg");

            // ---- I-type via LOAD ----
            check(enc_i(32'h0000_0010, 5'd1, `F3_LW, 5'd2, `OP_LOAD),
                  32'h0000_0010, "I load +16");

            // ---- S-type via SW ----
            check(enc_s(32'h0000_0000, 5'd1, `F3_SW, 5'd2, `OP_STORE),
                  32'h0000_0000, "S zero");
            check(enc_s(32'h0000_0010, 5'd1, `F3_SW, 5'd2, `OP_STORE),
                  32'h0000_0010, "S +16");
            check(enc_s(32'h0000_07F0, 5'd1, `F3_SW, 5'd2, `OP_STORE),
                  32'h0000_07F0, "S max pos");
            check(enc_s(32'hFFFF_FFF0, 5'd1, `F3_SW, 5'd2, `OP_STORE),
                  32'hFFFF_FFF0, "S -16");
            check(enc_s(32'hFFFF_F800, 5'd1, `F3_SW, 5'd2, `OP_STORE),
                  32'hFFFF_F800, "S min neg");

            // ---- B-type via BEQ ----
            check(enc_b(32'h0000_0000, 5'd1, `F3_BEQ, 5'd2, `OP_BRANCH),
                  32'h0000_0000, "B zero");
            check(enc_b(32'h0000_0002, 5'd1, `F3_BEQ, 5'd2, `OP_BRANCH),
                  32'h0000_0002, "B +2");
            check(enc_b(32'h0000_0FFE, 5'd1, `F3_BEQ, 5'd2, `OP_BRANCH),
                  32'h0000_0FFE, "B max pos");
            check(enc_b(32'hFFFF_F000, 5'd1, `F3_BEQ, 5'd2, `OP_BRANCH),
                  32'hFFFF_F000, "B -4096");
            check(enc_b(32'hFFFF_FFFE, 5'd1, `F3_BEQ, 5'd2, `OP_BRANCH),
                  32'hFFFF_FFFE, "B -2");

            // ---- U-type ----
            check(enc_u(32'hDEAD_B000, 5'd1, `OP_LUI),
                  32'hDEAD_B000, "U LUI");
            check(enc_u(32'hFFFF_F000, 5'd1, `OP_AUIPC),
                  32'hFFFF_F000, "U AUIPC -4K");

            // ---- J-type ----
            check(enc_j(32'h0000_0000, 5'd1, `OP_JAL),
                  32'h0000_0000, "J zero");
            check(enc_j(32'h0000_0002, 5'd1, `OP_JAL),
                  32'h0000_0002, "J +2");
            check(enc_j(32'h0000_0004, 5'd1, `OP_JAL),
                  32'h0000_0004, "J +4");
            check(enc_j(32'h000F_FFFE, 5'd1, `OP_JAL),
                  32'h000F_FFFE, "J large pos");
            check(enc_j(32'hFFF0_0000, 5'd1, `OP_JAL),
                  32'hFFF0_0000, "J large neg");
            check(enc_j(32'hFFFF_FFFE, 5'd1, `OP_JAL),
                  32'hFFFF_FFFE, "J -2");

            // ---- Unused opcode -> 0 ----
            check({25'b0, `OP_ATOMIC},   32'h0000_0000, "ATOMIC -> 0");
            check({25'b0, `OP_MISC_MEM}, 32'h0000_0000, "MISC_MEM -> 0");
        end
    endtask

    //------------------------------------------------------------------
    // Randomized round trip
    //------------------------------------------------------------------
    integer k;
    reg [31:0] r;
    reg [31:0] i_i;
    reg [31:0] i_s;
    reg [31:0] i_b;
    reg [31:0] i_u;
    reg [31:0] i_j;

    task run_random;
        begin
            for (k = 0; k < NUM_RANDOM; k = k + 1) begin
                r = $urandom;

                // I: 12-bit sign-extended immediate
                i_i = {{20{r[11]}}, r[11:0]};
                check(enc_i(i_i, 5'd3, `F3_ADDI, 5'd4, `OP_OP_IMM),
                      i_i, "RAND I");

                // S: 12-bit sign-extended
                i_s = {{20{r[11]}}, r[11:0]};
                check(enc_s(i_s, 5'd3, `F3_SW, 5'd4, `OP_STORE),
                      i_s, "RAND S");

                // B: 13-bit sign-extended, bit0 = 0
                i_b = {{19{r[12]}}, r[12:1], 1'b0};
                check(enc_b(i_b, 5'd3, `F3_BEQ, 5'd4, `OP_BRANCH),
                      i_b, "RAND B");

                // U: upper 20 bits, low 12 zero
                i_u = {r[31:12], 12'b0};
                check(enc_u(i_u, 5'd3, `OP_LUI),
                      i_u, "RAND U");

                // J: 21-bit sign-extended, bit0 = 0
                i_j = {{11{r[20]}}, r[20:1], 1'b0};
                check(enc_j(i_j, 5'd3, `OP_JAL),
                      i_j, "RAND J");
            end
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_imm_gen);

        errors    = 0;
        tests_run = 0;
        inst      = 32'b0;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_random;

        $display("---------------------------------------------");
        $display("tb_imm_gen: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_imm_gen");
        else
            $display("TEST FAILED: tb_imm_gen %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_imm_gen timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire