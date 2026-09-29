//=============================================================================
// Module:      tb_muldiv
// File:        sim/tb/tb_muldiv.v
// Description: Self-checking TB for muldiv.
//   - Directed MUL/MULH/MULHSU/MULHU edge cases
//   - Directed DIV/DIVU/REM/REMU edge cases (incl. div-by-zero, overflow)
//   - Busy-cycle count verification (1 for MUL, 32 for DIV)
//   - Randomized cross-check against reference model
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_muldiv;

    localparam integer CLK_PERIOD   = 10;
    localparam integer MAX_CYCLES   = 500000;
    localparam integer NUM_RANDOM   = 300;
    localparam [31:0]  SEED         = 32'hC0DE_1234;

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
    reg         start;
    reg  [3:0]  op;
    reg  [31:0] op_a;
    reg  [31:0] op_b;
    wire [31:0] result;
    wire        busy;

    muldiv dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (start),
        .op     (op),
        .op_a   (op_a),
        .op_b   (op_b),
        .result (result),
        .busy   (busy)
    );

    integer errors;
    integer tests_run;
    integer rng_seed;
    integer rng_dummy;
    integer last_busy_cycles;

    //------------------------------------------------------------------
    // Reference model
    //------------------------------------------------------------------
    function [31:0] ref_model;
        input [3:0]  op;
        input [31:0] a;
        input [31:0] b;
        reg signed [63:0] a_sx, b_sx, b_ux;
        reg        [63:0] prod;
        reg signed [31:0] sa, sb;
        begin
            a_sx = {{32{a[31]}}, a};
            b_sx = {{32{b[31]}}, b};
            b_ux = {32'b0, b};
            case (op)
                `MD_MUL: begin
                    prod = a_sx * b_sx;
                    ref_model = prod[31:0];
                end
                `MD_MULH: begin
                    prod = a_sx * b_sx;
                    ref_model = prod[63:32];
                end
                `MD_MULHSU: begin
                    prod = a_sx * b_ux;
                    ref_model = prod[63:32];
                end
                `MD_MULHU: begin
                    prod = {32'b0, a} * {32'b0, b};
                    ref_model = prod[63:32];
                end
                `MD_DIV: begin
                    sa = a; sb = b;
                    if (b == 32'd0)
                        ref_model = 32'hFFFF_FFFF;
                    else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF)
                        ref_model = 32'h8000_0000;
                    else
                        ref_model = sa / sb;
                end
                `MD_DIVU: begin
                    if (b == 32'd0) ref_model = 32'hFFFF_FFFF;
                    else            ref_model = a / b;
                end
                `MD_REM: begin
                    sa = a; sb = b;
                    if (b == 32'd0)
                        ref_model = a;
                    else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF)
                        ref_model = 32'd0;
                    else
                        ref_model = sa % sb;
                end
                `MD_REMU: begin
                    if (b == 32'd0) ref_model = a;
                    else            ref_model = a % b;
                end
                default: ref_model = 32'b0;
            endcase
        end
    endfunction

    //------------------------------------------------------------------
    // Drive one op, wait for busy to fall, record busy cycles.
    //------------------------------------------------------------------
    task drive_op;
        input [3:0]  op_in;
        input [31:0] a_in;
        input [31:0] b_in;
        begin
            @(negedge clk);
            op    = op_in;
            op_a  = a_in;
            op_b  = b_in;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            if (busy !== 1'b1) begin
                $display("FAIL: busy not asserted one cycle after start");
                errors = errors + 1;
            end
            last_busy_cycles = 0;
            while (busy) begin
                last_busy_cycles = last_busy_cycles + 1;
                @(negedge clk);
            end
        end
    endtask

    //------------------------------------------------------------------
    // Check result against reference model
    //------------------------------------------------------------------
    task check_op;
        input [3:0]   op_in;
        input [31:0]  a_in;
        input [31:0]  b_in;
        input [255:0] label;
        reg [31:0]    expected;
        begin
            drive_op(op_in, a_in, b_in);
            tests_run = tests_run + 1;
            expected  = ref_model(op_in, a_in, b_in);
            if (result !== expected) begin
                $display("FAIL [%0s] op=%0d a=%h b=%h got=%h exp=%h",
                         label, op_in, a_in, b_in, result, expected);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Check busy-cycle count
    //------------------------------------------------------------------
    task check_busy;
        input [3:0]   op_in;
        input [31:0]  a_in;
        input [31:0]  b_in;
        input integer exp_cycles;
        input [255:0] label;
        begin
            drive_op(op_in, a_in, b_in);
            tests_run = tests_run + 1;
            if (last_busy_cycles !== exp_cycles) begin
                $display("FAIL [%0s] busy_cycles got=%0d exp=%0d",
                         label, last_busy_cycles, exp_cycles);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Directed tests
    //------------------------------------------------------------------
    task run_directed;
        begin
            // ---------- MUL ----------
            check_op(`MD_MUL, 32'd0,        32'd0,        "MUL 0*0");
            check_op(`MD_MUL, 32'd1,        32'd1,        "MUL 1*1");
            check_op(`MD_MUL, 32'd3,        32'd7,        "MUL 3*7");
            check_op(`MD_MUL, 32'hFFFF_FFFF,32'd1,        "MUL -1*1");
            check_op(`MD_MUL, 32'hFFFF_FFFF,32'hFFFF_FFFF,"MUL -1*-1");
            check_op(`MD_MUL, 32'h8000_0000,32'h8000_0000,"MUL min*min");
            check_op(`MD_MUL, 32'h7FFF_FFFF,32'h7FFF_FFFF,"MUL max*max");
            check_op(`MD_MUL, 32'h0001_0000,32'h0001_0000,"MUL 65536*65536 wrap");

            // ---------- MULH ----------
            check_op(`MD_MULH, 32'h0001_0000,32'h0001_0000,"MULH 2^16*2^16");
            check_op(`MD_MULH, 32'h8000_0000,32'h8000_0000,"MULH min*min");
            check_op(`MD_MULH, 32'hFFFF_FFFF,32'hFFFF_FFFF,"MULH -1*-1");
            check_op(`MD_MULH, 32'h7FFF_FFFF,32'h7FFF_FFFF,"MULH max*max");
            check_op(`MD_MULH, 32'h7FFF_FFFF,32'h8000_0000,"MULH max*min");

            // ---------- MULHSU ----------
            check_op(`MD_MULHSU, 32'hFFFF_FFFF,32'hFFFF_FFFF,"MULHSU -1*u-max");
            check_op(`MD_MULHSU, 32'h8000_0000,32'hFFFF_FFFF,"MULHSU min*u-max");
            check_op(`MD_MULHSU, 32'h7FFF_FFFF,32'hFFFF_FFFF,"MULHSU max*u-max");
            check_op(`MD_MULHSU, 32'h0001_0000,32'h0001_0000,"MULHSU 2^16*2^16");

            // ---------- MULHU ----------
            check_op(`MD_MULHU, 32'hFFFF_FFFF,32'hFFFF_FFFF,"MULHU max*max");
            check_op(`MD_MULHU, 32'h8000_0000,32'h8000_0000,"MULHU 2^31*2^31");
            check_op(`MD_MULHU, 32'h0001_0000,32'h0001_0000,"MULHU 2^16*2^16");

            // ---------- DIV ----------
            check_op(`MD_DIV, 32'd10,        32'd3,         "DIV 10/3");
            check_op(`MD_DIV, 32'hFFFF_FFF6,32'd3,         "DIV -10/3");
            check_op(`MD_DIV, 32'd10,        32'hFFFF_FFFD,"DIV 10/-3");
            check_op(`MD_DIV, 32'hFFFF_FFF6,32'hFFFF_FFFD,"DIV -10/-3");
            check_op(`MD_DIV, 32'd10,        32'd0,         "DIV 10/0");
            check_op(`MD_DIV, 32'h8000_0000,32'hFFFF_FFFF,"DIV -2^31/-1");
            check_op(`MD_DIV, 32'd7,         32'hFFFF_FFFA,"DIV 7/-6");

            // ---------- DIVU ----------
            check_op(`MD_DIVU, 32'd10,        32'd3,        "DIVU 10/3");
            check_op(`MD_DIVU, 32'hFFFF_FFFF,32'd2,        "DIVU max/2");
            check_op(`MD_DIVU, 32'd10,        32'd0,        "DIVU 10/0");

            // ---------- REM ----------
            check_op(`MD_REM, 32'd10,        32'd3,         "REM 10%3");
            check_op(`MD_REM, 32'hFFFF_FFF6,32'd3,         "REM -10%3");
            check_op(`MD_REM, 32'd10,        32'hFFFF_FFFD,"REM 10%-3");
            check_op(`MD_REM, 32'hFFFF_FFF6,32'hFFFF_FFFD,"REM -10%-3");
            check_op(`MD_REM, 32'd10,        32'd0,         "REM 10%0");
            check_op(`MD_REM, 32'h8000_0000,32'hFFFF_FFFF,"REM -2^31%-1");

            // ---------- REMU ----------
            check_op(`MD_REMU, 32'd10,        32'd3,        "REMU 10%3");
            check_op(`MD_REMU, 32'hFFFF_FFFF,32'd7,        "REMU max%7");
            check_op(`MD_REMU, 32'd10,        32'd0,        "REMU 10%0");

            // ---------- Busy-cycle counts ----------
            check_busy(`MD_MUL,    32'd5, 32'd5,  1, "busy MUL");
            check_busy(`MD_MULH,   32'd5, 32'd5,  1, "busy MULH");
            check_busy(`MD_MULHSU, 32'd5, 32'd5,  1, "busy MULHSU");
            check_busy(`MD_MULHU,  32'd5, 32'd5,  1, "busy MULHU");
            check_busy(`MD_DIV,    32'd5, 32'd5, 32, "busy DIV");
            check_busy(`MD_DIVU,   32'd5, 32'd5, 32, "busy DIVU");
            check_busy(`MD_REM,    32'd5, 32'd5, 32, "busy REM");
            check_busy(`MD_REMU,   32'd5, 32'd5, 32, "busy REMU");
            check_busy(`MD_DIV,    32'd5, 32'd0,  1, "busy DIV/0");
            check_busy(`MD_REM,    32'd5, 32'd0,  1, "busy REM/0");
        end
    endtask

    //------------------------------------------------------------------
    // Randomized cross-check
    //------------------------------------------------------------------
    integer k;
    reg [3:0]  r_op;
    reg [31:0] r_a;
    reg [31:0] r_b;

    task run_random;
        begin
            for (k = 0; k < NUM_RANDOM; k = k + 1) begin
                r_op = $urandom_range(0, 8);   // MD_NONE(0)..MD_REMU(8)
                r_a  = $urandom;
                r_b  = $urandom;
                if (r_op == `MD_NONE) r_op = `MD_MUL;
                check_op(r_op, r_a, r_b, "RAND");
            end
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_muldiv);

        errors    = 0;
        tests_run = 0;
        start     = 1'b0;
        op        = `MD_NONE;
        op_a      = 32'b0;
        op_b      = 32'b0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_random;

        $display("---------------------------------------------");
        $display("tb_muldiv: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_muldiv");
        else
            $display("TEST FAILED: tb_muldiv %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_muldiv timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire