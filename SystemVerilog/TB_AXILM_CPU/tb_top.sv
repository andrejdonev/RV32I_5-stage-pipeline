// Top testbench-a: takt, reset, AXI interfejs, procesor i pokretanje UVM testa.
module tb_top;
  import uvm_pkg::*;
  import tb_pkg::*;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;                          // 10 ns
  initial #20 rst_n = 1;

  axil_if intf (clk, rst_n);

  soc_axil_top dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .s_axil_awaddr  (intf.awaddr),
    .s_axil_awvalid (intf.awvalid),
    .s_axil_awready (intf.awready),
    .s_axil_wdata   (intf.wdata),
    .s_axil_wstrb   (intf.wstrb),
    .s_axil_wvalid  (intf.wvalid),
    .s_axil_wready  (intf.wready),
    .s_axil_bresp   (intf.bresp),
    .s_axil_bvalid  (intf.bvalid),
    .s_axil_bready  (intf.bready),
    .s_axil_araddr  (intf.araddr),
    .s_axil_arvalid (intf.arvalid),
    .s_axil_arready (intf.arready),
    .s_axil_rdata   (intf.rdata),
    .s_axil_rresp   (intf.rresp),
    .s_axil_rvalid  (intf.rvalid),
    .s_axil_rready  (intf.rready)
  );

  initial begin
    uvm_config_db #(virtual axil_if)::set(null, "*", "vif", intf);
    run_test("test");
  end
endmodule
