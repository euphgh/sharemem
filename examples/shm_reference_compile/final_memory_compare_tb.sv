`timescale 1ns/1ps

package shm_final_memory_compare_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;
  import svt_uvm_pkg::*;
  import svt_mem_uvm_pkg::*;
  import shm_seq_item_package::*;
  import shm_env_package::*;

  `include "uvm_macros.svh"

  //----------------------------------------------------------------------------
  // @brief Verifies touched-byte final reference/actual memory comparison.
  //----------------------------------------------------------------------------
  class shm_final_memory_compare_test extends uvm_test;
    shm_environment_config cfg;
    shm_scoreboard scoreboard;
    shm_ordered_access_coverage ordered_coverage;
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
    extern protected function shm_wtrans_item make_order_item(
        string item_name,
        creq_rw_e direction,
        creq_dtype_e dtype,
        int unsigned thread_idx,
        shm_gid_t m_gid,
        shm_baddr_t m_baddr,
        shm_gid_t v_gid,
        shm_baddr_t v_baddr);
    extern protected function void check_order_coverage_pair(
        string scenario,
        shm_wtrans_item first_item,
        shm_wtrans_item second_item,
        int unsigned expected_kind,
        int unsigned expected_overlap,
        int unsigned expected_gid);

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
    ordered_coverage = shm_ordered_access_coverage::type_id::create("ordered_coverage", this);

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

  function shm_wtrans_item shm_final_memory_compare_test::make_order_item(
      string item_name,
      creq_rw_e direction,
      creq_dtype_e dtype,
      int unsigned thread_idx,
      shm_gid_t m_gid,
      shm_baddr_t m_baddr,
      shm_gid_t v_gid,
      shm_baddr_t v_baddr);
    shm_wtrans_item item;
    int unsigned byte_width;

    item = shm_wtrans_item::type_id::create(item_name);
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
    item.baddr_2d_array[thread_idx] = new[1];
    item.bid_2d_array[thread_idx] = new[1];
    item.gid_2d_array[thread_idx] = new[1];
    item.logical_addr_2d_array[thread_idx] = new[1];
    item.wstrb_2d_array[thread_idx] = new[1];
    item.baddr_2d_array[thread_idx][0] = m_baddr;
    item.bid_2d_array[thread_idx][0] = thread_idx;
    item.gid_2d_array[thread_idx][0] = m_gid;
    item.wstrb_2d_array[thread_idx][0] = byte'((1 << byte_width) - 1);
    return item;
  endfunction : make_order_item

  function void shm_final_memory_compare_test::check_order_coverage_pair(
      string scenario,
      shm_wtrans_item first_item,
      shm_wtrans_item second_item,
      int unsigned expected_kind,
      int unsigned expected_overlap,
      int unsigned expected_gid);
    longint unsigned before_count = ordered_coverage.observed_pair_count[expected_kind][expected_overlap];
    longint unsigned before_gid = ordered_coverage.observed_gid_count[expected_kind][expected_gid];
    longint unsigned before_converged = ordered_coverage.converged_pair_count;

    ordered_coverage.write(first_item);
    ordered_coverage.write(second_item);
    ordered_coverage.sample_final_result(1'b1);
    if (ordered_coverage.observed_pair_count[expected_kind][expected_overlap] != before_count + 1 ||
        ordered_coverage.observed_gid_count[expected_kind][expected_gid] != before_gid + 1 ||
        ordered_coverage.converged_pair_count != before_converged + 1) begin
      `uvm_fatal("SHM_ORDER_COVERAGE_COMPONENT",
                 $sformatf("%s did not increment kind=%0d overlap=%0d gid=%0d exactly once",
                           scenario, expected_kind, expected_overlap, expected_gid))
    end
    `uvm_info("SHM_ORDER_COVERAGE_CELL", {scenario, ": PASS"}, UVM_LOW)
  endfunction : check_order_coverage_pair

  task shm_final_memory_compare_test::main_phase(uvm_phase phase);
    shm_wtrans_item first_item;
    shm_wtrans_item second_item;

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

    for (int unsigned kind = 0; kind < 4; kind++) begin
      creq_rw_e first_direction;
      creq_rw_e second_direction;

      case (kind)
        0: begin first_direction = SHM_M2V; second_direction = SHM_V2M; end
        1: begin first_direction = SHM_V2M; second_direction = SHM_M2V; end
        2: begin first_direction = SHM_V2M; second_direction = SHM_V2M; end
        default: begin first_direction = SHM_M2V; second_direction = SHM_M2V; end
      endcase

      first_item = make_order_item($sformatf("order_cov_exact_first_%0d", kind),
                                   first_direction, DTYP_8, 0, 0, 'h200, 0, 'h300);
      second_item = make_order_item($sformatf("order_cov_exact_second_%0d", kind),
                                    second_direction, DTYP_8, 0, 0, 'h200, 0, 'h300);
      check_order_coverage_pair($sformatf("ORDER-COV-EXACT-%0d", kind), first_item, second_item,
                                kind, 0, 0);

      first_item = make_order_item($sformatf("order_cov_partial_first_%0d", kind),
                                   first_direction, DTYP_32, THD_N-1, 1, 'h400, 1, 'h500);
      second_item = make_order_item($sformatf("order_cov_partial_second_%0d", kind),
                                    second_direction, DTYP_16, THD_N-1, 1, 'h402, 1, 'h502);
      check_order_coverage_pair($sformatf("ORDER-COV-PARTIAL-%0d", kind), first_item, second_item,
                                kind, 1, 1);
    end

    `uvm_info("SHM_FINAL_MEMORY_COMPARE_TEST",
              "ORDER-SCB-001..005 and ORDER-COV exact/partial matrix: PASS", UVM_LOW)
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
