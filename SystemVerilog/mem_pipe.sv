module mem_pipe (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        stall,          // za sada 1'b0 (kasnije: čekanje na DMEM)

    // iz MEM stepena
    input  logic        valid_in,
    input  logic [31:0] pc_in,
    input  logic [4:0]  rd_addr_in,
    input  logic        rf_wr_en_in,    // mem_ctrl.rf_write_enable
    input  logic [31:0] wb_data_in,     // dmem_rd_data (load) ili mem_result

    output logic        valid_out,
    output logic [31:0] pc_out,
    output logic [4:0]  rd_addr_out,
    output logic        rf_wr_en_out,
    output logic [31:0] wb_data_out
);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_out    <= 1'b0;
        pc_out       <= 32'b0;
        rd_addr_out  <= 5'b0;
        rf_wr_en_out <= 1'b0;
        wb_data_out  <= 32'b0;
    end else if (!stall) begin
        valid_out    <= valid_in;
        pc_out       <= pc_in;
        rd_addr_out  <= rd_addr_in;
        rf_wr_en_out <= rf_wr_en_in;
        wb_data_out  <= wb_data_in;
    end
end

endmodule