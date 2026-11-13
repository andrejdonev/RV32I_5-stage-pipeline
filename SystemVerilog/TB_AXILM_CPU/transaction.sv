import uvm_pkg::*;
`include "uvm_macros.svh"

class transaction extends uvm_sequence_item;
  `uvm_object_utils(transaction)

  localparam bit [6:0]
    OPCODE_R_TYPE = 7'h33,
    OPCODE_I_LOAD = 7'h03,
    OPCODE_I_ALU  = 7'h13,
    OPCODE_I_JALR = 7'h67,
    OPCODE_S_TYPE = 7'h23,
    OPCODE_B_TYPE = 7'h63,
    OPCODE_LUI    = 7'h37,
    OPCODE_AUIPC  = 7'h17,
    OPCODE_JAL    = 7'h6F;

  typedef enum {R_TYPE, I_TYPE, S_TYPE, B_TYPE, U_TYPE, J_TYPE, IL_TYPE} instr_type_e;

  rand instr_type_e      instr_type;          
  rand bit [6:0]         opcode;              
  rand bit [2:0]         funct3;
  rand bit [6:0]         funct7;
  rand bit [4:0]         rd, rs1, rs2;       
  rand bit signed [31:0] imm;
       bit [31:0]        instruction;         
       bit               last;                // poslednja instrukcija programa -> driver pokrece program


  constraint c_type {
    instr_type dist {R_TYPE := 10, I_TYPE := 15, S_TYPE := 3, B_TYPE := 6,
                     U_TYPE := 2,  J_TYPE := 1,  IL_TYPE := 1};
    solve instr_type before opcode, funct3, funct7;
    solve opcode, funct3, funct7 before imm;
  }

    

  constraint c_op {
    if (instr_type == R_TYPE) {
      opcode == OPCODE_R_TYPE;
      funct7 inside {7'h00, 7'h20};
      funct7 == 7'h20 -> funct3 inside {0, 5};                   
    }
    if (instr_type == I_TYPE) {
      opcode inside {OPCODE_I_LOAD, OPCODE_I_ALU, OPCODE_I_JALR};
      opcode == OPCODE_I_LOAD -> funct3 inside {0, 1, 2, 4, 5};
      opcode == OPCODE_I_JALR -> funct3 == 0;
      if (opcode == OPCODE_I_ALU && funct3 inside {1, 5}) {      
        funct7 inside {7'h00, 7'h20};
        funct3 == 1 -> funct7 == 7'h00;
      } else funct7 == 0;
    }
    if (instr_type == S_TYPE)  { opcode == OPCODE_S_TYPE; funct3 inside {0, 1, 2};      funct7 == 0; }
    if (instr_type == B_TYPE)  { opcode == OPCODE_B_TYPE; funct3 inside {0, 1, [4:7]};  funct7 == 0; }
    if (instr_type == U_TYPE)  { opcode inside {OPCODE_LUI, OPCODE_AUIPC}; funct3 == 0; funct7 == 0; }
    if (instr_type == J_TYPE)  { opcode == OPCODE_JAL;                     funct3 == 0; funct7 == 0; }
    if (instr_type == IL_TYPE) { opcode == 0;                              funct3 == 0; funct7 == 0; }
  }

  constraint c_operands {
    instr_type inside {U_TYPE, J_TYPE, IL_TYPE}         -> rs1 == 0;
    instr_type inside {I_TYPE, U_TYPE, J_TYPE, IL_TYPE} -> rs2 == 0;
    instr_type inside {S_TYPE, B_TYPE, IL_TYPE}         -> rd  == 0;

    instr_type inside {R_TYPE, IL_TYPE} -> imm == 0;
    instr_type inside {I_TYPE, S_TYPE}  -> imm inside {[-2048:2047]};
    instr_type == B_TYPE -> {imm inside {[-4096:4095]};       imm[1:0] == 0;}  
    instr_type == J_TYPE -> {imm inside {[-1048576:1048575]}; imm[1:0] == 0;}
    instr_type == U_TYPE -> imm[11:0] == 0;
    (opcode == OPCODE_I_ALU && funct3 inside {1, 5}) -> imm[11:5] == funct7;  
  }

  function void post_randomize();
    case (instr_type)
      R_TYPE:  instruction = {funct7, rs2, rs1, funct3, rd, opcode};
      I_TYPE:  instruction = {imm[11:0], rs1, funct3, rd, opcode};
      S_TYPE:  instruction = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
      B_TYPE:  instruction = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
      U_TYPE:  instruction = {imm[31:12], rd, opcode};
      J_TYPE:  instruction = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
      default: instruction = 32'h0000_0000;         
    endcase
  endfunction

  function new(string name = "transaction"); 
    super.new(name); 
  endfunction

endclass