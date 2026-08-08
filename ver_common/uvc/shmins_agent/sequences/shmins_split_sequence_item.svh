`ifndef INC_SHMINS_SPLIT_SEQUENCE_ITEM_SVH
`define INC_SHMINS_SPLIT_SEQUENCE_ITEM_SVH

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
  ATYP_U = 1'b0,
  ATYP_S = 1'b1
} creq_atype_s_e;

typedef enum bit {
  GAUTO_1B = 1'b0,
  GAUTO_DW = 1'b1
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
// @brief Holds common SHM creq fields and validates generated transactions.
//
// Derived items generate offsets for one MADDR topology. This base class owns
// field encoding, active-element selection, address-space mapping, packed
// offset conversion, and final validation. It does not select a topology and
// therefore rejects direct randomization.
//------------------------------------------------------------------------------
class shmins_sequence_item extends uvm_sequence_item;
  parameter int unsigned ELEM_MAX_N = VEC_BYTE_N;

  typedef struct {
    bit                    valid;
    int unsigned           bank_id;
    bit [BADDR_W-1:0]      baddr;
    longint unsigned       local_offset;
    int unsigned           warp_index;
  } shmins_address_result_t;

  rand creq_rw_e      creq_rw       = SHM_V2M;
  rand creq_dtype_e   creq_dtype    = DTYP_32;
  rand creq_atype_w_e creq_atype_w  = ATYP_32;
  rand creq_atype_s_e creq_atype_s  = ATYP_U;
  rand creq_atype_g_e creq_atype_g  = GAUTO_1B;
  rand creq_itype_e   creq_itype    = LDST_V;
  rand logic          creq_ack_en   = 1'b0;
  rand logic [3:0]    creq_inv_size = '0;
  rand creq_space_e   creq_space    = SPACE_LOC;
  logic [19:0]        creq_typ      = '0;

  rand logic [3:0] creq_info = '0;
  rand logic [ID_W-1:0] creq_id = '0;
  rand logic [$clog2(WARP_N)-1:0] creq_wpid = '0;
  rand logic [$clog2(WARP_N+1)-1:0] creq_wpnum = 1;
  int wpid_width;
  rand logic [VADDR_W-1:0] creq_vaddr = '0;
  rand logic [47:0] creq_base = '0;

  rand logic [PRIO_W-1:0] creq_prio[THD_N] = '{THD_N{'0}};
  rand logic [7:0] creq_len[THD_N] = '{THD_N{'0}};
  rand byte unsigned elem_num[THD_N] = '{THD_N{'0}};
  rand logic [VEC_BYTE_N-1:0] creq_vmsk[THD_N] = '{THD_N{'0}};
  rand logic [THD_N-1:0] creq_tmsk = '0;
  logic [VEC_W-1:0] creq_offs_packed[THD_N];
  rand logic [VEC_BYTE_N-1:0][7:0] creq_vdat[THD_N] = '{THD_N{'0}};
  rand int delay_cycle = '0;

  // Optional benchmark policy. M2V duplicate reads remain legal by default.
  bit m2v_unique_enable = 1'b0;

  // Procedurally generated decoded offsets. These values do not enter solver.
  longint signed offs_elem[THD_N][ELEM_MAX_N];
  int unsigned elem_cnt_max;

  // Statistics from the latest generation and validation pass.
  int unsigned generation_retry_count;
  int unsigned generation_reject_count;
  int unsigned validation_error_count;

  constraint c_common_control {
    creq_inv_size inside {[0:12]};
    creq_wpid inside {[0:WARP_N-1]};
    creq_wpnum inside {1, 2, 4};
    creq_tmsk != '0;
    creq_vaddr inside {[0:WARP_STEP-VEC_BYTE_N]};
    creq_base < (longint'(1) << MADDR_W);

    // Temporary stimulus restriction. The protocol only requires final MADDR
    // natural alignment, which validate_transaction checks independently.
    if (creq_dtype == DTYP_32) {
      creq_base[1:0] == 2'b00;
    } else if (creq_dtype == DTYP_16) {
      creq_base[0] == 1'b0;
    }
  }

  constraint c_length {
    foreach (elem_num[thread_idx]) {
      if (creq_dtype == DTYP_32) {
        elem_num[thread_idx] <= VEC_W / 32;
        creq_len[thread_idx] == elem_num[thread_idx] * 4;
      } else if (creq_dtype == DTYP_16) {
        elem_num[thread_idx] <= VEC_W / 16;
        creq_len[thread_idx] == elem_num[thread_idx] * 2;
      } else {
        elem_num[thread_idx] <= VEC_W / 8;
        creq_len[thread_idx] == elem_num[thread_idx];
      }
    }
  }

  //----------------------------------------------------------------------------
  // @brief Constructs a common split-implementation transaction.
  //----------------------------------------------------------------------------
  extern function new(string name = "shmins_sequence_item");

  extern function logic [VEC_W-1:0] creq_offs(int thread_idx);
  extern function void set_creq_offs(
      int thread_idx,
      logic [VEC_W-1:0] offs_value);
  extern function int unsigned data_byte_w();
  extern function int unsigned data_bit_w();
  extern function int unsigned data_elem_max();
  extern function int unsigned offs_bit_w();
  extern function int unsigned offs_elem_max();
  extern function int unsigned gran_shift();
  extern function int unsigned thread_elem_cnt(int thread_idx);
  extern function bit is_active_element(int thread_idx, int elem_idx);
  extern function bit check_offset_encodable(longint signed offset);
  extern function bit encode_offset(
      longint signed offset,
      output logic [31:0] raw_bits);
  extern function longint signed decode_packed_offset(
      int thread_idx,
      int elem_idx);
  extern function longint unsigned coded_warp_bytes();
  extern function shmins_address_result_t map_maddr(
      int thread_idx,
      longint signed maddr);
  extern function longint unsigned physical_byte_key(
      int unsigned bank_id,
      longint unsigned baddr);
  extern function void post_randomize();
  extern function void pack_offsets();
  extern function void validate_transaction();
  extern function void rtl_to_item();
  extern function void item_to_rtl();
  extern function void do_copy(uvm_object rhs);
  extern function bit compare_item(shmins_sequence_item rhs);

  // Derived generators override both methods. The base remains concrete so a
  // future monitor can construct it without randomizing it.
  extern virtual protected function void generate_offsets();
  extern virtual protected function longint signed calculate_maddr(
      int thread_idx,
      int elem_idx);

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
    `uvm_field_sarray_int(elem_num, UVM_DEFAULT)
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
    default: return 0;
  endcase
endfunction : data_byte_w

function int unsigned shmins_sequence_item::data_bit_w();
  return data_byte_w() * 8;
endfunction : data_bit_w

function int unsigned shmins_sequence_item::data_elem_max();
  return data_bit_w() == 0 ? 0 : VEC_W / data_bit_w();
endfunction : data_elem_max

function int unsigned shmins_sequence_item::offs_bit_w();
  case (creq_atype_w)
    ATYP_32: return 32;
    ATYP_16: return 16;
    default: return 0;
  endcase
endfunction : offs_bit_w

function int unsigned shmins_sequence_item::offs_elem_max();
  return offs_bit_w() == 0 ? 0 : VEC_W / offs_bit_w();
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

function int unsigned shmins_sequence_item::thread_elem_cnt(int thread_idx);
  if (thread_idx < 0 || thread_idx >= THD_N || data_byte_w() == 0) begin
    return 0;
  end
  return int'(creq_len[thread_idx]) / data_byte_w();
endfunction : thread_elem_cnt

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

function bit shmins_sequence_item::check_offset_encodable(longint signed offset);
  longint signed raw_value;
  longint signed minimum;
  longint signed maximum;
  int unsigned scale;

  scale = 1 << gran_shift();
  if (data_byte_w() == 0 || offset % longint'(data_byte_w()) != 0) begin
    return 1'b0;
  end
  if (offset % longint'(scale) != 0) begin
    return 1'b0;
  end
  raw_value = offset / longint'(scale);

  if (creq_atype_s == ATYP_S) begin
    minimum = -(longint'(1) << (offs_bit_w() - 1));
    maximum = (longint'(1) << (offs_bit_w() - 1)) - 1;
  end else begin
    minimum = 0;
    maximum = (longint'(1) << offs_bit_w()) - 1;
  end
  return raw_value >= minimum && raw_value <= maximum;
endfunction : check_offset_encodable

function bit shmins_sequence_item::encode_offset(
    longint signed offset,
    output logic [31:0] raw_bits);
  longint signed raw_value;
  int unsigned scale;

  raw_bits = '0;
  if (!check_offset_encodable(offset)) begin
    return 1'b0;
  end
  scale = 1 << gran_shift();
  raw_value = offset / longint'(scale);
  raw_bits = raw_value[31:0];
  if (offs_bit_w() == 16) begin
    raw_bits[31:16] = '0;
  end
  return 1'b1;
endfunction : encode_offset

function longint signed shmins_sequence_item::decode_packed_offset(
    int thread_idx,
    int elem_idx);
  logic [31:0] raw_bits;
  longint signed raw_value;
  int unsigned width;

  width = offs_bit_w();
  raw_bits = '0;
  if (thread_idx < 0 || thread_idx >= THD_N ||
      elem_idx < 0 || elem_idx >= offs_elem_max()) begin
    return 0;
  end

  case (width)
    32: raw_bits = creq_offs_packed[thread_idx][elem_idx*32 +: 32];
    16: raw_bits[15:0] = creq_offs_packed[thread_idx][elem_idx*16 +: 16];
    default: return 0;
  endcase

  if (creq_atype_s == ATYP_S) begin
    case (width)
      32: raw_value = longint'($signed(raw_bits));
      16: raw_value = longint'($signed(raw_bits[15:0]));
      default: raw_value = 0;
    endcase
  end else begin
    raw_value = longint'($unsigned(raw_bits));
  end
  return raw_value * (longint'(1) << gran_shift());
endfunction : decode_packed_offset

function longint unsigned shmins_sequence_item::coded_warp_bytes();
  longint unsigned interleave_bytes;

  interleave_bytes = longint'(1) << (int'(creq_inv_size) + 2);
  return interleave_bytes <= 4096 ? WARP_STEP : 16 * 1024;
endfunction : coded_warp_bytes

function shmins_sequence_item::shmins_address_result_t shmins_sequence_item::map_maddr(
    int thread_idx,
    longint signed maddr);
  shmins_address_result_t result;
  longint unsigned address;
  longint unsigned coded_bytes;
  longint unsigned interleave_bytes;
  longint unsigned interleave_offset;
  longint unsigned interleave_index;

  result = '{default:'0};
  if (maddr < 0 || data_byte_w() == 0 ||
      maddr % longint'(data_byte_w()) != 0) begin
    return result;
  end

  address = longint'(maddr);
  coded_bytes = coded_warp_bytes();
  interleave_bytes = longint'(1) << (int'(creq_inv_size) + 2);
  interleave_offset = address % interleave_bytes;

  case (creq_space)
    SPACE_LOC: begin
      if (thread_idx < 0 || thread_idx >= BANK_N || address >= WARP_STEP) begin
        return result;
      end
      result.bank_id = thread_idx;
      result.local_offset = address;
      result.warp_index = int'(creq_wpid);
    end

    SPACE_WRP: begin
      if (address >= coded_bytes * BANK_N) begin
        return result;
      end
      result.bank_id = int'((address / interleave_bytes) % BANK_N);
      interleave_index = address / (interleave_bytes * BANK_N);
      result.local_offset = interleave_index * interleave_bytes + interleave_offset;
      result.warp_index = int'(creq_wpid);
    end

    SPACE_BLK: begin
      longint unsigned group_address;
      longint unsigned group_span;
      longint unsigned warp_group;
      longint unsigned warp_offset;
      int unsigned warps_per_group;

      if (creq_wpnum == 0 || address >= coded_bytes * BANK_N * WARP_N) begin
        return result;
      end
      warps_per_group = int'(creq_wpnum);
      group_span = coded_bytes * BANK_N * warps_per_group;
      warp_group = address / group_span;
      group_address = address % group_span;
      result.bank_id = int'((group_address / interleave_bytes) % BANK_N);
      warp_offset = (group_address / (interleave_bytes * BANK_N)) % warps_per_group;
      interleave_index = (group_address /
          (interleave_bytes * BANK_N * warps_per_group)) % (coded_bytes / interleave_bytes);
      result.local_offset = interleave_index * interleave_bytes + interleave_offset;
      result.warp_index = int'(warp_group * warps_per_group + warp_offset);
      if (result.warp_index >= WARP_N ||
          int'(creq_wpid) / warps_per_group != result.warp_index / warps_per_group) begin
        return '{default:'0};
      end
    end

    default: return result;
  endcase

  if (result.local_offset >= WARP_STEP || result.warp_index >= WARP_N) begin
    return '{default:'0};
  end
  result.baddr = BADDR_W'(result.warp_index * WARP_STEP + result.local_offset);
  result.valid = 1'b1;
  return result;
endfunction : map_maddr

function longint unsigned shmins_sequence_item::physical_byte_key(
    int unsigned bank_id,
    longint unsigned baddr);
  return (longint'(bank_id) << BADDR_W) | baddr;
endfunction : physical_byte_key

function void shmins_sequence_item::post_randomize();
  generation_retry_count = 0;
  generation_reject_count = 0;
  validation_error_count = 0;
  elem_cnt_max = data_elem_max();
  foreach (offs_elem[thread_idx, elem_idx]) begin
    offs_elem[thread_idx][elem_idx] = 0;
  end

  generate_offsets();
  pack_offsets();
  validate_transaction();
endfunction : post_randomize

function void shmins_sequence_item::pack_offsets();
  int unsigned offset_count;
  int unsigned width;

  offset_count = offs_elem_max();
  width = offs_bit_w();
  for (int thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    creq_offs_packed[thread_idx] = '0;
    for (int elem_idx = 0;
         elem_idx < offset_count && elem_idx < ELEM_MAX_N;
         elem_idx++) begin
      logic [31:0] raw_bits;

      if (!encode_offset(offs_elem[thread_idx][elem_idx], raw_bits)) begin
        `uvm_fatal("SHMINS_SPLIT_OFFSET_ENCODING",
                   $sformatf("thread=%0d elem=%0d offset=%0d is not encodable",
                             thread_idx, elem_idx, offs_elem[thread_idx][elem_idx]))
      end
      case (width)
        32: creq_offs_packed[thread_idx][elem_idx*32 +: 32] = raw_bits;
        16: creq_offs_packed[thread_idx][elem_idx*16 +: 16] = raw_bits[15:0];
        default: ;
      endcase
    end
  end
endfunction : pack_offsets

function void shmins_sequence_item::validate_transaction();
  bit used_bytes[longint unsigned];

  validation_error_count = 0;
  if ($isunknown(creq_tmsk) || creq_tmsk == '0) begin
    validation_error_count++;
    `uvm_error("SHMINS_SPLIT_INVALID_TMSK", "creq_tmsk must be known and non-zero")
  end
  if (creq_inv_size > 12) begin
    validation_error_count++;
    `uvm_error("SHMINS_SPLIT_INVALID_INV_SIZE",
               $sformatf("creq_inv_size=%0d is outside 0 through 12", creq_inv_size))
  end
  if (!(creq_wpnum inside {1, 2, 4}) || int'(creq_wpid) >= WARP_N) begin
    validation_error_count++;
    `uvm_error("SHMINS_SPLIT_INVALID_WARP",
               $sformatf("creq_wpid=%0d creq_wpnum=%0d", creq_wpid, creq_wpnum))
  end

  for (int thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    if (data_byte_w() == 0 ||
        int'(creq_len[thread_idx]) % data_byte_w() != 0 ||
        thread_elem_cnt(thread_idx) > data_elem_max()) begin
      validation_error_count++;
      `uvm_error("SHMINS_SPLIT_INVALID_LENGTH",
                 $sformatf("thread=%0d length=%0d dtype=%0d",
                           thread_idx, creq_len[thread_idx], creq_dtype))
      continue;
    end
    for (int elem_idx = 0;
         elem_idx < thread_elem_cnt(thread_idx) && elem_idx < ELEM_MAX_N;
         elem_idx++) begin
      longint signed maddr;
      shmins_address_result_t mapped;

      if (!is_active_element(thread_idx, elem_idx)) begin
        continue;
      end
      maddr = calculate_maddr(thread_idx, elem_idx);
      mapped = map_maddr(thread_idx, maddr);
      if (!mapped.valid) begin
        validation_error_count++;
        `uvm_error("SHMINS_SPLIT_INVALID_MADDR",
                   $sformatf("thread=%0d elem=%0d maddr=%0d is illegal",
                             thread_idx, elem_idx, maddr))
        continue;
      end

      if (creq_rw == SHM_V2M || m2v_unique_enable) begin
        for (int lane = 0; lane < data_byte_w(); lane++) begin
          longint unsigned key;

          key = physical_byte_key(mapped.bank_id, mapped.baddr + lane);
          if (used_bytes.exists(key)) begin
            validation_error_count++;
            `uvm_error("SHMINS_SPLIT_BYTE_COLLISION",
                       $sformatf("thread=%0d elem=%0d lane=%0d key=0x%0h",
                                 thread_idx, elem_idx, lane, key))
          end else begin
            used_bytes[key] = 1'b1;
          end
        end
      end
    end
  end

  if (validation_error_count != 0) begin
    `uvm_fatal("SHMINS_SPLIT_VALIDATION_FAILED",
               $sformatf("transaction has %0d validation errors", validation_error_count))
  end
endfunction : validate_transaction

function void shmins_sequence_item::generate_offsets();
  `uvm_fatal("SHMINS_SPLIT_BASE_RANDOMIZE",
             "shmins_sequence_item must be randomized through a topology subclass")
endfunction : generate_offsets

function longint signed shmins_sequence_item::calculate_maddr(
    int thread_idx,
    int elem_idx);
  return -1;
endfunction : calculate_maddr

function void shmins_sequence_item::rtl_to_item();
  {creq_info, creq_space, creq_inv_size, creq_ack_en, creq_itype,
   creq_atype_g, creq_atype_s, creq_atype_w, creq_dtype, creq_rw} = creq_typ;
endfunction : rtl_to_item

function void shmins_sequence_item::item_to_rtl();
  creq_typ = {creq_info, creq_space, creq_inv_size, creq_ack_en, creq_itype,
              creq_atype_g, creq_atype_s, creq_atype_w, creq_dtype, creq_rw};
endfunction : item_to_rtl

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
  generation_retry_count = rhs_item.generation_retry_count;
  generation_reject_count = rhs_item.generation_reject_count;
  validation_error_count = rhs_item.validation_error_count;

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

function bit shmins_sequence_item::compare_item(shmins_sequence_item rhs);
  return compare(rhs);
endfunction : compare_item

`endif // INC_SHMINS_SPLIT_SEQUENCE_ITEM_SVH
