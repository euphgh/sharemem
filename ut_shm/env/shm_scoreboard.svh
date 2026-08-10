`ifndef INC_SHM_SCOREBOARD_SVH
`define INC_SHM_SCOREBOARD_SVH

`include "shm_wtrans_item.svh"

// TLM Analysis Imp Declaration

//-----------------------------------------------------------------------------
// Class: shm_scoreboard
//-----------------------------------------------------------------------------
class shm_scoreboard extends uvm_scoreboard;

    // Data Members
    //---------------------------------------------------------------------
    parameter INFLIGHT_NUM = 8;
    parameter CLK_PERIOD   = 1;

    // banks write map type
    typedef vlm2aa::wmap_util wmap_util;
    typedef vlm2aa::wmap_t wmap_t;
    typedef vlm2aa::baddr_t baddr_t;

    typedef set_array_util#(baddr_t, BANK_N) waddr_util;
    typedef waddr_util::set_t waddr_set_t[BANK_N];
    // time map type
    typedef aa_array_util#(BANK_N, baddr_t, time) tmap_util;
    typedef tmap_util::aa_array_t tmap_t;

    // write aa of q array
    typedef aa_of_q_array_util#(BANK_N, baddr_t, byte) wmmap_util;
    typedef wmmap_util::aa_of_q_array_t wmmap_t;
    typedef set_util#(byte) byte_set_util;
    typedef byte_set_util::set_t byte_set_t;

    typedef aa_value_adapter_array_util#(BANK_N, baddr_t, byte) wmap_adapter_util;

    wmap_t wmap_final;
    wmmap_t wmap_expired;

    class ref_record_t;
        shm_wtrans_item tr;
        tmap_t matched;
        tmap_t expired;
        function new (shm_wtrans_item tr_);
            this.tr = tr_;
            for (int unsigned i = 0; i < BANK_N; i++) begin
                matched[i].delete();
                expired[i].delete();
            end
        endfunction
    endclass
    ref_record_t ref_record_q[$];

    svt_mem rtl_banks[BANK_N];
    shm_environment_config shm_environment_cfg;

    uvm_analysis_export #(vlm_memory_sequence_item) rtl_wrvlm_analysis_export;
    local uvm_tlm_analysis_fifo #(vlm_memory_sequence_item) rtl_wrvlm_analysis_fifo;

    uvm_analysis_export #(shm_wtrans_item) ref_wrvlm_analysis_export;
    local uvm_tlm_analysis_fifo #(shm_wtrans_item) ref_wrvlm_analysis_fifo;

    uvm_tlm_b_transport_imp #(vlm_memory_sequence_item, shm_scoreboard) mem_imp;

    extern function        new(string name = "shm_scoreboard", uvm_component parent);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);
    extern virtual task     configure_phase(uvm_phase phase);
    extern virtual task     main_phase(uvm_phase phase);
    extern virtual function void check_phase(uvm_phase phase);

    // collect reference transaction from reference
    extern task collect_ref();
    // Check for any time-out transactions, which will cause an error
    extern task scan_timeout_creq();
    // Compare dut w trans with ref, remove ref if dut match it
    extern task compare_dut_with_ref();

    extern function void compare_with_old_trans(const ref shm_wtrans_item new_trans);
    extern function bit is_finished_ref_trans(int index);
    extern virtual task b_transport(vlm_memory_sequence_item trans, uvm_tlm_time delay);

    `uvm_component_utils_begin(shm_scoreboard)

    `uvm_component_utils_end

endclass: shm_scoreboard

task shm_scoreboard::b_transport(vlm_memory_sequence_item trans, uvm_tlm_time delay);
    for(int unsigned bid = 0; bid < BANK_N; bid++) begin
        if (trans.vlm_bken[bid]) begin
            for (int unsigned byte_offs = 0; byte_offs < VLM_DATA_BYTE_W; byte_offs++) begin
                baddr_t byte_addr = trans.vlm_addr[bid] + baddr_t'(byte_offs);
                byte rdata = rtl_banks[bid].read(byte_addr);
                trans.vlm_data[bid][byte_offs * 8 +: 8] = rdata;
            end
            `uvm_info(get_type_name(), $sformatf("VLM[%02d][%x] R: %x", bid, trans.vlm_addr[bid], trans.vlm_data[bid]), UVM_FULL)
        end
    end
endtask // 任务结束，控制权和修改后的 txn 一起交还给 Driver

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
            ref_record_q[i].expired[bank][addr] = new_trans.issue_time;
        end
    end
endfunction

// collect reference transaction from reference
task shm_scoreboard::collect_ref();
    forever begin
        shm_wtrans_item tr;
        ref_wrvlm_analysis_fifo.get(tr);
        compare_with_old_trans(tr);
        begin
            ref_record_t new_ref_record = new(tr);
            ref_record_q.push_back(new_ref_record);
        end
    end
endtask

function bit shm_scoreboard::is_finished_ref_trans(int index);
    shm_wtrans_item curr_trans = ref_record_q[index].tr;
    waddr_set_t curr_matched = tmap_util::get_keys(ref_record_q[index].matched);
    waddr_set_t curr_expired = tmap_util::get_keys(ref_record_q[index].expired);
    waddr_set_t hitted_addrs = waddr_util::get_union(curr_matched, curr_expired);
    waddr_set_t trans_origin_addrs = wmap_util::get_keys(curr_trans.wmap);
    return waddr_util::contains(hitted_addrs, trans_origin_addrs);
endfunction

// Check for any time-out transactions, which will cause an error
task shm_scoreboard::scan_timeout_creq();
    forever begin: forever_wrap
        const int time_out_cycle = 128;
        ref_record_t rebuild_refs [$];
        // 每隔一段时间检查一遍，不需要每个时钟都扫，节省性能
        repeat(10) #(CLK_PERIOD);
        // Find all expired or finish ref trans
        foreach (ref_record_q[id]) begin: foreach_ref
            shm_wtrans_item tr = ref_record_q[id].tr;
            if (is_finished_ref_trans(id)) begin
                string info_msg = $sformatf("ref_record_q(id = %0d) all data is matched or expired: \n", ref_record_q[id].tr.creq_id);
                info_msg = {info_msg, tr.sprint(), tmap_util::sprint(ref_record_q[id].expired), tmap_util::sprint(ref_record_q[id].matched)};
                info_msg = {info_msg, "expired table: \n", tmap_util::sprint(ref_record_q[id].expired), "\n"};
                info_msg = {info_msg, "matched table: \n", tmap_util::sprint(ref_record_q[id].matched), "\n"};
                `uvm_info(get_type_name(), info_msg, UVM_FULL);
            end
            else if (($time - tr.issue_time) > (time_out_cycle * CLK_PERIOD)) begin
                wmap_t unmatched_wmap;
                string error_msg;

                foreach (tr.wmap[bank, addr]) begin
                    if (!ref_record_q[id].expired[bank].exists(addr) &&
                        !ref_record_q[id].matched[bank].exists(addr)) begin
                        unmatched_wmap[bank][addr] = tr.wmap[bank][addr];
                    end
                end

                error_msg = {$sformatf("shmins require expired after %0d cycles:\n", time_out_cycle), tr.sprint()};
                error_msg = {error_msg, "expired table: \n", tmap_util::sprint(ref_record_q[id].expired), "\n"};
                error_msg = {error_msg, "matched table: \n", tmap_util::sprint(ref_record_q[id].matched), "\n"};
                error_msg = {error_msg, "unmatched table: \n", wmap_util::sprint(unmatched_wmap), "\n"};
                `uvm_error(get_type_name(), error_msg);
            end
            else begin // only not finish and not expired records should be saved
                rebuild_refs.push_back(ref_record_q[id]);
            end
        end: foreach_ref
        ref_record_q = rebuild_refs;
    end: forever_wrap
endtask

// compare dut w trans with ref, remove ref if dut match it
task shm_scoreboard::compare_dut_with_ref();
    forever begin
        vlm_memory_sequence_item tr;
        wmap_t vlm_wmap;
        rtl_wrvlm_analysis_fifo.get(tr);
        if (tr.vlm_read) continue;
        for(int unsigned bid = 0; bid < BANK_N; bid ++) begin
            if (!tr.vlm_bken[bid]) continue;
            for (int unsigned byte_offs = 0; byte_offs < VLM_DATA_BYTE_W; byte_offs++) begin
                if (tr.vlm_strb[bid][byte_offs]) begin
                    baddr_t byte_waddr = tr.vlm_addr[bid] + baddr_t'(byte_offs);
                    byte unsigned wdata = tr.vlm_data[bid][byte_offs * 8 +: 8];
                    rtl_banks[bid].write(byte_waddr, wdata);
                end
            end
        end
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
                string err_msg = {"rtl write address is not expected:\n", waddr_util::sprint(error_waddr, "error address")};
                err_msg = {err_msg, "\n", wmap_util::sprint(vlm_wmap, "vlm table")};
                err_msg = {err_msg, "\n", wmap_util::sprint(wmap_final, "final wmap table")};
                err_msg = {err_msg, "\n", wmmap_util::sprint(wmap_expired, "expired wmmap table")};
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
                        err_msg = {err_msg, $sformatf("vlm[%0d][0x%x](%x) != final val(%x), also not in expired(%s)\n",
                            bidx, baddr, rtl_wdata, matched_final_wmap[bidx][baddr], byte_set_util::sprint(matched_expired_wmmap[bidx][baddr]))};
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
                    err_msg = {err_msg, "\n", wmap_util::sprint(vlm_wmap, "vlm table")};
                    err_msg = {err_msg, "\n", wmap_util::sprint(wmap_final, "final wmap table")};
                    err_msg = {err_msg, "\n", wmmap_util::sprint(wmap_expired, "expired wmmap table")};
                    `uvm_error(get_type_name(), err_msg);
                end
                else begin: value_full_match
                    `uvm_info(get_type_name(), {"rtl write fully matched with wmap_final and wmmap_expired:\n", wmap_util::sprint(vlm_wmap)}, UVM_FULL);
                    foreach(ref_record_q[i]) begin
                        shm_wtrans_item curr_trans = ref_record_q[i].tr;
                        wmap_t trans_pair_matched = wmap_util::get_intersect(vlm_wmap, curr_trans.wmap);
                        foreach(trans_pair_matched[bank, addr]) begin
                            if (ref_record_q[i].tr.wmap[bank][addr] == trans_pair_matched[bank][addr])
                                ref_record_q[i].matched[bank][addr] = $time;
                        end
                    end
                end: value_full_match
            end: value_check
        end
    end
endtask

function shm_scoreboard::new(string name = "shm_scoreboard", uvm_component parent);
    super.new(name, parent);
    mem_imp = new("mem_imp", this);
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

    foreach(rtl_banks[i]) begin
        int baddr_max = (1 << BADDR_W) - 1;
        rtl_banks[i] = new($sformatf("rtl_bank_%0x", i),
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
        `uvm_error(get_type_name(), {"wmap_final is not empty after test:\n", wmap_util::sprint(wmap_final, "final wmap table"), "\n"});
    end

endfunction: check_phase

//-----------------------------------------------------------------------------
// Task: configure_phase
//-----------------------------------------------------------------------------
// Stimulate the DUT
//-----------------------------------------------------------------------------
task shm_scoreboard::configure_phase(uvm_phase phase);
    foreach(rtl_banks[i]) begin
        rtl_banks[i].set_meminit(svt_mem::INCR, i << 4);
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
