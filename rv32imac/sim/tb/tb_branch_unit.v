//=============================================================================
// Module:      tb_branch_unit
// File:        sim/tb/tb_branch_unit.v
// Description: Self-checking TB for branch_unit.
//   - Exhaustive over all 8 flag combinations for each valid funct3
//   - Illegal funct3 values must yield take=0
//   - Integration check: alu + branch_unit on a handful of real operands
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_branch_unit;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 10000;
    localparam [31:0]  SEED       = 32'hFEED_FACE;

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
    reg  [2:0] funct3;
    reg        zero;
    reg        lt_s;
    reg        lt_u;
    wire       take;

    integer errors;
    integer tests_run;
    integer rng_seed;
    integer rng_dummy;

    branch_unit dut (
        .funct3 (funct3),
        .zero   (zero),
        .lt_s   (lt_s),
        .lt_u   (lt_u),
        .take   (take)
    );

    //------------------------------------------------------------------
    // Reference model
    //------------------------------------------------------------------
    function ref_take;
        input [2:0] f3;
        input       z;
        input       ls;
        input       lu;
        begin
            case (f3)
                `F3_BEQ:  ref_take =  z;
                `F3_BNE:  ref_take = ~z;
                `F3_BLT:  ref_take =  ls;
                `F3_BGE:  ref_take = ~ls;
                `F3_BLTU: ref_take =  lu;
                `F3_BGEU: ref_take = ~lu;
                default:  ref_take = 1'b0;
            endcase
        end
    endfunction

    //------------------------------------------------------------------
    // Checker
    //------------------------------------------------------------------
    task check;
        input [2:0]   f3;
        input         z;
        input         ls;
        input         lu;
        input [255:0] label;
        begin
            funct3 = f3;
            zero   = z;
            lt_s   = ls;
            lt_u   = lu;
            #1;
            tests_run = tests_run + 1;
            if (take !== ref_take(f3, z, ls, lu)) begin
                $display("FAIL [%0s] f3=%b z=%b ls=%b lu=%b got=%b exp=%b",
                         label, f3, z, ls, lu,
                         take, ref_take(f3, z, ls, lu));
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Directed: exhaustive over all 8 flag combinations per funct3
    //------------------------------------------------------------------
    integer z, ls, lu;

    task run_directed;
        begin
            // All six valid branches, exhaustive over flags
            for (z = 0; z < 2; z = z + 1) begin
                for (ls = 0; ls < 2; ls = ls + 1) begin
                    for (lu = 0; lu < 2; lu = lu + 1) begin
                        check(`F3_BEQ,  z[0], ls[0], lu[0], "BEQ");
                        check(`F3_BNE,  z[0], ls[0], lu[0], "BNE");
                        check(`F3_BLT,  z[0], ls[0], lu[0], "BLT");
                        check(`F3_BGE,  z[0], ls[0], lu[0], "BGE");
                        check(`F3_BLTU, z[0], ls[0], lu[0], "BLTU");
                        check(`F3_BGEU, z[0], ls[0], lu[0], "BGEU");
                    end
                end
            end

            // Illegal funct3 values must yield 0 regardless of flags
            for (z = 0; z < 2; z = z + 1) begin
                for (ls = 0; ls < 2; ls = ls + 1) begin
                    for (lu = 0; lu < 2; lu = lu + 1) begin
                        check(3'b010, z[0], ls[0], lu[0], "ILLEGAL 010");
                        check(3'b011, z[0], ls[0], lu[0], "ILLEGAL 011");
                        check(3'b111, z[0], ls[0], lu[0], "ILLEGAL 111");
                    end
                end
            end
        end
    endtask

    //------------------------------------------------------------------
    // Integration check: alu + branch_unit
    // The real EX stage wires alu's flags into branch_unit. This
    // proves the pairing works end-to-end on directed operands.
    //------------------------------------------------------------------
    reg  [31:0] op_a, op_b;
    reg  [4:0]  alu_op;
    wire [31:0] alu_result;
    wire        alu_zero, alu_lt_s, alu_lt_u;
    wire        bu_take;

    alu u_alu (
        .op_a   (op_a),
        .op_b   (op_b),
        .alu_op (alu_op),
        .result (alu_result),
        .zero   (alu_zero),
        .lt_s   (alu_lt_s),
        .lt_u   (alu_lt_u)
    );

    branch_unit u_bu (
        .funct3 (funct3),
        .zero   (alu_zero),
        .lt_s   (alu_lt_s),
        .lt_u   (alu_lt_u),
        .take   (bu_take)
    );

    task check_integration;
        input [31:0]  a;
        input [31:0]  b;
        input [2:0]   f3;
        input         expected;
        input [255:0] label;
        begin
            op_a   = a;
            op_b   = b;
            alu_op = `ALU_SUB;   // all three flags meaningful for SUB
            funct3 = f3;
            #1;
            tests_run = tests_run + 1;
            if (bu_take !== expected) begin
                $display("FAIL [%0s] a=%h b=%h f3=%b got=%b exp=%b",
                         label, a, b, f3, bu_take, expected);
                errors = errors + 1;
            end
        end
    endtask

    task run_integration;
        begin
            // Equal
            check_integration(32'h0000_0005, 32'h0000_0005, `F3_BEQ,  1'b1, "int BEQ eq");
            check_integration(32'h0000_0005, 32'h0000_0005, `F3_BNE,  1'b0, "int BNE eq");

            // Unsigned / signed disagree: a = -1, b = 1
            check_integration(32'hFFFF_FFFF, 32'h0000_0001, `F3_BLT,  1'b1, "int BLT -1<1");
            check_integration(32'hFFFF_FFFF, 32'h0000_0001, `F3_BLTU, 1'b0, "int BLTU -1<1");
            check_integration(32'hFFFF_FFFF, 32'h0000_0001, `F3_BGE,  1'b0, "int BGE -1>=1");
            check_integration(32'hFFFF_FFFF, 32'h0000_0001, `F3_BGEU, 1'b1, "int BGEU -1>=1");

            // Signed ordering: -2 < -1
            check_integration(32'hFFFF_FFFE, 32'hFFFF_FFFF, `F3_BLT,  1'b1, "int BLT -2<-1");
            check_integration(32'hFFFF_FFFE, 32'hFFFF_FFFF, `F3_BLTU, 1'b1, "int BLTU big-small");
            check_integration(32'hFFFF_FFFE, 32'hFFFF_FFFF, `F3_BGE,  1'b0, "int BGE -2>=-1");
            check_integration(32'hFFFF_FFFE, 32'hFFFF_FFFF, `F3_BGEU, 1'b0, "int BGEU big-small");

            // Positive ordering: 5 < 7
            check_integration(32'h0000_0005, 32'h0000_0007, `F3_BLT,  1'b1, "int BLT 5<7");
            check_integration(32'h0000_0005, 32'h0000_0007, `F3_BLTU, 1'b1, "int BLTU 5<7");
            check_integration(32'h0000_0005, 32'h0000_0007, `F3_BGE,  1'b0, "int BGE 5>=7");
            check_integration(32'h0000_0005, 32'h0000_0007, `F3_BGEU, 1'b0, "int BGEU 5>=7");
        end
    endtask

    //------------------------------------------------------------------
    // Randomized flag-triplet check
    //------------------------------------------------------------------
    integer k;
    reg [2:0] r_f3;
    reg [2:0] r_flags;

    task run_random;
        begin
            for (k = 0; k < 500; k = k + 1) begin
                r_f3    = $urandom_range(0, 7);
                r_flags = $urandom_range(0, 7);
                check(r_f3, r_flags[2], r_flags[1], r_flags[0], "RAND");
            end
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_branch_unit);

        errors    = 0;
        tests_run = 0;

        funct3 = 3'b0;
        zero   = 1'b0;
        lt_s   = 1'b0;
        lt_u   = 1'b0;
        op_a   = 32'b0;
        op_b   = 32'b0;
        alu_op = `ALU_SUB;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_random;
        run_integration;

        $display("---------------------------------------------");
        $display("tb_branch_unit: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_branch_unit");
        else
            $display("TEST FAILED: tb_branch_unit %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_branch_unit timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype none
`default_nettype wire