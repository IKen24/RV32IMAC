//=============================================================================
// Module:      tb_alu
// File:        sim/tb/tb_alu.v
// Description: Self-checking testbench for alu.v.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_alu;

    //------------------------------------------------------------------
    // Parameters
    //------------------------------------------------------------------
    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 10000;
    localparam integer NUM_RANDOM = 500;
    localparam [31:0]  SEED       = 32'hDEAD_BEEF;
    localparam integer NUM_OPS    = 12;

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
    reg  [31:0] op_a;
    reg  [31:0] op_b;
    reg  [4:0]  alu_op;
    wire [31:0] result;
    wire        zero;
    wire        lt_s;
    wire        lt_u;

    //------------------------------------------------------------------
    // Bookkeeping
    //------------------------------------------------------------------
    integer    errors;
    integer    tests_run;
    reg [31:0] opcode_hits;

    integer    rng_seed;
    integer    rng_dummy;

    reg [31:0] exp_result;
    reg        exp_zero;
    reg        exp_lt_s;
    reg        exp_lt_u;

    //------------------------------------------------------------------
    // DUT
    //------------------------------------------------------------------
    alu dut (
        .op_a   (op_a),
        .op_b   (op_b),
        .alu_op (alu_op),
        .result (result),
        .zero   (zero),
        .lt_s   (lt_s),
        .lt_u   (lt_u)
    );

    //------------------------------------------------------------------
    // Reference model
    //------------------------------------------------------------------
    task ref_model;
        input  [31:0] a;
        input  [31:0] b;
        input  [4:0]  op;
        begin
            exp_lt_s = ($signed(a) < $signed(b));
            exp_lt_u = (a < b);
            case (op)
                `ALU_ADD:    exp_result = a + b;
                `ALU_SUB:    exp_result = a - b;
                `ALU_SLL:    exp_result = a << b[4:0];
                `ALU_SLT:    exp_result = {31'b0, exp_lt_s};
                `ALU_SLTU:   exp_result = {31'b0, exp_lt_u};
                `ALU_XOR:    exp_result = a ^ b;
                `ALU_SRL:    exp_result = a >> b[4:0];
                `ALU_SRA:    exp_result = $signed(a) >>> b[4:0];
                `ALU_OR:     exp_result = a | b;
                `ALU_AND:    exp_result = a & b;
                `ALU_PASS_A: exp_result = a;
                `ALU_PASS_B: exp_result = b;
                default:     exp_result = 32'b0;
            endcase
            exp_zero = (exp_result == 32'b0);
        end
    endtask

    //------------------------------------------------------------------
    // Compare
    //------------------------------------------------------------------
    task compare_outputs;
        input [127:0] label;
        input [31:0]  a;
        input [31:0]  b;
        input [4:0]   op;
        begin
            if (result !== exp_result) begin
                $display("FAIL [%0s] op=%0d a=%h b=%h result=%h exp=%h",
                         label, op, a, b, result, exp_result);
                errors = errors + 1;
            end
            if (zero !== exp_zero) begin
                $display("FAIL [%0s] op=%0d a=%h b=%h zero=%b exp=%b",
                         label, op, a, b, zero, exp_zero);
                errors = errors + 1;
            end
            if (lt_s !== exp_lt_s) begin
                $display("FAIL [%0s] op=%0d a=%h b=%h lt_s=%b exp=%b",
                         label, op, a, b, lt_s, exp_lt_s);
                errors = errors + 1;
            end
            if (lt_u !== exp_lt_u) begin
                $display("FAIL [%0s] op=%0d a=%h b=%h lt_u=%b exp=%b",
                         label, op, a, b, lt_u, exp_lt_u);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Single-test driver
    //------------------------------------------------------------------
    task run_test;
        input [31:0]  a;
        input [31:0]  b;
        input [4:0]   op;
        input [127:0] label;
        begin
            @(negedge clk);
            op_a   = a;
            op_b   = b;
            alu_op = op;
            #1;
            tests_run = tests_run + 1;
            opcode_hits[op] = 1'b1;
            ref_model(a, b, op);
            compare_outputs(label, a, b, op);
        end
    endtask

    //------------------------------------------------------------------
    // Directed vectors
    //------------------------------------------------------------------
    task run_directed;
        begin
            // ADD
            run_test(32'h0000_0000, 32'h0000_0000, `ALU_ADD, "ADD 0+0");
            run_test(32'h0000_0000, 32'hFFFF_FFFF, `ALU_ADD, "ADD 0+max");
            run_test(32'hFFFF_FFFF, 32'h0000_0000, `ALU_ADD, "ADD max+0");
            run_test(32'hFFFF_FFFF, 32'hFFFF_FFFF, `ALU_ADD, "ADD wrap");
            run_test(32'h0000_0001, 32'hFFFF_FFFF, `ALU_ADD, "ADD 1+-1=0");
            run_test(32'h7FFF_FFFF, 32'h0000_0001, `ALU_ADD, "ADD signed ovf");

            // SUB
            run_test(32'h0000_0000, 32'h0000_0000, `ALU_SUB, "SUB 0-0");
            run_test(32'h0000_0000, 32'h0000_0001, `ALU_SUB, "SUB underflow");
            run_test(32'hFFFF_FFFF, 32'hFFFF_FFFF, `ALU_SUB, "SUB max-max");
            run_test(32'h8000_0000, 32'h0000_0001, `ALU_SUB, "SUB signed ovf");

            // Shifts
            run_test(32'h0000_0001, 32'h0000_0001, `ALU_SLL, "SLL 1<<1");
            run_test(32'h0000_0001, 32'h0000_001F, `ALU_SLL, "SLL 1<<31");
            run_test(32'h0000_0001, 32'h0000_0020, `ALU_SLL, "SLL 1<<32 low5=0");
            run_test(32'h0000_0001, 32'h0000_0021, `ALU_SLL, "SLL 1<<33 low5=1");
            run_test(32'h8000_0000, 32'h0000_0001, `ALU_SRL, "SRL msb>>1");
            run_test(32'h8000_0000, 32'h0000_0001, `ALU_SRA, "SRA msb>>1 sign");
            run_test(32'hFFFF_FFFF, 32'h0000_0004, `ALU_SRA, "SRA -1>>4");
            run_test(32'hFFFF_FFFF, 32'h0000_0004, `ALU_SRL, "SRL -1>>4");

            // SLT / SLTU
            run_test(32'h8000_0000, 32'h7FFF_FFFF, `ALU_SLT,  "SLT -1<max s");
            run_test(32'h8000_0000, 32'h7FFF_FFFF, `ALU_SLTU, "SLTU -1<max u");
            run_test(32'h0000_0005, 32'h0000_0005, `ALU_SLT,  "SLT equal");
            run_test(32'h0000_0005, 32'h0000_0005, `ALU_SLTU, "SLTU equal");
            run_test(32'h0000_0004, 32'h0000_0005, `ALU_SLT,  "SLT 4<5");
            run_test(32'h0000_0004, 32'h0000_0005, `ALU_SLTU, "SLTU 4<5");

            // Logic
            run_test(32'hAAAA_AAAA, 32'h5555_5555, `ALU_XOR, "XOR alt");
            run_test(32'hAAAA_AAAA, 32'h5555_5555, `ALU_OR,  "OR alt");
            run_test(32'hAAAA_AAAA, 32'h5555_5555, `ALU_AND, "AND alt");
            run_test(32'hFFFF_FFFF, 32'hFFFF_FFFF, `ALU_XOR, "XOR same=0");

            // Passthrough
            run_test(32'hDEAD_BEEF, 32'h0000_0000, `ALU_PASS_A, "PASS_A");
            run_test(32'h0000_0000, 32'hCAFE_F00D, `ALU_PASS_B, "PASS_B");

            // Zero flag
            run_test(32'h0000_0000, 32'h0000_0000, `ALU_OR,  "ZERO via OR");
            run_test(32'h1234_5678, 32'h1234_5678, `ALU_XOR, "ZERO via XOR");

            // Invalid opcode -> default -> result=0
            run_test(32'h1234_5678, 32'h8765_4321, 5'd12, "INVALID op12");
            run_test(32'hFFFF_FFFF, 32'hFFFF_FFFF, 5'd31, "INVALID op31");
        end
    endtask

    //------------------------------------------------------------------
    // Randomized cross-check
    //------------------------------------------------------------------
    reg [31:0] rand_a;
    reg [31:0] rand_b;
    reg [4:0]  rand_op;
    integer    k;

    task run_random;
        begin
            for (k = 0; k < NUM_RANDOM; k = k + 1) begin
                rand_a  = $urandom;
                rand_b  = $urandom;
                rand_op = $urandom_range(0, NUM_OPS - 1);
                run_test(rand_a, rand_b, rand_op, "RAND");
            end
        end
    endtask

    //------------------------------------------------------------------
    // Coverage assertion
    //------------------------------------------------------------------
    integer c;

    task check_coverage;
        begin
            for (c = 0; c < NUM_OPS; c = c + 1) begin
                if (!opcode_hits[c]) begin
                    $display("FAIL coverage: opcode %0d never exercised", c);
                    errors = errors + 1;
                end
            end
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_alu);

        errors      = 0;
        tests_run   = 0;
        opcode_hits = 32'b0;

        op_a   = 32'b0;
        op_b   = 32'b0;
        alu_op = 5'b0;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_random;
        check_coverage;

        $display("---------------------------------------------");
        $display("tb_alu: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_alu");
        else
            $display("TEST FAILED: tb_alu %0d errors", errors);
        $finish;
    end

    //------------------------------------------------------------------
    // Watchdog
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_alu timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire