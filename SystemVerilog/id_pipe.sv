import risc_pkg::*;

module id_pipe (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        stall,          // za sada 1'b0 (kasnije: delitelj u EX)
    input  logic        flush,          // load-use bubble ili skok/grananje u EX

    // iz if_pipe
    input  logic        valid_in,      
    input  logic [31:0] pc_in,

    // iz decode
    input  logic [4:0]  rd_addr_in,
    input  logic [2:0]  funct3_in,
    input  logic        is_branch_in,   // b_type
    input  logic [31:0] imm_in,

    // iz register_file
    input  logic [31:0] rs1_data_in,
    input  logic [31:0] rs2_data_in,
    input  logic [4:0] rs1_addr_in,
    input  logic [4:0] rs2_addr_in,

    // iz control
    input  control_t    ctrl_in,


    output logic        valid_out,
    output logic [31:0] pc_out,

    output logic [4:0]  rd_addr_out,
    output logic [2:0]  funct3_out,
    output logic        is_branch_out,
    output logic [31:0] imm_out,
    output logic [31:0] rs1_data_out,
    output logic [31:0] rs2_data_out,
    output logic [4:0] rs1_addr_out,
    output logic [4:0] rs2_addr_out,

    output control_t    ctrl_out
);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_out     <= 1'b0;
        pc_out        <= 32'b0;
        rd_addr_out   <= 5'b0;
        rs1_addr_out   <= 5'b0;
        rs2_addr_out   <= 5'b0;
        funct3_out    <= 3'b0;
        is_branch_out <= 1'b0;
        imm_out       <= 32'b0;
        rs1_data_out  <= 32'b0;
        rs2_data_out  <= 32'b0;
        ctrl_out      <= '0;
    end else if (flush) begin           // bubble: dovoljno je ugasiti valid i kontrolu
        valid_out     <= 1'b0;
        ctrl_out      <= '0;
    end else if (!stall) begin
        valid_out     <= valid_in;
        pc_out        <= pc_in;
        rd_addr_out   <= rd_addr_in;
        rs1_addr_out   <= rs1_addr_in;
        rs2_addr_out   <= rs2_addr_in;
        funct3_out    <= funct3_in;
        is_branch_out <= is_branch_in;
        imm_out       <= imm_in;
        rs1_data_out  <= rs1_data_in;
        rs2_data_out  <= rs2_data_in;
        ctrl_out      <= ctrl_in;
    end
end

endmodule