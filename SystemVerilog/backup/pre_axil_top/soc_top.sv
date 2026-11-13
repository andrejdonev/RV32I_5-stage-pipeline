// SoC wrapper: core + IMEM + DMEM + CTRL/STATUS + host port.
//
//              host port                 port B
//   (AXI4-Lite slave) --> host decoder --+------> IMEM 16 KB <-- port A -- core IF
//                                        +------> DMEM 16 KB <-- port A -+ core MEM
//                                        +------> CTRL/STATUS <----------+ (TOHOST)
//                                                     | core_rst_n (CTRL.run)
//                                                     v
//                                                   core
//
// Address map (risc_pkg):
//   IMEM_BASE 0x0000_0000  16 KB   core: fetch       host: R/W
//   DMEM_BASE 0x0001_0000  16 KB   core: load/store  host: R/W
//   CTRL_BASE 0x0002_0000  256 B   core: R/W TOHOST  host: R/W  (ctrl_regs.sv)
//   other                          host: host_rsp_err (-> AXI SLVERR)
// The core's data port only separates the CTRL window; every other address
// goes to DMEM (mirrored). Accesses outside the map will trap once Zicsr exists.
//
// Host port - one request per cycle, response exactly one cycle later:
//   cycle N  : host_req = 1, host_we, host_addr, host_be (byte enables), host_wdata
//   cycle N+1: host_rsp_valid = 1, host_rdata (reads), host_rsp_err (unmapped address)
// AXI4-Lite slave on top of it:
//   write: AW and W both received -> host_req/host_we = 1, host_be = WSTRB
//          host_rsp_valid -> BVALID, BRESP = host_rsp_err ? SLVERR : OKAY
//   read:  AR received -> host_req = 1, host_we = 0
//          host_rsp_valid -> RVALID, RDATA = host_rdata, RRESP as above
//   (keep B/R valid until BREADY/RREADY; host_rdata is only valid in cycle N+1)
// Load a program only while the core is stopped (CTRL.run = 0).

import risc_pkg::*;

module soc_top #(
    parameter logic [31:0] RESET_PC        = IMEM_BASE,
    parameter              IMEM_ADDR_WIDTH = 14,        // 16 KB
    parameter              DMEM_ADDR_WIDTH = 14,        // 16 KB
    parameter              IMEM_INIT       = ""         // optional preload, 1 word per line
) (
    input  logic        clk,
    input  logic        rst_n,

    // host port
    input  logic        host_req,
    input  logic        host_we,
    input  logic [31:0] host_addr,
    input  logic [3:0]  host_be,
    input  logic [31:0] host_wdata,
    output logic        host_rsp_valid,
    output logic [31:0] host_rdata,
    output logic        host_rsp_err
);

//=============================================================================
// Core
//=============================================================================

    logic        core_rst_n;

    logic        imem_req;
    logic [31:0] imem_addr, imem_rdata;

    logic        dmem_req, dmem_we;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_be;
    logic        retire;

    core #(
        .RESET_PC   (RESET_PC)
    ) u_core (
        .clk        (clk),
        .rst_n      (core_rst_n),
        .imem_req   (imem_req),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .dmem_req   (dmem_req),
        .dmem_we    (dmem_we),
        .dmem_addr  (dmem_addr),
        .dmem_be    (dmem_be),
        .dmem_wdata (dmem_wdata),
        .dmem_rdata (dmem_rdata),
        .retire     (retire)
    );

//=============================================================================
// Address decoders
//=============================================================================

    // host side: exact windows
    logic h_imem, h_dmem, h_ctrl;

    assign h_imem = host_addr[31:IMEM_ADDR_WIDTH] == IMEM_BASE[31:IMEM_ADDR_WIDTH];
    assign h_dmem = host_addr[31:DMEM_ADDR_WIDTH] == DMEM_BASE[31:DMEM_ADDR_WIDTH];
    assign h_ctrl = host_addr[31:8]               == CTRL_BASE[31:8];

    // core side: CTRL window, everything else -> DMEM
    logic c_ctrl;

    assign c_ctrl = dmem_addr[31:8]               == CTRL_BASE[31:8];

//=============================================================================
// Memories and CTRL/STATUS
//=============================================================================

    logic [31:0] imem_host_rdata, dmem_host_rdata, ctrl_host_rdata;
    logic [31:0] dmem_core_rdata, ctrl_core_rdata;

    dual_port_ram #(
        .ADDR_WIDTH (IMEM_ADDR_WIDTH),
        .INIT_FILE  (IMEM_INIT)
    ) u_imem (
        .clk     (clk),
        .a_req   (imem_req),
        .a_we    (1'b0),                    // the core never writes IMEM
        .a_addr  (imem_addr),
        .a_be    (4'b0),
        .a_wdata (32'b0),
        .a_rdata (imem_rdata),
        .b_req   (host_req && h_imem),
        .b_we    (host_we),
        .b_addr  (host_addr),
        .b_be    (host_be),
        .b_wdata (host_wdata),
        .b_rdata (imem_host_rdata)
    );

    dual_port_ram #(
        .ADDR_WIDTH (DMEM_ADDR_WIDTH)
    ) u_dmem (
        .clk     (clk),
        .a_req   (dmem_req && !c_ctrl),
        .a_we    (dmem_we),
        .a_addr  (dmem_addr),
        .a_be    (dmem_be),
        .a_wdata (dmem_wdata),
        .a_rdata (dmem_core_rdata),
        .b_req   (host_req && h_dmem),
        .b_we    (host_we),
        .b_addr  (host_addr),
        .b_be    (host_be),
        .b_wdata (host_wdata),
        .b_rdata (dmem_host_rdata)
    );

    ctrl_regs #(
        .RESET_PC   (RESET_PC)
    ) u_ctrl (
        .clk        (clk),
        .rst_n      (rst_n),
        .h_req      (host_req && h_ctrl),
        .h_we       (host_we),
        .h_addr     (host_addr[7:0]),
        .h_wdata    (host_wdata),
        .h_rdata    (ctrl_host_rdata),
        .c_req      (dmem_req && c_ctrl),
        .c_we       (dmem_we),
        .c_addr     (dmem_addr[7:0]),
        .c_wdata    (dmem_wdata),
        .c_rdata    (ctrl_core_rdata),
        .c_retire   (retire),
        .core_rst_n (core_rst_n)
    );

    assign dmem_rdata = c_ctrl ? ctrl_core_rdata : dmem_core_rdata;

//=============================================================================
// Host response (one cycle after the request)
//=============================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            host_rsp_valid <= 1'b0;
            host_rsp_err   <= 1'b0;
        end else begin
            host_rsp_valid <= host_req;
            host_rsp_err   <= host_req && !(h_imem || h_dmem || h_ctrl);
            if (host_req) begin
                if      (h_imem) host_rdata <= imem_host_rdata;
                else if (h_dmem) host_rdata <= dmem_host_rdata;
                else if (h_ctrl) host_rdata <= ctrl_host_rdata;
                else             host_rdata <= 32'b0;
            end
        end
    end


endmodule
