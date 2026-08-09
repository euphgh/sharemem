`ifndef INC_SHM_UNIT_TEST_SVH
`define INC_SHM_UNIT_TEST_SVH

import shm_seq_item_package::*;

class shm_unit_test extends shm_base_test;

    extern function new(string name = "shm_unit_test", uvm_component parent);
    extern virtual task main_phase(uvm_phase phase);

    `uvm_component_utils_begin(shm_unit_test)
    `uvm_component_utils_end
endclass: shm_unit_test

function shm_unit_test::new(string name = "shm_unit_test", uvm_component parent);
    super.new(name, parent);
endfunction :new

task shm_unit_test::main_phase(uvm_phase phase);
    shmins_mst_unit_sequence seq;
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "In main_phase...!!", UVM_DEBUG);

    // get simulate args
    seq = shmins_mst_unit_sequence::type_id::create("shmins_mst_unit_seq");
    seq.plusargs_override_config();
    `uvm_info(get_type_name(),
              $sformatf("Smoke configuration: TRANS_NUM=%0d", seq.m_seq_trans_num),
              UVM_LOW)
    `uvm_info(get_type_name(), {"Launch shm unit seq: ", seq.sprint()}, UVM_HIGH);
    seq.set_starting_phase(phase);
    seq.start(shm_env.shmins_mst_agt.sequencer);
    #200ns;
    phase.drop_objection(this);
endtask: main_phase

`endif // INC_SHM_UNIT_TEST_SVH
