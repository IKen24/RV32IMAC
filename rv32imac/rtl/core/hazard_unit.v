module hazard_unit (
    input  wire       ex_mem_read,
    input  wire       ex_reg_write,
    input  wire [4:0] ex_rd_addr,
    input  wire       id_use_rs1,
    input  wire       id_use_rs2,
    input  wire [4:0] id_rs1_addr,
    input  wire [4:0] id_rs2_addr,
    input  wire       ex_branch_taken,
    input  wire       ex_jump,
    input  wire       ex_trap,
    input  wire       muldiv_stall,     // NEW

    output wire       stall,
    output wire       flush_if_id,
    output wire       flush_id_ex
);

    wire ld_producer = ex_mem_read && ex_reg_write && (ex_rd_addr != 5'd0);
    wire id_match_rs1 = id_use_rs1 && (id_rs1_addr == ex_rd_addr);
    wire id_match_rs2 = id_use_rs2 && (id_rs2_addr == ex_rd_addr);
    wire load_use = ld_producer && (id_match_rs1 || id_match_rs2);

    // stall freezes PC + IF/ID + ID/EX.
    // Load-use and muldiv-busy both stall.
    assign stall = load_use || muldiv_stall;

    // IF/ID is cleared only on redirect.
    assign flush_if_id = ex_branch_taken || ex_jump || ex_trap;

    // ID/EX is cleared on redirect OR load-use (bubble insertion).
    // muldiv stall must NOT clear ID/EX -- it must hold it.
    assign flush_id_ex = (ex_branch_taken || ex_jump || ex_trap) || load_use;

endmodule