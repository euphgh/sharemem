`ifndef INC_SHM_M2V_VADDR_BOUNDARY_TEST_SVH
`define INC_SHM_M2V_VADDR_BOUNDARY_TEST_SVH

//------------------------------------------------------------------------------
// @brief Verifies exact first/last gid-local M2V writeback BADDR values.
//------------------------------------------------------------------------------
class shm_m2v_vaddr_boundary_test extends shm_directed_base_test;

  //----------------------------------------------------------------------------
  // @brief Constructs the M2V vaddr-boundary test.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this test.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_m2v_vaddr_boundary_test", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Sends first/last M2V writebacks for wpid 3 and 4.
  //
  // @param phase UVM main phase controlling the test objection.
  //----------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  `uvm_component_utils(shm_m2v_vaddr_boundary_test)
endclass : shm_m2v_vaddr_boundary_test

function shm_m2v_vaddr_boundary_test::new(
    string name = "shm_m2v_vaddr_boundary_test",
    uvm_component parent = null);
  super.new(name, parent);
endfunction : new

task shm_m2v_vaddr_boundary_test::main_phase(uvm_phase phase);
  shmins_contiguous_sequence_item item;
  longint unsigned read_maddr;
  int unsigned first_vaddr;
  int unsigned last_vaddr;

  phase.raise_objection(this);

  first_vaddr = 3 * WARP_STEP;
  last_vaddr = 4 * WARP_STEP - VEC_BYTE_N;
  read_maddr = WARP_STEP - 1;
  item = build_single_byte_item("m2v_warp3_first", SHM_M2V, SPACE_LOC, 3, 1, 0, 0,
                                read_maddr, first_vaddr, 8'h00);
  check_single_byte_mapping(item, 0, 0, 3, WARP_STEP - 1);
  send_directed_item(item);

  read_maddr = 0;
  item = build_single_byte_item("m2v_warp3_last", SHM_M2V, SPACE_LOC, 3, 1, 0, BANK_N - 1,
                                read_maddr, last_vaddr, 8'h00);
  check_single_byte_mapping(item, BANK_N - 1, BANK_N - 1, 3, 0);
  send_directed_item(item);

  first_vaddr = 0;
  last_vaddr = WARP_STEP - VEC_BYTE_N;
  read_maddr = WARP_STEP - 1;
  item = build_single_byte_item("m2v_warp4_first", SHM_M2V, SPACE_LOC, 4, 1, 0, 0,
                                read_maddr, first_vaddr, 8'h00);
  check_single_byte_mapping(item, 0, 0, 4, WARP_STEP - 1);
  send_directed_item(item);

  read_maddr = 0;
  item = build_single_byte_item("m2v_warp4_last", SHM_M2V, SPACE_LOC, 4, 1, 0, BANK_N - 1,
                                read_maddr, last_vaddr, 8'h00);
  check_single_byte_mapping(item, BANK_N - 1, BANK_N - 1, 4, 0);
  send_directed_item(item);

  shm_env.wait_for_idle();
  `uvm_info("SHM_M2V_VADDR_BOUNDARY_TEST", "M2V gid-local vaddr boundaries completed", UVM_LOW)
  phase.drop_objection(this);
endtask : main_phase

`endif // INC_SHM_M2V_VADDR_BOUNDARY_TEST_SVH
