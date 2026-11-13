// Load/store unit (MEM stage) - purely combinational.
//
// The data port works with whole 32-bit words and byte enables (like a block
// RAM, AXI WSTRB or any bus), so the byte lanes are arranged here:
//   store: the data is copied into every lane, be[3:0] selects the bytes written
//   load : the addressed byte / half-word is taken out of the word and extended
//
// Only naturally aligned accesses are supported (LW/SW: addr[1:0] = 0,
// LH/LHU/SH: addr[0] = 0). Misaligned accesses get a trap once Zicsr exists.

module load_store_unit import risc_pkg::*; (
    input  logic [1:0]  addr_lo,        // address bits [1:0]
    input  mem_size_t   size,
    input  logic        zero_extend,    // LBU / LHU

    input  logic [31:0] store_data,     // rs2 after forwarding
    output logic [3:0]  be,             // byte enables
    output logic [31:0] wdata,          // store data in its byte lanes

    input  logic [31:0] rdata,          // whole word from memory
    output logic [31:0] load_data       // value for rd
);

    logic [7:0]  rd_byte;
    logic [15:0] rd_half;

    // store: byte lanes + byte enables (be also tells which bytes a load reads)
    always_comb begin
        case (size)
            BYTE: begin
                be    = 4'b0001 << addr_lo;
                wdata = {4{store_data[7:0]}};
            end
            HALF_WORD: begin
                be    = addr_lo[1] ? 4'b1100 : 4'b0011;
                wdata = {2{store_data[15:0]}};
            end
            default: begin                      // WORD
                be    = 4'b1111;
                wdata = store_data;
            end
        endcase
    end

    // load: select the lane and extend
    assign rd_byte = rdata[8*addr_lo +: 8];
    assign rd_half = addr_lo[1] ? rdata[31:16] : rdata[15:0];

    always_comb begin
        case (size)
            BYTE:      load_data = zero_extend ? {24'b0, rd_byte} : {{24{rd_byte[7]}}, rd_byte};
            HALF_WORD: load_data = zero_extend ? {16'b0, rd_half} : {{16{rd_half[15]}}, rd_half};
            default:   load_data = rdata;       // WORD
        endcase
    end

endmodule
