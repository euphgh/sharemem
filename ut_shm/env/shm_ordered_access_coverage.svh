`ifndef INC_SHM_ORDERED_ACCESS_COVERAGE_SVH
`define INC_SHM_ORDERED_ACCESS_COVERAGE_SVH

//------------------------------------------------------------------------------
// @brief Covers accepted same-thread ordered-access pairs and final convergence.
//
// The collector derives physical byte overlap from immutable reference
// transactions, retains observations until the environment checks final memory,
// and samples only pairs whose architectural result converged. It does not
// predict data, alter scoreboard matching, or define testcase stimulus.
//------------------------------------------------------------------------------
class shm_ordered_access_coverage extends uvm_subscriber #(shm_wtrans_item);
  typedef enum int unsigned {
    SHM_ORDER_M_READ_THEN_WRITE,
    SHM_ORDER_M_WRITE_THEN_READ,
    SHM_ORDER_M_WRITE_THEN_WRITE,
    SHM_ORDER_V_WRITE_THEN_WRITE
  } shm_order_kind_e;

  typedef enum int unsigned {
    SHM_ORDER_OVERLAP_EXACT,
    SHM_ORDER_OVERLAP_PARTIAL
  } shm_order_overlap_e;

  typedef shm_physical_addr_t physical_addr_map_t[longint unsigned];

  typedef struct {
    shm_order_kind_e    kind;
    shm_order_overlap_e overlap;
    int unsigned        first_dtype;
    int unsigned        second_dtype;
    int unsigned        thread_idx;
    int unsigned        gid;
    int unsigned        first_space;
    int unsigned        second_space;
    int unsigned        first_itype;
    int unsigned        second_itype;
    bit                 has_vtrans;
  } ordered_pair_sample_t;

  // Most recently accepted reference transaction in the current checked batch.
  shm_wtrans_item previous_item;

  // Ordered overlap samples waiting for the next final-memory result.
  ordered_pair_sample_t pending_samples[$];

  // Public counters used by component tests and coverage diagnostics.
  longint unsigned observed_pair_count[4][2];
  longint unsigned observed_gid_count[4][GID_N];
  longint unsigned converged_pair_count;
  longint unsigned failed_final_check_count;

  covergroup ordered_access_cg with function sample(
      int unsigned order_kind,
      int unsigned overlap_class,
      int unsigned first_dtype,
      int unsigned second_dtype,
      int unsigned thread_idx,
      int unsigned gid,
      int unsigned first_space,
      int unsigned second_space,
      int unsigned first_itype,
      int unsigned second_itype,
      int unsigned has_vtrans,
      int unsigned converged);
    option.per_instance = 1;

    cp_order_kind: coverpoint order_kind {
      bins m_read_then_write = {SHM_ORDER_M_READ_THEN_WRITE};
      bins m_write_then_read = {SHM_ORDER_M_WRITE_THEN_READ};
      bins m_write_then_write = {SHM_ORDER_M_WRITE_THEN_WRITE};
      bins v_write_then_write = {SHM_ORDER_V_WRITE_THEN_WRITE};
    }
    cp_overlap: coverpoint overlap_class {
      bins exact = {SHM_ORDER_OVERLAP_EXACT};
      bins partial = {SHM_ORDER_OVERLAP_PARTIAL};
    }
    cp_first_dtype: coverpoint first_dtype {
      bins dtype8 = {DTYP_8};
      bins dtype16 = {DTYP_16};
      bins dtype32 = {DTYP_32};
    }
    cp_second_dtype: coverpoint second_dtype {
      bins dtype8 = {DTYP_8};
      bins dtype16 = {DTYP_16};
      bins dtype32 = {DTYP_32};
    }
    cp_thread: coverpoint thread_idx {
      bins thread0 = {0};
      bins thread15 = {THD_N-1};
    }
    cp_gid: coverpoint gid {
      bins low = {0};
      bins high = {1};
    }
    cp_first_space: coverpoint first_space {
      bins loc = {SPACE_LOC};
      bins wrp = {SPACE_WRP};
      bins blk = {SPACE_BLK};
    }
    cp_second_space: coverpoint second_space {
      bins loc = {SPACE_LOC};
      bins wrp = {SPACE_WRP};
      bins blk = {SPACE_BLK};
    }
    cp_first_topology: coverpoint first_itype {
      bins contiguous = {LDST_S, LDST_V};
      bins strided = {LDSTE_S};
      bins indexed = {LDSTE_V};
    }
    cp_second_topology: coverpoint second_itype {
      bins contiguous = {LDST_S, LDST_V};
      bins strided = {LDSTE_S};
      bins indexed = {LDSTE_V};
    }
    cp_vtrans: coverpoint has_vtrans {
      bins normal = {0};
      bins vtrans = {1};
    }
    cp_converged: coverpoint converged {
      bins yes = {1};
      illegal_bins no = {0};
    }

    cx_kind_overlap_result: cross cp_order_kind, cp_overlap, cp_converged;
    cx_kind_gid_result: cross cp_order_kind, cp_gid, cp_converged;
    cx_kind_thread_result: cross cp_order_kind, cp_thread, cp_converged;
  endgroup

  //----------------------------------------------------------------------------
  // @brief Constructs and clears the ordered-access coverage collector.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this collector.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_ordered_access_coverage", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Observes one reference transaction in creq acceptance order.
  //
  // @param t Immutable transaction after reference address reconstruction.
  //----------------------------------------------------------------------------
  extern virtual function void write(shm_wtrans_item t);

  //----------------------------------------------------------------------------
  // @brief Associates pending ordered pairs with one final-memory check result.
  //
  // @param converged 1 when reference and actual touched bytes are identical.
  // @post Pending samples and the pair-history boundary are cleared.
  //----------------------------------------------------------------------------
  extern function void sample_final_result(bit converged);

  //----------------------------------------------------------------------------
  // @brief Derives same-thread overlap samples from one consecutive pair.
  //
  // @param first_item Earlier accepted reference transaction.
  // @param second_item Later accepted reference transaction.
  // @post One pending sample is appended for each thread with ordered overlap.
  //----------------------------------------------------------------------------
  extern protected function void classify_pair(shm_wtrans_item first_item,
                                                shm_wtrans_item second_item);

  //----------------------------------------------------------------------------
  // @brief Collects one thread's interpreted M-side physical bytes.
  //
  // @param item Reference transaction containing mapped element addresses.
  // @param thread_idx Thread whose M-read or M-write bytes are selected.
  // @param accesses Replaced with a physical-keyed address map.
  //----------------------------------------------------------------------------
  extern protected function void collect_m_bytes(shm_wtrans_item item,
                                                  int unsigned thread_idx,
                                                  ref physical_addr_map_t accesses);

  //----------------------------------------------------------------------------
  // @brief Collects one M2V thread's physical V-write bytes.
  //
  // @param item Reference transaction containing writeback metadata.
  // @param thread_idx Thread whose V-write bytes are selected.
  // @param accesses Replaced with a physical-keyed address map.
  //----------------------------------------------------------------------------
  extern protected function void collect_v_write_bytes(shm_wtrans_item item,
                                                        int unsigned thread_idx,
                                                        ref physical_addr_map_t accesses);

  `uvm_component_utils(shm_ordered_access_coverage)
endclass : shm_ordered_access_coverage

function shm_ordered_access_coverage::new(string name = "shm_ordered_access_coverage",
                                          uvm_component parent = null);
  super.new(name, parent);
  previous_item = null;
  converged_pair_count = 0;
  failed_final_check_count = 0;
  foreach (observed_pair_count[kind, overlap]) begin
    observed_pair_count[kind][overlap] = 0;
  end
  foreach (observed_gid_count[kind, gid]) begin
    observed_gid_count[kind][gid] = 0;
  end
  ordered_access_cg = new();
endfunction : new

function void shm_ordered_access_coverage::write(shm_wtrans_item t);
  if (t == null) begin
    `uvm_error("SHM_ORDERED_COVERAGE_NULL", "received a null reference transaction")
    return;
  end
  if (previous_item != null) begin
    classify_pair(previous_item, t);
  end
  previous_item = t;
endfunction : write

function void shm_ordered_access_coverage::sample_final_result(bit converged);
  if (!converged) begin
    failed_final_check_count++;
  end
  foreach (pending_samples[index]) begin
    ordered_pair_sample_t sample_value = pending_samples[index];

    ordered_access_cg.sample(sample_value.kind, sample_value.overlap,
                             sample_value.first_dtype, sample_value.second_dtype,
                             sample_value.thread_idx, sample_value.gid,
                             sample_value.first_space, sample_value.second_space,
                             sample_value.first_itype, sample_value.second_itype,
                             sample_value.has_vtrans, converged);
    if (converged) begin
      converged_pair_count++;
    end
  end
  pending_samples.delete();
  previous_item = null;
endfunction : sample_final_result

function void shm_ordered_access_coverage::classify_pair(shm_wtrans_item first_item,
                                                         shm_wtrans_item second_item);
  shm_order_kind_e order_kind;

  if (first_item.creq_rw == SHM_M2V && second_item.creq_rw == SHM_V2M) begin
    order_kind = SHM_ORDER_M_READ_THEN_WRITE;
  end else if (first_item.creq_rw == SHM_V2M && second_item.creq_rw == SHM_M2V) begin
    order_kind = SHM_ORDER_M_WRITE_THEN_READ;
  end else if (first_item.creq_rw == SHM_V2M && second_item.creq_rw == SHM_V2M) begin
    order_kind = SHM_ORDER_M_WRITE_THEN_WRITE;
  end else begin
    order_kind = SHM_ORDER_V_WRITE_THEN_WRITE;
  end

  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    physical_addr_map_t first_accesses;
    physical_addr_map_t second_accesses;
    int unsigned overlap_count = 0;
    shm_physical_addr_t overlap_addr;

    if (order_kind == SHM_ORDER_V_WRITE_THEN_WRITE) begin
      collect_v_write_bytes(first_item, thread_idx, first_accesses);
      collect_v_write_bytes(second_item, thread_idx, second_accesses);
    end else begin
      collect_m_bytes(first_item, thread_idx, first_accesses);
      collect_m_bytes(second_item, thread_idx, second_accesses);
    end

    foreach (first_accesses[key]) begin
      if (second_accesses.exists(key)) begin
        overlap_count++;
        overlap_addr = first_accesses[key];
      end
    end
    if (overlap_count != 0) begin
      ordered_pair_sample_t sample_value;

      sample_value.kind = order_kind;
      sample_value.overlap = overlap_count == first_accesses.num() &&
                             overlap_count == second_accesses.num()
                                 ? SHM_ORDER_OVERLAP_EXACT
                                 : SHM_ORDER_OVERLAP_PARTIAL;
      sample_value.first_dtype = first_item.creq_dtype;
      sample_value.second_dtype = second_item.creq_dtype;
      sample_value.thread_idx = thread_idx;
      sample_value.gid = overlap_addr.gid;
      sample_value.first_space = first_item.creq_space;
      sample_value.second_space = second_item.creq_space;
      sample_value.first_itype = first_item.creq_itype;
      sample_value.second_itype = second_item.creq_itype;
      sample_value.has_vtrans = first_item.creq_info == 4'hf || second_item.creq_info == 4'hf;
      pending_samples.push_back(sample_value);
      observed_pair_count[order_kind][sample_value.overlap]++;
      observed_gid_count[order_kind][sample_value.gid]++;
    end
  end
endfunction : classify_pair

function void shm_ordered_access_coverage::collect_m_bytes(shm_wtrans_item item,
                                                           int unsigned thread_idx,
                                                           ref physical_addr_map_t accesses);
  accesses.delete();
  if (thread_idx >= THD_N || item.creq_tmsk[thread_idx] !== 1'b1) begin
    return;
  end

  for (int unsigned elem_idx = 0;
       elem_idx < item.baddr_2d_array[thread_idx].size();
       elem_idx++) begin
    for (int unsigned byte_lane = 0; byte_lane < item.data_byte_w(); byte_lane++) begin
      shm_physical_addr_t physical_addr;

      if (!item.wstrb_2d_array[thread_idx][elem_idx][byte_lane]) begin
        continue;
      end
      physical_addr.bank_id = item.bid_2d_array[thread_idx][elem_idx];
      physical_addr.gid = item.gid_2d_array[thread_idx][elem_idx];
      physical_addr.baddr = item.baddr_2d_array[thread_idx][elem_idx] + shm_baddr_t'(byte_lane);
      accesses[item.make_physical_byte_key(physical_addr)] = physical_addr;
    end
  end
endfunction : collect_m_bytes

function void shm_ordered_access_coverage::collect_v_write_bytes(
    shm_wtrans_item item,
    int unsigned thread_idx,
    ref physical_addr_map_t accesses);
  accesses.delete();
  if (item.creq_rw != SHM_M2V || thread_idx >= THD_N ||
      item.creq_tmsk[thread_idx] !== 1'b1) begin
    return;
  end

  for (int unsigned elem_idx = 0;
       elem_idx < item.wstrb_2d_array[thread_idx].size();
       elem_idx++) begin
    for (int unsigned byte_lane = 0; byte_lane < item.data_byte_w(); byte_lane++) begin
      shm_physical_addr_t physical_addr;

      if (!item.wstrb_2d_array[thread_idx][elem_idx][byte_lane]) begin
        continue;
      end
      physical_addr.bank_id = shm_bank_id_t'(thread_idx);
      physical_addr.gid = shm_gid_t'(int'(item.creq_wpid) / WARP_PER_GID);
      physical_addr.baddr = shm_baddr_t'(int'(item.creq_vaddr) + elem_idx * item.data_byte_w() + byte_lane);
      accesses[item.make_physical_byte_key(physical_addr)] = physical_addr;
    end
  end
endfunction : collect_v_write_bytes

`endif // INC_SHM_ORDERED_ACCESS_COVERAGE_SVH
