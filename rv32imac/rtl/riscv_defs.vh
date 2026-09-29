//=============================================================================
// File:    rtl/riscv_defs.vh
// Purpose: Global RISC-V constants shared across all modules.
//          Frozen after first use. Changes here invalidate every TB.
//=============================================================================
`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH

//------------------------------------------------------------------
// XLEN
//------------------------------------------------------------------
`define XLEN 32

//------------------------------------------------------------------
// ALU op encodings (frozen; mirrored from alu.v F01)
//------------------------------------------------------------------
`define ALU_ADD     5'd0
`define ALU_SUB     5'd1
`define ALU_SLL     5'd2
`define ALU_SLT     5'd3
`define ALU_SLTU    5'd4
`define ALU_XOR     5'd5
`define ALU_SRL     5'd6
`define ALU_SRA     5'd7
`define ALU_OR      5'd8
`define ALU_AND     5'd9
`define ALU_PASS_A  5'd10
`define ALU_PASS_B  5'd11

//------------------------------------------------------------------
// RV32I major opcodes (inst[6:0])
//------------------------------------------------------------------
`define OP_LUI      7'b0110111
`define OP_AUIPC    7'b0010111
`define OP_JAL      7'b1101111
`define OP_JALR     7'b1100111
`define OP_BRANCH   7'b1100011
`define OP_LOAD     7'b0000011
`define OP_STORE    7'b0100011
`define OP_OP_IMM   7'b0010011
`define OP_OP       7'b0110011
`define OP_MISC_MEM 7'b0001111
`define OP_SYSTEM   7'b1110011

// RV32M uses OP_OP with funct7=0000001
`define FUNCT7_M    7'b0000001

// RV32A uses OP_ATOMIC
`define OP_ATOMIC   7'b0101111
`define FUNCT5_LR   5'b00010
`define FUNCT5_SC   5'b00011

//------------------------------------------------------------------
// Branch funct3
//------------------------------------------------------------------
`define F3_BEQ  3'b000
`define F3_BNE  3'b001
`define F3_BLT  3'b100
`define F3_BGE  3'b101
`define F3_BLTU 3'b110
`define F3_BGEU 3'b111
`define F3_JALR 3'b000

//------------------------------------------------------------------
// Load funct3
//------------------------------------------------------------------
`define F3_LB   3'b000
`define F3_LH   3'b001
`define F3_LW   3'b010
`define F3_LBU  3'b100
`define F3_LHU  3'b101

//------------------------------------------------------------------
// Store funct3
//------------------------------------------------------------------
`define F3_SB   3'b000
`define F3_SH   3'b001
`define F3_SW   3'b010

//------------------------------------------------------------------
// OP-IMM funct3
//------------------------------------------------------------------
`define F3_ADDI  3'b000
`define F3_SLTI  3'b010
`define F3_SLTIU 3'b011
`define F3_XORI  3'b100
`define F3_ORI   3'b110
`define F3_ANDI  3'b111
`define F3_SLLI  3'b001
`define F3_SRI   3'b101   // SRLI / SRAI distinguished by funct7[5]

//------------------------------------------------------------------
// OP funct3 (register-register)
//------------------------------------------------------------------
`define F3_ADD_SUB  3'b000
`define F3_SLL      3'b001
`define F3_SLT      3'b010
`define F3_SLTU     3'b011
`define F3_XOR      3'b100
`define F3_SR       3'b101
`define F3_OR       3'b110
`define F3_AND      3'b111

//------------------------------------------------------------------
// RV32M funct3
//------------------------------------------------------------------
`define F3_MUL      3'b000
`define F3_MULH     3'b001
`define F3_MULHSU   3'b010
`define F3_MULHU    3'b011
`define F3_DIV      3'b100
`define F3_DIVU     3'b101
`define F3_REM      3'b110
`define F3_REMU     3'b111

//------------------------------------------------------------------
// RV32A funct5 (inst[31:27])
//------------------------------------------------------------------
`define A_AMOSWAP   5'b00001
`define A_AMOADD    5'b00000
`define A_AMOXOR    5'b00100
`define A_AMOAND    5'b01100
`define A_AMOOR     5'b01000
`define A_AMOMIN    5'b10000
`define A_AMOMAX    5'b10100
`define A_AMOMINU   5'b11000
`define A_AMOMAXU   5'b11100

//------------------------------------------------------------------
// SYSTEM funct3 / funct12
//------------------------------------------------------------------
`define F3_PRIV     3'b000
`define F3_CSRRW    3'b001
`define F3_CSRRS    3'b010
`define F3_CSRRC    3'b011
`define F3_CSRRWI   3'b101
`define F3_CSRRSI   3'b110
`define F3_CSRRCI   3'b111

`define FUNCT12_ECALL   12'h000
`define FUNCT12_EBREAK  12'h001
`define FUNCT12_MRET    12'h302
`define FUNCT12_SRET    12'h102
`define FUNCT12_WFI     12'h105
`define FUNCT12_SFENCE  12'h120

//------------------------------------------------------------------
// CSR addresses (Privileged Spec v1.11)
//------------------------------------------------------------------
`define CSR_USTATUS   12'h000
`define CSR_UIE       12'h004
`define CSR_UTVEC     12'h005
`define CSR_USCRATCH  12'h040
`define CSR_UEPC      12'h041
`define CSR_UCAUSE    12'h042
`define CSR_UTVAL     12'h043
`define CSR_UIP       12'h044

`define CSR_SSTATUS   12'h100
`define CSR_SIE       12'h104
`define CSR_STVEC     12'h105
`define CSR_SSCRATCH  12'h140
`define CSR_SEPC      12'h141
`define CSR_SCAUSE    12'h142
`define CSR_STVAL     12'h143
`define CSR_SIP       12'h144
`define CSR_SATP      12'h180

`define CSR_MSTATUS   12'h300
`define CSR_MISA      12'h301
`define CSR_MEDELEG   12'h302
`define CSR_MIDELEG   12'h303
`define CSR_MIE       12'h304
`define CSR_MTVEC     12'h305
`define CSR_MSCRATCH  12'h340
`define CSR_MEPC      12'h341
`define CSR_MCAUSE    12'h342
`define CSR_MTVAL     12'h343
`define CSR_MIP       12'h344

`define CSR_MCYCLE    12'hB00
`define CSR_MINSTRET  12'hB02
`define CSR_MCYCLEH   12'hB80
`define CSR_MINSTRETH 12'hB82
`define CSR_CYCLE     12'hC00
`define CSR_INSTRET   12'hC02
`define CSR_CYCLEH    12'hC80
`define CSR_INSTRETH  12'hC82

`define CSR_MVENDORID 12'hF11
`define CSR_MARCHID   12'hF12
`define CSR_MIMPID    12'hF13
`define CSR_MHARTID   12'hF14

//------------------------------------------------------------------
// Privilege levels
//------------------------------------------------------------------
`define PRV_U 2'b00
`define PRV_S 2'b01
`define PRV_M 2'b11

//------------------------------------------------------------------
// Exception codes (mcause/scause)
//------------------------------------------------------------------
`define CAUSE_INSN_MISALIGN   4'd0
`define CAUSE_INSN_ACCESS     4'd1
`define CAUSE_ILLEGAL_INSN    4'd2
`define CAUSE_BREAKPOINT      4'd3
`define CAUSE_LOAD_MISALIGN   4'd4
`define CAUSE_LOAD_ACCESS     4'd5
`define CAUSE_STORE_MISALIGN  4'd6
`define CAUSE_STORE_ACCESS    4'd7
`define CAUSE_ECALL_U         4'd8
`define CAUSE_ECALL_S         4'd9
`define CAUSE_ECALL_M         4'd11
`define CAUSE_INSN_PAGE_FAULT 4'd12
`define CAUSE_LOAD_PAGE_FAULT 4'd13
`define CAUSE_STORE_PAGE_FAULT 4'd15

//------------------------------------------------------------------
// Memory map (matches A5)
//------------------------------------------------------------------
`define BOOTROM_BASE  32'h0000_1000
`define CLINT_BASE    32'h0200_0000
`define PLIC_BASE     32'h0C00_0000
`define UART_BASE     32'h1000_0000
`define TIMER_BASE    32'h1000_1000
`define GPIO_BASE     32'h1000_2000
`define RAM_BASE      32'h8000_0000

//------------------------------------------------------------------
// Reset
//------------------------------------------------------------------
`define RESET_PC      32'h0000_1000

//------------------------------------------------------------------
// Immediate format selector (decoder output)
//------------------------------------------------------------------
`define IMM_I   3'd0
`define IMM_S   3'd1
`define IMM_B   3'd2
`define IMM_U   3'd3
`define IMM_J   3'd4

//------------------------------------------------------------------
// Writeback source selector
//------------------------------------------------------------------
`define WB_ALU  2'd0
`define WB_MEM  2'd1
`define WB_PC4  2'd2
`define WB_CSR  2'd3

//------------------------------------------------------------------
// CSR operation
//------------------------------------------------------------------
`define CSR_OP_RW  2'd0   // CSRRW / CSRRWI
`define CSR_OP_RS  2'd1   // CSRRS / CSRRSI
`define CSR_OP_RC  2'd2   // CSRRC / CSRRCI

//------------------------------------------------------------------
// System instruction subtype (sys_op)
//------------------------------------------------------------------
`define SYS_NONE     4'd0
`define SYS_ECALL    4'd1
`define SYS_EBREAK   4'd2
`define SYS_MRET     4'd3
`define SYS_SRET     4'd4
`define SYS_WFI      4'd5
`define SYS_FENCE    4'd6
`define SYS_FENCE_I  4'd7
`define SYS_SFENCE   4'd8

//------------------------------------------------------------------
// Muldiv operation selector
//------------------------------------------------------------------
`define MD_NONE     4'd0
`define MD_MUL      4'd1
`define MD_MULH     4'd2
`define MD_MULHSU   4'd3
`define MD_MULHU    4'd4
`define MD_DIV      4'd5
`define MD_DIVU     4'd6
`define MD_REM      4'd7
`define MD_REMU     4'd8

//------------------------------------------------------------------
// Forward unit source select
//------------------------------------------------------------------
`define FW_NONE 2'b00   // use regfile output
`define FW_MEM  2'b01   // forward from EX/MEM pipeline register
`define FW_WB   2'b10   // forward from MEM/WB pipeline register

`endif // RISCV_DEFS_VH