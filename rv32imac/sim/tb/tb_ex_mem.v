//=============================================================================
// Module:      tb_ex_mem
// File:        sim/tb/tb_ex_mem.v
// Description: Self-checking TB for ex_mem.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_ex_mem;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 100000;
    localparam integer NUM_RANDOM = 300;
    localparam [31:0]  SEED       = 32'hE5E5_1234;

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
    reg [201:0] in_packed;

    wire [31:0] ex_pc          = in_packed[31:0];
    wire [31:0] ex_pc_next     = in_packed[63:32];
    wire [31:0] ex_alu_result  = in_packed[95:64];
    wire [31:0] ex_store_data  = in_packed[127:96];
    wire [31:0] ex_csr_wdata   = in_packed[159:128];
    wire [11:0] ex_csr_addr    = in_packed[171:160];
    wire [4:0]  ex_rd_addr     = in_packed[176:172];
    wire [1:0]  ex_mem_size    = in_packed[178:177];
    wire [1:0]  ex_wb_sel      = in_packed[180:179];
    wire [1:0]  ex_csr_op      = in_packed[182:181];
    wire [3:0]  ex_sys_op      = in_packed[186:183];
    wire [4:0]  ex_amo_op      = in_packed[191:187];
    wire        ex_mem_read    = in_packed[192];
    wire        ex_mem_write   = in_packed[193];
    wire        ex_mem_unsigned= in_packed[194];
    wire        ex_reg_write   = in_packed[195];
    wire        ex_csr_we      = in_packed[196];
    wire        ex_atomic_sel  = in_packed[197];
    wire        ex_is_lr       = in_packed[198];
    wire        ex_is_sc       = in_packed[199];
    wire        ex_illegal     = in_packed[200];
    wire        ex_fetch_fault = in_packed[201];

    reg         stall, flush;

    //------------------------------------------------------------------
    // DUT outputs
    //------------------------------------------------------------------
    wire [31:0] mem_pc, mem_pc_next, mem_alu_result, mem_store_data, mem_csr_wdata;
    wire [11:0] mem_csr_addr;
    wire [4:0]  mem_rd_addr, mem_amo_op;
    wire [1:0]  mem_size, mem_wb_sel, mem_csr_op;
    wire [3:0]  mem_sys_op;
    wire        mem_read, mem_write, mem_unsigned, mem_reg_write;
    wire        mem_csr_we, mem_atomic_sel, mem_is_lr, mem_is_sc;
    wire        mem_illegal, mem_fetch_fault;

    ex_mem dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .stall            (stall),
        .flush            (flush),
        .ex_pc            (ex_pc),
        .ex_pc_next       (ex_pc_next),
        .ex_alu_result    (ex_alu_result),
        .ex_store_data    (ex_store_data),
        .ex_csr_wdata     (ex_csr_wdata),
        .ex_csr_addr      (ex_csr_addr),
        .ex_rd_addr       (ex_rd_addr),
        .ex_mem_read      (ex_mem_read),
        .ex_mem_write     (ex_mem_write),
        .ex_mem_size      (ex_mem_size),
        .ex_mem_unsigned  (ex_mem_unsigned),
        .ex_wb_sel        (ex_wb_sel),
        .ex_reg_write     (ex_reg_write),
        .ex_csr_we        (ex_csr_we),
        .ex_csr_op        (ex_csr_op),
        .ex_sys_op        (ex_sys_op),
        .ex_atomic_sel    (ex_atomic_sel),
        .ex_amo_op        (ex_amo_op),
        .ex_is_lr         (ex_is_lr),
        .ex_is_sc         (ex_is_sc),
        .ex_illegal       (ex_illegal),
        .ex_fetch_fault   (ex_fetch_fault),
        .mem_pc           (mem_pc),
        .mem_pc_next      (mem_pc_next),
        .mem_alu_result   (mem_alu_result),
        .mem_store_data   (mem_store_data),
        .mem_csr_wdata    (mem_csr_wdata),
        .mem_csr_addr     (mem_csr_addr),
        .mem_rd_addr      (mem_rd_addr),
        .mem_read         (mem_read),
        .mem_write        (mem_write),
        .mem_size         (mem_size),
        .mem_unsigned     (mem_unsigned),
        .mem_wb_sel       (mem_wb_sel),
        .mem_reg_write    (mem_reg_write),
        .mem_csr_we       (mem_csr_we),
        .mem_csr_op       (mem_csr_op),
        .mem_sys_op       (mem_sys_op),
        .mem_atomic_sel   (mem_atomic_sel),
        .mem_amo_op       (mem_amo_op),
        .mem_is_lr        (mem_is_lr),
        .mem_is_sc        (mem_is_sc),
        .mem_illegal      (mem_illegal),
        .mem_fetch_fault  (mem_fetch_fault)
    );

    //------------------------------------------------------------------
    // Repack outputs to match in_packed field order
    //------------------------------------------------------------------
    wire [201:0] got;
    assign got = {
        mem_fetch_fault,
        mem_illegal,
        mem_is_sc,
        mem_is_lr,
        mem_atomic_sel,
        mem_csr_we,
        mem_reg_write,
        mem_unsigned,
        mem_write,
        mem_read,
        mem_amo_op,
        mem_sys_op,
        mem_csr_op,
        mem_wb_sel,
        mem_size,
        mem_rd_addr,
        mem_csr_addr,
        mem_csr_wdata,
        mem_store_data,
        mem_alu_result,
        mem_pc_next,
        mem_pc
    };

    //------------------------------------------------------------------
    // Shadow
    //------------------------------------------------------------------
    reg [201:0] sh_packed;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        sh_packed <= 202'b0;
        else if (flush)    sh_packed <= 202'b0;
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
        reg [201:0] pat;
        begin
            // Reset state
            check("reset zero");

            // Build a distinctive pattern
            pat = 202'b0;
            pat[31:0]    = 32'hDEAD_BEEF;    // pc
            pat[63:32]   = 32'hCAFE_F00D;    // pc_next
            pat[95:64]   = 32'h1111_2222;    // alu_result
            pat[127:96]  = 32'h3333_4444;    // store_data
            pat[159:128] = 32'h5555_6666;    // csr_wdata
            pat[171:160] = 12'h800;          // csr_addr
            pat[176:172] = 5'd31;            // rd_addr
            pat[178:177] = 2'b01;            // mem_size
            pat[180:179] = 2'b10;            // wb_sel
            pat[182:181] = 2'b11;            // csr_op
            pat[186:183] = 4'hA;             // sys_op
            pat[191:187] = 5'h1C;            // amo_op
            pat[192]     = 1'b1;
            pat[193]     = 1'b1;
            pat[194]     = 1'b1;
            pat[195]     = 1'b1;
            pat[196]     = 1'b1;
            pat[197]     = 1'b1;
            pat[198]     = 1'b1;
            pat[199]     = 1'b1;
            pat[200]     = 1'b1;
            pat[201]     = 1'b1;

            // Capture
            @(negedge clk);
            in_packed = pat;
            stall = 1'b0;
            flush = 1'b0;
            @(negedge clk);
            check("capture pattern");

            // Stall holds
            @(negedge clk);
            in_packed = ~pat;
            stall = 1'b1;
            flush = 1'b0;
            @(negedge clk);
            check("stall holds");
            stall = 1'b0;

            // Capture complement
            @(negedge clk);
            in_packed = ~pat;
            stall = 1'b0;
            flush = 1'b0;
            @(negedge clk);
            check("capture complement");

            // Flush zeroes
            @(negedge clk);
            in_packed = pat;
            stall = 1'b0;
            flush = 1'b1;
            @(negedge clk);
            flush = 1'b0;
            check("flush zero");

            // Capture after flush
            @(negedge clk);
            in_packed = pat;
            stall = 1'b0;
            flush = 1'b0;
            @(negedge clk);
            check("capture after flush");

            // Flush priority over stall
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
                             $urandom, $urandom, $urandom, $urandom};
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
        $dumpvars(0, tb_ex_mem);

        errors    = 0;
        tests_run = 0;
        in_packed = 202'b0;
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
        $display("tb_ex_mem: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_ex_mem");
        else
            $display("TEST FAILED: tb_ex_mem %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_ex_mem timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire