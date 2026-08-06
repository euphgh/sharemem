`ifndef INC_SHMINS_MONITOR_SVH
`define INC_SHMINS_MONITOR_SVH

//-----------------------------------------------------------------------------
// Class: shmins_monitor
//-----------------------------------------------------------------------------

import shm_util_package::*;

class shmins_monitor extends uvm_monitor;

    parameter   SHMINS_ACK_TIMEOUT = 200;
    parameter   M2V_SEL = 0;
    parameter   V2M_SEL = 1;

    //---------------------------------------------------------------------
    // Data Members
    //---------------------------------------------------------------------
    int unsigned    shmins_agent_id;
    int unsigned    shmins_cnt = 0;
    process         thread_handles[2][int];

    shmins_sequence_item m_trans;

    //---------------------------------------------------------------------
    // Interface Instantiation
    //---------------------------------------------------------------------
    virtual shmins_interface shmins_mon_vif;

    //---------------------------------------------------------------------
    // Agent Configuration Instantiation
    //---------------------------------------------------------------------

    //---------------------------------------------------------------------
    // Coverage
    //---------------------------------------------------------------------
    //`include "shmins_shmins_covergroup.sv"

    //---------------------------------------------------------------------
    // Port Declaration
    //---------------------------------------------------------------------
    uvm_analysis_port #(shmins_sequence_item) shmins_analysis_port;

    //---------------------------------------------------------------------
    // Standard UVM Methods
    //---------------------------------------------------------------------
    extern function        new(string name= "shmins_monitor", uvm_component parent);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task     main_phase(uvm_phase phase);

    // User Defined APIs
    //---------------------------------------------------------------------
    extern task monitor_signals();

    // UVM Factory Registration
    //---------------------------------------------------------------------
    `uvm_component_utils_begin(shmins_monitor)
    // Add field configurations
    //---------------------------------------------------------------------
    `uvm_field_int(shmins_agent_id, UVM_ALL_ON)

    `uvm_component_utils_end
endclass :shmins_monitor

//-----------------------------------------------------------------------------
// Function: new
//-----------------------------------------------------------------------------
function shmins_monitor::new(string name = "shmins_monitor", uvm_component parent);
    super.new(name, parent);
    //cg_shmins = new();
endfunction :new

//-----------------------------------------------------------------------------
// Function: build_phase
//-----------------------------------------------------------------------------
// Create and configure of testbench structure
//-----------------------------------------------------------------------------
function void shmins_monitor::build_phase(uvm_phase phase);
    super.build_phase(phase);
    shmins_analysis_port = new("shmins_analysis_port", this);
endfunction : build_phase

//-----------------------------------------------------------------------------
// Task: main_phase
//-----------------------------------------------------------------------------
// Stimulate the DUT
//-----------------------------------------------------------------------------
task shmins_monitor::main_phase(uvm_phase phase);
    super.main_phase(phase);
    `uvm_info(get_type_name(), "In main_phase...!!", UVM_DEBUG);
    fork
        monitor_signals();
        forever begin
            wait (shmins_mon_vif.rst_n === 1);
            @(shmins_mon_vif.mon_cb iff shmins_mon_vif.mon_cb.mack_done === 1'b1);
            if (thread_handles[V2M_SEL].exists(shmins_mon_vif.mon_cb.mack_id)) begin
                int id = shmins_mon_vif.mon_cb.mack_id;
                thread_handles[V2M_SEL][id].kill();
                thread_handles[V2M_SEL].delete(id);
                `uvm_info(get_type_name(), $sformatf("trans(V2M) acked with id %0x", id), UVM_FULL);
            end
        end
        forever begin
            wait (shmins_mon_vif.rst_n === 1);
            @(shmins_mon_vif.mon_cb iff shmins_mon_vif.mon_cb.vack_done === 1'b1);
            if (thread_handles[M2V_SEL].exists(shmins_mon_vif.mon_cb.vack_id)) begin
                int id = shmins_mon_vif.mon_cb.vack_id;
                thread_handles[M2V_SEL][id].kill();
                thread_handles[M2V_SEL].delete(id);
                `uvm_info(get_type_name(), $sformatf("trans(M2V) acked with id %0x", id), UVM_FULL);
            end
        end
    join
endtask: main_phase

//-----------------------------------------------------------------------------
// User Defined
// Task: monitor_signals
//-----------------------------------------------------------------------------
// Monitor SHMINS sequence items.
//-----------------------------------------------------------------------------
task shmins_monitor::monitor_signals();
    forever begin
        shmins_sequence_item shmins_trans;
        wait (shmins_mon_vif.rst_n == 1);
        @(shmins_mon_vif.mon_cb iff shmins_mon_vif.mon_cb.creq_vld === 1'b1);
        `uvm_info(get_type_name(), $sformatf("monitor %0dth shmins_trans", shmins_cnt), UVM_NONE)

        shmins_trans = shmins_sequence_item::type_id::create($sformatf("shmins_trans%0d", shmins_cnt));

        shmins_trans.creq_id    = shmins_mon_vif.mon_cb.creq_id    ;
        shmins_trans.creq_wpid  = shmins_mon_vif.mon_cb.creq_wpid  ;
        shmins_trans.creq_wpnum = shmins_mon_vif.mon_cb.creq_wpnum ;
        shmins_trans.creq_typ   = shmins_mon_vif.mon_cb.creq_typ   ;
        shmins_trans.creq_vaddr = shmins_mon_vif.mon_cb.creq_vaddr ;
        shmins_trans.creq_tmsk  = shmins_mon_vif.mon_cb.creq_tmsk  ;
        shmins_trans.creq_base  = shmins_mon_vif.mon_cb.creq_base  ;

        if ($isunknown(shmins_trans.creq_tmsk)) begin
            `uvm_error("SHMINS_TMSK_XZ", $sformatf("creq_tmsk contains X/Z: %b", shmins_trans.creq_tmsk))
        end
        else if (shmins_trans.creq_tmsk == '0) begin
            `uvm_error("SHMINS_TMSK_ZERO", "creq_tmsk must enable at least one thread")
        end

        for (int th_idx=0; th_idx<16; th_idx++) begin
            shmins_trans.creq_prio[th_idx] = shmins_mon_vif.mon_cb.creq_prio[th_idx];
            shmins_trans.creq_len [th_idx] = shmins_mon_vif.mon_cb.creq_len [th_idx];
            shmins_trans.creq_vmsk[th_idx] = shmins_mon_vif.mon_cb.creq_vmsk[th_idx];
            shmins_trans.set_creq_offs(th_idx, shmins_mon_vif.mon_cb.creq_offs[th_idx]);
            shmins_trans.creq_vdat[th_idx] = shmins_mon_vif.mon_cb.creq_vdat[th_idx];
        end

        shmins_trans.rtl_to_item();
        shmins_analysis_port.write(shmins_trans);

        if (shmins_trans.creq_ack_en) begin
            fork
                automatic bit thd_hl_sel = shmins_trans.creq_rw == SHM_V2M ? V2M_SEL : M2V_SEL;
                automatic string trans_type = shmins_trans.creq_rw == SHM_V2M ? "V2M" : "M2V";
                automatic int expected_ack_id = shmins_trans.creq_id;
                automatic int unsigned expected_ack_index = shmins_cnt;
                begin
                    // 获取当前这个 fork 进程的句柄
                    `uvm_info(get_type_name(), $sformatf("%0dth trans(%s) with id %0x expected ack", expected_ack_index, trans_type, expected_ack_id), UVM_FULL);
                    thread_handles[thd_hl_sel][expected_ack_id] = process::self();

                    // 等待超时
                    repeat(SHMINS_ACK_TIMEOUT) @(shmins_mon_vif.mon_cb);
                    `uvm_error(get_type_name(), $sformatf("Ack of %0dth %s trans with id %0x TIMEOUT", expected_ack_index, trans_type, expected_ack_id));
                    thread_handles[thd_hl_sel].delete(expected_ack_id);
                end
            join_none
        end
        shmins_cnt++;
    end
endtask

`endif // INC_SHMINS_MONITOR_SVH
