`timescale 1ns/1ps

package shmins_driver_monitor_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;
  import shm_seq_item_package::*;

  `include "uvm_macros.svh"
  `include "shm_transaction_lifecycle_types.svh"
  `include "shmins_mst_agent_config.svh"
  `include "shmins_mst_sequencer.svh"
  `include "shmins_mst_driver.svh"
  `include "shmins_monitor.svh"
  `include "shmins_request_coverage.svh"
  `include "shmins_mst_agent.svh"
  `include "shm_directed_item_sequence.svh"

  //----------------------------------------------------------------------------
  // @brief Captures independent copies of monitor-published SHMINS requests.
  //----------------------------------------------------------------------------
  class shmins_driver_monitor_sink extends uvm_subscriber #(shmins_sequence_item);
    // Captured request copies in monitor publication order.
    shmins_sequence_item items[$];

    //----------------------------------------------------------------------------
    // @brief Constructs an empty driver/monitor sink.
    //
    // @param name UVM component instance name.
    // @param parent Parent component that owns this sink.
    //----------------------------------------------------------------------------
    extern function new(string name = "shmins_driver_monitor_sink", uvm_component parent = null);

    //----------------------------------------------------------------------------
    // @brief Copies and queues one monitor-published request.
    //
    // @param t Request observed on the SHMINS interface.
    //----------------------------------------------------------------------------
    extern virtual function void write(shmins_sequence_item t);

    `uvm_component_utils(shmins_driver_monitor_sink)
  endclass : shmins_driver_monitor_sink

  function shmins_driver_monitor_sink::new(string name = "shmins_driver_monitor_sink",
                                            uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  function void shmins_driver_monitor_sink::write(shmins_sequence_item t);
    shmins_sequence_item item_copy;

    $cast(item_copy, t.clone());
    if (item_copy == null) begin
      `uvm_fatal("SHMINS_DRIVER_MONITOR_CLONE", "failed to clone monitor transaction")
    end
    items.push_back(item_copy);
  endfunction : write

  //----------------------------------------------------------------------------
  // @brief Verifies four-state preservation and cycle-based request spacing.
  //
  // The test sends three legal requests through the production sequencer,
  // driver, interface, and monitor. It checks back-to-back issue for delay zero,
  // one complete idle cycle for delay one, and exact X preservation.
  //----------------------------------------------------------------------------
  class shmins_driver_monitor_test extends uvm_test;
    virtual clk_if clk_vif;
    virtual shmins_interface vif;
    shmins_mst_agent_config cfg;
    shmins_mst_agent agent;
    shmins_driver_monitor_sink sink;

    //----------------------------------------------------------------------------
    // @brief Constructs the driver/monitor component test.
    //
    // @param name UVM component instance name.
    // @param parent Parent component that owns this test.
    //----------------------------------------------------------------------------
    extern function new(string name = "shmins_driver_monitor_test", uvm_component parent = null);

    //----------------------------------------------------------------------------
    // @brief Creates and configures the production SHMINS agent.
    //
    // @param phase UVM build phase.
    //----------------------------------------------------------------------------
    extern virtual function void build_phase(uvm_phase phase);

    //----------------------------------------------------------------------------
    // @brief Connects monitor output to the local capture sink.
    //
    // @param phase UVM connect phase.
    //----------------------------------------------------------------------------
    extern virtual function void connect_phase(uvm_phase phase);

    //----------------------------------------------------------------------------
    // @brief Runs the X-DRV-001 and X-DRV-002 component scenarios.
    //
    // @param phase UVM main phase controlling the test objection.
    //----------------------------------------------------------------------------
    extern virtual task main_phase(uvm_phase phase);

    //----------------------------------------------------------------------------
    // @brief Creates a legal sparse-mask item for one topology.
    //
    // @param indexed Selects indexed rather than contiguous topology.
    // @param item_name UVM object instance name.
    // @return Generated item with thread zero active and elements 0/7 selected.
    //----------------------------------------------------------------------------
    extern protected function shmins_sequence_item create_item(bit indexed, string item_name);

    //----------------------------------------------------------------------------
    // @brief Sends one prepared item through the production driver.
    //
    // @param item Generated and optionally poisoned request.
    //----------------------------------------------------------------------------
    extern protected task send_item(shmins_sequence_item item);

    `uvm_component_utils(shmins_driver_monitor_test)
  endclass : shmins_driver_monitor_test

  function shmins_driver_monitor_test::new(string name = "shmins_driver_monitor_test",
                                            uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  function void shmins_driver_monitor_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif) ||
        !uvm_config_db#(virtual shmins_interface)::get(this, "", "vif", vif)) begin
      `uvm_fatal("SHMINS_DRIVER_MONITOR_VIF", "component test requires clock and SHMINS interfaces")
    end
    cfg = shmins_mst_agent_config::type_id::create("cfg");
    uvm_config_db#(shmins_mst_agent_config)::set(this, "agent", "cfg", cfg);
    uvm_config_db#(virtual shmins_interface)::set(this, "agent", "shmins_vif", vif);
    uvm_config_db#(virtual clk_if)::set(this, "agent.monitor", "clk_vif", clk_vif);
    agent = shmins_mst_agent::type_id::create("agent", this);
    sink = shmins_driver_monitor_sink::type_id::create("sink", this);
  endfunction : build_phase

  function void shmins_driver_monitor_test::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.monitor.shmins_analysis_port.connect(sink.analysis_export);
  endfunction : connect_phase

  function shmins_sequence_item shmins_driver_monitor_test::create_item(bit indexed, string item_name);
    shmins_sequence_item item;
    shmins_contiguous_sequence_item contiguous_item;
    shmins_indexed_sequence_item indexed_item;

    if (indexed) begin
      indexed_item = shmins_indexed_sequence_item::type_id::create(item_name);
      item = indexed_item;
    end else begin
      contiguous_item = shmins_contiguous_sequence_item::type_id::create(item_name);
      item = contiguous_item;
    end
    if (!item.randomize() with {
          creq_rw == SHM_V2M;
          creq_dtype == DTYP_8;
          creq_atype_w == ATYP_16;
          creq_atype_s == ATYP_U;
          creq_atype_g == GAUTO_1B;
          creq_space == SPACE_LOC;
          creq_wpid == 0;
          creq_tmsk == 16'h0001;
          elem_num[0] == 8;
          creq_vmsk[0][7:0] == 8'h81;
        }) begin
      `uvm_fatal("SHMINS_DRIVER_MONITOR_RANDOMIZE", $sformatf("failed to randomize %s", item_name))
    end
    return item;
  endfunction : create_item

  task shmins_driver_monitor_test::send_item(shmins_sequence_item item);
    shm_directed_item_sequence sequence_item;

    sequence_item = shm_directed_item_sequence::type_id::create({item.get_name(), "_sequence"});
    sequence_item.set_request(item);
    sequence_item.start(agent.sequencer);
  endtask : send_item

  task shmins_driver_monitor_test::main_phase(uvm_phase phase);
    shmins_sequence_item inactive_x_item;
    shmins_sequence_item indexed_x_item;
    shmins_sequence_item delayed_item;
    logic [VEC_W-1:0] indexed_offsets;

    phase.raise_objection(this);
    wait (vif.rst_n === 1'b1);

    inactive_x_item = create_item(1'b0, "inactive_x_item");
    inactive_x_item.delay_cycle = 0;
    if (!shmins_dontcare_x_util::poison_inactive_threads(inactive_x_item, 1'bx)) begin
      `uvm_fatal("X_DRV_001", "failed to poison inactive payload")
    end

    indexed_x_item = create_item(1'b1, "indexed_x_item");
    indexed_x_item.delay_cycle = 1;
    if (!shmins_dontcare_x_util::poison_masked_element_data(indexed_x_item, 1'bx) ||
        !shmins_dontcare_x_util::poison_indexed_masked_offsets(indexed_x_item, 1'bx)) begin
      `uvm_fatal("X_DRV_001", "failed to poison indexed masked payload")
    end

    delayed_item = create_item(1'b0, "delayed_item");
    delayed_item.delay_cycle = 0;

    send_item(inactive_x_item);
    send_item(indexed_x_item);
    send_item(delayed_item);

    repeat (20) begin
      if (sink.items.size() == 3) begin
        break;
      end
      @(posedge vif.clk);
    end
    if (sink.items.size() != 3) begin
      `uvm_fatal("X_DRV_COUNT", $sformatf("expected three monitor requests, observed %0d", sink.items.size()))
    end

    indexed_offsets = sink.items[1].creq_offs(0);
    if (!$isunknown(sink.items[0].creq_prio[1]) || !$isunknown(sink.items[0].creq_vdat[1]) ||
        !$isunknown(sink.items[1].creq_vdat[0][1]) || !$isunknown(indexed_offsets[31:16]) ||
        $isunknown(sink.items[1].creq_vdat[0][0]) || $isunknown(indexed_offsets[15:0])) begin
      `uvm_fatal("X_DRV_001", "driver/monitor did not preserve exact interpreted and ignored four-state slices")
    end
    if (sink.items[1].accept_cycle != sink.items[0].accept_cycle + 1 ||
        sink.items[2].accept_cycle != sink.items[1].accept_cycle + 2) begin
      `uvm_fatal("X_DRV_002",
                 $sformatf("unexpected accept cycles %0d, %0d, %0d", sink.items[0].accept_cycle,
                           sink.items[1].accept_cycle, sink.items[2].accept_cycle))
    end

    `uvm_info("SHMINS_DRIVER_MONITOR_TEST", "don’t-care driver/monitor component matrix: PASS", UVM_LOW)
    phase.drop_objection(this);
  endtask : main_phase
endpackage : shmins_driver_monitor_test_pkg

//------------------------------------------------------------------------------
// @brief Provides clock and interfaces for the SHMINS driver/monitor component test.
//------------------------------------------------------------------------------
module shmins_driver_monitor_tb;
  import uvm_pkg::*;
  import shmins_driver_monitor_test_pkg::*;

  logic clk;
  logic rst_n;
  clk_if clk_vif(clk);
  shmins_interface shmins_vif(clk, rst_n);

  initial begin
    clk = 1'b0;
    forever #5ns clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    shmins_vif.creq_rls = 1'b0;
    shmins_vif.vack_done = 1'b0;
    shmins_vif.vack_id = '0;
    shmins_vif.mack_done = 1'b0;
    shmins_vif.mack_id = '0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual clk_if)::set(null, "uvm_test_top", "clk_vif", clk_vif);
    uvm_config_db#(virtual shmins_interface)::set(null, "uvm_test_top", "vif", shmins_vif);
    run_test("shmins_driver_monitor_test");
  end
endmodule : shmins_driver_monitor_tb
