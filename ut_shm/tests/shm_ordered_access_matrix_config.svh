`ifndef INC_SHM_ORDERED_ACCESS_MATRIX_CONFIG_SVH
`define INC_SHM_ORDERED_ACCESS_MATRIX_CONFIG_SVH

typedef enum int unsigned {
  MATRIX_M_READ_THEN_WRITE = 0,
  MATRIX_M_WRITE_THEN_READ = 1,
  MATRIX_M_WRITE_THEN_WRITE = 2,
  MATRIX_V_WRITE_THEN_WRITE = 3
} shm_ordered_access_kind_e;

typedef enum int unsigned {
  MATRIX_OVERLAP_EXACT = 0,
  MATRIX_OVERLAP_PARTIAL = 1
} shm_ordered_access_overlap_e;

//------------------------------------------------------------------------------
// @brief Owns and validates one ordered-access regression matrix point.
//
// The object reads one complete cell description from plusargs. It rejects
// missing, misspelled, and unsupported combinations before stimulus starts. It
// does not generate transactions or inspect DUT results.
//------------------------------------------------------------------------------
class shm_ordered_access_matrix_config extends uvm_object;
  // Stable diagnostic label supplied by the TC alias.
  string cell_name;

  // Architectural ordered relation exercised by this simulation.
  shm_ordered_access_kind_e order_kind;

  // Physical-byte overlap class exercised by this simulation.
  shm_ordered_access_overlap_e overlap_class;

  // DTYPE of the earlier and later target transactions.
  creq_dtype_e first_dtype;
  creq_dtype_e second_dtype;

  // Common normal-transaction topology and address space for this matrix point.
  creq_itype_e itype;
  creq_space_e space;

  // Active thread and WARP controls. Signed storage preserves invalid negatives.
  int thread_idx;
  int wpid;
  int wpnum;

  // Selects the supported VTRANS-first special matrix point.
  bit first_is_vtrans;

  //----------------------------------------------------------------------------
  // @brief Constructs an empty matrix configuration.
  //
  // @param name UVM object instance name.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_ordered_access_matrix_config");

  //----------------------------------------------------------------------------
  // @brief Loads all required matrix fields from plusargs and validates them.
  //
  // @post Every public field contains a known, supported value.
  //----------------------------------------------------------------------------
  extern function void load_plusargs();

  //----------------------------------------------------------------------------
  // @brief Returns the physical gid expected for the configured overlap.
  //
  // @return Gid derived from the absolute configured WARP ID.
  //----------------------------------------------------------------------------
  extern function int unsigned expected_gid();

  //----------------------------------------------------------------------------
  // @brief Formats the complete matrix point for reports.
  //
  // @return Single-line configuration description.
  //----------------------------------------------------------------------------
  extern function string configuration_sprint();

  //----------------------------------------------------------------------------
  // @brief Reads one required string plusarg.
  //
  // @param name Plusarg name without a leading plus sign or equals sign.
  // @return Non-empty value supplied for the requested plusarg.
  //----------------------------------------------------------------------------
  extern protected function string required_string_plusarg(string name);

  //----------------------------------------------------------------------------
  // @brief Reads one required signed decimal plusarg.
  //
  // @param name Plusarg name without a leading plus sign or equals sign.
  // @return Decimal value supplied for the requested plusarg.
  //----------------------------------------------------------------------------
  extern protected function int required_int_plusarg(string name);

  //----------------------------------------------------------------------------
  // @brief Validates cross-field restrictions supported by the matrix runner.
  //----------------------------------------------------------------------------
  extern protected function void validate_configuration();

  `uvm_object_utils(shm_ordered_access_matrix_config)
endclass : shm_ordered_access_matrix_config

function shm_ordered_access_matrix_config::new(string name = "shm_ordered_access_matrix_config");
  super.new(name);
endfunction : new

function string shm_ordered_access_matrix_config::required_string_plusarg(string name);
  string value;

  if (!$value$plusargs({name, "=%s"}, value) || value.len() == 0) begin
    `uvm_fatal("SHM_ORDER_MATRIX_MISSING_PLUSARG",
               $sformatf("required plusarg +%s=<value> is missing", name))
  end
  return value;
endfunction : required_string_plusarg

function int shm_ordered_access_matrix_config::required_int_plusarg(string name);
  int value;

  if (!$value$plusargs({name, "=%d"}, value)) begin
    `uvm_fatal("SHM_ORDER_MATRIX_MISSING_PLUSARG",
               $sformatf("required plusarg +%s=<decimal> is missing", name))
  end
  return value;
endfunction : required_int_plusarg

function void shm_ordered_access_matrix_config::load_plusargs();
  string value;
  int vtrans_value;

  cell_name = required_string_plusarg("ORDER_CELL");

  value = str_toupper(required_string_plusarg("ORDER_KIND"));
  case (value)
    "M_READ_THEN_WRITE": order_kind = MATRIX_M_READ_THEN_WRITE;
    "M_WRITE_THEN_READ": order_kind = MATRIX_M_WRITE_THEN_READ;
    "M_WRITE_THEN_WRITE": order_kind = MATRIX_M_WRITE_THEN_WRITE;
    "V_WRITE_THEN_WRITE": order_kind = MATRIX_V_WRITE_THEN_WRITE;
    default: `uvm_fatal("SHM_ORDER_MATRIX_KIND_PLUSARG",
                        $sformatf("unsupported +ORDER_KIND=%s", value))
  endcase

  value = str_toupper(required_string_plusarg("ORDER_OVERLAP"));
  case (value)
    "EXACT": overlap_class = MATRIX_OVERLAP_EXACT;
    "PARTIAL": overlap_class = MATRIX_OVERLAP_PARTIAL;
    default: `uvm_fatal("SHM_ORDER_MATRIX_OVERLAP_PLUSARG",
                        $sformatf("unsupported +ORDER_OVERLAP=%s", value))
  endcase

  value = str_toupper(required_string_plusarg("ORDER_FIRST_DTYPE"));
  case (value)
    "DTYP_8": first_dtype = DTYP_8;
    "DTYP_16": first_dtype = DTYP_16;
    "DTYP_32": first_dtype = DTYP_32;
    default: `uvm_fatal("SHM_ORDER_MATRIX_FIRST_DTYPE_PLUSARG",
                        $sformatf("unsupported +ORDER_FIRST_DTYPE=%s", value))
  endcase

  value = str_toupper(required_string_plusarg("ORDER_SECOND_DTYPE"));
  case (value)
    "DTYP_8": second_dtype = DTYP_8;
    "DTYP_16": second_dtype = DTYP_16;
    "DTYP_32": second_dtype = DTYP_32;
    default: `uvm_fatal("SHM_ORDER_MATRIX_SECOND_DTYPE_PLUSARG",
                        $sformatf("unsupported +ORDER_SECOND_DTYPE=%s", value))
  endcase

  value = str_toupper(required_string_plusarg("ORDER_ITYPE"));
  case (value)
    "LDST_S": itype = LDST_S;
    "LDST_V": itype = LDST_V;
    "LDSTE_S": itype = LDSTE_S;
    "LDSTE_V": itype = LDSTE_V;
    default: `uvm_fatal("SHM_ORDER_MATRIX_ITYPE_PLUSARG",
                        $sformatf("unsupported +ORDER_ITYPE=%s", value))
  endcase

  value = str_toupper(required_string_plusarg("ORDER_SPACE"));
  case (value)
    "SPACE_LOC": space = SPACE_LOC;
    "SPACE_WRP": space = SPACE_WRP;
    "SPACE_BLK": space = SPACE_BLK;
    default: `uvm_fatal("SHM_ORDER_MATRIX_SPACE_PLUSARG",
                        $sformatf("unsupported +ORDER_SPACE=%s", value))
  endcase

  thread_idx = required_int_plusarg("ORDER_THREAD");
  wpid = required_int_plusarg("ORDER_WPID");
  wpnum = required_int_plusarg("ORDER_WPNUM");
  vtrans_value = required_int_plusarg("ORDER_VTRANS_FIRST");
  if (!(vtrans_value inside {0, 1})) begin
    `uvm_fatal("SHM_ORDER_MATRIX_VTRANS_PLUSARG",
               $sformatf("+ORDER_VTRANS_FIRST=%0d must be 0 or 1", vtrans_value))
  end
  first_is_vtrans = bit'(vtrans_value);
  validate_configuration();
endfunction : load_plusargs

function void shm_ordered_access_matrix_config::validate_configuration();
  if (thread_idx < 0 || thread_idx >= THD_N || wpid < 0 || wpid >= WARP_N ||
      !(wpnum inside {1, 2, 4})) begin
    `uvm_fatal("SHM_ORDER_MATRIX_INDEX_CONFIG",
               $sformatf("thread=%0d wpid=%0d wpnum=%0d is outside the supported domain",
                         thread_idx, wpid, wpnum))
  end
  if (space != SPACE_BLK && wpnum != 1) begin
    `uvm_fatal("SHM_ORDER_MATRIX_WPNUM_CONFIG",
               $sformatf("space=%s requires ORDER_WPNUM=1", creq_space_e_to_str(space)))
  end

  if (first_is_vtrans) begin
    if (order_kind != MATRIX_M_WRITE_THEN_WRITE || overlap_class != MATRIX_OVERLAP_PARTIAL ||
        first_dtype != DTYP_16 || second_dtype != DTYP_16 || space != SPACE_LOC ||
        !(itype inside {LDST_S, LDST_V}) || wpnum != 1) begin
      `uvm_fatal("SHM_ORDER_MATRIX_VTRANS_CONFIG",
                 "VTRANS cell requires MWMW, PARTIAL, DTYP16/16, LOC, contiguous, and WPNUM=1")
    end
  end else if (overlap_class == MATRIX_OVERLAP_EXACT) begin
    if (first_dtype != second_dtype) begin
      `uvm_fatal("SHM_ORDER_MATRIX_EXACT_DTYPE",
                 "normal EXACT cells require identical first and second DTYPE")
    end
  end else begin
    if (first_dtype != DTYP_32 || second_dtype != DTYP_16 || space != SPACE_LOC ||
        itype != LDST_S || wpnum != 1) begin
      `uvm_fatal("SHM_ORDER_MATRIX_PARTIAL_CONFIG",
                 "normal PARTIAL cells currently require DTYP32->DTYP16, LOC, LDST_S, and WPNUM=1")
    end
  end
endfunction : validate_configuration

function int unsigned shm_ordered_access_matrix_config::expected_gid();
  return int'(wpid) / WARP_PER_GID;
endfunction : expected_gid

function string shm_ordered_access_matrix_config::configuration_sprint();
  return $sformatf({"cell=%s kind=%0d overlap=%0d dtype=%s->%s itype=%s space=%s ",
                    "thread=%0d wpid=%0d wpnum=%0d vtrans_first=%0d"},
                   cell_name, order_kind, overlap_class, creq_dtype_e_to_str(first_dtype),
                   creq_dtype_e_to_str(second_dtype), creq_itype_e_to_str(itype),
                   creq_space_e_to_str(space), thread_idx, wpid, wpnum, first_is_vtrans);
endfunction : configuration_sprint

`endif // INC_SHM_ORDERED_ACCESS_MATRIX_CONFIG_SVH
