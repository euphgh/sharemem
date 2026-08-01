`ifndef INC_SHMINS_MST_DRIVER_SVH
`define INC_SHMINS_MST_DRIVER_SVH

//-----------------------------------------------------------------------------
// Class: shmins_mst_driver
//-----------------------------------------------------------------------------

import shm_config_pkg::*;

class shmins_mst_driver extends uvm_driver #(shmins_sequence_item);

    // Data Members
    //---------------------------------------------------------------------
    int unsigned shmins_agent_id;
    bit[31:0]    drv_tr_cnt = 0;

    int          credit_cnt = 0;
    semaphore    credit_sem;

    // Interface Instantiation
    //---------------------------------------------------------------------
    virtual shmins_interface shmins_mst_vif;

    // Agent Configuration Instantiation
    //---------------------------------------------------------------------
    shmins_mst_agent_config shmins_mst_agent_cfg;

    // Constraints
    //---------------------------------------------------------------------

    // Methods
    //---------------------------------------------------------------------

    // Standard UVM Methods
    //---------------------------------------------------------------------
    extern function        new(string name= "shmins_mst_driver", uvm_component parent);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task     main_phase(uvm_phase phase);

    // User Defined APIs
    //---------------------------------------------------------------------
    extern task reset_signals();
    extern task drive_signals(shmins_sequence_item trans);

        // UVM Factory Registration
    //---------------------------------------------------------------------
    `uvm_component_utils_begin(shmins_mst_driver)
    // Add field configurations
    //---------------------------------------------------------------------
    `uvm_field_int(shmins_agent_id, UVM_ALL_ON)
    `uvm_component_utils_end
endclass: shmins_mst_driver

//-----------------------------------------------------------------------------
// Function: new
//-----------------------------------------------------------------------------
function shmins_mst_driver::new(string name = "shmins_mst_driver", uvm_component parent);
    super.new(name, parent);
    credit_sem = new(1);
endfunction: new

function void shmins_mst_driver::build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info(get_type_name(), "In build_phase...!!", UVM_DEBUG);

    //---------------------------------------------------------------------
    // Get configuration
    //---------------------------------------------------------------------

    // Get Agent Configuration
    if (!uvm_config_db#(shmins_mst_agent_config)::get(this, "", "shmins_mst_agent_config", shmins_mst_agent_cfg))
    begin
        `uvm_error(get_type_name(), "shmins_mst_agent_config object is not found in config db!");
    end
    else
    begin
        shmins_mst_agent_cfg.print();
    end

    //---------------------------------------------------------------------
    // Construct children
    //---------------------------------------------------------------------

    //---------------------------------------------------------------------
    // Configure children
    //---------------------------------------------------------------------

endfunction: build_phase

task shmins_mst_driver::main_phase(uvm_phase phase);
    super.main_phase(phase);
    `uvm_info(get_type_name(), "In main_phase...!!", UVM_DEBUG);

    // Reset
    reset_signals();
    wait(shmins_mst_vif.rst_n === 1'b1);
    credit_sem = new(OTF_N);

    @(shmins_mst_vif.mst_cb);

    fork
        forever begin
            // Credit
            credit_sem.get(1);
            seq_item_port.get_next_item(req);
            `uvm_info(get_type_name(), {"req item\n",req.sprint()}, UVM_HIGH)
            drv_tr_cnt++;

            void'(begin_tr(req, "shmins_mst_driver"));
            req.item_to_rtl();
            req.creq_id = drv_tr_cnt[ID_W-1:0];
            drive_signals(req);
            end_tr(req);
            seq_item_port.item_done(req);
        end
        forever begin
            @(shmins_mst_vif.mst_cb);
            if (shmins_mst_vif.mon_cb.creq_rls === 1'b1) begin
                credit_sem.put(1);
            end
        end
    join
endtask: main_phase

task shmins_mst_driver::reset_signals();
    shmins_mst_vif.mst_cb.creq_vld   <= '0;
    shmins_mst_vif.mst_cb.creq_id    <= '0;
    shmins_mst_vif.mst_cb.creq_wpid  <= '0;
    shmins_mst_vif.mst_cb.creq_wpnum <= '0;
    shmins_mst_vif.mst_cb.creq_prio  <= '0;
    shmins_mst_vif.mst_cb.creq_len   <= '0;
    shmins_mst_vif.mst_cb.creq_typ   <= '0;
    shmins_mst_vif.mst_cb.creq_vaddr <= '0;
    shmins_mst_vif.mst_cb.creq_vmsk  <= '0;
    shmins_mst_vif.mst_cb.creq_base  <= '0;
    shmins_mst_vif.mst_cb.creq_offs  <= '0;
    shmins_mst_vif.mst_cb.creq_vdat  <= '0;

    `uvm_info(get_type_name(), "Reset shmins_mst_interface...!!", UVM_DEBUG);
endtask: reset_signals

//-----------------------------------------------------------------------------
// User Defined
// Task: drive_signals
//-----------------------------------------------------------------------------
// Driver SHMINS Master Output
//-----------------------------------------------------------------------------
task shmins_mst_driver::drive_signals(shmins_sequence_item trans);

    // Send Ins
    shmins_mst_vif.mst_cb.creq_vld   <= 1'b1           ;
    shmins_mst_vif.mst_cb.creq_id    <= trans.creq_id  ;
    shmins_mst_vif.mst_cb.creq_wpid  <= trans.creq_wpid;
    shmins_mst_vif.mst_cb.creq_wpnum <= trans.creq_wpnum;
    shmins_mst_vif.mst_cb.creq_typ   <= trans.creq_typ ;
    shmins_mst_vif.mst_cb.creq_vaddr <= trans.creq_vaddr;
    shmins_mst_vif.mst_cb.creq_base  <= trans.creq_base ;

    for (int th_idx=0; th_idx<16; th_idx++) begin
        shmins_mst_vif.mst_cb.creq_prio[th_idx] <= trans.creq_prio[th_idx];
        shmins_mst_vif.mst_cb.creq_len [th_idx] <= trans.creq_len [th_idx];
        shmins_mst_vif.mst_cb.creq_vmsk[th_idx] <= trans.creq_vmsk[th_idx];
        shmins_mst_vif.mst_cb.creq_offs[th_idx] <= trans.creq_offs[th_idx];
        shmins_mst_vif.mst_cb.creq_vdat[th_idx] <= trans.creq_vdat[th_idx];
    end

    @(shmins_mst_vif.mst_cb);
    shmins_mst_vif.mst_cb.creq_vld <= 1'b0;

    // delay for next trans
    repeat(trans.delay_cycle) @(shmins_mst_vif.mst_cb);

endtask: drive_signals

`endif //INC_SHMINS_MST_DRIVER_SVH