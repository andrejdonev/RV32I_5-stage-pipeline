// ISS (instruction set simulator) - referentni model procesora.
// Izvrsava program redom (nema skokova), samo instrukcije koje TB pravi:
// LUI, AUIPC, ALU sa registrima i sa immediate-om, SW.
class iss;
  bit [31:0] x[32];                              // registri
  bit [31:0] dmem[4096];                         // DMEM 16 KB, indeks = adresa / 4

  function void run(bit [31:0] prog[$]);
    foreach (prog[i]) step(prog[i], 4*i);        // instrukcija i je na adresi 4*i
  endfunction

  function void step(bit [31:0] ins, bit [31:0] pc);
    bit [4:0]  rd    = ins[11:7];
    bit [2:0]  f3    = ins[14:12];
    bit [31:0] a     = x[ins[19:15]];                          // rs1
    bit [31:0] b     = x[ins[24:20]];                          // rs2
    bit [31:0] imm_i = {{20{ins[31]}}, ins[31:20]};
    bit [31:0] imm_s = {{20{ins[31]}}, ins[31:25], ins[11:7]};
    bit [31:0] imm_u = {ins[31:12], 12'b0};
    bit [31:0] addr;

    case (ins[6:0])
      7'h37: x[rd] = imm_u;                                    // LUI
      7'h17: x[rd] = pc + imm_u;                               // AUIPC
      7'h13: x[rd] = alu(f3, f3 == 5 && ins[30], a, imm_i);    // ADDI ... SRAI
      7'h33: x[rd] = alu(f3, ins[30], a, b);                   // ADD ... AND
      7'h23: begin addr = a + imm_s; dmem[addr[13:2]] = b; end // SW
    endcase
    x[0] = 0;                                                  // x0 je uvek 0
  endfunction

  // alt = funct7[5]: SUB umesto ADD, SRA umesto SRL
  function bit [31:0] alu(bit [2:0] f3, bit alt, bit [31:0] a, bit [31:0] b);
    case (f3)
      0: return alt ? a - b : a + b;                           // ADD / SUB
      1: return a << b[4:0];                                   // SLL
      2: return $signed(a) < $signed(b);                       // SLT
      3: return a < b;                                         // SLTU
      4: return a ^ b;                                         // XOR
      5: if (alt) return $signed(a) >>> b[4:0];                // SRA
         else     return a >> b[4:0];                          // SRL
      6: return a | b;                                         // OR
      7: return a & b;                                         // AND
    endcase
  endfunction
endclass
