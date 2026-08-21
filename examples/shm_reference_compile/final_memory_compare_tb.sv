`timescale 1ns/1ps

package shm_final_memory_compare_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;
  import svt_uvm_pkg::*;
  import svt_mem_uvm_pkg::*;
  import shm_env_package::*;

  `include "uvm_macros.svh"

  //----------------------------------------------------------------------------
  // @brief Verifies touched-byte final reference/actual memory comparison.
  //----------------------------------------------------------------------------
  class shm_final_memory_compare_test extends uvm_test;
    shm_environment_config cfg;
    shm_scoreboard scoreboard;
    virtual clk_if clk_vif;
    svt_mem reference_banks[BANK_N][GID_N];

    extern function new(string name = "shm_final_memory_compare_test", uvm_component parent = null);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task configure_phase(uvm_phase phase);
    extern virtual task main_phase(uvm_phase phase);
    extern protected function void clear_touched();
    extern protected function void touch(int unsigned bank, int unsigned gid, shm_baddr_t baddr);
    extern protected function void write_pair(int unsigned bank,
                                              int unsigned gid,
                                              shm_baddr_t baddr,
                                              byte unsigned reference_value,
                                              byte unsigned actual_value);
    extern protected function void check_compare(string scenario, bit expected_match);

    `uvm_component_utils(shm_final_memory_compare_test)
  endclass : shm_final_memory_compare_test

  function shm_final_memory_compare_test::new(string name = "shm_final_memory_compare_test",
                                              uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  function void shm_final_memory_compare_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
      `uvm_fatal("SHM_FINAL_COMPARE_NO_CLK", "final-memory component test requires clk_vif")
    end
    cfg = shm_environment_config::type_id::create("cfg");
    cfg.init();
    uvm_config_db#(shm_environment_config)::set(this, "scoreboard", "shm_environment_config", cfg);
    uvm_config_db#(virtual clk_if)::set(this, "scoreboard", "clk_vif", clk_vif);
    scoreboard = shm_scoreboard::type_id::create("scoreboard", this);

    foreach (reference_banks[bank, gid]) begin
      reference_banks[bank][gid] = new($sformatf("component_ref_bank_%0d_gid_%0d", bank, gid),
                                       "COMPONENT_REF_BANKS", 8, 0, 0,
                                       (1 << BADDR_W) - 1);
    end
  endfunction : build_phase

  task shm_final_memory_compare_test::configure_phase(uvm_phase phase);
    foreach (reference_banks[bank, gid]) begin
      reference_banks[bank][gid].set_meminit(svt_mem::INCR, (bank * GID_N + gid) << 4);
    end
  endtask : configure_phase

  function void shm_final_memory_compare_test::clear_touched();
    foreach (scoreboard.touched_waddrs[physical_bank]) begin
      scoreboard.touched_waddrs[physical_bank].delete();
    end
  endfunction : clear_touched

  function void shm_final_memory_compare_test::touch(int unsigned bank,
                                                     int unsigned gid,
                                                     shm_baddr_t baddr);
    int unsigned physical_bank = physical_bank_index(bank, gid);
    scoreboard.touched_waddrs[physical_bank].push_back(baddr);
  endfunction : touch

  function void shm_final_memory_compare_test::write_pair(int unsigned bank,
                                                          int unsigned gid,
                                                          shm_baddr_t baddr,
                                                          byte unsigned reference_value,
                                                          byte unsigned actual_value);
    reference_banks[bank][gid].write(baddr, reference_value);
    scoreboard.rtl_banks[bank][gid].write(baddr, actual_value);
    touch(bank, gid, baddr);
  endfunction : write_pair

  function void shm_final_memory_compare_test::check_compare(string scenario, bit expected_match);
    string diagnostic;
    bit matched = scoreboard.compare_final_memory(reference_banks, diagnostic);

    if (matched != expected_match || (!expected_match && diagnostic == "")) begin
      `uvm_fatal("SHM_FINAL_COMPARE_MATRIX",
                 $sformatf("%s matched=%0d expected=%0d diagnostic=%s",
                           scenario, matched, expected_match, diagnostic))
    end
    `uvm_info("SHM_FINAL_COMPARE_CELL", $sformatf("%s: PASS", scenario), UVM_LOW)
  endfunction : check_compare

  task shm_final_memory_compare_test::main_phase(uvm_phase phase);
    phase.raise_objection(this);

    clear_touched();
    write_pair(0, 0, 'h100, 8'h22, 8'h22);
    check_compare("ORDER-SCB-001", 1'b1);

    clear_touched();
    write_pair(0, 0, 'h110, 8'h92, 8'h41);
    check_compare("ORDER-SCB-002", 1'b0);

    clear_touched();
    write_pair(1, 0, 'h120, 8'h10, 8'h10);
    write_pair(1, 0, 'h121, 8'h20, 8'h20);
    write_pair(1, 0, 'h122, 8'h30, 8'h30);
    check_compare("ORDER-SCB-003", 1'b1);

    clear_touched();
    write_pair(2, 0, 'h130, 8'h10, 8'h10);
    write_pair(2, 0, 'h131, 8'h20, 8'h11);
    write_pair(2, 0, 'h132, 8'h30, 8'h30);
    check_compare("ORDER-SCB-004", 1'b0);

    clear_touched();
    write_pair(3, 0, 'h140, 8'h5a, 8'h5a);
    write_pair(3, 1, 'h140, 8'ha5, 8'ha5);
    check_compare("ORDER-SCB-005", 1'b1);

    `uvm_info("SHM_FINAL_MEMORY_COMPARE_TEST", "ORDER-SCB-001..005: PASS", UVM_LOW)
    phase.drop_objection(this);
  endtask : main_phase
endpackage : shm_final_memory_compare_test_pkg

//------------------------------------------------------------------------------
// @brief Supplies the shared cycle interface for the memory component test.
//------------------------------------------------------------------------------
module shm_final_memory_compare_tb;
  import uvm_pkg::*;
  import shm_final_memory_compare_test_pkg::*;

  logic clk;
  clk_if clk_vif(clk);

  initial begin
    clk = 1'b0;
    forever #5ns clk = ~clk;
  end

  initial begin
    uvm_config_db#(virtual clk_if)::set(null, "uvm_test_top", "clk_vif", clk_vif);
    run_test("shm_final_memory_compare_test");
  end
endmodule : shm_final_memory_compare_tb
