// Driver = AXI4-Lite master.
//   1. instrukcije iz sekvence upisuje u IMEM (adrese 0, 4, 8, ...)
//   2. posle poslednje (tr.last) doda potpis: sw x1..x31 -> DMEM[1..31],
//      jer ALU instrukcije menjaju samo registre, a poredimo memoriju
//   3. CTRL.run = 1, saceka, procita DMEM[0..31], CTRL.run = 0
class driver extends uvm_driver #(transaction);
  `uvm_component_utils(driver)

  virtual axil_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(virtual axil_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "vif nije postavljen")
  endfunction

  task run_phase(uvm_phase phase);
    transaction tr;
    int n = 0;                                   // broj upisanih instrukcija

    vif.awvalid = 0; vif.wvalid = 0; vif.arvalid = 0;
    vif.bready  = 1; vif.rready = 1;             // odgovore uvek prihvatamo
    wait (vif.rst_n);

    forever begin
      seq_item_port.get_next_item(tr);
      write(IMEM_BASE + 4*n, tr.instruction);
      n++;

      if (tr.last) begin
        for (int r = 1; r < 32; r++) begin       // potpis
          write(IMEM_BASE + 4*n, sw(r));
          n++;
        end
        write(CTRL_BASE + REG_CTRL, 1);          // procesor krece
        repeat (200) @(posedge vif.clk);         // program se izvrsava
        for (int i = 0; i < 32; i++)
          read(DMEM_BASE + 4*i);                 // podatke belezi monitor
        write(CTRL_BASE + REG_CTRL, 0);          // stop
        n = 0;
      end

      seq_item_port.item_done();
    end
  endtask

  // sw xr, 4*r(x0)   S-tip: {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode}
  function bit [31:0] sw(bit [4:0] r);
    bit [11:0] imm = 4 * r;
    return {imm[11:5], r, 5'd0, 3'd2, imm[4:0], 7'h23};
  endfunction

  // signali se menjaju na silaznoj ivici, slave ih vidi na rastucoj
  task write(bit [31:0] addr, bit [31:0] data);
    bit aw_done = 0, w_done = 0;
    @(negedge vif.clk);
    vif.awaddr = addr; vif.awvalid = 1;
    vif.wdata  = data; vif.wvalid  = 1; vif.wstrb = 4'hF;
    while (!(aw_done && w_done)) begin           // AW i W mogu biti prihvaceni u razlicitim taktovima
      @(posedge vif.clk);
      if (vif.awready) aw_done = 1;
      if (vif.wready)  w_done  = 1;
      @(negedge vif.clk);
      if (aw_done) vif.awvalid = 0;
      if (w_done)  vif.wvalid  = 0;
    end
    do @(posedge vif.clk); while (!vif.bvalid);  // B odgovor
  endtask

  task read(bit [31:0] addr);
    @(negedge vif.clk);
    vif.araddr = addr; vif.arvalid = 1;
    do @(posedge vif.clk); while (!vif.arready);
    @(negedge vif.clk);
    vif.arvalid = 0;
    do @(posedge vif.clk); while (!vif.rvalid);  // R odgovor
  endtask
endclass
