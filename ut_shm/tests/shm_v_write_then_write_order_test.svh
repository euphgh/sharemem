`ifndef INC_SHM_V_WRITE_THEN_WRITE_ORDER_TEST_SVH
`define INC_SHM_V_WRITE_THEN_WRITE_ORDER_TEST_SVH

//------------------------------------------------------------------------------
// @brief Verifies overlapping M2V writebacks leave the second creq value in V memory.
//------------------------------------------------------------------------------
class shm_v_write_then_write_order_test extends shm_directed_base_test;
  extern function new(string name = "shm_v_write_then_write_order_test", uvm_component parent = null);
  extern virtual task main_phase(uvm_phase phase);

  `uvm_component_utils(shm_v_write_then_write_order_test)
endclass : shm_v_write_then_write_order_test

function shm_v_write_then_write_order_test::new(string name = "shm_v_write_then_write_order_test",
                                                uvm_component parent = null);
  super.new(name, parent);
endfunction : new

task shm_v_write_then_write_order_test::main_phase(uvm_phase phase);
  localparam byte unsigned FIRST_VALUE = 8'h58;
  localparam byte unsigned SECOND_VALUE = 8'hc7;
  localparam longint unsigned SOURCE0_MADDR = 'h180;
  localparam longint unsigned SOURCE1_MADDR = 'h1c0;
  localparam int unsigned VDEST_BADDR = 'h280;
  shmins_contiguous_sequence_item setup_first;
  shmins_contiguous_sequence_item setup_second;
  shmins_contiguous_sequence_item read_first;
  shmins_contiguous_sequence_item read_second;
  shmins_sequence_item setup_items[$];
  shmins_sequence_item target_items[$];
  shm_physical_addr_t vdest_addr;

  phase.raise_objection(this);
  wait (shm_env.shmins_vif.rst_n === 1'b1);

  setup_first = build_single_byte_item("order_v001_setup_first", SHM_V2M, SPACE_LOC, 0, 1, 0, 0,
                                       SOURCE0_MADDR, -1, FIRST_VALUE);
  setup_second = build_single_byte_item("order_v001_setup_second", SHM_V2M, SPACE_LOC, 0, 1, 0, 0,
                                        SOURCE1_MADDR, -1, SECOND_VALUE);
  setup_items.push_back(setup_first);
  setup_items.push_back(setup_second);
  send_directed_items(setup_items, 0);
  shm_env.wait_for_idle();
  shm_env.check_final_memory("ORDER-V-001 setup");

  read_first = build_single_byte_item("order_v001_read_first", SHM_M2V, SPACE_LOC, 0, 1, 0, 0,
                                      SOURCE0_MADDR, VDEST_BADDR, '0);
  read_second = build_single_byte_item("order_v001_read_second", SHM_M2V, SPACE_LOC, 0, 1, 0, 0,
                                       SOURCE1_MADDR, VDEST_BADDR, '0);
  target_items.push_back(read_first);
  target_items.push_back(read_second);
  send_directed_items(target_items, 0);
  shm_env.wait_for_idle();
  shm_env.check_final_memory("ORDER-V-001 target batch");

  vdest_addr.bank_id = 0;
  vdest_addr.gid = 0;
  vdest_addr.baddr = VDEST_BADDR;
  check_final_memory_byte("ORDER-V-001 Vdst", vdest_addr, SECOND_VALUE);
  `uvm_info("SHM_ORDER_V_WRITE_THEN_WRITE_TEST", "ORDER-V-001: PASS", UVM_LOW)
  phase.drop_objection(this);
endtask : main_phase

`endif // INC_SHM_V_WRITE_THEN_WRITE_ORDER_TEST_SVH
