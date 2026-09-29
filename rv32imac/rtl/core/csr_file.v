//=============================================================================
// Module:      csr_file
// File:        rtl/core/csr_file.v
// Description: M/S-mode CSR bank, privilege state, trap entry/return.
//              Owns:
//                - All M- and S-level CSRs (U CSRs reserved -> illegal)
//                - Privilege state machine (M/S/U)
//                - Trap entry with delegation (medeleg / mideleg)
//                - MRET / SRET return sequencing
//                - 64-bit mcycle / minstret
//                - Interrupt enable (mie) and pending (mip)
//                - satp storage for the future Sv32 MMU
//              Reads are combinational. Writes commit on posedge.
// Reset:       Synchronous active-low rst_n. priv = M, all CSRs = 0.
//=============================================================================
`timescale 1ns / 1ps

`include "riscv_defs.vh"

module csr_file #(
    parameter [31:0] HARTID = 32'h0
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- CSR access from WB stage ----
    input  wire        csr_we,
    input  wire [11:0] csr_addr,
    input  wire [1:0]  csr_op,      // CSR_OP_RW / RS / RC
    input  wire [31:0] csr_wdata,   // rs1 data or zero-extended zimm
    output reg  [31:0] csr_rdata,
    output reg         csr_illegal,

    // ---- Privilege ----
    output reg  [1:0]  current_priv,

    // ---- Trap entry ----
    input  wire        trap_enter,
    input  wire [3:0]  trap_cause,
    input  wire [31:0] trap_epc,        // PC of faulting instruction
    input  wire [31:0] trap_tval,
    input  wire        trap_is_interrupt,
    output wire [31:0] trap_target,     // new PC after trap

    // ---- Trap return ----
    input  wire        mret,
    input  wire        sret,
    output wire [31:0] xret_pc,         // PC to restore on MRET/SRET

    // ---- Interrupt lines ----
    input  wire        timer_irq,       // -> mip.MTIP
    input  wire        ext_irq,         // -> mip.MEIP
    output wire [31:0] mie_out,
    output wire [31:0] mip_out,

    // ---- Retire for counters ----
    input  wire        retire,

    // ---- Readouts ----
    output wire [31:0] satp_out
);

    //------------------------------------------------------------------
    // mstatus bit positions (RV32)
    //------------------------------------------------------------------
    localparam MSTATUS_SIE     = 1;
    localparam MSTATUS_MIE     = 3;
    localparam MSTATUS_SPIE    = 5;
    localparam MSTATUS_MPIE    = 7;
    localparam MSTATUS_SPP     = 8;
    localparam MSTATUS_MPP_LO  = 11;
    localparam MSTATUS_MPRV    = 17;
    localparam MSTATUS_SUM     = 18;
    localparam MSTATUS_MXR     = 19;

    //------------------------------------------------------------------
    // Constant CSR values
    //------------------------------------------------------------------
    localparam [31:0] MISA_VALUE = 32'h4000_1105; // RV32IMAC

    //------------------------------------------------------------------
    // S-visible masks
    //------------------------------------------------------------------
    // sstatus exposes: SIE(1), SPIE(5), SPP(8), SUM(18), MXR(19)
    localparam [31:0] SSTATUS_MASK = 32'h000C_0122;

    // sie/sip expose: SSIE(1), STIE(5), SEIE(9)
    localparam [31:0] SIE_MASK     = 32'h0000_0222;

    // mstatus writable bits: SIE,MIE,SPIE,MPIE,SPP,MPP,MPRV,SUM,MXR
    localparam [31:0] MSTATUS_WMASK = 32'h000E_19AA;

    //------------------------------------------------------------------
    // State
    //------------------------------------------------------------------
    reg [31:0] mstatus;
    reg [31:0] mtvec, mepc, mcause, mtval, mscratch;
    reg [31:0] mie;
    reg [31:0] mip_sw;      // SW-writable bits: SSIP(1), MSIP(3), STIP(5),
                            // SEIP(9), and any others we choose to expose
    reg [31:0] medeleg, mideleg;
    reg [31:0] stvec, sepc, scause, stval, sscratch;
    reg [31:0] satp;
    reg [63:0] mcycle, minstret;

    //------------------------------------------------------------------
    // mip composition: SW bits | HW-driven bits
    //------------------------------------------------------------------
    wire [31:0] mip = mip_sw
                    | (timer_irq ? 32'h0000_0080 : 32'h0)   // MTIP(7)
                    | (ext_irq   ? 32'h0000_0800 : 32'h0);  // MEIP(11)

    assign mie_out  = mie;
    assign mip_out  = mip;
    assign satp_out = satp;

    //------------------------------------------------------------------
    // CSR access legality
    //------------------------------------------------------------------
    wire [1:0] csr_min_priv = csr_addr[9:8];
    wire       csr_readonly = (csr_addr[11:10] == 2'b11);
    wire       priv_ok = (csr_min_priv == 2'b00) ||
                         ((csr_min_priv == 2'b01) && (current_priv != `PRV_U)) ||
                         ((csr_min_priv == 2'b11) && (current_priv == `PRV_M));

    //------------------------------------------------------------------
    // Read mux (combinational)
    //------------------------------------------------------------------
    always @(*) begin
        csr_rdata   = 32'b0;
        csr_illegal = 1'b0;

        case (csr_addr)
            // ---------------- S-level ----------------
            `CSR_SSTATUS:  csr_rdata = mstatus & SSTATUS_MASK;
            `CSR_SIE:      csr_rdata = mie     & SIE_MASK;
            `CSR_STVEC:    csr_rdata = stvec;
            `CSR_SSCRATCH: csr_rdata = sscratch;
            `CSR_SEPC:     csr_rdata = sepc;
            `CSR_SCAUSE:   csr_rdata = scause;
            `CSR_STVAL:    csr_rdata = stval;
            `CSR_SIP:      csr_rdata = mip     & SIE_MASK;
            `CSR_SATP:     csr_rdata = satp;

            // ---------------- M-level ----------------
            `CSR_MSTATUS:  csr_rdata = mstatus;
            `CSR_MISA:     csr_rdata = MISA_VALUE;
            `CSR_MEDELEG:  csr_rdata = medeleg;
            `CSR_MIDELEG:  csr_rdata = mideleg;
            `CSR_MIE:      csr_rdata = mie;
            `CSR_MTVEC:    csr_rdata = mtvec;
            `CSR_MSCRATCH: csr_rdata = mscratch;
            `CSR_MEPC:     csr_rdata = mepc;
            `CSR_MCAUSE:   csr_rdata = mcause;
            `CSR_MTVAL:    csr_rdata = mtval;
            `CSR_MIP:      csr_rdata = mip;

            `CSR_MCYCLE:   csr_rdata = mcycle[31:0];
            `CSR_MINSTRET: csr_rdata = minstret[31:0];
            `CSR_MCYCLEH:  csr_rdata = mcycle[63:32];
            `CSR_MINSTRETH:csr_rdata = minstret[63:32];

            `CSR_CYCLE:    csr_rdata = mcycle[31:0];
            `CSR_INSTRET:  csr_rdata = minstret[31:0];
            `CSR_CYCLEH:   csr_rdata = mcycle[63:32];
            `CSR_INSTRETH: csr_rdata = minstret[63:32];

            `CSR_MVENDORID:csr_rdata = 32'h0;
            `CSR_MARCHID:  csr_rdata = 32'h1;
            `CSR_MIMPID:   csr_rdata = 32'h1;
            `CSR_MHARTID:  csr_rdata = HARTID;

            default: csr_illegal = 1'b1;
        endcase

        if (!priv_ok) begin
            csr_rdata   = 32'b0;
            csr_illegal = 1'b1;
        end
    end

    //------------------------------------------------------------------
    // Compute value to write
    //------------------------------------------------------------------
    reg [31:0] csr_newval;
    always @(*) begin
        case (csr_op)
            `CSR_OP_RW: csr_newval = csr_wdata;
            `CSR_OP_RS: csr_newval = csr_rdata |  csr_wdata;
            `CSR_OP_RC: csr_newval = csr_rdata & ~csr_wdata;
            default:    csr_newval = csr_wdata;
        endcase
    end

    // RS/RC with zero source = no write (per spec)
    wire csr_will_write = csr_we && !csr_illegal && !csr_readonly &&
                          ((csr_op == `CSR_OP_RW) || (csr_wdata != 32'b0));

    //------------------------------------------------------------------
    // Trap target computation
    //------------------------------------------------------------------
    wire [31:0] mtvec_base = {mtvec[31:2], 2'b00};
    wire [31:0] stvec_base = {stvec[31:2], 2'b00};

    wire [31:0] mtvec_target = (mtvec[1:0] == 2'b01 && trap_is_interrupt)
                               ? mtvec_base + {26'b0, trap_cause, 2'b00}
                               : mtvec_base;
    wire [31:0] stvec_target = (stvec[1:0] == 2'b01 && trap_is_interrupt)
                               ? stvec_base + {26'b0, trap_cause, 2'b00}
                               : stvec_base;

    // Delegation decision
    wire [31:0] deleg_bit_field = trap_is_interrupt ? mideleg : medeleg;
    wire        deleg_bit = deleg_bit_field[trap_cause];
    wire        deleg = (current_priv != `PRV_M) && deleg_bit &&
                        !(trap_is_interrupt == 1'b0 && trap_cause == `CAUSE_ECALL_M);

    assign trap_target = deleg ? stvec_target : mtvec_target;

    // xret PC
    assign xret_pc = mret ? mepc : sepc;

    //------------------------------------------------------------------
    // Sequential state
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            mstatus      <= 32'h0;
            mtvec        <= 32'h0;
            mepc         <= 32'h0;
            mcause       <= 32'h0;
            mtval        <= 32'h0;
            mscratch     <= 32'h0;
            mie          <= 32'h0;
            mip_sw       <= 32'h0;
            medeleg      <= 32'h0;
            mideleg      <= 32'h0;
            stvec        <= 32'h0;
            sepc         <= 32'h0;
            scause       <= 32'h0;
            stval        <= 32'h0;
            sscratch     <= 32'h0;
            satp         <= 32'h0;
            mcycle       <= 64'h0;
            minstret     <= 64'h0;
            current_priv <= `PRV_M;
        end else begin
            // Counters
            mcycle <= mcycle + 64'h1;
            if (retire) minstret <= minstret + 64'h1;

            if (trap_enter) begin
                if (deleg) begin
                    sepc   <= trap_epc;
                    scause <= trap_is_interrupt ? (32'h8000_0000 | {28'b0, trap_cause})
                                                : {28'b0, trap_cause};
                    stval  <= trap_tval;
                    mstatus[MSTATUS_SPIE] <= mstatus[MSTATUS_SIE];
                    mstatus[MSTATUS_SIE]  <= 1'b0;
                    mstatus[MSTATUS_SPP]  <= (current_priv == `PRV_S);
                    current_priv <= `PRV_S;
                end else begin
                    mepc   <= trap_epc;
                    mcause <= trap_is_interrupt ? (32'h8000_0000 | {28'b0, trap_cause})
                                                : {28'b0, trap_cause};
                    mtval  <= trap_tval;
                    mstatus[MSTATUS_MPIE] <= mstatus[MSTATUS_MIE];
                    mstatus[MSTATUS_MIE]  <= 1'b0;
                    mstatus[MSTATUS_MPP_LO +: 2] <= current_priv;
                    current_priv <= `PRV_M;
                end
            end else if (mret) begin
                mstatus[MSTATUS_MIE]  <= mstatus[MSTATUS_MPIE];
                mstatus[MSTATUS_MPIE] <= 1'b1;
                current_priv <= mstatus[MSTATUS_MPP_LO +: 2];
                mstatus[MSTATUS_MPP_LO +: 2] <= `PRV_U;
            end else if (sret) begin
                mstatus[MSTATUS_SIE]  <= mstatus[MSTATUS_SPIE];
                mstatus[MSTATUS_SPIE] <= 1'b1;
                current_priv <= mstatus[MSTATUS_SPP] ? `PRV_S : `PRV_U;
                mstatus[MSTATUS_SPP]  <= 1'b0;
            end else if (csr_will_write) begin
                case (csr_addr)
                    // ------------- S-level -------------
                    `CSR_SSTATUS:  mstatus  <= (mstatus & ~SSTATUS_MASK) |
                                              (csr_newval & SSTATUS_MASK);
                    `CSR_SIE:      mie      <= (mie & ~SIE_MASK) | (csr_newval & SIE_MASK);
                    `CSR_STVEC:    stvec    <= csr_newval;
                    `CSR_SSCRATCH: sscratch <= csr_newval;
                    `CSR_SEPC:     sepc     <= csr_newval;
                    `CSR_SCAUSE:   scause   <= csr_newval;
                    `CSR_STVAL:    stval    <= csr_newval;
                    `CSR_SIP:      mip_sw   <= (mip_sw & ~SIE_MASK) |
                                              (csr_newval & SIE_MASK);
                    `CSR_SATP:     satp     <= csr_newval;

                    // ------------- M-level -------------
                    `CSR_MSTATUS:  mstatus  <= (mstatus & ~MSTATUS_WMASK) |
                                              (csr_newval & MSTATUS_WMASK);
                    `CSR_MEDELEG:  medeleg  <= csr_newval;
                    `CSR_MIDELEG:  mideleg  <= csr_newval;
                    `CSR_MIE:      mie      <= csr_newval;
                    `CSR_MTVEC:    mtvec    <= csr_newval;
                    `CSR_MSCRATCH: mscratch <= csr_newval;
                    `CSR_MEPC:     mepc     <= csr_newval;
                    `CSR_MCAUSE:   mcause   <= csr_newval;
                    `CSR_MTVAL:    mtval    <= csr_newval;
                    `CSR_MIP:      mip_sw   <= csr_newval & 32'h0000_0AAA;

                    `CSR_MCYCLE:   mcycle[31:0]    <= csr_newval;
                    `CSR_MINSTRET: minstret[31:0]  <= csr_newval;
                    `CSR_MCYCLEH:  mcycle[63:32]   <= csr_newval;
                    `CSR_MINSTRETH:minstret[63:32] <= csr_newval;

                    default: ; // read-only or unimplemented
                endcase
            end
        end
    end

endmodule