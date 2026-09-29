//=============================================================================
// Module:      if_stage
// File:        rtl/core/if_stage.v
// Description: IF stage. Owns the PC register, an aligned 32-bit fetch buffer,
//              the I-mem native req/rsp handshake, and pre-expansion of RVC
//              to 32-bit instructions.
//              Outputs the RVC-expanded 32-bit instruction to IF/ID along with
//              PC, PC+len (2 or 4), and a fetch-fault flag. When no instruction
//              is ready, emits NOP (0x0000_0013) so the pipeline naturally
//              propagates a bubble.
//              On redirect: PC jumps immediately, buffer invalidated implicitly
//              by the address mismatch on the next cycle.
//              On stall: PC holds, current instruction is not re-emitted.
// Reset:       Synchronous active-low rst_n. PC = RESET_PC. Buffer invalid.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module if_stage (
    input  wire        clk,
    input  wire        rst_n,

    // Pipeline controls
    input  wire        stall,
    input  wire        redirect,
    input  wire [31:0] redirect_target,

    // Native I-mem port
    output reg         mem_req_valid,
    input  wire        mem_req_ready,
    output reg  [31:0] mem_req_addr,
    input  wire        mem_rsp_valid,
    output reg         mem_rsp_ready,
    input  wire [31:0] mem_rsp_rdata,
    input  wire        mem_rsp_error,

    // To IF/ID
    output wire [31:0] if_pc,
    output wire [31:0] if_pc_next,
    output wire [31:0] if_inst,
    output wire        if_fetch_fault,
    output wire        if_valid
);

    localparam S_IDLE = 2'd0;
    localparam S_REQ  = 2'd1;
    localparam S_RSP  = 2'd2;

    reg [1:0]  state;
    reg [31:0] pc_r;
    reg [31:0] fbuf_data;
    reg [31:0] fbuf_addr;
    reg        fbuf_valid;
    reg        fbuf_error;
    reg [31:0] fetch_addr_r;

    wire [31:0] aligned_pc = {pc_r[31:2], 2'b00};
    wire        fbuf_hit   = fbuf_valid && (fbuf_addr == aligned_pc);

    //------------------------------------------------------------------
    // Half/full word selection based on pc_r[1]
    //------------------------------------------------------------------
    reg  [31:0] inst_raw;
    reg  [31:0] pc_plus_next;
    reg         align_fault;

    always @(*) begin
        inst_raw     = 32'h0000_0013;
        pc_plus_next = pc_r + 32'd2;
        align_fault  = 1'b0;

        if (pc_r[1] == 1'b0) begin
            if (fbuf_data[1:0] == 2'b11) begin
                // 32-bit instruction at half-word-aligned pc
                inst_raw     = fbuf_data;
                pc_plus_next = pc_r + 32'd4;
            end else begin
                // 16-bit compressed at lower half
                inst_raw     = {16'b0, fbuf_data[15:0]};
                pc_plus_next = pc_r + 32'd2;
            end
        end else begin
            // pc_r[1] == 1: upper half of a word, must be compressed
            if (fbuf_data[17:16] == 2'b11)
                align_fault = 1'b1;
            inst_raw     = {16'b0, fbuf_data[31:16]};
            pc_plus_next = pc_r + 32'd2;
        end
    end

    //------------------------------------------------------------------
    // RVC expansion
    //------------------------------------------------------------------
    wire [31:0] inst_expanded;
    wire        inst_is_compressed;
    wire        rvc_illegal;

    rvc_expand u_rvc (
        .inst_in       (inst_raw),
        .inst_out      (inst_expanded),
        .is_compressed (inst_is_compressed),
        .illegal       (rvc_illegal)
    );

    //------------------------------------------------------------------
    // Outputs
    //------------------------------------------------------------------
    wire emit = (state == S_IDLE) && fbuf_hit;

    assign if_pc      = pc_r;
    assign if_pc_next = pc_plus_next;
    assign if_inst    = emit ? ((align_fault || rvc_illegal || fbuf_error)
                                ? 32'h0000_0000
                                : inst_expanded)
                             : 32'h0000_0013;
    assign if_fetch_fault = emit ? (align_fault || fbuf_error) : 1'b0;
    assign if_valid   = emit && !stall && !redirect;

    //------------------------------------------------------------------
    // Sequential
    //------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            pc_r          <= `RESET_PC;
            fbuf_data     <= 32'b0;
            fbuf_addr     <= 32'b0;
            fbuf_valid    <= 1'b0;
            fbuf_error    <= 1'b0;
            fetch_addr_r  <= 32'b0;
            mem_req_valid <= 1'b0;
            mem_req_addr  <= 32'b0;
            mem_rsp_ready <= 1'b0;
        end else begin
            case (state)
                //------------------------------------------------------
                S_IDLE: begin
                    if (redirect) begin
                        pc_r <= redirect_target;
                    end else if (fbuf_hit) begin
                        if (!stall) begin
                            pc_r <= pc_plus_next;
                            if ({pc_plus_next[31:2], 2'b00} != fbuf_addr)
                                fbuf_valid <= 1'b0;
                        end
                    end else if (!stall) begin
                        mem_req_valid <= 1'b1;
                        mem_req_addr  <= aligned_pc;
                        fetch_addr_r  <= aligned_pc;
                        state         <= S_REQ;
                    end
                end

                //------------------------------------------------------
                S_REQ: begin
                    if (redirect)
                        pc_r <= redirect_target;
                    if (mem_req_ready) begin
                        mem_req_valid <= 1'b0;
                        mem_rsp_ready <= 1'b1;
                        state         <= S_RSP;
                    end
                end

                //------------------------------------------------------
                S_RSP: begin
                    if (redirect)
                        pc_r <= redirect_target;
                    if (mem_rsp_valid) begin
                        mem_rsp_ready <= 1'b0;
                        fbuf_data     <= mem_rsp_rdata;
                        fbuf_addr     <= fetch_addr_r;
                        fbuf_valid    <= 1'b1;
                        fbuf_error    <= mem_rsp_error;
                        state         <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule