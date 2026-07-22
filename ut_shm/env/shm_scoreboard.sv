import collection::*;

class shm_wtrans_item ;
    parameter int unsigned MADDR_W = 20;
    typedef bit [MADDR_W-1:0] maddr_t;
    typedef bit [15:0] baddr_t;

    typedef aa_array_util#(16, baddr_t, byte) wmap_util;
    // new field for compare
    realtime issue_time;
    wmap_util::aa_array_t wmap;
endclass

class shm_scoreboard;
    parameter int unsigned MADDR_W = 20;
    typedef bit [MADDR_W-1:0] maddr_t;
    typedef bit [15:0] baddr_t;
    parameter BANK_N = 16;
    typedef aa_array_util#(BANK_N,  baddr_t, byte) wmap_util; 
    // banks write map type
    typedef wmap_util::aa_array_t wmap_t;
    typedef set_array_util#(baddr_t, BANK_N) waddr_util; 
    typedef waddr_util::set_t waddr_set_t[BANK_N];
    // time map type
    typedef aa_array_util#(BANK_N, baddr_t, realtime) tmap_util;
    typedef tmap_util::aa_array_t tmap_t;
    // write aa_of_q array
    typedef aa_of_q_array_util#(BANK_N, baddr_t, byte) wmmap_util;
    typedef wmmap_util::aa_of_q_array_t wmmap_t;
    wmap_t wmap_final;
    wmmap_t wmap_expired;
    shm_wtrans_item ref_records [$];
    tmap_t trans_matched [$];
    tmap_t trans_expired [$];

    task collect_ref();
        shm_wtrans_item new_creq;
        wmap_t expired_total = wmap_util::get_intersect_merge_with(wmap_final, new_creq.wmap);
        wmmap_util::push_back_aa(wmap_expired, expired_total);
        foreach(ref_records[i]) begin
            shm_wtrans_item old_trans = ref_records[i];
            // continue if empty
            waddr_set_t old_trans_waddrs = wmap_util::get_keys(old_trans.wmap);
            waddr_set_t new_trans_waddrs = wmap_util::get_keys(new_creq.wmap);
            wmap_t expired_old_addrs = wmap_util::get_intersect(old_trans.wmap, new_creq.wmap);
            foreach(expired_old_addrs[bank, addr]) begin
                trans_expired[i][bank][addr] = new_creq.issue_time;
            end
        end
    endtask

    task scan_time_out_creq();
        foreach(ref_records[i]) begin
            shm_wtrans_item curr_trans = ref_records[i];
            waddr_set_t curr_matched = tmap_util::get_keys(trans_matched[i]);
            waddr_set_t curr_expired = tmap_util::get_keys(trans_expired[i]);
            waddr_set_t hited_addrs = waddr_util::get_union(curr_matched, curr_expired);
            waddr_set_t trans_origin_addrs = wmap_util::get_keys(curr_trans.wmap);
            bit ok = waddr_util::contains_set_array(hited_addrs, trans_origin_addrs);
            if (ok) begin
                // pop it
            end
        end
    endtask

    task compare_dut_with_ref();
        wmap_t vlm_wmap;
        waddr_set_t vlm_waddrs = wmap_util::get_keys(vlm_wmap);

        wmap_t matched_final_wmap = wmap_util::get_intersect_merge_with(wmap_final, vlm_wmap);
        waddr_set_t matched_final_waddr = wmap_util::get_keys(matched_final_wmap);

        wmap_t matched_expired_wmap = wmmap_util::get_intersect_with_aa_array(wmap_expired, vlm_wmap);
        waddr_set_t matched_expired_waddr = wmap_util::get_keys(matched_expired_wmap);

        waddr_set_t hited_addrs = waddr_util::get_union(matched_final_waddr, matched_expired_waddr);
        bit ok = waddr_util::contains_set_array(hited_addrs, vlm_waddrs);

        if (ok) begin
            wmap_util::diff_with(wmap_final, matched_final_wmap);
            wmmap_util::delete_from_aa_array(wmap_expired, matched_expired_wmap);

            foreach(ref_records[i]) begin
                shm_wtrans_item curr_trans = ref_records[i];
                wmap_t trans_pair_matched = wmap_util::get_intersect(curr_trans.wmap, vlm_wmap);
                foreach(trans_pair_matched[bank, addr]) begin
                    trans_matched[i][bank][addr] = $realtime; 
                end
            end
        end
    endtask
endclass
