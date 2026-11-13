// AXI4-Lite test for axi_reg_file + soc_top.
// An AXI4-Lite master (tasks axi_write / axi_read) drives your slave, the
// slave drives the soc_top host port. Every check prints PASS or FAIL.
//
// ModelSim (from the SystemVerilog folder):
//   vlog risc_pkg.sv alu.sv branch_control.sv control.sv decode.sv fetch.sv register_file.sv \
//        forwarding_unit.sv hazard_unit.sv if_pipe.sv id_pipe.sv ex_pipe.sv mem_pipe.sv \
//        load_store_unit.sv core.sv dual_port_ram.sv ctrl_regs.sv soc_top.sv \
//        axi_reg_file.sv tb_axil.sv
//   vsim -voptargs=+acc -onfinish stop work.tb_axil
//   run -all

`timescale 1ns/1ps

module tb_axil;

    import risc_pkg::*;

    localparam logic [1:0] OKAY = 2'b00, SLVERR = 2'b10;

    logic clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    // AXI4-Lite master side
    logic        AWVALID = 0, WVALID = 0, BREADY = 1, ARVALID = 0, RREADY = 1;
    logic [31:0] AWADDR = 0, WDATA = 0, ARADDR = 0;
    logic [3:0]  WSTRB = 0;
    logic        AWREADY, WREADY, BVALID, ARREADY, RVALID;
    logic [1:0]  BRESP, RRESP;
    logic [31:0] RDATA;

    // host port between the slave and soc_top
    logic        host_req, host_we, host_rsp_valid, host_rsp_err;
    logic [31:0] host_addr, host_wdata, host_rdata;
    logic [3:0]  host_be;

    axi_reg_file u_axil (
        .ACLK (clk), .ARESETn (rst_n),
        .AWVALID, .AWREADY, .AWADDR,
        .WVALID, .WREADY, .WDATA, .WSTRB,
        .BVALID, .BREADY, .BRESP,
        .ARVALID, .ARREADY, .ARADDR,
        .RVALID, .RREADY, .RDATA, .RRESP,
        .host_req, .host_we, .host_addr, .host_be, .host_wdata,
        .host_rsp_valid, .host_rdata, .host_rsp_err
    );

    soc_top dut (
        .clk, .rst_n,
        .host_req, .host_we, .host_addr, .host_be, .host_wdata,
        .host_rsp_valid, .host_rdata, .host_rsp_err
    );

    //-------------------------------------------------------------------------
    // bookkeeping
    //-------------------------------------------------------------------------

    int n_pass = 0, n_fail = 0;
    int n_host_rd = 0, n_host_wr = 0;      // requests seen on the host port

    always @(negedge clk)
        if (rst_n && host_req === 1'b1) begin
            if (host_we) n_host_wr++;
            else         n_host_rd++;
        end

    task automatic check(input string what, input logic [31:0] got, input logic [31:0] expected);
        if (got === expected) begin
            n_pass++;
            $display("  PASS  %-46s = %h", what, got);
        end else begin
            n_fail++;
            $display("  FAIL  %-46s = %h, expected %h", what, got, expected);
        end
    endtask

    //-------------------------------------------------------------------------
    // AXI4-Lite master tasks (signals change at negedge, sampled at posedge)
    //-------------------------------------------------------------------------

    task automatic axi_write(input logic [31:0] addr, input logic [31:0] data, input logic [3:0] strb,
                             output logic [1:0] resp, output logic ok);
        logic aw_done = 0, w_done = 0;
        int   t = 0;
        @(negedge clk);
        AWVALID = 1; AWADDR = addr;
        WVALID  = 1; WDATA  = data; WSTRB = strb;
        while (!(aw_done && w_done) && t < 50) begin
            @(posedge clk); t++;
            if (AWVALID && AWREADY) aw_done = 1;
            if (WVALID  && WREADY)  w_done  = 1;
            @(negedge clk);
            if (aw_done) AWVALID = 0;
            if (w_done)  WVALID  = 0;
        end
        t = 0;
        do begin @(posedge clk); t++; end while (!(BVALID && BREADY) && t < 50);
        ok   = BVALID && BREADY && aw_done && w_done;
        resp = BRESP;
        if (!ok) $display("  ....  write %h: no AW/W handshake or no BVALID within 50 cycles", addr);
    endtask

    task automatic axi_read(input logic [31:0] addr, output logic [31:0] data, output logic [1:0] resp,
                            output logic ok);
        int t = 0;
        @(negedge clk);
        ARVALID = 1; ARADDR = addr;
        do begin @(posedge clk); t++; end while (!(ARVALID && ARREADY) && t < 50);
        ok = ARREADY;
        @(negedge clk);
        ARVALID = 0;
        t = 0;
        do begin @(posedge clk); t++; end while (!(RVALID && RREADY) && t < 50);
        ok   = ok && RVALID && RREADY;
        data = RDATA;
        resp = RRESP;
        if (!ok) $display("  ....  read %h: no AR handshake or no RVALID within 50 cycles", addr);
    endtask

    //-------------------------------------------------------------------------
    // tests
    //-------------------------------------------------------------------------

    logic [1:0]  r, r2;
    logic [31:0] d;
    logic        ok, ok2;

    initial begin                                   // watchdog: the bus hangs
        #50000;
        $display("  FAIL  watchdog: AWREADY=%b WREADY=%b BVALID=%b ARREADY=%b RVALID=%b",
                 AWREADY, WREADY, BVALID, ARREADY, RVALID);
        $display("\n%0d PASS, %0d FAIL (stopped by the watchdog)", n_pass, n_fail + 1);
        $finish;
    end

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;

        $display("\n1) write DMEM[0x10] = DEADBEEF");
        n_host_rd = 0; n_host_wr = 0;
        axi_write(DMEM_BASE + 32'h10, 32'hDEAD_BEEF, 4'hF, r, ok);
        repeat (3) @(posedge clk);
        check("B handshake", ok, 1);
        check("BRESP", r, OKAY);
        check("write requests on the host port", n_host_wr, 1);
        check("read requests on the host port", n_host_rd, 0);
        check("DMEM word 4 (inside soc_top)", dut.u_dmem.mem[4], 32'hDEAD_BEEF);

        $display("\n2) read DMEM[0x10]");
        axi_read(DMEM_BASE + 32'h10, d, r, ok);
        check("R handshake", ok, 1);
        check("RDATA", d, 32'hDEAD_BEEF);
        check("RRESP", r, OKAY);

        $display("\n3) write only byte 1 (WSTRB = 0010), read back");
        axi_write(DMEM_BASE + 32'h10, 32'h0000_AA00, 4'b0010, r, ok);
        axi_read (DMEM_BASE + 32'h10, d, r2, ok2);
        check("B and R handshakes", ok && ok2, 1);
        check("RDATA", d, 32'hDEAD_AAEF);

        $display("\n4) address outside the map (0x0003_0000)");
        axi_write(32'h0003_0000, 32'h1, 4'hF, r, ok);
        check("BRESP", r, SLVERR);
        axi_read(32'h0003_0000, d, r, ok);
        check("RRESP", r, SLVERR);
        axi_read(DMEM_BASE + 32'h10, d, r, ok);           // the error must not leak into the next read
        check("RRESP of the next, valid read", r, OKAY);

        $display("\n5) write and read started in the same cycle");
        fork
            axi_write(DMEM_BASE + 32'h20, 32'h1234_5678, 4'hF, r, ok);
            axi_read (DMEM_BASE + 32'h10, d, r2, ok2);
        join
        repeat (3) @(posedge clk);
        check("B and R handshakes", ok && ok2, 1);
        check("BRESP", r, OKAY);
        check("RDATA", d, 32'hDEAD_AAEF);
        check("DMEM word 8", dut.u_dmem.mem[8], 32'h1234_5678);

        $display("\n6) slow master: RREADY low for 6 cycles");
        RREADY = 0;
        @(negedge clk); ARVALID = 1; ARADDR = DMEM_BASE + 32'h20;
        do @(posedge clk); while (!ARREADY);
        @(negedge clk); ARVALID = 0;
        repeat (6) @(posedge clk);
        @(negedge clk); RREADY = 1;
        begin : wait_rvalid
            int t;
            t = 0;
            do begin @(posedge clk); t++; end while (!RVALID && t < 50);
        end
        check("RVALID still 1 when RREADY comes", RVALID, 1);
        check("RDATA", RDATA, 32'h1234_5678);

        $display("\n7) slow master: BREADY low for 6 cycles");
        BREADY = 0;
        fork
            axi_write(DMEM_BASE + 32'h24, 32'hCAFE_F00D, 4'hF, r, ok);
            begin repeat (12) @(posedge clk); @(negedge clk); BREADY = 1; end
        join
        check("B handshake after BREADY", ok, 1);
        check("BRESP", r, OKAY);

        $display("\n%0d PASS, %0d FAIL", n_pass, n_fail);
        $finish;
    end

endmodule
