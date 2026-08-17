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

    //-------------------------------------------------------------------------
    // @brief Checks four-state values interpreted for active threads.
    //
    // Inactive payload is intentionally ignored. One report is emitted for
    // each offending thread and field, while dependent fields are skipped when
    // length or element-mask state is unknown.
    //
    // @param transaction Fully sampled request with creq_typ already decoded.
    //-------------------------------------------------------------------------
    extern protected function void check_active_payload_xz(shmins_sequence_item transaction);

    //-------------------------------------------------------------------------
    // @brief Checks one topology-selected packed offset for X/Z.
    //
    // @param transaction Sampled request containing packed offsets.
    // @param thread_idx Thread containing the offset.
    // @param offset_idx Offset element selected by the request topology.
    // @return 1 when the selected encoded offset contains X/Z.
    //-------------------------------------------------------------------------
    extern protected function bit packed_offset_has_xz(shmins_sequence_item transaction,
                                                        int unsigned thread_idx,
                                                        int unsigned offset_idx);

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

        for (int th_idx = 0; th_idx < THD_N; th_idx++) begin
            shmins_trans.creq_prio[th_idx] = shmins_mon_vif.mon_cb.creq_prio[th_idx];
            shmins_trans.creq_len [th_idx] = shmins_mon_vif.mon_cb.creq_len [th_idx];
            shmins_trans.creq_vmsk[th_idx] = shmins_mon_vif.mon_cb.creq_vmsk[th_idx];
            shmins_trans.set_creq_offs(th_idx, shmins_mon_vif.mon_cb.creq_offs[th_idx]);
            shmins_trans.creq_vdat[th_idx] = shmins_mon_vif.mon_cb.creq_vdat[th_idx];
        end

        shmins_trans.rtl_to_item();
        if ($isunknown(shmins_trans.creq_tmsk)) begin
            `uvm_error("SHMINS_TMSK_XZ", $sformatf("creq_tmsk contains X/Z: %b", shmins_trans.creq_tmsk))
        end
        else if (shmins_trans.creq_tmsk == '0) begin
            `uvm_error("SHMINS_TMSK_ZERO", "creq_tmsk must enable at least one thread")
            continue;
        end
        else begin
            check_active_payload_xz(shmins_trans);
        end

        shmins_trans.accept_cycle = clk_vif.cycle_count;
        shmins_trans.transaction_uid = next_transaction_uid;
        shmins_trans.reset_epoch = reset_epoch;
        next_transaction_uid++;
        shmins_analysis_port.write(shmins_trans);
        shmins_cnt++;
    end
endtask

function void shmins_monitor::check_active_payload_xz(shmins_sequence_item transaction);
    for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
        bit offset_xz;
        bit vdata_xz;
        bit vmsk_xz;
        bit has_active_element;
        int unsigned element_count;

        if (transaction.creq_tmsk[thread_idx] !== 1'b1) begin
            continue;
        end
        if ($isunknown(transaction.creq_prio[thread_idx])) begin
            `uvm_error("SHMINS_ACTIVE_PAYLOAD_XZ",
                       $sformatf("thread %0d field creq_prio contains X/Z: %b",
                                 thread_idx, transaction.creq_prio[thread_idx]))
        end
        if ($isunknown(transaction.creq_len[thread_idx])) begin
            `uvm_error("SHMINS_ACTIVE_PAYLOAD_XZ",
                       $sformatf("thread %0d field creq_len contains X/Z: %b",
                                 thread_idx, transaction.creq_len[thread_idx]))
            continue;
        end
        if (transaction.data_byte_w() == 0) begin
            continue;
        end

        element_count = transaction.thread_elem_cnt(thread_idx);
        if (element_count > transaction.max_elem_cnt()) begin
            element_count = transaction.max_elem_cnt();
        end
        offset_xz = 1'b0;
        vdata_xz = 1'b0;
        vmsk_xz = 1'b0;
        has_active_element = 1'b0;

        for (int unsigned elem_idx = 0; elem_idx < element_count; elem_idx++) begin
            if ($isunknown(transaction.creq_vmsk[thread_idx][elem_idx])) begin
                vmsk_xz = 1'b1;
                continue;
            end
            if (transaction.creq_vmsk[thread_idx][elem_idx] !== 1'b1) begin
                continue;
            end

            has_active_element = 1'b1;
            if (transaction.creq_itype == LDSTE_V &&
                packed_offset_has_xz(transaction, thread_idx, elem_idx)) begin
                offset_xz = 1'b1;
            end
            if (transaction.creq_rw == SHM_V2M) begin
                for (int unsigned byte_lane = 0; byte_lane < transaction.data_byte_w(); byte_lane++) begin
                    int unsigned byte_idx = elem_idx * transaction.data_byte_w() + byte_lane;
                    if ($isunknown(transaction.creq_vdat[thread_idx][byte_idx])) begin
                        vdata_xz = 1'b1;
                    end
                end
            end
        end

        if (has_active_element && transaction.creq_itype inside {LDST_S, LDST_V, LDSTE_S} &&
            packed_offset_has_xz(transaction, thread_idx, 0)) begin
            offset_xz = 1'b1;
        end
        if (vmsk_xz) begin
            `uvm_error("SHMINS_ACTIVE_PAYLOAD_XZ",
                       $sformatf("thread %0d field creq_vmsk contains X/Z in the length-bounded range",
                                 thread_idx))
        end
        if (offset_xz) begin
            `uvm_error("SHMINS_ACTIVE_PAYLOAD_XZ",
                       $sformatf("thread %0d field creq_offs contains X/Z in a topology-selected slice",
                                 thread_idx))
        end
        if (vdata_xz) begin
            `uvm_error("SHMINS_ACTIVE_PAYLOAD_XZ",
                       $sformatf("thread %0d field creq_vdat contains X/Z in an active V2M byte",
                                 thread_idx))
        end
    end
endfunction : check_active_payload_xz

function bit shmins_monitor::packed_offset_has_xz(shmins_sequence_item transaction,
                                                   int unsigned thread_idx,
                                                   int unsigned offset_idx);
    logic [VEC_W-1:0] packed_offsets;

    if (thread_idx >= THD_N || offset_idx >= transaction.offs_elem_max()) begin
        return 1'b0;
    end
    packed_offsets = transaction.creq_offs(thread_idx);
    case (transaction.offs_bit_w())
        16: return $isunknown(packed_offsets[offset_idx * 16 +: 16]);
        32: return $isunknown(packed_offsets[offset_idx * 32 +: 32]);
        default: return 1'b0;
    endcase
endfunction : packed_offset_has_xz

`endif // INC_SHMINS_MONITOR_SVH
