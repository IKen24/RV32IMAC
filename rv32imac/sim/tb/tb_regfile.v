//=============================================================================
// Module:      tb_regfile
// File:        sim/tb/tb_regfile.v
// Description: Self-checking TB for regfile.
//   - Write-then-read on every register
//   - x0 read-as-zero and write-discard
//   - Same-cycle read-during-write returns the NEW value (write-first)
//   - Dual-port independence
//   - Randomized write/read cross-check against a shadow model
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_regfile;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 100000;
    localparam integer NUM_RANDOM = 500;
    localparam [31:0]  SEED       = 32'h1234_5678;

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
    reg  [4:0]  rs1_addr, rs2_addr;
    wire [31:0] rs1_data, rs2_data;
    reg         reg_write;
    reg  [4:0]  rd_addr;
    reg  [31:0] rd_data;

    integer errors;
    integer tests_run;
    integer rng_seed;
    integer rng_dummy;

    // Shadow model
    reg [31:0] shadow [0:31];

    regfile dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (rs1_addr),
        .rs1_data (rs1_data),
        .rs2_addr (rs2_addr),
        .rs2_data (rs2_data),
        .reg_write(reg_write),
        .rd_addr  (rd_addr),
        .rd_data  (rd_data)
    );

    //------------------------------------------------------------------
    // Low-level drive helpers
    //------------------------------------------------------------------
    task idle_write;
        begin
            @(negedge clk);
            reg_write = 1'b0;
            rd_addr   = 5'b0;
            rd_data   = 32'b0;
        end
    endtask

    // Drive a write, wait for posedge commit, deassert.
    // Shadow updates at issue time so subsequent read checks (which
    // may be same-cycle) see the new value.
    task do_write;
        input [4:0]  addr;
        input [31:0] data;
        begin
            @(negedge clk);
            reg_write = 1'b1;
            rd_addr   = addr;
            rd_data   = data;
            if (addr != 5'd0)
                shadow[addr] = data;
            @(posedge clk);
            @(negedge clk);
            reg_write = 1'b0;
            rd_addr   = 5'b0;
            rd_data   = 32'b0;
        end
    endtask

    // Read both ports and compare against shadow.
    task check_reads;
        input [4:0]  a1;
        input [4:0]  a2;
        input [255:0] label;
        begin
            @(negedge clk);
            rs1_addr = a1;
            rs2_addr = a2;
            #1;
            tests_run = tests_run + 1;
            if (rs1_data !== shadow[a1]) begin
                $display("FAIL [%0s] rs1[%0d] got=%h exp=%h",
                         label, a1, rs1_data, shadow[a1]);
                errors = errors + 1;
            end
            if (rs2_data !== shadow[a2]) begin
                $display("FAIL [%0s] rs2[%0d] got=%h exp=%h",
                         label, a2, rs2_data, shadow[a2]);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Directed tests
    //------------------------------------------------------------------
    integer i;

    task run_directed;
        begin
            // ---- Reset state: every register reads 0 ----
            for (i = 0; i < 32; i = i + 1) begin
                check_reads(i[4:0], i[4:0], "RESET reads");
            end

            // ---- Write each register, read it back ----
            for (i = 1; i < 32; i = i + 1) begin
                do_write(i[4:0], 32'hA000_0000 + i[31:0]);
            end
            for (i = 1; i < 32; i = i + 1) begin
                check_reads(i[4:0], i[4:0], "WROTE+READ");
            end

            // ---- x0 read as zero, independent of writes ----
            do_write(5'd0, 32'hDEAD_BEEF);
            check_reads(5'd0, 5'd0, "x0 stays zero");

            // ---- Dual-port independence ----
            check_reads(5'd1, 5'd31, "dual port 1/31");
            check_reads(5'd31, 5'd1, "dual port 31/1");
            check_reads(5'd15, 5'd16, "dual port 15/16");

            // ---- reg_write=0 must not commit ----
            @(negedge clk);
            reg_write = 1'b0;
            rd_addr   = 5'd5;
            rd_data   = 32'hFFFF_FFFF;
            @(posedge clk);
            @(negedge clk);
            check_reads(5'd5, 5'd5, "WE=0 no commit");

            // ---- Read-during-write: write-first semantics ----
            // Preload r7 with a known value.
            do_write(5'd7, 32'h1111_1111);
            // Now drive a write to r7 in the same cycle we read r7.
            // The read port must return the NEW value (write-first).
            @(negedge clk);
            reg_write = 1'b1;
            rd_addr   = 5'd7;
            rd_data   = 32'h2222_2222;
            rs1_addr  = 5'd7;
            #1;
            tests_run = tests_run + 1;
            if (rs1_data !== 32'h2222_2222) begin
                $display("FAIL [RD-DURING-WR] got=%h exp=22222222", rs1_data);
                errors = errors + 1;
            end
            @(posedge clk);
            shadow[5'd7] = 32'h2222_2222;
            @(negedge clk);
            reg_write = 1'b0;
            rd_addr   = 5'b0;
            rd_data   = 32'b0;
            check_reads(5'd7, 5'd7, "post RD-DURING-WR");
        end
    endtask

    //------------------------------------------------------------------
    // Randomized write/read cross-check
    //------------------------------------------------------------------
    integer k;
    reg [4:0]  wa, ra1, ra2;
    reg [31:0] wd;

    task run_random;
        begin
            for (k = 0; k < NUM_RANDOM; k = k + 1) begin
                wa  = $urandom_range(0, 31);
                wd  = $urandom;
                do_write(wa, wd);

                ra1 = $urandom_range(0, 31);
                ra2 = $urandom_range(0, 31);
                check_reads(ra1, ra2, "RAND rd/wr");
            end
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_regfile);

        errors    = 0;
        tests_run = 0;

        rs1_addr  = 5'b0;
        rs2_addr  = 5'b0;
        reg_write = 1'b0;
        rd_addr   = 5'b0;
        rd_data   = 32'b0;

        for (i = 0; i < 32; i = i + 1)
            shadow[i] = 32'b0;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_random;

        $display("---------------------------------------------");
        $display("tb_regfile: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_regfile");
        else
            $display("TEST FAILED: tb_regfile %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_regfile timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire