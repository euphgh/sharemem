`ifndef INC_SHMINS_VTRANS_SEQUENCE_ITEM_SVH
`define INC_SHMINS_VTRANS_SEQUENCE_ITEM_SVH

//------------------------------------------------------------------------------
// @brief Generates a VTRANS request using the contiguous address algorithm.
//
// The item restricts direction, request info, address space, dtype, ITYPE,
// thread participation, length, and masks according to the VTRANS protocol.
// It inherits all MADDR, base, and offset generation from the contiguous item.
//------------------------------------------------------------------------------
class shmins_vtrans_sequence_item extends shmins_contiguous_sequence_item;

  // Override the ordinary contiguous request-kind constraint inherited under
  // the same name while retaining both legal contiguous ITYPE values.
  constraint c_contiguous_kind {
    creq_info == 4'hf;
    creq_rw == SHM_V2M;
    creq_space == SPACE_LOC;
    creq_dtype inside {DTYP_16, DTYP_8};
    creq_itype inside {LDST_S, LDST_V};
    creq_tmsk == '1;

    foreach (elem_num[thread_idx]) {
      elem_num[thread_idx] == 16;
    }
    foreach (creq_vmsk[thread_idx]) {
      creq_vmsk[thread_idx] == '1;
    }
  }

  //----------------------------------------------------------------------------
  // @brief Constructs a VTRANS SHM transaction.
  //
  // @param name UVM object instance name.
  //----------------------------------------------------------------------------
  extern function new(string name = "shmins_vtrans_sequence_item");

  `uvm_object_utils(shmins_vtrans_sequence_item)
endclass : shmins_vtrans_sequence_item

function shmins_vtrans_sequence_item::new(string name = "shmins_vtrans_sequence_item");
  super.new(name);
endfunction : new

`endif // INC_SHMINS_VTRANS_SEQUENCE_ITEM_SVH
