`ifndef INC_SHMINS_SEQUENCE_ITEM_SVH
`define INC_SHMINS_SEQUENCE_ITEM_SVH

//-------------------------------------------------------------------
// Class: shmins_sequence_item
//
//-------------------------------------------------------------------

typedef enum bit {
  SHM_V2M = 1'b0,
  SHM_M2V = 1'b1
} creq_rw_e;

typedef enum bit[1:0] {
  DTYP_32 = 2'h0,
  DTYP_16 = 2'h1,
  DTYP_8  = 2'h2
} creq_dtype_e;

typedef enum bit[1:0] {
  ATYP_32 = 2'h0,
  ATYP_16 = 2'h1,
  ATYP_8  = 2'h2
} creq_atype_w_e;

typedef enum bit {
  ATYP_U  = 1'h0,
  ATYP_S  = 1'h1
} creq_atype_s_e;

typedef enum bit {
  GAUTO_1B = 1'h0,
  GAUTO_DW = 1'h1
} creq_atype_g_e;

typedef enum bit[1:0] {
  LDST_S  = 2'h0,
  LDST_V  = 2'h1,
  LDSTE_S = 2'h2,
  LDSTE_V = 2'h3
} creq_itype_e;

typedef enum bit[1:0] {
  SPACE_LOC = 2'd0,
  SPACE_WRP = 2'd1,
  SPACE_BLK = 2'd2
} creq_space_e;

class shmins_sequence_item extends uvm_sequence_item;
  parameter WARP_ID_WIDTH_MAX = $clog2(4);
  parameter int unsigned ELEM_MAX_N = VEC_BYTE_N;
  parameter int unsigned VADDR_MAX = (1 << VADDR_W)-1;

  // item data
  rand creq_rw_e      creq_rw       = SHM_V2M ;
  rand creq_dtype_e   creq_dtype    = DTYP_32 ;
  rand creq_atype_w_e creq_atype_w  = ATYP_32 ;
  rand creq_atype_s_e creq_atype_s  = ATYP_U  ;
  rand creq_atype_g_e creq_atype_g  = GAUTO_1B ;
  rand creq_itype_e   creq_itype    = LDST_V  ;
  rand logic [0:0]    creq_ack_en   = '0      ;
  rand logic [3:0]    creq_inv_size = '0      ;
  rand creq_space_e   creq_space    = SPACE_LOC;
  logic [19:0]        creq_typ      = '0      ;

  rand logic [3:0]    creq_info     = '0      ;
  rand logic [ID_W-1:0] creq_id     = '0      ;
  rand logic [$clog2(WARP_N)-1:0] creq_wpid = '0 ;
  rand logic [$clog2(WARP_N+1)-1:0] creq_wpnum = '0 ;
  rand int wpid_width = '0 ;
  rand logic [VADDR_W-1:0] creq_vaddr = '0 ;
  rand logic [47:0] creq_base = '0 ; // byte addr

  rand logic [3:0] creq_prio[THD_N] = '{THD_N{'0}}; // thd prio
  rand logic [7:0] creq_len[THD_N]  = '{THD_N{'0}}; // element total byte number length:0~32, align with data type
  rand byte elem_num[THD_N]         = '{THD_N{'0}};
  rand logic [VEC_BYTE_N-1:0] creq_vmsk[THD_N] = '{THD_N{'0}}; // element mask
  rand logic [THD_N]          creq_tmsk = '{THD_N{'0}}; // thread mask, 1: active, 0: inactive
  logic [VEC_W-1:0] creq_offs_packed[THD_N]; // packed form, filled in post_randomize
  rand logic [VEC_BYTE_N-1:0][7:0] creq_vdat[THD_N] = '{THD_N{'0}};
  rand int delay_cycle = '0;

  // Accessor function matching original field name (hint #3)
  function logic [VEC_W-1:0] creq_offs(int t);
    return creq_offs_packed[t];
  endfunction

  function void set_creq_offs(int t, logic [VEC_W-1:0] offs_value);
    creq_offs_packed[t] = offs_value;
  endfunction

  // ==================================================================
  // Intermediate rand variables for offset elements (after extraction,
  // sign/zero-extension to 32-bit, granularity shift, and alignment).
  // offs_elem[thread][element index] is the final physical offset for
  // thread t, element k. Only indices < active element count are used.
  // ==================================================================
  rand int offs_elem[THD_N][ELEM_MAX_N];

  // Maximum active data elements allowed for each thread in this transaction.
  // The actual per-thread element count is derived from creq_len[t].
  rand int unsigned elem_cnt_max;

  // ==================================================================
  // Helper functions
  // ==================================================================

  // Data element byte width from creq_dtype
  function int unsigned data_byte_w();
    case (creq_dtype)
      DTYP_32: return 4;
      DTYP_16: return 2;
      DTYP_8 : return 1;
      default: return 4;
    endcase
  endfunction

  // Data element bit width
  function int unsigned data_bit_w();
    return data_byte_w() * 8;
  endfunction

  // Max data elements that fit in VEC_W bits
  function int unsigned data_elem_max();
    return $unsigned(VEC_W) / data_bit_w();
  endfunction

  // Offset element bit width from creq_atype_w
  function int unsigned offs_bit_w();
    case (creq_atype_w)
      ATYP_32: return 32;
      ATYP_16: return 16;
      ATYP_8 : return 8;
      default: return 32;
    endcase
  endfunction

  // Max offset elements that fit in VEC_W bits
  function int unsigned offs_elem_max();
    return $unsigned(VEC_W) / offs_bit_w();
  endfunction

  // Granularity left-shift amount
  function int unsigned gran_shift();
    if (creq_atype_g == GAUTO_1B) return 0;
    case (creq_dtype)
      DTYP_32: return 2;
      DTYP_16: return 1;
      DTYP_8 : return 0;
      default: return 0;
    endcase
  endfunction

  // Alignment mask: aligned offset must have (offset & align_mask) == 0
  function int unsigned align_mask();
    case (creq_dtype)
      DTYP_32: return 32'h3;
      DTYP_16: return 32'h1;
      DTYP_8 : return 32'h0;
      default: return 32'h0;
    endcase
  endfunction

  // Address space upper bound
  function int unsigned addr_max();
    case (creq_space)
      SPACE_LOC: return 1 << VADDR_W;
      SPACE_WRP: return 1 << BADDR_W;
      SPACE_BLK: return 1 << MADDR_W;
      default:   return 1 << VADDR_W;
    endcase
  endfunction

  // Max element count considering itype
  function int unsigned max_elem_cnt();
    if (creq_itype == LDSTE_V)
      return (data_elem_max() < offs_elem_max()) ? data_elem_max() : offs_elem_max();
    else
      return data_elem_max();
  endfunction

  // Active element count for thread t, derived from per-thread byte length.
  function automatic int unsigned thread_elem_cnt(int t);
    case (creq_dtype)
      DTYP_32: return int'(creq_len[t]) / 4;
      DTYP_16: return int'(creq_len[t]) / 2;
      DTYP_8 : return int'(creq_len[t]);
      default: return 0;
    endcase
  endfunction

  // Compute physical address for thread t, element k
  function int phys_addr(int t, int k);
    int base_20b = int'(creq_base[MADDR_W-1:0]); // truncate base to max address width
    int res;
    case (creq_itype)
      LDST_S, LDST_V:
        res = base_20b + offs_elem[t][0] + k * int'(data_byte_w());
      LDSTE_V:
        res = base_20b + offs_elem[t][k];
      LDSTE_S:
        res = base_20b + k * offs_elem[t][0];
      default:
        res = 0;
    endcase
    return res;
  endfunction

  // ==================================================================
  // Constraints (auto-generated - run: python scripts/gen_shmins_constraints.py)
  // ==================================================================
  `include "shmins_seq_item_constraints.svh"

  // -- base range and alignment -------------------------------------
  constraint c_base_range_and_align {
    (creq_inv_size + 2) inside {[2:14]}; // support 4B to 16KB
    creq_base inside {[0:(1 << MADDR_W)-1]};
    if (creq_dtype == DTYP_32) creq_base[1:0] == 0;
    else if (creq_dtype == DTYP_16) creq_base[0] == 0;
    wpid_width inside {[0:WARP_ID_WIDTH_MAX]};
    creq_wpnum == 1 << wpid_width;
    int'(creq_wpid) inside {[0: WARP_N-1]};
    creq_vaddr inside {[0: WARP_STEP - VEC_BYTE_N]};
    creq_tmsk != '0;
  }

  // -- inactive offsets ---------------------------------------------

  // ==================================================================
  // post_randomize: pack offs_elem back into creq_offs[THD_N] (VEC_W-bit)
  //
  // creq_offs encoding:
  //   offs_elem[k] is stored in creq_offs[offs_bit_w*k +: offs_bit_w]
  //   The raw offset element (before sign-ext, shift, alignment) is what
  //   lives in creq_offs. We reverse-compute it from offs_elem.
  // ==================================================================
  function void post_randomize();
    int unsigned obw = offs_bit_w();
    int unsigned omax = offs_elem_max();
    int unsigned gsh = gran_shift();

    for (int t = 0; t < THD_N; t++) begin
      int count_t = int'(thread_elem_cnt(t));
      creq_offs_packed[t] = '0;
      for (int unsigned k = 0; k < omax && k < ELEM_MAX_N; k++) begin
        // Reverse the pipeline:
        // Forward: raw (obw bits) -> sign/zero extend to 32b -> << gsh -> aligned offs_elem
        // Reverse: offs_elem >> gsh -> truncate to obw bits -> pack into creq_offs
        int raw_extended;
        bit [31:0] raw_bits;

        if (k < count_t) begin
          raw_extended = offs_elem[t][k] >>> gsh;
        end else begin
          raw_extended = 0;
        end

        // Truncate to offset bit width and pack
        raw_bits = $unsigned(raw_extended);
        case (obw)
          32: creq_offs_packed[t][k*32 +: 32] = raw_bits[31:0];
          16: creq_offs_packed[t][k*16 +: 16] = raw_bits[15:0];
          8:  creq_offs_packed[t][k*8  +:  8] = raw_bits[7:0];
          default: ;
        endcase
      end
    end

    // Verify all physical addresses in debug
    for (int t = 0; t < THD_N; t++) begin
      int count_t = int'(thread_elem_cnt(t));
      for (int k = 0; k < count_t; k++) begin
        int pa = phys_addr(t, k);
        if (pa < 0 || pa >= addr_max()) begin
          `uvm_warning(get_type_name(), $sformatf("post_randomize: phys_addr[%0d][%0d] = %0d out of range [0, %0d)", t, k, pa, addr_max()))
        end
      end
    end
  endfunction

  //-------------------------------------------------------------------
  // Constraints
  //-------------------------------------------------------------------

  //-------------------------------------------------------------------
  // Methods
  //-------------------------------------------------------------------

  // ------------------
  // Standard UVM Methods
  // ------------------
  extern function new(string name="shmins_sequence_item");

  // ------------------
  // User Defined APIs
  // ------------------
  function void do_copy(uvm_object rhs);
    shmins_sequence_item rhs_;
    if (!$cast(rhs_, rhs))
      `uvm_fatal(get_type_name(), "Cast of rhs object failed")

    this.creq_rw         = rhs_.creq_rw;
    this.creq_dtype      = rhs_.creq_dtype;
    this.creq_atype_w    = rhs_.creq_atype_w;
    this.creq_atype_s    = rhs_.creq_atype_s;
    this.creq_atype_g    = rhs_.creq_atype_g;
    this.creq_itype      = rhs_.creq_itype;
    this.creq_ack_en     = rhs_.creq_ack_en;
    this.creq_inv_size   = rhs_.creq_inv_size;
    this.creq_space      = rhs_.creq_space;
    this.creq_typ        = rhs_.creq_typ;
    this.creq_id         = rhs_.creq_id;
    this.creq_wpid       = rhs_.creq_wpid;
    this.creq_wpnum      = rhs_.creq_wpnum;
    this.wpid_width      = rhs_.wpid_width;
    this.creq_vaddr      = rhs_.creq_vaddr;
    this.creq_base       = rhs_.creq_base;
    this.delay_cycle     = rhs_.delay_cycle;

    foreach(creq_prio[i]) begin
      this.creq_prio[i] = rhs_.creq_prio[i];
    end

    foreach(creq_len[i]) begin
      this.creq_len[i] = rhs_.creq_len[i];
    end

    foreach(elem_num[i]) begin
      this.elem_num[i] = elem_num[i];
    end

    foreach(creq_vmsk[i]) begin
      this.creq_vmsk[i] = creq_vmsk[i];
    end

    foreach(creq_offs_packed[i]) begin
      this.creq_offs_packed[i] = creq_offs_packed[i];
    end

    foreach(creq_vdat[i]) begin
      this.creq_vdat[i] = rhs_.creq_vdat[i];
    end

    foreach(offs_elem[i, j]) begin
      this.offs_elem[i][j] = rhs_.offs_elem[i][j];
    end

    this.elem_cnt_max = rhs_.elem_cnt_max;
  endfunction : do_copy

  function void rtl_to_item();
    { creq_info     ,
      creq_space    ,
      creq_inv_size ,
      creq_ack_en   ,
      creq_itype    ,
      creq_atype_g  ,
      creq_atype_s  ,
      creq_atype_w  ,
      creq_dtype    ,
      creq_rw       } = creq_typ;
  endfunction : rtl_to_item

  function void item_to_rtl();
    creq_typ = { creq_info     ,
                 creq_space    ,
                 creq_inv_size ,
                 creq_ack_en   ,
                 creq_itype    ,
                 creq_atype_g  ,
                 creq_atype_s  ,
                 creq_atype_w  ,
                 creq_dtype    ,
                 creq_rw       };
  endfunction : item_to_rtl

  function bit compare_item(shmins_sequence_item shmins_trans);
    int error = 0;

    // do compare
    `uvm_fatal(get_type_name(), "please implement do_compare")

    return error;
  endfunction

  // ------------------
  // UVM Factory Registration
  // ------------------
  `uvm_object_utils_begin(shmins_sequence_item)
  // ------------------
  // Add field configurations
  // ------------------
  // ------------------
  `uvm_field_enum(creq_rw_e        , creq_rw      , UVM_DEFAULT)
  `uvm_field_enum(creq_dtype_e     , creq_dtype   , UVM_DEFAULT)
  `uvm_field_enum(creq_atype_w_e   , creq_atype_w , UVM_DEFAULT)
  `uvm_field_enum(creq_atype_s_e   , creq_atype_s , UVM_DEFAULT)
  `uvm_field_enum(creq_atype_g_e   , creq_atype_g , UVM_DEFAULT)
  `uvm_field_enum(creq_itype_e     , creq_itype   , UVM_DEFAULT)
  `uvm_field_enum(creq_space_e     , creq_space   , UVM_DEFAULT)

  `uvm_field_int(creq_info         , UVM_DEFAULT)
  `uvm_field_int(creq_ack_en       , UVM_DEFAULT)
  `uvm_field_int(creq_inv_size     , UVM_DEFAULT)
  `uvm_field_int(creq_typ          , UVM_DEFAULT)

  `uvm_field_int(creq_id           , UVM_DEFAULT)
  `uvm_field_int(creq_wpid         , UVM_DEFAULT)
  `uvm_field_int(creq_wpnum        , UVM_DEFAULT)
  `uvm_field_int(creq_vaddr        , UVM_DEFAULT)
  `uvm_field_int(creq_base         , UVM_DEFAULT)
  `uvm_field_int(delay_cycle       , UVM_DEFAULT)

  `uvm_field_sarray_int(creq_prio  , UVM_DEFAULT)
  `uvm_field_sarray_int(creq_len   , UVM_DEFAULT)
  `uvm_field_sarray_int(creq_vmsk  , UVM_DEFAULT)
  `uvm_field_sarray_int(creq_offs_packed, UVM_DEFAULT)
  `uvm_field_sarray_int(creq_vdat  , UVM_DEFAULT)

  `uvm_object_utils_end
endclass: shmins_sequence_item


//-------------------------------------------------------------------
// Function: new
//
//-------------------------------------------------------------------

function shmins_sequence_item::new(string name="shmins_sequence_item");
  super.new(name);
endfunction: new

`endif // INC_SHMINS_SEQUENCE_ITEM_SVH
