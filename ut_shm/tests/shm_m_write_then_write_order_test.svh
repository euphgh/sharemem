`ifndef INC_SHM_M_WRITE_THEN_WRITE_ORDER_TEST_SVH
`define INC_SHM_M_WRITE_THEN_WRITE_ORDER_TEST_SVH

//------------------------------------------------------------------------------
// @brief Verifies overlapping M-writes leave the second creq value in memory.
//------------------------------------------------------------------------------
class shm_m_write_then_write_order_test extends shm_directed_base_test;
  extern function new(string name = "shm_m_write_then_write_order_test", uvm_component parent = null);
  extern virtual task main_phase(uvm_phase phase);

  `uvm_component_utils(shm_m_write_then_write_order_test)
endclass : shm_m_write_then_write_order_test

function shm_m_write_then_write_order_test::new(string name = "shm_m_write_then_write_order_test",
                                                uvm_component parent = null);
  super.new(name, parent);
endfunction : new

task shm_m_write_then_write_order_test::main_phase(uvm_phase phase);
  localparam byte unsigned FIRST_VALUE = 8'h4d;
  localparam byte unsigned SECOND_VALUE = 8'he2;
  localparam longint unsigned DEST_MADDR = 'h140;
  shmins_contiguous_sequence_item first_item;
  shmins_contiguous_sequence_item second_item;
  shmins_sequence_item target_items[$];

  phase.raise_objection(this);
  wait (shm_env.shmins_vif.rst_n === 1'b1);

  first_item = build_single_byte_item("order_m003_first", SHM_V2M, SPACE_LOC, 0, 1, 0, 0,
                                      DEST_MADDR, -1, FIRST_VALUE);
  second_item = build_single_byte_item("order_m003_second", SHM_V2M, SPACE_LOC, 0, 1, 0, 0,
                                       DEST_MADDR, -1, SECOND_VALUE);
  target_items.push_back(first_item);
  target_items.push_back(second_item);
  send_directed_items(target_items, 0);
  shm_env.wait_for_idle();
  shm_env.check_final_memory("ORDER-M-003 target batch");

  check_final_memory_byte("ORDER-M-003 Mdst", second_item.elem_physical_addr[0][0], SECOND_VALUE);
  `uvm_info("SHM_ORDER_M_WRITE_THEN_WRITE_TEST", "ORDER-M-003: PASS", UVM_LOW)
  phase.drop_objection(this);
endtask : main_phase

`endif // INC_SHM_M_WRITE_THEN_WRITE_ORDER_TEST_SVH
