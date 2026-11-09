// Testbench for soc_top: the program is loaded and checked only through the
// host port, the same way the AXI4-Lite slave (and later cocotb or a PC over
// UART) will do it. The host_write / host_read tasks are what an AXI4-Lite
// master BFM will replace.
//
//   1. core held in reset (CTRL.run = 0), program written to IMEM word by word
//   2. CTRL.run = 1
//   3. poll STATUS until done (the program wrote TOHOST)
//   4. read TOHOST, CYCLE, INSTRET and the first words of DMEM
//
// Plusargs: +prog=<file> (default program.hex, one 32-bit word per line)
//           +dump=<n>    DMEM words to print (default 8)
// The program must end by writing TOHOST, e.g.
//     lui  x31, 0x20        # x31 = CTRL_BASE
//     addi x30, x0, 1
//     sw   x30, 12(x31)     # TOHOST = 1 -> STATUS.done
//     j    .                # wait here until the host stops the core

`timescale 1ns/1ps

module tb_soc;

    import risc_pkg::*;

    logic clk   = 1'b0;
    logic rst_n = 1'b0;

    always #5 clk = ~clk;

    logic        host_req   = 1'b0;
    logic        host_we    = 1'b0;
    logic [31:0] host_addr  = '0;
    logic [3:0]  host_be    = '0;
    logic [31:0] host_wdata = '0;
    logic        host_rsp_valid, host_rsp_err;
    logic [31:0] host_rdata;

    soc_top dut (
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

    // one host access: request in one cycle, response in the next
    task automatic host_access(input logic we, input logic [31:0] addr, input logic [31:0] wdata,
                               input logic [3:0] be, output logic [31:0] rdata, output logic err);
        @(negedge clk);
        host_req   = 1'b1;
        host_we    = we;
        host_addr  = addr;
        host_be    = be;
        host_wdata = wdata;
        @(negedge clk);
        host_req   = 1'b0;
        if (!host_rsp_valid) $error("no response from the host port for %08x", addr);
        rdata = host_rdata;
        err   = host_rsp_err;
    endtask

    task automatic host_write(input logic [31:0] addr, input logic [31:0] data);
        logic [31:0] unused;
        logic        err;
        host_access(1'b1, addr, data, 4'hF, unused, err);
        if (err) $error("host write %08x: error response", addr);
    endtask

    task automatic host_read(input logic [31:0] addr, output logic [31:0] data);
        logic err;
        host_access(1'b0, addr, 32'b0, 4'hF, data, err);
        if (err) $error("host read %08x: error response", addr);
    endtask

    logic [31:0] image [0:4095];
    string       prog_file;
    int          nwords, ndump, polls;
    logic [31:0] data, status, tohost, cyc, inst;
    logic        err;

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

        // 1. program -> IMEM
        for (int i = 0; i < nwords; i++) host_write(IMEM_BASE + 4*i, image[i]);
        for (int i = 0; i < nwords; i++) begin
            host_read(IMEM_BASE + 4*i, data);
            if (data !== image[i]) $error("IMEM[%0d] = %08x, expected %08x", i, data, image[i]);
        end
        $display("loaded %0d words from %s through the host port", nwords, prog_file);

        // an address outside the map must answer with an error (-> AXI SLVERR)
        host_access(1'b0, 32'h0003_0000, 32'b0, 4'hF, data, err);
        if (!err) $error("unmapped address answered without error");

        // 2. run
        host_write(CTRL_BASE + REG_CTRL, 32'h1);

        // 3. wait for done
        polls = 0;
        do begin
            repeat (10) @(posedge clk);
            host_read(CTRL_BASE + REG_STATUS, status);
            polls++;
        end while (!status[1] && polls < 10000);

        // 4. results
        host_read(CTRL_BASE + REG_TOHOST,     tohost);
        host_read(CTRL_BASE + REG_CYCLE_LO,   cyc);
        host_read(CTRL_BASE + REG_INSTRET_LO, inst);
        host_write(CTRL_BASE + REG_CTRL, 32'h0);              // stop the core

        if (!status[1]) $display("TIMEOUT: STATUS = %08x", status);
        else            $display("done: TOHOST = %0d, CYCLE = %0d, INSTRET = %0d, CPI = %0.3f",
                                 tohost, cyc, inst, real'(cyc) / real'(inst));
        for (int i = 0; i < ndump; i++) begin
            host_read(DMEM_BASE + 4*i, data);
            $display("DMEM[0x%0x] = %0d (0x%08x)", 4*i, $signed(data), data);
        end
        $finish;
    end

endmodule
