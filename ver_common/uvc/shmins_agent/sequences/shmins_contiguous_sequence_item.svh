`ifndef INC_SHMINS_CONTIGUOUS_SEQUENCE_ITEM_SVH
`define INC_SHMINS_CONTIGUOUS_SEQUENCE_ITEM_SVH

//------------------------------------------------------------------------------
// @brief Generates one contiguous MADDR stream per active thread.
//
// The item supports LDST_S and LDST_V, which share the address formula
// base+offset[thread]+element*D. It samples a starting MADDR from the selected
// space's encoded domain and derives an encodable offset. It does not implement
// strided, indexed, or VTRANS-specific constraints.
//------------------------------------------------------------------------------
class shmins_contiguous_sequence_item extends shmins_sequence_item;
  localparam int unsigned MAX_CANDIDATE_RETRY = 4096;

  constraint c_contiguous_kind {
    creq_itype inside {LDST_S, LDST_V};
    creq_info == 4'h0;
  }

  // Keep the benchmark base in the selected encoded domain and, for BLK, in
  // the WARP group selected by creq_wpid. This is a stimulus restriction that
  // makes every randomized control combination constructively reachable.
  constraint c_contiguous_base_domain {
    if (creq_space == SPACE_LOC) {
      creq_base < WARP_STEP;
      if (creq_atype_s == ATYP_U) {
        creq_base <= WARP_STEP - VEC_BYTE_N;
      }
    } else if (creq_space == SPACE_WRP) {
      if (creq_inv_size <= 10) {
        creq_base < WARP_STEP * BANK_N;
        if (creq_atype_s == ATYP_U) {
          creq_base < WARP_STEP * BANK_N - 4096;
        }
      } else {
        creq_base < 16 * 1024 * BANK_N;
        if (creq_atype_s == ATYP_U) {
          creq_base < 16 * 1024 * BANK_N - 4096;
        }
      }
    } else if (creq_space == SPACE_BLK) {
      if (creq_inv_size <= 10) {
        creq_base >= (creq_wpid / creq_wpnum) *
                     WARP_STEP * BANK_N * creq_wpnum;
        creq_base < ((creq_wpid / creq_wpnum) + 1) *
                    WARP_STEP * BANK_N * creq_wpnum;
        if (creq_atype_s == ATYP_U) {
          creq_base < ((creq_wpid / creq_wpnum) + 1) *
                      WARP_STEP * BANK_N * creq_wpnum - 4096;
        }
      } else {
        creq_base >= (creq_wpid / creq_wpnum) *
                     16 * 1024 * BANK_N * creq_wpnum;
        creq_base < ((creq_wpid / creq_wpnum) + 1) *
                    16 * 1024 * BANK_N * creq_wpnum;
        if (creq_atype_s == ATYP_U) {
          creq_base < ((creq_wpid / creq_wpnum) + 1) *
                      16 * 1024 * BANK_N * creq_wpnum - 4096;
        }
      }
    }
  }

  extern function new(string name = "shmins_contiguous_sequence_item");

  extern protected function void generate_offsets();
  extern protected function longint signed calculate_maddr(
      int thread_idx,
      int elem_idx);

  extern protected function bit start_maddr_interval(
      int thread_idx,
      output longint signed interval_lower,
      output longint signed interval_upper);
  extern protected function longint signed sample_start_maddr(
      longint signed interval_lower,
      longint signed interval_upper);
  extern protected function longint signed candidate_maddr(
      int elem_idx,
      longint signed offset);
  extern protected function bit candidate_is_valid(
      int thread_idx,
      longint signed offset,
      ref bit used_bytes[longint unsigned]);
  extern protected function void commit_candidate(
      int thread_idx,
      longint signed offset,
      ref bit used_bytes[longint unsigned]);

  `uvm_object_utils(shmins_contiguous_sequence_item)
endclass : shmins_contiguous_sequence_item

function shmins_contiguous_sequence_item::new(
    string name = "shmins_contiguous_sequence_item");
  super.new(name);
endfunction : new

function void shmins_contiguous_sequence_item::generate_offsets();
  bit used_bytes[longint unsigned];

  for (int thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    bit has_active_element;
    bit accepted;
    longint signed offset;
    longint signed interval_lower;
    longint signed interval_upper;

    has_active_element = 1'b0;
    for (int elem_idx = 0;
         elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N;
         elem_idx++) begin
      has_active_element |= is_active_element(thread_idx, elem_idx);
    end
    if (!has_active_element) begin
      offs_elem[thread_idx][0] = 0;
      continue;
    end

    if (!start_maddr_interval(thread_idx, interval_lower, interval_upper)) begin
      `uvm_fatal("SHMINS_CONTIGUOUS_EMPTY_INTERVAL",
                 $sformatf({"thread=%0d rw=%0d space=%0d dtype=%0d ",
                            "atype_w=%0d atype_s=%0d atype_g=%0d base=0x%0h"},
                           thread_idx, creq_rw, creq_space, creq_dtype,
                           creq_atype_w, creq_atype_s, creq_atype_g, creq_base))
    end

    accepted = 1'b0;
    for (int unsigned retry = 0; retry < MAX_CANDIDATE_RETRY; retry++) begin
      longint signed start_maddr;

      start_maddr = sample_start_maddr(interval_lower, interval_upper);
      offset = start_maddr - longint'(creq_base[MADDR_W-1:0]);
      if (candidate_is_valid(thread_idx, offset, used_bytes)) begin
        accepted = 1'b1;
        break;
      end
      generation_retry_count++;
      generation_reject_count++;
    end

    if (!accepted) begin
      `uvm_fatal("SHMINS_CONTIGUOUS_RETRY_EXHAUSTED",
                 $sformatf({"thread=%0d retries=%0d rw=%0d itype=%0d space=%0d ",
                            "dtype=%0d atype_w=%0d atype_s=%0d atype_g=%0d base=0x%0h"},
                           thread_idx, MAX_CANDIDATE_RETRY, creq_rw, creq_itype,
                           creq_space, creq_dtype, creq_atype_w, creq_atype_s,
                           creq_atype_g, creq_base))
    end

    offs_elem[thread_idx][0] = offset;
    commit_candidate(thread_idx, offset, used_bytes);
  end
endfunction : generate_offsets

function bit shmins_contiguous_sequence_item::start_maddr_interval(
    int thread_idx,
    output longint signed interval_lower,
    output longint signed interval_upper);
  longint unsigned domain_lower;
  longint unsigned domain_upper;
  longint unsigned coded_bytes;
  longint signed offset_lower;
  longint signed offset_upper;
  longint signed base_address;
  int first_active;
  int last_active;
  int unsigned element_bytes;

  coded_bytes = coded_warp_bytes();
  element_bytes = data_byte_w();
  domain_lower = 0;
  case (creq_space)
    SPACE_LOC: domain_upper = WARP_STEP;
    SPACE_WRP: domain_upper = coded_bytes * BANK_N;
    SPACE_BLK: begin
      longint unsigned group_span;
      longint unsigned selected_group;

      group_span = coded_bytes * BANK_N * int'(creq_wpnum);
      selected_group = int'(creq_wpid) / int'(creq_wpnum);
      domain_lower = selected_group * group_span;
      domain_upper = domain_lower + group_span;
    end
    default: begin
      domain_lower = 0;
      domain_upper = element_bytes;
    end
  endcase

  first_active = -1;
  last_active = -1;
  for (int elem_idx = 0;
       elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N;
       elem_idx++) begin
    if (is_active_element(thread_idx, elem_idx)) begin
      if (first_active < 0) begin
        first_active = elem_idx;
      end
      last_active = elem_idx;
    end
  end
  if (first_active < 0) begin
    interval_lower = 0;
    interval_upper = 0;
    return 1'b0;
  end

  if (creq_atype_s == ATYP_S) begin
    offset_lower = -(longint'(1) << (offs_bit_w() - 1));
    offset_upper = (longint'(1) << (offs_bit_w() - 1)) - 1;
  end else begin
    offset_lower = 0;
    offset_upper = (longint'(1) << offs_bit_w()) - 1;
  end
  offset_lower = offset_lower * (longint'(1) << gran_shift());
  offset_upper = offset_upper * (longint'(1) << gran_shift());
  base_address = longint'(creq_base[MADDR_W-1:0]);

  interval_lower = longint'(domain_lower);
  if (interval_lower < base_address + offset_lower) begin
    interval_lower = base_address + offset_lower;
  end
  interval_upper = longint'(domain_upper) - element_bytes -
                   longint'(last_active) * element_bytes;
  if (interval_upper > base_address + offset_upper) begin
    interval_upper = base_address + offset_upper;
  end

  interval_lower = ((interval_lower + element_bytes - 1) / element_bytes) *
                   element_bytes;
  interval_upper = (interval_upper / element_bytes) * element_bytes;
  return interval_lower <= interval_upper;
endfunction : start_maddr_interval

function longint signed shmins_contiguous_sequence_item::sample_start_maddr(
    longint signed interval_lower,
    longint signed interval_upper);
  longint unsigned slot_count;
  longint unsigned selected_slot;
  int unsigned element_bytes;

  element_bytes = data_byte_w();
  slot_count = (interval_upper - interval_lower) / element_bytes + 1;
  selected_slot = $urandom_range(int'(slot_count - 1), 0);
  return interval_lower + longint'(selected_slot * element_bytes);
endfunction : sample_start_maddr

function longint signed shmins_contiguous_sequence_item::candidate_maddr(
    int elem_idx,
    longint signed offset);
  return longint'(creq_base[MADDR_W-1:0]) + offset +
         longint'(elem_idx) * data_byte_w();
endfunction : candidate_maddr

function bit shmins_contiguous_sequence_item::candidate_is_valid(
    int thread_idx,
    longint signed offset,
    ref bit used_bytes[longint unsigned]);
  bit candidate_bytes[longint unsigned];

  if (!check_offset_encodable(offset)) begin
    return 1'b0;
  end

  for (int elem_idx = 0;
       elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N;
       elem_idx++) begin
    longint signed maddr;
    shmins_address_result_t mapped;

    if (!is_active_element(thread_idx, elem_idx)) begin
      continue;
    end
    maddr = candidate_maddr(elem_idx, offset);
    mapped = map_maddr(thread_idx, maddr);
    if (!mapped.valid) begin
      return 1'b0;
    end

    if (creq_rw == SHM_V2M || m2v_unique_enable) begin
      for (int lane = 0; lane < data_byte_w(); lane++) begin
        longint unsigned key;

        key = physical_byte_key(mapped.bank_id, mapped.baddr + lane);
        if (used_bytes.exists(key) || candidate_bytes.exists(key)) begin
          return 1'b0;
        end
        candidate_bytes[key] = 1'b1;
      end
    end
  end
  return 1'b1;
endfunction : candidate_is_valid

function void shmins_contiguous_sequence_item::commit_candidate(
    int thread_idx,
    longint signed offset,
    ref bit used_bytes[longint unsigned]);
  if (creq_rw != SHM_V2M && !m2v_unique_enable) begin
    return;
  end

  for (int elem_idx = 0;
       elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N;
       elem_idx++) begin
    shmins_address_result_t mapped;

    if (!is_active_element(thread_idx, elem_idx)) begin
      continue;
    end
    mapped = map_maddr(thread_idx, candidate_maddr(elem_idx, offset));
    for (int lane = 0; lane < data_byte_w(); lane++) begin
      used_bytes[physical_byte_key(mapped.bank_id, mapped.baddr + lane)] = 1'b1;
    end
  end
endfunction : commit_candidate

function longint signed shmins_contiguous_sequence_item::calculate_maddr(
    int thread_idx,
    int elem_idx);
  return longint'(creq_base[MADDR_W-1:0]) +
         decode_packed_offset(thread_idx, 0) +
         longint'(elem_idx) * data_byte_w();
endfunction : calculate_maddr

`endif // INC_SHMINS_CONTIGUOUS_SEQUENCE_ITEM_SVH
