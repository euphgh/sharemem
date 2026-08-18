`ifndef INC_SHM_PAYLOAD_DONTCARE_X_TEST_SVH
`define INC_SHM_PAYLOAD_DONTCARE_X_TEST_SVH

//------------------------------------------------------------------------------
// @brief Verifies legal inactive and masked SHMINS don’t-care X payload.
//
// The test sends 18 inactive-thread cells and 12 active masked-element cells
// through the real DUT. Production monitor, reference, coverage, scoreboard,
// and lifecycle components determine pass or fail.
//------------------------------------------------------------------------------
class shm_payload_dontcare_x_test extends shm_directed_base_test;
  //----------------------------------------------------------------------------
  // @brief Constructs the don’t-care X directed test.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this test.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_payload_dontcare_x_test", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Runs the complete 18 plus 12 transaction matrix.
  //
  // @param phase UVM main phase controlling the test objection.
  //----------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  //----------------------------------------------------------------------------
  // @brief Sends one inactive-thread X matrix cell and checks observed counts.
  //
  // @param direction V2M or M2V request direction.
  // @param space LOC, WRP, or BLK address space.
  // @param target_tmsk Single-zero, single-fifteen, or sparse active mask.
  // @param mask_name Stable label used in diagnostics.
  //----------------------------------------------------------------------------
  extern protected task run_inactive_x_cell(creq_rw_e direction,
                                             creq_space_e space,
                                             logic [THD_N-1:0] target_tmsk,
                                             string mask_name);

  //----------------------------------------------------------------------------
  // @brief Sends one masked-element X matrix cell and checks observed counts.
  //
  // @param direction V2M or M2V request direction.
  // @param topology 0 for contiguous, 1 for strided, or 2 for indexed.
  // @param atype_width ATYP_16 or ATYP_32 packed offset width.
  //----------------------------------------------------------------------------
  extern protected task run_masked_x_cell(creq_rw_e direction,
                                           int unsigned topology,
                                           creq_atype_w_e atype_width);

  //----------------------------------------------------------------------------
  // @brief Creates one legal sparse-element topology item for threads 0 and 15.
  //
  // @param direction V2M or M2V request direction.
  // @param topology 0 for contiguous, 1 for strided, or 2 for indexed.
  // @param atype_width ATYP_16 or ATYP_32 packed offset width.
  // @param item_name UVM object instance name.
  // @return Generated item with element 0/7 active in both boundary threads.
  //----------------------------------------------------------------------------
  extern protected function shmins_sequence_item build_masked_x_item(creq_rw_e direction,
                                                                      int unsigned topology,
                                                                      creq_atype_w_e atype_width,
                                                                      string item_name);

  `uvm_component_utils(shm_payload_dontcare_x_test)
endclass : shm_payload_dontcare_x_test

function shm_payload_dontcare_x_test::new(string name = "shm_payload_dontcare_x_test",
                                           uvm_component parent = null);
  super.new(name, parent);
endfunction : new

task shm_payload_dontcare_x_test::main_phase(uvm_phase phase);
  creq_rw_e directions[2] = '{SHM_V2M, SHM_M2V};
  creq_space_e spaces[3] = '{SPACE_LOC, SPACE_WRP, SPACE_BLK};
  logic [THD_N-1:0] masks[3] = '{16'h0001, 16'h8000, 16'h8421};
  string mask_names[3] = '{"m0", "m15", "ms"};
  creq_atype_w_e atype_widths[2] = '{ATYP_16, ATYP_32};

  phase.raise_objection(this);
  if (shm_env.shmins_mst_agt.coverage == null || shm_env.address_coverage == null) begin
    `uvm_fatal("SHM_DONTCARE_X_COVERAGE", "don’t-care X test requires request and address coverage")
  end

  foreach (directions[direction_idx]) begin
    foreach (spaces[space_idx]) begin
      foreach (masks[mask_idx]) begin
        run_inactive_x_cell(directions[direction_idx], spaces[space_idx], masks[mask_idx], mask_names[mask_idx]);
      end
    end
  end
  foreach (directions[direction_idx]) begin
    for (int unsigned topology = 0; topology < 3; topology++) begin
      foreach (atype_widths[atype_idx]) begin
        run_masked_x_cell(directions[direction_idx], topology, atype_widths[atype_idx]);
      end
    end
  end

  `uvm_info("SHM_PAYLOAD_DONTCARE_X_TEST", "30-cell legal don’t-care X matrix completed", UVM_LOW)
  phase.drop_objection(this);
endtask : main_phase

task shm_payload_dontcare_x_test::run_inactive_x_cell(creq_rw_e direction,
                                                       creq_space_e space,
                                                       logic [THD_N-1:0] target_tmsk,
                                                       string mask_name);
  shmins_contiguous_sequence_item item;
  longint unsigned request_count_before;
  longint unsigned interpreted_xz_before[4];
  longint unsigned inactive_x_before;
  longint unsigned address_byte_count_before;
  int unsigned monitor_count_before;
  string item_name;

  item_name = $sformatf("inactive_%s_%s_%s", direction == SHM_V2M ? "v2m" : "m2v",
                        creq_space_e_to_str(space).tolower(), mask_name);
  item = build_masked_byte_item(item_name, direction, space, target_tmsk);
  if (!shmins_dontcare_x_util::poison_inactive_threads(item, 1'bx)) begin
    `uvm_fatal("SHM_DONTCARE_X_INACTIVE_BUILD", $sformatf("%s poisoning failed", item_name))
  end

  request_count_before = shm_env.shmins_mst_agt.coverage.sampled_request_count;
  foreach (interpreted_xz_before[xz_class]) begin
    interpreted_xz_before[xz_class] =
        shm_env.shmins_mst_agt.coverage.sampled_active_payload_xz_count[xz_class];
  end
  inactive_x_before = shm_env.shmins_mst_agt.coverage.sampled_inactive_payload_xz_count[SHMINS_PAYLOAD_X];
  address_byte_count_before = shm_env.address_coverage.sampled_active_byte_count;
  monitor_count_before = shm_env.shmins_mst_agt.monitor.shmins_cnt;

  send_directed_item(item);
  shm_env.wait_for_idle();

  if (shm_env.shmins_mst_agt.coverage.sampled_request_count != request_count_before + 1) begin
    `uvm_fatal("SHM_DONTCARE_X_REQUEST_COVERAGE",
               $sformatf({"%s request coverage expected exactly one sample: request=%0d->%0d ",
                          "monitor=%0d->%0d id=%0d rw=%0d itype=%0d atype_w=%0d"},
                         item_name, request_count_before,
                         shm_env.shmins_mst_agt.coverage.sampled_request_count,
                         monitor_count_before, shm_env.shmins_mst_agt.monitor.shmins_cnt,
                         item.creq_id, item.creq_rw, item.creq_itype, item.creq_atype_w))
  end
  if (shm_env.shmins_mst_agt.coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_KNOWN] !=
      interpreted_xz_before[SHMINS_PAYLOAD_KNOWN] + 1) begin
    `uvm_fatal("SHM_DONTCARE_X_INTERPRETED_COVERAGE",
               $sformatf({"%s interpreted payload was not classified known: ",
                          "known=%0d->%0d x=%0d->%0d z=%0d->%0d xz=%0d->%0d ",
                          "request=%0d->%0d monitor=%0d->%0d id=%0d rw=%0d itype=%0d atype_w=%0d"},
                         item_name,
                         interpreted_xz_before[SHMINS_PAYLOAD_KNOWN],
                         shm_env.shmins_mst_agt.coverage.sampled_active_payload_xz_count[
                             SHMINS_PAYLOAD_KNOWN],
                         interpreted_xz_before[SHMINS_PAYLOAD_X],
                         shm_env.shmins_mst_agt.coverage.sampled_active_payload_xz_count[
                             SHMINS_PAYLOAD_X],
                         interpreted_xz_before[SHMINS_PAYLOAD_Z],
                         shm_env.shmins_mst_agt.coverage.sampled_active_payload_xz_count[
                             SHMINS_PAYLOAD_Z],
                         interpreted_xz_before[SHMINS_PAYLOAD_XZ],
                         shm_env.shmins_mst_agt.coverage.sampled_active_payload_xz_count[
                             SHMINS_PAYLOAD_XZ],
                         request_count_before,
                         shm_env.shmins_mst_agt.coverage.sampled_request_count,
                         monitor_count_before, shm_env.shmins_mst_agt.monitor.shmins_cnt,
                         item.creq_id, item.creq_rw, item.creq_itype, item.creq_atype_w))
  end
  if (shm_env.shmins_mst_agt.coverage.sampled_inactive_payload_xz_count[SHMINS_PAYLOAD_X] !=
      inactive_x_before + 1) begin
    `uvm_fatal("SHM_DONTCARE_X_INACTIVE_COVERAGE",
               $sformatf("%s inactive-X coverage expected %0d, observed %0d",
                         item_name, inactive_x_before + 1,
                         shm_env.shmins_mst_agt.coverage.sampled_inactive_payload_xz_count[
                             SHMINS_PAYLOAD_X]))
  end
  if (shm_env.address_coverage.sampled_active_byte_count !=
      address_byte_count_before + $countones(target_tmsk)) begin
    `uvm_fatal("SHM_DONTCARE_X_INACTIVE_BYTES",
               $sformatf("%s produced an unexpected active reference byte count", item_name))
  end
  `uvm_info("SHM_DONTCARE_X_CELL", $sformatf("%s: PASS", item_name), UVM_LOW)
endtask : run_inactive_x_cell

function shmins_sequence_item shm_payload_dontcare_x_test::build_masked_x_item(
    creq_rw_e direction,
    int unsigned topology,
    creq_atype_w_e atype_width,
    string item_name);
  shmins_sequence_item item;

  case (topology)
    0: item = shmins_contiguous_sequence_item::type_id::create(item_name);
    1: item = shmins_strided_sequence_item::type_id::create(item_name);
    2: item = shmins_indexed_sequence_item::type_id::create(item_name);
    default: begin
      `uvm_fatal("SHM_DONTCARE_X_TOPOLOGY", $sformatf("unsupported topology %0d", topology))
      return null;
    end
  endcase

  item.m2v_unique_enable = 1'b1;
  if (!item.randomize() with {
        creq_rw == local::direction;
        creq_dtype == DTYP_8;
        creq_atype_w == local::atype_width;
        creq_atype_s == ATYP_U;
        creq_atype_g == GAUTO_1B;
        creq_space == SPACE_LOC;
        creq_wpid == 0;
        creq_ack_en == 1'b1;
        creq_tmsk == 16'h8001;
        elem_num[0] == 8;
        elem_num[THD_N-1] == 8;
        creq_vmsk[0][7:0] == 8'h81;
        creq_vmsk[THD_N-1][7:0] == 8'h81;
        delay_cycle == 0;
      }) begin
    `uvm_fatal("SHM_DONTCARE_X_RANDOMIZE", $sformatf("failed to randomize %s", item_name))
  end

  if (direction == SHM_V2M) begin
    if (!shmins_dontcare_x_util::poison_masked_element_data(item, 1'bx)) begin
      `uvm_fatal("SHM_DONTCARE_X_MASKED_DATA", $sformatf("%s masked data poisoning failed", item_name))
    end
  end else if (!shmins_dontcare_x_util::poison_m2v_vdata(item, 1'bx)) begin
    `uvm_fatal("SHM_DONTCARE_X_M2V_DATA", $sformatf("%s M2V data poisoning failed", item_name))
  end
  if (topology == 2) begin
    if (!shmins_dontcare_x_util::poison_indexed_masked_offsets(item, 1'bx)) begin
      `uvm_fatal("SHM_DONTCARE_X_INDEXED_OFFSET", $sformatf("%s indexed offset poisoning failed", item_name))
    end
  end else if (!shmins_dontcare_x_util::poison_unused_offset_slices(item, 1'bx)) begin
    `uvm_fatal("SHM_DONTCARE_X_UNUSED_OFFSET", $sformatf("%s unused offset poisoning failed", item_name))
  end
  if (!shmins_dontcare_x_util::poison_out_of_length_payload(item, 1'bx)) begin
    `uvm_fatal("SHM_DONTCARE_X_OUT_OF_LENGTH", $sformatf("%s tail poisoning failed", item_name))
  end
  return item;
endfunction : build_masked_x_item

task shm_payload_dontcare_x_test::run_masked_x_cell(creq_rw_e direction,
                                                     int unsigned topology,
                                                     creq_atype_w_e atype_width);
  shmins_sequence_item item;
  longint unsigned request_count_before;
  longint unsigned interpreted_xz_before[4];
  longint unsigned target_x_before;
  longint unsigned indexed_x_before;
  longint unsigned out_of_length_x_before;
  longint unsigned address_byte_count_before;
  int unsigned monitor_count_before;
  string topology_name;
  string item_name;

  case (topology)
    0: topology_name = "contiguous";
    1: topology_name = "strided";
    2: topology_name = "indexed";
    default: topology_name = "invalid";
  endcase
  item_name = $sformatf("masked_%s_%s_atype%0d", direction == SHM_V2M ? "v2m" : "m2v",
                        topology_name, atype_width);
  item = build_masked_x_item(direction, topology, atype_width, item_name);

  request_count_before = shm_env.shmins_mst_agt.coverage.sampled_request_count;
  foreach (interpreted_xz_before[xz_class]) begin
    interpreted_xz_before[xz_class] =
        shm_env.shmins_mst_agt.coverage.sampled_active_payload_xz_count[xz_class];
  end
  target_x_before = direction == SHM_V2M ?
      shm_env.shmins_mst_agt.coverage.sampled_masked_data_xz_count[SHMINS_PAYLOAD_X] :
      shm_env.shmins_mst_agt.coverage.sampled_m2v_unused_vdata_xz_count[SHMINS_PAYLOAD_X];
  indexed_x_before =
      shm_env.shmins_mst_agt.coverage.sampled_masked_indexed_offset_xz_count[SHMINS_PAYLOAD_X];
  out_of_length_x_before =
      shm_env.shmins_mst_agt.coverage.sampled_out_of_length_xz_count[SHMINS_PAYLOAD_X];
  address_byte_count_before = shm_env.address_coverage.sampled_active_byte_count;
  monitor_count_before = shm_env.shmins_mst_agt.monitor.shmins_cnt;

  send_directed_item(item);
  shm_env.wait_for_idle();

  if (shm_env.shmins_mst_agt.coverage.sampled_request_count != request_count_before + 1) begin
    `uvm_fatal("SHM_DONTCARE_X_REQUEST_COVERAGE",
               $sformatf({"%s request coverage expected exactly one sample: request=%0d->%0d ",
                          "monitor=%0d->%0d id=%0d rw=%0d itype=%0d atype_w=%0d"},
                         item_name, request_count_before,
                         shm_env.shmins_mst_agt.coverage.sampled_request_count,
                         monitor_count_before, shm_env.shmins_mst_agt.monitor.shmins_cnt,
                         item.creq_id, item.creq_rw, item.creq_itype, item.creq_atype_w))
  end
  if (shm_env.shmins_mst_agt.coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_KNOWN] !=
      interpreted_xz_before[SHMINS_PAYLOAD_KNOWN] + 1) begin
    `uvm_fatal("SHM_DONTCARE_X_INTERPRETED_COVERAGE",
               $sformatf({"%s interpreted payload was not classified known: ",
                          "known=%0d->%0d x=%0d->%0d z=%0d->%0d xz=%0d->%0d ",
                          "request=%0d->%0d monitor=%0d->%0d id=%0d rw=%0d itype=%0d atype_w=%0d"},
                         item_name,
                         interpreted_xz_before[SHMINS_PAYLOAD_KNOWN],
                         shm_env.shmins_mst_agt.coverage.sampled_active_payload_xz_count[
                             SHMINS_PAYLOAD_KNOWN],
                         interpreted_xz_before[SHMINS_PAYLOAD_X],
                         shm_env.shmins_mst_agt.coverage.sampled_active_payload_xz_count[
                             SHMINS_PAYLOAD_X],
                         interpreted_xz_before[SHMINS_PAYLOAD_Z],
                         shm_env.shmins_mst_agt.coverage.sampled_active_payload_xz_count[
                             SHMINS_PAYLOAD_Z],
                         interpreted_xz_before[SHMINS_PAYLOAD_XZ],
                         shm_env.shmins_mst_agt.coverage.sampled_active_payload_xz_count[
                             SHMINS_PAYLOAD_XZ],
                         request_count_before,
                         shm_env.shmins_mst_agt.coverage.sampled_request_count,
                         monitor_count_before, shm_env.shmins_mst_agt.monitor.shmins_cnt,
                         item.creq_id, item.creq_rw, item.creq_itype, item.creq_atype_w))
  end
  if ((direction == SHM_V2M ?
       shm_env.shmins_mst_agt.coverage.sampled_masked_data_xz_count[SHMINS_PAYLOAD_X] :
       shm_env.shmins_mst_agt.coverage.sampled_m2v_unused_vdata_xz_count[SHMINS_PAYLOAD_X]) !=
      target_x_before + 1) begin
    `uvm_fatal("SHM_DONTCARE_X_DATA_COVERAGE", $sformatf("%s missed its data-X coverage", item_name))
  end
  if (topology == 2 &&
      shm_env.shmins_mst_agt.coverage.sampled_masked_indexed_offset_xz_count[SHMINS_PAYLOAD_X] !=
          indexed_x_before + 1) begin
    `uvm_fatal("SHM_DONTCARE_X_OFFSET_COVERAGE", $sformatf("%s missed indexed offset-X coverage", item_name))
  end
  if (shm_env.shmins_mst_agt.coverage.sampled_out_of_length_xz_count[SHMINS_PAYLOAD_X] !=
      out_of_length_x_before + 1) begin
    `uvm_fatal("SHM_DONTCARE_X_TAIL_COVERAGE", $sformatf("%s missed out-of-length X coverage", item_name))
  end
  if (shm_env.address_coverage.sampled_active_byte_count != address_byte_count_before + 4) begin
    `uvm_fatal("SHM_DONTCARE_X_MASKED_BYTES",
               $sformatf("%s produced an unexpected active reference byte count", item_name))
  end
  `uvm_info("SHM_DONTCARE_X_CELL", $sformatf("%s: PASS", item_name), UVM_LOW)
endtask : run_masked_x_cell

`endif // INC_SHM_PAYLOAD_DONTCARE_X_TEST_SVH
