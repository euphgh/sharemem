`ifndef INC_SHMINS_INDEXED_SEQUENCE_ITEM_SVH
`define INC_SHMINS_INDEXED_SEQUENCE_ITEM_SVH

//------------------------------------------------------------------------------
// @brief Generates one independently indexed MADDR for each active element.
//
// The item supports LDSTE_V. It samples active element MADDR values from the
// selected address space, incrementally maintains a feasible common base range,
// and derives one encoded offset per active element. It does not implement
// contiguous, strided, or VTRANS-specific generation.
//------------------------------------------------------------------------------
class shmins_indexed_sequence_item extends shmins_sequence_item;
  localparam int unsigned MAX_CANDIDATE_RETRY = 4096;
  localparam int unsigned MAX_GENERATION_RETRY = 64;

  constraint c_indexed_kind {
    creq_itype == LDSTE_V;
    creq_info == 4'h0;
  }

  constraint c_indexed_offset_capacity {
    foreach (elem_num[thread_idx]) {
      if (creq_atype_w == ATYP_32) {
        elem_num[thread_idx] <= VEC_W / 32;
      } else if (creq_atype_w == ATYP_16) {
        elem_num[thread_idx] <= VEC_W / 16;
      }
    }
  }

  //----------------------------------------------------------------------------
  // @brief Constructs an indexed SHM transaction.
  //
  // @param name UVM object instance name.
  //----------------------------------------------------------------------------
  extern function new(string name = "shmins_indexed_sequence_item");

  //----------------------------------------------------------------------------
  // @brief Generates per-element MADDR values, a shared base, and offsets.
  //
  // @post Each active offs_elem[t][k] encodes elem_maddr[t][k]-creq_base.
  //----------------------------------------------------------------------------
  extern protected function void generate_address_fields();

  //----------------------------------------------------------------------------
  // @brief Recomputes one indexed MADDR from packed transaction fields.
  //
  // @param thread_idx Source thread index.
  // @param elem_idx Data and offset element index.
  // @return creq_base plus the selected element's decoded packed offset.
  //----------------------------------------------------------------------------
  extern protected function longint signed calculate_maddr(int thread_idx, int elem_idx);

  //----------------------------------------------------------------------------
  // @brief Checks whether one candidate element overlaps committed byte keys.
  //
  // @param thread_idx Source thread used by the address-space mapping.
  // @param candidate_maddr Candidate element MADDR.
  // @param used_bytes Physical byte keys committed by earlier elements.
  // @return 1 when uniqueness is disabled or all candidate byte keys are free.
  //----------------------------------------------------------------------------
  extern protected function bit candidate_bytes_are_available(int thread_idx,
                                                               longint signed candidate_maddr,
                                                               ref bit used_bytes[longint unsigned]);

  //----------------------------------------------------------------------------
  // @brief Commits one accepted element's physical byte keys.
  //
  // @param thread_idx Source thread used by the address-space mapping.
  // @param accepted_maddr Accepted element MADDR.
  // @param used_bytes Physical byte-key set updated in place.
  // @post All element byte keys are present when uniqueness is required.
  //----------------------------------------------------------------------------
  extern protected function void reserve_candidate_bytes(int thread_idx,
                                                          longint signed accepted_maddr,
                                                          ref bit used_bytes[longint unsigned]);

  `uvm_object_utils(shmins_indexed_sequence_item)
endclass : shmins_indexed_sequence_item

function shmins_indexed_sequence_item::new(string name = "shmins_indexed_sequence_item");
  super.new(name);
endfunction : new

function void shmins_indexed_sequence_item::generate_address_fields();
  longint signed decode_lower;
  longint signed decode_upper;
  longint signed space_lower;
  longint signed space_upper;
  bit generated;

  if (!fast_legal_space_range(space_lower, space_upper)) begin
    `uvm_fatal("SHMINS_INDEXED_INVALID_SPACE",
               $sformatf("space=%0d wpid=%0d wpnum=%0d has no legal encoding range",
                         creq_space, creq_wpid, creq_wpnum))
  end
  decoded_offset_range(decode_lower, decode_upper);

  generated = 1'b0;
  for (int unsigned generation_attempt = 0;
       generation_attempt < MAX_GENERATION_RETRY && !generated;
       generation_attempt++) begin
    bit used_bytes[longint unsigned];
    longint signed base_lower;
    longint signed base_upper;
    bit all_elements_accepted;

    base_lower = 0;
    base_upper = (longint'(1) << MADDR_W) - 1;
    all_elements_accepted = 1'b1;
    foreach (elem_maddr[thread_idx, elem_idx]) begin
      elem_maddr[thread_idx][elem_idx] = 0;
      offs_elem[thread_idx][elem_idx] = 0;
    end

    for (int thread_idx = 0; thread_idx < THD_N && all_elements_accepted; thread_idx++) begin
      for (int elem_idx = 0;
           elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N;
           elem_idx++) begin
        longint signed target_lower;
        longint signed target_upper;
        bit accepted;

        if (!is_active_element(thread_idx, elem_idx)) begin
          continue;
        end
        target_lower = space_lower;
        if (target_lower < base_lower + decode_lower) begin
          target_lower = base_lower + decode_lower;
        end
        target_upper = space_upper;
        if (target_upper > base_upper + decode_upper + 1) begin
          target_upper = base_upper + decode_upper + 1;
        end

        accepted = 1'b0;
        for (int unsigned candidate_attempt = 0;
             candidate_attempt < MAX_CANDIDATE_RETRY;
             candidate_attempt++) begin
          longint signed candidate_base_lower;
          longint signed candidate_base_upper;
          longint signed candidate_maddr;

          if (!sample_aligned_value(target_lower, target_upper, data_byte_w(), candidate_maddr)) begin
            break;
          end
          candidate_base_lower = base_lower;
          candidate_base_upper = base_upper;
          if (legal_space_maddr_check(thread_idx, candidate_maddr) &&
              candidate_bytes_are_available(thread_idx, candidate_maddr, used_bytes) &&
              intersect_creq_base_range(candidate_maddr, candidate_base_lower, candidate_base_upper)) begin
            elem_maddr[thread_idx][elem_idx] = candidate_maddr;
            base_lower = candidate_base_lower;
            base_upper = candidate_base_upper;
            reserve_candidate_bytes(thread_idx, candidate_maddr, used_bytes);
            accepted = 1'b1;
            break;
          end
          generation_retry_count++;
          generation_reject_count++;
        end

        if (!accepted) begin
          all_elements_accepted = 1'b0;
          break;
        end
      end
    end

    if (!all_elements_accepted || !sample_creq_base(base_lower, base_upper)) begin
      generation_retry_count++;
      generation_reject_count++;
      continue;
    end

    generated = 1'b1;
    for (int thread_idx = 0; thread_idx < THD_N && generated; thread_idx++) begin
      for (int elem_idx = 0;
           elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N;
           elem_idx++) begin
        if (!is_active_element(thread_idx, elem_idx)) begin
          continue;
        end
        offs_elem[thread_idx][elem_idx] =
            elem_maddr[thread_idx][elem_idx] - longint'(creq_base[MADDR_W-1:0]);
        if (!check_offset_encodable(offs_elem[thread_idx][elem_idx])) begin
          generated = 1'b0;
          generation_retry_count++;
          generation_reject_count++;
          break;
        end
      end
    end
  end

  if (!generated) begin
    `uvm_fatal("SHMINS_INDEXED_RETRY_EXHAUSTED",
               $sformatf({"generation_retries=%0d candidate_retries=%0d rw=%0d space=%0d dtype=%0d ",
                          "atype_w=%0d atype_s=%0d atype_g=%0d inv_size=%0d wpid=%0d wpnum=%0d"},
                         MAX_GENERATION_RETRY, MAX_CANDIDATE_RETRY, creq_rw, creq_space, creq_dtype,
                         creq_atype_w, creq_atype_s, creq_atype_g, creq_inv_size, creq_wpid, creq_wpnum))
  end
endfunction : generate_address_fields

function bit shmins_indexed_sequence_item::candidate_bytes_are_available(
    int thread_idx,
    longint signed candidate_maddr,
    ref bit used_bytes[longint unsigned]);
  shmins_address_result_t mapped;

  if (!uniqueness_required()) begin
    return 1'b1;
  end
  mapped = map_maddr(thread_idx, candidate_maddr);
  if (!mapped.valid) begin
    return 1'b0;
  end
  for (int byte_lane = 0; byte_lane < data_byte_w(); byte_lane++) begin
    if (used_bytes.exists(physical_byte_key(mapped.bank_id, mapped.baddr + byte_lane))) begin
      return 1'b0;
    end
  end
  return 1'b1;
endfunction : candidate_bytes_are_available

function void shmins_indexed_sequence_item::reserve_candidate_bytes(
    int thread_idx,
    longint signed accepted_maddr,
    ref bit used_bytes[longint unsigned]);
  shmins_address_result_t mapped;

  if (!uniqueness_required()) begin
    return;
  end
  mapped = map_maddr(thread_idx, accepted_maddr);
  for (int byte_lane = 0; byte_lane < data_byte_w(); byte_lane++) begin
    used_bytes[physical_byte_key(mapped.bank_id, mapped.baddr + byte_lane)] = 1'b1;
  end
endfunction : reserve_candidate_bytes

function longint signed shmins_indexed_sequence_item::calculate_maddr(int thread_idx, int elem_idx);
  return longint'(creq_base[MADDR_W-1:0]) + decode_packed_offset(thread_idx, elem_idx);
endfunction : calculate_maddr

`endif // INC_SHMINS_INDEXED_SEQUENCE_ITEM_SVH
