import risc_pkg::*;

module ex_pipe (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        stall,          // za sada 1'b0 (kasnije: čekanje na DMEM)
    input  logic        flush,          // za sada 1'b0 (kasnije: delitelj zauzet u EX)

    // iz EX stepena
    input  logic        valid_in,
    input  logic [31:0] pc_in,
    input  logic [4:0]  rd_addr_in,
    input  logic [31:0] result_in,      // ALU / PC+4 / imm; za load/store je to adresa
    input  logic [31:0] store_data_in,  // rs2 POSLE forwarding-a
    input  control_t    ctrl_in,        // iz id_pipe; dalje se koriste mem_* i wb polja

    output logic        valid_out,
    output logic [31:0] pc_out,
    output logic [4:0]  rd_addr_out,
    output logic [31:0] result_out,
    output logic [31:0] store_data_out,
    output control_t    ctrl_out
);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_out      <= 1'b0;
        pc_out         <= 32'b0;
        rd_addr_out    <= 5'b0;
        result_out     <= 32'b0;
        store_data_out <= 32'b0;
        ctrl_out       <= '0;
    end else if (flush) begin           // bubble
        valid_out      <= 1'b0;
        ctrl_out       <= '0;
    end else if (!stall) begin
        valid_out      <= valid_in;
        pc_out         <= pc_in;
        rd_addr_out    <= rd_addr_in;
        result_out     <= result_in;
        store_data_out <= store_data_in;
        ctrl_out       <= ctrl_in;
    end
end

endmodule