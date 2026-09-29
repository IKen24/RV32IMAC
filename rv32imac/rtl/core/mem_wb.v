//=============================================================================
// Module:      mem_wb
// File:        rtl/core/mem_wb.v
// Description: MEM/WB pipeline register.
//              Carries everything WB needs to commit the instruction:
//              - pc / pc_next        (trap reporting, PC4 link value)
//              - alu_result          (WB_ALU path)
//              - mem_rdata           (WB_MEM path: load data or AMO old value)
//              - csr_wdata/addr/op   (CSR write commit)
//              - rd_addr, wb_sel, reg_write
//              - sys_op              (ECALL/EBREAK/MRET/SRET at commit)
//              - fault bits          (illegal, fetch_fault, mem_fault)
//              On flush: all outputs zeroed (bubble).
//              On stall: outputs hold. (Currently WB never stalls; input
//              exists for future use, e.g. CSR hazards with a slow peripheral.)
// Reset:       Synchronous active-low rst_n. All outputs = 0.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module mem_wb (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    // --- Inputs from MEM stage ---
    input  wire [31:0] mem_pc,
    input  wire [31:0] mem_pc_next,
    input  wire [31:0] mem_alu_result,
    input  wire [31:0] mem_rdata,
    input  wire [31:0] mem_csr_wdata,
    input  wire [11:0] mem_csr_addr,
    input  wire [4:0]  mem_rd_addr,
    input  wire [1:0]  mem_wb_sel,
    input  wire [1:0]  mem_csr_op,
    input  wire [3:0]  mem_sys_op,
    input  wire        mem_reg_write,
    input  wire        mem_csr_we,
    input  wire        mem_illegal,
    input  wire        mem_fetch_fault,
    input  wire        mem_fault,

    // --- Outputs to WB stage ---
    output reg  [31:0] wb_pc,
    output reg  [31:0] wb_pc_next,
    output reg  [31:0] wb_alu_result,
    output reg  [31:0] wb_rdata,
    output reg  [31:0] wb_csr_wdata,
    output reg  [11:0] wb_csr_addr,
    output reg  [4:0]  wb_rd_addr,
    output reg  [1:0]  wb_sel,
    output reg  [1:0]  wb_csr_op,
    output reg  [3:0]  wb_sys_op,
    output reg         wb_reg_write,
    output reg         wb_csr_we,
    output reg         wb_illegal,
    output reg         wb_fetch_fault,
    output reg         wb_mem_fault
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_pc          <= 32'b0;
            wb_pc_next     <= 32'b0;
            wb_alu_result  <= 32'b0;
            wb_rdata       <= 32'b0;
            wb_csr_wdata   <= 32'b0;
            wb_csr_addr    <= 12'b0;
            wb_rd_addr     <= 5'b0;
            wb_sel         <= 2'b0;
            wb_csr_op      <= 2'b0;
            wb_sys_op      <= 4'b0;
            wb_reg_write   <= 1'b0;
            wb_csr_we      <= 1'b0;
            wb_illegal     <= 1'b0;
            wb_fetch_fault <= 1'b0;
            wb_mem_fault   <= 1'b0;
        end else if (flush) begin
            wb_pc          <= 32'b0;
            wb_pc_next     <= 32'b0;
            wb_alu_result  <= 32'b0;
            wb_rdata       <= 32'b0;
            wb_csr_wdata   <= 32'b0;
            wb_csr_addr    <= 12'b0;
            wb_rd_addr     <= 5'b0;
            wb_sel         <= 2'b0;
            wb_csr_op      <= 2'b0;
            wb_sys_op      <= 4'b0;
            wb_reg_write   <= 1'b0;
            wb_csr_we      <= 1'b0;
            wb_illegal     <= 1'b0;
            wb_fetch_fault <= 1'b0;
            wb_mem_fault   <= 1'b0;
        end else if (!stall) begin
            wb_pc          <= mem_pc;
            wb_pc_next     <= mem_pc_next;
            wb_alu_result  <= mem_alu_result;
            wb_rdata       <= mem_rdata;
            wb_csr_wdata   <= mem_csr_wdata;
            wb_csr_addr    <= mem_csr_addr;
            wb_rd_addr     <= mem_rd_addr;
            wb_sel         <= mem_wb_sel;
            wb_csr_op      <= mem_csr_op;
            wb_sys_op      <= mem_sys_op;
            wb_reg_write   <= mem_reg_write;
            wb_csr_we      <= mem_csr_we;
            wb_illegal     <= mem_illegal;
            wb_fetch_fault <= mem_fetch_fault;
            wb_mem_fault   <= mem_fault;
        end
    end

endmodule