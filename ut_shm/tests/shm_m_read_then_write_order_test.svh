`ifndef INC_SHM_M_READ_THEN_WRITE_ORDER_TEST_SVH
`define INC_SHM_M_READ_THEN_WRITE_ORDER_TEST_SVH

//------------------------------------------------------------------------------
// @brief Verifies one thread observes M-read before a later overlapping M-write.
//------------------------------------------------------------------------------
class shm_m_read_then_write_order_test extends shm_directed_base_test;
  extern function new(string name = "shm_m_read_then_write_order_test", uvm_component parent = null);
  extern virtual task main_phase(uvm_phase phase);

  `uvm_component_utils(shm_m_read_then_write_order_test)
endclass : shm_m_read_then_write_order_test

function shm_m_read_then_write_order_test::new(string name = "shm_m_read_then_write_order_test",
                                               uvm_component parent = null);
  super.new(name, parent);
endfunction : new

task shm_m_read_then_write_order_test::main_phase(uvm_phase phase);
  localparam byte unsigned OLD_VALUE = 8'h31;
  localparam byte unsigned NEW_VALUE = 8'ha6;
  localparam longint unsigned SOURCE_MADDR = 'h100;
  localparam int unsigned VDEST_BADDR = 'h200;
  shmins_contiguous_sequence_item setup_item;
  shmins_contiguous_sequence_item read_item;
  shmins_contiguous_sequence_item write_item;
  shmins_sequence_item target_items[$];
  shm_physical_addr_t vdest_addr;

  phase.raise_objection(this);
  wait (shm_env.shmins_vif.rst_n === 1'b1);

  setup_item = build_single_byte_item("order_m001_setup", SHM_V2M, SPACE_LOC, 0, 1, 0, 0,
                                      SOURCE_MADDR, -1, OLD_VALUE);
  send_directed_item(setup_item);
  shm_env.wait_for_idle();
  shm_env.check_final_memory("ORDER-M-001 setup");

  read_item = build_single_byte_item("order_m001_read_old", SHM_M2V, SPACE_LOC, 0, 1, 0, 0,
                                     SOURCE_MADDR, VDEST_BADDR, '0);
  write_item = build_single_byte_item("order_m001_write_new", SHM_V2M, SPACE_LOC, 0, 1, 0, 0,
                                      SOURCE_MADDR, -1, NEW_VALUE);
  target_items.push_back(read_item);
  target_items.push_back(write_item);
  send_directed_items(target_items, 0);
  shm_env.wait_for_idle();
  shm_env.check_final_memory("ORDER-M-001 target batch");

  vdest_addr.bank_id = 0;
  vdest_addr.gid = 0;
  vdest_addr.baddr = VDEST_BADDR;
  check_final_memory_byte("ORDER-M-001 Msrc", write_item.elem_physical_addr[0][0], NEW_VALUE);
  check_final_memory_byte("ORDER-M-001 Vdst", vdest_addr, OLD_VALUE);
  `uvm_info("SHM_ORDER_M_READ_THEN_WRITE_TEST", "ORDER-M-001: PASS", UVM_LOW)
  phase.drop_objection(this);
endtask : main_phase

`endif // INC_SHM_M_READ_THEN_WRITE_ORDER_TEST_SVH
