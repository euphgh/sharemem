`ifndef INC_SHM_M_WRITE_THEN_READ_ORDER_TEST_SVH
`define INC_SHM_M_WRITE_THEN_READ_ORDER_TEST_SVH

//------------------------------------------------------------------------------
// @brief Verifies one thread observes an overlapping M-write before a later M-read.
//------------------------------------------------------------------------------
class shm_m_write_then_read_order_test extends shm_directed_base_test;
  extern function new(string name = "shm_m_write_then_read_order_test", uvm_component parent = null);
  extern virtual task main_phase(uvm_phase phase);

  `uvm_component_utils(shm_m_write_then_read_order_test)
endclass : shm_m_write_then_read_order_test

function shm_m_write_then_read_order_test::new(string name = "shm_m_write_then_read_order_test",
                                               uvm_component parent = null);
  super.new(name, parent);
endfunction : new

task shm_m_write_then_read_order_test::main_phase(uvm_phase phase);
  localparam byte unsigned OLD_VALUE = 8'h27;
  localparam byte unsigned NEW_VALUE = 8'hb4;
  localparam longint unsigned SOURCE_MADDR = 'h120;
  localparam int unsigned VDEST_BADDR = 'h220;
  shmins_contiguous_sequence_item setup_item;
  shmins_contiguous_sequence_item write_item;
  shmins_contiguous_sequence_item read_item;
  shmins_sequence_item target_items[$];
  shm_physical_addr_t vdest_addr;

  phase.raise_objection(this);
  wait (shm_env.shmins_vif.rst_n === 1'b1);

  setup_item = build_single_byte_item("order_m002_setup", SHM_V2M, SPACE_LOC, 0, 1, 0, 0,
                                      SOURCE_MADDR, -1, OLD_VALUE);
  send_directed_item(setup_item);
  shm_env.wait_for_idle();
  shm_env.check_final_memory("ORDER-M-002 setup");

  write_item = build_single_byte_item("order_m002_write_new", SHM_V2M, SPACE_LOC, 0, 1, 0, 0,
                                      SOURCE_MADDR, -1, NEW_VALUE);
  read_item = build_single_byte_item("order_m002_read_new", SHM_M2V, SPACE_LOC, 0, 1, 0, 0,
                                     SOURCE_MADDR, VDEST_BADDR, '0);
  target_items.push_back(write_item);
  target_items.push_back(read_item);
  send_directed_items(target_items, 0);
  shm_env.wait_for_idle();
  shm_env.check_final_memory("ORDER-M-002 target batch");

  vdest_addr.bank_id = 0;
  vdest_addr.gid = 0;
  vdest_addr.baddr = VDEST_BADDR;
  check_final_memory_byte("ORDER-M-002 Msrc", write_item.elem_physical_addr[0][0], NEW_VALUE);
  check_final_memory_byte("ORDER-M-002 Vdst", vdest_addr, NEW_VALUE);
  `uvm_info("SHM_ORDER_M_WRITE_THEN_READ_TEST", "ORDER-M-002: PASS", UVM_LOW)
  phase.drop_objection(this);
endtask : main_phase

`endif // INC_SHM_M_WRITE_THEN_READ_ORDER_TEST_SVH
