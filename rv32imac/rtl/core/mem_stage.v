//=============================================================================
// Module:      mem_stage
// File:        rtl/core/mem_stage.v
// Description: MEM stage.
//              Loads:  2-cycle LS FSM (IDLE -> RSP). mem_stall holds the
//                      pipeline until the response arrives.
//              Stores: single-cycle. Request issued from IDLE, no state
//                      transition, no stall. Response is ignored.
//              AMO: delegated to amo_unit (own FSM, stalls via amo_busy).
// Reset:       Synchronous active-low rst_n. LS FSM = IDLE.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module mem_stage (
    input  wire        clk,
    input  wire        rst_n,

    // ---- From EX/MEM ----
    input  wire [31:0] mem_alu_result,
    input  wire [31:0] mem_store_data,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [1:0]  mem_size,
    input  wire        mem_unsigned,
    input  wire        mem_atomic_sel,
    input  wire [4:0]  mem_amo_op,
    input  wire        mem_is_lr,
    input  wire        mem_is_sc,

    // ---- Native data memory port ----
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

    // ---- To MEM/WB ----
    output wire [31:0] mem_rdata,
    output wire        mem_fault,
    output wire        mem_stall
);

    //------------------------------------------------------------------
    // Byte-lane logic
    //------------------------------------------------------------------
    wire [1:0]  byte_off     = mem_alu_result[1:0];
    wire [31:0] store_shifted = mem_store_data << {byte_off, 3'b000};

    wire [3:0]  wstrb = (mem_size == 2'b00) ? (4'b0001 << byte_off) :
                        (mem_size == 2'b01) ? (4'b0011 << byte_off) :
                                              4'b1111;

    wire [31:0] load_shifted = dmem_rsp_rdata >> {byte_off, 3'b000};

    wire [31:0] load_extended =
        (mem_size == 2'b00) ?
            (mem_unsigned ? {24'b0, load_shifted[7:0]}
                          : {{24{load_shifted[7]}},  load_shifted[7:0]}) :
        (mem_size == 2'b01) ?
            (mem_unsigned ? {16'b0, load_shifted[15:0]}
                          : {{16{load_shifted[15]}}, load_shifted[15:0]}) :
            load_shifted;

    //------------------------------------------------------------------
    // Misalignment detection
    //------------------------------------------------------------------
    wire misalign_ld = mem_read  &&
        ( ((mem_size == 2'b01) &&  byte_off[0]) ||
          ((mem_size == 2'b10) && (byte_off != 2'b00)) );
    wire misalign_st = mem_write &&
        ( ((mem_size == 2'b01) &&  byte_off[0]) ||
          ((mem_size == 2'b10) && (byte_off != 2'b00)) );
    wire misalign = misalign_ld || misalign_st;

    //------------------------------------------------------------------
    // Load/store FSM
    //   - Only loads transition into LS_RSP.
    //   - Stores complete in the issue cycle; no state change.
    //------------------------------------------------------------------
    localparam LS_IDLE = 1'b0;
    localparam LS_RSP  = 1'b1;

    reg ls_state;

    wire is_mem_op    = mem_read || mem_write;
    wire ls_req       = (ls_state == LS_IDLE) && is_mem_op && !mem_atomic_sel;
    wire ls_rsp_ready = (ls_state == LS_RSP);
    wire ls_finishing = (ls_state == LS_RSP) && dmem_rsp_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ls_state <= LS_IDLE;
        end else if (mem_atomic_sel) begin
            ls_state <= LS_IDLE;
        end else begin
            case (ls_state)
                LS_IDLE: if (ls_req && dmem_req_ready && mem_read)
                             ls_state <= LS_RSP;
                         // store: stays in LS_IDLE, no wait
                LS_RSP:  if (dmem_rsp_valid)
                             ls_state <= LS_IDLE;
                default: ls_state <= LS_IDLE;
            endcase
        end
    end

    //------------------------------------------------------------------
    // AMO
    //------------------------------------------------------------------
    wire        amo_req_valid;
    wire        amo_req_ready;
    wire [31:0] amo_req_addr;
    wire [31:0] amo_req_wdata;
    wire [3:0]  amo_req_wstrb;
    wire        amo_req_write;
    wire [1:0]  amo_req_size;
    wire        amo_req_atomic;
    wire        amo_rsp_valid;
    wire        amo_rsp_ready;
    wire [31:0] amo_rsp_rdata;
    wire        amo_rsp_error;
    wire [31:0] amo_result;
    wire        amo_busy;
    wire        amo_done;
    wire        amo_error;

    reg  amo_started_r;
    wire amo_start = mem_atomic_sel && !amo_started_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) amo_started_r <= 1'b0;
        else if (!mem_atomic_sel) amo_started_r <= 1'b0;
        else if (amo_start) amo_started_r <= 1'b1;
    end

    reg amo_error_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) amo_error_r <= 1'b0;
        else if (!mem_atomic_sel) amo_error_r <= 1'b0;
        else if (amo_error) amo_error_r <= 1'b1;
    end

    amo_unit u_amo (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (amo_start),
        .op             (mem_amo_op),
        .is_lr          (mem_is_lr),
        .is_sc          (mem_is_sc),
        .req_addr       (mem_alu_result),
        .req_wdata      (mem_store_data),
        .mem_req_valid  (amo_req_valid),
        .mem_req_ready  (amo_req_ready),
        .mem_req_addr   (amo_req_addr),
        .mem_req_wdata  (amo_req_wdata),
        .mem_req_wstrb  (amo_req_wstrb),
        .mem_req_write  (amo_req_write),
        .mem_req_size   (amo_req_size),
        .mem_req_atomic (amo_req_atomic),
        .mem_rsp_valid  (amo_rsp_valid),
        .mem_rsp_ready  (amo_rsp_ready),
        .mem_rsp_rdata  (amo_rsp_rdata),
        .mem_rsp_error  (amo_rsp_error),
        .result         (amo_result),
        .busy           (amo_busy),
        .done           (amo_done),
        .error          (amo_error)
    );

    //------------------------------------------------------------------
    // Port mux
    //------------------------------------------------------------------
    assign dmem_req_valid  = mem_atomic_sel ? amo_req_valid  : ls_req;
    assign dmem_req_addr   = mem_atomic_sel ? amo_req_addr   : mem_alu_result;
    assign dmem_req_wdata  = mem_atomic_sel ? amo_req_wdata  : store_shifted;
    assign dmem_req_wstrb  = mem_atomic_sel ? amo_req_wstrb  : wstrb;
    assign dmem_req_write  = mem_atomic_sel ? amo_req_write  : mem_write;
    assign dmem_req_size   = mem_atomic_sel ? amo_req_size   : mem_size;
    assign dmem_req_atomic = mem_atomic_sel;

    assign amo_req_ready   = dmem_req_ready;
    assign amo_rsp_valid   = dmem_rsp_valid;
    assign amo_rsp_rdata   = dmem_rsp_rdata;
    assign amo_rsp_error   = dmem_rsp_error;
    assign dmem_rsp_ready  = mem_atomic_sel ? amo_rsp_ready : ls_rsp_ready;

    //------------------------------------------------------------------
    // Outputs
    //------------------------------------------------------------------
    wire ls_fault  = misalign || (dmem_rsp_error && (ls_state == LS_RSP));
    wire amo_fault = amo_error || amo_error_r;

    assign mem_rdata = mem_atomic_sel ? amo_result : load_extended;
    assign mem_fault = mem_atomic_sel ? amo_fault  : ls_fault;

    // Only loads stall. Stores complete in the issue cycle.
    wire ls_stall = (mem_read && !mem_atomic_sel) && !ls_finishing;
    assign mem_stall = mem_atomic_sel ? amo_busy : ls_stall;

endmodule