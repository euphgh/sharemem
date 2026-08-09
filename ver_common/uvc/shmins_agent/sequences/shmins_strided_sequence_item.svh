`ifndef INC_SHMINS_STRIDED_SEQUENCE_ITEM_SVH
`define INC_SHMINS_STRIDED_SEQUENCE_ITEM_SVH

//------------------------------------------------------------------------------
// @brief Generates one signed or unsigned stride for each active thread.
//
// The item supports LDSTE_S and the address formula base+element*stride[thread].
// It generates a common aligned base in the selected space, derives a fast
// reachable stride interval for each thread, and validates every active MADDR.
// It does not implement contiguous, indexed, or VTRANS-specific generation.
//------------------------------------------------------------------------------
class shmins_strided_sequence_item extends shmins_sequence_item;
  localparam int unsigned MAX_CANDIDATE_RETRY = 4096;
  localparam int unsigned MAX_GENERATION_RETRY = 64;

  constraint c_strided_kind {
    creq_itype == LDSTE_S;
    creq_info == 4'h0;
  }

  constraint c_strided_element_zero {
    if ((creq_rw == SHM_V2M || m2v_unique_enable) && creq_space inside {SPACE_WRP, SPACE_BLK}) {
      foreach (creq_vmsk[thread_idx]) {
        creq_tmsk[thread_idx] -> creq_vmsk[thread_idx][0] == 1'b0;
      }
    }
  }

  //----------------------------------------------------------------------------
  // @brief Constructs a strided SHM transaction.
  //
  // @param name UVM object instance name.
  //----------------------------------------------------------------------------
  extern function new(string name = "shmins_strided_sequence_item");

  //----------------------------------------------------------------------------
  // @brief Generates a common base, per-thread strides, and active MADDR values.
  //
  // @post offs_elem[t][0] is the encoded stride and elem_maddr follows base+k*stride.
  //----------------------------------------------------------------------------
  extern protected function void generate_address_fields();

  //----------------------------------------------------------------------------
  // @brief Recomputes one strided MADDR from packed transaction fields.
  //
  // @param thread_idx Source thread index.
  // @param elem_idx Data element index and stride multiplier.
  // @return creq_base plus elem_idx times the thread's decoded stride.
  //----------------------------------------------------------------------------
  extern protected function longint signed calculate_maddr(int thread_idx, int elem_idx);

  //----------------------------------------------------------------------------
  // @brief Computes a fast inclusive stride interval for one active thread.
  //
  // @param thread_idx Thread whose largest active index bounds the stride.
  // @param space_lower Inclusive address-space lower bound.
  // @param space_upper Exclusive address-space upper bound.
  // @param stride_lower Inclusive decoded stride lower bound.
  // @param stride_upper Inclusive decoded stride upper bound.
  // @return 1 when the thread has an active element and a non-empty stride range.
  //----------------------------------------------------------------------------
  extern protected function bit fast_stride_range(int thread_idx,
                                                  longint signed space_lower,
                                                  longint signed space_upper,
                                                  output longint signed stride_lower,
                                                  output longint signed stride_upper);

  //----------------------------------------------------------------------------
  // @brief Checks one candidate stride against space and byte-collision rules.
  //
  // @param thread_idx Thread receiving the candidate stride.
  // @param candidate_stride Decoded byte stride to check.
  // @param used_bytes Physical byte keys committed by earlier threads.
  // @return 1 when all active derived MADDR values are legal and non-overlapping.
  //----------------------------------------------------------------------------
  extern protected function bit candidate_stream_is_legal(int thread_idx,
                                                           longint signed candidate_stride,
                                                           ref bit used_bytes[longint unsigned]);

  //----------------------------------------------------------------------------
  // @brief Writes one accepted strided stream into the MADDR model and byte set.
  //
  // @param thread_idx Thread receiving the accepted stride.
  // @param accepted_stride Decoded byte stride for the thread.
  // @param used_bytes Physical byte-key set updated when uniqueness is required.
  // @post offs_elem[t][0], active elem_maddr entries, and used_bytes are updated.
  //----------------------------------------------------------------------------
  extern protected function void commit_strided_stream(int thread_idx,
                                                        longint signed accepted_stride,
                                                        ref bit used_bytes[longint unsigned]);

  //----------------------------------------------------------------------------
  // @brief Returns whether a thread contains at least one active data element.
  //
  // @param thread_idx Thread to inspect.
  // @return 1 when any element is selected by is_active_element().
  //----------------------------------------------------------------------------
  extern protected function bit thread_has_active_element(int thread_idx);

  `uvm_object_utils(shmins_strided_sequence_item)
endclass : shmins_strided_sequence_item

function shmins_strided_sequence_item::new(string name = "shmins_strided_sequence_item");
  super.new(name);
endfunction : new

function void shmins_strided_sequence_item::generate_address_fields();
  longint signed space_lower;
  longint signed space_upper;
  bit generated;

  if (!fast_legal_space_range(space_lower, space_upper)) begin
    `uvm_fatal("SHMINS_STRIDED_INVALID_SPACE",
               $sformatf("space=%0d wpid=%0d wpnum=%0d has no legal encoding range",
                         creq_space, creq_wpid, creq_wpnum))
  end

  generated = 1'b0;
  for (int unsigned generation_attempt = 0;
       generation_attempt < MAX_GENERATION_RETRY && !generated;
       generation_attempt++) begin
    bit used_bytes[longint unsigned];
    longint signed base_maddr;
    bit base_accepted;
    bit all_threads_accepted;

    foreach (elem_maddr[thread_idx, elem_idx]) begin
      elem_maddr[thread_idx][elem_idx] = 0;
      offs_elem[thread_idx][elem_idx] = 0;
    end

    base_accepted = 1'b0;
    for (int unsigned candidate_attempt = 0;
         candidate_attempt < MAX_CANDIDATE_RETRY;
         candidate_attempt++) begin
      if (sample_aligned_value(space_lower, space_upper, data_byte_w(), base_maddr) &&
          legal_space_maddr_check(0, base_maddr)) begin
        base_accepted = 1'b1;
        break;
      end
      generation_retry_count++;
      generation_reject_count++;
    end
    if (!base_accepted) begin
      generation_retry_count++;
      generation_reject_count++;
      continue;
    end
    creq_base = '0;
    creq_base[MADDR_W-1:0] = base_maddr[MADDR_W-1:0];

    all_threads_accepted = 1'b1;
    for (int thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
      longint signed stride_lower;
      longint signed stride_upper;
      bit accepted;

      if (!thread_has_active_element(thread_idx)) begin
        continue;
      end
      if (!fast_stride_range(thread_idx, space_lower, space_upper, stride_lower, stride_upper)) begin
        all_threads_accepted = 1'b0;
        break;
      end

      accepted = 1'b0;
      for (int unsigned candidate_attempt = 0;
           candidate_attempt < MAX_CANDIDATE_RETRY;
           candidate_attempt++) begin
        longint signed candidate_stride;

        if (!sample_aligned_value(stride_lower, stride_upper + 1, data_byte_w(), candidate_stride)) begin
          break;
        end
        if (check_offset_encodable(candidate_stride) &&
            candidate_stream_is_legal(thread_idx, candidate_stride, used_bytes)) begin
          commit_strided_stream(thread_idx, candidate_stride, used_bytes);
          accepted = 1'b1;
          break;
        end
        generation_retry_count++;
        generation_reject_count++;
      end
      if (!accepted) begin
        all_threads_accepted = 1'b0;
        break;
      end
    end

    if (!all_threads_accepted || !check_active_maddr_byte_uniqueness()) begin
      generation_retry_count++;
      generation_reject_count++;
      continue;
    end
    generated = 1'b1;
  end

  if (!generated) begin
    `uvm_fatal("SHMINS_STRIDED_RETRY_EXHAUSTED",
               $sformatf({"generation_retries=%0d candidate_retries=%0d rw=%0d space=%0d dtype=%0d ",
                          "atype_w=%0d atype_s=%0d atype_g=%0d inv_size=%0d wpid=%0d wpnum=%0d"},
                         MAX_GENERATION_RETRY, MAX_CANDIDATE_RETRY, creq_rw, creq_space, creq_dtype,
                         creq_atype_w, creq_atype_s, creq_atype_g, creq_inv_size, creq_wpid, creq_wpnum))
  end
endfunction : generate_address_fields

function bit shmins_strided_sequence_item::fast_stride_range(int thread_idx,
                                                             longint signed space_lower,
                                                             longint signed space_upper,
                                                             output longint signed stride_lower,
                                                             output longint signed stride_upper);
  longint signed decode_lower;
  longint signed decode_upper;
  longint signed base_maddr;
  int last_active;

  decoded_offset_range(decode_lower, decode_upper);
  stride_lower = decode_lower;
  stride_upper = decode_upper;
  last_active = -1;
  for (int elem_idx = 0; elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N; elem_idx++) begin
    if (is_active_element(thread_idx, elem_idx)) begin
      last_active = elem_idx;
    end
  end
  if (last_active < 0) begin
    return 1'b0;
  end
  if (last_active == 0) begin
    stride_lower = 0;
    stride_upper = 0;
    return check_offset_encodable(0);
  end

  base_maddr = longint'(creq_base[MADDR_W-1:0]);
  if (stride_lower < ceil_divide_signed(space_lower - base_maddr, last_active)) begin
    stride_lower = ceil_divide_signed(space_lower - base_maddr, last_active);
  end
  if (stride_upper > floor_divide_signed(space_upper - 1 - base_maddr, last_active)) begin
    stride_upper = floor_divide_signed(space_upper - 1 - base_maddr, last_active);
  end
  return stride_lower <= stride_upper;
endfunction : fast_stride_range

function bit shmins_strided_sequence_item::candidate_stream_is_legal(
    int thread_idx,
    longint signed candidate_stride,
    ref bit used_bytes[longint unsigned]);
  bit candidate_bytes[longint unsigned];

  for (int elem_idx = 0; elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N; elem_idx++) begin
    longint signed candidate_maddr;
    shmins_address_result_t mapped;

    if (!is_active_element(thread_idx, elem_idx)) begin
      continue;
    end
    candidate_maddr = longint'(creq_base[MADDR_W-1:0]) + longint'(elem_idx) * candidate_stride;
    if (!legal_space_maddr_check(thread_idx, candidate_maddr)) begin
      return 1'b0;
    end
    if (!uniqueness_required()) begin
      continue;
    end
    mapped = map_maddr(thread_idx, candidate_maddr);
    for (int byte_lane = 0; byte_lane < data_byte_w(); byte_lane++) begin
      longint unsigned key;

      key = physical_byte_key(mapped.bank_id, mapped.baddr + byte_lane);
      if (used_bytes.exists(key) || candidate_bytes.exists(key)) begin
        return 1'b0;
      end
      candidate_bytes[key] = 1'b1;
    end
  end
  return 1'b1;
endfunction : candidate_stream_is_legal

function void shmins_strided_sequence_item::commit_strided_stream(
    int thread_idx,
    longint signed accepted_stride,
    ref bit used_bytes[longint unsigned]);
  offs_elem[thread_idx][0] = accepted_stride;
  for (int elem_idx = 0; elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N; elem_idx++) begin
    shmins_address_result_t mapped;

    if (!is_active_element(thread_idx, elem_idx)) begin
      continue;
    end
    elem_maddr[thread_idx][elem_idx] =
        longint'(creq_base[MADDR_W-1:0]) + longint'(elem_idx) * accepted_stride;
    if (!uniqueness_required()) begin
      continue;
    end
    mapped = map_maddr(thread_idx, elem_maddr[thread_idx][elem_idx]);
    for (int byte_lane = 0; byte_lane < data_byte_w(); byte_lane++) begin
      used_bytes[physical_byte_key(mapped.bank_id, mapped.baddr + byte_lane)] = 1'b1;
    end
  end
endfunction : commit_strided_stream

function bit shmins_strided_sequence_item::thread_has_active_element(int thread_idx);
  for (int elem_idx = 0; elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N; elem_idx++) begin
    if (is_active_element(thread_idx, elem_idx)) begin
      return 1'b1;
    end
  end
  return 1'b0;
endfunction : thread_has_active_element

function longint signed shmins_strided_sequence_item::calculate_maddr(int thread_idx, int elem_idx);
  return longint'(creq_base[MADDR_W-1:0]) + longint'(elem_idx) * decode_packed_offset(thread_idx, 0);
endfunction : calculate_maddr

`endif // INC_SHMINS_STRIDED_SEQUENCE_ITEM_SVH
