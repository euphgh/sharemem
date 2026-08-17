`ifndef INC_SHM_VTRANS_FULL_MASK_TEST_SVH
`define INC_SHM_VTRANS_FULL_MASK_TEST_SVH

//------------------------------------------------------------------------------
// @brief Verifies all supported VTRANS dtype/itype full-mask combinations.
//
// Each item uses the production VTRANS sequence item, reference transpose, DUT
// data path, scoreboard, request coverage, and lifecycle retirement.
//------------------------------------------------------------------------------
class shm_vtrans_full_mask_test extends shm_directed_base_test;

  //----------------------------------------------------------------------------
  // @brief Constructs the VTRANS full-mask test.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this test.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_vtrans_full_mask_test", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Runs the two-dtype by two-itype VTRANS matrix.
  //
  // @param phase UVM main phase controlling the test objection.
  //----------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  //----------------------------------------------------------------------------
  // @brief Builds, sends, and checks one isolated VTRANS matrix cell.
  //
  // @param dtype DTYP_8 or DTYP_16.
  // @param itype LDST_S or LDST_V.
  //----------------------------------------------------------------------------
  extern protected task run_vtrans_cell(creq_dtype_e dtype, creq_itype_e itype);

  `uvm_component_utils(shm_vtrans_full_mask_test)
endclass : shm_vtrans_full_mask_test

function shm_vtrans_full_mask_test::new(string name = "shm_vtrans_full_mask_test",
                                        uvm_component parent = null);
  super.new(name, parent);
endfunction : new

task shm_vtrans_full_mask_test::main_phase(uvm_phase phase);
  creq_dtype_e dtypes[2] = '{DTYP_8, DTYP_16};
  creq_itype_e itypes[2] = '{LDST_S, LDST_V};

  phase.raise_objection(this);
  if (shm_env.shmins_mst_agt.coverage == null || shm_env.address_coverage == null) begin
    `uvm_fatal("SHM_VTRANS_COVERAGE_MISSING", "VTRANS test requires request and address coverage")
  end
  foreach (dtypes[dtype_idx]) begin
    foreach (itypes[itype_idx]) begin
      run_vtrans_cell(dtypes[dtype_idx], itypes[itype_idx]);
    end
  end

  `uvm_info("SHM_VTRANS_FULL_MASK_TEST", "four-cell VTRANS full-mask matrix completed", UVM_LOW)
  phase.drop_objection(this);
endtask : main_phase

task shm_vtrans_full_mask_test::run_vtrans_cell(creq_dtype_e dtype, creq_itype_e itype);
  shmins_vtrans_sequence_item item;
  longint unsigned request_count_before;
  longint unsigned address_byte_count_before;
  longint unsigned cross_count_before;
  int unsigned expected_length;
  int unsigned expected_byte_count;
  string item_name;

  item_name = $sformatf("vtrans_dtype%0d_itype%0d", dtype, itype);
  item = shmins_vtrans_sequence_item::type_id::create(item_name);
  if (!item.randomize() with {
        creq_dtype == local::dtype;
        creq_atype_w == ATYP_32;
        creq_atype_s == ATYP_U;
        creq_atype_g == GAUTO_1B;
        creq_itype == local::itype;
        creq_wpid == 0;
        creq_ack_en == 1'b1;
        delay_cycle == 0;
      }) begin
    `uvm_fatal("SHM_VTRANS_DIRECTED_RANDOMIZE", $sformatf("failed to randomize %s", item_name))
  end

  expected_length = dtype == DTYP_8 ? 16 : 32;
  foreach (item.elem_num[thread_idx]) begin
    if (item.creq_tmsk !== '1 || item.elem_num[thread_idx] != 16 ||
        item.creq_len[thread_idx] != expected_length || item.creq_vmsk[thread_idx] !== '1) begin
      `uvm_fatal("SHM_VTRANS_DIRECTED_CONTRACT",
                 $sformatf("%s thread %0d violates the VTRANS full-mask contract",
                           item_name, thread_idx))
    end
    item.creq_vdat[thread_idx] = '0;
    for (int unsigned elem_idx = 0; elem_idx < 16; elem_idx++) begin
      for (int unsigned byte_lane = 0; byte_lane < item.data_byte_w(); byte_lane++) begin
        item.creq_vdat[thread_idx][elem_idx * item.data_byte_w() + byte_lane] =
            byte'((thread_idx << 4) ^ (elem_idx << 1) ^ byte_lane);
      end
    end
  end
  item.item_to_rtl();

  request_count_before = shm_env.shmins_mst_agt.coverage.sampled_request_count;
  address_byte_count_before = shm_env.address_coverage.sampled_active_byte_count;
  cross_count_before = shm_env.shmins_mst_agt.coverage.vtrans_cross_count(dtype, itype);
  expected_byte_count = THD_N * 16 * item.data_byte_w();

  send_directed_item(item);
  shm_env.wait_for_idle();

  if (shm_env.shmins_mst_agt.coverage.sampled_request_count != request_count_before + 1 ||
      shm_env.shmins_mst_agt.coverage.vtrans_cross_count(dtype, itype) != cross_count_before + 1) begin
    `uvm_fatal("SHM_VTRANS_REQUEST_COVERAGE",
               $sformatf("%s did not increment its request coverage cell exactly once", item_name))
  end
  if (shm_env.address_coverage.sampled_active_byte_count !=
      address_byte_count_before + expected_byte_count) begin
    `uvm_fatal("SHM_VTRANS_REFERENCE_BYTE_COUNT",
               $sformatf("%s expected %0d reference bytes", item_name, expected_byte_count))
  end
  `uvm_info("SHM_VTRANS_MATRIX_CELL", $sformatf("%s: PASS", item_name), UVM_LOW)
endtask : run_vtrans_cell

`endif // INC_SHM_VTRANS_FULL_MASK_TEST_SVH
