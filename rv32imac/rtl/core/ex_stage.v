//=============================================================================
// Module:      ex_stage
// File:        rtl/core/ex_stage.v
// Description: EX stage.
//              Forwarding + ALU + branch comparator + branch_unit +
//              muldiv issue FSM. Emits alu_result (muxed muldiv or ALU),
//              store_data, branch_taken, redirect, redirect_target, and
//              muldiv_stall.
//              Branch decision uses a dedicated comparator (not ALU flags)
//              so the ALU can simultaneously compute pc + imm for the
//              branch/jump target.
// Reset:       Synchronous active-low rst_n clears the muldiv FSM.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module ex_stage (
    input  wire        clk,
    input  wire        rst_n,

    // ---- From ID/EX ----
    input  wire [31:0] ex_pc,
    input  wire [31:0] ex_rs1_data,
    input  wire [31:0] ex_rs2_data,
    input  wire [31:0] ex_imm,
    input  wire [4:0]  ex_rs1_addr,
    input  wire [4:0]  ex_rs2_addr,
    input  wire [4:0]  ex_alu_op,
    input  wire        ex_alu_src_a,     // 1 = use ex_pc for ALU operand A
    input  wire        ex_alu_src_b,
    input  wire [2:0]  ex_branch_funct3,
    input  wire        ex_branch,
    input  wire        ex_jump,
    input  wire        ex_use_rs1,
    input  wire        ex_use_rs2,
    input  wire        ex_muldiv_sel,
    input  wire [3:0]  ex_muldiv_op,

    // ---- Forwarding sources ----
    input  wire        mem_reg_write,
    input  wire [4:0]  mem_rd_addr,
    input  wire [31:0] mem_alu_result,
    input  wire        wb_reg_write,
    input  wire [4:0]  wb_rd_addr,
    input  wire [31:0] wb_rd_data,

    // ---- Outputs ----
    output wire [31:0] alu_result,
    output wire [31:0] store_data,
    output wire        branch_taken,
    output wire        redirect,
    output wire [31:0] redirect_target,
    output wire        muldiv_stall
);

    //------------------------------------------------------------------
    // Forwarding
    //------------------------------------------------------------------
    wire [1:0] fwd_a_sel, fwd_b_sel;

    forward_unit u_fwd (
        .ex_rs1_addr   (ex_rs1_addr),
        .ex_rs2_addr   (ex_rs2_addr),
        .ex_use_rs1    (ex_use_rs1),
        .ex_use_rs2    (ex_use_rs2),
        .mem_reg_write (mem_reg_write),
        .mem_rd_addr   (mem_rd_addr),
        .wb_reg_write  (wb_reg_write),
        .wb_rd_addr    (wb_rd_addr),
        .forward_a_sel (fwd_a_sel),
        .forward_b_sel (fwd_b_sel)
    );

    wire [31:0] fwd_a = (fwd_a_sel == `FW_MEM) ? mem_alu_result :
                        (fwd_a_sel == `FW_WB ) ? wb_rd_data    :
                                                 ex_rs1_data;
    wire [31:0] fwd_b = (fwd_b_sel == `FW_MEM) ? mem_alu_result :
                        (fwd_b_sel == `FW_WB ) ? wb_rd_data    :
                                                 ex_rs2_data;

    assign store_data = fwd_b;

    //------------------------------------------------------------------
    // ALU operand mux: A is either pc or the forwarded rs1
    //------------------------------------------------------------------
    wire [31:0] alu_a_eff = ex_alu_src_a ? ex_pc : fwd_a;
    wire [31:0] alu_b_eff = ex_alu_src_b ? ex_imm : fwd_b;

    wire [31:0] alu_result_raw;

    alu u_alu (
        .op_a   (alu_a_eff),
        .op_b   (alu_b_eff),
        .alu_op (ex_alu_op),
        .result (alu_result_raw),
        .zero   (),
        .lt_s   (),
        .lt_u   ()
    );

    //------------------------------------------------------------------
    // Branch comparator (independent of ALU)
    //------------------------------------------------------------------
    wire cmp_zero = (fwd_a == fwd_b);
    wire cmp_lt_s = ($signed(fwd_a) < $signed(fwd_b));
    wire cmp_lt_u = (fwd_a < fwd_b);

    wire take;
    branch_unit u_bu (
        .funct3 (ex_branch_funct3),
        .zero   (cmp_zero),
        .lt_s   (cmp_lt_s),
        .lt_u   (cmp_lt_u),
        .take   (take)
    );

    assign branch_taken    = ex_branch && take;
    assign redirect        = branch_taken || ex_jump;
    assign redirect_target = alu_result_raw & 32'hFFFF_FFFE;

    //------------------------------------------------------------------
    // Muldiv issue FSM
    //------------------------------------------------------------------
    localparam EX_IDLE = 1'b0;
    localparam EX_WAIT = 1'b1;

    reg  ex_state;
    wire muldiv_busy_w;
    wire [31:0] muldiv_result_w;

    wire muldiv_start = (ex_state == EX_IDLE) && ex_muldiv_sel;

    // Stall while muldiv is in flight. Released the cycle busy falls.
    assign muldiv_stall = ex_muldiv_sel &&
                          !((ex_state == EX_WAIT) && !muldiv_busy_w);

    muldiv u_muldiv (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (muldiv_start),
        .op     (ex_muldiv_op),
        .op_a   (fwd_a),
        .op_b   (fwd_b),
        .result (muldiv_result_w),
        .busy   (muldiv_busy_w)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_state <= EX_IDLE;
        end else begin
            case (ex_state)
                EX_IDLE: if (ex_muldiv_sel) ex_state <= EX_WAIT;
                EX_WAIT: if (!muldiv_busy_w) ex_state <= EX_IDLE;
                default: ex_state <= EX_IDLE;
            endcase
        end
    end

    //------------------------------------------------------------------
    // Result mux
    //------------------------------------------------------------------
    assign alu_result = ex_muldiv_sel ? muldiv_result_w : alu_result_raw;

endmodule