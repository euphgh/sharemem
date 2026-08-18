`ifndef INC_SHMINS_REQUEST_COVERAGE_SVH
`define INC_SHMINS_REQUEST_COVERAGE_SVH

typedef enum int unsigned {
  SHMINS_MASK_UNKNOWN,
  SHMINS_MASK_ZERO,
  SHMINS_MASK_SINGLE,
  SHMINS_MASK_SPARSE,
  SHMINS_MASK_FULL
} shmins_mask_class_e;

typedef enum int unsigned {
  SHMINS_PAYLOAD_KNOWN,
  SHMINS_PAYLOAD_X,
  SHMINS_PAYLOAD_Z,
  SHMINS_PAYLOAD_XZ
} shmins_payload_xz_e;

//------------------------------------------------------------------------------
// @brief Samples reusable SHM request mask and VTRANS functional coverage.
//
// The subscriber observes monitor transactions without checking legality or
// changing request flow. Tests may call write() directly for invalid requests
// that the production monitor intentionally drops.
//------------------------------------------------------------------------------
class shmins_request_coverage extends uvm_subscriber #(shmins_sequence_item);
  localparam int unsigned MASK_CLASS_N = 5;

  // Total number of requests sampled by the collector.
  longint unsigned sampled_request_count;

  // Sample counts indexed by shmins_mask_class_e.
  longint unsigned sampled_mask_class_count[MASK_CLASS_N];

  // Interpreted active and inactive payload samples indexed by shmins_payload_xz_e.
  longint unsigned sampled_active_payload_xz_count[4];
  longint unsigned sampled_inactive_payload_xz_count[4];

  // Don’t-care payload samples indexed by shmins_payload_xz_e.
  longint unsigned sampled_masked_data_xz_count[4];
  longint unsigned sampled_masked_indexed_offset_xz_count[4];
  longint unsigned sampled_out_of_length_xz_count[4];
  longint unsigned sampled_m2v_unused_vdata_xz_count[4];

  // Active-thread sample counts indexed by thread and direction encoding.
  longint unsigned sampled_active_thread_count[THD_N][2];

  // Normal request cross counts indexed by direction, space, and mask class.
  longint unsigned sampled_normal_cross_count[2][3][MASK_CLASS_N];

  // VTRANS cross counts indexed by dtype and itype encoding.
  longint unsigned sampled_vtrans_cross_count[3][4];

  covergroup request_cg with function sample(int unsigned request_kind,
                                              int unsigned mask_class,
                                              int unsigned population,
                                              int unsigned inactive_xz,
                                              int unsigned active_xz);
    option.per_instance = 1;
    cp_request_kind: coverpoint request_kind {
      bins normal = {0};
      bins vtrans = {1};
    }
    cp_mask_class: coverpoint mask_class {
      bins unknown = {SHMINS_MASK_UNKNOWN};
      bins zero = {SHMINS_MASK_ZERO};
      bins single = {SHMINS_MASK_SINGLE};
      bins sparse = {SHMINS_MASK_SPARSE};
      bins full = {SHMINS_MASK_FULL};
    }
    cp_population: coverpoint population {
      bins zero = {0};
      bins one = {1};
      bins sparse = {[2:THD_N-1]};
      bins full = {THD_N};
    }
    cp_inactive_xz: coverpoint inactive_xz {
      bins known = {SHMINS_PAYLOAD_KNOWN};
      bins x = {SHMINS_PAYLOAD_X};
      bins z = {SHMINS_PAYLOAD_Z};
      bins xz = {SHMINS_PAYLOAD_XZ};
    }
    cp_active_xz: coverpoint active_xz {
      bins known = {SHMINS_PAYLOAD_KNOWN};
      bins has_unknown = {[SHMINS_PAYLOAD_X:SHMINS_PAYLOAD_XZ]};
    }
    cx_mask_inactive_xz: cross cp_mask_class, cp_inactive_xz;
  endgroup

  covergroup normal_mask_cg with function sample(int unsigned direction,
                                                  int unsigned space,
                                                  int unsigned mask_class);
    option.per_instance = 1;
    cp_direction: coverpoint direction {
      bins v2m = {SHM_V2M};
      bins m2v = {SHM_M2V};
    }
    cp_space: coverpoint space {
      bins loc = {SPACE_LOC};
      bins wrp = {SPACE_WRP};
      bins blk = {SPACE_BLK};
    }
    cp_mask_class: coverpoint mask_class {
      bins single = {SHMINS_MASK_SINGLE};
      bins sparse = {SHMINS_MASK_SPARSE};
      bins full = {SHMINS_MASK_FULL};
    }
    cx_direction_space_mask: cross cp_direction, cp_space, cp_mask_class;
  endgroup

  covergroup active_thread_cg with function sample(int unsigned thread_idx,
                                                    int unsigned direction);
    option.per_instance = 1;
    cp_thread: coverpoint thread_idx {
      bins first = {0};
      bins middle[] = {[1:THD_N-2]};
      bins last = {THD_N-1};
    }
    cp_direction: coverpoint direction {
      bins v2m = {SHM_V2M};
      bins m2v = {SHM_M2V};
    }
    cx_thread_direction: cross cp_thread, cp_direction;
  endgroup

  covergroup vtrans_cg with function sample(int unsigned dtype,
                                             int unsigned itype,
                                             int unsigned mask_class);
    option.per_instance = 1;
    cp_dtype: coverpoint dtype {
      bins dtype8 = {DTYP_8};
      bins dtype16 = {DTYP_16};
    }
    cp_itype: coverpoint itype {
      bins ldst_s = {LDST_S};
      bins ldst_v = {LDST_V};
    }
    cp_mask_class: coverpoint mask_class {
      bins full = {SHMINS_MASK_FULL};
      illegal_bins not_full = default;
    }
    cx_dtype_itype_full_mask: cross cp_dtype, cp_itype, cp_mask_class;
  endgroup

  covergroup dontcare_xz_cg with function sample(int unsigned interpreted_xz,
                                                  int unsigned inactive_xz,
                                                  int unsigned masked_data_xz,
                                                  int unsigned masked_indexed_offset_xz,
                                                  int unsigned out_of_length_xz,
                                                  int unsigned m2v_unused_vdata_xz);
    option.per_instance = 1;
    cp_interpreted_xz: coverpoint interpreted_xz {
      bins known = {SHMINS_PAYLOAD_KNOWN};
      bins unknown = {[SHMINS_PAYLOAD_X:SHMINS_PAYLOAD_XZ]};
    }
    cp_inactive_xz: coverpoint inactive_xz {
      bins known = {SHMINS_PAYLOAD_KNOWN};
      bins x = {SHMINS_PAYLOAD_X};
      bins z = {SHMINS_PAYLOAD_Z};
      bins xz = {SHMINS_PAYLOAD_XZ};
    }
    cp_masked_data_xz: coverpoint masked_data_xz {
      bins known = {SHMINS_PAYLOAD_KNOWN};
      bins x = {SHMINS_PAYLOAD_X};
      bins z = {SHMINS_PAYLOAD_Z};
      bins xz = {SHMINS_PAYLOAD_XZ};
    }
    cp_masked_indexed_offset_xz: coverpoint masked_indexed_offset_xz {
      bins known = {SHMINS_PAYLOAD_KNOWN};
      bins x = {SHMINS_PAYLOAD_X};
      bins z = {SHMINS_PAYLOAD_Z};
      bins xz = {SHMINS_PAYLOAD_XZ};
    }
    cp_out_of_length_xz: coverpoint out_of_length_xz {
      bins known = {SHMINS_PAYLOAD_KNOWN};
      bins x = {SHMINS_PAYLOAD_X};
      bins z = {SHMINS_PAYLOAD_Z};
      bins xz = {SHMINS_PAYLOAD_XZ};
    }
    cp_m2v_unused_vdata_xz: coverpoint m2v_unused_vdata_xz {
      bins known = {SHMINS_PAYLOAD_KNOWN};
      bins x = {SHMINS_PAYLOAD_X};
      bins z = {SHMINS_PAYLOAD_Z};
      bins xz = {SHMINS_PAYLOAD_XZ};
    }
  endgroup

  //----------------------------------------------------------------------------
  // @brief Constructs and clears the SHM request coverage collector.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this collector.
  //----------------------------------------------------------------------------
  extern function new(string name = "shmins_request_coverage", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Samples one monitor or component-test request.
  //
  // @param t Read-only request to classify and sample.
  //----------------------------------------------------------------------------
  extern virtual function void write(shmins_sequence_item t);

  //----------------------------------------------------------------------------
  // @brief Returns the mask classification used by coverage and tests.
  //
  // @param tmsk Four-state thread mask to classify.
  // @return Unknown, zero, single, sparse, or full mask class.
  //----------------------------------------------------------------------------
  extern function shmins_mask_class_e classify_mask(logic [THD_N-1:0] tmsk);

  //----------------------------------------------------------------------------
  // @brief Returns the sampled count for one normal direction/space/mask cell.
  //
  // @param direction V2M or M2V request direction.
  // @param space LOC, WRP, or BLK address space.
  // @param mask_class Legal single, sparse, or full mask class.
  // @return Number of matching normal requests observed.
  //----------------------------------------------------------------------------
  extern function longint unsigned normal_cross_count(creq_rw_e direction,
                                                       creq_space_e space,
                                                       shmins_mask_class_e mask_class);

  //----------------------------------------------------------------------------
  // @brief Returns the sampled count for one VTRANS dtype/itype cell.
  //
  // @param dtype Supported VTRANS data type.
  // @param itype Supported contiguous instruction type.
  // @return Number of matching full-mask VTRANS requests observed.
  //----------------------------------------------------------------------------
  extern function longint unsigned vtrans_cross_count(creq_dtype_e dtype, creq_itype_e itype);

  //----------------------------------------------------------------------------
  // @brief Classifies X and Z values across active or inactive thread payload.
  //
  // @param transaction Request whose per-thread payload is inspected.
  // @param active Selects active threads when 1 and inactive threads when 0.
  // @return Known, X, Z, or combined X/Z category.
  //----------------------------------------------------------------------------
  extern protected function shmins_payload_xz_e classify_payload_xz(shmins_sequence_item transaction,
                                                                     bit active);

  //----------------------------------------------------------------------------
  // @brief Classifies only payload bits interpreted by an active request.
  //
  // @param transaction Request whose selected payload is inspected.
  // @return Known, X, Z, or combined X/Z category.
  //----------------------------------------------------------------------------
  extern protected function shmins_payload_xz_e classify_interpreted_payload_xz(
      shmins_sequence_item transaction);

  //----------------------------------------------------------------------------
  // @brief Classifies data bytes belonging to masked length-bounded elements.
  //
  // @param transaction Request whose masked element data is inspected.
  // @return Known, X, Z, or combined X/Z category.
  //----------------------------------------------------------------------------
  extern protected function shmins_payload_xz_e classify_masked_data_xz(shmins_sequence_item transaction);

  //----------------------------------------------------------------------------
  // @brief Classifies offsets belonging to masked indexed elements.
  //
  // @param transaction Request whose masked LDSTE_V offsets are inspected.
  // @return Known, X, Z, or combined X/Z category.
  //----------------------------------------------------------------------------
  extern protected function shmins_payload_xz_e classify_masked_indexed_offset_xz(
      shmins_sequence_item transaction);

  //----------------------------------------------------------------------------
  // @brief Classifies active-thread payload outside the selected length.
  //
  // @param transaction Request whose out-of-length payload is inspected.
  // @return Known, X, Z, or combined X/Z category.
  //----------------------------------------------------------------------------
  extern protected function shmins_payload_xz_e classify_out_of_length_xz(shmins_sequence_item transaction);

  //----------------------------------------------------------------------------
  // @brief Classifies unused active-thread input data on an M2V request.
  //
  // @param transaction Request whose M2V input data is inspected.
  // @return Known, X, Z, or combined X/Z category.
  //----------------------------------------------------------------------------
  extern protected function shmins_payload_xz_e classify_m2v_unused_vdata_xz(
      shmins_sequence_item transaction);

  //----------------------------------------------------------------------------
  // @brief Observes one packed offset element and updates four-state flags.
  //
  // @param transaction Request containing the packed offset vector.
  // @param thread_idx Thread index containing the selected offset.
  // @param offset_idx Offset element index within the packed vector.
  // @param has_x Set when the selected slice contains X.
  // @param has_z Set when the selected slice contains Z.
  //----------------------------------------------------------------------------
  extern protected function void observe_offset_xz(shmins_sequence_item transaction,
                                                    int unsigned thread_idx,
                                                    int unsigned offset_idx,
                                                    ref bit has_x,
                                                    ref bit has_z);

  //----------------------------------------------------------------------------
  // @brief Converts accumulated X/Z flags to the public classification enum.
  //
  // @param has_x Indicates that at least one X bit was observed.
  // @param has_z Indicates that at least one Z bit was observed.
  // @return Known, X, Z, or combined X/Z category.
  //----------------------------------------------------------------------------
  extern protected function shmins_payload_xz_e flags_to_xz(bit has_x, bit has_z);

  //----------------------------------------------------------------------------
  // @brief Updates X/Z flags for one four-state bit.
  //
  // @param value Bit to classify.
  // @param has_x Set when value is X.
  // @param has_z Set when value is Z.
  //----------------------------------------------------------------------------
  extern protected function void observe_four_state(logic value, ref bit has_x, ref bit has_z);

  `uvm_component_utils(shmins_request_coverage)
endclass : shmins_request_coverage

function shmins_request_coverage::new(string name = "shmins_request_coverage",
                                      uvm_component parent = null);
  super.new(name, parent);
  sampled_request_count = 0;
  foreach (sampled_mask_class_count[index]) sampled_mask_class_count[index] = 0;
  foreach (sampled_active_payload_xz_count[index]) sampled_active_payload_xz_count[index] = 0;
  foreach (sampled_inactive_payload_xz_count[index]) sampled_inactive_payload_xz_count[index] = 0;
  foreach (sampled_masked_data_xz_count[index]) sampled_masked_data_xz_count[index] = 0;
  foreach (sampled_masked_indexed_offset_xz_count[index]) sampled_masked_indexed_offset_xz_count[index] = 0;
  foreach (sampled_out_of_length_xz_count[index]) sampled_out_of_length_xz_count[index] = 0;
  foreach (sampled_m2v_unused_vdata_xz_count[index]) sampled_m2v_unused_vdata_xz_count[index] = 0;
  foreach (sampled_active_thread_count[thread_idx, direction]) begin
    sampled_active_thread_count[thread_idx][direction] = 0;
  end
  foreach (sampled_normal_cross_count[direction, space, mask_class]) begin
    sampled_normal_cross_count[direction][space][mask_class] = 0;
  end
  foreach (sampled_vtrans_cross_count[dtype, itype]) begin
    sampled_vtrans_cross_count[dtype][itype] = 0;
  end
  request_cg = new();
  normal_mask_cg = new();
  active_thread_cg = new();
  vtrans_cg = new();
  dontcare_xz_cg = new();
endfunction : new

function void shmins_request_coverage::write(shmins_sequence_item t);
  shmins_mask_class_e mask_class;
  shmins_payload_xz_e active_xz;
  shmins_payload_xz_e inactive_xz;
  shmins_payload_xz_e masked_data_xz;
  shmins_payload_xz_e masked_indexed_offset_xz;
  shmins_payload_xz_e out_of_length_xz;
  shmins_payload_xz_e m2v_unused_vdata_xz;
  int unsigned population;
  int unsigned request_kind;

  if (t == null) begin
    `uvm_error("SHMINS_REQUEST_COVERAGE_NULL", "received a null SHM request")
    return;
  end

  mask_class = classify_mask(t.creq_tmsk);
  population = mask_class == SHMINS_MASK_UNKNOWN ? 0 : $countones(t.creq_tmsk);
  request_kind = t.creq_info == 4'hf ? 1 : 0;
  inactive_xz = classify_payload_xz(t, 1'b0);
  active_xz = classify_payload_xz(t, 1'b1);
  masked_data_xz = classify_masked_data_xz(t);
  masked_indexed_offset_xz = classify_masked_indexed_offset_xz(t);
  out_of_length_xz = classify_out_of_length_xz(t);
  m2v_unused_vdata_xz = classify_m2v_unused_vdata_xz(t);
  request_cg.sample(request_kind, mask_class, population, inactive_xz, active_xz);
  dontcare_xz_cg.sample(active_xz, inactive_xz, masked_data_xz, masked_indexed_offset_xz,
                        out_of_length_xz, m2v_unused_vdata_xz);

  sampled_request_count++;
  sampled_mask_class_count[mask_class]++;
  sampled_active_payload_xz_count[active_xz]++;
  sampled_inactive_payload_xz_count[inactive_xz]++;
  sampled_masked_data_xz_count[masked_data_xz]++;
  sampled_masked_indexed_offset_xz_count[masked_indexed_offset_xz]++;
  sampled_out_of_length_xz_count[out_of_length_xz]++;
  sampled_m2v_unused_vdata_xz_count[m2v_unused_vdata_xz]++;
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    if (t.creq_tmsk[thread_idx] === 1'b1 && int'(t.creq_rw) < 2) begin
      active_thread_cg.sample(thread_idx, t.creq_rw);
      sampled_active_thread_count[thread_idx][t.creq_rw]++;
    end
  end

  if (t.creq_info == 4'h0 && mask_class inside {
        SHMINS_MASK_SINGLE, SHMINS_MASK_SPARSE, SHMINS_MASK_FULL
      } && int'(t.creq_rw) < 2 && int'(t.creq_space) < 3) begin
    normal_mask_cg.sample(t.creq_rw, t.creq_space, mask_class);
    sampled_normal_cross_count[t.creq_rw][t.creq_space][mask_class]++;
  end
  if (t.creq_info == 4'hf && mask_class == SHMINS_MASK_FULL &&
      int'(t.creq_dtype) < 3 && int'(t.creq_itype) < 4) begin
    vtrans_cg.sample(t.creq_dtype, t.creq_itype, mask_class);
    sampled_vtrans_cross_count[t.creq_dtype][t.creq_itype]++;
  end
  if (t.creq_info == 4'hf ||
      (mask_class == SHMINS_MASK_FULL && t.creq_rw == SHM_V2M && t.creq_space == SPACE_LOC)) begin
    `uvm_info("SHMINS_VTRANS_COVERAGE_SAMPLE",
              $sformatf({"uid=%0d id=%0d typ=0x%05h info=0x%0h rw=%0d space=%0d dtype=%0d ",
                         "itype=%0d tmsk=0x%0h mask_class=%0d request_count=%0d cell_count=%0d"},
                        t.transaction_uid, t.creq_id, t.creq_typ, t.creq_info, t.creq_rw,
                        t.creq_space, t.creq_dtype, t.creq_itype, t.creq_tmsk, mask_class,
                        sampled_request_count,
                        int'(t.creq_dtype) < 3 && int'(t.creq_itype) < 4 ?
                            sampled_vtrans_cross_count[t.creq_dtype][t.creq_itype] : 0),
              UVM_LOW)
  end
endfunction : write

function shmins_mask_class_e shmins_request_coverage::classify_mask(logic [THD_N-1:0] tmsk);
  int unsigned population;

  if ($isunknown(tmsk)) begin
    return SHMINS_MASK_UNKNOWN;
  end
  population = $countones(tmsk);
  if (population == 0) begin
    return SHMINS_MASK_ZERO;
  end
  if (population == 1) begin
    return SHMINS_MASK_SINGLE;
  end
  if (population == THD_N) begin
    return SHMINS_MASK_FULL;
  end
  return SHMINS_MASK_SPARSE;
endfunction : classify_mask

function longint unsigned shmins_request_coverage::normal_cross_count(
    creq_rw_e direction,
    creq_space_e space,
    shmins_mask_class_e mask_class);
  if (int'(direction) >= 2 || int'(space) >= 3 || int'(mask_class) >= MASK_CLASS_N) begin
    return 0;
  end
  return sampled_normal_cross_count[direction][space][mask_class];
endfunction : normal_cross_count

function longint unsigned shmins_request_coverage::vtrans_cross_count(creq_dtype_e dtype,
                                                                       creq_itype_e itype);
  if (int'(dtype) >= 3 || int'(itype) >= 4) begin
    return 0;
  end
  return sampled_vtrans_cross_count[dtype][itype];
endfunction : vtrans_cross_count

function shmins_payload_xz_e shmins_request_coverage::classify_payload_xz(
    shmins_sequence_item transaction,
    bit active);
  bit has_x;
  bit has_z;

  if (active) begin
    return classify_interpreted_payload_xz(transaction);
  end
  has_x = 1'b0;
  has_z = 1'b0;
  if ($isunknown(transaction.creq_tmsk)) begin
    return SHMINS_PAYLOAD_KNOWN;
  end

  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    logic [VEC_W-1:0] packed_offsets;

    if (transaction.creq_tmsk[thread_idx] !== 1'b0) begin
      continue;
    end
    packed_offsets = transaction.creq_offs(thread_idx);
    foreach (transaction.creq_prio[thread_idx][bit_idx]) begin
      observe_four_state(transaction.creq_prio[thread_idx][bit_idx], has_x, has_z);
    end
    foreach (transaction.creq_len[thread_idx][bit_idx]) begin
      observe_four_state(transaction.creq_len[thread_idx][bit_idx], has_x, has_z);
    end
    foreach (transaction.creq_vmsk[thread_idx][bit_idx]) begin
      observe_four_state(transaction.creq_vmsk[thread_idx][bit_idx], has_x, has_z);
    end
    foreach (packed_offsets[bit_idx]) begin
      observe_four_state(packed_offsets[bit_idx], has_x, has_z);
    end
    foreach (transaction.creq_vdat[thread_idx][byte_idx, bit_idx]) begin
      observe_four_state(transaction.creq_vdat[thread_idx][byte_idx][bit_idx], has_x, has_z);
    end
  end

  return flags_to_xz(has_x, has_z);
endfunction : classify_payload_xz

function shmins_payload_xz_e shmins_request_coverage::classify_interpreted_payload_xz(
    shmins_sequence_item transaction);
  bit has_x;
  bit has_z;

  has_x = 1'b0;
  has_z = 1'b0;
  if ($isunknown(transaction.creq_tmsk)) begin
    return SHMINS_PAYLOAD_KNOWN;
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    int unsigned element_count;
    bit has_active_element;

    if (transaction.creq_tmsk[thread_idx] !== 1'b1) begin
      continue;
    end
    foreach (transaction.creq_prio[thread_idx][bit_idx]) begin
      observe_four_state(transaction.creq_prio[thread_idx][bit_idx], has_x, has_z);
    end
    foreach (transaction.creq_len[thread_idx][bit_idx]) begin
      observe_four_state(transaction.creq_len[thread_idx][bit_idx], has_x, has_z);
    end
    if ($isunknown(transaction.creq_len[thread_idx]) || transaction.data_byte_w() == 0) begin
      continue;
    end
    element_count = transaction.thread_elem_cnt(thread_idx);
    if (element_count > transaction.max_elem_cnt()) begin
      element_count = transaction.max_elem_cnt();
    end
    has_active_element = 1'b0;
    for (int unsigned elem_idx = 0; elem_idx < element_count; elem_idx++) begin
      observe_four_state(transaction.creq_vmsk[thread_idx][elem_idx], has_x, has_z);
      if (transaction.creq_vmsk[thread_idx][elem_idx] !== 1'b1) begin
        continue;
      end
      has_active_element = 1'b1;
      if (transaction.creq_itype == LDSTE_V) begin
        observe_offset_xz(transaction, thread_idx, elem_idx, has_x, has_z);
      end
      if (transaction.creq_rw == SHM_V2M) begin
        for (int unsigned byte_lane = 0; byte_lane < transaction.data_byte_w(); byte_lane++) begin
          int unsigned byte_idx = elem_idx * transaction.data_byte_w() + byte_lane;
          foreach (transaction.creq_vdat[thread_idx][byte_idx, bit_idx]) begin
            observe_four_state(transaction.creq_vdat[thread_idx][byte_idx][bit_idx], has_x, has_z);
          end
        end
      end
    end
    if (has_active_element && transaction.creq_itype inside {LDST_S, LDST_V, LDSTE_S}) begin
      observe_offset_xz(transaction, thread_idx, 0, has_x, has_z);
    end
  end
  return flags_to_xz(has_x, has_z);
endfunction : classify_interpreted_payload_xz

function shmins_payload_xz_e shmins_request_coverage::classify_masked_data_xz(
    shmins_sequence_item transaction);
  bit has_x;
  bit has_z;

  has_x = 1'b0;
  has_z = 1'b0;
  if ($isunknown(transaction.creq_tmsk)) begin
    return SHMINS_PAYLOAD_KNOWN;
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    int unsigned element_count;

    if (transaction.creq_tmsk[thread_idx] !== 1'b1 || $isunknown(transaction.creq_len[thread_idx])) begin
      continue;
    end
    element_count = transaction.thread_elem_cnt(thread_idx);
    if (element_count > transaction.max_elem_cnt()) begin
      element_count = transaction.max_elem_cnt();
    end
    for (int unsigned elem_idx = 0; elem_idx < element_count; elem_idx++) begin
      if (transaction.creq_vmsk[thread_idx][elem_idx] !== 1'b0) begin
        continue;
      end
      for (int unsigned byte_lane = 0; byte_lane < transaction.data_byte_w(); byte_lane++) begin
        int unsigned byte_idx = elem_idx * transaction.data_byte_w() + byte_lane;
        foreach (transaction.creq_vdat[thread_idx][byte_idx, bit_idx]) begin
          observe_four_state(transaction.creq_vdat[thread_idx][byte_idx][bit_idx], has_x, has_z);
        end
      end
    end
  end
  return flags_to_xz(has_x, has_z);
endfunction : classify_masked_data_xz

function shmins_payload_xz_e shmins_request_coverage::classify_masked_indexed_offset_xz(
    shmins_sequence_item transaction);
  bit has_x;
  bit has_z;

  has_x = 1'b0;
  has_z = 1'b0;
  if ($isunknown(transaction.creq_tmsk) || transaction.creq_itype != LDSTE_V) begin
    return SHMINS_PAYLOAD_KNOWN;
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    int unsigned element_count;

    if (transaction.creq_tmsk[thread_idx] !== 1'b1 || $isunknown(transaction.creq_len[thread_idx])) begin
      continue;
    end
    element_count = transaction.thread_elem_cnt(thread_idx);
    if (element_count > transaction.max_elem_cnt()) begin
      element_count = transaction.max_elem_cnt();
    end
    for (int unsigned elem_idx = 0; elem_idx < element_count; elem_idx++) begin
      if (transaction.creq_vmsk[thread_idx][elem_idx] === 1'b0) begin
        observe_offset_xz(transaction, thread_idx, elem_idx, has_x, has_z);
      end
    end
  end
  return flags_to_xz(has_x, has_z);
endfunction : classify_masked_indexed_offset_xz

function shmins_payload_xz_e shmins_request_coverage::classify_out_of_length_xz(
    shmins_sequence_item transaction);
  bit has_x;
  bit has_z;

  has_x = 1'b0;
  has_z = 1'b0;
  if ($isunknown(transaction.creq_tmsk)) begin
    return SHMINS_PAYLOAD_KNOWN;
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    int unsigned byte_count;
    int unsigned element_count;

    if (transaction.creq_tmsk[thread_idx] !== 1'b1 || $isunknown(transaction.creq_len[thread_idx])) begin
      continue;
    end
    byte_count = int'(transaction.creq_len[thread_idx]);
    element_count = transaction.thread_elem_cnt(thread_idx);
    if (element_count > transaction.max_elem_cnt()) begin
      element_count = transaction.max_elem_cnt();
    end
    for (int unsigned elem_idx = element_count; elem_idx < VEC_BYTE_N; elem_idx++) begin
      observe_four_state(transaction.creq_vmsk[thread_idx][elem_idx], has_x, has_z);
    end
    for (int unsigned byte_idx = byte_count; byte_idx < VEC_BYTE_N; byte_idx++) begin
      foreach (transaction.creq_vdat[thread_idx][byte_idx, bit_idx]) begin
        observe_four_state(transaction.creq_vdat[thread_idx][byte_idx][bit_idx], has_x, has_z);
      end
    end
    if (transaction.creq_itype == LDSTE_V) begin
      for (int unsigned offset_idx = element_count; offset_idx < transaction.offs_elem_max(); offset_idx++) begin
        observe_offset_xz(transaction, thread_idx, offset_idx, has_x, has_z);
      end
    end else begin
      for (int unsigned offset_idx = 1; offset_idx < transaction.offs_elem_max(); offset_idx++) begin
        observe_offset_xz(transaction, thread_idx, offset_idx, has_x, has_z);
      end
    end
  end
  return flags_to_xz(has_x, has_z);
endfunction : classify_out_of_length_xz

function shmins_payload_xz_e shmins_request_coverage::classify_m2v_unused_vdata_xz(
    shmins_sequence_item transaction);
  bit has_x;
  bit has_z;

  has_x = 1'b0;
  has_z = 1'b0;
  if ($isunknown(transaction.creq_tmsk) || transaction.creq_rw != SHM_M2V) begin
    return SHMINS_PAYLOAD_KNOWN;
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    if (transaction.creq_tmsk[thread_idx] !== 1'b1) begin
      continue;
    end
    foreach (transaction.creq_vdat[thread_idx][byte_idx, bit_idx]) begin
      observe_four_state(transaction.creq_vdat[thread_idx][byte_idx][bit_idx], has_x, has_z);
    end
  end
  return flags_to_xz(has_x, has_z);
endfunction : classify_m2v_unused_vdata_xz

function void shmins_request_coverage::observe_offset_xz(shmins_sequence_item transaction,
                                                          int unsigned thread_idx,
                                                          int unsigned offset_idx,
                                                          ref bit has_x,
                                                          ref bit has_z);
  logic [VEC_W-1:0] packed_offsets;

  if (thread_idx >= THD_N || offset_idx >= transaction.offs_elem_max()) begin
    return;
  end
  packed_offsets = transaction.creq_offs(thread_idx);
  case (transaction.offs_bit_w())
    16: begin
      for (int unsigned bit_idx = offset_idx * 16; bit_idx < offset_idx * 16 + 16; bit_idx++) begin
        observe_four_state(packed_offsets[bit_idx], has_x, has_z);
      end
    end
    32: begin
      for (int unsigned bit_idx = offset_idx * 32; bit_idx < offset_idx * 32 + 32; bit_idx++) begin
        observe_four_state(packed_offsets[bit_idx], has_x, has_z);
      end
    end
    default: ;
  endcase
endfunction : observe_offset_xz

function shmins_payload_xz_e shmins_request_coverage::flags_to_xz(bit has_x, bit has_z);
  if (has_x && has_z) return SHMINS_PAYLOAD_XZ;
  if (has_x) return SHMINS_PAYLOAD_X;
  if (has_z) return SHMINS_PAYLOAD_Z;
  return SHMINS_PAYLOAD_KNOWN;
endfunction : flags_to_xz

function void shmins_request_coverage::observe_four_state(logic value, ref bit has_x, ref bit has_z);
  if (value === 1'bx) begin
    has_x = 1'b1;
  end
  else if (value === 1'bz) begin
    has_z = 1'b1;
  end
endfunction : observe_four_state

`endif // INC_SHMINS_REQUEST_COVERAGE_SVH
