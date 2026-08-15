`ifndef INC_SHM_DBANK_GID_ISOLATION_TEST_SVH
`define INC_SHM_DBANK_GID_ISOLATION_TEST_SVH

//------------------------------------------------------------------------------
// @brief Verifies equal BANK/BADDR writes remain isolated between gid 0 and 1.
//------------------------------------------------------------------------------
class shm_dbank_gid_isolation_test extends shm_directed_base_test;

  //----------------------------------------------------------------------------
  // @brief Constructs the dual-gid data-isolation test.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this test.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_dbank_gid_isolation_test", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Sends distinguishable values to equal BANK/BADDR in both gids.
  //
  // @param phase UVM main phase controlling the test objection.
  //----------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  `uvm_component_utils(shm_dbank_gid_isolation_test)
endclass : shm_dbank_gid_isolation_test

function shm_dbank_gid_isolation_test::new(
    string name = "shm_dbank_gid_isolation_test",
    uvm_component parent = null);
  super.new(name, parent);
endfunction : new

task shm_dbank_gid_isolation_test::main_phase(uvm_phase phase);
  shmins_contiguous_sequence_item low_gid_item;
  shmins_contiguous_sequence_item high_gid_item;
  longint unsigned maddr;
  int unsigned thread_idx;
  int unsigned laddr;

  phase.raise_objection(this);
  thread_idx = BANK_N - 1;
  laddr = 32'h2a5;
  maddr = encode_directed_maddr(SPACE_LOC, 0, thread_idx, 0, laddr, 1);

  low_gid_item = build_single_byte_item("gid0_equal_baddr", SHM_V2M, SPACE_LOC, 0, 1, 0,
                                        thread_idx, maddr, -1, 8'h35);
  high_gid_item = build_single_byte_item("gid1_equal_baddr", SHM_V2M, SPACE_LOC, 4, 1, 0,
                                         thread_idx, maddr, -1, 8'hca);
  check_single_byte_mapping(low_gid_item, thread_idx, thread_idx, 0, laddr);
  check_single_byte_mapping(high_gid_item, thread_idx, thread_idx, 4, laddr);

  if (low_gid_item.elem_physical_addr[thread_idx][0].baddr !=
          high_gid_item.elem_physical_addr[thread_idx][0].baddr ||
      low_gid_item.elem_physical_addr[thread_idx][0].gid ==
          high_gid_item.elem_physical_addr[thread_idx][0].gid) begin
    `uvm_fatal("SHM_DBANK_GID_ISOLATION_SETUP",
               "directed pair does not use equal BANK/BADDR and different gid")
  end

  send_directed_item(low_gid_item);
  send_directed_item(high_gid_item);
  shm_env.wait_for_idle();

  `uvm_info("SHM_DBANK_GID_ISOLATION_TEST", "equal-BADDR dual-gid writes completed", UVM_LOW)
  phase.drop_objection(this);
endtask : main_phase

`endif // INC_SHM_DBANK_GID_ISOLATION_TEST_SVH
