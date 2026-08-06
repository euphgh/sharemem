`ifndef INC_SHM_WTRANS_ITEM_SVH
`define INC_SHM_WTRANS_ITEM_SVH

class shm_wtrans_item extends shmins_sequence_item;
    parameter int unsigned ELEM_MAX_N = VEC_BYTE_N;
    `uvm_object_utils(shm_wtrans_item)

    typedef bit [MADDR_W-1:0] maddr_t;
    typedef vlm2aa::baddr_t baddr_t;
    typedef bit_rt_range#(MADDR_W) maddr_getter;
    typedef bit_rt_range#(BADDR_W) baddr_setter;
    typedef bit [$clog2(BANK_N)-1:0] bidx_t;

    typedef vlm2aa::wmap_util wmap_util;
    typedef vlm2aa::wmap_t wmap_t;
    // new field for compare
    time issue_time;
    wmap_t wmap;
    baddr_t baddr_2d_array[BANK_N][];
    bidx_t bid_2d_array[BANK_N][];
    // support max dtype 64
    byte wstrb_2d_array[BANK_N][];

    function new(string name = "ref_item");
        super.new(name);
        issue_time = $time;
    endfunction

    //---------------------------------------------------------------------
    // @brief Calculate creq_offs shift operator
    //---------------------------------------------------------------------
    function int unsigned get_offs_shift_op();
        get_offs_shift_op = 0;
        if ($isunknown(creq_atype_g)) begin
            `uvm_error(get_type_name(), $sformatf("Fail to calculte offset shift operator for unknown creq_atype_g: %x", creq_atype_g));
        end
        if (creq_atype_g == GAUTO_DW) begin
            if ($isunknown(creq_dtype)) begin
                `uvm_error(get_type_name(), $sformatf("Fail to calculte offset shift operator for unknown creq_atype_g: %x", creq_dtype));
            end
            get_offs_shift_op = creq_dtype == DTYP_32 ? 2 :
                                 creq_dtype == DTYP_16 ? 1 : 0;
        end
    endfunction

    //-----------------------------------------------------------------------------
    // @brief Calculate write/read database
    // @param
    //-----------------------------------------------------------------------------
    function void cal_unify_addr(input int tidx, ref bit [MADDR_W-1:0] elem_unify_addr[], ref int eoff_val[]);
        const int unsigned this_max_elem_cnt = max_elem_cnt();
        const int unsigned offs_sft = get_offs_shift_op();
        const int unsigned elem_byten = data_byte_w();
        bit [VEC_W-1:0] t_offs = creq_offs(tidx);
        eoff_val    = new[this_max_elem_cnt];
        elem_unify_addr = new[this_max_elem_cnt];
        for(int unsigned bidx = 0; bidx < this_max_elem_cnt; bidx ++) begin: each_elem_slot
            if(creq_itype == LDST_S || creq_itype == LDST_V) begin: vec_en_toff
                if(creq_atype_w == ATYP_32) begin: atype32
                    // support max 32 elemnt
                    eoff_val[bidx] = t_offs[31:0];
                end: atype32
                else if(creq_atype_w == ATYP_16) begin: atype16
                    // support max 32 elemnt
                    if (creq_atype_s == ATYP_S) begin
                        eoff_val[bidx] = $unsigned(32'($signed(t_offs[15:0])));
                    end
                    else begin
                        eoff_val[bidx] = 32'(t_offs[15:0]);
                    end
                end: atype16
                else begin: atype8
                    // support max 32 elemnt
                    if (creq_atype_s == ATYP_S) begin
                        eoff_val[bidx] = $unsigned(32'($signed(t_offs[7:0])));
                    end
                    else begin
                        eoff_val[bidx] = 32'(t_offs[7:0]);
                    end
                end: atype8
                eoff_val[bidx] = (eoff_val[bidx] << offs_sft) + (bidx * $unsigned(elem_byten));
            end: vec_en_toff
            else if(creq_itype == LDSTE_V) begin: ele_en_eoff
                if(creq_atype_w == ATYP_32) begin
                    // ATYP_32 mode, only support 8 element
                    eoff_val[bidx] = t_offs[bidx*32+:32];
                end
                else if(creq_atype_w == ATYP_16) begin: atype16
                    // ATYP_16 mode, only support 16 element
                    if (creq_atype_s == ATYP_S) begin
                        eoff_val[bidx] = $unsigned(32'($signed(t_offs[bidx*16+:16])));
                    end
                    else begin
                        eoff_val[bidx] = 32'(t_offs[bidx*16+:16]);
                    end
                end: atype16
                else begin: atype8
                    if (creq_atype_s == ATYP_S) begin
                        eoff_val[bidx] = $unsigned(32'($signed(t_offs[bidx*8+:8])));
                    end
                    else begin
                        eoff_val[bidx] = 32'(t_offs[bidx*8+:8]);
                    end
                end: atype8
                eoff_val[bidx] = eoff_val[bidx] << offs_sft;
            end: ele_en_eoff
            else if (creq_itype === LDSTE_S) begin: lsdte_s
                if(creq_atype_w === ATYP_32)
                    if (creq_atype_s == ATYP_S) begin
                        eoff_val[bidx] = $unsigned($signed(t_offs[31:0]) * $signed(bidx));
                    end
                    else begin
                        eoff_val[bidx] = (t_offs[31:0] * bidx);
                    end
                else if(creq_atype_w === ATYP_16)
                    if (creq_atype_s == ATYP_S) begin
                        eoff_val[bidx] = $unsigned(int'($signed(t_offs[15:0])) * $signed(bidx));
                    end
                    else begin
                        eoff_val[bidx] = $unsigned(32'($unsigned(t_offs[15:0])) * bidx); 
                    end
                else begin
                    if (creq_atype_s) begin
                        eoff_val[bidx] = $unsigned(int'($signed(t_offs[7:0])) * $signed(bidx));
                    end
                    else begin
                        eoff_val[bidx] = $unsigned(32'($unsigned(t_offs[7:0])) * bidx);
                    end
                end
                eoff_val[bidx] = eoff_val[bidx] << offs_sft;
            end: lsdte_s
        end: each_elem_slot
    endfunction
    //-----------------------------------------------------------------------------
    // @brief Calculate write/read database
    //-----------------------------------------------------------------------------
    function void generate_wdata();
        const int unsigned elem_byten = data_byte_w();
        const int unsigned this_max_elem_cnt = max_elem_cnt();
        const int unsigned wpidx_width = $clog2(creq_wpnum);
        const int unsigned inv_size = 2 + int'(creq_inv_size);
        const string action = creq_rw == SHM_V2M ? "W" : "R";
        const string space_name = creq_space_e_to_str(creq_space);

        // Inactive thread payload may contain X/Z. Keep its derived arrays empty
        // so no address, reservation, MEM request, or writeback expectation is built.
        for (int i = 0; i < BANK_N; i++) begin
            if (creq_tmsk[i] === 1'b1) begin
                baddr_2d_array[i] = new[this_max_elem_cnt];
                bid_2d_array [i] = new[this_max_elem_cnt];
                wstrb_2d_array[i] = new[this_max_elem_cnt];
            end
            else begin
                baddr_2d_array[i] = new[0];
                bid_2d_array [i] = new[0];
                wstrb_2d_array[i] = new[0];
            end
        end

        for (int tidx = 0; tidx < THD_N; tidx ++) begin: each_thread
            bit [MADDR_W-1:0] elem_unify_addr[];
            int eoff_val[];

            if (creq_tmsk[tidx] !== 1'b1) begin
                `uvm_info(get_type_name(), $sformatf("Skip inactive thread %0d", tidx), UVM_FULL)
                continue;
            end

            // 1. calculate offset
            cal_unify_addr(tidx, elem_unify_addr, eoff_val);

            foreach(elem_unify_addr[eidx]) begin
                if (creq_atype_s) begin
                    elem_unify_addr[eidx] = $unsigned($signed(creq_base[MADDR_W-1:0]) + $signed(eoff_val[eidx][MADDR_W-1:0]));
                end
                else begin
                    elem_unify_addr[eidx] = $unsigned(creq_base[MADDR_W-1:0] + eoff_val[eidx][MADDR_W-1:0]);
                end
                if (creq_vmsk[tidx][eidx]) begin
                    byte wstrb = 0;
                    for (int i = 0; i < elem_byten; i++) begin
                        wstrb[i] = int'(creq_len[tidx]) > ((elem_byten * eidx) + i);
                    end
                    wstrb_2d_array[tidx][eidx] = wstrb;
                end
                else begin
                    wstrb_2d_array[tidx][eidx] = 0;
                end
            end

            // start map from unify addr to bank addr according to creq_space and creq_ilv_size
            foreach(elem_unify_addr[eidx]) begin
                vlm_memory_sequence_item out = new("golden_vlm_memory_sequence_item");
                maddr_t elem_maddr = elem_unify_addr[eidx];
                // data field from elem_madr
                maddr_t inv_offs = maddr_getter::get_range(elem_maddr, inv_size-1, 0);
                // convert maddr to baddr and bid
                baddr_t elem_baddr;
                maddr_t warp_index;
                maddr_t inv_index;
                bidx_t elem_bid = bidx_t'(maddr_getter::get_plus_range(elem_maddr, inv_size, $clog2(BANK_N)));
                elem_baddr = baddr_setter::set_plus_range(elem_baddr, baddr_t'(inv_offs), 0, inv_size);

                if(creq_space == $bits(creq_space)'(SPACE_BLK)) begin
                    //   |      inv_index      |    warp_offs   |  bank_idx  |  inv_offs  |
                    //   | MADDR_W - $clog2(BANK_N) - inv_size - wpidx_width | wpidx_width | $clog2(BANK_N) | inv_size |
                    int inv_index_w = MADDR_W - inv_size - $clog2(BANK_N) - wpidx_width;
                    maddr_t warp_offs = maddr_getter::get_plus_range(elem_maddr, inv_size + $clog2(BANK_N), wpidx_width);
                    inv_index = maddr_getter::get_range(elem_maddr, MADDR_W-1, inv_size + $clog2(BANK_N) + wpidx_width);
                    warp_index = warp_offs;
                    elem_baddr = baddr_setter::set_plus_range(elem_baddr, baddr_t'(inv_index), inv_size, inv_index_w);
                    elem_baddr += baddr_t'(WARP_STEP * int'(warp_offs));
                end
                else if (creq_space == $bits(creq_space)'(SPACE_WRP)) begin
                    // |  th_line_idx   |    bank_idx   |  thread_line_offs |
                    // | VADDR_W - inv_size | $clog2(BANK_N) |    inv_size    |
                    int inv_index_w = VADDR_W - inv_size;
                    inv_index = maddr_getter::get_plus_range(elem_maddr, inv_size + $clog2(BANK_N), inv_index_w);
                    warp_index = maddr_t'(creq_wpid);
                    elem_baddr = baddr_setter::set_plus_range(elem_baddr, baddr_t'(inv_index), inv_size, inv_index_w);
                    elem_baddr += baddr_t'(WARP_STEP * int'(warp_index));
                end
                else if (creq_space == $bits(creq_space)'(SPACE_LOC)) begin
                    // |    dont care    |   VLM address   |
                    // |        7        |      VADDR_W    |
                    int inv_index_w = VADDR_W - inv_size;
                    inv_index = maddr_getter::get_plus_range(elem_maddr, inv_size, inv_index_w);
                    warp_index = maddr_t'(creq_wpid);
                    elem_baddr = baddr_setter::set_plus_range(elem_baddr, baddr_t'(inv_index), inv_size, inv_index_w);
                    elem_baddr += baddr_t'(WARP_STEP * int'(warp_index));
                    elem_bid = tidx;
                end
                else begin
                    `uvm_error(get_type_name(), "creq_space not expect");
                end

                `uvm_info(get_type_name(), $sformatf("THD[%0d].Elem[%0d] %s Bank[%0d][0x%x].Strb[0x%x] = %s[0x%x] = (%0d x 12KB) + {0x%x, 0x%x} = B + Offs(0x%x)", 
                tidx, eidx, action, elem_bid, elem_baddr, wstrb_2d_array[tidx][eidx], space_name, elem_maddr, warp_index, inv_index, inv_offs, eoff_val[eidx]), UVM_FULL);
                baddr_2d_array[tidx][eidx] = elem_baddr;
                bid_2d_array[tidx][eidx] = elem_bid;
            end
        end: each_thread
    endfunction

    function void init_from(shmins_sequence_item shmins);
        this.copy(shmins);
        generate_wdata ();
    endfunction

    virtual function void do_print(uvm_printer printer);
        super.do_print(printer);// 先打印父类字段
        printer.print_time("issue_time", issue_time);
        printer.print_generic("wmap" , "byte [bit[19:0]][16]", 0, wmap_util::sprint(wmap)) ;
    endfunction
endclass

`endif // INC_SHM_WTRANS_ITEM_SVH
