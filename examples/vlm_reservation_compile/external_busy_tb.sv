`timescale 1ns/1ps

package vlm_reservation_external_busy_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"

  `include "vlm_memory_sequence_item.svh"
  `include "vlm_reservation_types.svh"
  `include "vlm_reservation_agent_config.svh"
  `include "vlm_reservation_scheduler.svh"
  `include "vlm_reservation_checker.svh"
  `include "vlm_reservation_coverage.svh"
  `include "vlm_reservation_monitor.svh"
  `include "vlm_reservation_agent.svh"
  `include "vlm_agent.svh"

  //----------------------------------------------------------------------------
  // @brief Verifies plusarg propagation and active external busy driving.
  //----------------------------------------------------------------------------
  class vlm_reservation_external_busy_test extends uvm_test;
    vlm_reservation_agent_config reservation_cfg;
    vlm_agent                    agent;

    virtual vlm_interface vif;

    function new(string name = "vlm_reservation_external_busy_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      if (!uvm_config_db#(virtual vlm_interface)::get(this, "", "vlm_vif", vif)) begin
        `uvm_fatal("EXTERNAL_BUSY_NO_VIF", "test requires vlm_vif")
      end

      reservation_cfg = vlm_reservation_agent_config::type_id::create("reservation_cfg");
      reservation_cfg.vif                   = vif;
      reservation_cfg.EXTERNAL_BUSY_PERCENT = 7;

      uvm_config_db#(vlm_reservation_agent_config)::set(
          this, "agent", "cfg", reservation_cfg);
      agent = vlm_agent::type_id::create("agent", this);
    endfunction : build_phase

    virtual task main_phase(uvm_phase phase);
      phase.raise_objection(this);

      @(posedge vif.rst_n);
      repeat (2) @(vif.mon_cb);

      if (agent.scheduler.external_busy_percent != 100) begin
        `uvm_fatal("EXTERNAL_BUSY_PLUSARG",
                   $sformatf("expected plusarg override 100, got %0d",
                             agent.scheduler.external_busy_percent))
      end

      if (agent.scheduler.generated_external_slot_count == 0) begin
        `uvm_fatal("EXTERNAL_BUSY_NOT_GENERATED", "scheduler did not generate any external busy slots")
      end

      if (vif.mon_cb.rbusy != '1 || vif.mon_cb.wbusy != '1) begin
        `uvm_fatal("EXTERNAL_BUSY_NOT_DRIVEN",
                   $sformatf("expected all busy slots high, observed rbusy=0x%0h wbusy=0x%0h",
                             vif.mon_cb.rbusy, vif.mon_cb.wbusy))
      end

      `uvm_info("EXTERNAL_BUSY_TEST", "external busy plusarg regression: PASS", UVM_LOW)
      phase.drop_objection(this);
    endtask : main_phase

    `uvm_component_utils(vlm_reservation_external_busy_test)
  endclass : vlm_reservation_external_busy_test

endpackage : vlm_reservation_external_busy_test_pkg

module external_busy_tb;
  import uvm_pkg::*;
  import shm_util_package::*;
  import vlm_reservation_external_busy_test_pkg::*;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  clk_if clk_vif(clk);
  vlm_interface vif(clk, rst_n);

  always #5ns clk = ~clk;

  assign vif.rreq = '0;
  assign vif.raddr = '0;
  assign vif.rdly = '0;
  assign vif.rgid = '0;
  assign vif.wreq = '0;
  assign vif.waddr = '0;
  assign vif.wdly = '0;
  assign vif.wgid = '0;
  assign vif.rvld = '0;
  assign vif.mem_raddr = '0;
  assign vif.wvld = '0;
  assign vif.mem_waddr = '0;
  assign vif.wstrb = '0;
  assign vif.wdata = '0;

  initial begin
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual clk_if)::set(
        null, "uvm_test_top.agent.*", "clk_vif", clk_vif);
    uvm_config_db#(virtual vlm_interface)::set(null, "uvm_test_top", "vlm_vif", vif);
    run_test("vlm_reservation_external_busy_test");
  end

endmodule : external_busy_tb
