//=============================================================================
// Module:      riscv_core
// File:        rtl/core/riscv_core.v
// Description: RV32IMAC 5-stage core, top-level integration.
//              Instantiates: if_stage, if_id, id_stage, id_ex, ex_stage,
//              ex_mem, mem_stage, mem_wb, wb_stage, csr_file, hazard_unit.
//              Redirect priority: WB (trap/mret/sret) beats EX (branch/jump).
//              Stall tiers: stall_up = load-use || muldiv || mem-latency
//              freezes IF/ID, ID/EX, PC; stall_down = muldiv || mem-latency
//              freezes EX/MEM, MEM/WB. Load-use MUST NOT freeze EX/MEM so
//              the load can progress to MEM.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module riscv_core (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Instruction memory (native) ----
    output wire        imem_req_valid,
    input  wire        imem_req_ready,
    output wire [31:0] imem_req_addr,
    input  wire        imem_rsp_valid,
    output wire        imem_rsp_ready,
    input  wire [31:0] imem_rsp_rdata,
    input  wire        imem_rsp_error,

    // ---- Data memory (native) ----
    output wire        dmem_req_valid,
    input  wire        dmem_req_ready,
    output wire [31:0] dmem_req_addr,
    output wire [31:0] dmem_req_wdata,
    output wire [3:0]  dmem_req_wstrb,
    output wire        dmem_req_write,
    output wire [1:0]  dmem_req_size,
    output wire        dmem_req_atomic,
    input  wire        dmem_rsp_valid,
    output wire        dmem_rsp_ready,
    input  wire [31:0] dmem_rsp_rdata,
    input  wire        dmem_rsp_error,

    // ---- Interrupts ----
    input  wire        timer_irq,
    input  wire        ext_irq,

    // ---- Debug / status ----
    output wire [1:0]  current_priv,
    output wire        retire,
    output wire [31:0] pc_out
);

    //=================================================================
    // Inter-stage wires
    //=================================================================

    // IF -> IF/ID
    wire [31:0] if_pc, if_pc_next, if_inst;
    wire        if_fetch_fault, if_valid;

    // IF/ID -> ID
    wire [31:0] ifid_pc, ifid_pc_next, ifid_inst;
    wire        ifid_fetch_fault;

    // ID -> ID/EX
    wire [31:0] id_pc, id_pc_next, id_rs1_data, id_rs2_data;
    wire [31:0] id_imm, id_csr_wdata;
    wire [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    wire [11:0] id_csr_addr;
    wire [4:0]  id_alu_op;
    wire        id_alu_src_a, id_alu_src_b;
    wire [2:0]  id_branch_funct3;
    wire        id_branch, id_jump;
    wire        id_use_rs1, id_use_rs2;
    wire        id_mem_read, id_mem_write, id_mem_unsigned;
    wire [1:0]  id_mem_size, id_wb_sel;
    wire        id_reg_write, id_csr_we, id_csr_imm;
    wire [1:0]  id_csr_op;
    wire [3:0]  id_sys_op;
    wire        id_muldiv_sel;
    wire [3:0]  id_muldiv_op;
    wire        id_atomic_sel;
    wire [4:0]  id_amo_op;
    wire        id_is_lr, id_is_sc;
    wire        id_illegal, id_fetch_fault;

    // ID/EX -> EX
    wire [31:0] ex_pc, ex_pc_next, ex_rs1_data, ex_rs2_data;
    wire [31:0] ex_imm, ex_csr_wdata;
    wire [4:0]  ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire [11:0] ex_csr_addr;
    wire [4:0]  ex_alu_op;
    wire        ex_alu_src_a, ex_alu_src_b;
    wire [2:0]  ex_branch_funct3;
    wire        ex_branch, ex_jump;
    wire        ex_use_rs1, ex_use_rs2;
    wire        ex_mem_read_w, ex_mem_write_w, ex_mem_unsigned_w;
    wire [1:0]  ex_mem_size_w, ex_wb_sel_w;
    wire        ex_reg_write_w, ex_csr_we_w;
    wire [1:0]  ex_csr_op_w;
    wire [3:0]  ex_sys_op_w;
    wire        ex_muldiv_sel_w;
    wire [3:0]  ex_muldiv_op_w;
    wire        ex_atomic_sel_w;
    wire [4:0]  ex_amo_op_w;
    wire        ex_is_lr_w, ex_is_sc_w;
    wire        ex_illegal_w, ex_fetch_fault_w;

    // EX stage outputs
    wire [31:0] ex_alu_result_w, ex_store_data_w, ex_redirect_target_w;
    wire        ex_branch_taken_w, ex_redirect_w, ex_muldiv_stall_w;

    // EX/MEM -> MEM
    wire [31:0] mem_pc, mem_pc_next, mem_alu_result, mem_store_data, mem_csr_wdata;
    wire [11:0] mem_csr_addr;
    wire [4:0]  mem_rd_addr;
    wire        mem_read, mem_write, mem_unsigned;
    wire [1:0]  mem_size, mem_wb_sel;
    wire        mem_reg_write, mem_csr_we;
    wire [1:0]  mem_csr_op;
    wire [3:0]  mem_sys_op;
    wire        mem_atomic_sel;
    wire [4:0]  mem_amo_op;
    wire        mem_is_lr, mem_is_sc;
    wire        mem_illegal, mem_fetch_fault_w;

    // MEM -> MEM/WB
    wire [31:0] mem_rdata_w;
    wire        mem_fault_w, mem_stall_w;

    // MEM/WB -> WB
    wire [31:0] wb_pc, wb_pc_next, wb_alu_result_w, wb_rdata, wb_csr_wdata;
    wire [11:0] wb_csr_addr;
    wire [4:0]  wb_rd_addr;
    wire [1:0]  wb_sel, wb_csr_op;
    wire [3:0]  wb_sys_op;
    wire        wb_reg_write, wb_csr_we;
    wire        wb_illegal, wb_fetch_fault, wb_mem_fault;

    // WB stage outputs
    wire        wb_csr_we_out;
    wire [11:0] wb_csr_addr_out;
    wire [1:0]  wb_csr_op_out;
    wire [31:0] wb_csr_wdata_out;
    wire        wb_mret, wb_sret;
    wire        wb_trap_enter;
    wire [3:0]  wb_trap_cause;
    wire [31:0] wb_trap_epc, wb_trap_tval;
    wire        wb_trap_is_int;
    wire        wb_rf_we;
    wire [4:0]  wb_rf_rd_addr;
    wire [31:0] wb_rf_rd_data;
    wire        wb_redirect;
    wire [31:0] wb_redirect_pc;
    wire        wb_retire;

    // CSR file
    wire [31:0] csr_rdata_w;
    wire        csr_illegal_w;
    wire [1:0]  current_priv_w;
    wire [31:0] csr_trap_target;
    wire [31:0] csr_xret_pc;

    // Hazard unit
    wire        hazard_stall;
    wire        hazard_flush_ifid;
    wire        hazard_flush_idex;

    //=================================================================
    // Top-level redirect / stall network
    //=================================================================
    wire        redirect_any = ex_redirect_w || wb_redirect;
    wire [31:0] redirect_pc  = wb_redirect ? wb_redirect_pc : ex_redirect_target_w;

    wire stall_up   = hazard_stall || mem_stall_w;
    wire stall_down = ex_muldiv_stall_w || mem_stall_w;

    wire flush_if_id  = hazard_flush_ifid || wb_redirect;
    wire flush_id_ex  = hazard_flush_idex || wb_redirect;
    wire flush_ex_mem = wb_redirect;
    wire flush_mem_wb = wb_redirect;

    //=================================================================
    // IF stage
    //=================================================================
    if_stage u_if (
        .clk(clk), .rst_n(rst_n),
        .stall(stall_up),
        .redirect(redirect_any),
        .redirect_target(redirect_pc),
        .mem_req_valid(imem_req_valid),
        .mem_req_ready(imem_req_ready),
        .mem_req_addr(imem_req_addr),
        .mem_rsp_valid(imem_rsp_valid),
        .mem_rsp_ready(imem_rsp_ready),
        .mem_rsp_rdata(imem_rsp_rdata),
        .mem_rsp_error(imem_rsp_error),
        .if_pc(if_pc),
        .if_pc_next(if_pc_next),
        .if_inst(if_inst),
        .if_fetch_fault(if_fetch_fault),
        .if_valid(if_valid)
    );

    assign pc_out = if_pc;

    //=================================================================
    // IF/ID pipeline register
    //=================================================================
    if_id u_if_id (
        .clk(clk), .rst_n(rst_n),
        .stall(stall_up),
        .flush(flush_if_id),
        .if_pc(if_pc),
        .if_pc_next(if_pc_next),
        .if_inst(if_inst),
        .if_fetch_fault(if_fetch_fault),
        .id_pc(ifid_pc),
        .id_pc_next(ifid_pc_next),
        .id_inst(ifid_inst),
        .id_fetch_fault(ifid_fetch_fault)
    );

    //=================================================================
    // ID stage
    //=================================================================
    id_stage u_id (
        .clk(clk), .rst_n(rst_n),
        .if_pc(ifid_pc),
        .if_pc_next(ifid_pc_next),
        .if_inst(ifid_inst),
        .if_fetch_fault(ifid_fetch_fault),
        .wb_reg_write(wb_rf_we),
        .wb_rd_addr(wb_rf_rd_addr),
        .wb_rd_data(wb_rf_rd_data),
        .id_pc(id_pc),
        .id_pc_next(id_pc_next),
        .id_rs1_data(id_rs1_data),
        .id_rs2_data(id_rs2_data),
        .id_imm(id_imm),
        .id_csr_wdata(id_csr_wdata),
        .id_rs1_addr(id_rs1_addr),
        .id_rs2_addr(id_rs2_addr),
        .id_rd_addr(id_rd_addr),
        .id_csr_addr(id_csr_addr),
        .id_alu_op(id_alu_op),
        .id_alu_src_a(id_alu_src_a),
        .id_alu_src_b(id_alu_src_b),
        .id_branch_funct3(id_branch_funct3),
        .id_branch(id_branch),
        .id_jump(id_jump),
        .id_use_rs1(id_use_rs1),
        .id_use_rs2(id_use_rs2),
        .id_mem_read(id_mem_read),
        .id_mem_write(id_mem_write),
        .id_mem_size(id_mem_size),
        .id_mem_unsigned(id_mem_unsigned),
        .id_wb_sel(id_wb_sel),
        .id_reg_write(id_reg_write),
        .id_csr_we(id_csr_we),
        .id_csr_op(id_csr_op),
        .id_csr_imm(id_csr_imm),
        .id_sys_op(id_sys_op),
        .id_muldiv_sel(id_muldiv_sel),
        .id_muldiv_op(id_muldiv_op),
        .id_atomic_sel(id_atomic_sel),
        .id_amo_op(id_amo_op),
        .id_is_lr(id_is_lr),
        .id_is_sc(id_is_sc),
        .id_illegal(id_illegal),
        .id_fetch_fault(id_fetch_fault)
    );

    //=================================================================
    // ID/EX pipeline register
    //=================================================================
    id_ex u_id_ex (
        .clk(clk), .rst_n(rst_n),
        .stall(stall_up),
        .flush(flush_id_ex),
        .id_pc(id_pc),
        .id_pc_next(id_pc_next),
        .id_rs1_data(id_rs1_data),
        .id_rs2_data(id_rs2_data),
        .id_imm(id_imm),
        .id_csr_wdata(id_csr_wdata),
        .id_rs1_addr(id_rs1_addr),
        .id_rs2_addr(id_rs2_addr),
        .id_rd_addr(id_rd_addr),
        .id_csr_addr(id_csr_addr),
        .id_alu_op(id_alu_op),
        .id_alu_src_a(id_alu_src_a),
        .id_alu_src_b(id_alu_src_b),
        .id_branch_funct3(id_branch_funct3),
        .id_branch(id_branch),
        .id_jump(id_jump),
        .id_use_rs1(id_use_rs1),
        .id_use_rs2(id_use_rs2),
        .id_mem_read(id_mem_read),
        .id_mem_write(id_mem_write),
        .id_mem_size(id_mem_size),
        .id_mem_unsigned(id_mem_unsigned),
        .id_wb_sel(id_wb_sel),
        .id_reg_write(id_reg_write),
        .id_csr_we(id_csr_we),
        .id_csr_op(id_csr_op),
        .id_sys_op(id_sys_op),
        .id_muldiv_sel(id_muldiv_sel),
        .id_muldiv_op(id_muldiv_op),
        .id_atomic_sel(id_atomic_sel),
        .id_amo_op(id_amo_op),
        .id_is_lr(id_is_lr),
        .id_is_sc(id_is_sc),
        .id_illegal(id_illegal),
        .id_fetch_fault(id_fetch_fault),
        .ex_pc(ex_pc),
        .ex_pc_next(ex_pc_next),
        .ex_rs1_data(ex_rs1_data),
        .ex_rs2_data(ex_rs2_data),
        .ex_imm(ex_imm),
        .ex_csr_wdata(ex_csr_wdata),
        .ex_rs1_addr(ex_rs1_addr),
        .ex_rs2_addr(ex_rs2_addr),
        .ex_rd_addr(ex_rd_addr),
        .ex_csr_addr(ex_csr_addr),
        .ex_alu_op(ex_alu_op),
        .ex_alu_src_a(ex_alu_src_a),
        .ex_alu_src_b(ex_alu_src_b),
        .ex_branch_funct3(ex_branch_funct3),
        .ex_branch(ex_branch),
        .ex_jump(ex_jump),
        .ex_use_rs1(ex_use_rs1),
        .ex_use_rs2(ex_use_rs2),
        .ex_mem_read(ex_mem_read_w),
        .ex_mem_write(ex_mem_write_w),
        .ex_mem_size(ex_mem_size_w),
        .ex_mem_unsigned(ex_mem_unsigned_w),
        .ex_wb_sel(ex_wb_sel_w),
        .ex_reg_write(ex_reg_write_w),
        .ex_csr_we(ex_csr_we_w),
        .ex_csr_op(ex_csr_op_w),
        .ex_sys_op(ex_sys_op_w),
        .ex_muldiv_sel(ex_muldiv_sel_w),
        .ex_muldiv_op(ex_muldiv_op_w),
        .ex_atomic_sel(ex_atomic_sel_w),
        .ex_amo_op(ex_amo_op_w),
        .ex_is_lr(ex_is_lr_w),
        .ex_is_sc(ex_is_sc_w),
        .ex_illegal(ex_illegal_w),
        .ex_fetch_fault(ex_fetch_fault_w)
    );

    //=================================================================
    // EX stage
    //=================================================================
    ex_stage u_ex (
        .clk(clk), .rst_n(rst_n),
        .ex_pc(ex_pc),
        .ex_rs1_data(ex_rs1_data),
        .ex_rs2_data(ex_rs2_data),
        .ex_imm(ex_imm),
        .ex_rs1_addr(ex_rs1_addr),
        .ex_rs2_addr(ex_rs2_addr),
        .ex_alu_op(ex_alu_op),
        .ex_alu_src_a(ex_alu_src_a),
        .ex_alu_src_b(ex_alu_src_b),
        .ex_branch_funct3(ex_branch_funct3),
        .ex_branch(ex_branch),
        .ex_jump(ex_jump),
        .ex_use_rs1(ex_use_rs1),
        .ex_use_rs2(ex_use_rs2),
        .ex_muldiv_sel(ex_muldiv_sel_w),
        .ex_muldiv_op(ex_muldiv_op_w),
        .mem_reg_write(mem_reg_write),
        .mem_rd_addr(mem_rd_addr),
        .mem_alu_result(mem_alu_result),
        .wb_reg_write(wb_rf_we),
        .wb_rd_addr(wb_rf_rd_addr),
        .wb_rd_data(wb_rf_rd_data),
        .alu_result(ex_alu_result_w),
        .store_data(ex_store_data_w),
        .branch_taken(ex_branch_taken_w),
        .redirect(ex_redirect_w),
        .redirect_target(ex_redirect_target_w),
        .muldiv_stall(ex_muldiv_stall_w)
    );

    //=================================================================
    // EX/MEM pipeline register
    //=================================================================
    ex_mem u_ex_mem (
        .clk(clk), .rst_n(rst_n),
        .stall(stall_down),
        .flush(flush_ex_mem),
        .ex_pc(ex_pc),
        .ex_pc_next(ex_pc_next),
        .ex_alu_result(ex_alu_result_w),
        .ex_store_data(ex_store_data_w),
        .ex_csr_wdata(ex_csr_wdata),
        .ex_csr_addr(ex_csr_addr),
        .ex_rd_addr(ex_rd_addr),
        .ex_mem_read(ex_mem_read_w),
        .ex_mem_write(ex_mem_write_w),
        .ex_mem_size(ex_mem_size_w),
        .ex_mem_unsigned(ex_mem_unsigned_w),
        .ex_wb_sel(ex_wb_sel_w),
        .ex_reg_write(ex_reg_write_w),
        .ex_csr_we(ex_csr_we_w),
        .ex_csr_op(ex_csr_op_w),
        .ex_sys_op(ex_sys_op_w),
        .ex_atomic_sel(ex_atomic_sel_w),
        .ex_amo_op(ex_amo_op_w),
        .ex_is_lr(ex_is_lr_w),
        .ex_is_sc(ex_is_sc_w),
        .ex_illegal(ex_illegal_w),
        .ex_fetch_fault(ex_fetch_fault_w),
        .mem_pc(mem_pc),
        .mem_pc_next(mem_pc_next),
        .mem_alu_result(mem_alu_result),
        .mem_store_data(mem_store_data),
        .mem_csr_wdata(mem_csr_wdata),
        .mem_csr_addr(mem_csr_addr),
        .mem_rd_addr(mem_rd_addr),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_size(mem_size),
        .mem_unsigned(mem_unsigned),
        .mem_wb_sel(mem_wb_sel),
        .mem_reg_write(mem_reg_write),
        .mem_csr_we(mem_csr_we),
        .mem_csr_op(mem_csr_op),
        .mem_sys_op(mem_sys_op),
        .mem_atomic_sel(mem_atomic_sel),
        .mem_amo_op(mem_amo_op),
        .mem_is_lr(mem_is_lr),
        .mem_is_sc(mem_is_sc),
        .mem_illegal(mem_illegal),
        .mem_fetch_fault(mem_fetch_fault_w)
    );

    //=================================================================
    // MEM stage
    //=================================================================
    mem_stage u_mem (
        .clk(clk), .rst_n(rst_n),
        .mem_alu_result(mem_alu_result),
        .mem_store_data(mem_store_data),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_size(mem_size),
        .mem_unsigned(mem_unsigned),
        .mem_atomic_sel(mem_atomic_sel),
        .mem_amo_op(mem_amo_op),
        .mem_is_lr(mem_is_lr),
        .mem_is_sc(mem_is_sc),
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
        .mem_rdata(mem_rdata_w),
        .mem_fault(mem_fault_w),
        .mem_stall(mem_stall_w)
    );

    //=================================================================
    // MEM/WB pipeline register
    //=================================================================
    mem_wb u_mem_wb (
        .clk(clk), .rst_n(rst_n),
        .stall(stall_down),
        .flush(flush_mem_wb),
        .mem_pc(mem_pc),
        .mem_pc_next(mem_pc_next),
        .mem_alu_result(mem_alu_result),
        .mem_rdata(mem_rdata_w),
        .mem_csr_wdata(mem_csr_wdata),
        .mem_csr_addr(mem_csr_addr),
        .mem_rd_addr(mem_rd_addr),
        .mem_wb_sel(mem_wb_sel),
        .mem_csr_op(mem_csr_op),
        .mem_sys_op(mem_sys_op),
        .mem_reg_write(mem_reg_write),
        .mem_csr_we(mem_csr_we),
        .mem_illegal(mem_illegal),
        .mem_fetch_fault(mem_fetch_fault_w),
        .mem_fault(mem_fault_w),
        .wb_pc(wb_pc),
        .wb_pc_next(wb_pc_next),
        .wb_alu_result(wb_alu_result_w),
        .wb_rdata(wb_rdata),
        .wb_csr_wdata(wb_csr_wdata),
        .wb_csr_addr(wb_csr_addr),
        .wb_rd_addr(wb_rd_addr),
        .wb_sel(wb_sel),
        .wb_csr_op(wb_csr_op),
        .wb_sys_op(wb_sys_op),
        .wb_reg_write(wb_reg_write),
        .wb_csr_we(wb_csr_we),
        .wb_illegal(wb_illegal),
        .wb_fetch_fault(wb_fetch_fault),
        .wb_mem_fault(wb_mem_fault)
    );

    //=================================================================
    // WB stage
    //=================================================================
    wb_stage u_wb (
        .clk(clk), .rst_n(rst_n),
        .wb_pc(wb_pc),
        .wb_pc_next(wb_pc_next),
        .wb_alu_result(wb_alu_result_w),
        .wb_rdata(wb_rdata),
        .wb_csr_wdata(wb_csr_wdata),
        .wb_csr_addr(wb_csr_addr),
        .wb_rd_addr(wb_rd_addr),
        .wb_sel(wb_sel),
        .wb_csr_op(wb_csr_op),
        .wb_sys_op(wb_sys_op),
        .wb_reg_write(wb_reg_write),
        .wb_csr_we(wb_csr_we),
        .wb_illegal(wb_illegal),
        .wb_fetch_fault(wb_fetch_fault),
        .wb_mem_fault(wb_mem_fault),
        .csr_we(wb_csr_we_out),
        .csr_addr(wb_csr_addr_out),
        .csr_op(wb_csr_op_out),
        .csr_wdata(wb_csr_wdata_out),
        .csr_rdata(csr_rdata_w),
        .csr_illegal(csr_illegal_w),
        .current_priv(current_priv_w),
        .trap_target(csr_trap_target),
        .xret_pc(csr_xret_pc),
        .mret(wb_mret),
        .sret(wb_sret),
        .trap_enter(wb_trap_enter),
        .trap_cause(wb_trap_cause),
        .trap_epc(wb_trap_epc),
        .trap_tval(wb_trap_tval),
        .trap_is_interrupt(wb_trap_is_int),
        .rf_we(wb_rf_we),
        .rf_rd_addr(wb_rf_rd_addr),
        .rf_rd_data(wb_rf_rd_data),
        .wb_redirect(wb_redirect),
        .wb_redirect_pc(wb_redirect_pc),
        .retire(wb_retire)
    );

    //=================================================================
    // CSR file
    //=================================================================
    csr_file #(.HARTID(32'h0)) u_csr (
        .clk(clk), .rst_n(rst_n),
        .csr_we(wb_csr_we_out),
        .csr_addr(wb_csr_addr_out),
        .csr_op(wb_csr_op_out),
        .csr_wdata(wb_csr_wdata_out),
        .csr_rdata(csr_rdata_w),
        .csr_illegal(csr_illegal_w),
        .current_priv(current_priv_w),
        .trap_enter(wb_trap_enter),
        .trap_cause(wb_trap_cause),
        .trap_epc(wb_trap_epc),
        .trap_tval(wb_trap_tval),
        .trap_is_interrupt(wb_trap_is_int),
        .trap_target(csr_trap_target),
        .mret(wb_mret),
        .sret(wb_sret),
        .xret_pc(csr_xret_pc),
        .timer_irq(timer_irq),
        .ext_irq(ext_irq),
        .mie_out(),
        .mip_out(),
        .retire(wb_retire),
        .satp_out()
    );

    //=================================================================
    // Hazard unit
    //=================================================================
    hazard_unit u_haz (
        .ex_mem_read(ex_mem_read_w),
        .ex_reg_write(ex_reg_write_w),
        .ex_rd_addr(ex_rd_addr),
        .id_use_rs1(id_use_rs1),
        .id_use_rs2(id_use_rs2),
        .id_rs1_addr(id_rs1_addr),
        .id_rs2_addr(id_rs2_addr),
        .ex_branch_taken(ex_branch_taken_w),
        .ex_jump(ex_jump),
        .ex_trap(1'b0),
        .muldiv_stall(ex_muldiv_stall_w),
        .stall(hazard_stall),
        .flush_if_id(hazard_flush_ifid),
        .flush_id_ex(hazard_flush_idex)
    );

    //=================================================================
    // Debug outputs
    //=================================================================
    assign current_priv = current_priv_w;
    assign retire       = wb_retire;

endmodule