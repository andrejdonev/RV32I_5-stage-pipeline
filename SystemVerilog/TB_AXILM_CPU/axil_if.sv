interface axil_if (input logic clk, input logic rst_n);

  // write address
  logic [31:0] awaddr;
  logic        awvalid, awready;
  // write data
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid, wready;
  // write response
  logic [1:0]  bresp;
  logic        bvalid, bready;
  // read address
  logic [31:0] araddr;
  logic        arvalid, arready;
  // read data
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid, rready;

endinterface