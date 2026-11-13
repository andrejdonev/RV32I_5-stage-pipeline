// Top level for verification: AXI4-Lite slave (axil_slave.sv) + soc_top.
//
//   AXI4-Lite master (cocotb / pyuvm, SV testbench, later UART bridge)
//        |  s_axil_*
//        v
//   axi_reg_file  --host port-->  soc_top (core + IMEM + DMEM + CTRL/STATUS)
//
// Port names follow the usual "s_axil_<signal>" convention, so a cocotb
// AXI4-Lite driver can find the bus by its prefix ("s_axil").
// Address map, CTRL/STATUS registers and the end of a program (store to
// TOHOST) are the same as for soc_top (see risc_pkg.sv and soc_top.sv).
//
// One transaction at a time on the host port: ARREADY is low while a write is
// in progress, and a write waits until a read in flight has finished.

module soc_axil_top #(
    parameter logic [31:0] RESET_PC        = 32'h0000_0000,
    parameter              IMEM_ADDR_WIDTH = 14,        // 16 KB
    parameter              DMEM_ADDR_WIDTH = 14,        // 16 KB
    parameter              IMEM_INIT       = ""         // optional preload (backdoor), 1 word per line
) (
    input  logic        clk,
    input  logic        rst_n,

    // AXI4-Lite slave: write address
    input  logic [31:0] s_axil_awaddr,
    input  logic        s_axil_awvalid,
    output logic        s_axil_awready,
    // write data
    input  logic [31:0] s_axil_wdata,
    input  logic [3:0]  s_axil_wstrb,
    input  logic        s_axil_wvalid,
    output logic        s_axil_wready,
    // write response
    output logic [1:0]  s_axil_bresp,
    output logic        s_axil_bvalid,
    input  logic        s_axil_bready,
    // read address
    input  logic [31:0] s_axil_araddr,
    input  logic        s_axil_arvalid,
    output logic        s_axil_arready,
    // read data
    output logic [31:0] s_axil_rdata,
    output logic [1:0]  s_axil_rresp,
    output logic        s_axil_rvalid,
    input  logic        s_axil_rready
);

    // host port between the AXI slave and the SoC
    logic        host_req, host_we;
    logic [31:0] host_addr, host_wdata, host_rdata;
    logic [3:0]  host_be;
    logic        host_rsp_valid, host_rsp_err;

    axi_reg_file #(
        .ADDR_W         (32),
        .DATA_W         (32)
    ) u_axil (
        .ACLK           (clk),
        .ARESETn        (rst_n),
        .AWVALID        (s_axil_awvalid),
        .AWREADY        (s_axil_awready),
        .AWADDR         (s_axil_awaddr),
        .WVALID         (s_axil_wvalid),
        .WREADY         (s_axil_wready),
        .WDATA          (s_axil_wdata),
        .WSTRB          (s_axil_wstrb),
        .BVALID         (s_axil_bvalid),
        .BREADY         (s_axil_bready),
        .BRESP          (s_axil_bresp),
        .ARVALID        (s_axil_arvalid),
        .ARREADY        (s_axil_arready),
        .ARADDR         (s_axil_araddr),
        .RVALID         (s_axil_rvalid),
        .RREADY         (s_axil_rready),
        .RDATA          (s_axil_rdata),
        .RRESP          (s_axil_rresp),
        .host_req       (host_req),
        .host_we        (host_we),
        .host_addr      (host_addr),
        .host_be        (host_be),
        .host_wdata     (host_wdata),
        .host_rsp_valid (host_rsp_valid),
        .host_rdata     (host_rdata),
        .host_rsp_err   (host_rsp_err)
    );

    soc_top #(
        .RESET_PC        (RESET_PC),
        .IMEM_ADDR_WIDTH (IMEM_ADDR_WIDTH),
        .DMEM_ADDR_WIDTH (DMEM_ADDR_WIDTH),
        .IMEM_INIT       (IMEM_INIT)
    ) u_soc (
        .clk            (clk),
        .rst_n          (rst_n),
        .host_req       (host_req),
        .host_we        (host_we),
        .host_addr      (host_addr),
        .host_be        (host_be),
        .host_wdata     (host_wdata),
        .host_rsp_valid (host_rsp_valid),
        .host_rdata     (host_rdata),
        .host_rsp_err   (host_rsp_err)
    );

endmodule
