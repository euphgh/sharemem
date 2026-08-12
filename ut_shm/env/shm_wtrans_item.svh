`ifndef INC_SHM_WTRANS_ITEM_SVH
`define INC_SHM_WTRANS_ITEM_SVH

//------------------------------------------------------------------------------
// @brief Reconstructs active SHM element addresses for the reference model.
//
// The item copies one sampled creq, decodes its packed offsets, and maps only
// elements selected by thread mask, length, and vector mask into logical and
// physical addresses. It does not generate stimulus or change creq fields.
//------------------------------------------------------------------------------
class shm_wtrans_item extends shmins_sequence_item;
    parameter int unsigned ELEM_MAX_N = VEC_BYTE_N;
    `uvm_object_utils(shm_wtrans_item)

    typedef vlm2aa::baddr_t baddr_t;
    typedef bit [$clog2(BANK_N)-1:0] bidx_t;
    typedef bit [$clog2(GID_N)-1:0] gid_t;

    typedef vlm2aa::wmap_util wmap_util;
    typedef vlm2aa::wmap_t wmap_t;
    // new field for compare
    time issue_time;
    wmap_t wmap;
    baddr_t baddr_2d_array[BANK_N][];
    bidx_t bid_2d_array[BANK_N][];
    gid_t gid_2d_array[BANK_N][];
    shm_logical_addr_t logical_addr_2d_array[BANK_N][];
    // support max dtype 64
    byte wstrb_2d_array[BANK_N][];

    //-------------------------------------------------------------------------
    // @brief Constructs a reference-side SHM transaction.
    //
    // @param name UVM object instance name.
    //-------------------------------------------------------------------------
    function new(string name = "ref_item");
        super.new(name);
        issue_time = $time;
    endfunction : new

    //-------------------------------------------------------------------------
    // @brief Reconstructs length-bounded MADDR values from packed offsets.
    //
    // @param tidx Source thread index.
    // @param elem_unify_addr Reconstructed MADDR array indexed by data element.
    // @param eoff_val Address-offset array before adding creq_base.
    // @post Both arrays contain at most max_elem_cnt() entries and preserve
    //       signed decoded offsets without MADDR-width truncation.
    //-------------------------------------------------------------------------
    function void cal_unify_addr(input int tidx,
                                 ref longint signed elem_unify_addr[],
                                 ref longint signed eoff_val[]);
        int unsigned element_count;

        element_count = thread_elem_cnt(tidx);
        if (element_count > max_elem_cnt()) begin
            element_count = max_elem_cnt();
        end
        eoff_val = new[element_count];
        elem_unify_addr = new[element_count];

        for (int unsigned elem_idx = 0; elem_idx < element_count; elem_idx++) begin
            case (creq_itype)
                LDST_S, LDST_V: begin
                    eoff_val[elem_idx] = decode_packed_offset(tidx, 0) +
                                         longint'(elem_idx) * longint'(data_byte_w());
                end
                LDSTE_S: begin
                    eoff_val[elem_idx] = longint'(elem_idx) * decode_packed_offset(tidx, 0);
                end
                LDSTE_V: begin
                    eoff_val[elem_idx] = decode_packed_offset(tidx, elem_idx);
                end
                default: begin
                    eoff_val[elem_idx] = 0;
                end
            endcase
            elem_unify_addr[elem_idx] = longint'(creq_base[MADDR_W-1:0]) + eoff_val[elem_idx];
        end
    endfunction : cal_unify_addr
    //-------------------------------------------------------------------------
    // @brief Builds physical address and byte-strobe arrays for active elements.
    //
    // @post Dynamic arrays are length-bounded. Masked or out-of-length element
    //       slots never call map_maddr() and retain zero strobe/address values.
    //-------------------------------------------------------------------------
    function void generate_wdata();
        const int unsigned elem_byten = data_byte_w();
        const string action = creq_rw == SHM_V2M ? "W" : "R";
        const string space_name = creq_space_e_to_str(creq_space);

        // Inactive thread payload may contain X/Z. Keep its derived arrays empty
        // so no address, reservation, MEM request, or writeback expectation is built.
        for (int i = 0; i < BANK_N; i++) begin
            if (creq_tmsk[i] === 1'b1) begin
                int unsigned element_count = thread_elem_cnt(i);
                if (element_count > max_elem_cnt()) begin
                    element_count = max_elem_cnt();
                end
                baddr_2d_array[i] = new[element_count];
                bid_2d_array [i] = new[element_count];
                gid_2d_array [i] = new[element_count];
                logical_addr_2d_array[i] = new[element_count];
                wstrb_2d_array[i] = new[element_count];
            end
            else begin
                baddr_2d_array[i] = new[0];
                bid_2d_array [i] = new[0];
                gid_2d_array [i] = new[0];
                logical_addr_2d_array[i] = new[0];
                wstrb_2d_array[i] = new[0];
            end
        end

        for (int tidx = 0; tidx < THD_N; tidx ++) begin: each_thread
            longint signed elem_unify_addr[];
            longint signed eoff_val[];

            if (creq_tmsk[tidx] !== 1'b1) begin
                `uvm_info(get_type_name(), $sformatf("Skip inactive thread %0d", tidx), UVM_FULL)
                continue;
            end

            // 1. calculate offset
            cal_unify_addr(tidx, elem_unify_addr, eoff_val);

            foreach(elem_unify_addr[eidx]) begin
                shmins_address_result_t mapped;
                byte wstrb = 0;

                if (!is_active_element(tidx, eidx)) begin
                    continue;
                end
                for (int byte_idx = 0; byte_idx < elem_byten; byte_idx++) begin
                    wstrb[byte_idx] = int'(creq_len[tidx]) > ((elem_byten * eidx) + byte_idx);
                end
                wstrb_2d_array[tidx][eidx] = wstrb;
                mapped = map_maddr(tidx, elem_unify_addr[eidx]);

                if (!mapped.valid) begin
                    `uvm_error(get_type_name(), $sformatf("failed to map thread %0d element %0d MADDR 0x%0h",
                                                         tidx, eidx, elem_unify_addr[eidx]));
                    continue;
                end

                `uvm_info(get_type_name(),
                          $sformatf("THD[%0d].Elem[%0d] %s Bank[%0d].Gid[%0d][0x%x].Strb[0x%x] = %s[0x%x]",
                                    tidx, eidx, action, mapped.physical_addr.bank_id, mapped.physical_addr.gid,
                                    mapped.physical_addr.baddr, wstrb_2d_array[tidx][eidx], space_name,
                                    elem_unify_addr[eidx]),
                          UVM_FULL);
                baddr_2d_array[tidx][eidx] = mapped.physical_addr.baddr;
                bid_2d_array[tidx][eidx] = mapped.physical_addr.bank_id;
                gid_2d_array[tidx][eidx] = mapped.physical_addr.gid;
                logical_addr_2d_array[tidx][eidx] = mapped.logical_addr;
            end
        end: each_thread
    endfunction : generate_wdata

    //-------------------------------------------------------------------------
    // @brief Copies a sampled creq and builds its active address model.
    //
    // @param shmins Source transaction sampled from the SHM input interface.
    // @post This object owns a copy and has populated length-bounded arrays.
    //-------------------------------------------------------------------------
    function void init_from(shmins_sequence_item shmins);
        this.copy(shmins);
        generate_wdata();
    endfunction : init_from

    //-------------------------------------------------------------------------
    // @brief Prints inherited creq fields and the generated write map.
    //
    // @param printer UVM printer receiving formatted fields.
    //-------------------------------------------------------------------------
    virtual function void do_print(uvm_printer printer);
        super.do_print(printer);
        printer.print_time("issue_time", issue_time);
        printer.print_generic("wmap", "byte [bit[19:0]][16]", 0, wmap_util::sprint(wmap));
    endfunction : do_print
endclass : shm_wtrans_item

`endif // INC_SHM_WTRANS_ITEM_SVH
