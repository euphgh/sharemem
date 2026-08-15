`timescale 1ns/1ps

package vlm_reservation_external_busy_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"

  `include "vlm_memory_sequence_item.svh"
  `include "vlm_reservation_types.svh"
  `include "vlm_reservation_external_busy_policy.svh"
  `include "vlm_reservation_agent_config.svh"
  `include "vlm_reservation_scheduler.svh"
  `include "vlm_reservation_checker.svh"
  `include "vlm_reservation_coverage.svh"
  `include "vlm_reservation_monitor.svh"
  `include "vlm_reservation_agent.svh"
  `include "vlm_agent.svh"

  //----------------------------------------------------------------------------
  // @brief Provides the mandatory read-data transport endpoint for the agent.
  //----------------------------------------------------------------------------
  class vlm_reservation_memory_sink extends uvm_component;
    uvm_tlm_b_transport_imp #(vlm_memory_sequence_item, vlm_reservation_memory_sink) mem_imp;

    //----------------------------------------------------------------------------
    // @brief Constructs the component and its blocking transport implementation.
    //
    // @param name   UVM component instance name.
    // @param parent Parent component that owns this sink.
    //----------------------------------------------------------------------------
    function new(string name = "vlm_reservation_memory_sink", uvm_component parent = null);
      super.new(name, parent);
      mem_imp = new("mem_imp", this);
    endfunction : new

    //----------------------------------------------------------------------------
    // @brief Accepts a read-data request when a future extension drives MEM read.
    //
    // The external-busy test does not issue MEM requests, so the implementation
    // intentionally leaves the transaction unchanged.
    //
    // @param trans VLM memory transaction supplied by the reservation agent.
    // @param delay TLM delay associated with the transaction.
    //----------------------------------------------------------------------------
    virtual task b_transport(vlm_memory_sequence_item trans, uvm_tlm_time delay);
    endtask : b_transport

    `uvm_component_utils(vlm_reservation_memory_sink)
  endclass : vlm_reservation_memory_sink

  //----------------------------------------------------------------------------
  // @brief Verifies plusarg propagation and active external busy driving.
  //----------------------------------------------------------------------------
  class vlm_reservation_external_busy_test extends uvm_test;
    vlm_reservation_agent_config reservation_cfg;
    vlm_reservation_memory_sink  memory_sink;
    vlm_agent                    agent;

    virtual vlm_interface vif;

    //----------------------------------------------------------------------------
    // @brief Constructs the external-busy component test.
    //
    // @param name   UVM component instance name.
    // @param parent Parent component that owns this test.
    //----------------------------------------------------------------------------
    function new(string name = "vlm_reservation_external_busy_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    //----------------------------------------------------------------------------
    // @brief Creates the unified VLM agent and its required configuration.
    //
    // @param phase UVM build phase used to construct the test hierarchy.
    //----------------------------------------------------------------------------
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
      agent       = vlm_agent::type_id::create("agent", this);
      memory_sink = vlm_reservation_memory_sink::type_id::create("memory_sink", this);
    endfunction : build_phase

    //----------------------------------------------------------------------------
    // @brief Connects the mandatory read-data transport path to the local sink.
    //
    // @param phase UVM connect phase used to establish TLM connections.
    //----------------------------------------------------------------------------
    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.mem_port.connect(memory_sink.mem_imp);
    endfunction : connect_phase

    //----------------------------------------------------------------------------
    // @brief Checks plusarg precedence and externally generated busy outputs.
    //
    // @param phase UVM main phase controlling the test objection.
    //----------------------------------------------------------------------------
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
