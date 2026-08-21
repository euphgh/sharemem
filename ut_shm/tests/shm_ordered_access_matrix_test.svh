`ifndef INC_SHM_ORDERED_ACCESS_MATRIX_TEST_SVH
`define INC_SHM_ORDERED_ACCESS_MATRIX_TEST_SVH

//------------------------------------------------------------------------------
// @brief Extends ordered-access checking across dtype, topology, space, and gid.
//
// Each simulation loads one complete matrix point from plusargs, sends one
// drained setup followed by one back-to-back target pair, and checks the
// architectural result and matching coverage counter. It does not constrain
// DUT reservation or MEM issue order.
//------------------------------------------------------------------------------
class shm_ordered_access_matrix_test extends shm_directed_base_test;
  // Fully validated description of the sole matrix point run by this test.
  shm_ordered_access_matrix_config matrix_cfg;

  //----------------------------------------------------------------------------
  // @brief Constructs the ordered-access extension test.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this test.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_ordered_access_matrix_test", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Runs the single matrix cell selected by required plusargs.
  //
  // @param phase UVM main phase whose objection protects the complete matrix.
  //----------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  //----------------------------------------------------------------------------
  // @brief Generates one two-active-element template for an exact-overlap cell.
  //
  // @param item_name UVM object instance name.
  // @param dtype Element width used by both target requests.
  // @param itype Address topology under test.
  // @param space Address-space mapping under test.
  // @param wpid Absolute WARP selector or BLK group selector.
  // @param wpnum Number of WARP entries encoded by SPACE_BLK.
  // @param thread_idx Sole active thread.
  // @return Legal M2V item with unique M-read bytes and two active elements.
  //----------------------------------------------------------------------------
  extern protected function shmins_sequence_item build_exact_template(
      string item_name,
      creq_dtype_e dtype,
      creq_itype_e itype,
      creq_space_e space,
      int unsigned wpid,
      int unsigned wpnum,
      int unsigned thread_idx);

  //----------------------------------------------------------------------------
  // @brief Clones one production item while preserving its dynamic topology.
  //
  // @param item_name Name assigned to the cloned item.
  // @param source Fully generated source item.
  // @return Independent item with identical addresses and control state.
  //----------------------------------------------------------------------------
  extern protected function shmins_sequence_item clone_directed_item(
      string item_name,
      shmins_sequence_item source);

  //----------------------------------------------------------------------------
  // @brief Sets direction and deterministic active-element payload bytes.
  //
  // @param item Generated item to update and revalidate.
  // @param direction V2M or M2V direction.
  // @param data_base First deterministic V2M payload byte.
  // @post Packed type and validation state match the updated transaction.
  //----------------------------------------------------------------------------
  extern protected function void prepare_item(shmins_sequence_item item,
                                               creq_rw_e direction,
                                               byte unsigned data_base);

  //----------------------------------------------------------------------------
  // @brief Counts physical M-side byte overlap between two generated items.
  //
  // @param first_item First item whose active M bytes are inspected.
  // @param second_item Second item whose active M bytes are inspected.
  // @return Number of byte addresses present in both items.
  //----------------------------------------------------------------------------
  extern protected function int unsigned m_access_overlap_count(
      shmins_sequence_item first_item,
      shmins_sequence_item second_item);

  //----------------------------------------------------------------------------
  // @brief Checks all active M-side bytes against the deterministic payload.
  //
  // @param label Stable matrix-cell diagnostic label.
  // @param item Item supplying active physical M addresses.
  // @param data_base Payload base previously passed to prepare_item().
  //----------------------------------------------------------------------------
  extern protected function void check_m_payload(string label,
                                                  shmins_sequence_item item,
                                                  byte unsigned data_base);

  //----------------------------------------------------------------------------
  // @brief Checks all active M2V V-write bytes against expected source data.
  //
  // @param label Stable matrix-cell diagnostic label.
  // @param item M2V item supplying V-write addresses and element layout.
  // @param data_base Expected source payload base.
  //----------------------------------------------------------------------------
  extern protected function void check_v_payload(string label,
                                                  shmins_sequence_item item,
                                                  byte unsigned data_base);

  //----------------------------------------------------------------------------
  // @brief Executes one exact-overlap ordered relation with two active elements.
  //
  // @param label Stable cell name used in reports.
  // @param order_kind One of the four RTL-guaranteed relations.
  // @param dtype Common target-item dtype.
  // @param itype Common target-item topology.
  // @param space Common target-item address space.
  // @param wpid Absolute WARP selector or BLK group selector.
  // @param wpnum Number of WARP entries encoded by SPACE_BLK.
  // @param thread_idx Sole active thread.
  //----------------------------------------------------------------------------
  extern protected task run_exact_cell(string label,
                                       shm_ordered_access_kind_e order_kind,
                                       creq_dtype_e dtype,
                                       creq_itype_e itype,
                                       creq_space_e space,
                                       int unsigned wpid,
                                       int unsigned wpnum,
                                       int unsigned thread_idx);

  //----------------------------------------------------------------------------
  // @brief Executes one mixed-DTYPE partial-overlap relation.
  //
  // @param label Stable cell name used in reports.
  // @param order_kind One of the four RTL-guaranteed relations.
  // @param first_dtype DTYPE of the earlier target transaction.
  // @param second_dtype DTYPE of the later target transaction.
  // @param itype Common contiguous ITYPE.
  // @param space Common LOC address space.
  // @param wpid Absolute WARP selector.
  // @param wpnum Number of WARP entries; one for the supported LOC profile.
  // @param thread_idx Sole active thread.
  // @param maddr_base Four-byte-aligned LOC MADDR used by the first request.
  // @param vaddr_base Four-byte-aligned writeback BADDR in the selected gid.
  //----------------------------------------------------------------------------
  extern protected task run_partial_cell(string label,
                                         shm_ordered_access_kind_e order_kind,
                                         creq_dtype_e first_dtype,
                                         creq_dtype_e second_dtype,
                                         creq_itype_e itype,
                                         creq_space_e space,
                                         int unsigned wpid,
                                         int unsigned wpnum,
                                         int unsigned thread_idx,
                                         longint unsigned maddr_base,
                                         int unsigned vaddr_base);

  //----------------------------------------------------------------------------
  // @brief Executes configured VTRANS followed by an overlapping normal V2M.
  //
  // @param label Stable cell name used in reports.
  // @param dtype Common DTYPE of the VTRANS and normal V2M transactions.
  // @param itype Common contiguous ITYPE.
  // @param wpid Absolute WARP selector.
  // @param thread_idx Thread whose VTRANS element is overwritten.
  //----------------------------------------------------------------------------
  extern protected task run_vtrans_m_write_cell(string label,
                                                creq_dtype_e dtype,
                                                creq_itype_e itype,
                                                int unsigned wpid,
                                                int unsigned thread_idx);

  `uvm_component_utils(shm_ordered_access_matrix_test)
endclass : shm_ordered_access_matrix_test

function shm_ordered_access_matrix_test::new(string name = "shm_ordered_access_matrix_test",
                                             uvm_component parent = null);
  super.new(name, parent);
endfunction : new

function shmins_sequence_item shm_ordered_access_matrix_test::build_exact_template(
    string item_name,
    creq_dtype_e dtype,
    creq_itype_e itype,
    creq_space_e space,
    int unsigned wpid,
    int unsigned wpnum,
    int unsigned thread_idx);
  shmins_sequence_item item;
  logic [THD_N-1:0] active_tmsk;
  logic [VEC_BYTE_N-1:0] active_vmsk;
  int unsigned element_count;

  case (itype)
    LDST_S, LDST_V: item = shmins_contiguous_sequence_item::type_id::create(item_name);
    LDSTE_S: item = shmins_strided_sequence_item::type_id::create(item_name);
    LDSTE_V: item = shmins_indexed_sequence_item::type_id::create(item_name);
    default: item = null;
  endcase
  if (item == null || thread_idx >= THD_N) begin
    `uvm_fatal("SHM_ORDER_MATRIX_TEMPLATE_ARGUMENT",
               $sformatf("%s itype=%0d thread=%0d", item_name, itype, thread_idx))
  end

  active_tmsk = '0;
  active_tmsk[thread_idx] = 1'b1;
  active_vmsk = '0;
  if (itype == LDSTE_S && space inside {SPACE_WRP, SPACE_BLK}) begin
    element_count = 3;
    active_vmsk[2:1] = 2'b11;
  end else begin
    element_count = 2;
    active_vmsk[1:0] = 2'b11;
  end

  item.m2v_unique_enable = 1'b1;
  if (!item.randomize() with {
        creq_rw == SHM_M2V;
        creq_dtype == local::dtype;
        creq_atype_w == ATYP_32;
        creq_atype_s == ATYP_U;
        creq_atype_g == GAUTO_1B;
        creq_itype == local::itype;
        creq_space == local::space;
        creq_wpid == local::wpid;
        creq_wpnum == local::wpnum;
        creq_inv_size == 4;
        creq_ack_en == 1'b1;
        creq_tmsk == local::active_tmsk;
        delay_cycle == 0;
        foreach (elem_num[index]) {
          if (index == local::thread_idx) elem_num[index] == local::element_count;
          else elem_num[index] == 0;
        }
        foreach (creq_vmsk[index]) {
          if (index == local::thread_idx) creq_vmsk[index] == local::active_vmsk;
          else creq_vmsk[index] == '0;
        }
      }) begin
    `uvm_fatal("SHM_ORDER_MATRIX_TEMPLATE_RANDOMIZE",
               $sformatf("%s dtype=%0d itype=%0d space=%0d", item_name, dtype, itype, space))
  end
  return item;
endfunction : build_exact_template

function shmins_sequence_item shm_ordered_access_matrix_test::clone_directed_item(
    string item_name,
    shmins_sequence_item source);
  uvm_object cloned_object;
  shmins_sequence_item cloned_item;

  if (source == null) begin
    `uvm_fatal("SHM_ORDER_MATRIX_CLONE_NULL", $sformatf("cannot clone %s from null", item_name))
  end
  cloned_object = source.clone();
  if (!$cast(cloned_item, cloned_object)) begin
    `uvm_fatal("SHM_ORDER_MATRIX_CLONE_CAST", $sformatf("failed to clone %s", item_name))
  end
  cloned_item.set_name(item_name);
  return cloned_item;
endfunction : clone_directed_item

function void shm_ordered_access_matrix_test::prepare_item(shmins_sequence_item item,
                                                           creq_rw_e direction,
                                                           byte unsigned data_base);
  item.creq_rw = direction;
  item.creq_ack_en = 1'b1;
  item.delay_cycle = 0;
  foreach (item.creq_vdat[thread_idx]) begin
    item.creq_vdat[thread_idx] = '0;
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    for (int unsigned elem_idx = 0; elem_idx < item.thread_elem_cnt(thread_idx); elem_idx++) begin
      if (!item.is_active_element(thread_idx, elem_idx)) begin
        continue;
      end
      for (int unsigned byte_lane = 0; byte_lane < item.data_byte_w(); byte_lane++) begin
        item.creq_vdat[thread_idx][elem_idx * item.data_byte_w() + byte_lane] =
            byte'(data_base + elem_idx * 8 + byte_lane);
      end
    end
  end
  if (direction == SHM_M2V && !item.legal_m2v_writeback_address(item.creq_vaddr)) begin
    `uvm_fatal("SHM_ORDER_MATRIX_VADDR", $sformatf("%s has illegal vaddr 0x%0h", item.get_name(),
                                                    item.creq_vaddr))
  end
  item.validate_transaction();
  item.item_to_rtl();
endfunction : prepare_item

function int unsigned shm_ordered_access_matrix_test::m_access_overlap_count(
    shmins_sequence_item first_item,
    shmins_sequence_item second_item);
  bit first_keys[longint unsigned];
  bit second_keys[longint unsigned];
  int unsigned overlap_count = 0;

  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    for (int unsigned elem_idx = 0; elem_idx < first_item.thread_elem_cnt(thread_idx); elem_idx++) begin
      if (!first_item.is_active_element(thread_idx, elem_idx)) begin
        continue;
      end
      for (int unsigned byte_lane = 0; byte_lane < first_item.data_byte_w(); byte_lane++) begin
        shm_physical_addr_t physical_addr = first_item.elem_physical_addr[thread_idx][elem_idx];

        physical_addr.baddr += shm_baddr_t'(byte_lane);
        first_keys[first_item.make_physical_byte_key(physical_addr)] = 1'b1;
      end
    end
    for (int unsigned elem_idx = 0; elem_idx < second_item.thread_elem_cnt(thread_idx); elem_idx++) begin
      if (!second_item.is_active_element(thread_idx, elem_idx)) begin
        continue;
      end
      for (int unsigned byte_lane = 0; byte_lane < second_item.data_byte_w(); byte_lane++) begin
        shm_physical_addr_t physical_addr = second_item.elem_physical_addr[thread_idx][elem_idx];

        physical_addr.baddr += shm_baddr_t'(byte_lane);
        second_keys[second_item.make_physical_byte_key(physical_addr)] = 1'b1;
      end
    end
  end
  foreach (first_keys[key]) begin
    overlap_count += second_keys.exists(key);
  end
  return overlap_count;
endfunction : m_access_overlap_count

function void shm_ordered_access_matrix_test::check_m_payload(string label,
                                                              shmins_sequence_item item,
                                                              byte unsigned data_base);
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    for (int unsigned elem_idx = 0; elem_idx < item.thread_elem_cnt(thread_idx); elem_idx++) begin
      if (!item.is_active_element(thread_idx, elem_idx)) begin
        continue;
      end
      for (int unsigned byte_lane = 0; byte_lane < item.data_byte_w(); byte_lane++) begin
        shm_physical_addr_t physical_addr = item.elem_physical_addr[thread_idx][elem_idx];

        physical_addr.baddr += shm_baddr_t'(byte_lane);
        check_final_memory_byte(label, physical_addr,
                                byte'(data_base + elem_idx * 8 + byte_lane));
      end
    end
  end
endfunction : check_m_payload

function void shm_ordered_access_matrix_test::check_v_payload(string label,
                                                              shmins_sequence_item item,
                                                              byte unsigned data_base);
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    for (int unsigned elem_idx = 0; elem_idx < item.thread_elem_cnt(thread_idx); elem_idx++) begin
      if (!item.is_active_element(thread_idx, elem_idx)) begin
        continue;
      end
      for (int unsigned byte_lane = 0; byte_lane < item.data_byte_w(); byte_lane++) begin
        shm_physical_addr_t physical_addr;

        physical_addr.bank_id = shm_bank_id_t'(thread_idx);
        physical_addr.gid = shm_gid_t'(int'(item.creq_wpid) / WARP_PER_GID);
        physical_addr.baddr = shm_baddr_t'(int'(item.creq_vaddr) +
                                                   elem_idx * item.data_byte_w() + byte_lane);
        check_final_memory_byte(label, physical_addr,
                                byte'(data_base + elem_idx * 8 + byte_lane));
      end
    end
  end
endfunction : check_v_payload

task shm_ordered_access_matrix_test::run_exact_cell(string label,
                                                    shm_ordered_access_kind_e order_kind,
                                                    creq_dtype_e dtype,
                                                    creq_itype_e itype,
                                                    creq_space_e space,
                                                    int unsigned wpid,
                                                    int unsigned wpnum,
                                                    int unsigned thread_idx);
  localparam byte unsigned FIRST_DATA = 8'h24;
  localparam byte unsigned SECOND_DATA = 8'hb0;
  shmins_sequence_item template_item;
  shmins_sequence_item first_item;
  shmins_sequence_item second_item;
  shmins_sequence_item setup_items[$];
  shmins_sequence_item target_items[$];

  template_item = build_exact_template({label, "_template"}, dtype, itype, space,
                                       wpid, wpnum, thread_idx);
  case (order_kind)
    MATRIX_M_READ_THEN_WRITE: begin
      shmins_sequence_item setup_item = clone_directed_item({label, "_setup"}, template_item);

      first_item = clone_directed_item({label, "_read"}, template_item);
      second_item = clone_directed_item({label, "_write"}, template_item);
      prepare_item(setup_item, SHM_V2M, FIRST_DATA);
      prepare_item(first_item, SHM_M2V, '0);
      prepare_item(second_item, SHM_V2M, SECOND_DATA);
      setup_items.push_back(setup_item);
      send_directed_items(setup_items, 0);
      shm_env.wait_for_idle();
      shm_env.check_final_memory({label, " setup"});
    end
    MATRIX_M_WRITE_THEN_READ: begin
      first_item = clone_directed_item({label, "_write"}, template_item);
      second_item = clone_directed_item({label, "_read"}, template_item);
      prepare_item(first_item, SHM_V2M, SECOND_DATA);
      prepare_item(second_item, SHM_M2V, '0);
    end
    MATRIX_M_WRITE_THEN_WRITE: begin
      first_item = clone_directed_item({label, "_first"}, template_item);
      second_item = clone_directed_item({label, "_second"}, template_item);
      prepare_item(first_item, SHM_V2M, FIRST_DATA);
      prepare_item(second_item, SHM_V2M, SECOND_DATA);
    end
    MATRIX_V_WRITE_THEN_WRITE: begin
      bit second_ready = 1'b0;

      first_item = clone_directed_item({label, "_read_first"}, template_item);
      for (int unsigned attempt = 0; attempt < 64 && !second_ready; attempt++) begin
        second_item = build_exact_template($sformatf("%s_read_second_%0d", label, attempt),
                                           dtype, itype, space, wpid, wpnum, thread_idx);
        second_item.creq_vaddr = first_item.creq_vaddr;
        second_ready = second_item.legal_m2v_writeback_address(second_item.creq_vaddr) &&
                       m_access_overlap_count(first_item, second_item) == 0 &&
                       !first_item.has_unordered_cross_transaction_overlap(second_item);
      end
      if (!second_ready) begin
        `uvm_fatal("SHM_ORDER_MATRIX_VWRITE_SOURCE",
                   $sformatf("%s could not generate disjoint M-read sources", label))
      end
      begin
        shmins_sequence_item setup_first = clone_directed_item({label, "_setup_first"}, first_item);
        shmins_sequence_item setup_second = clone_directed_item({label, "_setup_second"}, second_item);

        prepare_item(setup_first, SHM_V2M, FIRST_DATA);
        prepare_item(setup_second, SHM_V2M, SECOND_DATA);
        prepare_item(first_item, SHM_M2V, '0);
        prepare_item(second_item, SHM_M2V, '0);
        setup_items.push_back(setup_first);
        setup_items.push_back(setup_second);
        send_directed_items(setup_items, 0);
        shm_env.wait_for_idle();
        shm_env.check_final_memory({label, " setup"});
      end
    end
    default: `uvm_fatal("SHM_ORDER_MATRIX_KIND", $sformatf("%s kind=%0d", label, order_kind))
  endcase

  target_items.push_back(first_item);
  target_items.push_back(second_item);
  send_directed_items(target_items, 0);
  shm_env.wait_for_idle();
  shm_env.check_final_memory({label, " target"});

  case (order_kind)
    MATRIX_M_READ_THEN_WRITE: begin
      check_m_payload({label, " M"}, second_item, SECOND_DATA);
      check_v_payload({label, " V"}, first_item, FIRST_DATA);
    end
    MATRIX_M_WRITE_THEN_READ: begin
      check_m_payload({label, " M"}, first_item, SECOND_DATA);
      check_v_payload({label, " V"}, second_item, SECOND_DATA);
    end
    MATRIX_M_WRITE_THEN_WRITE: check_m_payload({label, " M"}, second_item, SECOND_DATA);
    MATRIX_V_WRITE_THEN_WRITE: check_v_payload({label, " V"}, second_item, SECOND_DATA);
    default: begin end
  endcase
  `uvm_info("SHM_ORDERED_MATRIX_CELL", {label, ": PASS"}, UVM_LOW)
endtask : run_exact_cell

task shm_ordered_access_matrix_test::run_partial_cell(string label,
                                                      shm_ordered_access_kind_e order_kind,
                                                      creq_dtype_e first_dtype,
                                                      creq_dtype_e second_dtype,
                                                      creq_itype_e itype,
                                                      creq_space_e space,
                                                      int unsigned wpid,
                                                      int unsigned wpnum,
                                                      int unsigned thread_idx,
                                                      longint unsigned maddr_base,
                                                      int unsigned vaddr_base);
  localparam logic [31:0] FIRST_VALUE = 32'h44332211;
  localparam logic [15:0] SECOND_VALUE = 16'hbbaa;
  shmins_sequence_item first_item;
  shmins_sequence_item second_item;
  shmins_sequence_item setup_items[$];
  shmins_sequence_item target_items[$];

  case (order_kind)
    MATRIX_M_READ_THEN_WRITE: begin
      shmins_sequence_item setup_item;

      setup_item = build_single_element_item({label, "_setup"}, SHM_V2M, first_dtype, itype,
                                             space, wpid, wpnum, 0, thread_idx, maddr_base,
                                             -1, FIRST_VALUE);
      first_item = build_single_element_item({label, "_read"}, SHM_M2V, first_dtype, itype,
                                             space, wpid, wpnum, 0, thread_idx, maddr_base,
                                             vaddr_base, '0);
      second_item = build_single_element_item({label, "_write"}, SHM_V2M, second_dtype, itype,
                                              space, wpid, wpnum, 0, thread_idx, maddr_base + 2,
                                              -1, SECOND_VALUE);
      setup_items.push_back(setup_item);
      send_directed_items(setup_items, 0);
      shm_env.wait_for_idle();
      shm_env.check_final_memory({label, " setup"});
    end
    MATRIX_M_WRITE_THEN_READ: begin
      first_item = build_single_element_item({label, "_write"}, SHM_V2M, first_dtype, itype,
                                             space, wpid, wpnum, 0, thread_idx, maddr_base,
                                             -1, FIRST_VALUE);
      second_item = build_single_element_item({label, "_read"}, SHM_M2V, second_dtype, itype,
                                              space, wpid, wpnum, 0, thread_idx, maddr_base + 2,
                                              vaddr_base, '0);
    end
    MATRIX_M_WRITE_THEN_WRITE: begin
      first_item = build_single_element_item({label, "_first"}, SHM_V2M, first_dtype, itype,
                                             space, wpid, wpnum, 0, thread_idx, maddr_base,
                                             -1, FIRST_VALUE);
      second_item = build_single_element_item({label, "_second"}, SHM_V2M, second_dtype, itype,
                                              space, wpid, wpnum, 0, thread_idx, maddr_base + 2,
                                              -1, SECOND_VALUE);
    end
    MATRIX_V_WRITE_THEN_WRITE: begin
      shmins_sequence_item setup_first;
      shmins_sequence_item setup_second;

      setup_first = build_single_element_item({label, "_setup_first"}, SHM_V2M, first_dtype, itype,
                                              space, wpid, wpnum, 0, thread_idx, maddr_base,
                                              -1, FIRST_VALUE);
      setup_second = build_single_element_item({label, "_setup_second"}, SHM_V2M, second_dtype,
                                               itype, space, wpid, wpnum, 0, thread_idx,
                                               maddr_base + 'h40,
                                               -1, SECOND_VALUE);
      first_item = build_single_element_item({label, "_read_first"}, SHM_M2V, first_dtype, itype,
                                             space, wpid, wpnum, 0, thread_idx, maddr_base,
                                             vaddr_base, '0);
      second_item = build_single_element_item({label, "_read_second"}, SHM_M2V, second_dtype,
                                              itype, space, wpid, wpnum, 0, thread_idx,
                                              maddr_base + 'h40,
                                              vaddr_base + 2, '0);
      setup_items.push_back(setup_first);
      setup_items.push_back(setup_second);
      send_directed_items(setup_items, 0);
      shm_env.wait_for_idle();
      shm_env.check_final_memory({label, " setup"});
    end
    default: `uvm_fatal("SHM_ORDER_MATRIX_PARTIAL_KIND", $sformatf("%s kind=%0d", label, order_kind))
  endcase

  target_items.push_back(first_item);
  target_items.push_back(second_item);
  send_directed_items(target_items, 0);
  shm_env.wait_for_idle();
  shm_env.check_final_memory({label, " target"});

  case (order_kind)
    MATRIX_M_READ_THEN_WRITE, MATRIX_M_WRITE_THEN_WRITE: begin
      shm_physical_addr_t physical_addr = first_item.elem_physical_addr[thread_idx][0];
      logic [31:0] expected_value = 32'hbbaa2211;

      for (int unsigned byte_lane = 0; byte_lane < 4; byte_lane++) begin
        shm_physical_addr_t byte_addr = physical_addr;

        byte_addr.baddr += shm_baddr_t'(byte_lane);
        check_final_memory_byte({label, " M"}, byte_addr, expected_value[byte_lane * 8 +: 8]);
      end
      if (order_kind == MATRIX_M_READ_THEN_WRITE) begin
        shm_physical_addr_t vaddr;

        vaddr.bank_id = thread_idx;
        vaddr.gid = shm_gid_t'(wpid / WARP_PER_GID);
        vaddr.baddr = shm_baddr_t'(vaddr_base);
        for (int unsigned byte_lane = 0; byte_lane < 4; byte_lane++) begin
          shm_physical_addr_t byte_addr = vaddr;

          byte_addr.baddr += shm_baddr_t'(byte_lane);
          check_final_memory_byte({label, " V"}, byte_addr, FIRST_VALUE[byte_lane * 8 +: 8]);
        end
      end
    end
    MATRIX_M_WRITE_THEN_READ: begin
      begin
        shm_physical_addr_t maddr = first_item.elem_physical_addr[thread_idx][0];
        shm_physical_addr_t vaddr;
        logic [31:0] m_expected = FIRST_VALUE;
        logic [15:0] expected_value = 16'h4433;

        for (int unsigned byte_lane = 0; byte_lane < 4; byte_lane++) begin
          shm_physical_addr_t byte_addr = maddr;

          byte_addr.baddr += shm_baddr_t'(byte_lane);
          check_final_memory_byte({label, " M"}, byte_addr, m_expected[byte_lane * 8 +: 8]);
        end
        vaddr.bank_id = thread_idx;
        vaddr.gid = shm_gid_t'(wpid / WARP_PER_GID);
        vaddr.baddr = shm_baddr_t'(vaddr_base);
        for (int unsigned byte_lane = 0; byte_lane < 2; byte_lane++) begin
          shm_physical_addr_t byte_addr = vaddr;

          byte_addr.baddr += shm_baddr_t'(byte_lane);
          check_final_memory_byte({label, " V"}, byte_addr, expected_value[byte_lane * 8 +: 8]);
        end
      end
    end
    MATRIX_V_WRITE_THEN_WRITE: begin
      shm_physical_addr_t vaddr;
      logic [31:0] expected_value = 32'hbbaa2211;

      vaddr.bank_id = thread_idx;
      vaddr.gid = shm_gid_t'(wpid / WARP_PER_GID);
      vaddr.baddr = shm_baddr_t'(vaddr_base);
      for (int unsigned byte_lane = 0; byte_lane < 4; byte_lane++) begin
        shm_physical_addr_t byte_addr = vaddr;

        byte_addr.baddr += shm_baddr_t'(byte_lane);
        check_final_memory_byte({label, " V"}, byte_addr, expected_value[byte_lane * 8 +: 8]);
      end
    end
    default: begin end
  endcase
  `uvm_info("SHM_ORDERED_MATRIX_CELL", {label, ": PASS"}, UVM_LOW)
endtask : run_partial_cell

task shm_ordered_access_matrix_test::run_vtrans_m_write_cell(string label,
                                                            creq_dtype_e dtype,
                                                            creq_itype_e itype,
                                                            int unsigned wpid,
                                                            int unsigned thread_idx);
  localparam int unsigned TARGET_ELEMENT = 15;
  localparam logic [15:0] SECOND_VALUE = 16'h9f9e;
  shmins_vtrans_sequence_item vtrans_item;
  shmins_sequence_item normal_item;
  shmins_sequence_item target_items[$];
  longint unsigned target_maddr;

  vtrans_item = shmins_vtrans_sequence_item::type_id::create("order_ext_vtrans_first");
  if (!vtrans_item.randomize() with {
        creq_dtype == local::dtype;
        creq_atype_w == ATYP_32;
        creq_atype_s == ATYP_U;
        creq_atype_g == GAUTO_1B;
        creq_itype == local::itype;
        creq_wpid == local::wpid;
        creq_ack_en == 1'b1;
        delay_cycle == 0;
      }) begin
    `uvm_fatal("SHM_ORDER_MATRIX_VTRANS_RANDOMIZE", "failed to build VTRANS extension cell")
  end
  vtrans_item.creq_vdat[TARGET_ELEMENT][thread_idx * 2] = 8'h5a;
  vtrans_item.creq_vdat[TARGET_ELEMENT][thread_idx * 2 + 1] = 8'ha5;
  vtrans_item.item_to_rtl();
  target_maddr = vtrans_item.elem_maddr[thread_idx][TARGET_ELEMENT];

  normal_item = build_single_element_item("order_ext_vtrans_second", SHM_V2M, dtype, itype,
                                          SPACE_LOC, wpid, 1, 0, thread_idx, target_maddr,
                                          -1, SECOND_VALUE);
  target_items.push_back(vtrans_item);
  target_items.push_back(normal_item);
  send_directed_items(target_items, 0);
  shm_env.wait_for_idle();
  shm_env.check_final_memory({label, " target"});
  check_m_payload({label, " M"}, normal_item, 8'h9e);
  `uvm_info("SHM_ORDERED_MATRIX_CELL", {label, ": PASS"}, UVM_LOW)
endtask : run_vtrans_m_write_cell

task shm_ordered_access_matrix_test::main_phase(uvm_phase phase);
  int unsigned order_index;
  int unsigned overlap_index;
  int unsigned expected_gid;
  int unsigned vaddr_base;

  phase.raise_objection(this);
  wait (shm_env.shmins_vif.rst_n === 1'b1);

  matrix_cfg = shm_ordered_access_matrix_config::type_id::create("matrix_cfg");
  matrix_cfg.load_plusargs();
  `uvm_info("SHM_ORDER_MATRIX_CONFIG", matrix_cfg.configuration_sprint(), UVM_LOW)
  if (shm_env.ordered_access_coverage == null) begin
    `uvm_fatal("SHM_ORDER_MATRIX_NO_COVERAGE", "ordered-access coverage collector is missing")
  end

  order_index = int'(matrix_cfg.order_kind);
  overlap_index = int'(matrix_cfg.overlap_class);
  expected_gid = matrix_cfg.expected_gid();
  vaddr_base = (matrix_cfg.wpid % WARP_PER_GID) * WARP_STEP + 'h1000;

  if (matrix_cfg.first_is_vtrans) begin
    run_vtrans_m_write_cell(matrix_cfg.cell_name, matrix_cfg.first_dtype, matrix_cfg.itype,
                            matrix_cfg.wpid, matrix_cfg.thread_idx);
  end else if (matrix_cfg.overlap_class == MATRIX_OVERLAP_EXACT) begin
    run_exact_cell(matrix_cfg.cell_name, matrix_cfg.order_kind, matrix_cfg.first_dtype,
                   matrix_cfg.itype, matrix_cfg.space, matrix_cfg.wpid, matrix_cfg.wpnum,
                   matrix_cfg.thread_idx);
  end else begin
    run_partial_cell(matrix_cfg.cell_name, matrix_cfg.order_kind, matrix_cfg.first_dtype,
                     matrix_cfg.second_dtype, matrix_cfg.itype, matrix_cfg.space,
                     matrix_cfg.wpid, matrix_cfg.wpnum, matrix_cfg.thread_idx, 'h400,
                     vaddr_base);
  end

  if (shm_env.ordered_access_coverage.observed_pair_count[order_index][overlap_index] != 1) begin
    `uvm_fatal("SHM_ORDER_MATRIX_COVERAGE_CELL",
               $sformatf("%s observed kind=%0d overlap=%0d count=%0d, expected 1",
                         matrix_cfg.cell_name, order_index, overlap_index,
                         shm_env.ordered_access_coverage.observed_pair_count[order_index][overlap_index]))
  end
  if (shm_env.ordered_access_coverage.observed_gid_count[order_index][expected_gid] != 1) begin
    `uvm_fatal("SHM_ORDER_MATRIX_COVERAGE_GID",
               $sformatf("%s observed kind=%0d gid=%0d count=%0d, expected 1",
                         matrix_cfg.cell_name, order_index, expected_gid,
                         shm_env.ordered_access_coverage.observed_gid_count[order_index][expected_gid]))
  end
  if (shm_env.ordered_access_coverage.converged_pair_count != 1 ||
      shm_env.ordered_access_coverage.failed_final_check_count != 0) begin
    `uvm_fatal("SHM_ORDER_MATRIX_CONVERGENCE",
               $sformatf("%s converged=%0d failed_final=%0d, expected 1/0",
                         matrix_cfg.cell_name,
                         shm_env.ordered_access_coverage.converged_pair_count,
                         shm_env.ordered_access_coverage.failed_final_check_count))
  end
  `uvm_info("SHM_ORDERED_ACCESS_MATRIX_TEST",
            $sformatf("%s: PASS, converged_pairs=%0d", matrix_cfg.cell_name,
                      shm_env.ordered_access_coverage.converged_pair_count),
            UVM_LOW)
  phase.drop_objection(this);
endtask : main_phase

`endif // INC_SHM_ORDERED_ACCESS_MATRIX_TEST_SVH
