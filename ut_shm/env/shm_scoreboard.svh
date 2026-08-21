`ifndef INC_SHM_SCOREBOARD_SVH
`define INC_SHM_SCOREBOARD_SVH

`include "shm_wtrans_item.svh"

// TLM Analysis Imp Declaration

//------------------------------------------------------------------------------
// @brief Compares expected and observed SHM byte writes in shared clock cycles.
//
// The scoreboard keeps superseded expected values for legal out-of-order DUT
// writes, publishes transaction-level completion to the lifecycle checker, and
// provides independently configurable no-progress and record-age diagnostics.
//------------------------------------------------------------------------------
class shm_scoreboard extends uvm_scoreboard;

    // Data Members
    //---------------------------------------------------------------------
    parameter INFLIGHT_NUM = 8;
    // banks write map type
    typedef vlm2aa::wmap_util wmap_util;
    typedef vlm2aa::wmap_t wmap_t;
    typedef vlm2aa::baddr_t baddr_t;

    typedef set_array_util#(baddr_t, PHYSICAL_BANK_N) waddr_util;
    typedef waddr_util::elem_util waddr_elem_util;
    typedef waddr_util::set_t waddr_set_t[PHYSICAL_BANK_N];
    // Cycle map type.
    typedef aa_array_util#(PHYSICAL_BANK_N, baddr_t, shm_cycle_t) tmap_util;
    typedef tmap_util::aa_array_t tmap_t;

    // write aa of q array
    typedef shm_physical_map_util::wmmap_util wmmap_util;
    typedef shm_physical_map_util::wmmap_t wmmap_t;
    typedef set_util#(byte) byte_set_util;
    typedef byte_set_util::set_t byte_set_t;

    typedef aa_value_adapter_array_util#(PHYSICAL_BANK_N, baddr_t, byte) wmap_adapter_util;

    wmap_t wmap_final;
    wmmap_t wmap_expired;

    // Physical bytes written by at least one reference transaction in this epoch.
    waddr_set_t touched_waddrs;

    class ref_record_t;
        shm_wtrans_item tr;
        tmap_t matched;
        tmap_t expired;
        bit completion_reported;
        bit age_timeout_reported;
        function new (shm_wtrans_item tr_);
            this.tr = tr_;
            completion_reported = 1'b0;
            age_timeout_reported = 1'b0;
            for (int unsigned i = 0; i < PHYSICAL_BANK_N; i++) begin
                matched[i].delete();
                expired[i].delete();
            end
        endfunction
    endclass
    ref_record_t ref_record_q[$];

    svt_mem rtl_banks[BANK_N][GID_N];
    shm_environment_config shm_environment_cfg;
    virtual clk_if clk_vif;

    // Cycle of the latest reference arrival, expiration, or actual write match.
    shm_cycle_t last_progress_cycle;
    bit no_progress_timeout_reported;

    uvm_analysis_export #(vlm_memory_sequence_item) rtl_wrvlm_analysis_export;
    local uvm_tlm_analysis_fifo #(vlm_memory_sequence_item) rtl_wrvlm_analysis_fifo;

    uvm_analysis_export #(shm_wtrans_item) ref_wrvlm_analysis_export;
    local uvm_tlm_analysis_fifo #(shm_wtrans_item) ref_wrvlm_analysis_fifo;

    uvm_tlm_b_transport_imp #(vlm_memory_sequence_item, shm_scoreboard) mem_imp;
    uvm_analysis_port #(shm_completion_event) completion_analysis_port;

    extern function        new(string name = "shm_scoreboard", uvm_component parent);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);
    extern virtual task     configure_phase(uvm_phase phase);
    extern virtual task     main_phase(uvm_phase phase);
    extern virtual function void check_phase(uvm_phase phase);

    //-------------------------------------------------------------------------
    // @brief Collects expected write maps and records their acceptance cycle.
    //-------------------------------------------------------------------------
    extern task collect_ref();

    //-------------------------------------------------------------------------
    // @brief Scans completion and optional cycle-based timeout diagnostics.
    //
    // A reported timeout does not delete or expire expected transaction data.
    //-------------------------------------------------------------------------
    extern task scan_timeout_creq();

    //-------------------------------------------------------------------------
    // @brief Compares observed DUT writes with current and superseded data.
    //-------------------------------------------------------------------------
    extern task compare_dut_with_ref();

    //-------------------------------------------------------------------------
    // @brief Applies one new expected write map to older expected records.
    //
    // @param new_trans New reference transaction that supersedes overlapping
    //                  byte addresses from older records.
    // @post Overlapping old bytes are classified as expired at issue_cycle.
    //-------------------------------------------------------------------------
    extern function void compare_with_old_trans(const ref shm_wtrans_item new_trans);

    //-------------------------------------------------------------------------
    // @brief Returns whether all bytes of one reference record are resolved.
    //
    // @param index Queue index of the reference record to query.
    // @return 1 when every expected byte was either observed or superseded.
    //-------------------------------------------------------------------------
    extern function bit is_finished_ref_trans(int index);

    //-------------------------------------------------------------------------
    // @brief Returns whether all bytes were observed without supersession.
    //
    // @param index Queue index of the reference record to query.
    // @return 1 for a nonempty map whose every byte matched an actual write.
    //-------------------------------------------------------------------------
    extern function bit is_observed_ref_trans(int index);

    //-------------------------------------------------------------------------
    // @brief Publishes one completion event for each newly resolved record.
    //-------------------------------------------------------------------------
    extern function void publish_completion_events();

    //-------------------------------------------------------------------------
    // @brief Records progress at the current shared clock cycle.
    //-------------------------------------------------------------------------
    extern function void record_progress();

    //-------------------------------------------------------------------------
    // @brief Returns whether no reference, FIFO, or expected byte is pending.
    //
    // @return 1 when the scoreboard contains no outstanding work.
    //-------------------------------------------------------------------------
    extern function bit is_idle();

    //-------------------------------------------------------------------------
    // @brief Formats current pending state for drain-time diagnostics.
    //
    // @return Multi-line reference, FIFO, cycle, and expected-map summary.
    //-------------------------------------------------------------------------
    extern function string pending_state_sprint();

    //-------------------------------------------------------------------------
    // @brief Compares every touched byte in reference and actual memory.
    //
    // @param reference_banks Reference-owned architectural memory handles.
    // @param diagnostic Empty on success; otherwise lists every mismatched byte.
    // @return 1 when all touched BANK/GID/BADDR bytes have equal values.
    //-------------------------------------------------------------------------
    extern function bit compare_final_memory(svt_mem reference_banks[BANK_N][GID_N],
                                             output string diagnostic);

    //-------------------------------------------------------------------------
    // @brief Formats each pending record and expands its unresolved byte map.
    //
    // @return Multi-line transaction identity, byte progress, and unresolved addresses.
    //-------------------------------------------------------------------------
    extern function string pending_records_sprint();

    //-------------------------------------------------------------------------
    // @brief Formats the common first line for one reference record diagnostic.
    //
    // @param index Queue index of the reference record to format.
    // @return Transaction UID, ID, direction, issue cycle, age, and byte counts.
    //-------------------------------------------------------------------------
    extern protected function string ref_record_summary_sprint(int index);

    //-------------------------------------------------------------------------
    // @brief Expands every unresolved expected byte for one reference record.
    //
    // @param index Queue index of the reference record to format.
    // @return BANK/GID/BADDR/data hierarchy containing only unresolved bytes.
    //-------------------------------------------------------------------------
    extern protected function string unresolved_bytes_sprint(int index);

    //-------------------------------------------------------------------------
    // @brief Applies one resolved actual MEM write to rtl_banks.
    //
    // @param trans Write transaction with immutable gid/match metadata.
    // @post Every trusted strobe byte is visible to later read snapshots.
    //-------------------------------------------------------------------------
    extern protected function void commit_actual_memory_write(vlm_memory_sequence_item trans);

    //-------------------------------------------------------------------------
    // @brief Fills one resolved MEM read transaction from current rtl_banks.
    //
    // @param trans Read transaction whose active BANK data fields are updated.
    //-------------------------------------------------------------------------
    extern protected function void read_actual_memory_snapshot(vlm_memory_sequence_item trans);

    //-------------------------------------------------------------------------
    // @brief Executes one no-time actual-memory write or read operation.
    //
    // @param trans Resolved transaction selecting write commit or read snapshot.
    // @param delay TLM delay retained for API compatibility; no delay is added.
    //-------------------------------------------------------------------------
    extern virtual task b_transport(vlm_memory_sequence_item trans, uvm_tlm_time delay);

    `uvm_component_utils_begin(shm_scoreboard)

    `uvm_component_utils_end

endclass: shm_scoreboard

task shm_scoreboard::b_transport(vlm_memory_sequence_item trans, uvm_tlm_time delay);
    if (trans.vlm_read) begin
        read_actual_memory_snapshot(trans);
    end else begin
        commit_actual_memory_write(trans);
    end
endtask : b_transport

function void shm_scoreboard::commit_actual_memory_write(vlm_memory_sequence_item trans);
    for (int unsigned bid = 0; bid < BANK_N; bid++) begin
        if (!trans.vlm_bken[bid]) begin
            continue;
        end
        if (!trans.gid_valid[bid] || !trans.reservation_matched[bid]) begin
            `uvm_error(get_type_name(),
                       $sformatf("MEM write bank %0d has no uniquely matched reservation gid", bid))
            continue;
        end
        for (int unsigned byte_offs = 0; byte_offs < VLM_DATA_BYTE_W; byte_offs++) begin
            if (trans.vlm_strb[bid][byte_offs]) begin
                baddr_t byte_waddr = trans.vlm_addr[bid] + baddr_t'(byte_offs);
                byte unsigned wdata = trans.vlm_data[bid][byte_offs * 8 +: 8];
                rtl_banks[bid][trans.vlm_gid[bid]].write(byte_waddr, wdata);
            end
        end
    end
endfunction : commit_actual_memory_write

function void shm_scoreboard::read_actual_memory_snapshot(vlm_memory_sequence_item trans);
    for(int unsigned bid = 0; bid < BANK_N; bid++) begin
        if (trans.vlm_bken[bid]) begin
            if (!trans.gid_valid[bid] || !trans.reservation_matched[bid]) begin
                `uvm_error(get_type_name(), $sformatf("MEM read bank %0d has no uniquely matched reservation gid", bid))
                continue;
            end
            for (int unsigned byte_offs = 0; byte_offs < VLM_DATA_BYTE_W; byte_offs++) begin
                baddr_t byte_addr = trans.vlm_addr[bid] + baddr_t'(byte_offs);
                byte rdata = rtl_banks[bid][trans.vlm_gid[bid]].read(byte_addr);
                trans.vlm_data[bid][byte_offs * 8 +: 8] = rdata;
            end
            `uvm_info(get_type_name(),
                      $sformatf("VLM[%02d][%x] R: %x", bid, trans.vlm_addr[bid], trans.vlm_data[bid]),
                      UVM_FULL)
        end
    end
endfunction : read_actual_memory_snapshot

// compare new trans with old trans, calculate expired
function void shm_scoreboard::compare_with_old_trans(const ref shm_wtrans_item new_trans);
    // find if there wmap_final have address is overlapped
    // record overlaped data to wmap_expired
    wmap_t expired_total = wmap_util::get_intersect(wmap_final, new_trans.wmap);
    wmap_adapter_util::merge_with(wmap_expired, expired_total);
    // modify wmap_final with new trans
    wmap_util::merge_with(wmap_final, new_trans.wmap);

    // modify foreach old ref trans
    foreach(ref_record_q[i]) begin
        shm_wtrans_item old_trans = ref_record_q[i].tr;
        wmap_t expired_addrs = wmap_util::get_intersect(old_trans.wmap, new_trans.wmap);
        foreach(expired_addrs[bank, addr]) begin
            ref_record_q[i].expired[bank][addr] = new_trans.issue_cycle;
        end
    end
endfunction

// collect reference transaction from reference
task shm_scoreboard::collect_ref();
    forever begin
        shm_wtrans_item tr;
        ref_wrvlm_analysis_fifo.get(tr);
        foreach (tr.wmap[physical_bank, baddr]) begin
            void'(waddr_elem_util::insert(touched_waddrs[physical_bank], baddr));
        end
        compare_with_old_trans(tr);
        begin
            ref_record_t new_ref_record = new(tr);
            ref_record_q.push_back(new_ref_record);
        end
        record_progress();
        publish_completion_events();
    end
endtask

function bit shm_scoreboard::compare_final_memory(svt_mem reference_banks[BANK_N][GID_N],
                                                  output string diagnostic);
    int unsigned mismatch_count = 0;

    diagnostic = "";
    for (int unsigned physical_bank = 0; physical_bank < PHYSICAL_BANK_N; physical_bank++) begin
        int unsigned bank = physical_bank / GID_N;
        int unsigned gid = physical_bank % GID_N;

        foreach (touched_waddrs[physical_bank][index]) begin
            baddr_t baddr = touched_waddrs[physical_bank][index];
            byte unsigned reference_value = reference_banks[bank][gid].read(baddr);
            byte unsigned actual_value = rtl_banks[bank][gid].read(baddr);

            if (reference_value != actual_value) begin
                mismatch_count++;
                diagnostic = {diagnostic,
                              $sformatf({"BANK=%0d GID=%0d BADDR=0x%0h ",
                                         "reference=0x%02x actual=0x%02x\n"},
                                        bank, gid, baddr, reference_value, actual_value)};
            end
        end
    end
    if (mismatch_count != 0) begin
        diagnostic = {$sformatf("final memory mismatch bytes=%0d\n", mismatch_count), diagnostic};
    end
    return mismatch_count == 0;
endfunction : compare_final_memory

function bit shm_scoreboard::is_finished_ref_trans(int index);
    shm_wtrans_item curr_trans = ref_record_q[index].tr;
    waddr_set_t curr_matched = tmap_util::get_keys(ref_record_q[index].matched);
    waddr_set_t curr_expired = tmap_util::get_keys(ref_record_q[index].expired);
    waddr_set_t hitted_addrs = waddr_util::get_union(curr_matched, curr_expired);
    waddr_set_t trans_origin_addrs = wmap_util::get_keys(curr_trans.wmap);
    return waddr_util::contains(hitted_addrs, trans_origin_addrs);
endfunction

function bit shm_scoreboard::is_observed_ref_trans(int index);
    shm_wtrans_item curr_trans = ref_record_q[index].tr;
    waddr_set_t curr_matched = tmap_util::get_keys(ref_record_q[index].matched);
    waddr_set_t trans_origin_addrs = wmap_util::get_keys(curr_trans.wmap);
    bit has_expected_data = 1'b0;

    foreach (curr_trans.wmap[bank, addr]) begin
        has_expected_data = 1'b1;
    end
    return has_expected_data && waddr_util::contains(curr_matched, trans_origin_addrs);
endfunction : is_observed_ref_trans

function void shm_scoreboard::publish_completion_events();
    foreach (ref_record_q[index]) begin
        shm_completion_event completion_event;

        if (ref_record_q[index].completion_reported || !is_finished_ref_trans(index)) begin
            continue;
        end

        completion_event = shm_completion_event::type_id::create("completion_event");
        completion_event.transaction_uid = ref_record_q[index].tr.transaction_uid;
        completion_event.cycle = clk_vif.cycle_count;
        completion_event.kind = is_observed_ref_trans(index) ? SHM_COMPLETION_OBSERVED : SHM_COMPLETION_RESOLVED;
        ref_record_q[index].completion_reported = 1'b1;
        completion_analysis_port.write(completion_event);
    end
endfunction : publish_completion_events

function void shm_scoreboard::record_progress();
    last_progress_cycle = clk_vif.cycle_count;
    no_progress_timeout_reported = 1'b0;
endfunction : record_progress

function bit shm_scoreboard::is_idle();
    if (ref_record_q.size() != 0 || !rtl_wrvlm_analysis_fifo.is_empty() ||
        !ref_wrvlm_analysis_fifo.is_empty()) begin
        return 1'b0;
    end

    foreach (wmap_final[bank]) begin
        if (wmap_final[bank].size() != 0) begin
            return 1'b0;
        end
    end
    return 1'b1;
endfunction : is_idle

function string shm_scoreboard::pending_state_sprint();
    return {$sformatf({"scoreboard pending records=%0d rtl_fifo_empty=%0d ref_fifo_empty=%0d ",
                       "last_progress_cycle=%0d current_cycle=%0d\n"},
                      ref_record_q.size(), rtl_wrvlm_analysis_fifo.is_empty(),
                      ref_wrvlm_analysis_fifo.is_empty(), last_progress_cycle,
                      clk_vif.cycle_count),
            pending_records_sprint(),
            shm_physical_map_util::sprint_wmap(wmap_final, "final wmap table")};
endfunction : pending_state_sprint

function string shm_scoreboard::pending_records_sprint();
    string result;

    foreach (ref_record_q[index]) begin
        result = {result, ref_record_summary_sprint(index), unresolved_bytes_sprint(index), "\n"};
    end
    return result;
endfunction : pending_records_sprint

function string shm_scoreboard::ref_record_summary_sprint(int index);
    shm_wtrans_item tr = ref_record_q[index].tr;
    int unsigned expected_bytes = 0;
    int unsigned matched_bytes = 0;
    int unsigned expired_bytes = 0;
    int unsigned unresolved_bytes = 0;

    foreach (tr.wmap[bank, addr]) begin
        bit matched = ref_record_q[index].matched[bank].exists(addr);
        bit expired = ref_record_q[index].expired[bank].exists(addr);

        expected_bytes++;
        matched_bytes += matched;
        expired_bytes += expired;
        unresolved_bytes += !matched && !expired;
    end

    return $sformatf({"SHM transaction uid=%0d id=%0d direction=%s issue_cycle=%0d age=%0d ",
                      "bytes(expected/matched/expired/unresolved)=%0d/%0d/%0d/%0d\n"},
                     tr.transaction_uid, tr.creq_id, tr.creq_rw.name(), tr.issue_cycle,
                     clk_vif.cycle_count - tr.issue_cycle, expected_bytes, matched_bytes,
                     expired_bytes, unresolved_bytes);
endfunction : ref_record_summary_sprint

function string shm_scoreboard::unresolved_bytes_sprint(int index);
    shm_wtrans_item tr = ref_record_q[index].tr;
    wmap_t unresolved_wmap;

    foreach (tr.wmap[bank, addr]) begin
        if (!ref_record_q[index].expired[bank].exists(addr) &&
            !ref_record_q[index].matched[bank].exists(addr)) begin
            unresolved_wmap[bank][addr] = tr.wmap[bank][addr];
        end
    end
    return shm_physical_map_util::sprint_wmap(unresolved_wmap, "unresolved byte table");
endfunction : unresolved_bytes_sprint

// Scan completion and optional cycle-based timeout diagnostics.
task shm_scoreboard::scan_timeout_creq();
    forever begin: forever_wrap
        ref_record_t rebuild_refs [$];
        shm_cycle_t current_cycle;

        clk_vif.wait_cycles(shm_environment_cfg.scb_timeout_scan_interval_cycles);
        current_cycle = clk_vif.cycle_count;
        publish_completion_events();

        // Find all expired or finish ref trans
        foreach (ref_record_q[id]) begin: foreach_ref
            shm_wtrans_item tr = ref_record_q[id].tr;
            if (is_finished_ref_trans(id)) begin
                string info_msg = {
                    ref_record_summary_sprint(id),
                    "status=finished; all expected bytes are matched or expired\n",
                    "expired table:\n", tmap_util::sprint(ref_record_q[id].expired), "\n",
                    "matched table:\n", tmap_util::sprint(ref_record_q[id].matched), "\n"
                };
                `uvm_info(get_type_name(), info_msg, UVM_FULL);
            end
            else begin
                rebuild_refs.push_back(ref_record_q[id]);

                if (shm_environment_cfg.scb_record_age_timeout_cycles != 0 &&
                    current_cycle - tr.issue_cycle > shm_environment_cfg.scb_record_age_timeout_cycles &&
                    !ref_record_q[id].age_timeout_reported) begin
                    string error_msg = {
                        ref_record_summary_sprint(id),
                        $sformatf("record_age_timeout_cycles=%0d\n",
                                  shm_environment_cfg.scb_record_age_timeout_cycles),
                        unresolved_bytes_sprint(id), "\n"
                    };
                    `uvm_error("SHM_SCB_RECORD_AGE_TIMEOUT", error_msg)
                    ref_record_q[id].age_timeout_reported = 1'b1;
                end
            end
        end: foreach_ref
        ref_record_q = rebuild_refs;

        if (ref_record_q.size() == 0) begin
            no_progress_timeout_reported = 1'b0;
        end
        else if (shm_environment_cfg.scb_no_progress_timeout_cycles != 0 &&
                 current_cycle - last_progress_cycle > shm_environment_cfg.scb_no_progress_timeout_cycles &&
                 !no_progress_timeout_reported) begin
            string error_msg;

            foreach (ref_record_q[index]) begin
                error_msg = {
                    error_msg,
                    ref_record_summary_sprint(index),
                    $sformatf({"no_progress_timeout_cycles=%0d last_progress_cycle=%0d ",
                               "current_cycle=%0d stalled_cycles=%0d\n"},
                              shm_environment_cfg.scb_no_progress_timeout_cycles,
                              last_progress_cycle, current_cycle, current_cycle - last_progress_cycle),
                    unresolved_bytes_sprint(index), "\n"
                };
            end

            `uvm_error("SHM_SCB_NO_PROGRESS_TIMEOUT", error_msg)
            no_progress_timeout_reported = 1'b1;
        end
    end: forever_wrap
endtask

// compare dut w trans with ref, remove ref if dut match it
task shm_scoreboard::compare_dut_with_ref();
    forever begin
        vlm_memory_sequence_item tr;
        wmap_t vlm_wmap;
        rtl_wrvlm_analysis_fifo.get(tr);
        if (tr.vlm_read) continue;
        void'(vlm2aa::trans(tr, vlm_wmap));
        begin
            waddr_set_t vlm_waddrs = wmap_util::get_keys(vlm_wmap);

            wmap_t matched_final_wmap = wmap_util::get_intersect(wmap_final, vlm_wmap);
            waddr_set_t matched_final_waddr = wmap_util::get_keys(matched_final_wmap);

            wmmap_t matched_expired_wmmap = wmap_adapter_util::get_intersect(wmap_expired, vlm_wmap);
            waddr_set_t matched_expired_waddr = wmmap_util::get_keys(matched_expired_wmmap);

            waddr_set_t hited_addrs = waddr_util::get_union(matched_final_waddr, matched_expired_waddr);
            if (!waddr_util::contains(hited_addrs, vlm_waddrs)) begin: addr_check
                waddr_set_t error_waddr = waddr_util::get_diff(vlm_waddrs, hited_addrs);
                string err_msg = {"rtl write address is not expected:\n",
                                  waddr_util::sprint(error_waddr, "error address")};
                err_msg = {err_msg, "\n", shm_physical_map_util::sprint_wmap(vlm_wmap, "vlm table")};
                err_msg = {err_msg, "\n", shm_physical_map_util::sprint_wmap(wmap_final, "final wmap table")};
                err_msg = {err_msg, "\n",
                           shm_physical_map_util::sprint_wmmap(wmap_expired, "expired wmmap table")};
                `uvm_error(get_type_name(), err_msg);
            end: addr_check
            else begin: value_check
                bit value_error = 0;
                string err_msg = "rtl write data is not expected:\n";
                foreach(vlm_wmap[bidx, baddr]) begin
                    byte rtl_wdata = vlm_wmap[bidx][baddr];
                    if (matched_final_wmap[bidx][baddr] == rtl_wdata) begin
                        wmap_final[bidx].delete(baddr);
                    end
                    else if (byte_set_util::count(matched_expired_wmmap[bidx][baddr], rtl_wdata) > 0) begin
                        byte_set_util::delete(wmap_expired[bidx][baddr], rtl_wdata);
                    end
                    else begin
                        value_error = 1;
                        err_msg = {err_msg,
                                   $sformatf({"BANK[%0d].GID[%0d].BADDR[0x%04x]: actual=0x%02x ",
                                              "final=0x%02x expired=%s\n"},
                                             bidx / GID_N, bidx % GID_N, baddr, rtl_wdata,
                                             matched_final_wmap[bidx][baddr],
                                             shm_physical_map_util::sprint_byte_values(
                                                 matched_expired_wmmap[bidx][baddr]))};
                    end
                end

                // clean wmap_expired
                foreach (wmap_expired[bidx]) begin
                    baddr_t del_keys[$];
                    byte_set_t bank_expired[baddr_t] = wmap_expired[bidx];
                    del_keys.delete();

                    // 1. 先遍历当前 aa，收集要删的 key
                    foreach (bank_expired[addr]) begin
                        if (bank_expired[addr].size() == 0) begin
                            del_keys.push_back(addr);
                        end
                    end

                    // 2. 再统一删除
                    foreach (del_keys[j]) begin
                        wmap_expired[bidx].delete(del_keys[j]);
                    end
                end

                if (value_error) begin
                    err_msg = {err_msg, "\n", shm_physical_map_util::sprint_wmap(vlm_wmap, "vlm table")};
                    err_msg = {err_msg, "\n", shm_physical_map_util::sprint_wmap(wmap_final, "final wmap table")};
                    err_msg = {err_msg, "\n",
                               shm_physical_map_util::sprint_wmmap(wmap_expired, "expired wmmap table")};
                    `uvm_error(get_type_name(), err_msg);
                end
                else begin: value_full_match
                    `uvm_info(get_type_name(),
                              {"rtl write fully matched with wmap_final and wmmap_expired:\n",
                               shm_physical_map_util::sprint_wmap(vlm_wmap, "vlm table")},
                              UVM_FULL);
                    record_progress();
                    foreach(ref_record_q[i]) begin
                        shm_wtrans_item curr_trans = ref_record_q[i].tr;
                        wmap_t trans_pair_matched =
                            wmap_util::get_intersect(vlm_wmap, curr_trans.wmap);
                        foreach(trans_pair_matched[bank, addr]) begin
                            if (ref_record_q[i].tr.wmap[bank][addr] == trans_pair_matched[bank][addr])
                                ref_record_q[i].matched[bank][addr] = clk_vif.cycle_count;
                        end
                    end
                    publish_completion_events();
                end: value_full_match
            end: value_check
        end
    end
endtask

function shm_scoreboard::new(string name = "shm_scoreboard", uvm_component parent);
    super.new(name, parent);
    last_progress_cycle = 0;
    no_progress_timeout_reported = 1'b0;
    mem_imp = new("mem_imp", this);
    completion_analysis_port = new("completion_analysis_port", this);
    rtl_wrvlm_analysis_export = new("rtl_vlm_analysis_export", this);
    rtl_wrvlm_analysis_fifo = new("rtl_vlm_analysis_fifo", this);
    ref_wrvlm_analysis_export = new("ref_vlm_analysis_export", this);
    ref_wrvlm_analysis_fifo = new("ref_vlm_analysis_fifo", this);
endfunction: new

//-----------------------------------------------------------------------------
// Function: build_phase
//-----------------------------------------------------------------------------
// Create and configure of testbench structure
//-----------------------------------------------------------------------------
function void shm_scoreboard::build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info(get_type_name(), "In build_phase...!!", UVM_DEBUG);

    //---------------------------------------------------------------------
    // Get configuration
    //---------------------------------------------------------------------

    // Get Environment Configuration
    if (!uvm_config_db#(shm_environment_config)::get(this, "", "shm_environment_config", shm_environment_cfg))
    begin
        `uvm_error(get_type_name(), "shm_environment_config object is not found in config db!");
    end
    else
    begin
        shm_environment_cfg.print();
    end

    if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
        `uvm_fatal("SHM_SCB_NO_CLK_VIF", "shm_scoreboard requires virtual clk_if 'clk_vif'")
    end
    last_progress_cycle = clk_vif.cycle_count;

    foreach(rtl_banks[bank, gid]) begin
        int baddr_max = (1 << BADDR_W) - 1;
        rtl_banks[bank][gid] = new($sformatf("rtl_bank_%0x_gid_%0d", bank, gid),
                           "RTL_BANKS",         // Memory name
                           8,                   // Suite name
                           0,                   // data width
                           0,                   // Address region
                           baddr_max);          // Lower address bound to memory
                                                // Upper address bound to memory
    end

endfunction: build_phase

//-----------------------------------------------------------------------------
// Function: connect_phase
//-----------------------------------------------------------------------------
// Establish cross-component connections
//-----------------------------------------------------------------------------
function void shm_scoreboard::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    rtl_wrvlm_analysis_export.connect(rtl_wrvlm_analysis_fifo.analysis_export);
    ref_wrvlm_analysis_export.connect(ref_wrvlm_analysis_fifo.analysis_export);
    `uvm_info(get_type_name(), "In connect_phase...!!", UVM_DEBUG);
endfunction: connect_phase

//-----------------------------------------------------------------------------
// Function: check_phase
//-----------------------------------------------------------------------------
// Check for any unexpected conditions in the verification environment
//-----------------------------------------------------------------------------
function void shm_scoreboard::check_phase(uvm_phase phase);
    bit has_not_matched_data = 0;
    super.check_phase(phase);
    `uvm_info(get_type_name(), "In check_phase...!!", UVM_DEBUG);

    if (!rtl_wrvlm_analysis_fifo.is_empty()) begin
        `uvm_error(get_type_name(), $sformatf("rtl_vlm_fifo is not empty"));
    end
    if (!ref_wrvlm_analysis_fifo.is_empty()) begin
        `uvm_error(get_type_name(), $sformatf("ref_vlm_fifo is not empty"));
    end

    foreach (wmap_final[bidx]) begin
        byte wbank_final[baddr_t] = wmap_final[bidx];
        if (wbank_final.size() > 0) begin
            has_not_matched_data = 1;
        end
    end

    if (has_not_matched_data) begin
        `uvm_error(get_type_name(),
                   {"wmap_final is not empty after test:\n",
                    shm_physical_map_util::sprint_wmap(wmap_final, "final wmap table"), "\n"});
    end

endfunction: check_phase

//-----------------------------------------------------------------------------
// Task: configure_phase
//-----------------------------------------------------------------------------
// Stimulate the DUT
//-----------------------------------------------------------------------------
task shm_scoreboard::configure_phase(uvm_phase phase);
    foreach(rtl_banks[bank, gid]) begin
        rtl_banks[bank][gid].set_meminit(svt_mem::INCR, (bank * GID_N + gid) << 4);
    end
endtask: configure_phase

//-----------------------------------------------------------------------------
// Task: main_phase
//-----------------------------------------------------------------------------
// Stimulate the DUT
//-----------------------------------------------------------------------------
task shm_scoreboard::main_phase(uvm_phase phase);
    super.main_phase(phase);
    `uvm_info(get_type_name(), "In main_phase...!!", UVM_DEBUG);

    fork
        collect_ref();
        scan_timeout_creq();
        compare_dut_with_ref();
    join_none

endtask: main_phase

`endif // INC_SHM_SCOREBOARD_SVH
