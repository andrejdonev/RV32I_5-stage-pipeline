module fetch (
    input logic clk,
    input logic rst_n,

    input logic [31:0] pc,

    output logic  imem_req,
    output logic [31:0] imem_addr,

    input logic [31:0] imem_data,
    output logic [31:0] instruction
) ;

//Internal request register

logic req_reg;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        req_reg <= 1'b0;
    end else begin
        req_reg <= 1'b1;
    end
end

assign imem_req = req_reg;
assign imem_addr = pc;
assign instruction = imem_data;

endmodule