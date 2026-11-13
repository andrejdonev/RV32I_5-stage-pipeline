// Scoreboard: program iz monitora izvrsi na ISS-u i uporedi
// DMEM procesora sa DMEM-om ISS-a.
class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)

  uvm_analysis_imp #(cpu_result, scoreboard) imp;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp = new("imp", this);
  endfunction

  function void write(cpu_result res);
    iss ref_model = new();
    int errors = 0;

    ref_model.run(res.instr);
    foreach (res.mem[i])
      if (res.mem[i] !== ref_model.dmem[i]) begin
        `uvm_error("SCB", $sformatf("DMEM[%0d]: procesor %h, ISS %h", i, res.mem[i], ref_model.dmem[i]))
        errors++;
      end

    if (errors == 0)
      `uvm_info("SCB", $sformatf("OK: %0d instrukcija, %0d reci DMEM-a se poklapa",
                                 res.instr.size(), res.mem.size()), UVM_LOW)
  endfunction
endclass
