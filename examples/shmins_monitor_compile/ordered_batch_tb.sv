`timescale 1ns/1ps

package shmins_ordered_batch_test_pkg;
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
  // @brief Captures request acceptance cycles from the production monitor.
  //----------------------------------------------------------------------------
  class shmins_ordered_batch_sink extends uvm_subscriber #(shmins_sequence_item);
    shm_cycle_t cycles[$];

    extern function new(string name = "shmins_ordered_batch_sink", uvm_component parent = null);
    extern virtual function void write(shmins_sequence_item t);

    `uvm_component_utils(shmins_ordered_batch_sink)
  endclass : shmins_ordered_batch_sink

  function shmins_ordered_batch_sink::new(string name = "shmins_ordered_batch_sink",
                                          uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  function void shmins_ordered_batch_sink::write(shmins_sequence_item t);
    cycles.push_back(t.accept_cycle);
  endfunction : write

  //----------------------------------------------------------------------------
  // @brief Covers pairwise hazards and ordered queue transport without a DUT.
  //----------------------------------------------------------------------------
  class shmins_ordered_batch_test extends uvm_test;
    virtual shmins_interface vif;
    virtual clk_if clk_vif;
    shmins_mst_agent_config cfg;
    shmins_mst_agent agent;
    shmins_ordered_batch_sink sink;

    extern function new(string name = "shmins_ordered_batch_test", uvm_component parent = null);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);
    extern virtual task main_phase(uvm_phase phase);

    extern protected function shmins_sequence_item make_synthetic_item(
        string name,
        creq_rw_e direction,
        creq_dtype_e dtype,
        int unsigned thread_idx,
        shm_gid_t m_gid,
        shm_baddr_t m_baddr,
        shm_gid_t v_gid,
        shm_baddr_t v_baddr);
    extern protected function shmins_sequence_item make_transport_item(string name);
    extern protected function void check_pair(string scenario,
                                              shmins_sequence_item first_item,
                                              shmins_sequence_item second_item,
                                              bit expect_overlap,
                                              int unsigned expected_count = 0);
    extern protected function bit contains_text(string text, string fragment);
    extern protected task send_batch(ref shmins_sequence_item items[$], input int unsigned delay_cycles);

    `uvm_component_utils(shmins_ordered_batch_test)
  endclass : shmins_ordered_batch_test

  function shmins_ordered_batch_test::new(string name = "shmins_ordered_batch_test",
                                          uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  function void shmins_ordered_batch_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual shmins_interface)::get(this, "", "vif", vif) ||
        !uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
      `uvm_fatal("SHM_ORDERED_BATCH_NO_VIF", "ordered batch test requires shmins and clock interfaces")
    end
    cfg = shmins_mst_agent_config::type_id::create("cfg");
    uvm_config_db#(shmins_mst_agent_config)::set(this, "agent", "cfg", cfg);
    uvm_config_db#(virtual shmins_interface)::set(this, "agent", "shmins_vif", vif);
    uvm_config_db#(virtual clk_if)::set(this, "agent.monitor", "clk_vif", clk_vif);
    agent = shmins_mst_agent::type_id::create("agent", this);
    sink = shmins_ordered_batch_sink::type_id::create("sink", this);
  endfunction : build_phase

  function void shmins_ordered_batch_test::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.monitor.shmins_analysis_port.connect(sink.analysis_export);
  endfunction : connect_phase

  function shmins_sequence_item shmins_ordered_batch_test::make_synthetic_item(
      string name,
      creq_rw_e direction,
      creq_dtype_e dtype,
      int unsigned thread_idx,
      shm_gid_t m_gid,
      shm_baddr_t m_baddr,
      shm_gid_t v_gid,
      shm_baddr_t v_baddr);
    shmins_contiguous_sequence_item item;
    int unsigned byte_width;

    item = shmins_contiguous_sequence_item::type_id::create(name);
    item.creq_rw = direction;
    item.creq_dtype = dtype;
    item.creq_itype = LDST_S;
    item.creq_space = SPACE_LOC;
    item.creq_wpid = v_gid * WARP_PER_GID;
    item.creq_vaddr = v_baddr;
    item.creq_tmsk = '0;
    item.creq_tmsk[thread_idx] = 1'b1;
    byte_width = item.data_byte_w();
    item.creq_len[thread_idx] = byte_width;
    item.elem_num[thread_idx] = 1;
    item.creq_vmsk[thread_idx][0] = 1'b1;
    item.elem_physical_addr[thread_idx][0].bank_id = thread_idx;
    item.elem_physical_addr[thread_idx][0].gid = m_gid;
    item.elem_physical_addr[thread_idx][0].baddr = m_baddr;
    item.validation_error_count = 0;
    return item;
  endfunction : make_synthetic_item

  function shmins_sequence_item shmins_ordered_batch_test::make_transport_item(string name);
    shmins_contiguous_sequence_item item;

    item = shmins_contiguous_sequence_item::type_id::create(name);
    if (!item.randomize() with {
          creq_rw == SHM_V2M;
          creq_dtype == DTYP_8;
          creq_atype_w == ATYP_16;
          creq_atype_s == ATYP_U;
          creq_atype_g == GAUTO_1B;
          creq_itype == LDST_S;
          creq_space == SPACE_LOC;
          creq_wpid == 0;
          creq_tmsk == 16'h0001;
          elem_num[0] == 1;
          creq_vmsk[0] == VEC_BYTE_N'(1);
        }) begin
      `uvm_fatal("SHM_ORDERED_BATCH_RANDOMIZE", $sformatf("failed to randomize %s", name))
    end
    return item;
  endfunction : make_transport_item

  function void shmins_ordered_batch_test::check_pair(string scenario,
                                                      shmins_sequence_item first_item,
                                                      shmins_sequence_item second_item,
                                                      bit expect_overlap,
                                                      int unsigned expected_count = 0);
    int unsigned overlap_count = first_item.unordered_cross_transaction_overlap_count(second_item);

    if ((overlap_count != 0) != expect_overlap ||
        (expect_overlap && expected_count != 0 && overlap_count != expected_count)) begin
      `uvm_fatal("SHM_ORDERED_HAZARD_MATRIX",
                 $sformatf("%s overlap=%0d expected_overlap=%0d expected_count=%0d\n%s",
                           scenario, overlap_count, expect_overlap, expected_count,
                           first_item.cross_transaction_overlap_sprint(second_item)))
    end
    `uvm_info("SHM_ORDERED_HAZARD_CELL", $sformatf("%s: PASS", scenario), UVM_LOW)
  endfunction : check_pair

  function bit shmins_ordered_batch_test::contains_text(string text, string fragment);
    if (fragment.len() == 0 || fragment.len() > text.len()) begin
      return fragment.len() == 0;
    end
    for (int index = 0; index <= text.len() - fragment.len(); index++) begin
      if (text.substr(index, index + fragment.len() - 1) == fragment) begin
        return 1'b1;
      end
    end
    return 1'b0;
  endfunction : contains_text

  task shmins_ordered_batch_test::send_batch(ref shmins_sequence_item items[$],
                                             input int unsigned delay_cycles);
    shm_directed_item_sequence batch_sequence;

    batch_sequence = shm_directed_item_sequence::type_id::create("batch_sequence");
    batch_sequence.set_requests(items, delay_cycles);
    batch_sequence.start(agent.sequencer);
  endtask : send_batch

  task shmins_ordered_batch_test::main_phase(uvm_phase phase);
    shmins_sequence_item a;
    shmins_sequence_item b;
    shmins_sequence_item items[$];
    shm_directed_item_sequence invalid_batch;
    string diagnostic;
    int unsigned observed_before;

    phase.raise_objection(this);
    wait (vif.rst_n === 1'b1);

    a = make_synthetic_item("haz001_a", SHM_M2V, DTYP_8, 0, 0, 'h100, 0, 'h200);
    b = make_synthetic_item("haz001_b", SHM_M2V, DTYP_8, 0, 0, 'h200, 0, 'h300);
    check_pair("ORDER-HAZ-001", a, b, 1'b1, 1);
    a = make_synthetic_item("haz002_a", SHM_M2V, DTYP_8, 0, 0, 'h100, 0, 'h300);
    b = make_synthetic_item("haz002_b", SHM_M2V, DTYP_8, 0, 0, 'h200, 0, 'h100);
    check_pair("ORDER-HAZ-002", a, b, 1'b1, 1);
    a = make_synthetic_item("haz003_a", SHM_M2V, DTYP_8, 0, 0, 'h100, 0, 'h200);
    b = make_synthetic_item("haz003_b", SHM_V2M, DTYP_8, 0, 0, 'h200, 0, 'h300);
    check_pair("ORDER-HAZ-003", a, b, 1'b1, 1);
    a = make_synthetic_item("haz004_a", SHM_V2M, DTYP_8, 0, 0, 'h100, 0, 'h300);
    b = make_synthetic_item("haz004_b", SHM_M2V, DTYP_8, 0, 0, 'h200, 0, 'h100);
    check_pair("ORDER-HAZ-004", a, b, 1'b1, 1);
    a = make_synthetic_item("haz005_a", SHM_M2V, DTYP_8, 0, 0, 'h100, 0, 'h300);
    b = make_synthetic_item("haz005_b", SHM_V2M, DTYP_8, 0, 0, 'h100, 0, 'h200);
    check_pair("ORDER-HAZ-005", a, b, 1'b0);
    a = make_synthetic_item("haz006_a", SHM_V2M, DTYP_8, 0, 0, 'h100, 0, 'h200);
    b = make_synthetic_item("haz006_b", SHM_V2M, DTYP_8, 0, 0, 'h100, 0, 'h300);
    check_pair("ORDER-HAZ-006", a, b, 1'b0);
    a = make_synthetic_item("haz007_a", SHM_M2V, DTYP_8, 0, 0, 'h100, 0, 'h300);
    b = make_synthetic_item("haz007_b", SHM_M2V, DTYP_8, 0, 0, 'h180, 0, 'h300);
    check_pair("ORDER-HAZ-007", a, b, 1'b0);
    a = make_synthetic_item("haz008_a", SHM_M2V, DTYP_8, 0, 0, 'h100, 0, 'h200);
    b = make_synthetic_item("haz008_b", SHM_V2M, DTYP_8, 0, 0, 'h201, 0, 'h300);
    check_pair("ORDER-HAZ-008", a, b, 1'b0);
    a = make_synthetic_item("haz009_a", SHM_M2V, DTYP_8, 0, 0, 'h100, 0, 'h200);
    b = make_synthetic_item("haz009_b", SHM_V2M, DTYP_8, 0, 1, 'h200, 1, 'h300);
    check_pair("ORDER-HAZ-009", a, b, 1'b0);
    a = make_synthetic_item("haz010_a", SHM_M2V, DTYP_16, 0, 0, 'h100, 0, 'h200);
    b = make_synthetic_item("haz010_b", SHM_V2M, DTYP_16, 0, 0, 'h201, 0, 'h300);
    check_pair("ORDER-HAZ-010", a, b, 1'b1, 1);
    if (!contains_text(a.cross_transaction_overlap_sprint(b), "BADDR=0x201")) begin
      `uvm_fatal("SHM_ORDERED_HAZARD_DIAGNOSTIC", "partial-byte diagnostic omitted BADDR=0x201")
    end

    items.delete();
    items.push_back(make_transport_item("seq001_0"));
    items.push_back(make_transport_item("seq001_1"));
    send_batch(items, 0);
    items.delete();
    items.push_back(make_transport_item("seq002_0"));
    items.push_back(make_transport_item("seq002_1"));
    items.push_back(make_transport_item("seq002_2"));
    send_batch(items, 1);
    repeat (20) begin
      if (sink.cycles.size() == 5) break;
      @(posedge vif.clk);
    end
    if (sink.cycles.size() != 5 || sink.cycles[1] != sink.cycles[0] + 1 ||
        sink.cycles[3] != sink.cycles[2] + 2 || sink.cycles[4] != sink.cycles[3] + 2) begin
      `uvm_fatal("SHM_ORDERED_SEQUENCE_CYCLES", $sformatf("unexpected accepted cycles: %p", sink.cycles))
    end

    observed_before = sink.cycles.size();
    items.delete();
    items.push_back(make_synthetic_item("seq003_a", SHM_M2V, DTYP_8, 0, 0, 'h100, 0, 'h200));
    items.push_back(make_synthetic_item("seq003_b", SHM_V2M, DTYP_8, 0, 0, 'h200, 0, 'h300));
    invalid_batch = shm_directed_item_sequence::type_id::create("invalid_batch");
    invalid_batch.set_requests(items, 0);
    if (invalid_batch.validate_batch(diagnostic) || !contains_text(diagnostic, "request pair [0,1]")) begin
      `uvm_fatal("SHM_ORDERED_SEQUENCE_ATOMIC", {"invalid batch was not rejected:\n", diagnostic})
    end
    repeat (2) @(posedge vif.clk);
    if (sink.cycles.size() != observed_before) begin
      `uvm_fatal("SHM_ORDERED_SEQUENCE_PARTIAL", "invalid batch published a partial request")
    end

    `uvm_info("SHMINS_ORDERED_BATCH_TEST", "ORDER-HAZ-001..010 and ORDER-SEQ-001..004: PASS", UVM_LOW)
    phase.drop_objection(this);
  endtask : main_phase
endpackage : shmins_ordered_batch_test_pkg

//------------------------------------------------------------------------------
// @brief Supplies clock, reset, and credit-return behavior to the component test.
//------------------------------------------------------------------------------
module shmins_ordered_batch_tb;
  import uvm_pkg::*;
  import shmins_ordered_batch_test_pkg::*;

  logic clk;
  logic rst_n;
  clk_if clk_vif(clk);
  shmins_interface vif(clk, rst_n);

  initial begin
    clk = 1'b0;
    forever #5ns clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    vif.creq_rls = 1'b0;
    vif.vack_done = 1'b0;
    vif.vack_id = '0;
    vif.mack_done = 1'b0;
    vif.mack_id = '0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual shmins_interface)::set(null, "uvm_test_top", "vif", vif);
    uvm_config_db#(virtual clk_if)::set(null, "uvm_test_top", "clk_vif", clk_vif);
    run_test("shmins_ordered_batch_test");
  end
endmodule : shmins_ordered_batch_tb
