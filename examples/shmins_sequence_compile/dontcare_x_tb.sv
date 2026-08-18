`timescale 1ns/1ps

package shmins_dontcare_x_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
  `include "shmins_sequence_item.svh"
  `include "shmins_contiguous_sequence_item.svh"
  `include "shmins_strided_sequence_item.svh"
  `include "shmins_indexed_sequence_item.svh"
  `include "shmins_vtrans_sequence_item.svh"
  `include "shmins_dontcare_x_util.svh"

  //----------------------------------------------------------------------------
  // @brief Verifies exact slice edits made by the SHMINS don’t-care X utility.
  //
  // The test randomizes legal topology items, applies one utility operation at
  // a time, and checks that interpreted payload remains known and unchanged. It
  // does not instantiate a driver, monitor, reference model, or DUT.
  //----------------------------------------------------------------------------
  class shmins_dontcare_x_test extends uvm_test;
    //----------------------------------------------------------------------------
    // @brief Constructs the don’t-care utility component test.
    //
    // @param name UVM component instance name.
    // @param parent Parent component that owns this test.
    //----------------------------------------------------------------------------
    extern function new(string name = "shmins_dontcare_x_test", uvm_component parent = null);

    //----------------------------------------------------------------------------
    // @brief Runs utility scenarios X-UTIL-001 through X-UTIL-005.
    //
    // @param phase UVM run phase controlling the test objection.
    //----------------------------------------------------------------------------
    extern virtual task run_phase(uvm_phase phase);

    //----------------------------------------------------------------------------
    // @brief Creates one legal contiguous, strided, or indexed sparse-mask item.
    //
    // @param topology 0 for contiguous, 1 for strided, or 2 for indexed.
    // @param direction V2M or M2V direction.
    // @param item_name UVM object instance name.
    // @return Generated topology item with element 0/7 active in thread zero.
    //----------------------------------------------------------------------------
    extern protected function shmins_sequence_item create_sparse_item(int unsigned topology,
                                                                       creq_rw_e direction,
                                                                       string item_name);

    `uvm_component_utils(shmins_dontcare_x_test)
  endclass : shmins_dontcare_x_test

  function shmins_dontcare_x_test::new(string name = "shmins_dontcare_x_test",
                                        uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  function shmins_sequence_item shmins_dontcare_x_test::create_sparse_item(int unsigned topology,
                                                                            creq_rw_e direction,
                                                                            string item_name);
    shmins_sequence_item item;
    shmins_contiguous_sequence_item contiguous_item;
    shmins_strided_sequence_item strided_item;
    shmins_indexed_sequence_item indexed_item;

    case (topology)
      0: begin
        contiguous_item = shmins_contiguous_sequence_item::type_id::create(item_name);
        item = contiguous_item;
      end
      1: begin
        strided_item = shmins_strided_sequence_item::type_id::create(item_name);
        item = strided_item;
      end
      2: begin
        indexed_item = shmins_indexed_sequence_item::type_id::create(item_name);
        item = indexed_item;
      end
      default: begin
        `uvm_fatal("SHMINS_DONTCARE_TEST_TOPOLOGY", $sformatf("unsupported topology %0d", topology))
        return null;
      end
    endcase

    if (!item.randomize() with {
          creq_rw == local::direction;
          creq_dtype == DTYP_8;
          creq_atype_w == ATYP_16;
          creq_atype_s == ATYP_U;
          creq_atype_g == GAUTO_1B;
          creq_space == SPACE_LOC;
          creq_wpid == 0;
          creq_tmsk == 16'h0001;
          elem_num[0] == 8;
          creq_vmsk[0][7:0] == 8'h81;
        }) begin
      `uvm_fatal("SHMINS_DONTCARE_TEST_RANDOMIZE", $sformatf("failed to randomize %s", item_name))
    end
    return item;
  endfunction : create_sparse_item

  task shmins_dontcare_x_test::run_phase(uvm_phase phase);
    shmins_sequence_item contiguous_item;
    shmins_sequence_item strided_item;
    shmins_sequence_item indexed_item;
    shmins_sequence_item m2v_item;
    logic [VEC_W-1:0] packed_offsets;
    logic [15:0] offset_zero_before;

    phase.raise_objection(this);

    contiguous_item = create_sparse_item(0, SHM_V2M, "inactive_contiguous");
    if (!shmins_dontcare_x_util::poison_inactive_threads(contiguous_item, 1'bx) ||
        $isunknown(contiguous_item.creq_prio[0]) || !$isunknown(contiguous_item.creq_prio[1]) ||
        !$isunknown(contiguous_item.creq_len[1]) || !$isunknown(contiguous_item.creq_vmsk[1]) ||
        !$isunknown(contiguous_item.creq_offs(1)) || !$isunknown(contiguous_item.creq_vdat[1])) begin
      `uvm_fatal("X_UTIL_001", "inactive-thread poisoning changed an active field or missed an inactive field")
    end

    packed_offsets = contiguous_item.creq_offs(0);
    offset_zero_before = packed_offsets[15:0];
    if (!shmins_dontcare_x_util::poison_masked_element_data(contiguous_item, 1'bx) ||
        !shmins_dontcare_x_util::poison_unused_offset_slices(contiguous_item, 1'bx)) begin
      `uvm_fatal("X_UTIL_002", "contiguous masked-data or unused-offset poisoning failed")
    end
    packed_offsets = contiguous_item.creq_offs(0);
    if ($isunknown(contiguous_item.creq_vdat[0][0]) || !$isunknown(contiguous_item.creq_vdat[0][1]) ||
        packed_offsets[15:0] !== offset_zero_before || !$isunknown(packed_offsets[31:16])) begin
      `uvm_fatal("X_UTIL_002", "contiguous masked-data or unused-offset poisoning failed")
    end

    strided_item = create_sparse_item(1, SHM_V2M, "masked_strided");
    packed_offsets = strided_item.creq_offs(0);
    offset_zero_before = packed_offsets[15:0];
    if (!shmins_dontcare_x_util::poison_masked_element_data(strided_item, 1'bx) ||
        !shmins_dontcare_x_util::poison_unused_offset_slices(strided_item, 1'bx)) begin
      `uvm_fatal("X_UTIL_002", "strided shared offset was changed or unused offset remained known")
    end
    packed_offsets = strided_item.creq_offs(0);
    if (packed_offsets[15:0] !== offset_zero_before || !$isunknown(packed_offsets[31:16])) begin
      `uvm_fatal("X_UTIL_002", "strided shared offset was changed or unused offset remained known")
    end

    indexed_item = create_sparse_item(2, SHM_V2M, "masked_indexed");
    if (!shmins_dontcare_x_util::poison_masked_element_data(indexed_item, 1'bx) ||
        !shmins_dontcare_x_util::poison_indexed_masked_offsets(indexed_item, 1'bx)) begin
      `uvm_fatal("X_UTIL_003", "indexed masked data/offset poisoning crossed an active-element boundary")
    end
    packed_offsets = indexed_item.creq_offs(0);
    if ($isunknown(packed_offsets[15:0]) || !$isunknown(packed_offsets[31:16]) ||
        $isunknown(packed_offsets[127:112]) || $isunknown(indexed_item.creq_vdat[0][0]) ||
        !$isunknown(indexed_item.creq_vdat[0][1])) begin
      `uvm_fatal("X_UTIL_003", "indexed masked data/offset poisoning crossed an active-element boundary")
    end

    if (!shmins_dontcare_x_util::poison_out_of_length_payload(indexed_item, 1'bx)) begin
      `uvm_fatal("X_UTIL_004", "out-of-length poisoning failed")
    end
    packed_offsets = indexed_item.creq_offs(0);
    if ($isunknown(indexed_item.creq_vmsk[0][7]) || !$isunknown(indexed_item.creq_vmsk[0][8]) ||
        $isunknown(indexed_item.creq_vdat[0][7]) || !$isunknown(indexed_item.creq_vdat[0][8]) ||
        $isunknown(packed_offsets[127:112]) || !$isunknown(packed_offsets[143:128])) begin
      `uvm_fatal("X_UTIL_004", "out-of-length poisoning changed bounded payload or missed tail payload")
    end

    m2v_item = create_sparse_item(0, SHM_M2V, "m2v_unused_data");
    if (!shmins_dontcare_x_util::poison_m2v_vdata(m2v_item, 1'bx) ||
        !$isunknown(m2v_item.creq_vdat[0]) || $isunknown(m2v_item.creq_vmsk[0][0])) begin
      `uvm_fatal("X_UTIL_005", "M2V unused input-data poisoning changed interpreted payload")
    end

    `uvm_info("SHMINS_DONTCARE_X_TEST", "don’t-care X utility component matrix: PASS", UVM_LOW)
    phase.drop_objection(this);
  endtask : run_phase
endpackage : shmins_dontcare_x_test_pkg

//------------------------------------------------------------------------------
// @brief Provides an empty-design top for the don’t-care X utility test.
//------------------------------------------------------------------------------
module shmins_dontcare_x_tb;
  import uvm_pkg::*;
  import shmins_dontcare_x_test_pkg::*;

  initial begin
    run_test("shmins_dontcare_x_test");
  end
endmodule : shmins_dontcare_x_tb
