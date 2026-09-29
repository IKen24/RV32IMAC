//=============================================================================
// Module:      tb_if_id
// File:        sim/tb/tb_if_id.v
// Description: Self-checking TB for if_id.
//   - Reset state = NOP / zeros
//   - Capture, stall-hold, flush-to-NOP, capture-after-flush
//   - Flush has priority over stall
//   - Fault propagates
//   - Randomized cross-check against a shadow model with identical semantics
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_if_id;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 100000;
    localparam integer NUM_RANDOM = 200;
    localparam [31:0]  SEED       = 32'h1F1D_ABCD;
    localparam [31:0]  NOP        = 32'h0000_0013;

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
    reg         stall, flush;
    reg  [31:0] if_pc, if_pc_next, if_inst;
    reg         if_fetch_fault;
    wire [31:0] id_pc, id_pc_next, id_inst;
    wire        id_fetch_fault;

    integer errors;
    integer tests_run;
    integer rng_seed;
    integer rng_dummy;

    if_id dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .stall          (stall),
        .flush          (flush),
        .if_pc          (if_pc),
        .if_pc_next     (if_pc_next),
        .if_inst        (if_inst),
        .if_fetch_fault (if_fetch_fault),
        .id_pc          (id_pc),
        .id_pc_next     (id_pc_next),
        .id_inst        (id_inst),
        .id_fetch_fault (id_fetch_fault)
    );

    //------------------------------------------------------------------
    // Shadow model — same semantics as the DUT
    //------------------------------------------------------------------
    reg [31:0] sh_pc, sh_pc_next, sh_inst;
    reg        sh_fault;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sh_pc      <= 32'b0;
            sh_pc_next <= 32'b0;
            sh_inst    <= NOP;
            sh_fault   <= 1'b0;
        end else if (flush) begin
            sh_pc      <= 32'b0;
            sh_pc_next <= 32'b0;
            sh_inst    <= NOP;
            sh_fault   <= 1'b0;
        end else if (!stall) begin
            sh_pc      <= if_pc;
            sh_pc_next <= if_pc_next;
            sh_inst    <= if_inst;
            sh_fault   <= if_fetch_fault;
        end
    end

    //------------------------------------------------------------------
    // Check
    //------------------------------------------------------------------
    task check_outputs;
        input [255:0] label;
        begin
            tests_run = tests_run + 1;
            if (id_pc !== sh_pc) begin
                $display("FAIL [%0s] id_pc got=%h exp=%h", label, id_pc, sh_pc);
                errors = errors + 1;
            end
            if (id_pc_next !== sh_pc_next) begin
                $display("FAIL [%0s] id_pc_next got=%h exp=%h",
                         label, id_pc_next, sh_pc_next);
                errors = errors + 1;
            end
            if (id_inst !== sh_inst) begin
                $display("FAIL [%0s] id_inst got=%h exp=%h",
                         label, id_inst, sh_inst);
                errors = errors + 1;
            end
            if (id_fetch_fault !== sh_fault) begin
                $display("FAIL [%0s] id_fetch_fault got=%b exp=%b",
                         label, id_fetch_fault, sh_fault);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Drive helpers
    //------------------------------------------------------------------
    task drive_capture;
        input [31:0] pc, pcn, ins;
        input        f;
        begin
            @(negedge clk);
            if_pc          = pc;
            if_pc_next     = pcn;
            if_inst        = ins;
            if_fetch_fault = f;
            stall = 1'b0;
            flush = 1'b0;
            @(negedge clk);
        end
    endtask

    task drive_stall;
        input [31:0] pc, pcn, ins;
        input        f;
        begin
            @(negedge clk);
            if_pc          = pc;
            if_pc_next     = pcn;
            if_inst        = ins;
            if_fetch_fault = f;
            stall = 1'b1;
            flush = 1'b0;
            @(negedge clk);
            stall = 1'b0;
        end
    endtask

    task pulse_flush;
        begin
            @(negedge clk);
            stall = 1'b0;
            flush = 1'b1;
            @(negedge clk);
            flush = 1'b0;
        end
    endtask

    task pulse_flush_with_stall;
        begin
            @(negedge clk);
            stall = 1'b1;
            flush = 1'b1;
            @(negedge clk);
            stall = 1'b0;
            flush = 1'b0;
        end
    endtask

    //------------------------------------------------------------------
    // Directed sequence
    //------------------------------------------------------------------
    task run_directed;
        begin
            // Reset state check
            check_outputs("reset");

            // ---- Capture A ----
            drive_capture(32'h0000_1000, 32'h0000_1004,
                          32'hDEAD_BEEF, 1'b0);
            check_outputs("capture A");

            // ---- Stall holds A even with new inputs ----
            drive_stall(32'h0000_2000, 32'h0000_2004,
                        32'hCAFE_BABE, 1'b0);
            check_outputs("stall holds A");

            // ---- Capture B ----
            drive_capture(32'h0000_2000, 32'h0000_2004,
                          32'hCAFE_BABE, 1'b0);
            check_outputs("capture B");

            // ---- Flush -> NOP ----
            pulse_flush;
            check_outputs("flush -> NOP");

            // ---- Capture C after flush ----
            drive_capture(32'h0000_3000, 32'h0000_3004,
                          32'h1234_5678, 1'b1);
            check_outputs("capture C");

            // ---- Fault propagates ----
            drive_capture(32'h0000_4000, 32'h0000_4004,
                          32'hAAAA_AAAA, 1'b1);
            check_outputs("fault propagates");

            // ---- Flush overrides stall ----
            drive_capture(32'h0000_5000, 32'h0000_5004,
                          32'h5555_5555, 1'b0);
            check_outputs("pre flush+stall");
            pulse_flush_with_stall;
            check_outputs("flush+stall -> NOP");
        end
    endtask

    //------------------------------------------------------------------
    // Randomized
    //------------------------------------------------------------------
    integer k;
    integer mode;
    reg [31:0] r_pc, r_pcn, r_inst;
    reg        r_f;

    task run_random;
        begin
            for (k = 0; k < NUM_RANDOM; k = k + 1) begin
                r_pc   = $urandom;
                r_pcn  = $urandom;
                r_inst = $urandom;
                r_f    = $urandom_range(0, 1);
                mode   = $urandom_range(0, 3);

                @(negedge clk);
                if_pc          = r_pc;
                if_pc_next     = r_pcn;
                if_inst        = r_inst;
                if_fetch_fault = r_f;
                case (mode)
                    0, 1: begin stall = 1'b0; flush = 1'b0; end // capture
                    2:    begin stall = 1'b1; flush = 1'b0; end // stall
                    3:    begin stall = 1'b0; flush = 1'b1; end // flush
                endcase

                @(negedge clk);
                check_outputs("RAND");

                // Return controls to idle so next iteration starts clean
                stall = 1'b0;
                flush = 1'b0;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_if_id);

        errors    = 0;
        tests_run = 0;

        stall          = 1'b0;
        flush          = 1'b0;
        if_pc          = 32'b0;
        if_pc_next     = 32'b0;
        if_inst        = NOP;
        if_fetch_fault = 1'b0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_random;

        $display("---------------------------------------------");
        $display("tb_if_id: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_if_id");
        else
            $display("TEST FAILED: tb_if_id %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_if_id timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire