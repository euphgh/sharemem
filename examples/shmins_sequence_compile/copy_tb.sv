`timescale 1ns/1ps

package shmins_transaction_copy_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
  `include "shmins_sequence_item.svh"
  `include "shmins_contiguous_sequence_item.svh"
  `include "shmins_strided_sequence_item.svh"
  `include "shmins_indexed_sequence_item.svh"
  `include "shmins_vtrans_sequence_item.svh"

  //----------------------------------------------------------------------------
  // @brief Verifies copy and registered-field compare behavior for every SHMINS topology.
  //
  // Randomizes valid normal and VTRANS items, copies them into the same dynamic
  // type, and checks both registered transaction fields and generated address
  // state. It does not instantiate or drive a DUT.
  //----------------------------------------------------------------------------
  class shmins_transaction_copy_test extends uvm_test;

    // Number of topology items that completed all copy and compare checks.
    int unsigned checked_item_count;

    //----------------------------------------------------------------------------
    // @brief Constructs the transaction copy component test.
    //
    // @param name UVM component instance name.
    // @param parent Parent component that owns this test.
    //----------------------------------------------------------------------------
    extern function new(string name = "shmins_transaction_copy_test", uvm_component parent = null);

    //----------------------------------------------------------------------------
    // @brief Randomizes and checks contiguous, strided, indexed, and VTRANS items.
    //
    // @param phase UVM run phase controlling the test objection.
    //----------------------------------------------------------------------------
    extern virtual task run_phase(uvm_phase phase);

    //----------------------------------------------------------------------------
    // @brief Checks common copy state and positive/negative compare behavior.
    //
    // @param source Valid randomized item used as the copy source.
    // @param destination Same-topology item receiving source through copy().
    // @param label Stable topology label used in failure diagnostics.
    //----------------------------------------------------------------------------
    extern protected function void check_item_copy(shmins_sequence_item source,
                                                    shmins_sequence_item destination,
                                                    string label);

    //----------------------------------------------------------------------------
    // @brief Checks generated state that is intentionally not part of compare().
    //
    // @param source Item containing the expected generated address state.
    // @param destination Item whose copied generated state is checked.
    // @param label Stable topology label used in failure diagnostics.
    //----------------------------------------------------------------------------
    extern protected function void check_generated_state(shmins_sequence_item source,
                                                          shmins_sequence_item destination,
                                                          string label);

    `uvm_component_utils(shmins_transaction_copy_test)
  endclass : shmins_transaction_copy_test

  function shmins_transaction_copy_test::new(string name = "shmins_transaction_copy_test",
                                              uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  task shmins_transaction_copy_test::run_phase(uvm_phase phase);
    shmins_contiguous_sequence_item contiguous_source;
    shmins_contiguous_sequence_item contiguous_copy;
    shmins_strided_sequence_item strided_source;
    shmins_strided_sequence_item strided_copy;
    shmins_indexed_sequence_item indexed_source;
    shmins_indexed_sequence_item indexed_copy;
    shmins_vtrans_sequence_item vtrans_source;
    shmins_vtrans_sequence_item vtrans_copy;

    phase.raise_objection(this);

    contiguous_source = shmins_contiguous_sequence_item::type_id::create("contiguous_source");
    contiguous_copy = shmins_contiguous_sequence_item::type_id::create("contiguous_copy");
    if (!contiguous_source.randomize() with {
          creq_rw == SHM_M2V;
          creq_dtype == DTYP_16;
          creq_atype_w == ATYP_16;
          creq_atype_s == ATYP_S;
          creq_atype_g == GAUTO_DW;
          creq_itype == LDST_S;
          creq_space == SPACE_WRP;
          creq_wpid == 4;
          creq_wpnum == 2;
          creq_id == 8'ha5;
          creq_ack_en == 1'b1;
          delay_cycle == 7;
          creq_tmsk[0] == 1'b1;
          creq_tmsk[THD_N-1] == 1'b1;
          $countones(creq_tmsk) == 2;
          elem_num[0] == 4;
          elem_num[THD_N-1] == 3;
          creq_vmsk[0][3:0] == 4'hf;
          creq_vmsk[THD_N-1][2:0] == 3'h7;
        }) begin
      `uvm_fatal("SHMINS_COPY_CONTIGUOUS_RANDOMIZE", "failed to randomize contiguous source")
    end
    contiguous_source.item_to_rtl();
    check_item_copy(contiguous_source, contiguous_copy, "contiguous");

    strided_source = shmins_strided_sequence_item::type_id::create("strided_source");
    strided_copy = shmins_strided_sequence_item::type_id::create("strided_copy");
    if (!strided_source.randomize() with {
          creq_rw == SHM_M2V;
          creq_dtype == DTYP_8;
          creq_atype_w == ATYP_32;
          creq_atype_s == ATYP_S;
          creq_atype_g == GAUTO_1B;
          creq_space == SPACE_BLK;
          creq_wpid == 7;
          creq_wpnum == 1;
          creq_id == 8'h5a;
          delay_cycle == 5;
          creq_tmsk[0] == 1'b1;
          creq_tmsk[THD_N-1] == 1'b1;
          $countones(creq_tmsk) == 2;
          elem_num[0] == 5;
          elem_num[THD_N-1] == 4;
          creq_vmsk[0][4:0] == 5'h1f;
          creq_vmsk[THD_N-1][3:0] == 4'hf;
        }) begin
      `uvm_fatal("SHMINS_COPY_STRIDED_RANDOMIZE", "failed to randomize strided source")
    end
    strided_source.item_to_rtl();
    check_item_copy(strided_source, strided_copy, "strided");

    indexed_source = shmins_indexed_sequence_item::type_id::create("indexed_source");
    indexed_copy = shmins_indexed_sequence_item::type_id::create("indexed_copy");
    if (!indexed_source.randomize() with {
          creq_rw == SHM_M2V;
          creq_dtype == DTYP_32;
          creq_atype_w == ATYP_16;
          creq_atype_s == ATYP_U;
          creq_atype_g == GAUTO_DW;
          creq_space == SPACE_LOC;
          creq_wpid == 3;
          creq_wpnum == 4;
          creq_id == 8'h3c;
          creq_ack_en == 1'b1;
          delay_cycle == 3;
          creq_tmsk[0] == 1'b1;
          creq_tmsk[THD_N-1] == 1'b1;
          $countones(creq_tmsk) == 2;
          elem_num[0] == 3;
          elem_num[THD_N-1] == 2;
          creq_vmsk[0][2:0] == 3'h7;
          creq_vmsk[THD_N-1][1:0] == 2'h3;
        }) begin
      `uvm_fatal("SHMINS_COPY_INDEXED_RANDOMIZE", "failed to randomize indexed source")
    end
    indexed_source.item_to_rtl();
    check_item_copy(indexed_source, indexed_copy, "indexed");

    for (int unsigned dtype_idx = 0; dtype_idx < 2; dtype_idx++) begin
      creq_dtype_e vtrans_dtype = dtype_idx == 0 ? DTYP_8 : DTYP_16;
      for (int unsigned itype_idx = 0; itype_idx < 2; itype_idx++) begin
        creq_itype_e vtrans_itype = itype_idx == 0 ? LDST_S : LDST_V;
        string label = $sformatf("vtrans_dtype%0d_itype%0d", vtrans_dtype, vtrans_itype);

        vtrans_source = shmins_vtrans_sequence_item::type_id::create({label, "_source"});
        vtrans_copy = shmins_vtrans_sequence_item::type_id::create({label, "_copy"});
        if (!vtrans_source.randomize() with {
              creq_dtype == local::vtrans_dtype;
              creq_atype_w == ATYP_32;
              creq_atype_s == ATYP_U;
              creq_atype_g == GAUTO_1B;
              creq_itype == local::vtrans_itype;
              creq_wpid == 0;
              creq_id == 8'hc3;
              creq_ack_en == 1'b1;
              delay_cycle == 9;
            }) begin
          `uvm_fatal("SHMINS_COPY_VTRANS_RANDOMIZE", $sformatf("failed to randomize %s", label))
        end
        foreach (vtrans_source.elem_num[thread_idx]) begin
          int unsigned expected_length = vtrans_dtype == DTYP_8 ? 16 : 32;
          if (vtrans_source.creq_tmsk !== '1 || vtrans_source.elem_num[thread_idx] != 16 ||
              vtrans_source.creq_len[thread_idx] != expected_length ||
              vtrans_source.creq_vmsk[thread_idx] !== '1) begin
            `uvm_fatal("SHMINS_COPY_VTRANS_MASK",
                       $sformatf("%s thread %0d does not satisfy the VTRANS full-mask contract",
                                 label, thread_idx))
          end
        end
        vtrans_source.item_to_rtl();
        check_item_copy(vtrans_source, vtrans_copy, label);
      end
    end

    if (checked_item_count != 7) begin
      `uvm_fatal("SHMINS_COPY_COUNT", $sformatf("expected 7 checked items, observed %0d", checked_item_count))
    end

    `uvm_info("SHMINS_COPY_TEST", "transaction copy and compare component test: PASS", UVM_LOW)
    phase.drop_objection(this);
  endtask : run_phase

  function void shmins_transaction_copy_test::check_item_copy(shmins_sequence_item source,
                                                               shmins_sequence_item destination,
                                                               string label);
    logic [ID_W-1:0] copied_id;

    destination.copy(source);
    if (!destination.compare_item(source)) begin
      `uvm_fatal("SHMINS_COPY_REGISTERED", $sformatf("%s registered fields differ after copy", label))
    end
    check_generated_state(source, destination, label);

    copied_id = destination.creq_id;
    destination.creq_id = copied_id ^ ID_W'(1);
    if (destination.compare_item(source)) begin
      `uvm_fatal("SHMINS_COMPARE_NEGATIVE", $sformatf("%s compare accepted a changed creq_id", label))
    end
    destination.creq_id = copied_id;
    if (!destination.compare_item(source)) begin
      `uvm_fatal("SHMINS_COMPARE_RESTORE", $sformatf("%s compare failed after restoring creq_id", label))
    end

    checked_item_count++;
  endfunction : check_item_copy

  function void shmins_transaction_copy_test::check_generated_state(shmins_sequence_item source,
                                                                     shmins_sequence_item destination,
                                                                     string label);
    shmins_contiguous_sequence_item contiguous_source;
    shmins_contiguous_sequence_item contiguous_destination;

    if (destination.wpid_width != source.wpid_width || destination.elem_cnt_max != source.elem_cnt_max ||
        destination.generation_retry_count != source.generation_retry_count ||
        destination.generation_reject_count != source.generation_reject_count ||
        destination.validation_error_count != source.validation_error_count) begin
      `uvm_fatal("SHMINS_COPY_GENERATION_META", $sformatf("%s generation metadata differs after copy", label))
    end

    foreach (source.offs_elem[thread_idx, elem_idx]) begin
      if (destination.offs_elem[thread_idx][elem_idx] != source.offs_elem[thread_idx][elem_idx] ||
          destination.elem_maddr[thread_idx][elem_idx] != source.elem_maddr[thread_idx][elem_idx] ||
          destination.elem_logical_addr[thread_idx][elem_idx] !== source.elem_logical_addr[thread_idx][elem_idx] ||
          destination.elem_physical_addr[thread_idx][elem_idx] !==
              source.elem_physical_addr[thread_idx][elem_idx]) begin
        `uvm_fatal("SHMINS_COPY_GENERATED_ADDRESS",
                   $sformatf("%s generated address state differs at thread %0d element %0d",
                             label, thread_idx, elem_idx))
      end
    end

    if ($cast(contiguous_source, source)) begin
      if (!$cast(contiguous_destination, destination)) begin
        `uvm_fatal("SHMINS_COPY_CONTIGUOUS_CAST", $sformatf("%s destination lost contiguous type", label))
      end
      foreach (contiguous_source.start_maddr[thread_idx]) begin
        if (contiguous_destination.start_maddr[thread_idx] != contiguous_source.start_maddr[thread_idx]) begin
          `uvm_fatal("SHMINS_COPY_START_MADDR",
                     $sformatf("%s start MADDR differs at thread %0d", label, thread_idx))
        end
      end
    end
  endfunction : check_generated_state

endpackage : shmins_transaction_copy_test_pkg

//------------------------------------------------------------------------------
// @brief Provides an empty-design top for the SHMINS transaction copy test.
//------------------------------------------------------------------------------
module shmins_transaction_copy_tb;
  import uvm_pkg::*;
  import shmins_transaction_copy_test_pkg::*;

  initial begin
    run_test("shmins_transaction_copy_test");
  end
endmodule : shmins_transaction_copy_tb
