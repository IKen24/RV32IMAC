//=============================================================================
// File:    rtl/riscv_defs.vh
// Purpose: Global RISC-V constants shared across all modules.
//          Frozen after first use. Changes here invalidate every TB.
//=============================================================================
`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH                 // include-guard macro for this header file

//------------------------------------------------------------------
// XLEN
//------------------------------------------------------------------
`define XLEN 32                       // integer register width: 32-bit RISC-V (RV32)

//------------------------------------------------------------------
// ALU op encodings (frozen; mirrored from alu.v F01)
//------------------------------------------------------------------
`define ALU_ADD     5'd0              // ALU op: add A + B
`define ALU_SUB     5'd1              // ALU op: subtract A - B
`define ALU_SLL     5'd2              // ALU op: shift A left logical by B
`define ALU_SLT     5'd3              // ALU op: signed less-than, 1 if A < B signed
`define ALU_SLTU    5'd4              // ALU op: unsigned less-than, 1 if A < B unsigned
`define ALU_XOR     5'd5              // ALU op: bitwise XOR A ^ B
`define ALU_SRL     5'd6              // ALU op: shift A right logical by B
`define ALU_SRA     5'd7              // ALU op: shift A right arithmetic by B, sign-fill
`define ALU_OR      5'd8              // ALU op: bitwise OR A | B
`define ALU_AND     5'd9              // ALU op: bitwise AND A & B
`define ALU_PASS_A  5'd10             // ALU op: pass A through unchanged
`define ALU_PASS_B  5'd11             // ALU op: pass B through unchanged

//------------------------------------------------------------------
// RV32I major opcodes (inst[6:0])
//------------------------------------------------------------------
`define OP_LUI      7'b0110111        // major opcode: LUI, load upper immediate into rd
`define OP_AUIPC    7'b0010111        // major opcode: AUIPC, add upper immediate to PC
`define OP_JAL      7'b1101111        // major opcode: JAL, jump and link, save return address
`define OP_JALR     7'b1100111        // major opcode: JALR, jump and link via register
`define OP_BRANCH   7'b1100011        // major opcode: conditional branch group
`define OP_LOAD     7'b0000011        // major opcode: load from memory into rd
`define OP_STORE    7'b0100011        // major opcode: store from rs2 to memory
`define OP_OP_IMM   7'b0010011        // major opcode: integer ALU op with immediate
`define OP_OP       7'b0110011        // major opcode: integer ALU op register-register
`define OP_MISC_MEM 7'b0001111        // major opcode: FENCE / FENCE.I memory ordering
`define OP_SYSTEM   7'b1110011        // major opcode: SYSTEM, CSR/ECALL/EBREAK/MRET/etc.

// RV32M uses OP_OP with funct7=0000001
`define FUNCT7_M    7'b0000001        // funct7 value marking RV32M multiply/divide ops

// RV32A uses OP_ATOMIC
`define OP_ATOMIC   7'b0101111        // major opcode: RV32A atomic memory operations
`define FUNCT5_LR   5'b00010          // funct5: LR.W load-reserved atomic operation
`define FUNCT5_SC   5'b00011          // funct5: SC.W store-conditional atomic operation

//------------------------------------------------------------------
// Branch funct3
//------------------------------------------------------------------
`define F3_BEQ  3'b000                // branch funct3: branch if rs1 == rs2
`define F3_BNE  3'b001                // branch funct3: branch if rs1 != rs2
`define F3_BLT  3'b100                // branch funct3: branch if rs1 < rs2 signed
`define F3_BGE  3'b101                // branch funct3: branch if rs1 >= rs2 signed
`define F3_BLTU 3'b110                // branch funct3: branch if rs1 < rs2 unsigned
`define F3_BGEU 3'b111                // branch funct3: branch if rs1 >= rs2 unsigned
`define F3_JALR 3'b000                // JALR funct3: always 000

//------------------------------------------------------------------
// Load funct3
//------------------------------------------------------------------
`define F3_LB   3'b000                // load funct3: load byte, sign-extended
`define F3_LH   3'b001                // load funct3: load halfword, sign-extended
`define F3_LW   3'b010                // load funct3: load word, 32 bits
`define F3_LBU  3'b100                // load funct3: load byte, zero-extended
`define F3_LHU  3'b101                // load funct3: load halfword, zero-extended

//------------------------------------------------------------------
// Store funct3
//------------------------------------------------------------------
`define F3_SB   3'b000                // store funct3: store byte
`define F3_SH   3'b001                // store funct3: store halfword
`define F3_SW   3'b010                // store funct3: store word

//------------------------------------------------------------------
// OP-IMM funct3
//------------------------------------------------------------------
`define F3_ADDI  3'b000               // OP-IMM funct3: add immediate
`define F3_SLTI  3'b010               // OP-IMM funct3: signed less-than immediate
`define F3_SLTIU 3'b011               // OP-IMM funct3: unsigned less-than immediate
`define F3_XORI  3'b100               // OP-IMM funct3: XOR immediate
`define F3_ORI   3'b110               // OP-IMM funct3: OR immediate
`define F3_ANDI  3'b111               // OP-IMM funct3: AND immediate
`define F3_SLLI  3'b001               // OP-IMM funct3: shift left logical immediate
`define F3_SRI   3'b101               // OP-IMM funct3: shift right immediate; SRLI/SRAI by funct7[5]

//------------------------------------------------------------------
// OP funct3 (register-register)
//------------------------------------------------------------------
`define F3_ADD_SUB  3'b000            // OP funct3: ADD or SUB, selected by funct7
`define F3_SLL      3'b001            // OP funct3: shift left logical
`define F3_SLT      3'b010            // OP funct3: signed less-than
`define F3_SLTU     3'b011            // OP funct3: unsigned less-than
`define F3_XOR      3'b100            // OP funct3: bitwise XOR
`define F3_SR       3'b101            // OP funct3: SRL or SRA, selected by funct7
`define F3_OR       3'b110            // OP funct3: bitwise OR
`define F3_AND      3'b111            // OP funct3: bitwise AND

//------------------------------------------------------------------
// RV32M funct3
//------------------------------------------------------------------
`define F3_MUL      3'b000            // RV32M funct3: multiply, low 32 bits of product
`define F3_MULH     3'b001            // RV32M funct3: signed × signed, high 32 bits
`define F3_MULHSU   3'b010            // RV32M funct3: signed × unsigned, high 32 bits
`define F3_MULHU    3'b011            // RV32M funct3: unsigned × unsigned, high 32 bits
`define F3_DIV      3'b100            // RV32M funct3: signed division quotient
`define F3_DIVU     3'b101            // RV32M funct3: unsigned division quotient
`define F3_REM      3'b110            // RV32M funct3: signed division remainder
`define F3_REMU     3'b111            // RV32M funct3: unsigned division remainder

//------------------------------------------------------------------
// RV32A funct5 (inst[31:27])
//------------------------------------------------------------------
`define A_AMOSWAP   5'b00001          // atomic op: swap memory and register
`define A_AMOADD    5'b00000          // atomic op: add register to memory
`define A_AMOXOR    5'b00100          // atomic op: XOR register into memory
`define A_AMOAND    5'b01100          // atomic op: AND register into memory
`define A_AMOOR     5'b01000          // atomic op: OR register into memory
`define A_AMOMIN    5'b10000          // atomic op: signed minimum into memory
`define A_AMOMAX    5'b10100          // atomic op: signed maximum into memory
`define A_AMOMINU   5'b11000          // atomic op: unsigned minimum into memory
`define A_AMOMAXU   5'b11100          // atomic op: unsigned maximum into memory

//------------------------------------------------------------------
// SYSTEM funct3 / funct12
//------------------------------------------------------------------
`define F3_PRIV     3'b000            // SYSTEM funct3: privileged instruction such as ECALL/EBREAK/MRET
`define F3_CSRRW    3'b001            // SYSTEM funct3: CSR read/write
`define F3_CSRRS    3'b010            // SYSTEM funct3: CSR read and set bits
`define F3_CSRRC    3'b011            // SYSTEM funct3: CSR read and clear bits
`define F3_CSRRWI   3'b101            // SYSTEM funct3: CSR read/write with immediate
`define F3_CSRRSI   3'b110            // SYSTEM funct3: CSR read/set with immediate
`define F3_CSRRCI   3'b111            // SYSTEM funct3: CSR read/clear with immediate

`define FUNCT12_ECALL   12'h000       // SYSTEM funct12: ECALL, environment call trap
`define FUNCT12_EBREAK  12'h001       // SYSTEM funct12: EBREAK, breakpoint trap
`define FUNCT12_MRET    12'h302       // SYSTEM funct12: MRET, return from machine trap
`define FUNCT12_SRET    12'h102       // SYSTEM funct12: SRET, return from supervisor trap
`define FUNCT12_WFI     12'h105       // SYSTEM funct12: WFI, wait for interrupt
`define FUNCT12_SFENCE  12'h120       // SYSTEM funct12: SFENCE.VMA, supervisor address-translation fence

//------------------------------------------------------------------
// CSR addresses (Privileged Spec v1.11)
//------------------------------------------------------------------
`define CSR_USTATUS   12'h000         // CSR: user status register
`define CSR_UIE       12'h004         // CSR: user interrupt-enable register
`define CSR_UTVEC     12'h005         // CSR: user trap vector base
`define CSR_USCRATCH  12'h040         // CSR: user scratch register
`define CSR_UEPC      12'h041         // CSR: user exception program counter
`define CSR_UCAUSE    12'h042         // CSR: user trap cause
`define CSR_UTVAL     12'h043         // CSR: user trap value
`define CSR_UIP       12'h044         // CSR: user interrupt-pending register

`define CSR_SSTATUS   12'h100         // CSR: supervisor status register
`define CSR_SIE       12'h104         // CSR: supervisor interrupt-enable register
`define CSR_STVEC     12'h105         // CSR: supervisor trap vector base
`define CSR_SSCRATCH  12'h140         // CSR: supervisor scratch register
`define CSR_SEPC      12'h141         // CSR: supervisor exception program counter
`define CSR_SCAUSE    12'h142         // CSR: supervisor trap cause
`define CSR_STVAL     12'h143         // CSR: supervisor trap value
`define CSR_SIP       12'h144         // CSR: supervisor interrupt-pending register
`define CSR_SATP      12'h180         // CSR: supervisor address translation and protection, page-table base/mode

`define CSR_MSTATUS   12'h300         // CSR: machine status register
`define CSR_MISA      12'h301         // CSR: machine ISA and extension bits
`define CSR_MEDELEG   12'h302         // CSR: machine exception delegation to supervisor
`define CSR_MIDELEG   12'h303         // CSR: machine interrupt delegation to supervisor
`define CSR_MIE       12'h304         // CSR: machine interrupt-enable register
`define CSR_MTVEC     12'h305         // CSR: machine trap vector base
`define CSR_MSCRATCH  12'h340         // CSR: machine scratch register
`define CSR_MEPC      12'h341         // CSR: machine exception program counter
`define CSR_MCAUSE    12'h342         // CSR: machine trap cause
`define CSR_MTVAL     12'h343         // CSR: machine trap value
`define CSR_MIP       12'h344         // CSR: machine interrupt-pending register

`define CSR_MCYCLE    12'hB00         // CSR: machine cycle counter, low 32 bits
`define CSR_MINSTRET  12'hB02         // CSR: machine retired-instruction counter, low 32 bits
`define CSR_MCYCLEH   12'hB80         // CSR: machine cycle counter, high 32 bits
`define CSR_MINSTRETH 12'hB82         // CSR: machine retired-instruction counter, high 32 bits
`define CSR_CYCLE     12'hC00         // CSR: user cycle counter, low 32 bits
`define CSR_INSTRET   12'hC02         // CSR: user retired-instruction counter, low 32 bits
`define CSR_CYCLEH    12'hC80         // CSR: user cycle counter, high 32 bits
`define CSR_INSTRETH  12'hC82         // CSR: user retired-instruction counter, high 32 bits

`define CSR_MVENDORID 12'hF11         // CSR: machine vendor ID
`define CSR_MARCHID   12'hF12         // CSR: machine architecture ID
`define CSR_MIMPID    12'hF13         // CSR: machine implementation ID
`define CSR_MHARTID   12'hF14         // CSR: machine hart ID

//------------------------------------------------------------------
// Privilege levels
//------------------------------------------------------------------
`define PRV_U 2'b00                   // privilege mode: user mode
`define PRV_S 2'b01                   // privilege mode: supervisor mode
`define PRV_M 2'b11                   // privilege mode: machine mode

//------------------------------------------------------------------
// Exception codes (mcause/scause)
//------------------------------------------------------------------
`define CAUSE_INSN_MISALIGN   4'd0    // trap cause: instruction address misaligned
`define CAUSE_INSN_ACCESS     4'd1    // trap cause: instruction access fault
`define CAUSE_ILLEGAL_INSN    4'd2    // trap cause: illegal instruction
`define CAUSE_BREAKPOINT      4'd3    // trap cause: breakpoint
`define CAUSE_LOAD_MISALIGN   4'd4    // trap cause: load address misaligned
`define CAUSE_LOAD_ACCESS     4'd5    // trap cause: load access fault
`define CAUSE_STORE_MISALIGN  4'd6    // trap cause: store/AMO address misaligned
`define CAUSE_STORE_ACCESS    4'd7    // trap cause: store/AMO access fault
`define CAUSE_ECALL_U         4'd8    // trap cause: environment call from user mode
`define CAUSE_ECALL_S         4'd9    // trap cause: environment call from supervisor mode
`define CAUSE_ECALL_M         4'd11   // trap cause: environment call from machine mode
`define CAUSE_INSN_PAGE_FAULT 4'd12   // trap cause: instruction page fault
`define CAUSE_LOAD_PAGE_FAULT 4'd13   // trap cause: load page fault
`define CAUSE_STORE_PAGE_FAULT 4'd15  // trap cause: store/AMO page fault

//------------------------------------------------------------------
// Memory map (matches A5)
//------------------------------------------------------------------
`define BOOTROM_BASE  32'h0000_1000    // memory map: boot ROM base address
`define CLINT_BASE    32'h0200_0000    // memory map: core-local interruptor base, timer/software interrupts
`define PLIC_BASE     32'h0C00_0000    // memory map: platform-level interrupt controller base
`define UART_BASE     32'h1000_0000    // memory map: UART serial port base
`define TIMER_BASE    32'h1000_1000    // memory map: timer base
`define GPIO_BASE     32'h1000_2000    // memory map: GPIO base
`define RAM_BASE      32'h8000_0000    // memory map: main RAM base

//------------------------------------------------------------------
// Reset
//------------------------------------------------------------------
`define RESET_PC      32'h0000_1000    // PC value loaded after reset

//------------------------------------------------------------------
// Immediate format selector (decoder output)
//------------------------------------------------------------------
`define IMM_I   3'd0                  // immediate format: I-type, loads/ALU-immediate/JALR
`define IMM_S   3'd1                  // immediate format: S-type, stores
`define IMM_B   3'd2                  // immediate format: B-type, branches
`define IMM_U   3'd3                  // immediate format: U-type, LUI/AUIPC
`define IMM_J   3'd4                  // immediate format: J-type, JAL

//------------------------------------------------------------------
// Writeback source selector
//------------------------------------------------------------------
`define WB_ALU  2'd0                  // writeback source: ALU result
`define WB_MEM  2'd1                  // writeback source: loaded memory data
`define WB_PC4  2'd2                  // writeback source: PC+4 return address
`define WB_CSR  2'd3                  // writeback source: CSR read value

//------------------------------------------------------------------
// CSR operation
//------------------------------------------------------------------
`define CSR_OP_RW  2'd0               // CSR operation: read/write CSR
`define CSR_OP_RS  2'd1               // CSR operation: read CSR and set bits
`define CSR_OP_RC  2'd2               // CSR operation: read CSR and clear bits

//------------------------------------------------------------------
// System instruction subtype (sys_op)
//------------------------------------------------------------------
`define SYS_NONE     4'd0             // system subtype: no system operation
`define SYS_ECALL    4'd1             // system subtype: ECALL, environment call
`define SYS_EBREAK   4'd2             // system subtype: EBREAK, breakpoint
`define SYS_MRET     4'd3             // system subtype: MRET, return from machine trap
`define SYS_SRET     4'd4             // system subtype: SRET, return from supervisor trap
`define SYS_WFI      4'd5             // system subtype: WFI, wait for interrupt
`define SYS_FENCE    4'd6             // system subtype: FENCE, memory ordering
`define SYS_FENCE_I  4'd7             // system subtype: FENCE.I, instruction-cache synchronization
`define SYS_SFENCE   4'd8             // system subtype: SFENCE.VMA, address-translation fence

//------------------------------------------------------------------
// Muldiv operation selector
//------------------------------------------------------------------
`define MD_NONE     4'd0              // muldiv op: none
`define MD_MUL      4'd1              // muldiv op: multiply, low 32 bits
`define MD_MULH     4'd2              // muldiv op: signed × signed, high 32 bits
`define MD_MULHSU   4'd3              // muldiv op: signed × unsigned, high 32 bits
`define MD_MULHU    4'd4              // muldiv op: unsigned × unsigned, high 32 bits
`define MD_DIV      4'd5              // muldiv op: signed division quotient
`define MD_DIVU     4'd6              // muldiv op: unsigned division quotient
`define MD_REM      4'd7              // muldiv op: signed division remainder
`define MD_REMU     4'd8              // muldiv op: unsigned division remainder

//------------------------------------------------------------------
// Forward unit source select
//------------------------------------------------------------------
`define FW_NONE 2'b00                  // forwarding select: no forward, use register file output
`define FW_MEM  2'b01                  // forwarding select: forward from EX/MEM pipeline register
`define FW_WB   2'b10                  // forwarding select: forward from MEM/WB pipeline register

`endif // RISCV_DEFS_VH
