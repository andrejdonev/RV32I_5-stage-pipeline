// Jedan program = 10 random ALU instrukcija. Poslednja ima last = 1,
// to je za driver znak da program pokrene.
class sequence1 extends uvm_sequence #(transaction);
  `uvm_object_utils(sequence1)

  transaction tr;

  function new(input string path = "sequence1");
    super.new(path);
  endfunction

  task body();
    for (int i = 0; i < 10; i++) begin
      tr = transaction::type_id::create("tr");
      start_item(tr);
      // samo ALU: bez skokova i memorijskih pristupa, program uvek stigne do kraja
      if (!tr.randomize() with { opcode inside {OPCODE_R_TYPE, OPCODE_I_ALU, OPCODE_LUI, OPCODE_AUIPC}; })
        `uvm_error("SEQ", "randomize nije uspeo")
      tr.last = (i == 9);
      finish_item(tr);
    end
  endtask
endclass
