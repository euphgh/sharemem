`ifndef INC_VLM2AA_SVH
`define INC_VLM2AA_SVH

import shm_seq_item_package::vlm_sequence_item;
import shm_util_package::BANK_N;
import shm_util_package::BADDR_W;
import collection::aa_array_util;
import collection::aa_util;

class vlm2aa;
    typedef bit [BADDR_W-1:0] baddr_t;
    typedef aa_array_util#(BANK_N, baddr_t, byte) wmap_util;
    // 16 bank write trace
    typedef wmap_util::aa_array_t wmap_t;

    // apply this item write data to res(array of associate array)
    static function bit trans(vlm_sequence_item vlm, ref wmap_t res);
        bit has_overlap = 1'b0;
        for (int bk_id = 0; bk_id < BANK_N; bk_id ++) begin: bank_loop
            baddr_t base_baddr = vlm.vlm_addr[bk_id];
            if (!vlm.vlm_bken[bk_id])
                continue; // skip not enable bank
            if ($isunknown(vlm.vlm_addr[bk_id])) begin
                `uvm_error(vlm.get_type_name(), $sformatf("Write Enable But Addr include X/Z: %x", vlm.vlm_addr[bk_id]));
                continue;
            end
            for (int by_id = 0; by_id < 32; by_id ++) begin: byte_id
                if (!vlm.vlm_strb[bk_id][by_id])
                    continue; // skip not strb byte
                begin
                    baddr_t byte_addr = base_baddr + baddr_t'(by_id);
                    baddr_t byte_data = vlm.vlm_data[bk_id][by_id * 8 +: 8];
                    if (res[bk_id].exists(byte_addr)) begin
                        has_overlap = 1'b1;
                        `uvm_info(vlm.get_type_name(), $sformatf("Write Overlap at bank[%0d][0x%x], %0x -> %0x", bk_id, byte_addr, res[bk_id][byte_addr], byte_data), UVM_HIGH);
                    end
                    res[bk_id][byte_addr] = byte_data;
                end
            end: byte_id
        end: bank_loop
        return has_overlap;
    endfunction

endclass

`endif // INC_VLM2AA_SVH
