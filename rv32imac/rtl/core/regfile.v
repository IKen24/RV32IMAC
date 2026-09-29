//=============================================================================
// Module:      regfile
// File:        rtl/core/regfile.v
// Description: 32 x 32-bit RISC-V general-purpose register file.
//              Two combinational read ports, one synchronous write port.
//              x0 is hardwired to zero (reads as 0, writes discarded).
//              Write-first behavior: if a write commits this cycle and a
//              read port targets the same register, that read returns the
//              new value. This eliminates the read-during-write hazard
//              without a pipeline bubble.
// Latency:     Read = combinational. Write = 1 cycle (posedge).
// Reset:       Synchronous active-low rst_n clears all registers.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module regfile (
    input  wire        clk,
    input  wire        rst_n,

    // Read port 1
    input  wire [4:0]  rs1_addr,
    output wire [31:0] rs1_data,

    // Read port 2
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs2_data,

    // Write port
    input  wire        reg_write,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data
);

    reg [31:0] regs [0:31];

    integer i;

    // Synchronous write + synchronous reset.
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (reg_write && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end

    // Write-first read ports, x0 forced to zero.
    assign rs1_data = (rs1_addr == 5'd0) ? 32'b0 :
                      (reg_write && (rd_addr == rs1_addr)) ? rd_data :
                      regs[rs1_addr];

    assign rs2_data = (rs2_addr == 5'd0) ? 32'b0 :
                      (reg_write && (rd_addr == rs2_addr)) ? rd_data :
                      regs[rs2_addr];

endmodule