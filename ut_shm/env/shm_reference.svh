`ifndef INC_SHM_REFERENCE_SVH
`define INC_SHM_REFERENCE_SVH

import shm_util_package::*;

`include "shm_wtrans_item.svh"

// TLM Analysis Imp Declaration
//AUTO_GEN_REF_IMP_BEGIN
`uvm_analysis_imp_decl(_shmins__reference)
`uvm_analysis_imp_decl(_rdvlm__reference)
//AUTO_GEN_REF_IMP_END

//-----------------------------------------------------------------------------
// Class: shm_reference
//-----------------------------------------------------------------------------
class shm_reference extends uvm_component;

    // Data Members
    //---------------------------------------------------------------------
    int trans_cnt = 0;

    string filename = "vlm.ref";
    int    vlm_ref_fp;
    svt_mem ref_banks[BANK_N];
    typedef vlm2aa::baddr_t baddr_t;
    typedef bit [$clog2(BANK_N)-1:0] bidx_t;

    // Interface Instantiation
    //---------------------------------------------------------------------

    // Environment Configuration Instantiation
    //---------------------------------------------------------------------
    shm_environment_config shm_environment_cfg;

    // Coverage
    //---------------------------------------------------------------------

    // Port Declaration
    //---------------------------------------------------------------------

    //AUTO_GEN_REF_TLM_OBJECT_BEGIN
    uvm_analysis_imp_shmins__reference #(shmins_sequence_item, shm_reference) shmins_analysis_export;

    //AUTO_GEN_REF_TLM_OBJECT_END
    uvm_analysis_port #(shm_wtrans_item) wdata_ass_arr_port;

    extern function        new(string name="shm_reference", uvm_component parent);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task     configure_phase(uvm_phase phase);

    // User Defined APIs
    //---------------------------------------------------------------------
    //AUTO_GEN_REF_TLM_EXTERN_BEGIN
    extern function void write_shmins__reference(shmins_sequence_item shmins_trans);
    extern function void write_rdvlm__reference(vlm_sequence_item vlm_trans);

    extern function void v2m_write_wmap(string label, int tidx, int eidx, int lidx, byte unsigned wdata, shm_wtrans_item item);
    extern function void write_wmap(string label, int tidx, int eidx, int lidx, bit wen, bidx_t bid, baddr_t baddr, byte unsigned wdata, shm_wtrans_item item);
    //AUTO_GEN_REF_TLM_EXTERN_END
    //extern function void shm_refmodel(shmins_sequence_item shmins_trans);

    // UVM Factory Registration
    //---------------------------------------------------------------------
    `uvm_component_utils_begin(shm_reference)
    // Add field configurations
    //---------------------------------------------------------------------

    `uvm_component_utils_end
endclass: shm_reference


function shm_reference::new(string name = "shm_reference", uvm_component parent);
    super.new(name, parent);
    //AUTO_GEN_REF_TLM_NEW_BEGIN
    shmins_analysis_export = new("shmins_analysis_export", this);
    wdata_ass_arr_port = new("wdata_ass_arr_port", this);
    //AUTO_GEN_REF_TLM_NEW_END

    if ($test$plusargs("file_debug")) begin
        vlm_ref_fp = $fopen(filename, "w");
    end
endfunction: new

//-----------------------------------------------------------------------------
// Function: build_phase
//-----------------------------------------------------------------------------
// Create and configure of testbench structure
//-----------------------------------------------------------------------------
function void shm_reference::build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info(get_type_name(), "In build_phase...!!", UVM_DEBUG);
    // Get Environment Configuration
    if (!uvm_config_db#(shm_environment_config)::get(this, "", "shm_environment_config", shm_environment_cfg)) begin
        `uvm_error(get_type_name(), "shm_environment_config object is not found in config db!");
    end
    else begin
        shm_environment_cfg.print();
    end

    foreach(ref_banks[i]) begin
        int baddr_max = (1 << BADDR_W) - 1;
        ref_banks[i] = new($sformatf("ref_bank_%0x", i),      // Memory name
                           "REF_BANKS",                       // Suite name
                           8,                                // data width
                           0,                                // Address region
                           0,                                // Lower address bound to memory
                           baddr_max);                       // Upper address bound to memory
    end

endfunction: build_phase

task shm_reference::configure_phase(uvm_phase phase);
    foreach(ref_banks[i]) begin
        ref_banks[i].set_meminit(svt_mem::INCR, i << 4);
    end
endtask: configure_phase

function void shm_reference::write_wmap(string label, int tidx, int eidx, int lidx, bit wen, bidx_t bid, baddr_t baddr, byte unsigned wdata, shm_wtrans_item item);
    if (wen) begin
        `uvm_info(get_type_name(), $sformatf("%s Thd[%0d].Elem[%0d].Lane[%0d] W bank[%0d]@0x%x 0x%x", label, tidx, eidx, lidx, bid, baddr, wdata), UVM_FULL);
        if (item.wmap[bid].exists(baddr))
            `uvm_error(get_type_name(), $sformatf("%s write address overlap at %x, %x -> %x", label, baddr, item.wmap[bid][baddr], wdata));
        item.wmap[bid][baddr] = wdata;
        ref_banks[bid].write(baddr, wdata);
    end
endfunction: write_wmap

function void shm_reference::v2m_write_wmap(string label, int tidx, int eidx, int lidx, byte unsigned wdata, shm_wtrans_item item);
    bit     wen   = item.wstrb_2d_array[tidx][eidx][lidx];
    bidx_t  bid   = item.bid_2d_array[tidx][eidx];
    baddr_t baddr = item.baddr_2d_array[tidx][eidx] + baddr_t'(lidx);
    write_wmap(label, tidx, eidx, lidx, wen, bid, baddr, wdata, item);
endfunction: v2m_write_wmap

function void shm_reference::write_shmins__reference(shmins_sequence_item shmins_trans);
    shm_wtrans_item wgolden = shm_wtrans_item::type_id::create("ref_shm_wtrans", this);
    wgolden.init_from(shmins_trans);
    if (shmins_trans.creq_rw == SHM_V2M) begin
        const int unsigned elem_byten = wgolden.data_byte_w();
        foreach(wgolden.baddr_2d_array[tidx, eidx]) begin
            byte elem_wmask = wgolden.wstrb_2d_array[tidx][eidx];
            if (wgolden.creq_info == 1) begin: vtrans_v2m
                if (eidx >= 16) continue;
                for(int unsigned byte_idx = 0; byte_idx < elem_byten; byte_idx++) begin: foreach_byte
                    int data_offset = tidx * elem_byten + byte_idx;
                    byte byte_wdata = wgolden.creq_vdata[tidx][data_offset];
                    v2m_write_wmap("VTRANS", tidx, eidx, byte_idx, byte_wdata, wgolden);
                end: foreach_byte
            end: vtrans_v2m
            else begin: normal_v2m
                for(int unsigned byte_idx = 0; byte_idx < elem_byten; byte_idx++) begin: foreach_byte
                    int data_offset = eidx * elem_byten + byte_idx;
                    byte byte_wdata = wgolden.creq_vdata[tidx][data_offset];
                    v2m_write_wmap("V2M", tidx, eidx, byte_idx, byte_wdata, wgolden);
                end: foreach_byte
            end: normal_v2m
        end
    end
    else begin: m2v
        byte unsigned rdata[BANK_N][VEC_BYTE_N];
        int elem_byte_n = wgolden.data_byte_w();
        baddr_t waddr_base = baddr_t'(wgolden.creq_vaddr) + baddr_t'(WARP_STEP * int'(wgolden.creq_wpid));
        // tidx: thread index, eidx: element index
        foreach(wgolden.baddr_2d_array[tidx, eidx]) begin
            // the value of wmap in read mode is the element/byte index
            for (int unsigned i = 0; i < elem_byte_n; i++) begin
                baddr_t baddr = wgolden.baddr_2d_array[tidx][eidx] + i;
                bidx_t bidx = wgolden.bid_2d_array[tidx][eidx];
                byte raw_data = ref_banks[bidx].read(baddr);
                rdata[tidx][eidx * elem_byte_n + i] = raw_data;
                `uvm_info(get_type_name(), $sformatf("M2V Thd[%0d].Elem[%0d].Lane[%0d] R bank[%0d]@0x%x = %x", tidx, eidx, i, bidx, baddr, raw_data), UVM_FULL);
            end
        end

        foreach(wgolden.baddr_2d_array[tidx, eidx]) begin
            for (int unsigned i = 0; i < elem_byte_n; i++) begin
                baddr_t wr_baddr = waddr_base + eidx * elem_byte_n + i;
                byte unsigned value = rdata[tidx][eidx * elem_byte_n + i];
                bit wen = wgolden.wstrb_2d_array[tidx][eidx][i];
                write_wmap("M2V", tidx, eidx, i, wen, tidx, wr_baddr, value, wgolden);
            end
        end
    end: m2v

    wdata_ass_arr_port.write(wgolden);
    trans_cnt++;
endfunction

`endif //INC_SHM_REFERENCE_SVH