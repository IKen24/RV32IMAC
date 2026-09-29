//=============================================================================
// Module:      tb_csr_file
// File:        sim/tb/tb_csr_file.v
// Description: Self-checking TB for csr_file.
//=============================================================================
`default_nettype none
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module tb_csr_file;

    localparam integer CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 200000;
    localparam [31:0]  SEED       = 32'hABAD_1DEA;

    reg clk;
    reg rst_n;
    integer cycles;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycles <= 0;
        else        cycles <= cycles + 1;
    end

    reg         csr_we;
    reg  [11:0] csr_addr;
    reg  [1:0]  csr_op;
    reg  [31:0] csr_wdata;
    wire [31:0] csr_rdata;
    wire        csr_illegal;
    wire [1:0]  current_priv;

    reg         trap_enter;
    reg  [3:0]  trap_cause;
    reg  [31:0] trap_epc;
    reg  [31:0] trap_tval;
    reg         trap_is_interrupt;
    wire [31:0] trap_target;

    reg         mret;
    reg         sret;
    wire [31:0] xret_pc;

    reg         timer_irq;
    reg         ext_irq;
    wire [31:0] mie_out;
    wire [31:0] mip_out;

    reg         retire;

    wire [31:0] satp_out;

    integer errors;
    integer tests_run;
    integer rng_seed;
    integer rng_dummy;

    csr_file #(.HARTID(32'h0)) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .csr_we          (csr_we),
        .csr_addr        (csr_addr),
        .csr_op          (csr_op),
        .csr_wdata       (csr_wdata),
        .csr_rdata       (csr_rdata),
        .csr_illegal     (csr_illegal),
        .current_priv    (current_priv),
        .trap_enter      (trap_enter),
        .trap_cause      (trap_cause),
        .trap_epc        (trap_epc),
        .trap_tval       (trap_tval),
        .trap_is_interrupt(trap_is_interrupt),
        .trap_target     (trap_target),
        .mret            (mret),
        .sret            (sret),
        .xret_pc         (xret_pc),
        .timer_irq       (timer_irq),
        .ext_irq         (ext_irq),
        .mie_out         (mie_out),
        .mip_out         (mip_out),
        .retire          (retire),
        .satp_out        (satp_out)
    );

    //------------------------------------------------------------------
    // Helpers
    //------------------------------------------------------------------
    task deassert_all;
        begin
            csr_we    = 1'b0;
            csr_addr  = 12'b0;
            csr_op    = `CSR_OP_RW;
            csr_wdata = 32'b0;
            trap_enter = 1'b0;
            trap_cause = 4'b0;
            trap_epc   = 32'b0;
            trap_tval  = 32'b0;
            trap_is_interrupt = 1'b0;
            mret      = 1'b0;
            sret      = 1'b0;
            timer_irq = 1'b0;
            ext_irq   = 1'b0;
            retire    = 1'b0;
        end
    endtask

    task read_csr;
        input  [11:0] addr;
        output [31:0] val;
        output        ill;
        begin
            @(negedge clk);
            csr_we   = 1'b0;
            csr_addr = addr;
            #1;
            val = csr_rdata;
            ill = csr_illegal;
        end
    endtask

    task read_two_csrs;
        input  [11:0] addr_a;
        input  [11:0] addr_b;
        output [31:0] a;
        output [31:0] b;
        begin
            @(negedge clk);
            csr_we   = 1'b0;
            csr_addr = addr_a;
            #1;
            a = csr_rdata;
            csr_addr = addr_b;
            #1;
            b = csr_rdata;
        end
    endtask

    task write_csr;
        input [11:0] addr;
        input [31:0] data;
        input [1:0]  op;
        begin
            @(negedge clk);
            csr_we    = 1'b1;
            csr_addr  = addr;
            csr_wdata = data;
            csr_op    = op;
            @(posedge clk);
            @(negedge clk);
            csr_we    = 1'b0;
            csr_wdata = 32'b0;
        end
    endtask

    task check_read;
        input [11:0]  addr;
        input [31:0]  expected;
        input         ill_expected;
        input [255:0] label;
        reg [31:0]    v;
        reg           i;
        begin
            read_csr(addr, v, i);
            tests_run = tests_run + 1;
            if (v !== expected) begin
                $display("FAIL [%0s] addr=%h got=%h exp=%h", label, addr, v, expected);
                errors = errors + 1;
            end
            if (i !== ill_expected) begin
                $display("FAIL [%0s] addr=%h illegal=%b exp=%b", label, addr, i, ill_expected);
                errors = errors + 1;
            end
        end
    endtask

    task check_priv;
        input [1:0]   expected;
        input [255:0] label;
        begin
            tests_run = tests_run + 1;
            if (current_priv !== expected) begin
                $display("FAIL [%0s] priv got=%b exp=%b", label, current_priv, expected);
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Directed tests
    //------------------------------------------------------------------
    task run_reset_checks;
        begin
            check_read(`CSR_MSTATUS,   32'h0, 1'b0, "rst mstatus");
            check_read(`CSR_MTVEC,     32'h0, 1'b0, "rst mtvec");
            check_read(`CSR_MEPC,      32'h0, 1'b0, "rst mepc");
            check_read(`CSR_MCAUSE,    32'h0, 1'b0, "rst mcause");
            check_read(`CSR_MTVAL,     32'h0, 1'b0, "rst mtval");
            check_read(`CSR_MSCRATCH,  32'h0, 1'b0, "rst mscratch");
            check_read(`CSR_MIE,       32'h0, 1'b0, "rst mie");
            check_read(`CSR_MEDELEG,   32'h0, 1'b0, "rst medeleg");
            check_read(`CSR_MIDELEG,   32'h0, 1'b0, "rst mideleg");
            check_read(`CSR_STVEC,     32'h0, 1'b0, "rst stvec");
            check_read(`CSR_SEPC,      32'h0, 1'b0, "rst sepc");
            check_read(`CSR_SCAUSE,    32'h0, 1'b0, "rst scause");
            check_read(`CSR_STVAL,     32'h0, 1'b0, "rst stval");
            check_read(`CSR_SATP,      32'h0, 1'b0, "rst satp");
            check_read(`CSR_MISA,      32'h4000_1105, 1'b0, "rst misa");
            check_read(`CSR_MVENDORID, 32'h0, 1'b0, "rst mvendorid");
            check_read(`CSR_MARCHID,   32'h1, 1'b0, "rst marchid");
            check_read(`CSR_MIMPID,    32'h1, 1'b0, "rst mimpid");
            check_read(`CSR_MHARTID,   32'h0, 1'b0, "rst mhartid");
            check_priv(`PRV_M, "rst priv");
        end
    endtask

    task run_rw_checks;
        begin
            write_csr(`CSR_MTVEC, 32'h8000_0100, `CSR_OP_RW);
            check_read(`CSR_MTVEC, 32'h8000_0100, 1'b0, "mtvec rw");

            write_csr(`CSR_MSCRATCH, 32'hAAAA_5555, `CSR_OP_RW);
            check_read(`CSR_MSCRATCH, 32'hAAAA_5555, 1'b0, "mscratch rw");

            write_csr(`CSR_MSCRATCH, 32'h0000_FFFF, `CSR_OP_RS);
            check_read(`CSR_MSCRATCH, 32'hAAAA_FFFF, 1'b0, "mscratch rs");

            write_csr(`CSR_MSCRATCH, 32'hAAAA_0000, `CSR_OP_RC);
            check_read(`CSR_MSCRATCH, 32'h0000_FFFF, 1'b0, "mscratch rc");

            write_csr(`CSR_MSCRATCH, 32'hDEAD_BEEF, `CSR_OP_RW);
            write_csr(`CSR_MSCRATCH, 32'h0000_0000, `CSR_OP_RS);
            check_read(`CSR_MSCRATCH, 32'hDEAD_BEEF, 1'b0, "mscratch rs0");

            write_csr(`CSR_MSCRATCH, 32'h0000_0000, `CSR_OP_RC);
            check_read(`CSR_MSCRATCH, 32'hDEAD_BEEF, 1'b0, "mscratch rc0");

            write_csr(`CSR_MEPC,   32'h8000_2000, `CSR_OP_RW);
            write_csr(`CSR_MCAUSE, 32'h0000_000B, `CSR_OP_RW);
            write_csr(`CSR_MTVAL,  32'h1234_5678, `CSR_OP_RW);
            check_read(`CSR_MEPC,   32'h8000_2000, 1'b0, "mepc rw");
            check_read(`CSR_MCAUSE, 32'h0000_000B, 1'b0, "mcause rw");
            check_read(`CSR_MTVAL,  32'h1234_5678, 1'b0, "mtval rw");

            write_csr(`CSR_STVEC,    32'h8000_0400, `CSR_OP_RW);
            write_csr(`CSR_SEPC,     32'h8000_3000, `CSR_OP_RW);
            write_csr(`CSR_SCAUSE,   32'h0000_0009, `CSR_OP_RW);
            write_csr(`CSR_STVAL,    32'hCAFE_BABE, `CSR_OP_RW);
            write_csr(`CSR_SSCRATCH, 32'hFEED_FACE, `CSR_OP_RW);
            check_read(`CSR_STVEC,    32'h8000_0400, 1'b0, "stvec rw");
            check_read(`CSR_SEPC,     32'h8000_3000, 1'b0, "sepc rw");
            check_read(`CSR_SCAUSE,   32'h0000_0009, 1'b0, "scause rw");
            check_read(`CSR_STVAL,    32'hCAFE_BABE, 1'b0, "stval rw");
            check_read(`CSR_SSCRATCH, 32'hFEED_FACE, 1'b0, "sscratch rw");

            write_csr(`CSR_SATP, 32'h8000_1234, `CSR_OP_RW);
            check_read(`CSR_SATP, 32'h8000_1234, 1'b0, "satp rw");
            tests_run = tests_run + 1;
            if (satp_out !== 32'h8000_1234) begin
                $display("FAIL satp_out: got=%h exp=80001234", satp_out);
                errors = errors + 1;
            end

            write_csr(`CSR_MEDELEG, 32'h0000_B3FF, `CSR_OP_RW);
            write_csr(`CSR_MIDELEG, 32'h0000_0222, `CSR_OP_RW);
            check_read(`CSR_MEDELEG, 32'h0000_B3FF, 1'b0, "medeleg rw");
            check_read(`CSR_MIDELEG, 32'h0000_0222, 1'b0, "mideleg rw");
        end
    endtask

    task run_mask_checks;
        reg [31:0] v; reg i;
        begin
            write_csr(`CSR_MSTATUS, 32'hFFFF_FFFF, `CSR_OP_RW);
            read_csr(`CSR_MSTATUS, v, i);
            tests_run = tests_run + 1;
            if (v !== 32'h000E_19AA) begin
                $display("FAIL mstatus write mask: got=%h exp=000E19AA", v);
                errors = errors + 1;
            end

            write_csr(`CSR_MSTATUS, 32'h0, `CSR_OP_RW);
            check_read(`CSR_MSTATUS, 32'h0, 1'b0, "mstatus clear");

            write_csr(`CSR_MSTATUS, 32'h0000_0008, `CSR_OP_RW);
            check_read(`CSR_MSTATUS, 32'h0000_0008, 1'b0, "mstatus MIE");

            write_csr(`CSR_MSTATUS, 32'h0000_0180, `CSR_OP_RW);
            read_csr(`CSR_SSTATUS, v, i);
            tests_run = tests_run + 1;
            if (v !== 32'h0000_0100) begin
                $display("FAIL sstatus view: got=%h exp=00000100", v);
                errors = errors + 1;
            end

            write_csr(`CSR_SSTATUS, 32'h0000_0022, `CSR_OP_RW);
            read_csr(`CSR_MSTATUS, v, i);
            tests_run = tests_run + 1;
            if ((v & 32'h0000_0022) !== 32'h0000_0022) begin
                $display("FAIL sstatus->mstatus: got=%h", v);
                errors = errors + 1;
            end

            write_csr(`CSR_MIE, 32'h0000_0AAA, `CSR_OP_RW);
            read_csr(`CSR_SIE, v, i);
            tests_run = tests_run + 1;
            if (v !== 32'h0000_0222) begin
                $display("FAIL sie view: got=%h exp=00000222", v);
                errors = errors + 1;
            end

            timer_irq = 1'b1;
            read_csr(`CSR_MIP, v, i);
            tests_run = tests_run + 1;
            if ((v & 32'h0000_0080) !== 32'h0000_0080) begin
                $display("FAIL mip MTIP: got=%h", v);
                errors = errors + 1;
            end
            timer_irq = 1'b0;
        end
    endtask

    task run_privilege_checks;
        reg [31:0] v; reg i;
        begin
            // Clear delegation so subsequent traps don't get hijacked.
            write_csr(`CSR_MEDELEG, 32'h0, `CSR_OP_RW);
            write_csr(`CSR_MIDELEG, 32'h0, `CSR_OP_RW);

            // Enter S: MPP = S (bits[12:11] = 01)
            write_csr(`CSR_MSTATUS, 32'h0000_0800, `CSR_OP_RW);
            write_csr(`CSR_MEPC, 32'h8000_0000, `CSR_OP_RW);
            @(negedge clk);
            mret = 1'b1;
            @(posedge clk);
            @(negedge clk);
            mret = 1'b0;
            check_priv(`PRV_S, "priv -> S via mret");

            // In S: mtvec read should be illegal
            read_csr(`CSR_MTVEC, v, i);
            tests_run = tests_run + 1;
            if (!i) begin
                $display("FAIL priv: read mtvec from S should be illegal");
                errors = errors + 1;
            end

            // In S: stvec read should be legal
            read_csr(`CSR_STVEC, v, i);
            tests_run = tests_run + 1;
            if (i) begin
                $display("FAIL priv: read stvec from S should be legal");
                errors = errors + 1;
            end

            // Back to M via ECALL_S trap (now undelegated)
            @(negedge clk);
            trap_enter = 1'b1;
            trap_cause = `CAUSE_ECALL_S;
            trap_epc   = 32'h8000_1000;
            trap_tval  = 32'h0;
            trap_is_interrupt = 1'b0;
            @(posedge clk);
            @(negedge clk);
            trap_enter = 1'b0;
            check_priv(`PRV_M, "priv -> M via trap");
        end
    endtask

    task run_trap_tests;
        reg [31:0] v; reg i;
        begin
            // ---- Trap to M-mode (no delegation) ----
            write_csr(`CSR_MEDELEG, 32'h0, `CSR_OP_RW);
            write_csr(`CSR_MSTATUS, 32'h0000_0008, `CSR_OP_RW); // MIE=1

            @(negedge clk);
            trap_enter = 1'b1;
            trap_cause = `CAUSE_ILLEGAL_INSN;
            trap_epc   = 32'h8000_2000;
            trap_tval  = 32'hDEADBEEF;
            trap_is_interrupt = 1'b0;
            @(posedge clk);
            @(negedge clk);
            trap_enter = 1'b0;

            check_priv(`PRV_M, "trap M priv");
            read_csr(`CSR_MEPC, v, i);
            tests_run = tests_run + 1;
            if (v !== 32'h8000_2000) begin
                $display("FAIL trap M mepc: got=%h", v);
                errors = errors + 1;
            end
            read_csr(`CSR_MCAUSE, v, i);
            tests_run = tests_run + 1;
            if (v !== 32'h0000_0002) begin
                $display("FAIL trap M mcause: got=%h", v);
                errors = errors + 1;
            end
            read_csr(`CSR_MTVAL, v, i);
            tests_run = tests_run + 1;
            if (v !== 32'hDEADBEEF) begin
                $display("FAIL trap M mtval: got=%h", v);
                errors = errors + 1;
            end
            read_csr(`CSR_MSTATUS, v, i);
            tests_run = tests_run + 1;
            if ((v & 32'h0000_1888) !== 32'h0000_1880) begin
                $display("FAIL trap M mstatus: got=%h", v);
                errors = errors + 1;
            end

            // ---- MRET back to M ----
            @(negedge clk);
            mret = 1'b1;
            @(posedge clk);
            @(negedge clk);
            mret = 1'b0;
            read_csr(`CSR_MSTATUS, v, i);
            tests_run = tests_run + 1;
            if ((v & 32'h0000_0008) !== 32'h0000_0008) begin
                $display("FAIL mret MIE restore: got=%h", v);
                errors = errors + 1;
            end

            // ---- Delegated trap to S ----
            write_csr(`CSR_MSTATUS, 32'h0000_0800, `CSR_OP_RW); // MPP=S
            write_csr(`CSR_MEPC, 32'h8000_0000, `CSR_OP_RW);
            @(negedge clk); mret = 1'b1;
            @(posedge clk); @(negedge clk); mret = 1'b0;
            check_priv(`PRV_S, "deleg setup -> S");

            // Back to M via undelegated ECALL_S
            @(negedge clk);
            trap_enter = 1'b1; trap_cause = `CAUSE_ECALL_S;
            trap_epc = 32'h8000_0000; trap_is_interrupt = 1'b0;
            @(posedge clk); @(negedge clk); trap_enter = 1'b0;
            check_priv(`PRV_M, "back to M");

            write_csr(`CSR_MEDELEG, 32'h0000_0004, `CSR_OP_RW); // delegate ILLEGAL_INSN
            write_csr(`CSR_MSTATUS, 32'h0000_0800, `CSR_OP_RW); // MPP=S
            write_csr(`CSR_MEPC, 32'h8000_0000, `CSR_OP_RW);
            @(negedge clk); mret = 1'b1;
            @(posedge clk); @(negedge clk); mret = 1'b0;
            check_priv(`PRV_S, "back to S");

            write_csr(`CSR_STVEC, 32'h8000_5000, `CSR_OP_RW);
            @(negedge clk);
            trap_enter = 1'b1; trap_cause = `CAUSE_ILLEGAL_INSN;
            trap_epc = 32'h8000_3000; trap_tval = 32'hCAFE;
            trap_is_interrupt = 1'b0;
            @(posedge clk); @(negedge clk); trap_enter = 1'b0;

            check_priv(`PRV_S, "deleg trap stays S");
            read_csr(`CSR_SEPC, v, i);
            tests_run = tests_run + 1;
            if (v !== 32'h8000_3000) begin
                $display("FAIL deleg sepc: got=%h", v);
                errors = errors + 1;
            end
            read_csr(`CSR_SCAUSE, v, i);
            tests_run = tests_run + 1;
            if (v !== 32'h0000_0002) begin
                $display("FAIL deleg scause: got=%h exp=00000002", v);
                errors = errors + 1;
            end
            read_csr(`CSR_STVAL, v, i);
            tests_run = tests_run + 1;
            if (v !== 32'h0000_CAFE) begin
                $display("FAIL deleg stval: got=%h exp=0000CAFE", v);
                errors = errors + 1;
            end
            tests_run = tests_run + 1;
            if (trap_target !== 32'h8000_5000) begin
                $display("FAIL deleg trap_target: got=%h exp=80005000", trap_target);
                errors = errors + 1;
            end

            // ---- SRET back to S (SPP=1 set by trap) ----
            @(negedge clk); sret = 1'b1;
            @(posedge clk); @(negedge clk); sret = 1'b0;
            check_priv(`PRV_S, "sret -> S");

            // ---- Force back to M for cleanup ----
            // Clear delegation so ECALL_S goes to M.
            write_csr(`CSR_MEDELEG, 32'h0, `CSR_OP_RW);
            @(negedge clk);
            trap_enter = 1'b1; trap_cause = `CAUSE_ECALL_S;
            trap_epc = 32'h0; trap_is_interrupt = 1'b0;
            @(posedge clk); @(negedge clk); trap_enter = 1'b0;
            check_priv(`PRV_M, "back to M for cleanup");
        end
    endtask

    task run_counter_checks;
        reg [63:0] c0, c1, i0, i1;
        reg [31:0] lo, hi, lo2, hi2; reg ill;
        begin
            read_csr(`CSR_MCYCLE, lo, ill);
            read_csr(`CSR_MCYCLEH, hi, ill);
            c0 = {hi, lo};

            repeat (10) @(posedge clk);

            read_csr(`CSR_MCYCLE, lo, ill);
            read_csr(`CSR_MCYCLEH, hi, ill);
            c1 = {hi, lo};

            tests_run = tests_run + 1;
            if (c1 <= c0) begin
                $display("FAIL mcycle did not advance: %0d -> %0d", c0, c1);
                errors = errors + 1;
            end

            read_csr(`CSR_MINSTRET, lo, ill);
            read_csr(`CSR_MINSTRETH, hi, ill);
            i0 = {hi, lo};

            repeat (5) @(posedge clk);
            read_csr(`CSR_MINSTRET, lo, ill);
            read_csr(`CSR_MINSTRETH, hi, ill);
            i1 = {hi, lo};

            tests_run = tests_run + 1;
            if (i1 !== i0) begin
                $display("FAIL minstret advanced w/o retire: %0d -> %0d", i0, i1);
                errors = errors + 1;
            end

            repeat (7) begin
                @(negedge clk);
                retire = 1'b1;
                @(posedge clk);
            end
            @(negedge clk);
            retire = 1'b0;

            read_csr(`CSR_MINSTRET, lo, ill);
            read_csr(`CSR_MINSTRETH, hi, ill);
            tests_run = tests_run + 1;
            if ({hi, lo} !== i0 + 64'd7) begin
                $display("FAIL minstret count: got=%0d exp=%0d", {hi,lo}, i0+64'd7);
                errors = errors + 1;
            end

            read_two_csrs(`CSR_CYCLE, `CSR_MCYCLE, lo2, hi2);
            tests_run = tests_run + 1;
            if (lo2 !== hi2) begin
                $display("FAIL CYCLE alias: %h != MCYCLE %h", lo2, hi2);
                errors = errors + 1;
            end
        end
    endtask

    task run_readonly_checks;
        reg [31:0] v; reg i;
        begin
            write_csr(`CSR_MVENDORID, 32'hFFFF_FFFF, `CSR_OP_RW);
            check_read(`CSR_MVENDORID, 32'h0, 1'b0, "mvendorid RO");

            write_csr(`CSR_MISA, 32'hFFFF_FFFF, `CSR_OP_RW);
            check_read(`CSR_MISA, 32'h4000_1105, 1'b0, "misa RO");

            write_csr(`CSR_CYCLE, 32'h0, `CSR_OP_RW);
            read_csr(`CSR_CYCLE, v, i);
            tests_run = tests_run + 1;
            if (i) begin
                $display("FAIL CYCLE write flagged illegal");
                errors = errors + 1;
            end
        end
    endtask

    task run_illegal_addr;
        reg [31:0] v; reg i;
        begin
            read_csr(12'h7FF, v, i);
            tests_run = tests_run + 1;
            if (!i) begin
                $display("FAIL reserved CSR not flagged illegal");
                errors = errors + 1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Main
    //------------------------------------------------------------------
    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_csr_file);

        errors    = 0;
        tests_run = 0;
        deassert_all;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        rng_seed  = SEED;
        rng_dummy = $urandom(rng_seed);

        run_reset_checks;
        run_rw_checks;
        run_mask_checks;
        run_privilege_checks;
        run_trap_tests;
        run_counter_checks;
        run_readonly_checks;
        run_illegal_addr;

        $display("---------------------------------------------");
        $display("tb_csr_file: %0d tests, %0d errors, %0d cycles",
                 tests_run, errors, cycles);
        if (errors == 0)
            $display("TEST PASSED: tb_csr_file");
        else
            $display("TEST FAILED: tb_csr_file %0d errors", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cycles > MAX_CYCLES)
            $fatal(1, "TEST FAILED: tb_csr_file timeout after %0d cycles", cycles);
    end

endmodule

`default_nettype wire