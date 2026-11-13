// Test: napravi okruzenje i pusti sekvencu od 10 instrukcija.
class test extends uvm_test;
  `uvm_component_utils(test)

  env e;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    e = env::type_id::create("e", this);
  endfunction

  task run_phase(uvm_phase phase);
    sequence1 seq = sequence1::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(e.seqr);                           // vraca se tek kad driver zavrsi ceo program
    phase.drop_objection(this);
  endtask
endclass
