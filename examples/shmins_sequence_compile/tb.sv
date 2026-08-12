`timescale 1ns/1ps

package shmins_sequence_compile_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
  `include "shmins_sequence_item.svh"
  `include "shmins_contiguous_sequence_item.svh"
  `include "shmins_strided_sequence_item.svh"
  `include "shmins_indexed_sequence_item.svh"
  `include "shmins_vtrans_sequence_item.svh"
  `include "shmins_enum_field.svh"
  `include "shmins_mst_unit_sequence.svh"

  //----------------------------------------------------------------------------
  // @brief Constructs the integrated SHMINS sequence classes without a DUT.
  //
  // The test makes factory and public-API references visible to elaboration.
  // It does not start the sequence, randomize an item, or drive an interface.
  //----------------------------------------------------------------------------
  class shmins_sequence_compile_test extends uvm_test;

    //----------------------------------------------------------------------------
    // @brief Constructs the compile-only UVM test.
    //
    // @param name UVM component instance name.
    // @param parent Parent component that owns this test.
    //----------------------------------------------------------------------------
    function new(string name = "shmins_sequence_compile_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    //----------------------------------------------------------------------------
    // @brief Creates representative item and sequence objects through the factory.
    //
    // @param phase UVM build phase used only as an elaboration entry point.
    //----------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
      shmins_sequence_item item;
      shmins_mst_unit_sequence seq;

      super.build_phase(phase);
      item = shmins_vtrans_sequence_item::type_id::create("item");
      seq = shmins_mst_unit_sequence::type_id::create("seq");
      seq.set_fix_rw(SHM_M2V);
      seq.set_fix_vtrans_dtype(DTYP_16);
      seq.set_vtrans_en(25);
    endfunction : build_phase

    `uvm_component_utils(shmins_sequence_compile_test)
  endclass : shmins_sequence_compile_test

endpackage : shmins_sequence_compile_pkg

//------------------------------------------------------------------------------
// @brief Provides an empty-design UVM elaboration top for sequence compilation.
//------------------------------------------------------------------------------
module shmins_sequence_compile_tb;
  import uvm_pkg::*;
  import shmins_sequence_compile_pkg::*;

  initial begin
    run_test("shmins_sequence_compile_test");
  end
endmodule : shmins_sequence_compile_tb
