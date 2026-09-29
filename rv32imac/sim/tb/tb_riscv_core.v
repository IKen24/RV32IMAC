//=============================================================================
// Module:      tb_riscv_core
// File:        sim/tb/tb_riscv_core.v
// Description: Integration TB for riscv_core. DEBUG build.
//              Prints every D-memory access and every register retire.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_riscv_core;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 5000;
    localparam integer MEM_WORDS  = 4096;
    localparam [31:0]  SEED       = 32'hC0DE_C0DE;

    reg clk, rst_n;
    integer cycles;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycles <= 0;
        else        cycles <= cycles + 1;
    end

    wire        imem_req_valid;
    wire        imem_req_ready;
    wire [31:0] imem_req_addr;
    wire        imem_rsp_valid;
    wire        imem_rsp_ready;
    wire [31:0] imem_rsp_rdata;
    wire        imem_rsp_error;

    wire        dmem_req_valid;
    wire        dmem_req_ready;
    wire [31:0] dmem_req_addr;
    wire [31:0] dmem_req_wdata;
    wire [3:0]  dmem_req_wstrb;
    wire        dmem_req_write;
    wire [1:0]  dmem_req_size;
    wire        dmem_req_atomic;
    wire        dmem_rsp_valid;
    wire        dmem_rsp_ready;
    wire [31:0] dmem_rsp_rdata;
    wire        dmem_rsp_error;

    wire [1:0]  current_priv;
    wire        retire;
    wire [31:0] pc_out;

    integer errors, tests_run;
    integer rng_seed, rng_dummy;

    riscv_core dut (
        .clk(clk), .rst_n(rst_n),
        .imem_req_valid(imem_req_valid),
        .imem_req_ready(imem_req_ready),
        .imem_req_addr(imem_req_addr),
        .imem_rsp_valid(imem_rsp_valid),
        .imem_rsp_ready(imem_rsp_ready),
        .imem_rsp_rdata(imem_rsp_rdata),
        .imem_rsp_error(imem_rsp_error),
        .dmem_req_valid(dmem_req_valid),
        .dmem_req_ready(dmem_req_ready),
        .dmem_req_addr(dmem_req_addr),
        .dmem_req_wdata(dmem_req_wdata),
        .dmem_req_wstrb(dmem_req_wstrb),
        .dmem_req_write(dmem_req_write),
        .dmem_req_size(dmem_req_size),
        .dmem_req_atomic(dmem_req_atomic),
        .dmem_rsp_valid(dmem_rsp_valid),
        .dmem_rsp_ready(dmem_rsp_ready),
        .dmem_rsp_rdata(dmem_rsp_rdata),
        .dmem_rsp_error(dmem_rsp_error),
        .timer_irq(1'b0),
        .ext_irq(1'b0),
        .current_priv(current_priv),
        .retire(retire),
        .pc_out(pc_out)
    );

    //------------------------------------------------------------------
    // Debug traces
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.wb_rf_we)
                $display("T=%0d RETIRE pc=%h rd=%0d data=%h sel=%b",
                         cycles, dut.wb_pc, dut.wb_rf_rd_addr,
                         dut.wb_rf_rd_data, dut.wb_sel);
            if (dmem_req_valid && dmem_req_ready)
                $display("T=%0d %0s addr=%h data=%h strb=%b",
                         cycles, dmem_req_write ? "DWRITE" : "DREAD ",
                         dmem_req_addr, dmem_req_wdata, dmem_req_wstrb);
        end
    end

    //------------------------------------------------------------------
    // Shared memory
    //------------------------------------------------------------------
    reg [31:0] mem [0:MEM_WORDS-1];

    assign imem_req_ready = 1'b1;
    assign dmem_req_ready = 1'b1;

    reg        imem_rsp_valid_r;
    reg [31:0] imem_rsp_rdata_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_rsp_valid_r <= 1'b0;
            imem_rsp_rdata_r <= 32'b0;
        end else begin
            if (imem_req_valid && imem_req_ready) begin
                imem_rsp_rdata_r <= mem[imem_req_addr[13:2]];
                imem_rsp_valid_r <= 1'b1;
            end else if (imem_rsp_valid_r && imem_rsp_ready) begin
                imem_rsp_valid_r <= 1'b0;
            end
        end
    end

    assign imem_rsp_valid = imem_rsp_valid_r;
    assign imem_rsp_rdata = imem_rsp_rdata_r;
    assign imem_rsp_error = 1'b0;

    reg        dmem_rsp_valid_r;
    reg [31:0] dmem_rsp_rdata_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_rsp_valid_r <= 1'b0;
            dmem_rsp_rdata_r <= 32'b0;
        end else begin
            if (dmem_req_valid && dmem_req_ready) begin
                dmem_rsp_rdata_r <= mem[dmem_req_addr[13:2]];
                dmem_rsp_valid_r <= 1'b1;
                if (dmem_req_write) begin
                    if (dmem_req_wstrb[0]) mem[dmem_req_addr[13:2]][7:0]   <= dmem_req_wdata[7:0];
                    if (dmem_req_wstrb[1]) mem[dmem_req_addr[13:2]][15:8]  <= dmem_req_wdata[15:8];
                    if (dmem_req_wstrb[2]) mem[dmem_req_addr[13:2]][23:16] <= dmem_req_wdata[23:16];
                    if (dmem_req_wstrb[3]) mem[dmem_req_addr[13:2]][31:24] <= dmem_req_wdata[31:24];
                end
            end else if (dmem_rsp_valid_r && dmem_rsp_ready) begin
                dmem_rsp_valid_r <= 1'b0;
            end
        end
    end

    assign dmem_rsp_valid = dmem_rsp_valid_r;
    assign dmem_rsp_rdata = dmem_rsp_rdata_r;
    assign dmem_rsp_error = 1'b0;

    integer i;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1)
            mem[i] = 32'h00000013;

        mem[32'h1000 >> 2] = 32'h00500093;
        mem[32'h1004 >> 2] = 32'h00700113;
        mem[32'h1008 >> 2] = 32'h002081B3;
        mem[32'h100C >> 2] = 32'h00302023;
        mem[32'h1010 >> 2] = 32'h00002203;
        mem[32'h1014 >> 2] = 32'h00402223;
        mem[32'h1018 >> 2] = 32'h0000006F;
    end

    integer timeout;

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_riscv_core);

        errors    = 0;
        tests_run = 0;
        rst_n     = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        timeout = 0;
        while (pc_out !== 32'h0000_1018 && timeout < MAX_CYCLES) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        tests_run = tests_run + 1;
        if (timeout >= MAX_CYCLES) begin
            $display("FAIL: timeout waiting for program to reach 0x1018");
            errors = errors + 1;
        end

        repeat (20) @(posedge clk);

        $display("--- mem[0]=%0d (0x%h)  mem[1]=%0d (0x%h) ---",
                 mem[0], mem[0], mem[1], mem[1]);

        tests_run = tests_run + 1;
        if (mem[0] !== 32'd12) begin
            $display("FAIL: mem[0] = %0d, expected 12", mem[0]);
            errors = errors + 1;
        end

        tests_run = tests_run + 1;
        if (mem[1] !== 32'd12) begin
            $display("FAIL: mem[1] = %0d, expected 12", mem[1]);
            errors = errors + 1;
        end

        $display("---------------------------------------------");
        $display("tb_riscv_core: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0) $display("TEST PASSED: tb_riscv_core");
        else             $display("TEST FAILED: tb_riscv_core %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES * 4)
            $fatal(1, "TEST FAILED: tb_riscv_core global timeout");
    end

endmodule

`default_nettype wire