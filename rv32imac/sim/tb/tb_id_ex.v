//=============================================================================
// Module:      tb_id_ex
// File:        sim/tb/tb_id_ex.v
// Description: Self-checking TB for id_ex.
//   - Reset state = all zeros
//   - Capture of a distinctive pattern
//   - Stall holds
//   - Flush zeroes everything (bubble)
//   - Flush has priority over stall
//   - Random capture / stall / flush cross-check
//
//   Field packing (LSB first):
//     [31:0]   pc
//     [63:32]  pc_next
//     [95:64]  rs1_data
//     [127:96] rs2_data
//     [159:128] imm
//     [191:160] csr_wdata
//     [196:192] rs1_addr
//     [201:197] rs2_addr
//     [206:202] rd_addr
//     [218:207] csr_addr
//     [223:219] alu_op
//     [225:224] mem_size
//     [227:226] wb_sel
//     [230:228] branch_funct3
//     [232:231] csr_op
//     [236:233] sys_op
//     [240:237] muldiv_op
//     [245:241] amo_op
//     [246] fetch_fault
//     [247] alu_src_a
//     [248] alu_src_b
//     [249] reg_write
//     [250] use_rs1
//     [251] use_rs2
//     [252] branch
//     [253] jump
//     [254] mem_read
//     [255] mem_write
//     [256] mem_unsigned
//     [257] csr_we
//     [258] atomic_sel
//     [259] is_lr
//     [260] is_sc
//     [261] muldiv_sel
//     [262] illegal
//   Total = 263 bits
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_id_ex;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 100000;
    localparam integer NUM_RANDOM = 300;
    localparam [31:0]  SEED       = 32'h1DEx_ABCD;  // 0x1DEx invalid -> replaced
    // Correct seed below:
    // localparam [31:0] SEED = 32'h1DEE_ABCD;

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
    // Packed input register. Drives all id_* signals via continuous
    // assignments so tests can write one wide word.
    //------------------------------------------------------------------
    reg [262:0] in_packed;

    wire [31:0] id_pc          = in_packed[31:0];
    wire [31:0] id_pc_next     = in_packed[63:32];
    wire [31:0] id_rs1_data    = in_packed[95:64];
    wire [31:0] id_rs2_data    = in_packed[127:96];
    wire [31:0] id_imm         = in_packed[159:128];
    wire [31:0] id_csr_wdata   = in_packed[191:160];
    wire [4:0]  id_rs1_addr    = in_packed[196:192];
    wire [4:0]  id_rs2_addr    = in_packed[201:197];
    wire [4:0]  id_rd_addr     = in_packed[206:202];
    wire [11:0] id_csr_addr    = in_packed[218:207];
    wire [4:0]  id_alu_op      = in_packed[223:219];
    wire [1:0]  id_mem_size    = in_packed[225:224];
    wire [1:0]  id_wb_sel      = in_packed[227:226];
    wire [2:0]  id_branch_f3   = in_packed[230:228];
    wire [1:0]  id_csr_op      = in_packed[232:231];
    wire [3:0]  id_sys_op      = in_packed[236:233];
    wire [3:0]  id_muldiv_op   = in_packed[240:237];
    wire [4:0]  id_amo_op      = in_packed[245:241];
    wire        id_fetch_fault = in_packed[246];
    wire        id_alu_src_a   = in_packed[247];
    wire        id_alu_src_b   = in_packed[248];
    wire        id_reg_write   = in_packed[249];
    wire        id_use_rs1     = in_packed[250];
    wire        id_use_rs2     = in_packed[251];
    wire        id_branch      = in_packed[252];
    wire        id_jump        = in_packed[253];
    wire        id_mem_read    = in_packed[254];
    wire        id_mem_write   = in_packed[255];
    wire        id_mem_unsigned= in_packed[256];
    wire        id_csr_we      = in_packed[257];
    wire        id_atomic_sel  = in_packed[258];
    wire        id_is_lr       = in_packed[259];
    wire        id_is_sc       = in_packed[260];
    wire        id_muldiv_sel  = in_packed[261];
    wire        id_illegal     = in_packed[262];

    reg         stall, flush;

    //------------------------------------------------------------------
    // DUT outputs
    //------------------------------------------------------------------
    wire [31:0] ex_pc;
    wire [31:0] ex_pc_next;
    wire [31:0] ex_rs1_data;
    wire [31:0] ex_rs2_data;
    wire [31:0] ex_imm;
    wire [31:0] ex_csr_wdata;
    wire [4:0]  ex_rs1_addr;
    wire [4:0]  ex_rs2_addr;
    wire [4:0]  ex_rd_addr;
    wire [11:0] ex_csr_addr;
    wire [4:0]  ex_alu_op;
    wire        ex_alu_src_a;
    wire        ex_alu_src_b;
    wire [2:0]  ex_branch_funct3;
    wire        ex_branch;
    wire        ex_jump;
    wire        ex_use_rs1;
    wire        ex_use_rs2;
    wire        ex_mem_read;
    wire        ex_mem_write;
    wire [1:0]  ex_mem_size;
    wire        ex_mem_unsigned;
    wire [1:0]  ex_wb_sel;
    wire        ex_reg_write;
    wire        ex_csr_we;
    wire [1:0]  ex_csr_op;
    wire [3:0]  ex_sys_op;
    wire        ex_muldiv_sel;
    wire [3:0]  ex_muldiv_op;
    wire        ex_atomic_sel;
    wire [4:0]  ex_amo_op;
    wire        ex_is_lr;
    wire        ex_is_sc;
    wire        ex_illegal;
    wire        ex_fetch_fault;

    id_ex dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .stall            (stall),
        .flush            (flush),
        .id_pc            (id_pc),
        .id_pc_next       (id_pc_next),
        .id_rs1_data      (id_rs1_data),
        .id_rs2_data      (id_rs2_data),
        .id_imm           (id_imm),
        .id_csr_wdata     (id_csr_wdata),
        .id_rs1_addr      (id_rs1_addr),
        .id_rs2_addr      (id_rs2_addr),
        .id_rd_addr       (id_rd_addr),
        .id_csr_addr      (id_csr_addr),
        .id_alu_op        (id_alu_op),
        .id_alu_src_a     (id_alu_src_a),
        .id_alu_src_b     (id_alu_src_b),
        .id_branch_funct3 (id_branch_f3),
        .id_branch        (id_branch),
        .id_jump          (id_jump),
        .id_use_rs1       (id_use_rs1),
        .id_use_rs2       (id_use_rs2),
        .id_mem_read      (id_mem_read),
        .id_mem_write     (id_mem_write),
        .id_mem_size      (id_mem_size),
        .id_mem_unsigned  (id_mem_unsigned),
        .id_wb_sel        (id_wb_sel),
        .id_reg_write     (id_reg_write),
        .id_csr_we        (id_csr_we),
        .id_csr_op        (id_csr_op),
        .id_sys_op        (id_sys_op),
        .id_muldiv_sel    (id_muldiv_sel),
        .id_muldiv_op     (id_muldiv_op),
        .id_atomic_sel    (id_atomic_sel),
        .id_amo_op        (id_amo_op),
        .id_is_lr         (id_is_lr),
        .id_is_sc         (id_is_sc),
        .id_illegal       (id_illegal),
        .id_fetch_fault   (id_fetch_fault),
        .ex_pc            (ex_pc),
        .ex_pc_next       (ex_pc_next),
        .ex_rs1_data      (ex_rs1_data),
        .ex_rs2_data      (ex_rs2_data),
        .ex_imm           (ex_imm),
        .ex_csr_wdata     (ex_csr_wdata),
        .ex_rs1_addr      (ex_rs1_addr),
        .ex_rs2_addr      (ex_rs2_addr),
        .ex_rd_addr       (ex_rd_addr),
        .ex_csr_addr      (ex_csr_addr),
        .ex_alu_op        (ex_alu_op),
        .ex_alu_src_a     (ex_alu_src_a),
        .ex_alu_src_b     (ex_alu_src_b),
        .ex_branch_funct3 (ex_branch_funct3),
        .ex_branch        (ex_branch),
        .ex_jump          (ex_jump),
        .ex_use_rs1       (ex_use_rs1),
        .ex_use_rs2       (ex_use_rs2),
        .ex_mem_read      (ex_mem_read),
        .ex_mem_write     (ex_mem_write),
        .ex_mem_size      (ex_mem_size),
        .ex_mem_unsigned  (ex_mem_unsigned),
        .ex_wb_sel        (ex_wb_sel),
        .ex_reg_write     (ex_reg_write),
        .ex_csr_we        (ex_csr_we),
        .ex_csr_op        (ex_csr_op),
        .ex_sys_op        (ex_sys_op),
        .ex_muldiv_sel    (ex_muldiv_sel),
        .ex_muldiv_op     (ex_muldiv_op),
        .ex_atomic_sel    (ex_atomic_sel),
        .ex_amo_op        (ex_amo_op),
        .ex_is_lr         (ex_is_lr),
        .ex_is_sc         (ex_is_sc),
        .ex_illegal       (ex_illegal),
        .ex_fetch_fault   (ex_fetch_fault)
    );

    //------------------------------------------------------------------
    // Pack DUT outputs in the same field order as in_packed.
    //------------------------------------------------------------------
    wire [262:0] got;
    assign got = {
        ex_illegal,
        ex_muldiv_sel,
        ex_is_sc,
        ex_is_lr,
        ex_atomic_sel,
        ex_csr_we,
        ex_mem_unsigned,
        ex_mem_write,
        ex_mem_read,
        ex_jump,
        ex_branch,
        ex_use_rs2,
        ex_use_rs1,
        ex_reg_write,
        ex_alu_src_b,
        ex_alu_src_a,
        ex_fetch_fault,
        ex_amo_op,
        ex_muldiv_op,
        ex_sys_op,
        ex_csr_op,
        ex_branch_funct3,
        ex_wb_sel,
        ex_mem_size,
        ex_alu_op,
        ex_csr_addr,
        ex_rd_addr,
        ex_rs2_addr,
        ex_rs1_addr,
        ex_csr_wdata,
        ex_imm,
        ex_rs2_data,
        ex_rs1_data,
        ex_pc_next,
        ex_pc
    };

    //------------------------------------------------------------------
    // Shadow
    //------------------------------------------------------------------
    reg [262:0] sh_packed;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)         sh_packed <= 263'b0;
        else if (flush)     sh_packed <= 263'b0;
        else if (!stall)    sh_packed <= in_packed;
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
        reg [262:0] pat;
        begin
            // Reset state check
            check("reset all-zero");

            // Build a distinctive pattern
            pat = 263'b0;
            pat[31:0]    = 32'hDEAD_BEEF;
            pat[63:32]   = 32'hCAFE_F00D;
            pat[95:64]   = 32'h1111_2222;
            pat[127:96]  = 32'h3333_4444;
            pat[159:128] = 32'h5555_6666;
            pat[191:160] = 32'h7777_8888;
            pat[196:192] = 5'd31;
            pat[201:197] = 5'd30;
            pat[206:202] = 5'd29;
            pat[218:207] = 12'h800;
            pat[223:219] = 5'd22;
            pat[225:224] = 2'b01;
            pat[227:226] = 2'b10;
            pat[230:228] = 3'b101;
            pat[232:231] = 2'b11;
            pat[236:233] = 4'hA;
            pat[240:237] = 4'hB;
            pat[245:241] = 5'h1C;
            pat[246]     = 1'b1;
            pat[247]     = 1'b1;
            pat[248]     = 1'b1;
            pat[249]     = 1'b1;
            pat[250]     = 1'b1;
            pat[251]     = 1'b1;
            pat[252]     = 1'b1;
            pat[253]     = 1'b1;
            pat[254]     = 1'b1;
            pat[255]     = 1'b1;
            pat[256]     = 1'b1;
            pat[257]     = 1'b1;
            pat[258]     = 1'b1;
            pat[259]     = 1'b1;
            pat[260]     = 1'b1;
            pat[261]     = 1'b1;
            pat[262]     = 1'b1;

            // Capture
            @(negedge clk);
            in_packed = pat;
            stall = 1'b0;
            flush = 1'b0;
            @(negedge clk);
            check("capture pattern");

            // Stall holds with different data on inputs
            @(negedge clk);
            in_packed = ~pat;
            stall = 1'b1;
            flush = 1'b0;
            @(negedge clk);
            check("stall holds");
            stall = 1'b0;

            // Capture ~pat (inputs still ~pat)
            @(negedge clk);
            in_packed = ~pat;
            stall = 1'b0;
            flush = 1'b0;
            @(negedge clk);
            check("capture complement");

            // Flush -> all zeros
            @(negedge clk);
            in_packed = pat;
            stall = 1'b0;
            flush = 1'b1;
            @(negedge clk);
            flush = 1'b0;
            check("flush -> zero");

            // Capture again after flush
            @(negedge clk);
            in_packed = pat;
            stall = 1'b0;
            flush = 1'b0;
            @(negedge clk);
            check("capture after flush");

            // Flush has priority over stall
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
                in_packed = {$urandom, $urandom, $urandom, $urandom,
                             $urandom, $urandom, $urandom, $urandom,
                             $urandom};
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
        $dumpvars(0, tb_id_ex);

        errors    = 0;
        tests_run = 0;
        in_packed = 263'b0;
        stall     = 1'b0;
        flush     = 1'b0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed  = 32'h1DEE_ABCD;
        rng_dummy = $urandom(rng_seed);

        run_directed;
        run_random;

        $display("---------------------------------------------");
        $display("tb_id_ex: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_id_ex");
        else
            $display("TEST FAILED: tb_id_ex %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_id_ex timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire