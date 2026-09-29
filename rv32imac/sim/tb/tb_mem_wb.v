//=============================================================================
// Module:      tb_mem_wb
// File:        sim/tb/tb_mem_wb.v
// Description: Self-checking TB for mem_wb.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_mem_wb;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 100000;
    localparam integer NUM_RANDOM = 300;
    localparam [31:0]  SEED       = 32'hABAB_5678;

    reg clk, rst_n;
    integer cycles;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycles <= 0;
        else        cycles <= cycles + 1;
    end

    integer errors;
    integer tests_run;
    integer rng_seed;
    integer rng_dummy;

    //------------------------------------------------------------------
    // Packed input
    //------------------------------------------------------------------
    reg [189:0] in_packed;

    wire [31:0] mem_pc         = in_packed[31:0];
    wire [31:0] mem_pc_next    = in_packed[63:32];
    wire [31:0] mem_alu_result = in_packed[95:64];
    wire [31:0] mem_rdata      = in_packed[127:96];
    wire [31:0] mem_csr_wdata  = in_packed[159:128];
    wire [11:0] mem_csr_addr   = in_packed[171:160];
    wire [4:0]  mem_rd_addr    = in_packed[176:172];
    wire [1:0]  mem_wb_sel     = in_packed[178:177];
    wire [1:0]  mem_csr_op     = in_packed[180:179];
    wire [3:0]  mem_sys_op     = in_packed[184:181];
    wire        mem_reg_write  = in_packed[185];
    wire        mem_csr_we     = in_packed[186];
    wire        mem_illegal    = in_packed[187];
    wire        mem_fetch_fault= in_packed[188];
    wire        mem_fault      = in_packed[189];

    reg         stall, flush;

    //------------------------------------------------------------------
    // DUT outputs
    //------------------------------------------------------------------
    wire [31:0] wb_pc, wb_pc_next, wb_alu_result, wb_rdata, wb_csr_wdata;
    wire [11:0] wb_csr_addr;
    wire [4:0]  wb_rd_addr;
    wire [1:0]  wb_sel, wb_csr_op;
    wire [3:0]  wb_sys_op;
    wire        wb_reg_write, wb_csr_we;
    wire        wb_illegal, wb_fetch_fault, wb_mem_fault;

    mem_wb dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .stall            (stall),
        .flush            (flush),
        .mem_pc           (mem_pc),
        .mem_pc_next      (mem_pc_next),
        .mem_alu_result   (mem_alu_result),
        .mem_rdata        (mem_rdata),
        .mem_csr_wdata    (mem_csr_wdata),
        .mem_csr_addr     (mem_csr_addr),
        .mem_rd_addr      (mem_rd_addr),
        .mem_wb_sel       (mem_wb_sel),
        .mem_csr_op       (mem_csr_op),
        .mem_sys_op       (mem_sys_op),
        .mem_reg_write    (mem_reg_write),
        .mem_csr_we       (mem_csr_we),
        .mem_illegal      (mem_illegal),
        .mem_fetch_fault  (mem_fetch_fault),
        .mem_fault        (mem_fault),
        .wb_pc            (wb_pc),
        .wb_pc_next       (wb_pc_next),
        .wb_alu_result    (wb_alu_result),
        .wb_rdata         (wb_rdata),
        .wb_csr_wdata     (wb_csr_wdata),
        .wb_csr_addr      (wb_csr_addr),
        .wb_rd_addr       (wb_rd_addr),
        .wb_sel           (wb_sel),
        .wb_csr_op        (wb_csr_op),
        .wb_sys_op        (wb_sys_op),
        .wb_reg_write     (wb_reg_write),
        .wb_csr_we        (wb_csr_we),
        .wb_illegal       (wb_illegal),
        .wb_fetch_fault   (wb_fetch_fault),
        .wb_mem_fault     (wb_mem_fault)
    );

    //------------------------------------------------------------------
    // Repack
    //------------------------------------------------------------------
    wire [189:0] got;
    assign got = {
        wb_mem_fault,
        wb_fetch_fault,
        wb_illegal,
        wb_csr_we,
        wb_reg_write,
        wb_sys_op,
        wb_csr_op,
        wb_sel,
        wb_rd_addr,
        wb_csr_addr,
        wb_csr_wdata,
        wb_rdata,
        wb_alu_result,
        wb_pc_next,
        wb_pc
    };

    //------------------------------------------------------------------
    // Shadow
    //------------------------------------------------------------------
    reg [189:0] sh_packed;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        sh_packed <= 190'b0;
        else if (flush)    sh_packed <= 190'b0;
        else if (!stall)   sh_packed <= in_packed;
    end

    //------------------------------------------------------------------
    // Check
    //------------------------------------------------------------------
    task check;
        input [255:0] label;
        begin
            tests_run = tests_run + 1;
            if (got !== sh_packed) begin
                $display("FAIL [%0s]", label);
                $display("  got = %0h", got);
                $display("  exp = %0h", sh_packed);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Directed
    //------------------------------------------------------------------
    task run_directed;
        reg [189:0] pat;
        begin
            check("reset zero");

            pat = 190'b0;
            pat[31:0]    = 32'hDEAD_BEEF;
            pat[63:32]   = 32'hCAFE_F00D;
            pat[95:64]   = 32'h1111_2222;
            pat[127:96]  = 32'h3333_4444;
            pat[159:128] = 32'h5555_6666;
            pat[171:160] = 12'h800;
            pat[176:172] = 5'd31;
            pat[178:177] = 2'b10;
            pat[180:179] = 2'b11;
            pat[184:181] = 4'hA;
            pat[185]     = 1'b1;
            pat[186]     = 1'b1;
            pat[187]     = 1'b1;
            pat[188]     = 1'b1;
            pat[189]     = 1'b1;

            @(negedge clk);
            in_packed = pat;
            stall = 1'b0;
            flush = 1'b0;
            @(negedge clk);
            check("capture pattern");

            @(negedge clk);
            in_packed = ~pat;
            stall = 1'b1;
            flush = 1'b0;
            @(negedge clk);
            check("stall holds");
            stall = 1'b0;

            @(negedge clk);
            in_packed = ~pat;
            stall = 1'b0;
            flush = 1'b0;
            @(negedge clk);
            check("capture complement");

            @(negedge clk);
            in_packed = pat;
            stall = 1'b0;
            flush = 1'b1;
            @(negedge clk);
            flush = 1'b0;
            check("flush zero");

            @(negedge clk);
            in_packed = pat;
            stall = 1'b0;
            flush = 1'b0;
            @(negedge clk);
            check("capture after flush");

            @(negedge clk);
            in_packed = ~pat;
            stall = 1'b1;
            flush = 1'b1;
            @(negedge clk);
            stall = 1'b0;
            flush = 1'b0;
            check("flush beats stall");
        end
    endtask

    //------------------------------------------------------------------
    // Random
    //------------------------------------------------------------------
    integer k;
    integer mode;

    task run_random;
        begin
            for (k = 0; k < NUM_RANDOM; k = k + 1) begin
                @(negedge clk);
                in_packed = {$urandom, $urandom, $urandom,
                             $urandom, $urandom, $urandom};
                mode = $urandom_range(0, 3);
                case (mode)
                    0, 1: begin stall = 1'b0; flush = 1'b0; end
                    2:    begin stall = 1'b1; flush = 1'b0; end
                    3:    begin stall = 1'b0; flush = 1'b1; end
                endcase
                @(negedge clk);
                check("RAND");
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
        $dumpvars(0, tb_mem_wb);

        errors    = 0;
        tests_run = 0;
        in_packed = 190'b0;
        stall     = 1'b0;
        flush     = 1'b0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_random;

        $display("---------------------------------------------");
        $display("tb_mem_wb: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_mem_wb");
        else
            $display("TEST FAILED: tb_mem_wb %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_mem_wb timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire