// Ono sto monitor salje scoreboard-u: program i memorija na kraju.
class cpu_result;
  bit [31:0] instr[$];                           // reci upisane u IMEM
  bit [31:0] mem[$];                             // reci procitane iz DMEM
endclass

// Monitor: samo posmatra AXI magistralu.
// Belezi upise u IMEM i citanja iz DMEM. Kad driver zaustavi
// procesor (upis CTRL = 0), salje sve scoreboard-u.
class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)

  virtual axil_if vif;
  uvm_analysis_port #(cpu_result) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(virtual axil_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "vif nije postavljen")
  endfunction

  task run_phase(uvm_phase phase);
    cpu_result res = new();
    bit [31:0] awaddr, wdata, araddr;

    forever begin
      @(posedge vif.clk);
      // adresa i podatak (handshake = valid && ready)
      if (vif.awvalid && vif.awready) awaddr = vif.awaddr;
      if (vif.wvalid  && vif.wready)  wdata  = vif.wdata;
      if (vif.arvalid && vif.arready) araddr = vif.araddr;

      // upis zavrsen (B)
      if (vif.bvalid && vif.bready) begin
        if (awaddr < DMEM_BASE)
          res.instr.push_back(wdata);                        // instrukcija
        else if (awaddr == CTRL_BASE + REG_CTRL && wdata == 0) begin
          ap.write(res);                                     // kraj programa
          res = new();
        end
      end

      // citanje zavrseno (R)
      if (vif.rvalid && vif.rready && araddr >= DMEM_BASE && araddr < CTRL_BASE)
        res.mem.push_back(vif.rdata);
    end
  endtask
endclass
