`timescale 1ns/1ps

package shmins_dual_gid_address_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
  `include "shmins_sequence_item.svh"
  `include "shmins_contiguous_sequence_item.svh"
  `include "shmins_strided_sequence_item.svh"
  `include "shmins_indexed_sequence_item.svh"
  `include "shmins_vtrans_sequence_item.svh"

  //----------------------------------------------------------------------------
  // @brief Checks dual-gid address conversion and reusable M2V byte hazards.
  //----------------------------------------------------------------------------
  class shmins_dual_gid_address_test extends uvm_test;
    //----------------------------------------------------------------------------
    // @brief Constructs the address component test.
    //
    // @param name UVM component instance name.
    // @param parent Parent component that owns this test.
    //----------------------------------------------------------------------------
    extern function new(string name = "shmins_dual_gid_address_test", uvm_component parent = null);

    //----------------------------------------------------------------------------
    // @brief Runs fixed logical conversion, VTRANS, and M2V hazard scenarios.
    //
    // @param phase UVM run phase controlling the test objection.
    //----------------------------------------------------------------------------
    extern virtual task run_phase(uvm_phase phase);

    //----------------------------------------------------------------------------
    // @brief Checks one logical-to-physical conversion against an independent formula.
    //
    // @param bank Source logical BANK.
    // @param warp Source absolute warp.
    // @param laddr Source warp-local byte address.
    //----------------------------------------------------------------------------
    extern protected function void check_logical_address(int unsigned bank,
                                                          int unsigned warp,
                                                          int unsigned laddr);

    //----------------------------------------------------------------------------
    // @brief Checks one contiguous space at a fixed low/high gid boundary wpid.
    //
    // @param space Address space selected for procedural MADDR generation.
    // @param wpid  Absolute warp expected in every active mapped element.
    //----------------------------------------------------------------------------
    extern protected function void check_contiguous_space_wpid(creq_space_e space, int unsigned wpid);

    `uvm_component_utils(shmins_dual_gid_address_test)
  endclass : shmins_dual_gid_address_test

  function shmins_dual_gid_address_test::new(string name = "shmins_dual_gid_address_test",
                                              uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  function void shmins_dual_gid_address_test::check_logical_address(int unsigned bank,
                                                                     int unsigned warp,
                                                                     int unsigned laddr);
    shm_logical_addr_t logical_addr;
    shm_physical_addr_t physical_addr;
    int unsigned expected_baddr;

    logical_addr.bank_id = shm_bank_id_t'(bank);
    logical_addr.warp_id = shm_warp_id_t'(warp);
    logical_addr.laddr = shm_warp_laddr_t'(laddr);
    if (!logical_to_physical_addr(logical_addr, physical_addr)) begin
      `uvm_fatal("SHMINS_DUAL_GID_VALID", $sformatf("valid logical address was rejected: %p", logical_addr))
    end
    expected_baddr = (warp % WARP_PER_GID) * WARP_STEP + laddr;
    if (int'(physical_addr.bank_id) != bank || int'(physical_addr.gid) != warp / WARP_PER_GID ||
        int'(physical_addr.baddr) != expected_baddr) begin
      `uvm_fatal("SHMINS_DUAL_GID_FORMULA",
                 $sformatf("bank=%0d warp=%0d laddr=%0d produced physical=%p expected gid=%0d baddr=0x%0h",
                           bank, warp, laddr, physical_addr, warp / WARP_PER_GID, expected_baddr))
    end
  endfunction : check_logical_address

  function void shmins_dual_gid_address_test::check_contiguous_space_wpid(
      creq_space_e space,
      int unsigned wpid);
    shmins_contiguous_sequence_item item;

    item = shmins_contiguous_sequence_item::type_id::create($sformatf("space_%0d_wpid_%0d", space, wpid));
    if (!item.randomize() with {
          creq_rw == SHM_V2M;
          creq_dtype == DTYP_8;
          creq_itype == LDST_S;
          creq_space == space;
          creq_wpid == wpid;
          creq_wpnum == 1;
          creq_tmsk == 16'h0001;
          elem_num[0] == 1;
          creq_vmsk[0][0] == 1'b1;
        }) begin
      `uvm_fatal("SHMINS_DUAL_GID_SPACE_RANDOMIZE",
                 $sformatf("failed to randomize space %0d wpid %0d", space, wpid))
    end
    if (item.elem_logical_addr[0][0].warp_id != wpid || item.elem_physical_addr[0][0].gid != wpid / 4) begin
      `uvm_fatal("SHMINS_DUAL_GID_SPACE_MAP",
                 $sformatf("space %0d wpid %0d mapped to logical warp %0d gid %0d", space, wpid,
                           item.elem_logical_addr[0][0].warp_id, item.elem_physical_addr[0][0].gid))
    end
  endfunction : check_contiguous_space_wpid

  task shmins_dual_gid_address_test::run_phase(uvm_phase phase);
    shmins_contiguous_sequence_item m2v_item;
    shmins_vtrans_sequence_item vtrans_low_item;
    shmins_vtrans_sequence_item vtrans_high_item;
    shm_logical_addr_t invalid_logical;
    shm_physical_addr_t physical_addr;
    bit found_overlap_candidate;
    int unsigned one_byte_overlap_candidate;
    int unsigned adjacent_candidate;
    int unsigned same_beat_candidate;
    int unsigned first_candidate;
    int unsigned last_candidate;

    phase.raise_objection(this);
    check_logical_address(0, 0, 0);
    check_logical_address(0, 3, WARP_STEP - 1);
    check_logical_address(0, 4, 0);
    check_logical_address(0, 7, WARP_STEP - 1);
    check_logical_address(BANK_N - 1, 0, WARP_STEP - 1);
    check_logical_address(BANK_N - 1, 3, 0);
    check_logical_address(BANK_N - 1, 4, WARP_STEP - 1);
    check_logical_address(BANK_N - 1, 7, 0);
    check_contiguous_space_wpid(SPACE_LOC, 3);
    check_contiguous_space_wpid(SPACE_LOC, 4);
    check_contiguous_space_wpid(SPACE_WRP, 3);
    check_contiguous_space_wpid(SPACE_WRP, 4);
    check_contiguous_space_wpid(SPACE_BLK, 3);
    check_contiguous_space_wpid(SPACE_BLK, 4);

    invalid_logical = '0;
    invalid_logical.laddr = shm_warp_laddr_t'(WARP_STEP);
    if (logical_to_physical_addr(invalid_logical, physical_addr)) begin
      `uvm_fatal("SHMINS_DUAL_GID_INVALID", "laddr==WARP_STEP was accepted")
    end

    vtrans_low_item = shmins_vtrans_sequence_item::type_id::create("vtrans_low_item");
    if (!vtrans_low_item.randomize() with {
          creq_dtype == DTYP_8;
          creq_itype == LDST_S;
          creq_wpid == 3;
        }) begin
      `uvm_fatal("SHMINS_DUAL_GID_VTRANS_LOW", "failed to randomize the wpid 3 VTRANS item")
    end
    foreach (vtrans_low_item.elem_physical_addr[thread_idx, elem_idx]) begin
      if (!vtrans_low_item.is_active_element(thread_idx, elem_idx)) begin
        continue;
      end
      if (vtrans_low_item.elem_physical_addr[thread_idx][elem_idx].gid != 0) begin
        `uvm_fatal("SHMINS_DUAL_GID_VTRANS_LOW",
                   $sformatf("wpid 3 thread %0d element %0d mapped to gid %0d", thread_idx, elem_idx,
                             vtrans_low_item.elem_physical_addr[thread_idx][elem_idx].gid))
      end
    end

    vtrans_high_item = shmins_vtrans_sequence_item::type_id::create("vtrans_high_item");
    if (!vtrans_high_item.randomize() with {
          creq_dtype == DTYP_8;
          creq_itype == LDST_S;
          creq_wpid == 4;
        }) begin
      `uvm_fatal("SHMINS_DUAL_GID_VTRANS_HIGH", "failed to randomize the wpid 4 VTRANS item")
    end
    foreach (vtrans_high_item.elem_physical_addr[thread_idx, elem_idx]) begin
      if (!vtrans_high_item.is_active_element(thread_idx, elem_idx)) begin
        continue;
      end
      if (vtrans_high_item.elem_physical_addr[thread_idx][elem_idx].gid != 1) begin
        `uvm_fatal("SHMINS_DUAL_GID_VTRANS_HIGH",
                   $sformatf("wpid 4 thread %0d element %0d mapped to gid %0d", thread_idx, elem_idx,
                             vtrans_high_item.elem_physical_addr[thread_idx][elem_idx].gid))
      end
    end

    m2v_item = shmins_contiguous_sequence_item::type_id::create("m2v_item");
    found_overlap_candidate = 1'b0;
    for (int unsigned attempt = 0; attempt < 256 && !found_overlap_candidate; attempt++) begin
      int unsigned read_baddr;
      int unsigned warp_base;
      int unsigned warp_end;

      if (!m2v_item.randomize() with {
            creq_rw == SHM_M2V;
            creq_dtype == DTYP_32;
            creq_itype == LDST_S;
            creq_space == SPACE_LOC;
            creq_wpid == 3;
            creq_tmsk == 16'h0001;
            elem_num[0] == 1;
            creq_vmsk[0][0] == 1'b1;
          }) begin
        `uvm_fatal("SHMINS_DUAL_GID_RANDOMIZE", "failed to randomize directed M2V item")
      end
      read_baddr = m2v_item.elem_physical_addr[0][0].baddr;
      warp_base = (int'(m2v_item.creq_wpid) % WARP_PER_GID) * WARP_STEP;
      warp_end = warp_base + WARP_STEP;
      first_candidate = warp_base;
      last_candidate = warp_end - VEC_BYTE_N;
      if (read_baddr < warp_base + 4 || read_baddr + VEC_BYTE_N > warp_end) begin
        continue;
      end
      one_byte_overlap_candidate = read_baddr - 3;
      adjacent_candidate = read_baddr - 4;
      same_beat_candidate = 0;
      for (int unsigned candidate = warp_base; candidate <= last_candidate; candidate++) begin
        if ((candidate >> 5) == (read_baddr >> 5) &&
            (candidate + m2v_item.data_byte_w() <= read_baddr ||
             read_baddr + m2v_item.data_byte_w() <= candidate)) begin
          same_beat_candidate = candidate;
          break;
        end
      end
      found_overlap_candidate = same_beat_candidate != 0 &&
                                m2v_item.legal_m2v_writeback_address(first_candidate) &&
                                m2v_item.legal_m2v_writeback_address(last_candidate);
    end
    if (!m2v_item.legal_m2v_writeback_address(m2v_item.creq_vaddr)) begin
      `uvm_fatal("SHMINS_DUAL_GID_GENERATED_VADDR", "generated M2V writeback failed the reusable predicate")
    end

    if (!found_overlap_candidate) begin
      `uvm_fatal("SHMINS_DUAL_GID_OVERLAP_CANDIDATE", "could not construct an in-range overlap candidate")
    end
    if (m2v_item.legal_m2v_writeback_address(m2v_item.elem_physical_addr[0][0].baddr)) begin
      `uvm_fatal("SHMINS_DUAL_GID_OVERLAP", "exact read/write byte overlap was accepted")
    end
    if (m2v_item.legal_m2v_writeback_address(one_byte_overlap_candidate)) begin
      `uvm_fatal("SHMINS_DUAL_GID_ONE_BYTE_OVERLAP", "one-byte read/write overlap was accepted")
    end
    if (!m2v_item.legal_m2v_writeback_address(adjacent_candidate)) begin
      `uvm_fatal("SHMINS_DUAL_GID_ADJACENT", "adjacent byte ranges were rejected")
    end
    if (!m2v_item.legal_m2v_writeback_address(same_beat_candidate)) begin
      `uvm_fatal("SHMINS_DUAL_GID_SAME_BEAT", "disjoint bytes in one 32-byte beat were rejected")
    end
    begin
      shm_gid_t original_read_gid = m2v_item.elem_physical_addr[0][0].gid;

      m2v_item.elem_physical_addr[0][0].gid = shm_gid_t'(1 - int'(original_read_gid));
      if (!m2v_item.legal_m2v_writeback_address(m2v_item.elem_physical_addr[0][0].baddr)) begin
        `uvm_fatal("SHMINS_DUAL_GID_DIFFERENT_GID", "equal BANK/BADDR in another gid was treated as overlap")
      end
      m2v_item.elem_physical_addr[0][0].gid = original_read_gid;
    end

    `uvm_info("SHMINS_DUAL_GID_ADDRESS_TEST", "dual-gid address and M2V byte-hazard component test: PASS", UVM_LOW)
    phase.drop_objection(this);
  endtask : run_phase
endpackage : shmins_dual_gid_address_test_pkg

module shmins_dual_gid_address_tb;
  import uvm_pkg::*;
  import shmins_dual_gid_address_test_pkg::*;

  initial begin
    run_test("shmins_dual_gid_address_test");
  end
endmodule : shmins_dual_gid_address_tb
