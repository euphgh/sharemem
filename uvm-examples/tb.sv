`timescale 1ns/1ps

package vcs_uvm_smoke_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  //----------------------------------------------------------------------------
  // @brief Provides one executable test for validating the VCS UVM runtime.
  //
  // The test raises and drops a run-phase objection and emits a uniquely tagged
  // UVM message. It does not instantiate a DUT or model any design behavior.
  //----------------------------------------------------------------------------
  class vcs_uvm_smoke_test extends uvm_test;
    `uvm_component_utils(vcs_uvm_smoke_test)

    //--------------------------------------------------------------------------
    // @brief Constructs the minimal VCS UVM smoke test.
    //
    // @param name   UVM instance name assigned by the factory.
    // @param parent Parent component; null when the test is the UVM root.
    //--------------------------------------------------------------------------
    function new(
        string        name = "vcs_uvm_smoke_test",
        uvm_component parent = null);
      super.new(name, parent);
    endfunction

    //--------------------------------------------------------------------------
    // @brief Exercises the UVM run phase and reports successful execution.
    //
    // @param phase Active UVM run phase whose objection controls test lifetime.
    // @post One VCS_UVM_SMOKE informational message has been emitted.
    //--------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      `uvm_info("VCS_UVM_SMOKE", "UVM smoke test passed", UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass
endpackage

//------------------------------------------------------------------------------
// @brief Starts the UVM smoke test without requiring a DUT instance.
//------------------------------------------------------------------------------
module tb;
  import uvm_pkg::*;
  import vcs_uvm_smoke_pkg::*;

  initial begin
    run_test("vcs_uvm_smoke_test");
  end
endmodule

