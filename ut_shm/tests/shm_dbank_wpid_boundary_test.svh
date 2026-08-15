`ifndef INC_SHM_DBANK_WPID_BOUNDARY_TEST_SVH
`define INC_SHM_DBANK_WPID_BOUNDARY_TEST_SVH

//------------------------------------------------------------------------------
// @brief Drives deterministic LOC/WRP/BLK addresses across the gid boundary.
//------------------------------------------------------------------------------
class shm_dbank_wpid_boundary_test extends shm_directed_base_test;

  //----------------------------------------------------------------------------
  // @brief Constructs the dual-bank WARP-boundary test.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this test.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_dbank_wpid_boundary_test", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Sends fixed logical boundary addresses through the real DUT.
  //
  // @param phase UVM main phase controlling the test objection.
  //----------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  `uvm_component_utils(shm_dbank_wpid_boundary_test)
endclass : shm_dbank_wpid_boundary_test

function shm_dbank_wpid_boundary_test::new(
    string name = "shm_dbank_wpid_boundary_test",
    uvm_component parent = null);
  super.new(name, parent);
endfunction : new

task shm_dbank_wpid_boundary_test::main_phase(uvm_phase phase);
  shmins_contiguous_sequence_item item;
  longint unsigned maddr;

  phase.raise_objection(this);

  maddr = encode_directed_maddr(SPACE_LOC, 0, 0, 0, 0, 1);
  item = build_single_byte_item("loc_warp3_first", SHM_V2M, SPACE_LOC, 3, 1, 0, 0,
                                maddr, -1, 8'h31);
  check_single_byte_mapping(item, 0, 0, 3, 0);
  send_directed_item(item);

  maddr = encode_directed_maddr(SPACE_LOC, 0, BANK_N - 1, 0, WARP_STEP - 1, 1);
  item = build_single_byte_item("loc_warp4_last", SHM_V2M, SPACE_LOC, 4, 1, 0, BANK_N - 1,
                                maddr, -1, 8'h42);
  check_single_byte_mapping(item, BANK_N - 1, BANK_N - 1, 4, WARP_STEP - 1);
  send_directed_item(item);

  maddr = encode_directed_maddr(SPACE_WRP, 0, 0, 0, 0, 1);
  item = build_single_byte_item("wrp_warp3_first", SHM_V2M, SPACE_WRP, 3, 1, 0, 0,
                                maddr, -1, 8'h53);
  check_single_byte_mapping(item, 0, 0, 3, 0);
  send_directed_item(item);

  maddr = encode_directed_maddr(SPACE_WRP, 0, BANK_N - 1, 0, WARP_STEP - 1, 1);
  item = build_single_byte_item("wrp_warp4_last", SHM_V2M, SPACE_WRP, 4, 1, 0, 0,
                                maddr, -1, 8'h64);
  check_single_byte_mapping(item, 0, BANK_N - 1, 4, WARP_STEP - 1);
  send_directed_item(item);

  maddr = encode_directed_maddr(SPACE_WRP, 12, BANK_N - 1, 0, WARP_STEP - 1, 1);
  item = build_single_byte_item("wrp_warp7_large_interleave", SHM_V2M, SPACE_WRP, 7, 1, 12, 0,
                                maddr, -1, 8'h75);
  check_single_byte_mapping(item, 0, BANK_N - 1, 7, WARP_STEP - 1);
  send_directed_item(item);

  maddr = encode_directed_maddr(SPACE_BLK, 0, 0, 0, 0, 1);
  item = build_single_byte_item("blk_wpnum1_warp0", SHM_V2M, SPACE_BLK, 0, 1, 0, 0,
                                maddr, -1, 8'h86);
  check_single_byte_mapping(item, 0, 0, 0, 0);
  send_directed_item(item);

  maddr = encode_directed_maddr(SPACE_BLK, 0, BANK_N - 1, 0, WARP_STEP - 1, 1);
  item = build_single_byte_item("blk_wpnum1_warp7", SHM_V2M, SPACE_BLK, 7, 1, 0, 0,
                                maddr, -1, 8'h97);
  check_single_byte_mapping(item, 0, BANK_N - 1, 7, WARP_STEP - 1);
  send_directed_item(item);

  maddr = encode_directed_maddr(SPACE_BLK, 0, 0, 1, 0, 2);
  item = build_single_byte_item("blk_wpnum2_warp3", SHM_V2M, SPACE_BLK, 3, 2, 0, 0,
                                maddr, -1, 8'ha8);
  check_single_byte_mapping(item, 0, 0, 3, 0);
  send_directed_item(item);

  maddr = encode_directed_maddr(SPACE_BLK, 0, BANK_N - 1, 0, WARP_STEP - 1, 2);
  item = build_single_byte_item("blk_wpnum2_warp4", SHM_V2M, SPACE_BLK, 4, 2, 0, 0,
                                maddr, -1, 8'hb9);
  check_single_byte_mapping(item, 0, BANK_N - 1, 4, WARP_STEP - 1);
  send_directed_item(item);

  maddr = encode_directed_maddr(SPACE_BLK, 12, BANK_N - 1, 3, WARP_STEP - 1, 4);
  item = build_single_byte_item("blk_wpnum4_warp3", SHM_V2M, SPACE_BLK, 3, 4, 12, 0,
                                maddr, -1, 8'hca);
  check_single_byte_mapping(item, 0, BANK_N - 1, 3, WARP_STEP - 1);
  send_directed_item(item);

  maddr = encode_directed_maddr(SPACE_BLK, 12, 0, 0, 0, 4);
  item = build_single_byte_item("blk_wpnum4_warp4", SHM_V2M, SPACE_BLK, 4, 4, 12, 0,
                                maddr, -1, 8'hdb);
  check_single_byte_mapping(item, 0, 0, 4, 0);
  send_directed_item(item);

  shm_env.wait_for_idle();
  `uvm_info("SHM_DBANK_WPID_BOUNDARY_TEST", "directed dual-gid address boundaries completed", UVM_LOW)
  phase.drop_objection(this);
endtask : main_phase

`endif // INC_SHM_DBANK_WPID_BOUNDARY_TEST_SVH
