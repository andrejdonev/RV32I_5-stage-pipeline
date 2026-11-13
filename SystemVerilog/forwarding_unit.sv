// Forwarding unit - gives the instruction in EX the newest value of rs1/rs2.
//
//   EX/MEM -> EX : producer is one instruction ahead (now in MEM)
//   MEM/WB -> EX : producer is two instructions ahead (now in WB)
//
// The younger producer (MEM) wins when both match. x0 is never forwarded.
// A load in MEM is never forwarded from here (mem_result is its address):
// the hazard unit stalls the dependent instruction one cycle, so it gets the
// load data from MEM/WB instead.

module forwarding_unit (
    // instruction in EX (id_pipe outputs)
    input  logic [4:0]  ex_rs1_addr,
    input  logic [4:0]  ex_rs2_addr,
    input  logic [31:0] ex_rs1_data,       // value read in ID
    input  logic [31:0] ex_rs2_data,

    // instruction in MEM (ex_pipe outputs)
    input  logic        mem_valid,
    input  logic        mem_rf_wr_en,
    input  logic [4:0]  mem_rd_addr,
    input  logic [31:0] mem_result,

    // instruction in WB (mem_pipe outputs)
    input  logic        wb_valid,
    input  logic        wb_rf_wr_en,
    input  logic [4:0]  wb_rd_addr,
    input  logic [31:0] wb_data,

    output logic [31:0] rs1_fwd,
    output logic [31:0] rs2_fwd
);

    logic mem_writes_rd, wb_writes_rd;

    assign mem_writes_rd = mem_valid && mem_rf_wr_en && (mem_rd_addr != 5'd0);
    assign wb_writes_rd  = wb_valid  && wb_rf_wr_en  && (wb_rd_addr  != 5'd0);

    always_comb begin
        if      (mem_writes_rd && (mem_rd_addr == ex_rs1_addr)) rs1_fwd = mem_result;
        else if (wb_writes_rd  && (wb_rd_addr  == ex_rs1_addr)) rs1_fwd = wb_data;
        else                                                    rs1_fwd = ex_rs1_data;

        if      (mem_writes_rd && (mem_rd_addr == ex_rs2_addr)) rs2_fwd = mem_result;
        else if (wb_writes_rd  && (wb_rd_addr  == ex_rs2_addr)) rs2_fwd = wb_data;
        else                                                    rs2_fwd = ex_rs2_data;
    end

endmodule
