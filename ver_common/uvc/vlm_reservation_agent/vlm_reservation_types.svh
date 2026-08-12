`ifndef INC_VLM_RESERVATION_TYPES_SVH
`define INC_VLM_RESERVATION_TYPES_SVH

//------------------------------------------------------------------------------
// @brief Selects the independently scheduled read or write reservation table.
//------------------------------------------------------------------------------
typedef enum bit {
  VLM_RESERVATION_READ  = 1'b0,
  VLM_RESERVATION_WRITE = 1'b1
} vlm_reservation_direction_e;

// Number of independently scheduled reservation directions.
localparam int unsigned VLM_RESERVATION_DIRECTION_N = 2;

// Two-state busy table indexed by relative delay, gid, and sub-bank identifier.
typedef bit [VTAB_D-1:0][GID_N-1:0][VLM_SUB_BANK_N-1:0] vlm_busy_table_t;

//------------------------------------------------------------------------------
// @brief Carries one fully known actual MEM request sampled by the monitor.
//
// Array position identifies direction and BANK. A null handle in the containing
// cycle transaction means that the corresponding physical port produced no
// fully known request. The monitor owns each instance; downstream components
// must treat it as read-only.
//------------------------------------------------------------------------------
class vlm_mem_req;
  // Known BANK-local address carried by the actual MEM request.
  bit [BADDR_W-1:0] address;

  // MEM write byte enables and data sampled in the request cycle.
  bit [VLM_DATA_BYTE_W-1:0] strb;
  bit [VLM_DATA_BIT_W-1:0] data;
endclass : vlm_mem_req

//------------------------------------------------------------------------------
// @brief Carries one fully known VLM reservation request.
//
// Extends the actual-MEM request payload with the issue-time relative delay.
// Array position identifies direction, BANK, and write port. Semantic legality
// is checked after monitoring; downstream components must not modify instances.
//------------------------------------------------------------------------------
class vlm_rsv_req extends vlm_mem_req;
  // Requested number of cycles from issue to the actual MEM request.
  int unsigned delay;

  // Low/high physical bank selected by this reservation.
  shm_gid_t gid;
endclass : vlm_rsv_req

//------------------------------------------------------------------------------
// @brief Describes one accepted DUT reservation stored by the scheduler.
//
// Direction, current relative delay, and BANK are represented by the indices of
// the containing scheduler array. Sub-bank identity is derived from address.
// The scheduler owns each instance and all readers must treat it as immutable.
//------------------------------------------------------------------------------
class vlm_shm_record_t;
  // Complete known BANK-local address reserved by the DUT, including low bits.
  bit [BADDR_W-1:0] address;

  // Low/high physical bank carried by the accepted reservation request.
  shm_gid_t gid;

  // Source write-port index; read reservations use zero by convention.
  int unsigned write_port;

  // Global clk_if cycle in which the reservation request was sampled.
  longint unsigned issue_cycle;

  // Original issue-time delay; this value does not change as the record moves.
  int unsigned issue_delay;
endclass : vlm_shm_record_t


//------------------------------------------------------------------------------
// @brief Carries one normalized reservation/MEM cycle transaction.
//
// The cycle is a snapshot of clk_if.cycle_count, not an independently
// maintained counter. Known semantic violations remain as events for checker
// diagnosis. A physical port has a non-null request handle only when its valid
// and active payload were fully known at the sampling edge.
//------------------------------------------------------------------------------
typedef struct {
  // Global clk_if cycle associated with all events in this transaction.
  longint unsigned cycle;

  // Two-state busy values observed at the interface; monitor maps X/Z to zero.
  vlm_busy_table_t observed_busy[VLM_RESERVATION_DIRECTION_N];

  // Per-BANK read reservation handles; null means no fully known request.
  vlm_rsv_req rsv_rreq_array[BANK_N];

  // Per-BANK and per-port write reservation handles; null means no known request.
  vlm_rsv_req rsv_wreq_array[BANK_N][WRITE_PORT_N];

  // Per-BANK actual MEM read handles; null means no fully known request.
  vlm_mem_req mem_rreq_array[BANK_N];

  // Per-BANK actual MEM write handles; null means no fully known request.
  vlm_mem_req mem_wreq_array[BANK_N];

  // Set when the monitor detects any unknown valid, active payload, or busy.
  bit input_error;
} vlm_reservation_cycle_transaction_t;

//------------------------------------------------------------------------------
// @brief Summarizes checker outcomes for one normalized cycle transaction.
//
// The checker creates one result before the scheduler mutates its state. The
// agent passes the result to coverage together with the same transaction and
// pre-update scheduler view.
//------------------------------------------------------------------------------
typedef struct {
  // Set when every checker category passes for the sampled cycle.
  bit passed;

  // Number of reservation protocol violations reported in this cycle.
  int unsigned reservation_error_count;

  // Number of scheduler busy-state violations reported in this cycle.
  int unsigned busy_error_count;

  // Number of reservation-to-MEM matching violations reported in this cycle.
  int unsigned mem_match_error_count;

  // Number of unsupported dly-zero reservations reported in this cycle.
  int unsigned dly_zero_error_count;

  // Number of MEM requests matched to their unique due records in this cycle.
  int unsigned matched_mem_request_count;

  // Per-direction, per-BANK gid resolution for actual MEM requests.
  shm_gid_t mem_gid[VLM_RESERVATION_DIRECTION_N][BANK_N];
  bit mem_gid_valid[VLM_RESERVATION_DIRECTION_N][BANK_N];
  bit mem_reservation_matched[VLM_RESERVATION_DIRECTION_N][BANK_N];
} vlm_reservation_check_result_t;

`endif // INC_VLM_RESERVATION_TYPES_SVH
