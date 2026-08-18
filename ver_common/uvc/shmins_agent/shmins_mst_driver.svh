`ifndef INC_SHMINS_MST_DRIVER_SVH
`define INC_SHMINS_MST_DRIVER_SVH

//------------------------------------------------------------------------------
// @brief Drives credit-controlled SHMINS requests on clocking-block boundaries.
//
// The driver schedules at most one request per cycle, consumes one credit for
// every scheduled request, and restores credits from sampled creq_rls pulses.
// Request checking and architectural result comparison remain monitor and
// scoreboard responsibilities.
//------------------------------------------------------------------------------

import shm_util_package::*;

class shmins_mst_driver extends uvm_driver #(shmins_sequence_item);

    // Data Members
    //---------------------------------------------------------------------
    int unsigned shmins_agent_id;

    // Number of requests scheduled by this driver since construction.
    bit [31:0] drv_tr_cnt = 0;

    // Number of currently available DUT request credits.
    int unsigned credit_cnt = 0;

    // Number of complete idle request cycles remaining before another issue.
    int unsigned delay_cnt = 0;

    // Interface Instantiation
    //---------------------------------------------------------------------
    virtual shmins_interface shmins_mst_vif;

    // Constraints
    //---------------------------------------------------------------------

    // Methods
    //---------------------------------------------------------------------

    // Standard UVM Methods
    //---------------------------------------------------------------------
    extern function        new(string name= "shmins_mst_driver", uvm_component parent);
    extern virtual task     main_phase(uvm_phase phase);

    // User Defined APIs
    //---------------------------------------------------------------------

    //------------------------------------------------------------------------------
    // @brief Drives all request outputs to their reset values without waiting.
    //------------------------------------------------------------------------------
    extern function void reset_signals();

    //------------------------------------------------------------------------------
    // @brief Restores one credit when creq_rls is sampled and checks overflow.
    //
    // @pre Called once after each mst_cb event.
    //------------------------------------------------------------------------------
    extern protected function void process_credit_release();

    //------------------------------------------------------------------------------
    // @brief Consumes one configured idle cycle when an inter-request delay is active.
    //
    // @return 1 when request issue must be skipped for the current scheduler cycle.
    //------------------------------------------------------------------------------
    extern protected function bit consume_delay_cycle();

    //------------------------------------------------------------------------------
    // @brief Reports whether the driver currently owns a request credit.
    //
    // @return 1 when a request may be scheduled; otherwise 0.
    //------------------------------------------------------------------------------

    //------------------------------------------------------------------------------
    // @brief Assigns one request payload to the SHMINS clocking-block outputs.
    //
    // @param transaction Encoded request to present at the next DUT sampling edge.
    //------------------------------------------------------------------------------
    extern protected function void drive_signals(shmins_sequence_item transaction);

    //------------------------------------------------------------------------------
    // @brief Records, encodes, drives, and accounts for one sequencer request.
    //
    // @param transaction Request returned by try_next_item().
    // @pre transaction is non-null and credit_available() returns 1.
    // @post One credit is consumed and the configured inter-request delay is armed.
    //------------------------------------------------------------------------------
    extern protected function void issue_request(shmins_sequence_item transaction);

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
endfunction: new

//------------------------------------------------------------------------------
// @brief Runs the cycle-based request, delay, and credit scheduler.
//
// The only clock wait is at the top of the loop. All helper functions schedule
// outputs for the next sampling edge without consuming simulation time.
//------------------------------------------------------------------------------
task shmins_mst_driver::main_phase(uvm_phase phase);
    super.main_phase(phase);
    `uvm_info(get_type_name(), "In main_phase...!!", UVM_DEBUG);

    // Reset
    reset_signals();
    wait(shmins_mst_vif.rst_n === 1'b1);
    delay_cnt = 0;
    credit_cnt = OTF_N;

    forever begin
        @(shmins_mst_vif.mst_cb);
        process_credit_release();

        // Drives creq_vld low by default
        shmins_mst_vif.mst_cb.creq_vld <= 1'b0;

        if (consume_delay_cycle()) begin
            continue;
        end

        // Wait when no credit is available
        if (credit_cnt == 0) begin
            continue;
        end

        // UVM defines try_next_item() as a task, so it cannot be wrapped in a
        // function. It does not wait for an item and returns null when none is
        // currently available from the sequencer.
        req = null;
        seq_item_port.try_next_item(req);
        if (req == null) begin
            continue;
        end

        issue_request(req);
    end
endtask: main_phase

function void shmins_mst_driver::reset_signals();
    shmins_mst_vif.mst_cb.creq_vld   <= '0;
    shmins_mst_vif.mst_cb.creq_id    <= '0;
    shmins_mst_vif.mst_cb.creq_wpid  <= '0;
    shmins_mst_vif.mst_cb.creq_wpnum <= '0;
    shmins_mst_vif.mst_cb.creq_prio  <= '0;
    shmins_mst_vif.mst_cb.creq_len   <= '0;
    shmins_mst_vif.mst_cb.creq_typ   <= '0;
    shmins_mst_vif.mst_cb.creq_vaddr <= '0;
    shmins_mst_vif.mst_cb.creq_tmsk  <= '0;
    shmins_mst_vif.mst_cb.creq_vmsk  <= '0;
    shmins_mst_vif.mst_cb.creq_base  <= '0;
    shmins_mst_vif.mst_cb.creq_offs  <= '0;
    shmins_mst_vif.mst_cb.creq_vdat  <= '0;

    `uvm_info(get_type_name(), "Reset shmins_mst_interface...!!", UVM_DEBUG);
endfunction: reset_signals

function void shmins_mst_driver::process_credit_release();
    if (shmins_mst_vif.mon_cb.creq_rls !== 1'b1) begin
        return;
    end

    if (credit_cnt == OTF_N) begin
        `uvm_error("SHMINS_CREDIT_OVERFLOW", "Received shmins release while all credits are available")
        return;
    end

    credit_cnt++;
endfunction: process_credit_release

function bit shmins_mst_driver::consume_delay_cycle();
    if (delay_cnt == 0) begin
        return 1'b0;
    end

    delay_cnt--;
    return 1'b1;
endfunction: consume_delay_cycle

function void shmins_mst_driver::drive_signals(shmins_sequence_item transaction);
    `uvm_info(get_type_name(), "Driving shmins trans valid", UVM_HIGH)

    // Send Ins
    shmins_mst_vif.mst_cb.creq_vld   <= 1'b1;
    shmins_mst_vif.mst_cb.creq_id    <= transaction.creq_id;
    shmins_mst_vif.mst_cb.creq_wpid  <= transaction.creq_wpid;
    shmins_mst_vif.mst_cb.creq_wpnum <= transaction.creq_wpnum;
    shmins_mst_vif.mst_cb.creq_typ   <= transaction.creq_typ;
    shmins_mst_vif.mst_cb.creq_vaddr <= transaction.creq_vaddr;
    shmins_mst_vif.mst_cb.creq_tmsk  <= transaction.creq_tmsk;
    shmins_mst_vif.mst_cb.creq_base  <= transaction.creq_base;

    for (int th_idx = 0; th_idx < THD_N; th_idx++) begin
        shmins_mst_vif.mst_cb.creq_prio[th_idx] <= transaction.creq_prio[th_idx];
        shmins_mst_vif.mst_cb.creq_len [th_idx] <= transaction.creq_len [th_idx];
        shmins_mst_vif.mst_cb.creq_vmsk[th_idx] <= transaction.creq_vmsk[th_idx];
        shmins_mst_vif.mst_cb.creq_offs[th_idx] <= transaction.creq_offs(th_idx);
        shmins_mst_vif.mst_cb.creq_vdat[th_idx] <= transaction.creq_vdat[th_idx];
    end
endfunction: drive_signals

function void shmins_mst_driver::issue_request(shmins_sequence_item transaction);
    `uvm_info(get_type_name(), {"req item\n", transaction.sprint()}, UVM_HIGH)
    drv_tr_cnt++;
    void'(begin_tr(transaction, "shmins_mst_driver"));
    transaction.item_to_rtl();
    transaction.creq_id = drv_tr_cnt[ID_W-1:0];
    drive_signals(transaction);
    end_tr(transaction);

    delay_cnt = transaction.delay_cycle;
    credit_cnt--;
    seq_item_port.item_done(transaction);
endfunction: issue_request

`endif //INC_SHMINS_MST_DRIVER_SVH
