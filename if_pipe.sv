module if_pipe (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        stall,           // load-use: zadrži
    input  logic        flush,           // skok/grananje u EX: poništi

    input  logic        valid_in,
    input  logic [31:0] pc_in,
    input  logic [31:0] instruction_in,

    output logic        valid_out,
    output logic [31:0] pc_out,
    output logic [31:0] instruction_out
);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_out       <= 1'b0;
        pc_out          <= 32'b0;
        instruction_out <= 32'b0;
    end else if (flush) begin            // flush ima prednost nad stall-om
        valid_out       <= 1'b0;
        pc_out          <= 32'b0;
        instruction_out <= 32'b0;
    end else if (!stall) begin
        valid_out       <= valid_in;
        pc_out          <= pc_in;
        instruction_out <= instruction_in;
    end
    // stall: ništa se ne upisuje, registar drži staru vrednost
end

endmodule