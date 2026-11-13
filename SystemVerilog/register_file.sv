module register_file (
    input logic clk,
    input logic rst_n,

    //rd reg
    input logic [4:0] rs1_addr,
    input logic [4:0] rs2_addr,

    //wr port
    input logic [4:0] rd_addr,
    input logic       rf_wr_en,
    input logic [31:0] wr_data,

    //rd data
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data
) ;

//reg file declaration
    logic [31:0] regs [0:31];

//Reset and write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(int i = 0; i < 32; i++) begin
                regs[i] <= 32'b0;
            end
        end else if(rf_wr_en && rd_addr != 5'b0) begin
            regs[rd_addr] <= wr_data;
        end
    end

//Read logic
    assign rs1_data = regs[rs1_addr];
    assign rs2_data = regs[rs2_addr];

endmodule