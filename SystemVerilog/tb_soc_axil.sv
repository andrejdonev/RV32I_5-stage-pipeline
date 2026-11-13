// Testbench for soc_axil_top: everything goes through AXI4-Lite, the way
// cocotb / pyuvm (and later a PC over UART) will drive the chip.
//
//   1. core held in reset (CTRL.run = 0), program written to IMEM over AXI
//   2. CTRL.run = 1
//   3. poll STATUS over AXI until done (the program wrote TOHOST)
//   4. read TOHOST, CYCLE, INSTRET and the first words of DMEM over AXI
//
// Plusargs: +prog=<file> (default program.hex, one 32-bit word per line)
//           +dump=<n>    DMEM words to print (default 8)
// The program must end by writing TOHOST:
//     lui  x31, 0x20 / addi x30, x0, 1 / sw x30, 12(x31) / j .

`timescale 1ns/1ps

module tb_soc_axil;

    import risc_pkg::*;

    localparam logic [1:0] OKAY = 2'b00, SLVERR = 2'b10;

    logic clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    logic        awvalid = 0, wvalid = 0, bready = 1, arvalid = 0, rready = 1;
    logic [31:0] awaddr = 0, wdata = 0, araddr = 0;
    logic [3:0]  wstrb = 0;
    logic        awready, wready, bvalid, arready, rvalid;
    logic [1:0]  bresp, rresp;
    logic [31:0] rdata;

    soc_axil_top dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axil_awaddr  (awaddr),
        .s_axil_awvalid (awvalid),
        .s_axil_awready (awready),
        .s_axil_wdata   (wdata),
        .s_axil_wstrb   (wstrb),
        .s_axil_wvalid  (wvalid),
        .s_axil_wready  (wready),
        .s_axil_bresp   (bresp),
        .s_axil_bvalid  (bvalid),
        .s_axil_bready  (bready),
        .s_axil_araddr  (araddr),
        .s_axil_arvalid (arvalid),
        .s_axil_arready (arready),
        .s_axil_rdata   (rdata),
        .s_axil_rresp   (rresp),
        .s_axil_rvalid  (rvalid),
        .s_axil_rready  (rready)
    );

    //-------------------------------------------------------------------------
    // AXI4-Lite master (signals change at negedge, sampled at posedge)
    //-------------------------------------------------------------------------

    task automatic axi_write(input logic [31:0] addr, input logic [31:0] data, output logic [1:0] resp);
        logic aw_done = 0, w_done = 0;
        int   t = 0;
        @(negedge clk);
        awvalid = 1; awaddr = addr;
        wvalid  = 1; wdata  = data; wstrb = 4'hF;
        while (!(aw_done && w_done)) begin
            @(posedge clk);
            if (awvalid && awready) aw_done = 1;
            if (wvalid  && wready)  w_done  = 1;
            @(negedge clk);
            if (aw_done) awvalid = 0;
            if (w_done)  wvalid  = 0;
            t++; if (t > 100) $fatal(1, "AXI write %08x: no AW/W handshake", addr);
        end
        t = 0;
        do begin
            @(posedge clk);
            t++; if (t > 100) $fatal(1, "AXI write %08x: no BVALID", addr);
        end while (!(bvalid && bready));
        resp = bresp;
    endtask

    task automatic axi_read(input logic [31:0] addr, output logic [31:0] data, output logic [1:0] resp);
        int t = 0;
        @(negedge clk);
        arvalid = 1; araddr = addr;
        do begin
            @(posedge clk);
            t++; if (t > 100) $fatal(1, "AXI read %08x: no AR handshake", addr);
        end while (!(arvalid && arready));
        @(negedge clk);
        arvalid = 0;
        t = 0;
        do begin
            @(posedge clk);
            t++; if (t > 100) $fatal(1, "AXI read %08x: no RVALID", addr);
        end while (!(rvalid && rready));
        data = rdata;
        resp = rresp;
    endtask

    task automatic axi_write_ok(input logic [31:0] addr, input logic [31:0] data);
        logic [1:0] resp;
        axi_write(addr, data, resp);
        if (resp != OKAY) $error("AXI write %08x: BRESP = %b", addr, resp);
    endtask

    task automatic axi_read_ok(input logic [31:0] addr, output logic [31:0] data);
        logic [1:0] resp;
        axi_read(addr, data, resp);
        if (resp != OKAY) $error("AXI read %08x: RRESP = %b", addr, resp);
    endtask

    //-------------------------------------------------------------------------
    // test
    //-------------------------------------------------------------------------

    logic [31:0] image [0:4095];
    string       prog_file;
    int          nwords, ndump, polls;
    logic [31:0] data, status, tohost, cyc, inst;
    logic [1:0]  resp;

    initial begin
        if (!$value$plusargs("prog=%s", prog_file)) prog_file = "program.hex";
        if (!$value$plusargs("dump=%d", ndump))     ndump = 8;

        // program length = last non-zero word (a warning that the file has
        // fewer words than the array is expected)
        for (int i = 0; i < 4096; i++) image[i] = 32'b0;
        $readmemh(prog_file, image);
        nwords = 0;
        for (int i = 0; i < 4096; i++) if (image[i] != 32'b0) nwords = i + 1;

        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;

        // 1. program -> IMEM, then read it back
        for (int i = 0; i < nwords; i++) axi_write_ok(IMEM_BASE + 4*i, image[i]);
        for (int i = 0; i < nwords; i++) begin
            axi_read_ok(IMEM_BASE + 4*i, data);
            if (data !== image[i]) $error("IMEM[%0d] = %08x, expected %08x", i, data, image[i]);
        end
        $display("loaded %0d words from %s over AXI4-Lite", nwords, prog_file);

        // an address outside the map must answer with SLVERR
        axi_read(32'h0003_0000, data, resp);
        if (resp != SLVERR) $error("read outside the map: RRESP = %b, expected SLVERR", resp);
        axi_write(32'h0003_0000, 32'h0, resp);
        if (resp != SLVERR) $error("write outside the map: BRESP = %b, expected SLVERR", resp);

        // 2. run
        axi_write_ok(CTRL_BASE + REG_CTRL, 32'h1);

        // 3. wait for done
        polls = 0;
        do begin
            repeat (10) @(posedge clk);
            axi_read_ok(CTRL_BASE + REG_STATUS, status);
            polls++;
        end while (!status[1] && polls < 10000);

        // 4. results
        axi_read_ok(CTRL_BASE + REG_TOHOST,     tohost);
        axi_read_ok(CTRL_BASE + REG_CYCLE_LO,   cyc);
        axi_read_ok(CTRL_BASE + REG_INSTRET_LO, inst);
        axi_write_ok(CTRL_BASE + REG_CTRL, 32'h0);            // stop the core

        if (!status[1]) $display("TIMEOUT: STATUS = %08x", status);
        else            $display("done: TOHOST = %0d, CYCLE = %0d, INSTRET = %0d, CPI = %0.3f",
                                 tohost, cyc, inst, real'(cyc) / real'(inst));
        for (int i = 0; i < ndump; i++) begin
            axi_read_ok(DMEM_BASE + 4*i, data);
            $display("DMEM[0x%0x] = %0d (0x%08x)", 4*i, $signed(data), data);
        end
        $finish;
    end

endmodule
