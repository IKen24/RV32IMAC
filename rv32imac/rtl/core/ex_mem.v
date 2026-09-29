//=============================================================================
// Module:      ex_mem
// File:        rtl/core/ex_mem.v
// Description: EX/MEM pipeline register.
//              Carries the computed ALU result (address for loads/stores or
//              the value for ALU/muldiv ops), store data, CSR payload, and
//              all control signals MEM and WB will need.
//              On flush: all outputs zeroed (bubble).
//              On stall: outputs hold. (Currently MEM never stalls; the
//              input exists for cache/AMO stall use later.)
// Reset:       Synchronous active-low rst_n. All outputs = 0.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module ex_mem (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,

    // --- Inputs from EX stage ---
    input  wire [31:0] ex_pc,
    input  wire [31:0] ex_pc_next,
    input  wire [31:0] ex_alu_result,
    input  wire [31:0] ex_store_data,
    input  wire [31:0] ex_csr_wdata,
    input  wire [11:0] ex_csr_addr,
    input  wire [4:0]  ex_rd_addr,
    input  wire        ex_mem_read,
    input  wire        ex_mem_write,
    input  wire [1:0]  ex_mem_size,
    input  wire        ex_mem_unsigned,
    input  wire [1:0]  ex_wb_sel,
    input  wire        ex_reg_write,
    input  wire        ex_csr_we,
    input  wire [1:0]  ex_csr_op,
    input  wire [3:0]  ex_sys_op,
    input  wire        ex_atomic_sel,
    input  wire [4:0]  ex_amo_op,
    input  wire        ex_is_lr,
    input  wire        ex_is_sc,
    input  wire        ex_illegal,
    input  wire        ex_fetch_fault,

    // --- Outputs to MEM stage ---
    output reg  [31:0] mem_pc,
    output reg  [31:0] mem_pc_next,
    output reg  [31:0] mem_alu_result,
    output reg  [31:0] mem_store_data,
    output reg  [31:0] mem_csr_wdata,
    output reg  [11:0] mem_csr_addr,
    output reg  [4:0]  mem_rd_addr,
    output reg         mem_read,
    output reg         mem_write,
    output reg  [1:0]  mem_size,
    output reg         mem_unsigned,
    output reg  [1:0]  mem_wb_sel,
    output reg         mem_reg_write,
    output reg         mem_csr_we,
    output reg  [1:0]  mem_csr_op,
    output reg  [3:0]  mem_sys_op,
    output reg         mem_atomic_sel,
    output reg  [4:0]  mem_amo_op,
    output reg         mem_is_lr,
    output reg         mem_is_sc,
    output reg         mem_illegal,
    output reg         mem_fetch_fault
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_pc          <= 32'b0;
            mem_pc_next     <= 32'b0;
            mem_alu_result  <= 32'b0;
            mem_store_data  <= 32'b0;
            mem_csr_wdata   <= 32'b0;
            mem_csr_addr    <= 12'b0;
            mem_rd_addr     <= 5'b0;
            mem_read        <= 1'b0;
            mem_write       <= 1'b0;
            mem_size        <= 2'b0;
            mem_unsigned    <= 1'b0;
            mem_wb_sel      <= 2'b0;
            mem_reg_write   <= 1'b0;
            mem_csr_we      <= 1'b0;
            mem_csr_op      <= 2'b0;
            mem_sys_op      <= 4'b0;
            mem_atomic_sel  <= 1'b0;
            mem_amo_op      <= 5'b0;
            mem_is_lr       <= 1'b0;
            mem_is_sc       <= 1'b0;
            mem_illegal     <= 1'b0;
            mem_fetch_fault <= 1'b0;
        end else if (flush) begin
            mem_pc          <= 32'b0;
            mem_pc_next     <= 32'b0;
            mem_alu_result  <= 32'b0;
            mem_store_data  <= 32'b0;
            mem_csr_wdata   <= 32'b0;
            mem_csr_addr    <= 12'b0;
            mem_rd_addr     <= 5'b0;
            mem_read        <= 1'b0;
            mem_write       <= 1'b0;
            mem_size        <= 2'b0;
            mem_unsigned    <= 1'b0;
            mem_wb_sel      <= 2'b0;
            mem_reg_write   <= 1'b0;
            mem_csr_we      <= 1'b0;
            mem_csr_op      <= 2'b0;
            mem_sys_op      <= 4'b0;
            mem_atomic_sel  <= 1'b0;
            mem_amo_op      <= 5'b0;
            mem_is_lr       <= 1'b0;
            mem_is_sc       <= 1'b0;
            mem_illegal     <= 1'b0;
            mem_fetch_fault <= 1'b0;
        end else if (!stall) begin
            mem_pc          <= ex_pc;
            mem_pc_next     <= ex_pc_next;
            mem_alu_result  <= ex_alu_result;
            mem_store_data  <= ex_store_data;
            mem_csr_wdata   <= ex_csr_wdata;
            mem_csr_addr    <= ex_csr_addr;
            mem_rd_addr     <= ex_rd_addr;
            mem_read        <= ex_mem_read;
            mem_write       <= ex_mem_write;
            mem_size        <= ex_mem_size;
            mem_unsigned    <= ex_mem_unsigned;
            mem_wb_sel      <= ex_wb_sel;
            mem_reg_write   <= ex_reg_write;
            mem_csr_we      <= ex_csr_we;
            mem_csr_op      <= ex_csr_op;
            mem_sys_op      <= ex_sys_op;
            mem_atomic_sel  <= ex_atomic_sel;
            mem_amo_op      <= ex_amo_op;
            mem_is_lr       <= ex_is_lr;
            mem_is_sc       <= ex_is_sc;
            mem_illegal     <= ex_illegal;
            mem_fetch_fault <= ex_fetch_fault;
        end
    end

endmodule