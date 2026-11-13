// CTRL/STATUS registers (PROJEKAT_RV32_AI.md, 2.4). Offsets from CTRL_BASE:
//
//   0x00 CTRL        R/W  bit0 run: 1 = core runs, 0 = core held in reset.
//                         0 -> 1 clears done, TOHOST and the counters.
//                         bit1 halt, bit2 soft_reset: reserved (not implemented)
//   0x04 STATUS      R    bit0 running, bit1 done, bit2 trap (0 until traps exist)
//   0x08 RESET_PC    R    start address (the RESET_PC parameter for now)
//   0x0C TOHOST      R/W  the core writes it; a value != 0 sets STATUS.done
//   0x10 FROMHOST    R/W  host -> core
//   0x20/0x24 CYCLE_LO/HI      cycles from run until done
//   0x28/0x2C INSTRET_LO/HI    retired instructions from run until done
//                              (the store to TOHOST itself is not counted)
//
// Host side: only full-word writes; read data in the cycle after the request.
// Core side: the core may only write TOHOST; reads are combinational.
// After done the core keeps running (programs end with "j ."), the host stops
// it by writing CTRL.run = 0.

module ctrl_regs import risc_pkg::*; #(
    parameter logic [31:0] RESET_PC = 32'h0000_0000
) (
    input  logic        clk,
    input  logic        rst_n,

    // host side
    input  logic        h_req,
    input  logic        h_we,
    input  logic [7:0]  h_addr,
    input  logic [31:0] h_wdata,
    output logic [31:0] h_rdata,

    // core side (MEM stage)
    input  logic        c_req,
    input  logic        c_we,
    input  logic [7:0]  c_addr,
    input  logic [31:0] c_wdata,
    output logic [31:0] c_rdata,
    input  logic        c_retire,

    output logic        core_rst_n
);

    logic        run_q, done_q;
    logic [31:0] tohost_q, fromhost_q;
    logic [63:0] cycle_q, instret_q;
    logic        start;

    assign start = h_req && h_we && (h_addr == REG_CTRL) && h_wdata[0] && !run_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            run_q      <= 1'b0;
            done_q     <= 1'b0;
            tohost_q   <= 32'b0;
            fromhost_q <= 32'b0;
            cycle_q    <= 64'b0;
            instret_q  <= 64'b0;
        end else begin
            // host writes
            if (h_req && h_we) begin
                case (h_addr)
                    REG_CTRL:     run_q      <= h_wdata[0];
                    REG_TOHOST:   tohost_q   <= h_wdata;
                    REG_FROMHOST: fromhost_q <= h_wdata;
                    default: ;
                endcase
            end

            if (start) begin                        // new run
                done_q    <= 1'b0;
                tohost_q  <= 32'b0;
                cycle_q   <= 64'b0;
                instret_q <= 64'b0;
            end else if (run_q && !done_q) begin
                cycle_q <= cycle_q + 64'd1;
                if (c_retire) instret_q <= instret_q + 64'd1;
                if (c_req && c_we && (c_addr == REG_TOHOST)) begin
                    tohost_q <= c_wdata;
                    if (c_wdata != 32'b0) done_q <= 1'b1;
                end
            end
        end
    end

    // the core is held in reset until the host sets CTRL.run
    assign core_rst_n = rst_n && run_q;

    // read mux, shared by both sides
    function automatic logic [31:0] read_reg(input logic [7:0] addr);
        case (addr)
            REG_CTRL:       return {31'b0, run_q};
            REG_STATUS:     return {29'b0, 1'b0, done_q, run_q && !done_q};
            REG_RESET_PC:   return RESET_PC;
            REG_TOHOST:     return tohost_q;
            REG_FROMHOST:   return fromhost_q;
            REG_CYCLE_LO:   return cycle_q[31:0];
            REG_CYCLE_HI:   return cycle_q[63:32];
            REG_INSTRET_LO: return instret_q[31:0];
            REG_INSTRET_HI: return instret_q[63:32];
            default:        return 32'b0;
        endcase
    endfunction

    assign c_rdata = read_reg(c_addr);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)              h_rdata <= 32'b0;
        else if (h_req && !h_we) h_rdata <= read_reg(h_addr);
    end

endmodule
