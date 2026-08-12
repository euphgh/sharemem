`ifndef INC_VLM_MEMORY_SEQUENCE_ITEM_SVH
`define INC_VLM_MEMORY_SEQUENCE_ITEM_SVH

//-------------------------------------------------------------------
// Class: vlm_memory_sequence_item
//
//-------------------------------------------------------------------

class vlm_memory_sequence_item extends uvm_sequence_item;

  rand logic                      vlm_read = '0;       // 0: write; 1:read
  rand logic [BANK_N-1:0]         vlm_bken = '0;
  rand logic [BADDR_W-1:0]        vlm_addr[BANK_N] = '{BANK_N{'0}};
  rand logic [VLM_DATA_BIT_W-1:0] vlm_data[BANK_N] = '{BANK_N{'0}};
  rand logic [VLM_DATA_BYTE_W-1:0] vlm_strb[BANK_N] = '{BANK_N{'0}};
  logic [BANK_N-1:0]               vlm_gid = '0;
  logic [BANK_N-1:0]               gid_valid = '0;
  logic [BANK_N-1:0]               reservation_matched = '0;

  //
  rand int                        delay_cycle = '0;

//-------------------------------------------------------------------
// Constraints
//-------------------------------------------------------------------

//-------------------------------------------------------------------
// Methods
//-------------------------------------------------------------------

// ------------------
// Standard UVM Methods
// ------------------
  extern function        new(string name="vlm_memory_sequence_item");

// ------------------
// User Defined APIs
// ------------------

  function bit compare_item(vlm_memory_sequence_item vlm_trans);
    int error = 0;

    // do compare
    for (int bk_idx=0; bk_idx<16; bk_idx++) begin
      if (vlm_bken[bk_idx]) begin
        if (vlm_addr[bk_idx] !== vlm_trans.vlm_addr[bk_idx]) begin
          $display("[ERROR] : VLM Addr[%02d] Compare Failed: exp_addr = %x, act_addr =%x", bk_idx, vlm_addr[bk_idx], vlm_trans.vlm_addr[bk_idx]);
        end
        if (vlm_data[bk_idx] !== vlm_trans.vlm_data[bk_idx]) begin
          $display("[ERROR] : VLM Data[%02d] Compare Failed: exp_data = %x, act_data =%x", bk_idx, vlm_addr[bk_idx], vlm_trans.vlm_addr[bk_idx]);
        end
        if (vlm_read == 1'b0 && vlm_strb[bk_idx] !== vlm_trans.vlm_strb[bk_idx]) begin
          $display("[ERROR] : VLM Strb[%02d] Compare Failed: exp_strb = %x, act_strb =%x", bk_idx, vlm_strb[bk_idx], vlm_trans.vlm_strb[bk_idx]);
        end
      end
    end

    return error;

  endfunction


  function void write_file(int fp);

    if (fp) begin
      for (int bank_idx=0; bank_idx<BANK_N; bank_idx++)
        $fwrite(fp, "%x : %x\n", vlm_addr[bank_idx], vlm_data[bank_idx]);
    end
    else begin
      `uvm_fatal(get_type_name(), "Can't open write file handle")
      return;
    end

  endfunction


// ------------------
// UVM Factory Registration
// ------------------
// `uvm_object_utils_begin(vlm_memory_sequence_item#(PART_N,PART_S,VLM_DW))
`uvm_object_param_utils_begin(vlm_memory_sequence_item)
// ------------------
// Add field configurations
// ------------------
// ------------------
`uvm_field_int(vlm_read       , UVM_DEFAULT)
`uvm_field_int(vlm_bken       , UVM_DEFAULT)

`uvm_field_sarray_int(vlm_addr , UVM_DEFAULT)
`uvm_field_sarray_int(vlm_data , UVM_DEFAULT)
`uvm_field_sarray_int(vlm_strb , UVM_DEFAULT)
`uvm_field_int(vlm_gid, UVM_DEFAULT)
`uvm_field_int(gid_valid, UVM_DEFAULT)
`uvm_field_int(reservation_matched, UVM_DEFAULT)

`uvm_object_utils_end
endclass: vlm_memory_sequence_item


//-------------------------------------------------------------------
// Function: new
//
//-------------------------------------------------------------------

function vlm_memory_sequence_item::new(string name="vlm_memory_sequence_item");
  super.new(name);
endfunction: new

`endif // INC_VLM_MEMORY_SEQUENCE_ITEM_SVH
