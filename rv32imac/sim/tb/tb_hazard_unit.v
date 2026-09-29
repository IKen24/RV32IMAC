//=============================================================================
// Module:      tb_hazard_unit
// File:        sim/tb/tb_hazard_unit.v
// Description: Self-checking TB for hazard_unit.
//   - Load-use stalls for both operands
//   - Redirects (branch/jump/trap) flush IF/ID and ID/EX
//   - muldiv_stall participates in stall, but NOT in flush_id_ex
//   - Randomized cross-check
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_hazard_unit;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 100000;
    localparam integer NUM_RANDOM = 1000;
    localparam [31:0]  SEED       = 32'hA1C0_1234;

    reg clk, rst_n;
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
    reg        ex_mem_read;
    reg        ex_reg_write;
    reg  [4:0] ex_rd_addr;
    reg        id_use_rs1;
    reg        id_use_rs2;
    reg  [4:0] id_rs1_addr;
    reg  [4:0] id_rs2_addr;
    reg        ex_branch_taken;
    reg        ex_jump;
    reg        ex_trap;
    reg        muldiv_stall;
    wire       stall;
    wire       flush_if_id;
    wire       flush_id_ex;

    integer errors;
    integer tests_run;
    integer rng_seed;
    integer rng_dummy;

    hazard_unit dut (
        .ex_mem_read    (ex_mem_read),
        .ex_reg_write   (ex_reg_write),
        .ex_rd_addr     (ex_rd_addr),
        .id_use_rs1     (id_use_rs1),
        .id_use_rs2     (id_use_rs2),
        .id_rs1_addr    (id_rs1_addr),
        .id_rs2_addr    (id_rs2_addr),
        .ex_branch_taken(ex_branch_taken),
        .ex_jump        (ex_jump),
        .ex_trap        (ex_trap),
        .muldiv_stall   (muldiv_stall),
        .stall          (stall),
        .flush_if_id    (flush_if_id),
        .flush_id_ex    (flush_id_ex)
    );

    //------------------------------------------------------------------
    // Reference model
    //------------------------------------------------------------------
    function ref_load_use;
        input        mrd, rw;
        input [4:0]  rd;
        input        u1, u2;
        input [4:0]  r1, r2;
        begin
            ref_load_use = mrd && rw && (rd != 5'd0) &&
                           ((u1 && (r1 == rd)) || (u2 && (r2 == rd)));
        end
    endfunction

    function ref_flush_if_id;
        input bt, jp, tp;
        begin
            ref_flush_if_id = bt || jp || tp;
        end
    endfunction

    //------------------------------------------------------------------
    // Check helper
    //------------------------------------------------------------------
    task check;
        input         mrd, rw;
        input [4:0]   rd;
        input         u1, u2;
        input [4:0]   r1, r2;
        input         bt, jp, tp, md;
        input [255:0] label;
        reg           lduse, exp_stall, exp_fif, exp_fie;
        begin
            @(negedge clk);
            ex_mem_read     = mrd;
            ex_reg_write    = rw;
            ex_rd_addr      = rd;
            id_use_rs1      = u1;
            id_use_rs2      = u2;
            id_rs1_addr     = r1;
            id_rs2_addr     = r2;
            ex_branch_taken = bt;
            ex_jump         = jp;
            ex_trap         = tp;
            muldiv_stall    = md;
            #1;

            lduse     = ref_load_use(mrd, rw, rd, u1, u2, r1, r2);
            exp_stall = lduse || md;
            exp_fif   = ref_flush_if_id(bt, jp, tp);
            exp_fie   = bt || jp || tp || lduse;

            tests_run = tests_run + 1;
            if (stall !== exp_stall) begin
                $display("FAIL [%0s] stall got=%b exp=%b", label, stall, exp_stall);
                errors = errors + 1;
            end
            if (flush_if_id !== exp_fif) begin
                $display("FAIL [%0s] flush_if_id got=%b exp=%b",
                         label, flush_if_id, exp_fif);
                errors = errors + 1;
            end
            if (flush_id_ex !== exp_fie) begin
                $display("FAIL [%0s] flush_id_ex got=%b exp=%b",
                         label, flush_id_ex, exp_fie);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Directed tests (each check now takes an md argument)
    //------------------------------------------------------------------
    task run_directed;
        begin
            // -------- Load-use stalls (md = 0) --------
            check(1'b1, 1'b1, 5'd1, 1'b1, 1'b0, 5'd1, 5'd0,
                  1'b0, 1'b0, 1'b0, 1'b0, "LD-USE rs1");
            check(1'b1, 1'b1, 5'd1, 1'b0, 1'b1, 5'd0, 5'd1,
                  1'b0, 1'b0, 1'b0, 1'b0, "LD-USE rs2");
            check(1'b1, 1'b1, 5'd5, 1'b1, 1'b1, 5'd5, 5'd5,
                  1'b0, 1'b0, 1'b0, 1'b0, "LD-USE both");
            check(1'b1, 1'b1, 5'd0, 1'b1, 1'b1, 5'd0, 5'd0,
                  1'b0, 1'b0, 1'b0, 1'b0, "LD-USE rd=x0 no stall");
            check(1'b0, 1'b1, 5'd1, 1'b1, 1'b0, 5'd1, 5'd0,
                  1'b0, 1'b0, 1'b0, 1'b0, "ALU producer no stall");
            check(1'b1, 1'b0, 5'd1, 1'b1, 1'b0, 5'd1, 5'd0,
                  1'b0, 1'b0, 1'b0, 1'b0, "no reg_write no stall");
            check(1'b1, 1'b1, 5'd1, 1'b0, 1'b0, 5'd0, 5'd0,
                  1'b0, 1'b0, 1'b0, 1'b0, "consumer no rs no stall");
            check(1'b1, 1'b1, 5'd1, 1'b1, 1'b1, 5'd2, 5'd3,
                  1'b0, 1'b0, 1'b0, 1'b0, "no addr match no stall");

            // -------- Redirects (md = 0) --------
            check(1'b0, 1'b0, 5'd0, 1'b0, 1'b0, 5'd0, 5'd0,
                  1'b1, 1'b0, 1'b0, 1'b0, "branch taken flush");
            check(1'b0, 1'b0, 5'd0, 1'b0, 1'b0, 5'd0, 5'd0,
                  1'b0, 1'b1, 1'b0, 1'b0, "jump flush");
            check(1'b0, 1'b0, 5'd0, 1'b0, 1'b0, 5'd0, 5'd0,
                  1'b0, 1'b0, 1'b1, 1'b0, "trap flush");
            check(1'b0, 1'b0, 5'd0, 1'b0, 1'b0, 5'd0, 5'd0,
                  1'b0, 1'b0, 1'b0, 1'b0, "no redirect no flush");

            // -------- Load-use + redirect (md = 0) --------
            check(1'b1, 1'b1, 5'd1, 1'b1, 1'b0, 5'd1, 5'd0,
                  1'b1, 1'b0, 1'b0, 1'b0, "stall + branch");
            check(1'b1, 1'b1, 5'd1, 1'b1, 1'b0, 5'd1, 5'd0,
                  1'b0, 1'b1, 1'b0, 1'b0, "stall + jump");
            check(1'b1, 1'b1, 5'd1, 1'b1, 1'b0, 5'd1, 5'd0,
                  1'b0, 1'b0, 1'b1, 1'b0, "stall + trap");

            // -------- muldiv_stall (NEW) --------
            // md alone: stall = 1, but flush_id_ex must be 0
            check(1'b0, 1'b0, 5'd0, 1'b0, 1'b0, 5'd0, 5'd0,
                  1'b0, 1'b0, 1'b0, 1'b1, "muldiv stall alone");
            // md + load-use: stall = 1, flush_id_ex = 1 (load-use bubble)
            check(1'b1, 1'b1, 5'd1, 1'b1, 1'b0, 5'd1, 5'd0,
                  1'b0, 1'b0, 1'b0, 1'b1, "muldiv + load-use");
            // md + branch: stall = 1, flush_if_id = 1, flush_id_ex = 1
            check(1'b0, 1'b0, 5'd0, 1'b0, 1'b0, 5'd0, 5'd0,
                  1'b1, 1'b0, 1'b0, 1'b1, "muldiv + branch");
            // md + jump
            check(1'b0, 1'b0, 5'd0, 1'b0, 1'b0, 5'd0, 5'd0,
                  1'b0, 1'b1, 1'b0, 1'b1, "muldiv + jump");
        end
    endtask

    //------------------------------------------------------------------
    // Random cross-check
    //------------------------------------------------------------------
    integer k;
    reg        r_mrd, r_rw, r_u1, r_u2, r_bt, r_jp, r_tp, r_md;
    reg [4:0]  r_rd, r_r1, r_r2;

    task run_random;
        begin
            for (k = 0; k < NUM_RANDOM; k = k + 1) begin
                r_mrd = $urandom_range(0, 1);
                r_rw  = $urandom_range(0, 1);
                r_u1  = $urandom_range(0, 1);
                r_u2  = $urandom_range(0, 1);
                r_bt  = $urandom_range(0, 1);
                r_jp  = $urandom_range(0, 1);
                r_tp  = $urandom_range(0, 1);
                r_md  = $urandom_range(0, 1);
                r_rd  = $urandom_range(0, 4);
                r_r1  = $urandom_range(0, 4);
                r_r2  = $urandom_range(0, 4);

                check(r_mrd, r_rw, r_rd, r_u1, r_u2, r_r1, r_r2,
                      r_bt, r_jp, r_tp, r_md, "RAND");
            end
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_hazard_unit);

        errors    = 0;
        tests_run = 0;

        ex_mem_read     = 1'b0;
        ex_reg_write    = 1'b0;
        ex_rd_addr      = 5'b0;
        id_use_rs1      = 1'b0;
        id_use_rs2      = 1'b0;
        id_rs1_addr     = 5'b0;
        id_rs2_addr     = 5'b0;
        ex_branch_taken = 1'b0;
        ex_jump         = 1'b0;
        ex_trap         = 1'b0;
        muldiv_stall    = 1'b0;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_random;

        $display("---------------------------------------------");
        $display("tb_hazard_unit: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_hazard_unit");
        else
            $display("TEST FAILED: tb_hazard_unit %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_hazard_unit timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire