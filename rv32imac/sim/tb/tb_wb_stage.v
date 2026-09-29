//=============================================================================
// Module:      tb_wb_stage
// File:        sim/tb/tb_wb_stage.v
// Description: Self-checking TB for wb_stage.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_wb_stage;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 100000;
    localparam [31:0]  SEED       = 32'h1B1B_4321;

    reg clk, rst_n;
    integer cycles;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycles <= 0;
        else        cycles <= cycles + 1;
    end

    reg  [31:0] wb_pc, wb_pc_next, wb_alu_result, wb_rdata, wb_csr_wdata;
    reg  [11:0] wb_csr_addr;
    reg  [4:0]  wb_rd_addr;
    reg  [1:0]  wb_sel, wb_csr_op;
    reg  [3:0]  wb_sys_op;
    reg         wb_reg_write, wb_csr_we;
    reg         wb_illegal, wb_fetch_fault, wb_mem_fault;

    reg  [31:0] csr_rdata;
    reg         csr_illegal;
    reg  [1:0]  current_priv;
    reg  [31:0] trap_target, xret_pc;

    wire        csr_we;
    wire [11:0] csr_addr;
    wire [1:0]  csr_op;
    wire [31:0] csr_wdata;
    wire        mret, sret, trap_enter;
    wire [3:0]  trap_cause;
    wire [31:0] trap_epc, trap_tval;
    wire        trap_is_interrupt;
    wire        rf_we;
    wire [4:0]  rf_rd_addr;
    wire [31:0] rf_rd_data;
    wire        wb_redirect;
    wire [31:0] wb_redirect_pc;
    wire        retire;

    integer errors, tests_run;

    wb_stage dut (
        .clk(clk), .rst_n(rst_n),
        .wb_pc(wb_pc), .wb_pc_next(wb_pc_next),
        .wb_alu_result(wb_alu_result), .wb_rdata(wb_rdata),
        .wb_csr_wdata(wb_csr_wdata), .wb_csr_addr(wb_csr_addr),
        .wb_rd_addr(wb_rd_addr),
        .wb_sel(wb_sel), .wb_csr_op(wb_csr_op), .wb_sys_op(wb_sys_op),
        .wb_reg_write(wb_reg_write), .wb_csr_we(wb_csr_we),
        .wb_illegal(wb_illegal), .wb_fetch_fault(wb_fetch_fault),
        .wb_mem_fault(wb_mem_fault),
        .csr_we(csr_we), .csr_addr(csr_addr),
        .csr_op(csr_op), .csr_wdata(csr_wdata),
        .csr_rdata(csr_rdata), .csr_illegal(csr_illegal),
        .current_priv(current_priv),
        .trap_target(trap_target), .xret_pc(xret_pc),
        .mret(mret), .sret(sret),
        .trap_enter(trap_enter), .trap_cause(trap_cause),
        .trap_epc(trap_epc), .trap_tval(trap_tval),
        .trap_is_interrupt(trap_is_interrupt),
        .rf_we(rf_we), .rf_rd_addr(rf_rd_addr), .rf_rd_data(rf_rd_data),
        .wb_redirect(wb_redirect), .wb_redirect_pc(wb_redirect_pc),
        .retire(retire)
    );

    task clear_inputs;
        begin
            wb_pc=0; wb_pc_next=0; wb_alu_result=0; wb_rdata=0;
            wb_csr_wdata=0; wb_csr_addr=0; wb_rd_addr=0;
            wb_sel=`WB_ALU; wb_csr_op=`CSR_OP_RW; wb_sys_op=`SYS_NONE;
            wb_reg_write=0; wb_csr_we=0;
            wb_illegal=0; wb_fetch_fault=0; wb_mem_fault=0;
            csr_rdata=0; csr_illegal=0;
            current_priv=`PRV_M;
            trap_target=0; xret_pc=0;
        end
    endtask

    task mark_valid;
        begin
            wb_pc = 32'h0000_1000;
        end
    endtask

    task check;
        input [31:0]  exp_rf_data;
        input [4:0]   exp_rf_addr;
        input         exp_rf_we;
        input         exp_trap;
        input [3:0]   exp_cause;
        input [31:0]  exp_epc, exp_tval;
        input         exp_redirect;
        input [31:0]  exp_red_pc;
        input         exp_retire;
        input [255:0] label;
        begin
            tests_run = tests_run + 1;
            if (rf_rd_data !== exp_rf_data) begin
                $display("FAIL [%0s] rf_rd_data got=%h exp=%h",
                         label, rf_rd_data, exp_rf_data);
                errors = errors + 1;
            end
            if (rf_rd_addr !== exp_rf_addr) begin
                $display("FAIL [%0s] rf_rd_addr got=%0d exp=%0d",
                         label, rf_rd_addr, exp_rf_addr);
                errors = errors + 1;
            end
            if (rf_we !== exp_rf_we) begin
                $display("FAIL [%0s] rf_we got=%b exp=%b",
                         label, rf_we, exp_rf_we);
                errors = errors + 1;
            end
            if (trap_enter !== exp_trap) begin
                $display("FAIL [%0s] trap_enter got=%b exp=%b",
                         label, trap_enter, exp_trap);
                errors = errors + 1;
            end
            if (trap_enter && (trap_cause !== exp_cause)) begin
                $display("FAIL [%0s] trap_cause got=%0d exp=%0d",
                         label, trap_cause, exp_cause);
                errors = errors + 1;
            end
            if (trap_enter && (trap_epc !== exp_epc)) begin
                $display("FAIL [%0s] trap_epc got=%h exp=%h",
                         label, trap_epc, exp_epc);
                errors = errors + 1;
            end
            if (trap_enter && (trap_tval !== exp_tval)) begin
                $display("FAIL [%0s] trap_tval got=%h exp=%h",
                         label, trap_tval, exp_tval);
                errors = errors + 1;
            end
            if (wb_redirect !== exp_redirect) begin
                $display("FAIL [%0s] wb_redirect got=%b exp=%b",
                         label, wb_redirect, exp_redirect);
                errors = errors + 1;
            end
            if (wb_redirect && (wb_redirect_pc !== exp_red_pc)) begin
                $display("FAIL [%0s] wb_redirect_pc got=%h exp=%h",
                         label, wb_redirect_pc, exp_red_pc);
                errors = errors + 1;
            end
            if (retire !== exp_retire) begin
                $display("FAIL [%0s] retire got=%b exp=%b",
                         label, retire, exp_retire);
                errors = errors + 1;
            end
        end
    endtask

    task run_directed;
        begin
            // ---- 1: WB_ALU writeback ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_alu_result = 32'hDEAD_BEEF;
            wb_rdata      = 32'h1111_1111;
            wb_pc_next    = 32'h2222_2222;
            wb_rd_addr    = 5'd10;
            wb_reg_write  = 1'b1;
            wb_sel        = `WB_ALU;
            csr_rdata     = 32'h3333_3333;
            #1;
            check(32'hDEAD_BEEF, 5'd10, 1'b1, 1'b0, 4'b0, 0, 0,
                  1'b0, 0, 1'b1, "WB_ALU");

            // ---- 2: WB_MEM writeback ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_alu_result = 32'hDEAD_BEEF;
            wb_rdata      = 32'h1111_1111;
            wb_rd_addr    = 5'd11;
            wb_reg_write  = 1'b1;
            wb_sel        = `WB_MEM;
            #1;
            check(32'h1111_1111, 5'd11, 1'b1, 1'b0, 4'b0, 0, 0,
                  1'b0, 0, 1'b1, "WB_MEM");

            // ---- 3: WB_PC4 writeback ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_pc_next    = 32'h0000_2004;
            wb_rd_addr    = 5'd1;
            wb_reg_write  = 1'b1;
            wb_sel        = `WB_PC4;
            #1;
            check(32'h0000_2004, 5'd1, 1'b1, 1'b0, 4'b0, 0, 0,
                  1'b0, 0, 1'b1, "WB_PC4");

            // ---- 4: WB_CSR writeback ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_rd_addr    = 5'd12;
            wb_reg_write  = 1'b1;
            wb_sel        = `WB_CSR;
            wb_csr_we     = 1'b1;
            wb_csr_addr   = `CSR_MSTATUS;
            wb_csr_op     = `CSR_OP_RW;
            wb_csr_wdata  = 32'h0000_0008;
            csr_rdata     = 32'h8000_0000;
            #1;
            check(32'h8000_0000, 5'd12, 1'b1, 1'b0, 4'b0, 0, 0,
                  1'b0, 0, 1'b1, "WB_CSR");
            tests_run = tests_run + 1;
            if (csr_we !== 1'b1 || csr_addr !== `CSR_MSTATUS ||
                csr_op !== `CSR_OP_RW || csr_wdata !== 32'h0000_0008) begin
                $display("FAIL [WB_CSR passthrough] csr_we=%b addr=%h op=%b wdata=%h",
                         csr_we, csr_addr, csr_op, csr_wdata);
                errors = errors + 1;
            end

            // ---- 5: rf_we gated on illegal ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_rd_addr    = 5'd5;
            wb_reg_write  = 1'b1;
            wb_illegal    = 1'b1;
            #1;
            check(32'h0, 5'd5, 1'b0, 1'b1, `CAUSE_ILLEGAL_INSN,
                  32'h0000_1000, 32'h0,
                  1'b1, trap_target, 1'b0, "illegal traps, no rf_we");

            // ---- 6: rf_we gated on fetch_fault ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_rd_addr     = 5'd5;
            wb_reg_write   = 1'b1;
            wb_fetch_fault = 1'b1;
            #1;
            check(32'h0, 5'd5, 1'b0, 1'b1, `CAUSE_INSN_ACCESS,
                  32'h0000_1000, 32'h0000_1000,
                  1'b1, trap_target, 1'b0, "fetch fault");

            // ---- 7: rf_we gated on mem_fault ----
            // rf_rd_data is the WB mux output (WB_ALU path) = wb_alu_result,
            // not zeroed by the fault. Only rf_we is gated.
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_rd_addr     = 5'd5;
            wb_reg_write   = 1'b1;
            wb_alu_result  = 32'h0000_2000;   // faulting address
            wb_mem_fault   = 1'b1;
            #1;
            check(32'h0000_2000, 5'd5, 1'b0, 1'b1, `CAUSE_LOAD_ACCESS,
                  32'h0000_1000, 32'h0000_2000,
                  1'b1, trap_target, 1'b0, "mem fault");

            // ---- 8: rf_we gated on csr_illegal (only when csr_we=1) ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_rd_addr   = 5'd5;
            wb_reg_write = 1'b1;
            wb_csr_we    = 1'b1;
            wb_csr_addr  = 12'hFFF;
            csr_illegal  = 1'b1;
            #1;
            check(32'h0, 5'd5, 1'b0, 1'b1, `CAUSE_ILLEGAL_INSN,
                  32'h0000_1000, 32'h0,
                  1'b1, trap_target, 1'b0, "csr_illegal + csr_we");

            // ---- 9: csr_illegal with csr_we=0 is ignored ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_rd_addr   = 5'd5;
            wb_reg_write = 1'b1;
            wb_csr_we    = 1'b0;
            csr_illegal  = 1'b1;
            #1;
            check(32'h0, 5'd5, 1'b1, 1'b0, 4'b0, 0, 0,
                  1'b0, 0, 1'b1, "csr_illegal ignored w/o csr_we");

            // ---- 10: ECALL from U-mode ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_sys_op    = `SYS_ECALL;
            current_priv = `PRV_U;
            #1;
            check(32'h0, 5'd0, 1'b0, 1'b1, `CAUSE_ECALL_U,
                  32'h0000_1000, 32'h0,
                  1'b1, trap_target, 1'b0, "ECALL U");

            // ---- 11: ECALL from S-mode ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_sys_op    = `SYS_ECALL;
            current_priv = `PRV_S;
            #1;
            check(32'h0, 5'd0, 1'b0, 1'b1, `CAUSE_ECALL_S,
                  32'h0000_1000, 32'h0,
                  1'b1, trap_target, 1'b0, "ECALL S");

            // ---- 12: ECALL from M-mode ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_sys_op    = `SYS_ECALL;
            current_priv = `PRV_M;
            #1;
            check(32'h0, 5'd0, 1'b0, 1'b1, `CAUSE_ECALL_M,
                  32'h0000_1000, 32'h0,
                  1'b1, trap_target, 1'b0, "ECALL M");

            // ---- 13: EBREAK ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_sys_op    = `SYS_EBREAK;
            #1;
            check(32'h0, 5'd0, 1'b0, 1'b1, `CAUSE_BREAKPOINT,
                  32'h0000_1000, 32'h0,
                  1'b1, trap_target, 1'b0, "EBREAK");

            // ---- 14: MRET ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_sys_op = `SYS_MRET;
            xret_pc   = 32'h8000_1234;
            #1;
            check(32'h0, 5'd0, 1'b0, 1'b0, 4'b0, 0, 0,
                  1'b1, 32'h8000_1234, 1'b1, "MRET");
            tests_run = tests_run + 1;
            if (!mret || sret) begin
                $display("FAIL: MRET decode mret=%b sret=%b", mret, sret);
                errors = errors + 1;
            end

            // ---- 15: SRET ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_sys_op = `SYS_SRET;
            xret_pc   = 32'h8000_5678;
            #1;
            check(32'h0, 5'd0, 1'b0, 1'b0, 4'b0, 0, 0,
                  1'b1, 32'h8000_5678, 1'b1, "SRET");
            tests_run = tests_run + 1;
            if (mret || !sret) begin
                $display("FAIL: SRET decode mret=%b sret=%b", mret, sret);
                errors = errors + 1;
            end

            // ---- 16: Bubble (all zeros): retire=0 ----
            clear_inputs;
            @(negedge clk);
            #1;
            tests_run = tests_run + 1;
            if (retire !== 1'b0) begin
                $display("FAIL: bubble retire=%b exp=0", retire);
                errors = errors + 1;
            end
            tests_run = tests_run + 1;
            if (wb_redirect !== 1'b0) begin
                $display("FAIL: bubble wb_redirect=%b exp=0", wb_redirect);
                errors = errors + 1;
            end

            // ---- 17: NOP at pc=0x1000 retires ----
            clear_inputs;
            @(negedge clk);
            wb_pc = 32'h0000_1000;
            wb_reg_write = 1'b1;
            #1;
            tests_run = tests_run + 1;
            if (retire !== 1'b1) begin
                $display("FAIL: NOP retire=%b exp=1", retire);
                errors = errors + 1;
            end

            // ---- 18: trap_tval = 0 for illegal ----
            clear_inputs;
            @(negedge clk);
            mark_valid;
            wb_illegal = 1'b1;
            #1;
            tests_run = tests_run + 1;
            if (trap_tval !== 32'b0) begin
                $display("FAIL: illegal trap_tval got=%h exp=0", trap_tval);
                errors = errors + 1;
            end

            clear_inputs;
        end
    endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_wb_stage);

        errors = 0; tests_run = 0;
        clear_inputs;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        run_directed;

        $display("---------------------------------------------");
        $display("tb_wb_stage: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0) $display("TEST PASSED: tb_wb_stage");
        else             $display("TEST FAILED: tb_wb_stage %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_wb_stage timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire