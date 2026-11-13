import risc_pkg::*;

// 5-stage pipelined RV32I core:  IF -> ID -> EX -> MEM -> WB
//
//   pc -> fetch -> [if_pipe] -> decode / control / register_file -> [id_pipe]
//      -> forwarding / alu / branch_control -> [ex_pipe]
//      -> load_store_unit -> [mem_pipe] -> register_file write
//
// Signal prefix = stage the instruction is in (if_, id_, ex_, mem_, wb_).
// Every instruction carries its own valid bit and PC; every side effect
// (register write, memory access, PC redirect) is qualified with valid.
//
// The memories are outside the core (soc_top). Both ports have no wait states:
//   instruction port: imem_rdata belongs to imem_addr in the same cycle
//   data port:        dmem_rdata belongs to dmem_addr in the same cycle,
//                     a write happens at the clock edge when dmem_req && dmem_we
// Addresses are byte addresses. dmem_addr is the full address of the access,
// dmem_be/dmem_wdata are already arranged into the byte lanes of the word.

module core #(
    parameter RESET_PC = 32'h0000
) (
    input  logic        clk,
    input  logic        rst_n,

    // instruction port (IF)
    output logic        imem_req,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,

    // data port (MEM)
    output logic        dmem_req,
    output logic        dmem_we,
    output logic [31:0] dmem_addr,
    output logic [3:0]  dmem_be,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,

    // an instruction leaves WB in this cycle (INSTRET counter)
    output logic        retire
);

//=============================================================================
// Signals
//=============================================================================

    // hazard control
    logic        stall_if, stall_id, flush_id, flush_ex;
    logic        ex_redirect;              // taken branch / JAL / JALR in EX
    logic [31:0] ex_target;

    // IF
    logic        reset_seen;
    logic [31:0] pc;
    logic [31:0] if_instruction;

    // ID (if_pipe outputs + decode/control/register file)
    logic        id_valid;
    logic [31:0] id_pc, id_instruction;
    logic [6:0]  id_opcode, id_funct7;
    logic [2:0]  id_funct3;
    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic        id_r_type, id_i_type, id_s_type, id_b_type, id_u_type, id_j_type;
    logic [31:0] id_immediate;
    logic [31:0] rf_rs1_data, rf_rs2_data;   // raw register file outputs
    logic [31:0] id_rs1_data, id_rs2_data;   // after WB -> ID bypass
    logic        id_uses_rs1, id_uses_rs2;
    control_t    id_ctrl;

    // EX (id_pipe outputs + datapath)
    logic        ex_valid;
    logic [31:0] ex_pc;
    logic [4:0]  ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    logic [2:0]  ex_funct3;
    logic        ex_is_branch;
    logic [31:0] ex_imm;
    logic [31:0] ex_rs1_data, ex_rs2_data;   // read in ID
    control_t    ex_ctrl;
    logic [31:0] ex_rs1, ex_rs2;             // after forwarding
    logic [31:0] alu_a, alu_b, ex_alu_res;
    logic        ex_branch_taken;
    logic [31:0] ex_result;

    // MEM (ex_pipe outputs + load/store unit)
    logic        mem_valid;
    logic [31:0] mem_pc;
    logic [4:0]  mem_rd_addr;
    logic [31:0] mem_result, mem_store_data;
    control_t    mem_ctrl;
    logic [31:0] mem_load_data;
    logic [31:0] mem_wb_data;

    // WB (mem_pipe outputs)
    logic        wb_valid;
    logic [31:0] wb_pc;                      // for RVFI later
    logic [4:0]  wb_rd_addr;
    logic        wb_rf_wr_en;
    logic [31:0] wb_data;
    logic        wb_rf_we;                   // register file write enable

//=============================================================================
// IF - instruction fetch
//=============================================================================

    // fetch.req_reg is 0 in the first cycle after reset, so the PC waits too
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) reset_seen <= 1'b0;
        else        reset_seen <= 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= RESET_PC;
        end else if (reset_seen) begin
            if (ex_redirect)    pc <= ex_target;        // resolved in EX
            else if (!stall_if) pc <= pc + 32'd4;       // predict not taken
        end
    end

    fetch u_fetch (
        .clk         (clk),
        .rst_n       (rst_n),
        .pc          (pc),
        .imem_req    (imem_req),
        .imem_addr   (imem_addr),
        .imem_data   (imem_rdata),
        .instruction (if_instruction)
    );

    if_pipe u_if_pipe (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall           (stall_id),
        .flush           (flush_id),
        .valid_in        (imem_req),
        .pc_in           (pc),
        .instruction_in  (if_instruction),
        .valid_out       (id_valid),
        .pc_out          (id_pc),
        .instruction_out (id_instruction)
    );

//=============================================================================
// ID - decode, control, register file read
//=============================================================================

    decode u_decode (
        .instruction (id_instruction),
        .rs1_addr    (id_rs1_addr),
        .rs2_addr    (id_rs2_addr),
        .rd_addr     (id_rd_addr),
        .opcode      (id_opcode),
        .funct3      (id_funct3),
        .funct7      (id_funct7),
        .r_type      (id_r_type),
        .i_type      (id_i_type),
        .s_type      (id_s_type),
        .b_type      (id_b_type),
        .u_type      (id_u_type),
        .j_type      (id_j_type),
        .immediate   (id_immediate)
    );

    control u_control (
        .r_type           (id_r_type),
        .i_type           (id_i_type),
        .s_type           (id_s_type),
        .b_type           (id_b_type),
        .u_type           (id_u_type),
        .j_type           (id_j_type),
        .funct3           (id_funct3),
        .funct7           (id_funct7),
        .opcode           (id_opcode),
        .pc_sel           (id_ctrl.pc_src_select),
        .op1_sel          (id_ctrl.alu_src_a_select),
        .op2_sel          (id_ctrl.alu_src_b_select),
        .alu_op           (id_ctrl.alu_op),
        .rf_wr_data_sel   (id_ctrl.wb_src),
        .dmem_req         (id_ctrl.mem_valid),
        .dmem_size        (id_ctrl.mem_size),
        .dmem_wr_en       (id_ctrl.mem_write),
        .dmem_zero_extend (id_ctrl.load_zero_extend),
        .rf_wr_en         (id_ctrl.rf_write_enable)
    );

    // read in ID, written by the instruction in WB
    register_file u_register_file (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_rs1_addr),
        .rs2_addr (id_rs2_addr),
        .rd_addr  (wb_rd_addr),
        .rf_wr_en (wb_rf_we),
        .wr_data  (wb_data),
        .rs1_data (rf_rs1_data),
        .rs2_data (rf_rs2_data)
    );

    // WB -> ID bypass: register written in this cycle is read in this cycle
    assign id_rs1_data = (wb_rf_we && (wb_rd_addr != 5'd0) && (wb_rd_addr == id_rs1_addr))
                         ? wb_data : rf_rs1_data;
    assign id_rs2_data = (wb_rf_we && (wb_rd_addr != 5'd0) && (wb_rd_addr == id_rs2_addr))
                         ? wb_data : rf_rs2_data;

    // source registers the instruction really reads (for load-use detection)
    assign id_uses_rs1 = id_r_type | id_i_type | id_s_type | id_b_type;
    assign id_uses_rs2 = id_r_type | id_s_type | id_b_type;

    id_pipe u_id_pipe (
        .clk           (clk),
        .rst_n         (rst_n),
        .stall         (1'b0),
        .flush         (flush_ex),           // load-use bubble or wrong path
        .valid_in      (id_valid),
        .pc_in         (id_pc),
        .rs1_addr_in   (id_rs1_addr),
        .rs2_addr_in   (id_rs2_addr),
        .rd_addr_in    (id_rd_addr),
        .funct3_in     (id_funct3),
        .is_branch_in  (id_b_type),
        .imm_in        (id_immediate),
        .rs1_data_in   (id_rs1_data),
        .rs2_data_in   (id_rs2_data),
        .ctrl_in       (id_ctrl),
        .valid_out     (ex_valid),
        .pc_out        (ex_pc),
        .rs1_addr_out  (ex_rs1_addr),
        .rs2_addr_out  (ex_rs2_addr),
        .rd_addr_out   (ex_rd_addr),
        .funct3_out    (ex_funct3),
        .is_branch_out (ex_is_branch),
        .imm_out       (ex_imm),
        .rs1_data_out  (ex_rs1_data),
        .rs2_data_out  (ex_rs2_data),
        .ctrl_out      (ex_ctrl)
    );

//=============================================================================
// EX - forwarding, ALU, branch resolution
//=============================================================================

    forwarding_unit u_forwarding_unit (
        .ex_rs1_addr  (ex_rs1_addr),
        .ex_rs2_addr  (ex_rs2_addr),
        .ex_rs1_data  (ex_rs1_data),
        .ex_rs2_data  (ex_rs2_data),
        .mem_valid    (mem_valid),
        .mem_rf_wr_en (mem_ctrl.rf_write_enable),
        .mem_rd_addr  (mem_rd_addr),
        .mem_result   (mem_result),
        .wb_valid     (wb_valid),
        .wb_rf_wr_en  (wb_rf_wr_en),
        .wb_rd_addr   (wb_rd_addr),
        .wb_data      (wb_data),
        .rs1_fwd      (ex_rs1),
        .rs2_fwd      (ex_rs2)
    );

    assign alu_a = ex_ctrl.alu_src_a_select ? ex_pc  : ex_rs1;
    assign alu_b = ex_ctrl.alu_src_b_select ? ex_imm : ex_rs2;

    alu u_alu (
        .alu_a   (alu_a),
        .alu_b   (alu_b),
        .alu_op  (ex_ctrl.alu_op),
        .alu_res (ex_alu_res)
    );

    branch_control u_branch_control (
        .opr_a        (ex_rs1),
        .opr_b        (ex_rs2),
        .is_b_type    (ex_is_branch),
        .funct3       (ex_funct3),
        .branch_taken (ex_branch_taken)
    );

    // ALU computes PC + imm (branch, JAL) or rs1 + imm (JALR); bit 0 cleared
    assign ex_redirect = ex_valid && (ex_branch_taken || ex_ctrl.pc_src_select);
    assign ex_target   = {ex_alu_res[31:1], 1'b0};

    // value for rd, known in EX for everything except loads
    always_comb begin
        case (ex_ctrl.wb_src)
            WB_SRC_PC:  ex_result = ex_pc + 32'd4;      // JAL/JALR link
            WB_SRC_IMM: ex_result = ex_imm;             // LUI
            default:    ex_result = ex_alu_res;         // ALU, AUIPC, load/store address
        endcase
    end

    ex_pipe u_ex_pipe (
        .clk            (clk),
        .rst_n          (rst_n),
        .stall          (1'b0),
        .flush          (1'b0),
        .valid_in       (ex_valid),
        .pc_in          (ex_pc),
        .rd_addr_in     (ex_rd_addr),
        .result_in      (ex_result),
        .store_data_in  (ex_rs2),                // after forwarding
        .ctrl_in        (ex_ctrl),
        .valid_out      (mem_valid),
        .pc_out         (mem_pc),
        .rd_addr_out    (mem_rd_addr),
        .result_out     (mem_result),
        .store_data_out (mem_store_data),
        .ctrl_out       (mem_ctrl)
    );

//=============================================================================
// MEM - data port (memory is in soc_top)
//=============================================================================

    assign dmem_req  = mem_valid && mem_ctrl.mem_valid;
    assign dmem_we   = dmem_req  && mem_ctrl.mem_write;
    assign dmem_addr = mem_result;

    load_store_unit u_load_store_unit (
        .addr_lo     (mem_result[1:0]),
        .size        (mem_ctrl.mem_size),
        .zero_extend (mem_ctrl.load_zero_extend),
        .store_data  (mem_store_data),
        .be          (dmem_be),
        .wdata       (dmem_wdata),
        .rdata       (dmem_rdata),
        .load_data   (mem_load_data)
    );

    assign mem_wb_data = (mem_ctrl.wb_src == WB_SRC_MEM) ? mem_load_data : mem_result;

    mem_pipe u_mem_pipe (
        .clk          (clk),
        .rst_n        (rst_n),
        .stall        (1'b0),
        .valid_in     (mem_valid),
        .pc_in        (mem_pc),
        .rd_addr_in   (mem_rd_addr),
        .rf_wr_en_in  (mem_ctrl.rf_write_enable),
        .wb_data_in   (mem_wb_data),
        .valid_out    (wb_valid),
        .pc_out       (wb_pc),
        .rd_addr_out  (wb_rd_addr),
        .rf_wr_en_out (wb_rf_wr_en),
        .wb_data_out  (wb_data)
    );

//=============================================================================
// WB - register file write (register_file is instantiated in ID)
//=============================================================================

    assign wb_rf_we = wb_valid && wb_rf_wr_en;
    assign retire   = wb_valid;

//=============================================================================
// Hazard unit: load-use stall, flush on taken branch / jump
//=============================================================================

    hazard_unit u_hazard_unit (
        .id_valid    (id_valid),
        .id_rs1_addr (id_rs1_addr),
        .id_rs2_addr (id_rs2_addr),
        .id_uses_rs1 (id_uses_rs1),
        .id_uses_rs2 (id_uses_rs2),
        .ex_valid    (ex_valid),
        .ex_is_load  (ex_ctrl.mem_valid && !ex_ctrl.mem_write),
        .ex_rd_addr  (ex_rd_addr),
        .ex_redirect (ex_redirect),
        .stall_if    (stall_if),
        .stall_id    (stall_id),
        .flush_id    (flush_id),
        .flush_ex    (flush_ex)
    );

endmodule
