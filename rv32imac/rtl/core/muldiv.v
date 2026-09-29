//=============================================================================
// Module:      muldiv
// File:        rtl/core/muldiv.v
// Description: RV32M multiply/divide unit.
//              - MUL/MULH/MULHSU/MULHU: combinational product, registered
//                on start (busy=1 for 1 cycle).
//              - DIV/DIVU/REM/REMU: 32-cycle restoring divider FSM.
//              Handshake: assert start for 1 cycle. busy stays high for N
//              cycles (N=1 for MUL, N=32 for DIV). result is valid on the
//              cycle busy falls and remains stable until the next start.
// Reset:       Synchronous active-low rst_n. busy=0, result=0.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module muldiv (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [3:0]  op,
    input  wire [31:0] op_a,
    input  wire [31:0] op_b,
    output reg  [31:0] result,
    output reg         busy
);

    //------------------------------------------------------------------
    // Operation classification
    //------------------------------------------------------------------
    wire is_mul = (op == `MD_MUL)  || (op == `MD_MULH) ||
                  (op == `MD_MULHSU) || (op == `MD_MULHU);
    wire is_div = (op == `MD_DIV)  || (op == `MD_DIVU) ||
                  (op == `MD_REM)  || (op == `MD_REMU);

    wire div_signed = (op == `MD_DIV) || (op == `MD_REM);
    wire want_rem   = (op == `MD_REM) || (op == `MD_REMU);

    //------------------------------------------------------------------
    // Combinational multiplier (explicit sign/zero extension)
    //------------------------------------------------------------------
    wire signed [63:0] a_sx = {{32{op_a[31]}}, op_a};
    wire signed [63:0] b_sx = {{32{op_b[31]}}, op_b};
    wire signed [63:0] b_ux = {32'b0, op_b};
    wire        [63:0] a_ux = {32'b0, op_a};

    wire signed [63:0] prod_ss = a_sx * b_sx;
    wire signed [63:0] prod_su = a_sx * b_ux;
    wire        [63:0] prod_uu = a_ux * b_ux;

    reg [63:0] mul_product;
    always @(*) begin
        case (op)
            `MD_MUL:    mul_product = prod_ss;
            `MD_MULH:   mul_product = prod_ss;
            `MD_MULHSU: mul_product = prod_su;
            `MD_MULHU:  mul_product = prod_uu;
            default:    mul_product = 64'b0;
        endcase
    end

    wire [31:0] mul_result = (op == `MD_MUL) ? mul_product[31:0]
                                             : mul_product[63:32];

    //------------------------------------------------------------------
    // Divider state
    //------------------------------------------------------------------
    reg        div_running;
    reg [5:0]  div_cnt;
    reg [31:0] div_dend;      // shifting dividend
    reg [31:0] div_quot;      // accumulated quotient
    reg [32:0] div_rem;       // shifting remainder
    reg [32:0] div_sr_b;      // zero-extended divisor
    reg        div_q_neg;     // negate quotient at end
    reg        div_r_neg;     // negate remainder at end
    reg        div_want_rem;  // output = remainder

    // Absolute values for signed division
    wire [31:0] a_neg = ~op_a + 32'd1;
    wire [31:0] b_neg = ~op_b + 32'd1;
    wire [31:0] div_a_abs = (div_signed && op_a[31]) ? a_neg : op_a;
    wire [31:0] div_b_abs = (div_signed && op_b[31]) ? b_neg : op_b;

    wire div_by_zero  = (op_b == 32'd0);
    wire div_overflow = div_signed &&
                        (op_a == 32'h8000_0000) &&
                        (op_b == 32'hFFFF_FFFF);

    wire [31:0] div_zero_result = want_rem ? op_a : 32'hFFFF_FFFF;
    wire [31:0] div_ovf_result  = want_rem ? 32'd0 : 32'h8000_0000;

    // One iteration of restoring division
    wire [32:0] iter_shifted_rem = {div_rem[31:0], div_dend[31]};
    wire        iter_sub         = (iter_shifted_rem >= div_sr_b);
    wire [32:0] iter_next_rem    = iter_sub ? (iter_shifted_rem - div_sr_b)
                                            : iter_shifted_rem;
    wire [31:0] iter_next_quot   = {div_quot[30:0], iter_sub};
    wire [31:0] iter_next_dend   = {div_dend[30:0], 1'b0};

    // Final signed adjustments
    wire [31:0] div_q_out = div_q_neg ? (~iter_next_quot + 32'd1) : iter_next_quot;
    wire [31:0] div_r_out = div_r_neg ? (~iter_next_rem[31:0] + 32'd1)
                                      :  iter_next_rem[31:0];
    wire [31:0] div_final = div_want_rem ? div_r_out : div_q_out;

    //------------------------------------------------------------------
    // Sequential FSM
    //------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result       <= 32'b0;
            busy         <= 1'b0;
            div_running  <= 1'b0;
            div_cnt      <= 6'd0;
            div_dend     <= 32'b0;
            div_quot     <= 32'b0;
            div_rem      <= 33'b0;
            div_sr_b     <= 33'b0;
            div_q_neg    <= 1'b0;
            div_r_neg    <= 1'b0;
            div_want_rem <= 1'b0;
        end else if (div_running) begin
            if (div_cnt >= 6'd32) begin
                // Sentinel: MUL or div special case. Drop busy.
                busy        <= 1'b0;
                div_running <= 1'b0;
            end else if (div_cnt == 6'd31) begin
                // Final iteration: register result, drop busy.
                result      <= div_final;
                busy        <= 1'b0;
                div_running <= 1'b0;
            end else begin
                // Normal iteration.
                div_dend <= iter_next_dend;
                div_quot <= iter_next_quot;
                div_rem  <= iter_next_rem;
                div_cnt  <= div_cnt + 6'd1;
                busy     <= 1'b1;
            end
        end else if (start) begin
            if (is_mul) begin
                result      <= mul_result;
                busy        <= 1'b1;
                div_running <= 1'b1;
                div_cnt     <= 6'd63;   // single-cycle sentinel
            end else if (is_div) begin
                if (div_by_zero) begin
                    result      <= div_zero_result;
                    busy        <= 1'b1;
                    div_running <= 1'b1;
                    div_cnt     <= 6'd63;
                end else if (div_overflow) begin
                    result      <= div_ovf_result;
                    busy        <= 1'b1;
                    div_running <= 1'b1;
                    div_cnt     <= 6'd63;
                end else begin
                    div_dend     <= div_a_abs;
                    div_quot     <= 32'b0;
                    div_rem      <= 33'b0;
                    div_sr_b     <= {1'b0, div_b_abs};
                    div_q_neg    <= (op_a[31] ^ op_b[31]) & div_signed;
                    div_r_neg    <= op_a[31] & div_signed;
                    div_want_rem <= want_rem;
                    div_cnt      <= 6'd0;
                    busy         <= 1'b1;
                    div_running  <= 1'b1;
                end
            end
        end else begin
            busy <= 1'b0;
        end
    end

endmodule