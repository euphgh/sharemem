`timescale 1ns/1ps

package vlm_agent_metadata_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
  `include "shm_expected_report_catcher.svh"
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
  // @brief Captures write transactions published by the unified VLM agent.
  //----------------------------------------------------------------------------
  class vlm_agent_metadata_sink extends uvm_subscriber #(vlm_memory_sequence_item);
    vlm_memory_sequence_item items[$];

    //----------------------------------------------------------------------------
    // @brief Constructs the metadata capture sink.
    //
    // @param name   UVM component instance name.
    // @param parent Parent component that owns this sink.
    //----------------------------------------------------------------------------
    function new(string name = "vlm_agent_metadata_sink", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    //----------------------------------------------------------------------------
    // @brief Queues one immutable published memory transaction.
    //
    // @param t Transaction published by the unified VLM agent.
    //----------------------------------------------------------------------------
    virtual function void write(vlm_memory_sequence_item t);
      items.push_back(t);
    endfunction : write

    `uvm_component_utils(vlm_agent_metadata_sink)
  endclass : vlm_agent_metadata_sink

  //----------------------------------------------------------------------------
  // @brief Provides the mandatory read-data transport endpoint.
  //----------------------------------------------------------------------------
  class vlm_agent_metadata_memory_sink extends uvm_component;
    uvm_tlm_b_transport_imp #(vlm_memory_sequence_item, vlm_agent_metadata_memory_sink) mem_imp;

    //----------------------------------------------------------------------------
    // @brief Constructs the read-data transport endpoint.
    //
    // @param name   UVM component instance name.
    // @param parent Parent component that owns this sink.
    //----------------------------------------------------------------------------
    function new(string name = "vlm_agent_metadata_memory_sink", uvm_component parent = null);
      super.new(name, parent);
      mem_imp = new("mem_imp", this);
    endfunction : new

    //----------------------------------------------------------------------------
    // @brief Accepts a read request; this write-only test never calls the API.
    //
    // @param trans Read transaction supplied by the VLM agent.
    // @param delay TLM delay associated with the transaction.
    //----------------------------------------------------------------------------
    virtual task b_transport(vlm_memory_sequence_item trans, uvm_tlm_time delay);
    endtask : b_transport

    `uvm_component_utils(vlm_agent_metadata_memory_sink)
  endclass : vlm_agent_metadata_memory_sink

  //----------------------------------------------------------------------------
  // @brief Verifies that unmatched MEM publication never carries trusted gid metadata.
  //----------------------------------------------------------------------------
  class vlm_agent_metadata_test extends uvm_test;
    vlm_reservation_agent_config cfg;
    vlm_agent agent;
    vlm_agent_metadata_sink write_sink;
    vlm_agent_metadata_memory_sink memory_sink;
    shm_expected_report_catcher report_catcher;
    vlm_reservation_directed_busy_policy directed_policy;
    virtual vlm_interface vif;

    //----------------------------------------------------------------------------
    // @brief Constructs the agent metadata test.
    //
    // @param name   UVM component instance name.
    // @param parent Parent component that owns this test.
    //----------------------------------------------------------------------------
    function new(string name = "vlm_agent_metadata_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    //----------------------------------------------------------------------------
    // @brief Creates the agent, capture sink, and exact expected-report catcher.
    //
    // @param phase UVM build phase.
    //----------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual vlm_interface)::get(this, "", "vlm_vif", vif)) begin
        `uvm_fatal("VLM_AGENT_METADATA_NO_VIF", "test requires vlm_vif")
      end
      cfg = vlm_reservation_agent_config::type_id::create("cfg");
      cfg.vif = vif;
      cfg.EXTERNAL_BUSY_PERCENT = 100;
      directed_policy = vlm_reservation_directed_busy_policy::type_id::create("directed_policy");
      directed_policy.add_busy_range(0, 100, VLM_RESERVATION_READ, 4, 1, 2);
      cfg.external_busy_policy = directed_policy;
      uvm_config_db#(vlm_reservation_agent_config)::set(this, "agent", "cfg", cfg);
      agent = vlm_agent::type_id::create("agent", this);
      write_sink = vlm_agent_metadata_sink::type_id::create("write_sink", this);
      memory_sink = vlm_agent_metadata_memory_sink::type_id::create("memory_sink", this);
      report_catcher = new();
      report_catcher.expect_report("VLM_RESERVATION_UNEXPECTED_MEM");
      uvm_report_cb::add(null, report_catcher);
    endfunction : build_phase

    //----------------------------------------------------------------------------
    // @brief Connects published writes and the required read transport endpoint.
    //
    // @param phase UVM connect phase.
    //----------------------------------------------------------------------------
    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.write_analysis_port.connect(write_sink.analysis_export);
      agent.mem_port.connect(memory_sink.mem_imp);
    endfunction : connect_phase

    //----------------------------------------------------------------------------
    // @brief Drives one unreserved MEM write and checks published trust metadata.
    //
    // @param phase UVM main phase controlling the test objection.
    //----------------------------------------------------------------------------
    virtual task main_phase(uvm_phase phase);
      int unsigned bank = 5;

      phase.raise_objection(this);
      @(posedge vif.rst_n);
      @(negedge vif.clk);
      vif.wvld[bank] = 1'b1;
      vif.mem_waddr[bank] = 'h140;
      vif.wstrb[bank] = 'h1;
      vif.wdata[bank][7:0] = 8'h5a;
      @(negedge vif.clk);
      vif.wvld[bank] = 1'b0;
      repeat (2) @(vif.mon_cb);

      if (agent.scheduler.external_busy_policy != directed_policy || vif.mon_cb.wbusy != '0 ||
          agent.scheduler.generated_external_slot_count == 0) begin
        `uvm_fatal("VLM_AGENT_METADATA_POLICY",
                   "config policy did not replace 100-percent random external-busy generation")
      end
      if (write_sink.items.size() != 1 || !write_sink.items[0].vlm_bken[bank] ||
          write_sink.items[0].gid_valid[bank] || write_sink.items[0].reservation_matched[bank]) begin
        `uvm_fatal("VLM_AGENT_METADATA_TRUST", "unmatched MEM write received trusted reservation metadata")
      end
      if (!report_catcher.expectations_met()) begin
        `uvm_fatal("VLM_AGENT_METADATA_REPORT", "unexpected-MEM report count did not match")
      end

      `uvm_info("VLM_AGENT_METADATA_TEST", "unmatched MEM metadata component test: PASS", UVM_LOW)
      phase.drop_objection(this);
    endtask : main_phase

    `uvm_component_utils(vlm_agent_metadata_test)
  endclass : vlm_agent_metadata_test
endpackage : vlm_agent_metadata_test_pkg

module agent_metadata_tb;
  import uvm_pkg::*;
  import shm_util_package::*;
  import vlm_agent_metadata_test_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  clk_if clock_service(clk);
  vlm_interface vif(clk, rst_n);

  always #5ns clk = ~clk;

  initial begin
    vif.rreq = '0;
    vif.raddr = '0;
    vif.rdly = '0;
    vif.rgid = '0;
    vif.wreq = '0;
    vif.waddr = '0;
    vif.wdly = '0;
    vif.wgid = '0;
    vif.rvld = '0;
    vif.mem_raddr = '0;
    vif.wvld = '0;
    vif.mem_waddr = '0;
    vif.wstrb = '0;
    vif.wdata = '0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual clk_if)::set(null, "uvm_test_top.agent.*", "clk_vif", clock_service);
    uvm_config_db#(virtual vlm_interface)::set(null, "uvm_test_top", "vlm_vif", vif);
    run_test("vlm_agent_metadata_test");
  end
endmodule : agent_metadata_tb
