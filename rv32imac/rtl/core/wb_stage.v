//=============================================================================
// Module:      wb_stage
// File:        rtl/core/wb_stage.v
// Description: WB stage. Combinational.
//              Owns the register-writeback mux, CSR read/write access to
//              csr_file, trap generation, MRET/SRET, and retire detection.
//              CSR read is deferred to WB (values sampled combinationally
//              from csr_file), but csr_file commits the write on the next
//              posedge when csr_we is high.
//              Retire uses an all-zero test on the MEM/WB contents. Since
//              flush produces all-zero, and every real instruction has a
//              nonzero pc, this correctly distinguishes bubbles from real
//              instructions.
// Reset:       None (no state).
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module wb_stage (
    input  wire        clk,
    input  wire        rst_n,

    // ---- From MEM/WB ----
    input  wire [31:0] wb_pc,
    input  wire [31:0] wb_pc_next,
    input  wire [31:0] wb_alu_result,
    input  wire [31:0] wb_rdata,
    input  wire [31:0] wb_csr_wdata,
    input  wire [11:0] wb_csr_addr,
    input  wire [4:0]  wb_rd_addr,
    input  wire [1:0]  wb_sel,
    input  wire [1:0]  wb_csr_op,
    input  wire [3:0]  wb_sys_op,
    input  wire        wb_reg_write,
    input  wire        wb_csr_we,
    input  wire        wb_illegal,
    input  wire        wb_fetch_fault,
    input  wire        wb_mem_fault,

    // ---- CSR file interface ----
    output wire        csr_we,
    output wire [11:0] csr_addr,
    output wire [1:0]  csr_op,
    output wire [31:0] csr_wdata,
    input  wire [31:0] csr_rdata,
    input  wire        csr_illegal,
    input  wire [1:0]  current_priv,
    input  wire [31:0] trap_target,
    input  wire [31:0] xret_pc,
    output wire        mret,
    output wire        sret,
    output wire        trap_enter,
    output wire [3:0]  trap_cause,
    output wire [31:0] trap_epc,
    output wire [31:0] trap_tval,
    output wire        trap_is_interrupt,

    // ---- Regfile write port ----
    output wire        rf_we,
    output wire [4:0]  rf_rd_addr,
    output wire [31:0] rf_rd_data,

    // ---- Redirect ----
    output wire        wb_redirect,
    output wire [31:0] wb_redirect_pc,

    // ---- Retire ----
    output wire        retire
);

    //------------------------------------------------------------------
    // CSR pass-through
    //------------------------------------------------------------------
    assign csr_we    = wb_csr_we;
    assign csr_addr  = wb_csr_addr;
    assign csr_op    = wb_csr_op;
    assign csr_wdata = wb_csr_wdata;

    //------------------------------------------------------------------
    // Writeback mux
    //------------------------------------------------------------------
    assign rf_rd_addr = wb_rd_addr;

    assign rf_rd_data =
        (wb_sel == `WB_ALU) ? wb_alu_result :
        (wb_sel == `WB_MEM) ? wb_rdata      :
        (wb_sel == `WB_PC4) ? wb_pc_next    :
        (wb_sel == `WB_CSR) ? csr_rdata     :
                              wb_alu_result;

    //------------------------------------------------------------------
    // System ops
    //------------------------------------------------------------------
    assign mret = (wb_sys_op == `SYS_MRET);
    assign sret = (wb_sys_op == `SYS_SRET);

    //------------------------------------------------------------------
    // Trap detection
    //------------------------------------------------------------------
    wire tr_illegal = wb_illegal || (wb_csr_we && csr_illegal);
    wire tr_fetch   = wb_fetch_fault;
    wire tr_mem     = wb_mem_fault;
    wire tr_ecall   = (wb_sys_op == `SYS_ECALL);
    wire tr_ebreak  = (wb_sys_op == `SYS_EBREAK);

    assign trap_enter = tr_illegal || tr_fetch || tr_mem || tr_ecall || tr_ebreak;

    reg [3:0] cause_r;
    always @(*) begin
        if      (tr_illegal) cause_r = `CAUSE_ILLEGAL_INSN;
        else if (tr_ebreak)  cause_r = `CAUSE_BREAKPOINT;
        else if (tr_ecall)   cause_r = (current_priv == `PRV_M) ? `CAUSE_ECALL_M :
                                       (current_priv == `PRV_S) ? `CAUSE_ECALL_S :
                                                                  `CAUSE_ECALL_U;
        else if (tr_fetch)   cause_r = `CAUSE_INSN_ACCESS;
        else if (tr_mem)     cause_r = `CAUSE_LOAD_ACCESS;
        else                 cause_r = 4'b0;
    end
    assign trap_cause = cause_r;

    assign trap_epc = wb_pc;

    assign trap_tval = tr_fetch ? wb_pc         :
                       tr_mem   ? wb_alu_result :  // faulting address
                                  32'b0;

    assign trap_is_interrupt = 1'b0;

    //------------------------------------------------------------------
    // Register write gating
    //------------------------------------------------------------------
    wire no_fault = !wb_illegal && !wb_fetch_fault && !wb_mem_fault &&
                    !(wb_csr_we && csr_illegal);

    assign rf_we = wb_reg_write && no_fault;

    //------------------------------------------------------------------
    // Redirect
    //------------------------------------------------------------------
    assign wb_redirect    = trap_enter || mret || sret;
    assign wb_redirect_pc = trap_enter      ? trap_target :
                            (mret || sret)  ? xret_pc     :
                                              32'b0;

    //------------------------------------------------------------------
    // Retire: any non-bubble that didn't trap
    //------------------------------------------------------------------
    wire is_bubble = ~(|{wb_pc, wb_pc_next, wb_alu_result, wb_rdata,
                         wb_csr_wdata, wb_csr_addr, wb_rd_addr,
                         wb_sel, wb_csr_op, wb_sys_op,
                         wb_reg_write, wb_csr_we,
                         wb_illegal, wb_fetch_fault, wb_mem_fault});

    assign retire = !is_bubble && !trap_enter;

endmodule