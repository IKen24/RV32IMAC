//=============================================================================
// Module:      tb_if_stage
// File:        sim/tb/tb_if_stage.v
// Description: Self-checking TB for if_stage.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_if_stage;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 100000;
    localparam [31:0]  SEED       = 32'h1F17_5678;

    reg clk, rst_n;
    integer cycles;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycles <= 0;
        else        cycles <= cycles + 1;
    end

    reg         stall, redirect;
    reg  [31:0] redirect_target;

    wire        mem_req_valid;
    wire        mem_req_ready;
    wire [31:0] mem_req_addr;
    wire        mem_rsp_valid;
    wire        mem_rsp_ready;
    wire [31:0] mem_rsp_rdata;
    wire        mem_rsp_error;

    wire [31:0] if_pc, if_pc_next, if_inst;
    wire        if_fetch_fault, if_valid;

    integer errors;
    integer tests_run;
    integer rng_seed;
    integer rng_dummy;

    if_stage dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall           (stall),
        .redirect        (redirect),
        .redirect_target (redirect_target),
        .mem_req_valid   (mem_req_valid),
        .mem_req_ready   (mem_req_ready),
        .mem_req_addr    (mem_req_addr),
        .mem_rsp_valid   (mem_rsp_valid),
        .mem_rsp_ready   (mem_rsp_ready),
        .mem_rsp_rdata   (mem_rsp_rdata),
        .mem_rsp_error   (mem_rsp_error),
        .if_pc           (if_pc),
        .if_pc_next      (if_pc_next),
        .if_inst         (if_inst),
        .if_fetch_fault  (if_fetch_fault),
        .if_valid        (if_valid)
    );

    //------------------------------------------------------------------
    // I-memory: 16 KiB (4096 words). Indexed by addr[13:2].
    // 1-cycle read latency. Errors on err_addr if enabled.
    //------------------------------------------------------------------
    reg [31:0] imem [0:4095];
    reg        err_addr_valid;
    reg [31:0] err_addr;

    assign mem_req_ready = 1'b1;

    reg        rsp_valid_r;
    reg [31:0] rsp_data_r;
    reg        rsp_error_r;

    assign mem_rsp_valid = rsp_valid_r;
    assign mem_rsp_rdata = rsp_data_r;
    assign mem_rsp_error = rsp_error_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid_r <= 1'b0;
            rsp_data_r  <= 32'b0;
            rsp_error_r <= 1'b0;
        end else begin
            if (rsp_valid_r && mem_rsp_ready)
                rsp_valid_r <= 1'b0;
            if (mem_req_valid && mem_req_ready) begin
                rsp_data_r  <= imem[mem_req_addr[13:2]];
                rsp_error_r <= err_addr_valid && (mem_req_addr == err_addr);
                rsp_valid_r <= 1'b1;
            end
        end
    end

    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1)
            imem[i] = 32'h0000_0013;   // NOP default
    end

    //------------------------------------------------------------------
    // Helpers
    //------------------------------------------------------------------
    task wait_valid;
        input [255:0] label;
        integer timeout;
        begin
            timeout = 0;
            while (!if_valid && timeout < 200) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            tests_run = tests_run + 1;
            if (!if_valid) begin
                $display("FAIL [%0s] timeout waiting for if_valid", label);
                errors = errors + 1;
            end
        end
    endtask

    task expect_insn;
        input [31:0]  exp_pc;
        input [31:0]  exp_inst;
        input         exp_fault;
        input [255:0] label;
        begin
            tests_run = tests_run + 1;
            if (if_pc !== exp_pc) begin
                $display("FAIL [%0s] pc got=%h exp=%h", label, if_pc, exp_pc);
                errors = errors + 1;
            end
            if (if_inst !== exp_inst) begin
                $display("FAIL [%0s] inst got=%h exp=%h", label, if_inst, exp_inst);
                errors = errors + 1;
            end
            if (if_fetch_fault !== exp_fault) begin
                $display("FAIL [%0s] fault got=%b exp=%b",
                         label, if_fetch_fault, exp_fault);
                errors = errors + 1;
            end
        end
    endtask

    task next_valid;
        input [255:0] label;
        begin
            @(negedge clk);
            wait_valid(label);
        end
    endtask

    //------------------------------------------------------------------
    // Directed sequence
    //------------------------------------------------------------------
    task run_directed;
        begin
            imem[32'h1000 >> 2] = 32'h00A00093;   // addi x1, x0, 10
            imem[32'h1004 >> 2] = 32'h00B00113;   // addi x2, x0, 11
            imem[32'h1008 >> 2] = 32'h003100B3;   // add x1, x2, x3
            imem[32'h100C >> 2] = 32'h0001_0001;  // two C.NOPs
            imem[32'h1010 >> 2] = 32'h0001_0001;  // two C.NOPs

            wait_valid("first insn");
            expect_insn(32'h0000_1000, 32'h00A00093, 1'b0, "insn1");

            next_valid("second insn");
            expect_insn(32'h0000_1004, 32'h00B00113, 1'b0, "insn2");

            next_valid("third insn");
            expect_insn(32'h0000_1008, 32'h003100B3, 1'b0, "insn3");

            next_valid("4th insn (low half)");
            expect_insn(32'h0000_100C, 32'h0000_0013, 1'b0, "insn4");

            next_valid("5th insn (upper half)");
            expect_insn(32'h0000_100E, 32'h0000_0013, 1'b0, "insn5");

            next_valid("6th insn");
            expect_insn(32'h0000_1010, 32'h0000_0013, 1'b0, "insn6");

            // Redirect to 0x1008
            @(negedge clk);
            redirect        = 1'b1;
            redirect_target = 32'h0000_1008;
            @(negedge clk);
            redirect = 1'b0;
            tests_run = tests_run + 1;
            if (if_valid) begin
                $display("FAIL: if_valid high during redirect");
                errors = errors + 1;
            end

            next_valid("after redirect");
            expect_insn(32'h0000_1008, 32'h003100B3, 1'b0, "redirect target");
        end
    endtask

    //------------------------------------------------------------------
    // Stall test - sample PC and assert stall at the same negedge.
    //------------------------------------------------------------------
        task run_stall_test;
        reg [31:0] pc_before;
        begin
            @(negedge clk);
            wait_valid("stall setup");
            pc_before = if_pc;
            stall     = 1'b1;     // assert before next posedge

            repeat (3) @(posedge clk);

            tests_run = tests_run + 1;
            if (if_pc !== pc_before) begin
                $display("FAIL: PC advanced during stall: got=%h exp=%h",
                         if_pc, pc_before);
                errors = errors + 1;
            end
            tests_run = tests_run + 1;
            if (if_valid) begin
                $display("FAIL: if_valid high during stall");
                errors = errors + 1;
            end

            // Release stall and sample in the SAME cycle, before the next
            // posedge can advance pc_r.
            @(negedge clk);
            stall = 1'b0;
            #1;
            tests_run = tests_run + 1;
            if (!if_valid) begin
                $display("FAIL: if_valid not asserted after stall release");
                errors = errors + 1;
            end
            expect_insn(pc_before, 32'h0000_0013, 1'b0, "resume after stall");
        end
    endtask

    //------------------------------------------------------------------
    // Fault test
    //------------------------------------------------------------------
    task run_fault_test;
        begin
            err_addr            = 32'h0000_2000;
            err_addr_valid      = 1'b1;
            imem[32'h2000 >> 2] = 32'h00A00093;

            @(negedge clk);
            redirect        = 1'b1;
            redirect_target = 32'h0000_2000;
            @(negedge clk);
            redirect = 1'b0;

            wait_valid("fault fetch");
            tests_run = tests_run + 1;
            if (if_pc !== 32'h0000_2000) begin
                $display("FAIL fault pc: got=%h exp=00002000", if_pc);
                errors = errors + 1;
            end
            tests_run = tests_run + 1;
            if (!if_fetch_fault) begin
                $display("FAIL: fetch_fault not asserted on mem error");
                errors = errors + 1;
            end

            err_addr_valid = 1'b0;
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_if_stage);

        errors         = 0;
        tests_run      = 0;
        stall          = 1'b0;
        redirect       = 1'b0;
        redirect_target= 32'b0;
        err_addr_valid = 1'b0;
        err_addr       = 32'b0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_stall_test;
        run_fault_test;

        $display("---------------------------------------------");
        $display("tb_if_stage: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_if_stage");
        else
            $display("TEST FAILED: tb_if_stage %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_if_stage timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire