`ifndef INC_SHMINS_CONTIGUOUS_SEQUENCE_ITEM_SVH
`define INC_SHMINS_CONTIGUOUS_SEQUENCE_ITEM_SVH

//------------------------------------------------------------------------------
// @brief Generates one contiguous MADDR stream per active thread.
//
// The item supports LDST_S and LDST_V, which share the address formula
// base+offset[thread]+element*D. It generates aligned start MADDR values in the
// selected space, fills the common element MADDR model, derives a shared base,
// and encodes one offset per thread. It does not implement strided, indexed, or
// VTRANS-specific generation.
//------------------------------------------------------------------------------
class shmins_contiguous_sequence_item extends shmins_sequence_item;
  localparam int unsigned MAX_CANDIDATE_RETRY = 4096;
  localparam int unsigned MAX_GENERATION_RETRY = 256;

  // Element-zero MADDR anchor generated for each thread.
  longint signed start_maddr[THD_N];

  constraint c_contiguous_kind {
    creq_itype inside {LDST_S, LDST_V};
    creq_info == 4'h0;
  }

  //----------------------------------------------------------------------------
  // @brief Constructs a contiguous SHM transaction.
  //
  // @param name UVM object instance name.
  //----------------------------------------------------------------------------
  extern function new(string name = "shmins_contiguous_sequence_item");

  //----------------------------------------------------------------------------
  // @brief Generates start MADDR values, a shared base, and per-thread offsets.
  //
  // @post elem_maddr contains every active contiguous MADDR and offs_elem[t][0]
  //       encodes start_maddr[t]-creq_base for each active thread.
  //----------------------------------------------------------------------------
  extern protected function void generate_address_fields();

  //----------------------------------------------------------------------------
  // @brief Recomputes one contiguous MADDR from packed transaction fields.
  //
  // @param thread_idx Source thread index.
  // @param elem_idx Data element index.
  // @return creq_base plus thread offset plus elem_idx times dtype byte width.
  //----------------------------------------------------------------------------
  extern protected function longint signed calculate_maddr(int thread_idx, int elem_idx);

  //----------------------------------------------------------------------------
  // @brief Narrows the fast space range to legal contiguous start candidates.
  //
  // @param thread_idx Thread whose active element indices determine the range.
  // @param space_lower Inclusive lower bound returned by fast_legal_space_range().
  // @param space_upper Exclusive upper bound returned by fast_legal_space_range().
  // @param start_lower Inclusive start MADDR lower bound.
  // @param start_upper Exclusive start MADDR upper bound.
  // @return 1 when the thread has an active element and a non-empty fast range.
  //----------------------------------------------------------------------------
  extern protected function bit fast_contiguous_start_range(int thread_idx,
                                                            longint signed space_lower,
                                                            longint signed space_upper,
                                                            output longint signed start_lower,
                                                            output longint signed start_upper);

  //----------------------------------------------------------------------------
  // @brief Checks all active elements derived from one candidate start MADDR.
  //
  // @param thread_idx Thread receiving the candidate start.
  // @param candidate_start Element-zero MADDR anchor to check.
  // @return 1 when every active derived MADDR passes legal_space_maddr_check().
  //----------------------------------------------------------------------------
  extern protected function bit candidate_stream_is_legal(int thread_idx, longint signed candidate_start);

  //----------------------------------------------------------------------------
  // @brief Writes one accepted contiguous stream into the common MADDR model.
  //
  // @param thread_idx Thread receiving the accepted stream.
  // @param accepted_start Element-zero MADDR anchor for the stream.
  // @post start_maddr and every active elem_maddr entry for the thread are updated.
  //----------------------------------------------------------------------------
  extern protected function void fill_contiguous_maddrs(int thread_idx, longint signed accepted_start);

  //----------------------------------------------------------------------------
  // @brief Returns whether a thread contains at least one active data element.
  //
  // @param thread_idx Thread to inspect.
  // @return 1 when any element is selected by is_active_element().
  //----------------------------------------------------------------------------
  extern protected function bit thread_has_active_element(int thread_idx);

  `uvm_object_utils(shmins_contiguous_sequence_item)
endclass : shmins_contiguous_sequence_item

function shmins_contiguous_sequence_item::new(string name = "shmins_contiguous_sequence_item");
  super.new(name);
endfunction : new

function void shmins_contiguous_sequence_item::generate_address_fields();
  longint signed space_lower;
  longint signed space_upper;
  bit generated;

  if (!fast_legal_space_range(space_lower, space_upper)) begin
    `uvm_fatal("SHMINS_CONTIGUOUS_INVALID_SPACE",
               $sformatf("space=%0d wpid=%0d wpnum=%0d has no legal encoding range",
                         creq_space, creq_wpid, creq_wpnum))
  end

  generated = 1'b0;
  for (int unsigned generation_attempt = 0;
       generation_attempt < MAX_GENERATION_RETRY && !generated;
       generation_attempt++) begin
    longint signed base_lower;
    longint signed base_upper;
    bit all_threads_accepted;

    base_lower = 0;
    base_upper = (longint'(1) << MADDR_W) - 1;
    all_threads_accepted = 1'b1;
    foreach (start_maddr[thread_idx]) begin
      start_maddr[thread_idx] = 0;
    end
    foreach (elem_maddr[thread_idx, elem_idx]) begin
      elem_maddr[thread_idx][elem_idx] = 0;
      offs_elem[thread_idx][elem_idx] = 0;
    end

    for (int thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
      longint signed start_lower;
      longint signed start_upper;
      bit accepted;

      if (!thread_has_active_element(thread_idx)) begin
        continue;
      end
      if (!fast_contiguous_start_range(thread_idx, space_lower, space_upper, start_lower, start_upper)) begin
        all_threads_accepted = 1'b0;
        break;
      end

      accepted = 1'b0;
      for (int unsigned candidate_attempt = 0; candidate_attempt < MAX_CANDIDATE_RETRY; candidate_attempt++) begin
        longint signed candidate_base_lower;
        longint signed candidate_base_upper;
        longint signed candidate_start;

        if (!sample_aligned_value(start_lower, start_upper, data_byte_w(), candidate_start)) begin
          break;
        end
        candidate_base_lower = base_lower;
        candidate_base_upper = base_upper;
        if (candidate_stream_is_legal(thread_idx, candidate_start) &&
            intersect_creq_base_range(candidate_start, candidate_base_lower, candidate_base_upper)) begin
          start_maddr[thread_idx] = candidate_start;
          base_lower = candidate_base_lower;
          base_upper = candidate_base_upper;
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
      fill_contiguous_maddrs(thread_idx, start_maddr[thread_idx]);
    end

    if (!all_threads_accepted || !check_active_maddr_byte_uniqueness()) begin
      generation_retry_count++;
      generation_reject_count++;
      continue;
    end
    if (!sample_creq_base(base_lower, base_upper)) begin
      generation_retry_count++;
      generation_reject_count++;
      continue;
    end

    generated = 1'b1;
    for (int thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
      if (!thread_has_active_element(thread_idx)) begin
        continue;
      end
      offs_elem[thread_idx][0] = start_maddr[thread_idx] - longint'(creq_base[MADDR_W-1:0]);
      if (!check_offset_encodable(offs_elem[thread_idx][0])) begin
        generated = 1'b0;
        generation_retry_count++;
        generation_reject_count++;
        break;
      end
    end
  end

  if (!generated) begin
    `uvm_fatal("SHMINS_CONTIGUOUS_RETRY_EXHAUSTED",
               $sformatf({"generation_retries=%0d candidate_retries=%0d rw=%0d itype=%0d space=%0d ",
                          "dtype=%0d atype_w=%0d atype_s=%0d atype_g=%0d inv_size=%0d wpid=%0d wpnum=%0d"},
                         MAX_GENERATION_RETRY, MAX_CANDIDATE_RETRY, creq_rw, creq_itype, creq_space,
                         creq_dtype, creq_atype_w, creq_atype_s, creq_atype_g, creq_inv_size,
                         creq_wpid, creq_wpnum))
  end
endfunction : generate_address_fields

function bit shmins_contiguous_sequence_item::fast_contiguous_start_range(int thread_idx,
                                                                          longint signed space_lower,
                                                                          longint signed space_upper,
                                                                          output longint signed start_lower,
                                                                          output longint signed start_upper);
  int last_active;

  start_lower = space_lower;
  start_upper = space_lower;
  last_active = -1;
  for (int elem_idx = 0; elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N; elem_idx++) begin
    if (is_active_element(thread_idx, elem_idx)) begin
      last_active = elem_idx;
    end
  end
  if (last_active < 0) begin
    return 1'b0;
  end

  start_upper = space_upper - longint'(last_active) * data_byte_w();
  return start_upper > start_lower;
endfunction : fast_contiguous_start_range

function bit shmins_contiguous_sequence_item::candidate_stream_is_legal(int thread_idx,
                                                                        longint signed candidate_start);
  for (int elem_idx = 0; elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N; elem_idx++) begin
    longint signed candidate_maddr;

    if (!is_active_element(thread_idx, elem_idx)) begin
      continue;
    end
    candidate_maddr = candidate_start + longint'(elem_idx) * data_byte_w();
    if (!legal_space_maddr_check(thread_idx, candidate_maddr)) begin
      return 1'b0;
    end
  end
  return 1'b1;
endfunction : candidate_stream_is_legal

function void shmins_contiguous_sequence_item::fill_contiguous_maddrs(int thread_idx,
                                                                     longint signed accepted_start);
  start_maddr[thread_idx] = accepted_start;
  for (int elem_idx = 0; elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N; elem_idx++) begin
    if (is_active_element(thread_idx, elem_idx)) begin
      elem_maddr[thread_idx][elem_idx] = accepted_start + longint'(elem_idx) * data_byte_w();
    end
  end
endfunction : fill_contiguous_maddrs

function bit shmins_contiguous_sequence_item::thread_has_active_element(int thread_idx);
  for (int elem_idx = 0; elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N; elem_idx++) begin
    if (is_active_element(thread_idx, elem_idx)) begin
      return 1'b1;
    end
  end
  return 1'b0;
endfunction : thread_has_active_element

function longint signed shmins_contiguous_sequence_item::calculate_maddr(int thread_idx, int elem_idx);
  return longint'(creq_base[MADDR_W-1:0]) + decode_packed_offset(thread_idx, 0) +
         longint'(elem_idx) * data_byte_w();
endfunction : calculate_maddr

`endif // INC_SHMINS_CONTIGUOUS_SEQUENCE_ITEM_SVH
