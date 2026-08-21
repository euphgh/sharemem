`ifndef INC_SHM_DIRECTED_BASE_TEST_SVH
`define INC_SHM_DIRECTED_BASE_TEST_SVH

//------------------------------------------------------------------------------
// @brief Provides deterministic single-element builders for real-DUT tests.
//
// Derived tests use the production contiguous item, address mapper, validator,
// driver, reference, and scoreboard. The builder fixes every address-affecting
// field and never relies on a random seed to reach a directed boundary.
//------------------------------------------------------------------------------
class shm_directed_base_test extends shm_base_test;

  //----------------------------------------------------------------------------
  // @brief Constructs a directed SHM test.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this test.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_directed_base_test", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Encodes one legal logical address into the selected space MADDR.
  //
  // @param space Address-space mapping to encode.
  // @param inv_size Interleave-size encoding in the range 0 through 12.
  // @param bank Logical BANK index.
  // @param warp_offs Group-relative WARP offset; used only by SPACE_BLK.
  // @param laddr Legal WARP-local byte address.
  // @param wpnum Number of WARP entries encoded by SPACE_BLK.
  // @return MADDR implementing the requested logical address.
  //----------------------------------------------------------------------------
  extern protected function longint unsigned encode_directed_maddr(
      creq_space_e space,
      int unsigned inv_size,
      int unsigned bank,
      int unsigned warp_offs,
      int unsigned laddr,
      int unsigned wpnum);

  //----------------------------------------------------------------------------
  // @brief Builds and validates one deterministic contiguous transaction.
  //
  // @param item_name UVM object instance name.
  // @param rw V2M or M2V direction.
  // @param space Address-space mapping.
  // @param wpid Absolute WARP selector or BLK group selector.
  // @param wpnum Number of WARP entries encoded by SPACE_BLK.
  // @param inv_size Interleave-size encoding.
  // @param thread_idx Sole active thread and LOC BANK.
  // @param maddr Sole active element MADDR.
  // @param requested_vaddr Exact M2V BADDR, or -1 for automatic generation.
  // @param data_byte V2M byte payload used by the data-isolation tests.
  // @return Fully packed and validated production topology item.
  //----------------------------------------------------------------------------
  extern protected function shmins_contiguous_sequence_item build_single_byte_item(
      string item_name,
      creq_rw_e rw,
      creq_space_e space,
      int unsigned wpid,
      int unsigned wpnum,
      int unsigned inv_size,
      int unsigned thread_idx,
      longint unsigned maddr,
      longint signed requested_vaddr,
      byte unsigned data_byte);

  //----------------------------------------------------------------------------
  // @brief Builds one legal byte transaction with retained inactive sentinels.
  //
  // The item is first generated with all threads active so every thread owns a
  // legal, byte-unique address and payload. The final tmsk is then narrowed
  // without clearing inactive fields, allowing the DUT test to detect accesses
  // incorrectly issued for masked threads.
  //
  // @param item_name UVM object instance name and matrix-cell label.
  // @param rw V2M or M2V request direction.
  // @param space LOC, WRP, or BLK address space.
  // @param target_tmsk Known non-zero final thread mask.
  // @return Fully validated contiguous item retaining inactive sentinels.
  //----------------------------------------------------------------------------
  extern protected function shmins_contiguous_sequence_item build_masked_byte_item(
      string item_name,
      creq_rw_e rw,
      creq_space_e space,
      logic [THD_N-1:0] target_tmsk);

  //----------------------------------------------------------------------------
  // @brief Checks the production mapper result against explicit logical fields.
  //
  // @param item Directed item containing one active element.
  // @param thread_idx Active thread index.
  // @param expected_bank Expected logical BANK.
  // @param expected_warp Expected absolute WARP.
  // @param expected_laddr Expected WARP-local byte address.
  //----------------------------------------------------------------------------
  extern protected function void check_single_byte_mapping(
      shmins_contiguous_sequence_item item,
      int unsigned thread_idx,
      int unsigned expected_bank,
      int unsigned expected_warp,
      int unsigned expected_laddr);

  //----------------------------------------------------------------------------
  // @brief Sends one prepared item through the production SHMINS driver.
  //
  // @param item Fully validated topology item.
  //----------------------------------------------------------------------------
  extern protected task send_directed_item(shmins_sequence_item item);

  //----------------------------------------------------------------------------
  // @brief Atomically validates and sends one ordered directed-item batch.
  //
  // @param items Fully prepared items in required creq acceptance order.
  // @param inter_item_delay_cycles Complete idle cycles between adjacent items.
  //----------------------------------------------------------------------------
  extern protected task send_directed_items(ref shmins_sequence_item items[$],
                                            input int unsigned inter_item_delay_cycles = 0);

  //----------------------------------------------------------------------------
  // @brief Checks one final physical byte in both reference and actual memories.
  //
  // @param label Stable testcase diagnostic label.
  // @param physical_addr BANK, gid, and BADDR to inspect.
  // @param expected Expected architectural byte value.
  //----------------------------------------------------------------------------
  extern protected function void check_final_memory_byte(string label,
                                                         shm_physical_addr_t physical_addr,
                                                         byte unsigned expected);

  `uvm_component_utils(shm_directed_base_test)
endclass : shm_directed_base_test

function shm_directed_base_test::new(string name = "shm_directed_base_test", uvm_component parent = null);
  super.new(name, parent);
endfunction : new

function longint unsigned shm_directed_base_test::encode_directed_maddr(
    creq_space_e space,
    int unsigned inv_size,
    int unsigned bank,
    int unsigned warp_offs,
    int unsigned laddr,
    int unsigned wpnum);
  longint unsigned interleave_bytes;
  longint unsigned interleave_index;
  longint unsigned interleave_offset;

  if (inv_size > 12 || bank >= BANK_N || laddr >= WARP_STEP || !(wpnum inside {1, 2, 4}) ||
      warp_offs >= wpnum) begin
    `uvm_fatal("SHM_DIRECTED_MADDR_ARGUMENT",
               $sformatf("space=%0d inv=%0d bank=%0d warp_offs=%0d laddr=%0d wpnum=%0d",
                         space, inv_size, bank, warp_offs, laddr, wpnum))
  end

  interleave_bytes = longint'(1) << (inv_size + 2);
  interleave_index = laddr / interleave_bytes;
  interleave_offset = laddr % interleave_bytes;
  case (space)
    SPACE_LOC: return laddr;
    SPACE_WRP: return interleave_index * interleave_bytes * BANK_N +
                      bank * interleave_bytes + interleave_offset;
    SPACE_BLK: return interleave_index * interleave_bytes * BANK_N * wpnum +
                      warp_offs * interleave_bytes * BANK_N + bank * interleave_bytes +
                      interleave_offset;
    default: begin
      `uvm_fatal("SHM_DIRECTED_MADDR_SPACE", $sformatf("unsupported space %0d", space))
      return 0;
    end
  endcase
endfunction : encode_directed_maddr

function shmins_contiguous_sequence_item shm_directed_base_test::build_single_byte_item(
    string item_name,
    creq_rw_e rw,
    creq_space_e space,
    int unsigned wpid,
    int unsigned wpnum,
    int unsigned inv_size,
    int unsigned thread_idx,
    longint unsigned maddr,
    longint signed requested_vaddr,
    byte unsigned data_byte);
  shmins_contiguous_sequence_item item;
  int unsigned warp_base;

  if (thread_idx >= THD_N || wpid >= WARP_N || maddr >= (longint'(1) << MADDR_W)) begin
    `uvm_fatal("SHM_DIRECTED_ITEM_ARGUMENT",
               $sformatf("thread=%0d wpid=%0d maddr=0x%0h", thread_idx, wpid, maddr))
  end

  item = shmins_contiguous_sequence_item::type_id::create(item_name);
  item.creq_rw = rw;
  item.creq_dtype = DTYP_8;
  item.creq_atype_w = ATYP_32;
  item.creq_atype_s = ATYP_U;
  item.creq_atype_g = GAUTO_1B;
  item.creq_itype = LDST_S;
  item.creq_ack_en = 1'b1;
  item.creq_inv_size = inv_size;
  item.creq_space = space;
  item.creq_info = '0;
  item.creq_id = '0;
  item.creq_wpid = wpid;
  item.creq_wpnum = wpnum;
  item.creq_tmsk = '0;
  item.creq_tmsk[thread_idx] = 1'b1;
  item.creq_base = '0;
  item.creq_base[MADDR_W-1:0] = maddr[MADDR_W-1:0];
  item.delay_cycle = 0;
  item.elem_cnt_max = item.data_elem_max();

  foreach (item.creq_prio[index]) begin
    item.creq_prio[index] = '0;
    item.creq_len[index] = '0;
    item.elem_num[index] = '0;
    item.creq_vmsk[index] = '0;
    item.creq_vdat[index] = '0;
  end
  item.creq_len[thread_idx] = 1;
  item.elem_num[thread_idx] = 1;
  item.creq_vmsk[thread_idx][0] = 1'b1;
  item.creq_vdat[thread_idx][7:0] = data_byte;

  foreach (item.elem_maddr[index, elem_idx]) begin
    item.start_maddr[index] = 0;
    item.elem_maddr[index][elem_idx] = 0;
    item.offs_elem[index][elem_idx] = 0;
  end
  item.start_maddr[thread_idx] = maddr;
  item.elem_maddr[thread_idx][0] = maddr;

  if (!item.populate_element_addresses()) begin
    `uvm_fatal("SHM_DIRECTED_ADDRESS_BACKFILL",
               $sformatf("%s could not map MADDR 0x%0h", item_name, maddr))
  end

  warp_base = (wpid % WARP_PER_GID) * WARP_STEP;
  item.creq_vaddr = shm_baddr_t'(warp_base);
  if (rw == SHM_M2V) begin
    if (requested_vaddr >= 0) begin
      item.creq_vaddr = shm_baddr_t'(requested_vaddr);
      if (!item.legal_m2v_writeback_address(item.creq_vaddr)) begin
        `uvm_fatal("SHM_DIRECTED_M2V_VADDR",
                   $sformatf("%s vaddr 0x%0h is illegal for MADDR 0x%0h",
                             item_name, requested_vaddr, maddr))
      end
    end else if (!item.generate_m2v_writeback_address()) begin
      `uvm_fatal("SHM_DIRECTED_M2V_GENERATE", $sformatf("%s could not generate vaddr", item_name))
    end
  end

  item.pack_offsets();
  item.validate_transaction();
  item.item_to_rtl();
  return item;
endfunction : build_single_byte_item

function shmins_contiguous_sequence_item shm_directed_base_test::build_masked_byte_item(
    string item_name,
    creq_rw_e rw,
    creq_space_e space,
    logic [THD_N-1:0] target_tmsk);
  shmins_contiguous_sequence_item item;

  if ($isunknown(target_tmsk) || target_tmsk == '0) begin
    `uvm_fatal("SHM_DIRECTED_MASK_ARGUMENT",
               $sformatf("%s target tmsk must be known and non-zero: %b", item_name, target_tmsk))
  end

  item = shmins_contiguous_sequence_item::type_id::create(item_name);
  item.m2v_unique_enable = 1'b1;
  if (!item.randomize() with {
        creq_rw == local::rw;
        creq_dtype == DTYP_8;
        creq_atype_w == ATYP_32;
        creq_atype_s == ATYP_U;
        creq_atype_g == GAUTO_1B;
        creq_itype == LDST_S;
        creq_space == local::space;
        creq_wpid == 0;
        creq_wpnum == (local::space == SPACE_BLK ? 4 : 1);
        creq_inv_size == 0;
        creq_ack_en == 1'b1;
        creq_tmsk == '1;
        delay_cycle == 0;
        foreach (elem_num[thread_idx]) elem_num[thread_idx] == 1;
        foreach (creq_vmsk[thread_idx]) creq_vmsk[thread_idx] == VEC_BYTE_N'(1);
      }) begin
    `uvm_fatal("SHM_DIRECTED_MASK_RANDOMIZE",
               $sformatf("%s failed to generate full-mask sentinel item", item_name))
  end

  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    item.creq_vdat[thread_idx] = '0;
    item.creq_vdat[thread_idx][0] = byte'(8'h40 + thread_idx);
    for (int unsigned previous_thread = 0; previous_thread < thread_idx; previous_thread++) begin
      if (item.make_physical_byte_key(item.elem_physical_addr[thread_idx][0]) ==
          item.make_physical_byte_key(item.elem_physical_addr[previous_thread][0])) begin
        `uvm_fatal("SHM_DIRECTED_MASK_SENTINEL_OVERLAP",
                   $sformatf("%s threads %0d and %0d generated the same physical byte",
                             item_name, previous_thread, thread_idx))
      end
    end
  end

  item.creq_tmsk = target_tmsk;
  item.validate_transaction();
  item.item_to_rtl();
  return item;
endfunction : build_masked_byte_item

function void shm_directed_base_test::check_single_byte_mapping(
    shmins_contiguous_sequence_item item,
    int unsigned thread_idx,
    int unsigned expected_bank,
    int unsigned expected_warp,
    int unsigned expected_laddr);
  shm_logical_addr_t logical_addr;
  shm_physical_addr_t physical_addr;

  logical_addr = item.elem_logical_addr[thread_idx][0];
  physical_addr = item.elem_physical_addr[thread_idx][0];
  if (int'(logical_addr.bank_id) != expected_bank || int'(logical_addr.warp_id) != expected_warp ||
      int'(logical_addr.laddr) != expected_laddr || int'(physical_addr.bank_id) != expected_bank ||
      int'(physical_addr.gid) != expected_warp / WARP_PER_GID ||
      int'(physical_addr.baddr) != (expected_warp % WARP_PER_GID) * WARP_STEP + expected_laddr) begin
    `uvm_fatal("SHM_DIRECTED_MAPPING",
               $sformatf({"expected bank=%0d warp=%0d laddr=0x%0h, got logical <%0d,%0d,0x%0h> ",
                          "physical <%0d,%0d,0x%0h>"},
                         expected_bank, expected_warp, expected_laddr, logical_addr.bank_id,
                         logical_addr.warp_id, logical_addr.laddr, physical_addr.bank_id,
                         physical_addr.gid, physical_addr.baddr))
  end
endfunction : check_single_byte_mapping

task shm_directed_base_test::send_directed_item(shmins_sequence_item item);
  shmins_sequence_item items[$];

  items.push_back(item);
  send_directed_items(items);
endtask : send_directed_item

task shm_directed_base_test::send_directed_items(ref shmins_sequence_item items[$],
                                                 input int unsigned inter_item_delay_cycles = 0);
  shm_directed_item_sequence item_sequence;

  item_sequence = shm_directed_item_sequence::type_id::create("directed_batch_sequence");
  item_sequence.set_requests(items, inter_item_delay_cycles);
  item_sequence.start(shm_env.shmins_mst_agt.sequencer);
endtask : send_directed_items

function void shm_directed_base_test::check_final_memory_byte(string label,
                                                              shm_physical_addr_t physical_addr,
                                                              byte unsigned expected);
  byte unsigned reference_value;
  byte unsigned actual_value;

  reference_value = shm_env.shm_ref.ref_banks[physical_addr.bank_id][physical_addr.gid].read(
      physical_addr.baddr);
  actual_value = shm_env.shm_scb.rtl_banks[physical_addr.bank_id][physical_addr.gid].read(
      physical_addr.baddr);
  if (reference_value != expected || actual_value != expected) begin
    `uvm_fatal("SHM_DIRECTED_FINAL_BYTE",
               $sformatf({"%s BANK=%0d GID=%0d BADDR=0x%0h expected=0x%02x ",
                          "reference=0x%02x actual=0x%02x"},
                         label, physical_addr.bank_id, physical_addr.gid,
                         physical_addr.baddr, expected, reference_value, actual_value))
  end
endfunction : check_final_memory_byte

`endif // INC_SHM_DIRECTED_BASE_TEST_SVH
