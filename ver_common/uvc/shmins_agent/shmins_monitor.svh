`ifndef INC_SHMINS_MONITOR_SVH
`define INC_SHMINS_MONITOR_SVH

import shm_util_package::*;

//------------------------------------------------------------------------------
// @brief Samples accepted SHM creq and raw direction-specific ack events.
//
// Accepted transactions receive shared-clock, reset-epoch, and unique identity
// metadata. The monitor reports four-state sampling errors but delegates ack
// correlation, completion timing, and end-of-test drain to the environment.
//------------------------------------------------------------------------------
class shmins_monitor extends uvm_monitor;

    //---------------------------------------------------------------------
    // Data Members
    //---------------------------------------------------------------------
    int unsigned    shmins_agent_id;
    int unsigned    shmins_cnt = 0;

    // Shared cycle source used to timestamp accepted creq and ack events.
    virtual clk_if clk_vif;

    // Monotonic monitor-owned identity; zero remains the unassigned value.
    shm_transaction_uid_t next_transaction_uid = 1;

    // Incremented whenever reset is asserted during simulation.
    longint unsigned reset_epoch = 0;

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
    uvm_analysis_port #(shmins_ack_event) ack_analysis_port;

    //---------------------------------------------------------------------
    // Standard UVM Methods
    //---------------------------------------------------------------------
    extern function        new(string name= "shmins_monitor", uvm_component parent);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task     main_phase(uvm_phase phase);

    //-------------------------------------------------------------------------
    // @brief Samples accepted creq transactions and publishes independent copies.
    //-------------------------------------------------------------------------
    extern task monitor_signals();

    //-------------------------------------------------------------------------
    // @brief Samples raw ack pulses for one request direction.
    //
    // @param direction SHM_V2M selects mack; SHM_M2V selects vack.
    //-------------------------------------------------------------------------
    extern task monitor_ack(creq_rw_e direction);

    //-------------------------------------------------------------------------
    // @brief Advances the monitor reset epoch on each reset assertion.
    //-------------------------------------------------------------------------
    extern task monitor_reset_epoch();

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
    ack_analysis_port = new("ack_analysis_port", this);
    if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
        `uvm_fatal("SHMINS_MON_NO_CLK_VIF", "shmins_monitor requires virtual clk_if 'clk_vif'")
    end
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
        monitor_ack(SHM_V2M);
        monitor_ack(SHM_M2V);
        monitor_reset_epoch();
    join
endtask: main_phase

task shmins_monitor::monitor_ack(creq_rw_e direction);
    forever begin
        logic ack_done;
        logic [ID_W-1:0] ack_id;
        shmins_ack_event ack_event;

        @(shmins_mon_vif.mon_cb);
        if (shmins_mon_vif.rst_n !== 1'b1) begin
            continue;
        end

        if (direction == SHM_V2M) begin
            ack_done = shmins_mon_vif.mon_cb.mack_done;
            ack_id = shmins_mon_vif.mon_cb.mack_id;
        end
        else begin
            ack_done = shmins_mon_vif.mon_cb.vack_done;
            ack_id = shmins_mon_vif.mon_cb.vack_id;
        end

        if ($isunknown(ack_done)) begin
            `uvm_error("SHMINS_ACK_DONE_XZ", $sformatf("%s ack done contains X/Z", direction.name()))
            continue;
        end
        if (ack_done !== 1'b1) begin
            continue;
        end
        if ($isunknown(ack_id)) begin
            `uvm_error("SHMINS_ACK_ID_XZ", $sformatf("%s ack id contains X/Z: %b", direction.name(), ack_id))
            continue;
        end

        ack_event = shmins_ack_event::type_id::create("ack_event");
        ack_event.direction = direction;
        ack_event.transaction_id = ack_id;
        ack_event.cycle = clk_vif.cycle_count;
        ack_event.reset_epoch = reset_epoch;

        // Let a creq accepted on this same edge enter the lifecycle table first.
        uvm_wait_for_nba_region();
        ack_analysis_port.write(ack_event);
    end
endtask : monitor_ack

task shmins_monitor::monitor_reset_epoch();
    forever begin
        @(negedge shmins_mon_vif.rst_n);
        reset_epoch++;
    end
endtask : monitor_reset_epoch

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
        shmins_trans.accept_cycle = clk_vif.cycle_count;
        shmins_trans.transaction_uid = next_transaction_uid;
        shmins_trans.reset_epoch = reset_epoch;
        next_transaction_uid++;
        shmins_analysis_port.write(shmins_trans);
        shmins_cnt++;
    end
endtask

`endif // INC_SHMINS_MONITOR_SVH
