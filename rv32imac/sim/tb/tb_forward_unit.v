//=============================================================================
// Module:      tb_forward_unit
// File:        sim/tb/tb_forward_unit.v
// Description: Self-checking TB for forward_unit.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_forward_unit;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 10000;
    localparam integer NUM_RANDOM = 500;
    localparam [31:0]  SEED       = 32'hF0F0_1234;

    reg clk, rst_n;
    integer cycles;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycles <= 0;
        else        cycles <= cycles + 1;
    end

    reg  [4:0] ex_rs1_addr, ex_rs2_addr;
    reg        ex_use_rs1, ex_use_rs2;
    reg        mem_reg_write;
    reg  [4:0] mem_rd_addr;
    reg        wb_reg_write;
    reg  [4:0] wb_rd_addr;
    wire [1:0] forward_a_sel, forward_b_sel;

    integer errors;
    integer tests_run;
    integer rng_seed;
    integer rng_dummy;

    forward_unit dut (
        .ex_rs1_addr  (ex_rs1_addr),
        .ex_rs2_addr  (ex_rs2_addr),
        .ex_use_rs1   (ex_use_rs1),
        .ex_use_rs2   (ex_use_rs2),
        .mem_reg_write(mem_reg_write),
        .mem_rd_addr  (mem_rd_addr),
        .wb_reg_write (wb_reg_write),
        .wb_rd_addr   (wb_rd_addr),
        .forward_a_sel(forward_a_sel),
        .forward_b_sel(forward_b_sel)
    );

    //------------------------------------------------------------------
    // Reference model
    //------------------------------------------------------------------
    function [1:0] ref_fwd;
        input        en;
        input [4:0]  src;
        input        mem_we;
        input [4:0]  mem_rd;
        input        wb_we;
        input [4:0]  wb_rd;
        begin
            if (en && mem_we && (mem_rd != 5'd0) && (mem_rd == src))
                ref_fwd = `FW_MEM;
            else if (en && wb_we && (wb_rd != 5'd0) && (wb_rd == src))
                ref_fwd = `FW_WB;
            else
                ref_fwd = `FW_NONE;
        end
    endfunction

    //------------------------------------------------------------------
    // Check helper
    //------------------------------------------------------------------
    task check;
        input [4:0]   rs1, rs2;
        input         u1, u2;
        input         mwe;
        input [4:0]   mrd;
        input         wwe;
        input [4:0]   wrd;
        input [255:0] label;
        reg [1:0]     exp_a, exp_b;
        begin
            @(negedge clk);
            ex_rs1_addr   = rs1;
            ex_rs2_addr   = rs2;
            ex_use_rs1    = u1;
            ex_use_rs2    = u2;
            mem_reg_write = mwe;
            mem_rd_addr   = mrd;
            wb_reg_write  = wwe;
            wb_rd_addr    = wrd;
            #1;

            exp_a = ref_fwd(u1, rs1, mwe, mrd, wwe, wrd);
            exp_b = ref_fwd(u2, rs2, mwe, mrd, wwe, wrd);

            tests_run = tests_run + 1;
            if (forward_a_sel !== exp_a) begin
                $display("FAIL [%0s] a got=%b exp=%b (rs1=%0d u1=%b mwe=%b mrd=%0d wwe=%b wrd=%0d)",
                         label, forward_a_sel, exp_a, rs1, u1, mwe, mrd, wwe, wrd);
                errors = errors + 1;
            end
            if (forward_b_sel !== exp_b) begin
                $display("FAIL [%0s] b got=%b exp=%b (rs2=%0d u2=%b mwe=%b mrd=%0d wwe=%b wrd=%0d)",
                         label, forward_b_sel, exp_b, rs2, u2, mwe, mrd, wwe, wrd);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Directed tests
    //------------------------------------------------------------------
    task run_directed;
        begin
            check(5'd1,  5'd2,  1'b1, 1'b1,
                  1'b0, 5'd0, 1'b0, 5'd0, "no producers");

            check(5'd1,  5'd2,  1'b1, 1'b1,
                  1'b1, 5'd1, 1'b0, 5'd0, "A from MEM");

            check(5'd1,  5'd2,  1'b1, 1'b1,
                  1'b0, 5'd0, 1'b1, 5'd2, "B from WB");

            check(5'd1,  5'd2,  1'b1, 1'b1,
                  1'b1, 5'd1, 1'b1, 5'd2, "A=MEM, B=WB");

            check(5'd3,  5'd4,  1'b1, 1'b1,
                  1'b1, 5'd3, 1'b1, 5'd3, "A both -> MEM wins");

            check(5'd1,  5'd3,  1'b1, 1'b1,
                  1'b1, 5'd3, 1'b1, 5'd3, "B both -> MEM wins");

            check(5'd0,  5'd0,  1'b1, 1'b1,
                  1'b1, 5'd0, 1'b1, 5'd0, "x0 consumer no forward");

            check(5'd5,  5'd6,  1'b1, 1'b1,
                  1'b1, 5'd0, 1'b1, 5'd0, "x0 producer no forward");

            check(5'd1,  5'd2,  1'b0, 1'b1,
                  1'b1, 5'd1, 1'b1, 5'd2, "use_rs1=0 gates A");

            check(5'd1,  5'd2,  1'b1, 1'b0,
                  1'b1, 5'd1, 1'b1, 5'd2, "use_rs2=0 gates B");

            check(5'd1,  5'd2,  1'b0, 1'b0,
                  1'b1, 5'd1, 1'b1, 5'd2, "use both off");

            check(5'd1,  5'd2,  1'b1, 1'b1,
                  1'b0, 5'd1, 1'b1, 5'd2, "mem_we=0");

            check(5'd1,  5'd2,  1'b1, 1'b1,
                  1'b1, 5'd1, 1'b0, 5'd2, "wb_we=0");

            check(5'd7,  5'd7,  1'b1, 1'b1,
                  1'b1, 5'd7, 1'b0, 5'd0, "A=B same reg from MEM");

            check(5'd4,  5'd8,  1'b1, 1'b1,
                  1'b0, 5'd0, 1'b1, 5'd4, "A from WB only");

            check(5'd9,  5'd10, 1'b1, 1'b1,
                  1'b1, 5'd9, 1'b1, 5'd9, "A both, B none");
        end
    endtask

    //------------------------------------------------------------------
    // Random cross-check
    //------------------------------------------------------------------
    integer k;
    reg [4:0] r_rs1, r_rs2, r_mrd, r_wrd;
    reg       r_u1, r_u2, r_mwe, r_wwe;

    task run_random;
        begin
            for (k = 0; k < NUM_RANDOM; k = k + 1) begin
                r_rs1 = $urandom_range(0, 7);
                r_rs2 = $urandom_range(0, 7);
                r_u1  = $urandom_range(0, 1);
                r_u2  = $urandom_range(0, 1);
                r_mwe = $urandom_range(0, 1);
                r_wwe = $urandom_range(0, 1);
                r_mrd = $urandom_range(0, 7);
                r_wrd = $urandom_range(0, 7);

                check(r_rs1, r_rs2, r_u1, r_u2,
                      r_mwe, r_mrd, r_wwe, r_wrd, "RAND");
            end
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_forward_unit);

        errors    = 0;
        tests_run = 0;

        ex_rs1_addr   = 5'b0;
        ex_rs2_addr   = 5'b0;
        ex_use_rs1    = 1'b0;
        ex_use_rs2    = 1'b0;
        mem_reg_write = 1'b0;
        mem_rd_addr   = 5'b0;
        wb_reg_write  = 1'b0;
        wb_rd_addr    = 5'b0;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_random;

        $display("---------------------------------------------");
        $display("tb_forward_unit: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_forward_unit");
        else
            $display("TEST FAILED: tb_forward_unit %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_forward_unit timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire