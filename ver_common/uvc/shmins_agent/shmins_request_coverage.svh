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

  // Active and inactive payload samples indexed by shmins_payload_xz_e.
  longint unsigned sampled_active_payload_xz_count[4];
  longint unsigned sampled_inactive_payload_xz_count[4];

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
endfunction : new

function void shmins_request_coverage::write(shmins_sequence_item t);
  shmins_mask_class_e mask_class;
  shmins_payload_xz_e active_xz;
  shmins_payload_xz_e inactive_xz;
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
  request_cg.sample(request_kind, mask_class, population, inactive_xz, active_xz);

  sampled_request_count++;
  sampled_mask_class_count[mask_class]++;
  sampled_active_payload_xz_count[active_xz]++;
  sampled_inactive_payload_xz_count[inactive_xz]++;
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

  has_x = 1'b0;
  has_z = 1'b0;
  if ($isunknown(transaction.creq_tmsk)) begin
    return SHMINS_PAYLOAD_KNOWN;
  end

  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    logic [VEC_W-1:0] packed_offsets;

    if ((transaction.creq_tmsk[thread_idx] === 1'b1) != active) begin
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

  if (has_x && has_z) return SHMINS_PAYLOAD_XZ;
  if (has_x) return SHMINS_PAYLOAD_X;
  if (has_z) return SHMINS_PAYLOAD_Z;
  return SHMINS_PAYLOAD_KNOWN;
endfunction : classify_payload_xz

function void shmins_request_coverage::observe_four_state(logic value, ref bit has_x, ref bit has_z);
  if (value === 1'bx) begin
    has_x = 1'b1;
  end
  else if (value === 1'bz) begin
    has_z = 1'b1;
  end
endfunction : observe_four_state

`endif // INC_SHMINS_REQUEST_COVERAGE_SVH
