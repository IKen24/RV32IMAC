//=============================================================================
// Module:      id_ex
// File:        rtl/core/id_ex.v
// Description: ID/EX pipeline register.
//              Carries operand data, addresses, and full decode control
//              from ID into EX. Also carries all signals MEM and WB will
//              later need — this avoids split-brain wiring bugs at the cost
//              of a wider register; synthesis prunes unused bits.
//              On flush: all outputs go to 0 (bubble). Note that 0 control
//              bits means no register write, no memory access, no CSR write.
//              On stall: outputs hold.
// Reset:       Synchronous active-low rst_n. All outputs = 0.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module id_ex (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    // --- Inputs from ID stage ---
    input  wire [31:0] id_pc,
    input  wire [31:0] id_pc_next,
    input  wire [31:0] id_rs1_data,
    input  wire [31:0] id_rs2_data,
    input  wire [31:0] id_imm,
    input  wire [31:0] id_csr_wdata,
    input  wire [4:0]  id_rs1_addr,
    input  wire [4:0]  id_rs2_addr,
    input  wire [4:0]  id_rd_addr,
    input  wire [11:0] id_csr_addr,
    input  wire [4:0]  id_alu_op,
    input  wire        id_alu_src_a,
    input  wire        id_alu_src_b,
    input  wire [2:0]  id_branch_funct3,
    input  wire        id_branch,
    input  wire        id_jump,
    input  wire        id_use_rs1,
    input  wire        id_use_rs2,
    input  wire        id_mem_read,
    input  wire        id_mem_write,
    input  wire [1:0]  id_mem_size,
    input  wire        id_mem_unsigned,
    input  wire [1:0]  id_wb_sel,
    input  wire        id_reg_write,
    input  wire        id_csr_we,
    input  wire [1:0]  id_csr_op,
    input  wire [3:0]  id_sys_op,
    input  wire        id_muldiv_sel,
    input  wire [3:0]  id_muldiv_op,
    input  wire        id_atomic_sel,
    input  wire [4:0]  id_amo_op,
    input  wire        id_is_lr,
    input  wire        id_is_sc,
    input  wire        id_illegal,
    input  wire        id_fetch_fault,

    // --- Outputs to EX stage ---
    output reg  [31:0] ex_pc,
    output reg  [31:0] ex_pc_next,
    output reg  [31:0] ex_rs1_data,
    output reg  [31:0] ex_rs2_data,
    output reg  [31:0] ex_imm,
    output reg  [31:0] ex_csr_wdata,
    output reg  [4:0]  ex_rs1_addr,
    output reg  [4:0]  ex_rs2_addr,
    output reg  [4:0]  ex_rd_addr,
    output reg  [11:0] ex_csr_addr,
    output reg  [4:0]  ex_alu_op,
    output reg         ex_alu_src_a,
    output reg         ex_alu_src_b,
    output reg  [2:0]  ex_branch_funct3,
    output reg         ex_branch,
    output reg         ex_jump,
    output reg         ex_use_rs1,
    output reg         ex_use_rs2,
    output reg         ex_mem_read,
    output reg         ex_mem_write,
    output reg  [1:0]  ex_mem_size,
    output reg         ex_mem_unsigned,
    output reg  [1:0]  ex_wb_sel,
    output reg         ex_reg_write,
    output reg         ex_csr_we,
    output reg  [1:0]  ex_csr_op,
    output reg  [3:0]  ex_sys_op,
    output reg         ex_muldiv_sel,
    output reg  [3:0]  ex_muldiv_op,
    output reg         ex_atomic_sel,
    output reg  [4:0]  ex_amo_op,
    output reg         ex_is_lr,
    output reg         ex_is_sc,
    output reg         ex_illegal,
    output reg         ex_fetch_fault
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_pc             <= 32'b0;
            ex_pc_next        <= 32'b0;
            ex_rs1_data       <= 32'b0;
            ex_rs2_data       <= 32'b0;
            ex_imm            <= 32'b0;
            ex_csr_wdata      <= 32'b0;
            ex_rs1_addr       <= 5'b0;
            ex_rs2_addr       <= 5'b0;
            ex_rd_addr        <= 5'b0;
            ex_csr_addr       <= 12'b0;
            ex_alu_op         <= 5'b0;
            ex_alu_src_a      <= 1'b0;
            ex_alu_src_b      <= 1'b0;
            ex_branch_funct3  <= 3'b0;
            ex_branch         <= 1'b0;
            ex_jump           <= 1'b0;
            ex_use_rs1        <= 1'b0;
            ex_use_rs2        <= 1'b0;
            ex_mem_read       <= 1'b0;
            ex_mem_write      <= 1'b0;
            ex_mem_size       <= 2'b0;
            ex_mem_unsigned   <= 1'b0;
            ex_wb_sel         <= 2'b0;
            ex_reg_write      <= 1'b0;
            ex_csr_we         <= 1'b0;
            ex_csr_op         <= 2'b0;
            ex_sys_op         <= 4'b0;
            ex_muldiv_sel     <= 1'b0;
            ex_muldiv_op      <= 4'b0;
            ex_atomic_sel     <= 1'b0;
            ex_amo_op         <= 5'b0;
            ex_is_lr          <= 1'b0;
            ex_is_sc          <= 1'b0;
            ex_illegal        <= 1'b0;
            ex_fetch_fault    <= 1'b0;
        end else if (flush) begin
            ex_pc             <= 32'b0;
            ex_pc_next        <= 32'b0;
            ex_rs1_data       <= 32'b0;
            ex_rs2_data       <= 32'b0;
            ex_imm            <= 32'b0;
            ex_csr_wdata      <= 32'b0;
            ex_rs1_addr       <= 5'b0;
            ex_rs2_addr       <= 5'b0;
            ex_rd_addr        <= 5'b0;
            ex_csr_addr       <= 12'b0;
            ex_alu_op         <= 5'b0;
            ex_alu_src_a      <= 1'b0;
            ex_alu_src_b      <= 1'b0;
            ex_branch_funct3  <= 3'b0;
            ex_branch         <= 1'b0;
            ex_jump           <= 1'b0;
            ex_use_rs1        <= 1'b0;
            ex_use_rs2        <= 1'b0;
            ex_mem_read       <= 1'b0;
            ex_mem_write      <= 1'b0;
            ex_mem_size       <= 2'b0;
            ex_mem_unsigned   <= 1'b0;
            ex_wb_sel         <= 2'b0;
            ex_reg_write      <= 1'b0;
            ex_csr_we         <= 1'b0;
            ex_csr_op         <= 2'b0;
            ex_sys_op         <= 4'b0;
            ex_muldiv_sel     <= 1'b0;
            ex_muldiv_op      <= 4'b0;
            ex_atomic_sel     <= 1'b0;
            ex_amo_op         <= 5'b0;
            ex_is_lr          <= 1'b0;
            ex_is_sc          <= 1'b0;
            ex_illegal        <= 1'b0;
            ex_fetch_fault    <= 1'b0;
        end else if (!stall) begin
            ex_pc             <= id_pc;
            ex_pc_next        <= id_pc_next;
            ex_rs1_data       <= id_rs1_data;
            ex_rs2_data       <= id_rs2_data;
            ex_imm            <= id_imm;
            ex_csr_wdata      <= id_csr_wdata;
            ex_rs1_addr       <= id_rs1_addr;
            ex_rs2_addr       <= id_rs2_addr;
            ex_rd_addr        <= id_rd_addr;
            ex_csr_addr       <= id_csr_addr;
            ex_alu_op         <= id_alu_op;
            ex_alu_src_a      <= id_alu_src_a;
            ex_alu_src_b      <= id_alu_src_b;
            ex_branch_funct3  <= id_branch_funct3;
            ex_branch         <= id_branch;
            ex_jump           <= id_jump;
            ex_use_rs1        <= id_use_rs1;
            ex_use_rs2        <= id_use_rs2;
            ex_mem_read       <= id_mem_read;
            ex_mem_write      <= id_mem_write;
            ex_mem_size       <= id_mem_size;
            ex_mem_unsigned   <= id_mem_unsigned;
            ex_wb_sel         <= id_wb_sel;
            ex_reg_write      <= id_reg_write;
            ex_csr_we         <= id_csr_we;
            ex_csr_op         <= id_csr_op;
            ex_sys_op         <= id_sys_op;
            ex_muldiv_sel     <= id_muldiv_sel;
            ex_muldiv_op      <= id_muldiv_op;
            ex_atomic_sel     <= id_atomic_sel;
            ex_amo_op         <= id_amo_op;
            ex_is_lr          <= id_is_lr;
            ex_is_sc          <= id_is_sc;
            ex_illegal        <= id_illegal;
            ex_fetch_fault    <= id_fetch_fault;
        end
    end

endmodule