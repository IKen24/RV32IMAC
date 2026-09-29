//=============================================================================
// Module:      tb_amo_unit
// File:        sim/tb/tb_amo_unit.v
// Description: Self-checking TB for amo_unit.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_amo_unit;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 100000;
    localparam integer MEM_WORDS  = 1024;
    localparam [31:0]  SEED       = 32'hA70A_1234;

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
    reg         start;
    reg  [4:0]  op;
    reg         is_lr, is_sc;
    reg  [31:0] req_addr, req_wdata;

    wire        mem_req_valid;
    wire        mem_req_ready;
    wire [31:0] mem_req_addr;
    wire [31:0] mem_req_wdata;
    wire [3:0]  mem_req_wstrb;
    wire        mem_req_write;
    wire [1:0]  mem_req_size;
    wire        mem_req_atomic;
    wire        mem_rsp_valid;
    wire        mem_rsp_ready;
    wire [31:0] mem_rsp_rdata;
    wire        mem_rsp_error;

    wire [31:0] result;
    wire        busy, done, error;

    integer errors;
    integer tests_run;
    integer rng_seed;
    integer rng_dummy;

    amo_unit dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .op             (op),
        .is_lr          (is_lr),
        .is_sc          (is_sc),
        .req_addr       (req_addr),
        .req_wdata      (req_wdata),
        .mem_req_valid  (mem_req_valid),
        .mem_req_ready  (mem_req_ready),
        .mem_req_addr   (mem_req_addr),
        .mem_req_wdata  (mem_req_wdata),
        .mem_req_wstrb  (mem_req_wstrb),
        .mem_req_write  (mem_req_write),
        .mem_req_size   (mem_req_size),
        .mem_req_atomic (mem_req_atomic),
        .mem_rsp_valid  (mem_rsp_valid),
        .mem_rsp_ready  (mem_rsp_ready),
        .mem_rsp_rdata  (mem_rsp_rdata),
        .mem_rsp_error  (mem_rsp_error),
        .result         (result),
        .busy           (busy),
        .done           (done),
        .error          (error)
    );

    //------------------------------------------------------------------
    // Synchronous memory model (1-cycle latency, always-ready)
    //------------------------------------------------------------------
    reg [31:0] mem [0:MEM_WORDS-1];
    reg        rsp_valid_r;
    reg [31:0] rsp_data_r;

    assign mem_req_ready = 1'b1;
    assign mem_rsp_valid = rsp_valid_r;
    assign mem_rsp_rdata = rsp_data_r;
    assign mem_rsp_error = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid_r <= 1'b0;
            rsp_data_r  <= 32'b0;
        end else begin
            rsp_valid_r <= 1'b0;
            if (mem_req_valid && mem_req_ready) begin
                if (mem_req_write) begin
                    mem[mem_req_addr[11:2]] <= mem_req_wdata;
                    rsp_valid_r             <= 1'b1;
                end else begin
                    rsp_data_r  <= mem[mem_req_addr[11:2]];
                    rsp_valid_r <= 1'b1;
                end
            end
        end
    end

    integer i;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1)
            mem[i] = 32'b0;
    end

    //------------------------------------------------------------------
    // Driver
    //------------------------------------------------------------------
    integer wait_cnt;

    task drive_amo;
        input [4:0]  op_in;
        input        lr_in, sc_in;
        input [31:0] addr_in, data_in;
        begin
            @(negedge clk);
            op        = op_in;
            is_lr     = lr_in;
            is_sc     = sc_in;
            req_addr  = addr_in;
            req_wdata = data_in;
            start     = 1'b1;
            @(negedge clk);
            start     = 1'b0;

            wait_cnt = 0;
            while (!done && wait_cnt < 50) begin
                @(negedge clk);
                wait_cnt = wait_cnt + 1;
            end
            if (!done) begin
                $display("FAIL: amo timeout op=%0d", op_in);
                errors = errors + 1;
            end
            @(negedge clk);
        end
    endtask

    task check_amo;
        input [4:0]   op_in;
        input         lr_in, sc_in;
        input [31:0]  addr_in, data_in;
        input [31:0]  exp_result;
        input [31:0]  exp_mem;
        input         exp_error;
        input [255:0] label;
        reg [31:0]    got_mem;
        begin
            drive_amo(op_in, lr_in, sc_in, addr_in, data_in);
            tests_run = tests_run + 1;
            if (result !== exp_result) begin
                $display("FAIL [%0s] result got=%h exp=%h",
                         label, result, exp_result);
                errors = errors + 1;
            end
            if (error !== exp_error) begin
                $display("FAIL [%0s] error got=%b exp=%b",
                         label, error, exp_error);
                errors = errors + 1;
            end
            got_mem = mem[addr_in[11:2]];
            if (got_mem !== exp_mem) begin
                $display("FAIL [%0s] mem[%h] got=%h exp=%h",
                         label, addr_in, got_mem, exp_mem);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Directed tests
    //------------------------------------------------------------------
    task run_directed;
        begin
            // ---- LR: loads value, sets reservation ----
            mem[32'h100 >> 2] = 32'hDEAD_BEEF;
            check_amo(`FUNCT5_LR, 1'b1, 1'b0,
                      32'h100, 32'h0,
                      32'hDEAD_BEEF, 32'hDEAD_BEEF, 1'b0, "LR load");

            // ---- SC success to same addr ----
            check_amo(`FUNCT5_SC, 1'b0, 1'b1,
                      32'h100, 32'h1234_5678,
                      32'h0, 32'h1234_5678, 1'b0, "SC success");

            // ---- SC without reservation ----
            check_amo(`FUNCT5_SC, 1'b0, 1'b1,
                      32'h200, 32'hAAA,
                      32'h1, 32'h0, 1'b0, "SC no res -> fail");

            // ---- LR then SC to different addr: fail ----
            mem[32'h300 >> 2] = 32'h1111_1111;
            check_amo(`FUNCT5_LR, 1'b1, 1'b0,
                      32'h300, 32'h0,
                      32'h1111_1111, 32'h1111_1111, 1'b0, "LR 0x300");
            check_amo(`FUNCT5_SC, 1'b0, 1'b1,
                      32'h400, 32'h9999,
                      32'h1, 32'h0, 1'b0, "SC wrong addr -> fail");

            // ---- LR then AMO to same addr invalidates reservation ----
            mem[32'h500 >> 2] = 32'hAAAA_AAAA;
            check_amo(`FUNCT5_LR, 1'b1, 1'b0,
                      32'h500, 32'h0,
                      32'hAAAA_AAAA, 32'hAAAA_AAAA, 1'b0, "LR 0x500");
            check_amo(`A_AMOADD, 1'b0, 1'b0,
                      32'h500, 32'h5,
                      32'hAAAA_AAAA, 32'hAAAA_AAAF, 1'b0, "AMOADD hits res");
            check_amo(`FUNCT5_SC, 1'b0, 1'b1,
                      32'h500, 32'h7777,
                      32'h1, 32'hAAAA_AAAF, 1'b0, "SC after AMO -> fail");

            // ---- AMOSWAP ----
            mem[32'h600 >> 2] = 32'hCAFE_BABE;
            check_amo(`A_AMOSWAP, 1'b0, 1'b0,
                      32'h600, 32'h1234_5678,
                      32'hCAFE_BABE, 32'h1234_5678, 1'b0, "AMOSWAP");

            // ---- AMOADD ----
            mem[32'h700 >> 2] = 32'h0000_0005;
            check_amo(`A_AMOADD, 1'b0, 1'b0,
                      32'h700, 32'h0000_000A,
                      32'h0000_0005, 32'h0000_000F, 1'b0, "AMOADD");

            // ---- AMOXOR ----
            mem[32'h800 >> 2] = 32'hFFFF_0000;
            check_amo(`A_AMOXOR, 1'b0, 1'b0,
                      32'h800, 32'h0000_FFFF,
                      32'hFFFF_0000, 32'hFFFF_FFFF, 1'b0, "AMOXOR");

            // ---- AMOAND ----
            mem[32'h900 >> 2] = 32'hFFFF_FFFF;
            check_amo(`A_AMOAND, 1'b0, 1'b0,
                      32'h900, 32'h0F0F_0F0F,
                      32'hFFFF_FFFF, 32'h0F0F_0F0F, 1'b0, "AMOAND");

            // ---- AMOOR ----
            mem[32'hA00 >> 2] = 32'h0F0F_0F0F;
            check_amo(`A_AMOOR, 1'b0, 1'b0,
                      32'hA00, 32'hF0F0_F0F0,
                      32'h0F0F_0F0F, 32'hFFFF_FFFF, 1'b0, "AMOOR");

            // ---- AMOMIN signed: -1 vs 1 ----
            mem[32'hB00 >> 2] = 32'hFFFF_FFFF;
            check_amo(`A_AMOMIN, 1'b0, 1'b0,
                      32'hB00, 32'h0000_0001,
                      32'hFFFF_FFFF, 32'hFFFF_FFFF, 1'b0, "AMOMIN -1,1");

            mem[32'hB10 >> 2] = 32'h0000_0005;
            check_amo(`A_AMOMIN, 1'b0, 1'b0,
                      32'hB10, 32'hFFFF_FFFF,
                      32'h0000_0005, 32'hFFFF_FFFF, 1'b0, "AMOMIN 5,-1");

            // ---- AMOMAX signed ----
            mem[32'hB20 >> 2] = 32'hFFFF_FFFF;
            check_amo(`A_AMOMAX, 1'b0, 1'b0,
                      32'hB20, 32'h0000_0001,
                      32'hFFFF_FFFF, 32'h0000_0001, 1'b0, "AMOMAX -1,1");

            // ---- AMOMINU ----
            mem[32'hB30 >> 2] = 32'hFFFF_FFFF;
            check_amo(`A_AMOMINU, 1'b0, 1'b0,
                      32'hB30, 32'h0000_0001,
                      32'hFFFF_FFFF, 32'h0000_0001, 1'b0, "AMOMINU");

            // ---- AMOMAXU ----
            mem[32'hB40 >> 2] = 32'h0000_0001;
            check_amo(`A_AMOMAXU, 1'b0, 1'b0,
                      32'hB40, 32'hFFFF_FFFF,
                      32'h0000_0001, 32'hFFFF_FFFF, 1'b0, "AMOMAXU");
        end
    endtask

    //------------------------------------------------------------------
    // Busy/done handshake check
    //------------------------------------------------------------------
    task run_handshake;
        begin
            @(negedge clk);
            op        = `A_AMOADD;
            is_lr     = 1'b0;
            is_sc     = 1'b0;
            req_addr  = 32'hC00;
            req_wdata = 32'h1;
            start     = 1'b1;
            @(negedge clk);
            start     = 1'b0;

            tests_run = tests_run + 1;
            if (!busy) begin
                $display("FAIL: busy not asserted after start");
                errors = errors + 1;
            end

            wait_cnt = 0;
            while (!done && wait_cnt < 50) begin
                @(negedge clk);
                wait_cnt = wait_cnt + 1;
            end
            @(negedge clk);
            tests_run = tests_run + 1;
            if (busy) begin
                $display("FAIL: busy still high one cycle after done");
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Random AMO cross-check
    //------------------------------------------------------------------
    integer k;
    reg [4:0]  r_op;
    reg [31:0] r_a, r_b;
    reg [31:0] old_val_r;
    reg [31:0] exp_res;
    reg [31:0] exp_mem;

    function [31:0] ref_amo;
        input [4:0]  op_f;
        input [31:0] a, b;
        begin
            case (op_f)
                `A_AMOSWAP: ref_amo = b;
                `A_AMOADD:  ref_amo = a + b;
                `A_AMOXOR:  ref_amo = a ^ b;
                `A_AMOAND:  ref_amo = a & b;
                `A_AMOOR:   ref_amo = a | b;
                `A_AMOMIN:  ref_amo = ($signed(a) < $signed(b)) ? a : b;
                `A_AMOMAX:  ref_amo = ($signed(a) > $signed(b)) ? a : b;
                `A_AMOMINU: ref_amo = (a < b) ? a : b;
                `A_AMOMAXU: ref_amo = (a > b) ? a : b;
                default:    ref_amo = b;
            endcase
        end
    endfunction

    task run_random;
        integer sel;
        begin
            for (k = 0; k < 100; k = k + 1) begin
                r_a = $urandom;
                r_b = $urandom;
                sel = $urandom_range(0, 8);
                case (sel)
                    0: r_op = `A_AMOADD;
                    1: r_op = `A_AMOSWAP;
                    2: r_op = `A_AMOXOR;
                    3: r_op = `A_AMOAND;
                    4: r_op = `A_AMOOR;
                    5: r_op = `A_AMOMIN;
                    6: r_op = `A_AMOMAX;
                    7: r_op = `A_AMOMINU;
                    8: r_op = `A_AMOMAXU;
                    default: r_op = `A_AMOADD;
                endcase

                // Preload memory with old value
                mem[r_a[11:2]] = r_b;
                old_val_r = r_b;

                // Incoming value for the AMO
                r_b = $urandom;

                exp_res = old_val_r;
                exp_mem = ref_amo(r_op, old_val_r, r_b);

                check_amo(r_op, 1'b0, 1'b0,
                          r_a, r_b,
                          exp_res, exp_mem, 1'b0, "RAND AMO");
            end
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_amo_unit);

        errors    = 0;
        tests_run = 0;
        start     = 1'b0;
        op        = 5'b0;
        is_lr     = 1'b0;
        is_sc     = 1'b0;
        req_addr  = 32'b0;
        req_wdata = 32'b0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_handshake;
        run_random;

        $display("---------------------------------------------");
        $display("tb_amo_unit: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_amo_unit");
        else
            $display("TEST FAILED: tb_amo_unit %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_amo_unit timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire