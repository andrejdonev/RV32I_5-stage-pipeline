// Sve UVM klase testbench-a u jednom paketu.
// U Vivadu ukljuceni fajlovi moraju biti tipa "Verilog Header".
package tb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import risc_pkg::IMEM_BASE, risc_pkg::DMEM_BASE, risc_pkg::CTRL_BASE, risc_pkg::REG_CTRL;

  `include "transaction.sv"
  `include "sequence.sv"
  `include "driver.sv"
  `include "monitor.sv"
  `include "iss.sv"
  `include "scoreboard.sv"
  `include "env.sv"
  `include "test.sv"
endpackage
