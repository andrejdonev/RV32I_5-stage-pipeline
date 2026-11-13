

module axi_reg_file #(
  parameter int unsigned ADDR_W = 32,
  parameter int unsigned DATA_W = 32
) (
  input  logic                 ACLK,
  input  logic                 ARESETn,

  // Write address channel
  input  logic                 AWVALID,
  output logic                 AWREADY,
  input  logic [ADDR_W-1:0]    AWADDR,

  // Write data channel
  input  logic                 WVALID,
  output logic                 WREADY,
  input  logic [DATA_W-1:0]    WDATA,
  input  logic [DATA_W/8-1:0]  WSTRB,

  // Write response channel
  output logic                 BVALID,
  input  logic                 BREADY,
  output logic [1:0]           BRESP,

  // Read address channel
  input  logic                 ARVALID,
  output logic                 ARREADY,
  input  logic [ADDR_W-1:0]    ARADDR,

  // Read data channel
  output logic                 RVALID,
  input  logic                 RREADY,
  output logic [DATA_W-1:0]    RDATA,
  output logic [1:0]           RRESP,

  //Core side interface
  output logic                 host_req,
  output logic                 host_we,
  output logic [ADDR_W-1:0]    host_addr,
  output logic [DATA_W/8-1:0]  host_be,
  output logic [DATA_W-1:0]    host_wdata,

  input  logic                 host_rsp_valid,
  input  logic [DATA_W-1:0]    host_rdata,
  input  logic                 host_rsp_err
);

  //WRITE PROCESS
  logic aw_seen, w_seen, w_done;
  assign AWREADY = !aw_seen;
  assign WREADY = !w_seen;

  logic [ADDR_W-1:0] awaddr_q;
  logic [DATA_W-1:0] wdata_q;
  logic [DATA_W/8-1:0] wstrb_q;

  //aw handshake
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if(!ARESETn) begin aw_seen <= 0; awaddr_q <= '0; end
    else begin 
      if(AWREADY && AWVALID && !aw_seen) begin aw_seen <= 1; awaddr_q <= AWADDR; end
      else if(BVALID && BREADY) begin aw_seen <= 0; end
    end
  end

  //w handshake
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if(!ARESETn) begin w_seen <= 0; wdata_q <= '0; wstrb_q <= '0; end
    else begin 
      if(WREADY && WVALID && !w_seen) begin w_seen <= 1; wdata_q <= WDATA; wstrb_q <= WSTRB; end
      else if(BVALID && BREADY) begin w_seen <= 0; end
    end
  end

  //b handshake
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if(!ARESETn) begin BVALID <= 0; BRESP <= 0; end
    else begin 
      if(w_done && !BVALID && host_rsp_valid) begin 
        BVALID <= 1;
        if(host_rsp_err) begin BRESP <= 2'b10; end
        else begin BRESP <= 2'b00; end 
      end
      else if(BVALID && BREADY) begin BVALID <= 0; end
    end
  end

  //write data 
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if(!ARESETn) begin host_wdata <= '0; host_we <= 0; host_be <= '0; w_done <= 0; end
    else begin 
      if(aw_seen && w_seen && !BVALID && !w_done && !ar_seen) begin
        host_wdata <= wdata_q;
        host_we <= 1;
        host_be <= wstrb_q;
        w_done <= 1;
      end else if(BVALID && BREADY) begin
        w_done <= 0;
      end else begin
        host_we <= 0;
      end
    end
  end

  //READ PROCESS
  logic ar_seen;
  assign ARREADY = !RVALID && !ar_seen && !(aw_seen && w_seen);

  //r handshake
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if(!ARESETn) begin ar_seen <= 0; end
    else begin 
      if(ARREADY && ARVALID && !RVALID) begin ar_seen <= 1; end
      else if(RVALID && RREADY) begin ar_seen <= 0; end
    end
  end

  //Mem read
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if(!ARESETn) begin RDATA <= '0; RRESP <= '0; RVALID <= 0; end
    else begin 
      if(ar_seen && !RVALID && host_rsp_valid) begin 
        RDATA <= host_rdata;
        RVALID <= 1;
        if(host_rsp_err) begin RRESP <= 2'b10; end
        else begin RRESP <= 2'b00; end
      end else if(RVALID && RREADY) begin
        RVALID <= 0;
      end
    end
  end

  //host addr an rsp
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if(!ARESETn) begin host_addr <= '0; host_req <= 0; end
    else begin 
      if(aw_seen && w_seen && !BVALID && !w_done && !ar_seen) begin
        host_addr <= awaddr_q;
        host_req <= 1;
      end else if (ARREADY && ARVALID && !RVALID) begin
        host_addr <= ARADDR;
        host_req <= 1;
      end else begin
        host_req <= 0;
      end
    end
  end

endmodule