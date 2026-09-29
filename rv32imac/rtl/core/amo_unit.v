//=============================================================================
// Module:      amo_unit
// File:        rtl/core/amo_unit.v
// Description: RV32A atomic memory operations unit.
//              - LR.W: read, set reservation, return loaded value
//              - SC.W: if reservation hits, write; return 0 on success, 1 on fail
//              - AMO*.W: read-modify-write, return old value
//              Reservation register is internal. Cleared on ANY SC (success
//              or failure), and on any AMO/SC to the reserved address.
//              Memory interface: native req/rsp handshake (A4).
// Reset:       Synchronous active-low rst_n. Reservation cleared.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module amo_unit (
    input  wire        clk,
    input  wire        rst_n,

    // Request (from MEM stage)
    input  wire        start,
    input  wire [4:0]  op,          // funct5 (A_AMOADD .. A_AMOMAXU, FUNCT5_LR, FUNCT5_SC)
    input  wire        is_lr,
    input  wire        is_sc,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,

    // Native memory port
    output reg         mem_req_valid,
    input  wire        mem_req_ready,
    output wire [31:0] mem_req_addr,
    output reg  [31:0] mem_req_wdata,
    output wire [3:0]  mem_req_wstrb,
    output reg         mem_req_write,
    output wire [1:0]  mem_req_size,
    output reg         mem_req_atomic,
    input  wire        mem_rsp_valid,
    output reg         mem_rsp_ready,
    input  wire [31:0] mem_rsp_rdata,
    input  wire        mem_rsp_error,

    // Result
    output reg  [31:0] result,
    output reg         busy,
    output reg         done,
    output reg         error
);

    //------------------------------------------------------------------
    // FSM states
    //------------------------------------------------------------------
    localparam S_IDLE      = 3'd0;
    localparam S_READ_REQ  = 3'd1;
    localparam S_READ_RSP  = 3'd2;
    localparam S_WRITE_REQ = 3'd3;
    localparam S_WRITE_RSP = 3'd4;
    localparam S_DONE      = 3'd5;

    reg [2:0] state;

    //------------------------------------------------------------------
    // Registered request
    //------------------------------------------------------------------
    reg [4:0]  op_r;
    reg        is_lr_r, is_sc_r;
    reg [31:0] addr_r, wdata_r;
    reg [31:0] old_val;

    //------------------------------------------------------------------
    // Reservation register
    //------------------------------------------------------------------
    reg        res_valid;
    reg [31:0] res_addr;

    wire res_hit = res_valid && (res_addr == addr_r);

    //------------------------------------------------------------------
    // Constant memory port tie-offs
    //------------------------------------------------------------------
    assign mem_req_addr  = addr_r;
    assign mem_req_wstrb = 4'b1111;
    assign mem_req_size  = 2'b10;   // word

    //------------------------------------------------------------------
    // AMO compute
    //------------------------------------------------------------------
    function [31:0] amo_compute;
        input [4:0]  op;
        input [31:0] a;
        input [31:0] b;
        begin
            case (op)
                `A_AMOSWAP: amo_compute = b;
                `A_AMOADD:  amo_compute = a + b;
                `A_AMOXOR:  amo_compute = a ^ b;
                `A_AMOAND:  amo_compute = a & b;
                `A_AMOOR:   amo_compute = a | b;
                `A_AMOMIN:  amo_compute = ($signed(a) < $signed(b)) ? a : b;
                `A_AMOMAX:  amo_compute = ($signed(a) > $signed(b)) ? a : b;
                `A_AMOMINU: amo_compute = (a < b) ? a : b;
                `A_AMOMAXU: amo_compute = (a > b) ? a : b;
                default:    amo_compute = b;
            endcase
        end
    endfunction

    //------------------------------------------------------------------
    // Sequential FSM
    //------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            op_r           <= 5'b0;
            is_lr_r        <= 1'b0;
            is_sc_r        <= 1'b0;
            addr_r         <= 32'b0;
            wdata_r        <= 32'b0;
            old_val        <= 32'b0;
            res_valid      <= 1'b0;
            res_addr       <= 32'b0;
            mem_req_valid  <= 1'b0;
            mem_req_write  <= 1'b0;
            mem_req_wdata  <= 32'b0;
            mem_rsp_ready  <= 1'b0;
            mem_req_atomic <= 1'b1;
            result         <= 32'b0;
            busy           <= 1'b0;
            done           <= 1'b0;
            error          <= 1'b0;
        end else begin
            // One-cycle pulses
            done  <= 1'b0;
            error <= 1'b0;

            case (state)
                //----------------------------------------------------
                S_IDLE: begin
                    busy          <= 1'b0;
                    mem_req_valid <= 1'b0;
                    mem_rsp_ready <= 1'b0;
                    mem_req_write <= 1'b0;

                    if (start) begin
                        op_r    <= op;
                        is_lr_r <= is_lr;
                        is_sc_r <= is_sc;
                        addr_r  <= req_addr;
                        wdata_r <= req_wdata;
                        busy    <= 1'b1;

                        if (is_sc) begin
                            if (res_valid && (res_addr == req_addr)) begin
                                // SC with valid reservation: issue write.
                                state         <= S_WRITE_REQ;
                                mem_req_valid <= 1'b1;
                                mem_req_write <= 1'b1;
                                mem_req_wdata <= req_wdata;
                            end else begin
                                // SC failure: no memory traffic, clear
                                // reservation (spec mandates this).
                                result    <= 32'd1;
                                res_valid <= 1'b0;
                                state     <= S_DONE;
                            end
                        end else begin
                            // LR or AMO: issue read.
                            state         <= S_READ_REQ;
                            mem_req_valid <= 1'b1;
                            mem_req_write <= 1'b0;
                        end
                    end
                end

                //----------------------------------------------------
                S_READ_REQ: begin
                    mem_req_valid <= 1'b1;
                    mem_req_write <= 1'b0;
                    if (mem_req_valid && mem_req_ready) begin
                        mem_req_valid <= 1'b0;
                        mem_rsp_ready <= 1'b1;
                        state         <= S_READ_RSP;
                    end
                end

                //----------------------------------------------------
                S_READ_RSP: begin
                    mem_rsp_ready <= 1'b1;
                    if (mem_rsp_valid) begin
                        mem_rsp_ready <= 1'b0;
                        if (mem_rsp_error) begin
                            error <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            old_val <= mem_rsp_rdata;
                            if (is_lr_r) begin
                                result    <= mem_rsp_rdata;
                                res_valid <= 1'b1;
                                res_addr  <= addr_r;
                                state     <= S_DONE;
                            end else begin
                                // AMO: read-modify-write
                                mem_req_valid <= 1'b1;
                                mem_req_write <= 1'b1;
                                mem_req_wdata <= amo_compute(op_r,
                                                             mem_rsp_rdata,
                                                             wdata_r);
                                state <= S_WRITE_REQ;
                            end
                        end
                    end
                end

                //----------------------------------------------------
                S_WRITE_REQ: begin
                    mem_req_valid <= 1'b1;
                    mem_req_write <= 1'b1;
                    if (mem_req_valid && mem_req_ready) begin
                        mem_req_valid <= 1'b0;
                        mem_rsp_ready <= 1'b1;
                        state         <= S_WRITE_RSP;
                    end
                end

                //----------------------------------------------------
                S_WRITE_RSP: begin
                    mem_rsp_ready <= 1'b1;
                    if (mem_rsp_valid) begin
                        mem_rsp_ready <= 1'b0;

                        if (mem_rsp_error) begin
                            error <= 1'b1;
                            if (is_sc_r) result <= 32'd1;
                        end else if (is_sc_r) begin
                            result <= 32'd0;
                        end else begin
                            result <= old_val;
                        end

                        // Reservation clears on any SC, or on AMO/SC hitting
                        // the reserved address.
                        if (is_sc_r || res_hit)
                            res_valid <= 1'b0;

                        state <= S_DONE;
                    end
                end

                //----------------------------------------------------
                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                //----------------------------------------------------
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule