//=============================================================================
// Module:      id_stage
// File:        rtl/core/id_stage.v
// Description: ID stage. Wraps decoder + imm_gen + regfile.
//              Consumes the RVC-expanded 32-bit instruction from IF/ID,
//              produces every control signal ID/EX needs plus operand data,
//              immediate, and the CSR write payload.
//              The CSR read is deferred to WB; only the CSR write-data is
//              computed here (register value or zero-extended zimm).
//              regfile write port is driven by the WB stage from the top
//              level — the regfile instance lives inside this module.
//              Branch funct3 is a direct wire-through of inst[14:12]; the
//              decoder separately validates it.
// Reset:       Passed through to the regfile.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module id_stage (
    input  wire        clk,
    input  wire        rst_n,

    // ---- From IF/ID register ----
    input  wire [31:0] if_pc,
    input  wire [31:0] if_pc_next,
    input  wire [31:0] if_inst,
    input  wire        if_fetch_fault,

    // ---- WB write port to the regfile ----
    input  wire        wb_reg_write,
    input  wire [4:0]  wb_rd_addr,
    input  wire [31:0] wb_rd_data,

    // ---- To ID/EX register ----
    output wire [31:0] id_pc,
    output wire [31:0] id_pc_next,
    output wire [31:0] id_rs1_data,
    output wire [31:0] id_rs2_data,
    output wire [31:0] id_imm,
    output wire [31:0] id_csr_wdata,
    output wire [4:0]  id_rs1_addr,
    output wire [4:0]  id_rs2_addr,
    output wire [4:0]  id_rd_addr,
    output wire [11:0] id_csr_addr,
    output wire [4:0]  id_alu_op,
    output wire        id_alu_src_a,
    output wire        id_alu_src_b,
    output wire [2:0]  id_branch_funct3,
    output wire        id_branch,
    output wire        id_jump,
    output wire        id_use_rs1,
    output wire        id_use_rs2,
    output wire        id_mem_read,
    output wire        id_mem_write,
    output wire [1:0]  id_mem_size,
    output wire        id_mem_unsigned,
    output wire [1:0]  id_wb_sel,
    output wire        id_reg_write,
    output wire        id_csr_we,
    output wire [1:0]  id_csr_op,
    output wire        id_csr_imm,
    output wire [3:0]  id_sys_op,
    output wire        id_muldiv_sel,
    output wire [3:0]  id_muldiv_op,
    output wire        id_atomic_sel,
    output wire [4:0]  id_amo_op,
    output wire        id_is_lr,
    output wire        id_is_sc,
    output wire        id_illegal,
    output wire        id_fetch_fault
);

    //------------------------------------------------------------------
    // Decoder
    //------------------------------------------------------------------
    wire [4:0]  dec_rs1_addr, dec_rs2_addr, dec_rd_addr;
    wire [11:0] dec_csr_addr;
    wire [4:0]  dec_alu_op;
    wire        dec_alu_src_a, dec_alu_src_b;
    wire        dec_use_rs1, dec_use_rs2, dec_reg_write;
    wire [2:0]  dec_imm_sel;
    wire        dec_mem_read, dec_mem_write, dec_mem_unsigned;
    wire [1:0]  dec_mem_size, dec_wb_sel;
    wire        dec_branch, dec_jump;
    wire        dec_csr_we, dec_csr_imm;
    wire [1:0]  dec_csr_op;
    wire [3:0]  dec_sys_op;
    wire        dec_muldiv_sel;
    wire [3:0]  dec_muldiv_op;
    wire        dec_atomic_sel;
    wire [4:0]  dec_amo_op;
    wire        dec_is_lr, dec_is_sc, dec_illegal;

    decoder u_dec (
        .inst         (if_inst),
        .rs1_addr     (dec_rs1_addr),
        .rs2_addr     (dec_rs2_addr),
        .rd_addr      (dec_rd_addr),
        .csr_addr     (dec_csr_addr),
        .use_rs1      (dec_use_rs1),
        .use_rs2      (dec_use_rs2),
        .reg_write    (dec_reg_write),
        .imm_sel      (dec_imm_sel),
        .alu_op       (dec_alu_op),
        .alu_src_a    (dec_alu_src_a),
        .alu_src_b    (dec_alu_src_b),
        .mem_read     (dec_mem_read),
        .mem_write    (dec_mem_write),
        .mem_size     (dec_mem_size),
        .mem_unsigned (dec_mem_unsigned),
        .wb_sel       (dec_wb_sel),
        .branch       (dec_branch),
        .jump         (dec_jump),
        .csr_we       (dec_csr_we),
        .csr_op       (dec_csr_op),
        .csr_imm      (dec_csr_imm),
        .sys_op       (dec_sys_op),
        .muldiv_sel   (dec_muldiv_sel),
        .muldiv_op    (dec_muldiv_op),
        .atomic_sel   (dec_atomic_sel),
        .amo_op       (dec_amo_op),
        .is_lr        (dec_is_lr),
        .is_sc        (dec_is_sc),
        .illegal      (dec_illegal)
    );

    //------------------------------------------------------------------
    // Immediate
    //------------------------------------------------------------------
    wire [31:0] imm;
    imm_gen u_imm (
        .inst (if_inst),
        .imm  (imm)
    );

    //------------------------------------------------------------------
    // Register file
    //------------------------------------------------------------------
    wire [31:0] rs1_data, rs2_data;

    regfile u_rf (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1_addr  (dec_rs1_addr),
        .rs1_data  (rs1_data),
        .rs2_addr  (dec_rs2_addr),
        .rs2_data  (rs2_data),
        .reg_write (wb_reg_write),
        .rd_addr   (wb_rd_addr),
        .rd_data   (wb_rd_data)
    );

    //------------------------------------------------------------------
    // CSR write payload: register value, or zero-extended zimm
    //------------------------------------------------------------------
    wire [31:0] csr_wdata = dec_csr_imm
                            ? {27'b0, if_inst[19:15]}
                            : rs1_data;

    //------------------------------------------------------------------
    // Outputs
    //------------------------------------------------------------------
    assign id_pc             = if_pc;
    assign id_pc_next        = if_pc_next;
    assign id_rs1_data       = rs1_data;
    assign id_rs2_data       = rs2_data;
    assign id_imm            = imm;
    assign id_csr_wdata      = csr_wdata;
    assign id_rs1_addr       = dec_rs1_addr;
    assign id_rs2_addr       = dec_rs2_addr;
    assign id_rd_addr        = dec_rd_addr;
    assign id_csr_addr       = dec_csr_addr;
    assign id_alu_op         = dec_alu_op;
    assign id_alu_src_a      = dec_alu_src_a;
    assign id_alu_src_b      = dec_alu_src_b;
    assign id_branch_funct3  = if_inst[14:12];
    assign id_branch         = dec_branch;
    assign id_jump           = dec_jump;
    assign id_use_rs1        = dec_use_rs1;
    assign id_use_rs2        = dec_use_rs2;
    assign id_mem_read       = dec_mem_read;
    assign id_mem_write      = dec_mem_write;
    assign id_mem_size       = dec_mem_size;
    assign id_mem_unsigned   = dec_mem_unsigned;
    assign id_wb_sel         = dec_wb_sel;
    assign id_reg_write      = dec_reg_write;
    assign id_csr_we         = dec_csr_we;
    assign id_csr_op         = dec_csr_op;
    assign id_csr_imm        = dec_csr_imm;
    assign id_sys_op         = dec_sys_op;
    assign id_muldiv_sel     = dec_muldiv_sel;
    assign id_muldiv_op      = dec_muldiv_op;
    assign id_atomic_sel     = dec_atomic_sel;
    assign id_amo_op         = dec_amo_op;
    assign id_is_lr          = dec_is_lr;
    assign id_is_sc          = dec_is_sc;
    assign id_illegal        = dec_illegal;
    assign id_fetch_fault    = if_fetch_fault;

endmodule