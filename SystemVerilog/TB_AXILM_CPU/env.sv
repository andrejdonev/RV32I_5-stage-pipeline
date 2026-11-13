// Okruzenje: sequencer -> driver, monitor -> scoreboard.
class env extends uvm_env;
  `uvm_component_utils(env)

  uvm_sequencer #(transaction) seqr;
  driver     drv;
  monitor    mon;
  scoreboard scb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    seqr = uvm_sequencer #(transaction)::type_id::create("seqr", this);
    drv  = driver::type_id::create("drv", this);
    mon  = monitor::type_id::create("mon", this);
    scb  = scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
    mon.ap.connect(scb.imp);
  endfunction
endclass
