`ifndef INC_SHMINS_POST_RANDOMIZE_SEQUENCE_ITEM_SVH
`define INC_SHMINS_POST_RANDOMIZE_SEQUENCE_ITEM_SVH

typedef enum bit {
  SHM_V2M = 1'b0,
  SHM_M2V = 1'b1
} creq_rw_e;

typedef enum bit [1:0] {
  DTYP_32 = 2'h0,
  DTYP_16 = 2'h1,
  DTYP_8  = 2'h2
} creq_dtype_e;

typedef enum bit [1:0] {
  ATYP_32 = 2'h0,
  ATYP_16 = 2'h1
} creq_atype_w_e;

typedef enum bit {
  ATYP_U = 1'h0,
  ATYP_S = 1'h1
} creq_atype_s_e;

typedef enum bit {
  GAUTO_1B = 1'h0,
  GAUTO_DW = 1'h1
} creq_atype_g_e;

typedef enum bit [1:0] {
  LDST_S  = 2'h0,
  LDST_V  = 2'h1,
  LDSTE_S = 2'h2,
  LDSTE_V = 2'h3
} creq_itype_e;

typedef enum bit [1:0] {
  SPACE_LOC = 2'd0,
  SPACE_WRP = 2'd1,
  SPACE_BLK = 2'd2
} creq_space_e;

//------------------------------------------------------------------------------
// @brief Randomizes SHM input transactions with procedural offset repair.
//
// The class has the same public type name and transaction fields as the legacy
// solver-based item, but does not inherit from or include that implementation.
// It keeps the basic offset encoding and address constraints in the solver,
// then repairs active LDST_S, LDST_V, LDSTE_S, and LDSTE_V offsets with bounded
// rejection sampling. It does not drive a sequencer or DUT.
//------------------------------------------------------------------------------
class shmins_sequence_item extends uvm_sequence_item;
  parameter int unsigned WARP_ID_WIDTH_MAX = $clog2(4);
  parameter int unsigned ELEM_MAX_N = VEC_BYTE_N;
  parameter int unsigned VADDR_MAX = WARP_STEP - 1;

  // Bounds rejection sampling when randomized control fields have no reachable
  // legal candidate. Exhaustion is reported instead of looping forever.
  localparam int unsigned MAX_OFFS_RETRY = 10000;

  rand creq_rw_e      creq_rw       = SHM_V2M;
  rand creq_dtype_e   creq_dtype    = DTYP_32;
  rand creq_atype_w_e creq_atype_w  = ATYP_32;
  rand creq_atype_s_e creq_atype_s  = ATYP_U;
  rand creq_atype_g_e creq_atype_g  = GAUTO_1B;
  rand creq_itype_e   creq_itype    = LDST_V;
  rand logic [0:0]    creq_ack_en   = '0;
  rand logic [3:0]    creq_inv_size = '0;
  rand creq_space_e   creq_space    = SPACE_LOC;
  logic [19:0]        creq_typ      = '0;

  rand logic [3:0] creq_info = '0;
  rand logic [ID_W-1:0] creq_id = '0;
  rand logic [$clog2(WARP_N)-1:0] creq_wpid = '0;
  rand logic [$clog2(WARP_N+1)-1:0] creq_wpnum = '0;
  rand int wpid_width = '0;
  rand logic [BADDR_W-1:0] creq_vaddr = '0;
  rand logic [47:0] creq_base = '0;

  rand logic [3:0] creq_prio[THD_N] = '{THD_N{'0}};
  rand logic [7:0] creq_len[THD_N] = '{THD_N{'0}};
  rand byte elem_num[THD_N] = '{THD_N{'0}};
  rand logic [VEC_BYTE_N-1:0] creq_vmsk[THD_N] = '{THD_N{'0}};
  rand logic [THD_N-1:0] creq_tmsk = '0;
  logic [VEC_W-1:0] creq_offs_packed[THD_N];
  rand logic [VEC_BYTE_N-1:0][7:0] creq_vdat[THD_N] = '{THD_N{'0}};
  rand int delay_cycle = '0;

  // Enables procedural address uniqueness for M2V. V2M always enables it.
  bit m2v_unique_enable = 1'b0;

  // Final scaled offset values indexed by thread and encoded element slot.
  rand int offs_elem[THD_N][ELEM_MAX_N];

  // Maximum data-element count selected by dtype and offset encoding.
  rand int unsigned elem_cnt_max;

  // Rejection statistics from the latest post_randomize call.
  int unsigned post_randomize_retry_count;
  int unsigned duplicate_reject_count;
  int unsigned offs_width_reject_count;
  int unsigned addr_bound_reject_count;
  int unsigned address_hole_reject_count;
  int unsigned warp_group_reject_count;

  // Reuse the generated basic constraints while omitting solver collision
  // constraints. No-op declarations below preserve the benchmark control API.
  `define SHMINS_DISABLE_SOLVER_COLLISION_CONSTRAINTS
  `include "shmins_seq_item_constraints.svh"
  `undef SHMINS_DISABLE_SOLVER_COLLISION_CONSTRAINTS

  constraint c_ldste_v_loc_unique { 1; }
  constraint c_ldste_v_global_unique { 1; }
  constraint c_ldst_thread_range_no_overlap { 1; }

  constraint c_base_range_and_align {
    (creq_inv_size + 2) inside {[2:14]};
    creq_base inside {[0:(1 << MADDR_W)-1]};
    if (creq_dtype == DTYP_32) {
      creq_base[1:0] == 0;
    } else if (creq_dtype == DTYP_16) {
      creq_base[0] == 0;
    }
    wpid_width inside {[0:WARP_ID_WIDTH_MAX]};
    creq_wpnum == 1 << wpid_width;
    int'(creq_wpid) inside {[0:WARP_N-1]};
    creq_vaddr inside {[0:WARP_STEP-VEC_BYTE_N]};
    creq_tmsk != '0;
  }

  // LDSTE_S V2M element zero addresses collide across active threads in the
  // shared WRP and BLK spaces. Mask them before procedural uniqueness checks.
  constraint c_ldste_s_v2m_elem_zero_mask {
    if (creq_rw == SHM_V2M && creq_itype == LDSTE_S &&
        creq_space inside {SPACE_WRP, SPACE_BLK}) {
      foreach (creq_vmsk[t]) {
        creq_tmsk[t] -> creq_vmsk[t][0] == 1'b0;
      }
    }
  }

  // Unsigned offsets cannot bring an out-of-range base back into LOC or WRP.
  // Keep a 4 KiB candidate window below each encoded upper bound.
  constraint c_post_randomize_unsigned_base_reachable {
    if (creq_atype_s == ATYP_U && creq_space == SPACE_LOC) {
      creq_base < WARP_STEP - 4096;
    }
    if (creq_atype_s == ATYP_U && creq_space == SPACE_WRP) {
      creq_base < (1 << BADDR_W) - 4096;
    }
  }

  // Keep the benchmark's group-zero BLK profile away from the final encoded
  // hole so a legal forward offset remains easy to find.
  constraint c_post_randomize_blk_base_reachable {
    if (creq_space == SPACE_BLK && creq_atype_s == ATYP_U && creq_wpid == 0) {
      if (creq_inv_size <= 10) {
        creq_base < WARP_STEP * BANK_N * creq_wpnum - 4096;
      } else {
        creq_base < 16 * 1024 * BANK_N * creq_wpnum - 4096;
      }
    }
  }

  //----------------------------------------------------------------------------
  // @brief Constructs a procedural-offset transaction.
  //
  // @param name UVM object instance name.
  //----------------------------------------------------------------------------
  extern function new(string name = "shmins_sequence_item");

  //----------------------------------------------------------------------------
  // @brief Returns the packed RTL offset vector for one thread.
  //
  // @param thread_idx Thread index in the range 0 through THD_N-1.
  // @return Packed offset payload previously produced by post_randomize.
  //----------------------------------------------------------------------------
  extern function logic [VEC_W-1:0] creq_offs(int thread_idx);

  //----------------------------------------------------------------------------
  // @brief Replaces the packed RTL offset vector for one thread.
  //
  // @param thread_idx Thread index in the range 0 through THD_N-1.
  // @param offs_value Packed offset payload to store.
  //----------------------------------------------------------------------------
  extern function void set_creq_offs(
      int thread_idx,
      logic [VEC_W-1:0] offs_value);

  //----------------------------------------------------------------------------
  // @brief Returns the byte width of one data element.
  //
  // @return 4, 2, or 1 for DTYP_32, DTYP_16, or DTYP_8 respectively.
  //----------------------------------------------------------------------------
  extern function int unsigned data_byte_w();

  //----------------------------------------------------------------------------
  // @brief Returns the bit width of one data element.
  //
  // @return The selected data width in bits.
  //----------------------------------------------------------------------------
  extern function int unsigned data_bit_w();

  //----------------------------------------------------------------------------
  // @brief Returns the maximum data-element count in one vector.
  //
  // @return VEC_W divided by the selected data-element width.
  //----------------------------------------------------------------------------
  extern function int unsigned data_elem_max();

  //----------------------------------------------------------------------------
  // @brief Returns the encoded offset-element width.
  //
  // @return 32 or 16 according to creq_atype_w.
  //----------------------------------------------------------------------------
  extern function int unsigned offs_bit_w();

  //----------------------------------------------------------------------------
  // @brief Returns the number of encoded offset slots in one vector.
  //
  // @return VEC_W divided by the selected offset width.
  //----------------------------------------------------------------------------
  extern function int unsigned offs_elem_max();

  //----------------------------------------------------------------------------
  // @brief Returns the granularity scaling shift.
  //
  // @return Zero for byte granularity or the dtype shift for data granularity.
  //----------------------------------------------------------------------------
  extern function int unsigned gran_shift();

  //----------------------------------------------------------------------------
  // @brief Returns the dtype alignment mask for a final scaled offset.
  //
  // @return A mask whose set bits must be zero in a legal offset.
  //----------------------------------------------------------------------------
  extern function int unsigned align_mask();

  //----------------------------------------------------------------------------
  // @brief Returns the encoded MADDR upper bound for the selected space.
  //
  // @return Exclusive upper bound before address-hole filtering.
  //----------------------------------------------------------------------------
  extern function int unsigned addr_max();

  //----------------------------------------------------------------------------
  // @brief Returns the maximum element count for the selected instruction.
  //
  // @return The smaller data/offset capacity for LDSTE_V, otherwise data capacity.
  //----------------------------------------------------------------------------
  extern function int unsigned max_elem_cnt();

  //----------------------------------------------------------------------------
  // @brief Returns the active length-derived element count for one thread.
  //
  // @param thread_idx Thread whose byte length is converted to elements.
  // @return Element count derived from creq_len and creq_dtype.
  //----------------------------------------------------------------------------
  extern function int unsigned thread_elem_cnt(int thread_idx);

  //----------------------------------------------------------------------------
  // @brief Computes one final MADDR from the current offset array.
  //
  // @param thread_idx Thread containing the element.
  // @param elem_idx Element index within the thread.
  // @return Signed byte address before address-space mapping.
  //----------------------------------------------------------------------------
  extern function int phys_addr(int thread_idx, int elem_idx);

  //----------------------------------------------------------------------------
  // @brief Repairs active offsets and packs the RTL offset payload.
  //
  // @post Every active address passes width, bound, hole, WARP-group, and
  //       enabled uniqueness checks.
  //----------------------------------------------------------------------------
  extern function void post_randomize();

  //----------------------------------------------------------------------------
  // @brief Checks offset encoding, granularity, and dtype alignment.
  //
  // @param candidate Final scaled offset value to validate.
  // @return 1 when the selected ATYP fields can encode candidate.
  //----------------------------------------------------------------------------
  extern function bit check_offs_width(int candidate);

  //----------------------------------------------------------------------------
  // @brief Checks the address bound for one candidate-generated element.
  //
  // @param thread_idx Thread containing the candidate.
  // @param elem_idx Active element affected by the candidate.
  // @param candidate Offset, stride, or start offset according to creq_itype.
  // @return 1 when the resulting address is inside the encoded address range.
  //----------------------------------------------------------------------------
  extern function bit check_addr_bound(
      int thread_idx,
      int elem_idx,
      int candidate);

  extern function void rtl_to_item();
  extern function void item_to_rtl();
  extern function bit compare_item(shmins_sequence_item shmins_trans);
  extern function void do_copy(uvm_object rhs);

  //----------------------------------------------------------------------------
  // @brief Repairs all active offset generation units for the selected itype.
  //----------------------------------------------------------------------------
  extern protected function void repair_active_offsets();

  //----------------------------------------------------------------------------
  // @brief Packs final scaled offsets into the RTL raw offset representation.
  //----------------------------------------------------------------------------
  extern protected function void pack_offsets();

  //----------------------------------------------------------------------------
  // @brief Returns whether an element produces an access.
  //
  // @param thread_idx Thread containing the element.
  // @param elem_idx Element index within the thread.
  // @return 1 only when tmsk, length, and vmsk all enable the element.
  //----------------------------------------------------------------------------
  extern protected function bit is_active_element(
      int thread_idx,
      int elem_idx);

  //----------------------------------------------------------------------------
  // @brief Returns whether uniqueness is enabled for the current transaction.
  //
  // @return 1 for V2M, or for M2V when m2v_unique_enable is set and the
  //         applicable diagnostic constraint remains enabled.
  //----------------------------------------------------------------------------
  extern protected function bit uniqueness_required();

  //----------------------------------------------------------------------------
  // @brief Checks one offset generation unit against all affected elements.
  //
  // @param thread_idx Thread receiving the candidate.
  // @param elem_idx LDSTE_V element index; ignored by other itypes.
  // @param candidate Offset, stride, or start offset under test.
  // @param used_addresses Addresses accepted for earlier generation units.
  // @return 1 when every affected active address is legal.
  //----------------------------------------------------------------------------
  extern protected function bit check_candidate(
      int thread_idx,
      int elem_idx,
      int candidate,
      ref bit used_addresses[longint]);

  //----------------------------------------------------------------------------
  // @brief Adds a successful candidate's active addresses to the used set.
  //
  // @param thread_idx Thread owning the candidate.
  // @param elem_idx LDSTE_V element index; ignored by other itypes.
  // @param candidate Accepted offset, stride, or start offset.
  // @param used_addresses Set updated when uniqueness is enabled.
  //----------------------------------------------------------------------------
  extern protected function void commit_candidate_addresses(
      int thread_idx,
      int elem_idx,
      int candidate,
      ref bit used_addresses[longint]);

  //----------------------------------------------------------------------------
  // @brief Generates one offset from the selected ATYP encoding domain.
  //
  // @return A final scaled and dtype-aligned candidate.
  //----------------------------------------------------------------------------
  extern protected function int generate_offs_candidate();

  //----------------------------------------------------------------------------
  // @brief Computes an address using a replacement candidate.
  //
  // @param thread_idx Thread containing the element.
  // @param elem_idx Active element affected by the candidate.
  // @param candidate Offset, stride, or start offset under test.
  // @return Signed candidate-generated MADDR.
  //----------------------------------------------------------------------------
  extern protected function longint signed candidate_address(
      int thread_idx,
      int elem_idx,
      int candidate);

  //----------------------------------------------------------------------------
  // @brief Converts an address to the uniqueness key for its address space.
  //
  // @param thread_idx Thread producing the address.
  // @param address Candidate-generated MADDR.
  // @return A per-thread key for LOC or a global key for WRP/BLK.
  //----------------------------------------------------------------------------
  extern protected function longint address_key(
      int thread_idx,
      longint signed address);

  //----------------------------------------------------------------------------
  // @brief Checks that one MADDR does not map into a 12-to-16 KiB hole.
  //
  // @param address Candidate-generated MADDR.
  // @return 1 when the mapped local offset is below WARP_STEP.
  //----------------------------------------------------------------------------
  extern protected function bit check_address_hole(longint signed address);

  //----------------------------------------------------------------------------
  // @brief Checks the SPACE_BLK WARP-group assertion for one MADDR.
  //
  // @param address Candidate-generated MADDR.
  // @return 1 when the mapped WARP belongs to the creq_wpid group.
  //----------------------------------------------------------------------------
  extern protected function bit check_warp_group(longint signed address);

  `uvm_object_utils_begin(shmins_sequence_item)
    `uvm_field_enum(creq_rw_e, creq_rw, UVM_DEFAULT)
    `uvm_field_enum(creq_dtype_e, creq_dtype, UVM_DEFAULT)
    `uvm_field_enum(creq_atype_w_e, creq_atype_w, UVM_DEFAULT)
    `uvm_field_enum(creq_atype_s_e, creq_atype_s, UVM_DEFAULT)
    `uvm_field_enum(creq_atype_g_e, creq_atype_g, UVM_DEFAULT)
    `uvm_field_enum(creq_itype_e, creq_itype, UVM_DEFAULT)
    `uvm_field_enum(creq_space_e, creq_space, UVM_DEFAULT)
    `uvm_field_int(creq_info, UVM_DEFAULT)
    `uvm_field_int(creq_ack_en, UVM_DEFAULT)
    `uvm_field_int(creq_inv_size, UVM_DEFAULT)
    `uvm_field_int(creq_typ, UVM_DEFAULT)
    `uvm_field_int(creq_id, UVM_DEFAULT)
    `uvm_field_int(creq_wpid, UVM_DEFAULT)
    `uvm_field_int(creq_wpnum, UVM_DEFAULT)
    `uvm_field_int(creq_vaddr, UVM_DEFAULT)
    `uvm_field_int(creq_base, UVM_DEFAULT)
    `uvm_field_int(creq_tmsk, UVM_DEFAULT)
    `uvm_field_int(delay_cycle, UVM_DEFAULT)
    `uvm_field_int(m2v_unique_enable, UVM_DEFAULT)
    `uvm_field_sarray_int(creq_prio, UVM_DEFAULT)
    `uvm_field_sarray_int(creq_len, UVM_DEFAULT)
    `uvm_field_sarray_int(creq_vmsk, UVM_DEFAULT)
    `uvm_field_sarray_int(creq_offs_packed, UVM_DEFAULT)
    `uvm_field_sarray_int(creq_vdat, UVM_DEFAULT)
  `uvm_object_utils_end
endclass : shmins_sequence_item

function shmins_sequence_item::new(string name = "shmins_sequence_item");
  super.new(name);
endfunction : new

function logic [VEC_W-1:0] shmins_sequence_item::creq_offs(int thread_idx);
  return creq_offs_packed[thread_idx];
endfunction : creq_offs

function void shmins_sequence_item::set_creq_offs(
    int thread_idx,
    logic [VEC_W-1:0] offs_value);
  creq_offs_packed[thread_idx] = offs_value;
endfunction : set_creq_offs

function int unsigned shmins_sequence_item::data_byte_w();
  case (creq_dtype)
    DTYP_32: return 4;
    DTYP_16: return 2;
    DTYP_8:  return 1;
    default: return 4;
  endcase
endfunction : data_byte_w

function int unsigned shmins_sequence_item::data_bit_w();
  return data_byte_w() * 8;
endfunction : data_bit_w

function int unsigned shmins_sequence_item::data_elem_max();
  return $unsigned(VEC_W) / data_bit_w();
endfunction : data_elem_max

function int unsigned shmins_sequence_item::offs_bit_w();
  case (creq_atype_w)
    ATYP_32: return 32;
    ATYP_16: return 16;
    default: return 32;
  endcase
endfunction : offs_bit_w

function int unsigned shmins_sequence_item::offs_elem_max();
  return $unsigned(VEC_W) / offs_bit_w();
endfunction : offs_elem_max

function int unsigned shmins_sequence_item::gran_shift();
  if (creq_atype_g == GAUTO_1B) begin
    return 0;
  end
  case (creq_dtype)
    DTYP_32: return 2;
    DTYP_16: return 1;
    DTYP_8:  return 0;
    default: return 0;
  endcase
endfunction : gran_shift

function int unsigned shmins_sequence_item::align_mask();
  case (creq_dtype)
    DTYP_32: return 32'h3;
    DTYP_16: return 32'h1;
    DTYP_8:  return 32'h0;
    default: return 32'h0;
  endcase
endfunction : align_mask

function int unsigned shmins_sequence_item::addr_max();
  case (creq_space)
    SPACE_LOC: return WARP_STEP;
    SPACE_WRP: return 1 << BADDR_W;
    SPACE_BLK: return 1 << MADDR_W;
    default:   return WARP_STEP;
  endcase
endfunction : addr_max

function int unsigned shmins_sequence_item::max_elem_cnt();
  if (creq_itype == LDSTE_V) begin
    return data_elem_max() < offs_elem_max() ? data_elem_max() : offs_elem_max();
  end
  return data_elem_max();
endfunction : max_elem_cnt

function automatic int unsigned shmins_sequence_item::thread_elem_cnt(int thread_idx);
  case (creq_dtype)
    DTYP_32: return int'(creq_len[thread_idx]) / 4;
    DTYP_16: return int'(creq_len[thread_idx]) / 2;
    DTYP_8:  return int'(creq_len[thread_idx]);
    default: return 0;
  endcase
endfunction : thread_elem_cnt

function int shmins_sequence_item::phys_addr(int thread_idx, int elem_idx);
  return int'(candidate_address(thread_idx, elem_idx, offs_elem[thread_idx][
      creq_itype == LDSTE_V ? elem_idx : 0]));
endfunction : phys_addr

function void shmins_sequence_item::post_randomize();
  post_randomize_retry_count = 0;
  duplicate_reject_count = 0;
  offs_width_reject_count = 0;
  addr_bound_reject_count = 0;
  address_hole_reject_count = 0;
  warp_group_reject_count = 0;

  repair_active_offsets();
  pack_offsets();

  `uvm_info("SHMINS_POST_RANDOMIZE_STATS",
            $sformatf({"itype=%0d space=%0d rw=%0d retries=%0d duplicate=%0d ",
                       "offs_width=%0d addr_bound=%0d address_hole=%0d warp_group=%0d"},
                      creq_itype, creq_space, creq_rw, post_randomize_retry_count,
                      duplicate_reject_count, offs_width_reject_count,
                      addr_bound_reject_count, address_hole_reject_count,
                      warp_group_reject_count),
            UVM_HIGH)
endfunction : post_randomize

function bit shmins_sequence_item::check_offs_width(int candidate);
  longint signed minimum;
  longint signed maximum;
  int unsigned shift;

  shift = gran_shift();
  minimum = -(longint'(1) << 31);
  maximum = (longint'(1) << 31) - 1;

  case (creq_atype_w)
    ATYP_16: begin
      if (creq_atype_s == ATYP_S) begin
        minimum = -(longint'(1) << 15) << shift;
        maximum = ((longint'(1) << 15) - 1) << shift;
      end else begin
        minimum = 0;
        maximum = ((longint'(1) << 16) - 1) << shift;
      end
    end
    ATYP_32: begin
      if (creq_atype_s == ATYP_U) begin
        minimum = 0;
      end
    end
    default: return 1'b0;
  endcase

  if (longint'(candidate) < minimum || longint'(candidate) > maximum) begin
    return 1'b0;
  end
  if (shift != 0 && candidate % (1 << shift) != 0) begin
    return 1'b0;
  end
  if ((candidate & int'(align_mask())) != 0) begin
    return 1'b0;
  end
  return 1'b1;
endfunction : check_offs_width

function bit shmins_sequence_item::check_addr_bound(
    int thread_idx,
    int elem_idx,
    int candidate);
  longint signed address;
  longint signed upper_bound;

  if (thread_idx < 0 || thread_idx >= THD_N ||
      elem_idx < 0 || elem_idx >= ELEM_MAX_N) begin
    return 1'b0;
  end

  address = candidate_address(thread_idx, elem_idx, candidate);
  upper_bound = longint'(addr_max());
  return address >= 0 && address < upper_bound;
endfunction : check_addr_bound

function void shmins_sequence_item::repair_active_offsets();
  bit used_addresses[longint];

  for (int thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    int unsigned element_count;

    element_count = thread_elem_cnt(thread_idx);
    if (creq_itype == LDSTE_V) begin
      for (int elem_idx = 0;
           elem_idx < element_count && elem_idx < ELEM_MAX_N;
           elem_idx++) begin
        int candidate;
        int unsigned retry_count;

        if (!is_active_element(thread_idx, elem_idx)) begin
          continue;
        end

        candidate = offs_elem[thread_idx][elem_idx];
        retry_count = 0;
        while (!check_candidate(thread_idx, elem_idx, candidate, used_addresses)) begin
          if (retry_count >= MAX_OFFS_RETRY) begin
            `uvm_fatal("SHMINS_POST_RANDOMIZE_RETRY_EXHAUSTED",
                       $sformatf({"unable to repair thread=%0d elem=%0d after %0d retries: ",
                                  "rw=%0d itype=%0d space=%0d base=0x%0h"},
                                 thread_idx, elem_idx, MAX_OFFS_RETRY, creq_rw,
                                 creq_itype, creq_space, creq_base))
          end
          candidate = generate_offs_candidate();
          retry_count++;
          post_randomize_retry_count++;
        end
        offs_elem[thread_idx][elem_idx] = candidate;
        commit_candidate_addresses(thread_idx, elem_idx, candidate, used_addresses);
      end
    end else begin
      bit has_active_element;
      int candidate;
      int unsigned retry_count;

      has_active_element = 1'b0;
      for (int elem_idx = 0;
           elem_idx < element_count && elem_idx < ELEM_MAX_N;
           elem_idx++) begin
        has_active_element |= is_active_element(thread_idx, elem_idx);
      end
      if (!has_active_element) begin
        continue;
      end

      candidate = offs_elem[thread_idx][0];
      retry_count = 0;
      while (!check_candidate(thread_idx, -1, candidate, used_addresses)) begin
        if (retry_count >= MAX_OFFS_RETRY) begin
          `uvm_fatal("SHMINS_POST_RANDOMIZE_RETRY_EXHAUSTED",
                     $sformatf({"unable to repair thread=%0d after %0d retries: ",
                                "rw=%0d itype=%0d space=%0d base=0x%0h"},
                               thread_idx, MAX_OFFS_RETRY, creq_rw,
                               creq_itype, creq_space, creq_base))
        end
        candidate = generate_offs_candidate();
        retry_count++;
        post_randomize_retry_count++;
      end
      offs_elem[thread_idx][0] = candidate;
      commit_candidate_addresses(thread_idx, -1, candidate, used_addresses);
    end
  end
endfunction : repair_active_offsets

function void shmins_sequence_item::pack_offsets();
  int unsigned offset_width;
  int unsigned offset_count;
  int unsigned shift;

  offset_width = offs_bit_w();
  offset_count = offs_elem_max();
  shift = gran_shift();

  for (int thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    int element_count;

    element_count = int'(thread_elem_cnt(thread_idx));
    creq_offs_packed[thread_idx] = '0;
    for (int unsigned elem_idx = 0;
         elem_idx < offset_count && elem_idx < ELEM_MAX_N;
         elem_idx++) begin
      int raw_extended;
      bit [31:0] raw_bits;

      if (elem_idx < element_count) begin
        raw_extended = offs_elem[thread_idx][elem_idx] >>> shift;
      end else begin
        raw_extended = 0;
      end
      raw_bits = $unsigned(raw_extended);

      case (offset_width)
        32: creq_offs_packed[thread_idx][elem_idx*32 +: 32] = raw_bits[31:0];
        16: creq_offs_packed[thread_idx][elem_idx*16 +: 16] = raw_bits[15:0];
        default: ;
      endcase
    end
  end
endfunction : pack_offsets

function bit shmins_sequence_item::is_active_element(
    int thread_idx,
    int elem_idx);
  if (thread_idx < 0 || thread_idx >= THD_N ||
      elem_idx < 0 || elem_idx >= ELEM_MAX_N) begin
    return 1'b0;
  end
  return creq_tmsk[thread_idx] === 1'b1 &&
         elem_idx < thread_elem_cnt(thread_idx) &&
         creq_vmsk[thread_idx][elem_idx] === 1'b1;
endfunction : is_active_element

function bit shmins_sequence_item::uniqueness_required();
  if (creq_rw != SHM_V2M && !m2v_unique_enable) begin
    return 1'b0;
  end

  case (creq_itype)
    LDST_S, LDST_V:
      return c_ldst_thread_range_no_overlap.constraint_mode() != 0;
    LDSTE_S, LDSTE_V: begin
      if (creq_space == SPACE_LOC) begin
        return c_ldste_v_loc_unique.constraint_mode() != 0;
      end
      return c_ldste_v_global_unique.constraint_mode() != 0;
    end
    default: return 1'b0;
  endcase
endfunction : uniqueness_required

function bit shmins_sequence_item::check_candidate(
    int thread_idx,
    int elem_idx,
    int candidate,
    ref bit used_addresses[longint]);
  bit candidate_addresses[longint];
  int first_elem;
  int last_elem;

  if (!check_offs_width(candidate)) begin
    offs_width_reject_count++;
    return 1'b0;
  end

  if (creq_itype == LDSTE_V) begin
    first_elem = elem_idx;
    last_elem = elem_idx;
  end else begin
    first_elem = 0;
    last_elem = int'(thread_elem_cnt(thread_idx)) - 1;
  end

  for (int active_elem = first_elem;
       active_elem <= last_elem && active_elem < ELEM_MAX_N;
       active_elem++) begin
    longint signed address;
    longint key;

    if (!is_active_element(thread_idx, active_elem)) begin
      continue;
    end
    if (c_addr_bound.constraint_mode() != 0 &&
        !check_addr_bound(thread_idx, active_elem, candidate)) begin
      addr_bound_reject_count++;
      return 1'b0;
    end

    address = candidate_address(thread_idx, active_elem, candidate);
    if (!check_address_hole(address)) begin
      address_hole_reject_count++;
      return 1'b0;
    end
    if (!check_warp_group(address)) begin
      warp_group_reject_count++;
      return 1'b0;
    end

    // LDSTE_S element zero is independent of the stride. M2V may legally read
    // that shared address even when optional offset uniqueness is enabled.
    if (uniqueness_required() &&
        !(creq_rw == SHM_M2V && creq_itype == LDSTE_S && active_elem == 0)) begin
      key = address_key(thread_idx, address);
      if (used_addresses.exists(key) || candidate_addresses.exists(key)) begin
        duplicate_reject_count++;
        return 1'b0;
      end
      candidate_addresses[key] = 1'b1;
    end
  end
  return 1'b1;
endfunction : check_candidate

function void shmins_sequence_item::commit_candidate_addresses(
    int thread_idx,
    int elem_idx,
    int candidate,
    ref bit used_addresses[longint]);
  int first_elem;
  int last_elem;

  if (!uniqueness_required()) begin
    return;
  end
  if (creq_itype == LDSTE_V) begin
    first_elem = elem_idx;
    last_elem = elem_idx;
  end else begin
    first_elem = 0;
    last_elem = int'(thread_elem_cnt(thread_idx)) - 1;
  end

  for (int active_elem = first_elem;
       active_elem <= last_elem && active_elem < ELEM_MAX_N;
       active_elem++) begin
    longint signed address;

    if (!is_active_element(thread_idx, active_elem)) begin
      continue;
    end
    if (!(creq_rw == SHM_M2V && creq_itype == LDSTE_S && active_elem == 0)) begin
      address = candidate_address(thread_idx, active_elem, candidate);
      used_addresses[address_key(thread_idx, address)] = 1'b1;
    end
  end
endfunction : commit_candidate_addresses

function int shmins_sequence_item::generate_offs_candidate();
  bit [31:0] raw_bits;
  int raw_value;
  int candidate;
  int unsigned shift;

  raw_bits = $urandom();
  shift = gran_shift();
  case (creq_atype_w)
    ATYP_16: begin
      if (creq_atype_s == ATYP_S) begin
        raw_value = int'($signed(raw_bits[15:0]));
      end else begin
        raw_value = int'($unsigned(raw_bits[15:0]));
      end
    end
    ATYP_32: begin
      if (creq_atype_s == ATYP_S) begin
        if (shift == 0) begin
          raw_value = int'($signed(raw_bits));
        end else begin
          raw_value = int'($signed(raw_bits << shift) >>> shift);
        end
      end else begin
        raw_bits &= 32'h7fff_ffff >> shift;
        raw_value = int'($unsigned(raw_bits));
      end
    end
    default: raw_value = 0;
  endcase

  candidate = raw_value <<< shift;
  candidate &= ~int'(align_mask());
  return candidate;
endfunction : generate_offs_candidate

function longint signed shmins_sequence_item::candidate_address(
    int thread_idx,
    int elem_idx,
    int candidate);
  longint signed base_address;

  base_address = longint'(creq_base[MADDR_W-1:0]);
  case (creq_itype)
    LDST_S, LDST_V:
      return base_address + longint'(candidate) +
          longint'(elem_idx) * longint'(data_byte_w());
    LDSTE_S:
      return base_address + longint'(elem_idx) * longint'(candidate);
    LDSTE_V:
      return base_address + longint'(candidate);
    default:
      return -1;
  endcase
endfunction : candidate_address

function longint shmins_sequence_item::address_key(
    int thread_idx,
    longint signed address);
  if (creq_space == SPACE_LOC) begin
    return (longint'(thread_idx) << 32) | (address & 64'h0000_0000_ffff_ffff);
  end
  return longint'(address);
endfunction : address_key

function bit shmins_sequence_item::check_address_hole(longint signed address);
  longint signed group_address;
  longint signed group_span;
  longint signed interleave_bytes;
  longint signed interleave_index;
  longint signed interleave_offset;
  longint signed local_offset;
  longint signed coded_warp_bytes;

  if (address < 0) begin
    return 1'b0;
  end

  interleave_bytes = longint'(1) << (int'(creq_inv_size) + 2);
  coded_warp_bytes = interleave_bytes <= 4096 ? WARP_STEP : 16 * 1024;
  interleave_offset = address % interleave_bytes;

  case (creq_space)
    SPACE_LOC: local_offset = address;
    SPACE_WRP: begin
      interleave_index = address / (interleave_bytes * BANK_N);
      local_offset = interleave_index * interleave_bytes + interleave_offset;
    end
    SPACE_BLK: begin
      if (creq_wpnum == 0) begin
        return 1'b0;
      end
      group_span = coded_warp_bytes * BANK_N * int'(creq_wpnum);
      group_address = address % group_span;
      interleave_index = group_address /
          (interleave_bytes * BANK_N * int'(creq_wpnum));
      local_offset = interleave_index * interleave_bytes + interleave_offset;
    end
    default: return 1'b0;
  endcase

  return local_offset >= 0 && local_offset < WARP_STEP;
endfunction : check_address_hole

function bit shmins_sequence_item::check_warp_group(longint signed address);
  longint signed coded_warp_bytes;
  longint signed group_address;
  longint signed group_span;
  longint signed interleave_bytes;
  longint signed warp_group;
  longint signed warp_index;
  longint signed warp_offset;
  int unsigned warps_per_group;

  if (creq_space != SPACE_BLK) begin
    return 1'b1;
  end
  if (creq_wpnum == 0 || address < 0) begin
    return 1'b0;
  end

  warps_per_group = int'(creq_wpnum);
  interleave_bytes = longint'(1) << (int'(creq_inv_size) + 2);
  coded_warp_bytes = interleave_bytes <= 4096 ? WARP_STEP : 16 * 1024;
  group_span = coded_warp_bytes * BANK_N * warps_per_group;
  warp_group = address / group_span;
  group_address = address % group_span;
  warp_offset = (group_address / (interleave_bytes * BANK_N)) % warps_per_group;
  warp_index = warp_group * warps_per_group + warp_offset;

  return warp_index >= 0 &&
         warp_index < WARP_N &&
         int'(creq_wpid) / warps_per_group == warp_index / warps_per_group;
endfunction : check_warp_group

function void shmins_sequence_item::do_copy(uvm_object rhs);
  shmins_sequence_item rhs_item;

  super.do_copy(rhs);
  if (!$cast(rhs_item, rhs)) begin
    `uvm_fatal(get_type_name(), "Cast of rhs object failed")
  end

  creq_rw = rhs_item.creq_rw;
  creq_dtype = rhs_item.creq_dtype;
  creq_atype_w = rhs_item.creq_atype_w;
  creq_atype_s = rhs_item.creq_atype_s;
  creq_atype_g = rhs_item.creq_atype_g;
  creq_itype = rhs_item.creq_itype;
  creq_ack_en = rhs_item.creq_ack_en;
  creq_inv_size = rhs_item.creq_inv_size;
  creq_space = rhs_item.creq_space;
  creq_typ = rhs_item.creq_typ;
  creq_info = rhs_item.creq_info;
  creq_id = rhs_item.creq_id;
  creq_wpid = rhs_item.creq_wpid;
  creq_wpnum = rhs_item.creq_wpnum;
  wpid_width = rhs_item.wpid_width;
  creq_vaddr = rhs_item.creq_vaddr;
  creq_base = rhs_item.creq_base;
  creq_tmsk = rhs_item.creq_tmsk;
  delay_cycle = rhs_item.delay_cycle;
  m2v_unique_enable = rhs_item.m2v_unique_enable;
  elem_cnt_max = rhs_item.elem_cnt_max;

  foreach (creq_prio[index]) creq_prio[index] = rhs_item.creq_prio[index];
  foreach (creq_len[index]) creq_len[index] = rhs_item.creq_len[index];
  foreach (elem_num[index]) elem_num[index] = rhs_item.elem_num[index];
  foreach (creq_vmsk[index]) creq_vmsk[index] = rhs_item.creq_vmsk[index];
  foreach (creq_offs_packed[index]) begin
    creq_offs_packed[index] = rhs_item.creq_offs_packed[index];
  end
  foreach (creq_vdat[index]) creq_vdat[index] = rhs_item.creq_vdat[index];
  foreach (offs_elem[thread_idx, elem_idx]) begin
    offs_elem[thread_idx][elem_idx] = rhs_item.offs_elem[thread_idx][elem_idx];
  end
endfunction : do_copy

function void shmins_sequence_item::rtl_to_item();
  {creq_info, creq_space, creq_inv_size, creq_ack_en, creq_itype,
   creq_atype_g, creq_atype_s, creq_atype_w, creq_dtype, creq_rw} = creq_typ;
endfunction : rtl_to_item

function void shmins_sequence_item::item_to_rtl();
  creq_typ = {creq_info, creq_space, creq_inv_size, creq_ack_en, creq_itype,
              creq_atype_g, creq_atype_s, creq_atype_w, creq_dtype, creq_rw};
endfunction : item_to_rtl

function bit shmins_sequence_item::compare_item(shmins_sequence_item shmins_trans);
  return compare(shmins_trans);
endfunction : compare_item

`endif // INC_SHMINS_POST_RANDOMIZE_SEQUENCE_ITEM_SVH
