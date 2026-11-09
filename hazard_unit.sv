// Hazard unit - stall and flush control for the 5-stage pipeline.
//
// 1) Load-use: a load is in EX and the instruction in ID reads its rd.
//    The data only exists after MEM, so: hold PC and IF/ID for one cycle and
//    insert a bubble into ID/EX. Next cycle the load is in WB and the
//    dependent instruction gets the data through MEM/WB -> EX forwarding.
//
// 2) Control: a taken branch or JAL/JALR is resolved in EX. The two younger
//    instructions (in IF/ID and the one being fetched) are on the wrong path:
//    flush IF/ID and ID/EX, PC <- target (2-cycle penalty, static not-taken).
//
// Later: multi-cycle EX (divider) adds a stall_ex that holds PC, IF/ID and
// ID/EX and inserts a bubble into EX/MEM.

module hazard_unit (
    // instruction in ID (IF/ID register + decoder)
    input  logic       id_valid,
    input  logic [4:0] id_rs1_addr,
    input  logic [4:0] id_rs2_addr,
    input  logic       id_uses_rs1,
    input  logic       id_uses_rs2,

    // instruction in EX (ID/EX register)
    input  logic       ex_valid,
    input  logic       ex_is_load,
    input  logic [4:0] ex_rd_addr,
    input  logic       ex_redirect,      // taken branch or JAL/JALR

    output logic       stall_if,         // hold PC
    output logic       stall_id,         // hold IF/ID
    output logic       flush_id,         // IF/ID <- bubble
    output logic       flush_ex          // ID/EX <- bubble
);

    logic load_use;

    assign load_use = ex_valid && ex_is_load && (ex_rd_addr != 5'd0) && id_valid &&
                      ((id_uses_rs1 && (id_rs1_addr == ex_rd_addr)) ||
                       (id_uses_rs2 && (id_rs2_addr == ex_rd_addr)));

    // A load and a redirect can never be in EX at the same time,
    // the redirect still has priority for clarity.
    assign stall_if = load_use && !ex_redirect;
    assign stall_id = load_use && !ex_redirect;
    assign flush_id = ex_redirect;
    assign flush_ex = ex_redirect || load_use;

endmodule
