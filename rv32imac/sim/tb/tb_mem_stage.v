//=============================================================================
// Module:      tb_mem_stage
// File:        sim/tb/tb_mem_stage.v
// Description: Self-checking TB for mem_stage.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_mem_stage;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 200000;
    localparam integer MEM_WORDS  = 1024;
    localparam [31:0]  SEED       = 32'h3E3E_1111;

    reg clk, rst_n;
    integer cycles;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycles <= 0;
        else        cycles <= cycles + 1;
    end

    reg  [31:0] mem_alu_result;
    reg  [31:0] mem_store_data;
    reg         mem_read, mem_write;
    reg  [1:0]  mem_size;
    reg         mem_unsigned;
    reg         mem_atomic_sel;
    reg  [4:0]  mem_amo_op;
    reg         mem_is_lr, mem_is_sc;

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

    wire [31:0] mem_rdata;
    wire        mem_fault, mem_stall;

    integer errors, tests_run;

    mem_stage dut (
        .clk(clk), .rst_n(rst_n),
        .mem_alu_result(mem_alu_result), .mem_store_data(mem_store_data),
        .mem_read(mem_read), .mem_write(mem_write),
        .mem_size(mem_size), .mem_unsigned(mem_unsigned),
        .mem_atomic_sel(mem_atomic_sel),
        .mem_amo_op(mem_amo_op),
        .mem_is_lr(mem_is_lr), .mem_is_sc(mem_is_sc),
        .dmem_req_valid(dmem_req_valid), .dmem_req_ready(dmem_req_ready),
        .dmem_req_addr(dmem_req_addr), .dmem_req_wdata(dmem_req_wdata),
        .dmem_req_wstrb(dmem_req_wstrb), .dmem_req_write(dmem_req_write),
        .dmem_req_size(dmem_req_size), .dmem_req_atomic(dmem_req_atomic),
        .dmem_rsp_valid(dmem_rsp_valid), .dmem_rsp_ready(dmem_rsp_ready),
        .dmem_rsp_rdata(dmem_rsp_rdata), .dmem_rsp_error(dmem_rsp_error),
        .mem_rdata(mem_rdata), .mem_fault(mem_fault), .mem_stall(mem_stall)
    );

    //------------------------------------------------------------------
    // Synchronous data memory model
    //------------------------------------------------------------------
    reg [31:0] dmem [0:MEM_WORDS-1];
    reg        rsp_valid_r;
    reg [31:0] rsp_data_r;
    reg        rsp_error_r;
    reg        inject_error;

    assign dmem_req_ready = 1'b1;
    assign dmem_rsp_valid = rsp_valid_r;
    assign dmem_rsp_rdata = rsp_data_r;
    assign dmem_rsp_error = rsp_error_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid_r <= 1'b0;
            rsp_data_r  <= 32'b0;
            rsp_error_r <= 1'b0;
        end else begin
            rsp_valid_r <= 1'b0;
            if (dmem_req_valid && dmem_req_ready) begin
                if (dmem_req_write) begin
                    if (dmem_req_wstrb[0])
                        dmem[dmem_req_addr[11:2]][7:0]   <= dmem_req_wdata[7:0];
                    if (dmem_req_wstrb[1])
                        dmem[dmem_req_addr[11:2]][15:8]  <= dmem_req_wdata[15:8];
                    if (dmem_req_wstrb[2])
                        dmem[dmem_req_addr[11:2]][23:16] <= dmem_req_wdata[23:16];
                    if (dmem_req_wstrb[3])
                        dmem[dmem_req_addr[11:2]][31:24] <= dmem_req_wdata[31:24];
                end else begin
                    rsp_data_r <= dmem[dmem_req_addr[11:2]];
                end
                rsp_valid_r <= 1'b1;
                rsp_error_r <= inject_error;
            end
        end
    end

    integer i;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1)
            dmem[i] = 32'b0;
    end

    //------------------------------------------------------------------
    // Helpers
    //------------------------------------------------------------------
    task clear_inputs;
        begin
            mem_alu_result=0; mem_store_data=0;
            mem_read=0; mem_write=0;
            mem_size=2'b10; mem_unsigned=0;
            mem_atomic_sel=0; mem_amo_op=0;
            mem_is_lr=0; mem_is_sc=0;
            inject_error=0;
        end
    endtask

    // Wait for stall to assert, then wait for it to drop.
    task wait_done;
        integer timeout;
        begin
            // Phase 1: wait for stall to rise (handles AMO where busy
            // is only asserted after the first posedge).
            timeout = 0;
            while (!mem_stall && timeout < 10) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            // Phase 2: wait for stall to drop (transaction complete).
            timeout = 0;
            while (mem_stall && timeout < 200) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 200) begin
                $display("FAIL: mem_stall stuck high");
                errors = errors + 1;
            end
        end
    endtask

    task do_load;
        input [31:0]  addr;
        input [1:0]   size;
        input         uns;
        input [31:0]  exp_data;
        input         exp_fault;
        input [255:0] label;
        begin
            @(negedge clk);
            clear_inputs;
            mem_alu_result = addr;
            mem_read       = 1'b1;
            mem_size       = size;
            mem_unsigned   = uns;
            #1;
            wait_done;
            mem_read = 1'b0;   // clear at the same negedge (prevents re-issue)
            tests_run = tests_run + 1;
            if (!exp_fault) begin
                if (mem_rdata !== exp_data) begin
                    $display("FAIL [%0s] mem_rdata got=%h exp=%h",
                             label, mem_rdata, exp_data);
                    errors = errors + 1;
                end
            end
            if (mem_fault !== exp_fault) begin
                $display("FAIL [%0s] mem_fault got=%b exp=%b",
                         label, mem_fault, exp_fault);
                errors = errors + 1;
            end
        end
    endtask

    task do_store;
        input [31:0]  addr;
        input [1:0]   size;
        input [31:0]  data;
        input [255:0] label;
        begin
            @(negedge clk);
            clear_inputs;
            mem_alu_result = addr;
            mem_store_data = data;
            mem_write      = 1'b1;
            mem_size       = size;
            #1;
            wait_done;
            mem_write = 1'b0;   // clear at the same negedge
            tests_run = tests_run + 1;
        end
    endtask

    task check_mem_word;
        input [31:0]  addr;
        input [31:0]  exp;
        input [255:0] label;
        begin
            tests_run = tests_run + 1;
            if (dmem[addr[11:2]] !== exp) begin
                $display("FAIL [%0s] dmem[%h] got=%h exp=%h",
                         label, addr, dmem[addr[11:2]], exp);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Directed
    //------------------------------------------------------------------
    task run_directed;
        begin
            dmem[32'h100 >> 2] = 32'hDEAD_BEEF;

            // ---- LW 0x100 ----
            do_load(32'h100, 2'b10, 1'b0, 32'hDEAD_BEEF, 1'b0, "LW 0x100");

            // ---- Byte loads ----
            do_load(32'h100, 2'b00, 1'b0, 32'hFFFF_FFEF, 1'b0, "LB 0x100");
            do_load(32'h100, 2'b00, 1'b1, 32'h0000_00EF, 1'b0, "LBU 0x100");
            do_load(32'h101, 2'b00, 1'b0, 32'hFFFF_FFBE, 1'b0, "LB 0x101");
            do_load(32'h101, 2'b00, 1'b1, 32'h0000_00BE, 1'b0, "LBU 0x101");
            do_load(32'h102, 2'b00, 1'b0, 32'hFFFF_FFAD, 1'b0, "LB 0x102");
            do_load(32'h103, 2'b00, 1'b0, 32'hFFFF_FFDE, 1'b0, "LB 0x103");

            // ---- Halfword loads ----
            do_load(32'h100, 2'b01, 1'b0, 32'hFFFF_BEEF, 1'b0, "LH 0x100");
            do_load(32'h100, 2'b01, 1'b1, 32'h0000_BEEF, 1'b0, "LHU 0x100");
            do_load(32'h102, 2'b01, 1'b0, 32'hFFFF_DEAD, 1'b0, "LH 0x102");
            do_load(32'h102, 2'b01, 1'b1, 32'h0000_DEAD, 1'b0, "LHU 0x102");

            // ---- Misaligned loads: mem_fault=1, data don't care ----
            do_load(32'h101, 2'b01, 1'b0, 32'h0, 1'b1, "LH misalign");
            do_load(32'h101, 2'b10, 1'b0, 32'h0, 1'b1, "LW misalign");
            do_load(32'h102, 2'b10, 1'b0, 32'h0, 1'b1, "LW misalign 2");

            // ---- Stores ----
            do_store(32'h200, 2'b10, 32'h1234_5678, "SW");
            check_mem_word(32'h200, 32'h1234_5678, "SW verify");

            do_store(32'h204, 2'b01, 32'h0000_ABCD, "SH");
            check_mem_word(32'h204, 32'h0000_ABCD, "SH verify");

            // After SH, word[0x204] = 0x0000ABCD.
            // SB at 0x206 (byte offset 2) sets byte 2 to 0x42, preserving
            // bytes 0-1 -> word becomes 0x0042ABCD.
            do_store(32'h206, 2'b00, 32'h0000_0042, "SB");
            check_mem_word(32'h206, 32'h0042_ABCD, "SB verify");

            // ---- SW, then SB over-write of byte 1 ----
            do_store(32'h208, 2'b10, 32'hFFFF_FFFF, "SW full");
            do_store(32'h209, 2'b00, 32'h0000_0000, "SB over");
            check_mem_word(32'h208, 32'hFFFF_00FF, "SB over verify");

            // ---- Read error ----
            @(negedge clk);
            clear_inputs;
            mem_alu_result = 32'h300;
            mem_read       = 1'b1;
            mem_size       = 2'b10;
            inject_error   = 1'b1;
            #1;
            wait_done;
            mem_read     = 1'b0;
            inject_error = 1'b0;
            tests_run = tests_run + 1;
            if (!mem_fault) begin
                $display("FAIL: read error not flagged");
                errors = errors + 1;
            end

            // ---- No memory op: mem_stall must be 0 ----
            @(negedge clk);
            clear_inputs;
            #1;
            tests_run = tests_run + 1;
            if (mem_stall !== 1'b0) begin
                $display("FAIL: mem_stall high with no mem op");
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // AMO test
    //------------------------------------------------------------------
    task run_amo_test;
        begin
            dmem[32'h400 >> 2] = 32'h0000_0100;

            @(negedge clk);
            clear_inputs;
            mem_alu_result  = 32'h400;
            mem_store_data  = 32'h0000_0010;
            mem_atomic_sel  = 1'b1;
            mem_amo_op      = `A_AMOADD;
            mem_is_lr       = 1'b0;
            mem_is_sc       = 1'b0;
            #1;
            wait_done;

            // Check BEFORE deasserting mem_atomic_sel, so mem_rdata is
            // still sourced from the AMO path.
            tests_run = tests_run + 1;
            if (mem_rdata !== 32'h0000_0100) begin
                $display("FAIL AMOADD result got=%h exp=00000100", mem_rdata);
                errors = errors + 1;
            end
            if (mem_fault) begin
                $display("FAIL AMOADD fault unexpected");
                errors = errors + 1;
            end

            // Clear at the same negedge
            mem_atomic_sel = 1'b0;

            // Verify memory was updated
            tests_run = tests_run + 1;
            if (dmem[32'h400 >> 2] !== 32'h0000_0110) begin
                $display("FAIL AMOADD memory got=%h exp=00000110",
                         dmem[32'h400 >> 2]);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_mem_stage);

        errors    = 0;
        tests_run = 0;
        clear_inputs;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        run_directed;
        run_amo_test;

        $display("---------------------------------------------");
        $display("tb_mem_stage: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0) $display("TEST PASSED: tb_mem_stage");
        else             $display("TEST FAILED: tb_mem_stage %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_mem_stage timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire