// Dual-port RAM: 32-bit words, byte enables, 2**ADDR_WIDTH bytes.
//
//   port A (core): asynchronous read, write at the clock edge
//   port B (host): synchronous read (data in the cycle after the request),
//                  write at the clock edge
//
// Addresses are byte addresses; only bits [ADDR_WIDTH-1:2] are used, the
// address decoder in soc_top decides which window the access belongs to.
// Writing the same word from both ports in the same cycle is not defined:
// the host writes only while the core is stopped.
//
// FPGA block RAM: port A must become synchronous too (IMEM addressed with
// next_pc, load data arriving in WB). Until then this maps to LUT RAM.
// The memory is written with "always @(posedge clk)" instead of always_ff,
// because always_ff variables may not also be written by the initial block.

module dual_port_ram #(
    parameter ADDR_WIDTH = 14,          // 16 KB
    parameter INIT_FILE  = ""           // optional $readmemh, one 32-bit word per line
) (
    input  logic        clk,

    // port A (core)
    input  logic        a_req,
    input  logic        a_we,
    input  logic [31:0] a_addr,
    input  logic [3:0]  a_be,
    input  logic [31:0] a_wdata,
    output logic [31:0] a_rdata,

    // port B (host)
    input  logic        b_req,
    input  logic        b_we,
    input  logic [31:0] b_addr,
    input  logic [3:0]  b_be,
    input  logic [31:0] b_wdata,
    output logic [31:0] b_rdata
);

    localparam WORDS = 2**(ADDR_WIDTH-2);

    logic [31:0]           mem [0:WORDS-1];
    logic [ADDR_WIDTH-3:0] a_word, b_word;

    assign a_word = a_addr[ADDR_WIDTH-1:2];
    assign b_word = b_addr[ADDR_WIDTH-1:2];

    initial begin
        for (int i = 0; i < WORDS; i++) mem[i] = 32'b0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    // writes, byte by byte
    always @(posedge clk) begin
        for (int i = 0; i < 4; i++) begin
            if (a_req && a_we && a_be[i]) mem[a_word][8*i +: 8] <= a_wdata[8*i +: 8];
            if (b_req && b_we && b_be[i]) mem[b_word][8*i +: 8] <= b_wdata[8*i +: 8];
        end
    end

    // port A: asynchronous read
    assign a_rdata = mem[a_word];

    // port B: synchronous read
    always @(posedge clk) begin
        if (b_req && !b_we) b_rdata <= mem[b_word];
    end

endmodule
