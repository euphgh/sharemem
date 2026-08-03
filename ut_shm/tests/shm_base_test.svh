`ifndef INC_SHM_BASE_TEST_SVH
`define INC_SHM_BASE_TEST_SVH

//-----------------------------------------------------------------------------
// Class: shm_base_test
//-----------------------------------------------------------------------------
class shm_base_test extends uvm_test;

    // Data Members
    //---------------------------------------------------------------------

    // Environment Data Members

    // Interface Instantiation

    // Component Declaration
    //---------------------------------------------------------------------

    // Environments Instantiation
    shm_environment shm_env;

    // Configuration Instantiation
    //---------------------------------------------------------------------

    // Environment Configuration Object Instantiation
    shm_environment_config shm_environment_cfg;

    // Constraints

    // Methods

    // Misc Instantiation
    //---------------------------------------------------------------------
    uvm_table_printer printer;

    // Standard UVM Methods
    //---------------------------------------------------------------------
    extern function        new(string name = "shm_base_test", uvm_component parent);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void end_of_elaboration_phase(uvm_phase phase);
    extern virtual task     main_phase(uvm_phase phase);
    extern virtual function void report_phase(uvm_phase phase);

    `uvm_component_utils(shm_base_test)

endclass: shm_base_test

function shm_base_test::new(string name = "shm_base_test", uvm_component parent);
 super.new(name, parent);
endfunction :new

function void shm_base_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info(get_type_name(), "In build_phase...!!", UVM_DEBUG);

    shm_env = shm_environment::type_id::create("shm_env", this);
    shm_environment_cfg = shm_environment_config::type_id::create("shm_environment_cfg", this);
    shm_environment_cfg.init();

    uvm_config_db#(shm_environment_config)::set(this, "shm_env", "shm_environment_config", shm_environment_cfg);

    printer = new();
endfunction: build_phase

function void shm_base_test::end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    `uvm_info(get_type_name(), "In end_of_elaboration_phase...!!", UVM_DEBUG);
    `uvm_info(get_type_name(), $sformatf("Printing the Test Topology : %s", this.sprint(printer)), UVM_HIGH);
endfunction: end_of_elaboration_phase

task shm_base_test::main_phase(uvm_phase phase);

    int trans_num = 10; // default trans_num=10;
    shmins_mst_sequence seq;
    //
    super.main_phase(phase);
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "In main_phase...!!", UVM_DEBUG);

    // get simulate args
    $value$plusargs("trans_num=%d", trans_num);

    seq = shmins_mst_sequence::type_id::create("seq");
    seq.trans_num = trans_num;
    seq.set_starting_phase(phase);
    seq.start(shm_env.shmins_mst_agt.sequencer);
    #100ns;
    phase.drop_objection(this);

endtask: main_phase

function void shm_base_test::report_phase(uvm_phase phase);
    uvm_report_server svr;
    super.report_phase(phase);
    `uvm_info(get_type_name(), "In report_phase...!!", UVM_DEBUG);
    svr = uvm_report_server::get_server();

    if(svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR)) begin
        $display("==================================================");
        $display("======= UVM_CASE_FAIL =======");
        $display("==================================================");
    end
    else begin
        $display("==================================================");
        $display("======= UVM_CASE_PASS =======");
        $display("==================================================");
    end

endfunction: report_phase

`endif //INC_SHM_BASE_TEST_SVH
