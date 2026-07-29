`ifndef VLM_RESERVATION_TYPES_SVH
`define VLM_RESERVATION_TYPES_SVH

//------------------------------------------------------------------------------
// @brief Selects the independently scheduled read or write reservation table.
//------------------------------------------------------------------------------
typedef enum bit {
  VLM_RESERVATION_READ  = 1'b0,
  VLM_RESERVATION_WRITE = 1'b1
} vlm_reservation_direction_e;

// Number of independently scheduled reservation directions.
localparam int unsigned VLM_RESERVATION_DIRECTION_N = 2;

//------------------------------------------------------------------------------
// @brief Selects how the scheduler obtains external busy reservations.
//------------------------------------------------------------------------------
typedef enum bit [1:0] {
  VLM_EXTERNAL_BUSY_ALL_FREE = 2'b00,
  VLM_EXTERNAL_BUSY_DIRECTED = 2'b01,
  VLM_EXTERNAL_BUSY_RANDOM   = 2'b10
} vlm_external_busy_mode_e;

// Two-state busy table indexed by relative delay and sub-bank identifier.
typedef bit [VTAB_D-1:0][VLM_SUB_BANK_N-1:0] vlm_busy_table_t;

// Four-state busy table used only at the interface sampling boundary.
typedef logic [VTAB_D-1:0][VLM_SUB_BANK_N-1:0]
    vlm_raw_busy_table_t;

//------------------------------------------------------------------------------
// @brief Describes one fully known DUT reservation event.
//
// The monitor creates this event only when request, address, and delay are
// known. Semantic legality is checked later by the checker and scheduler.
//------------------------------------------------------------------------------
typedef struct {
  // Independently scheduled read or write direction.
  vlm_reservation_direction_e direction;

  // Physical BANK that issued the reservation.
  int unsigned bank_id;

  // Write reservation port index; read reservations use zero.
  int unsigned write_port;

  // BANK-local address carried by the reservation request.
  bit [BADDR_W-1:0] address;

  // Requested number of cycles from issue to the actual MEM request.
  int unsigned delay;
} vlm_reservation_event_t;

// Queue of fully known reservation events sampled in one cycle.
typedef vlm_reservation_event_t vlm_reservation_event_queue_t[$];

//------------------------------------------------------------------------------
// @brief Describes one fully known actual MEM request event.
//
// Data, strobe, and read-response information are intentionally excluded from
// reservation-to-MEM matching.
//------------------------------------------------------------------------------
typedef struct {
  // Actual MEM read or write direction.
  vlm_reservation_direction_e direction;

  // Physical BANK that issued the actual MEM request.
  int unsigned bank_id;

  // BANK-local address carried by the actual MEM request.
  bit [BADDR_W-1:0] address;
} vlm_memory_request_event_t;

// Queue of fully known actual MEM requests sampled in one cycle.
typedef vlm_memory_request_event_t vlm_memory_request_event_queue_t[$];

//------------------------------------------------------------------------------
// @brief Describes one accepted DUT reservation stored in an SHM busy slot.
//
// Direction, relative delay, and sub-bank identifier are represented by the
// indices of the queue containing this record.
//------------------------------------------------------------------------------
typedef struct {
  // Physical BANK that issued the accepted reservation.
  int unsigned bank_id;

  // Reservation write-port index; read reservations use zero.
  int unsigned write_port;

  // Known BANK-local, 32-byte-aligned address reserved by the DUT.
  bit [BADDR_W-1:0] address;

  // Global clk_if cycle in which the reservation request was sampled.
  longint unsigned issue_cycle;

  // Global clk_if cycle in which the matching MEM request must occur.
  longint unsigned due_cycle;
} vlm_shm_record_t;

// Queue of DUT records sharing one direction, delay, and sub-bank slot.
typedef vlm_shm_record_t vlm_shm_record_queue_t[$];

//------------------------------------------------------------------------------
// @brief Captures raw four-state interface values from one sampling edge.
//
// This type is private to the monitor-facing sampling path. Scheduler,
// checker, and coverage APIs consume only the normalized two-state
// transaction.
//------------------------------------------------------------------------------
typedef struct {
  // Global clk_if cycle associated with the sampling edge.
  longint unsigned cycle;

  // Busy values observed at the DUT interface, indexed by direction.
  vlm_raw_busy_table_t observed_busy[VLM_RESERVATION_DIRECTION_N];

  // Per-BANK read reservation valid signals.
  logic [BANK_N-1:0] rreq;

  // Per-BANK read reservation addresses.
  logic [BANK_N-1:0][BADDR_W-1:0] raddr;

  // Per-BANK read reservation delays.
  logic [BANK_N-1:0][$clog2(VTAB_D)-1:0] rdly;

  // Per-BANK and per-port write reservation valid signals.
  logic [BANK_N-1:0][WRITE_PORT_N-1:0] wreq;

  // Per-BANK and per-port write reservation addresses.
  logic [BANK_N-1:0][WRITE_PORT_N-1:0][BADDR_W-1:0] waddr;

  // Per-BANK and per-port write reservation delays.
  logic [BANK_N-1:0][WRITE_PORT_N-1:0][$clog2(VTAB_D)-1:0] wdly;

  // Per-BANK actual MEM read request valid signals.
  logic [BANK_N-1:0] mem_rvld;

  // Per-BANK actual MEM read request addresses.
  logic [BANK_N-1:0][BADDR_W-1:0] mem_raddr;

  // Per-BANK actual MEM write request valid signals.
  logic [BANK_N-1:0] mem_wvld;

  // Per-BANK actual MEM write request addresses.
  logic [BANK_N-1:0][BADDR_W-1:0] mem_waddr;
} vlm_reservation_raw_sample_t;

//------------------------------------------------------------------------------
// @brief Carries one normalized two-state reservation/MEM cycle transaction.
//
// The cycle is a snapshot of clk_if.cycle_count, not an independently
// maintained counter. Known semantic violations remain as events for checker
// diagnosis, while ports containing unknown valid or active payload values do
// not create events.
//------------------------------------------------------------------------------
typedef struct {
  // Global clk_if cycle associated with all events in this transaction.
  longint unsigned cycle;

  // Known two-state busy values observed at the reservation interface.
  vlm_busy_table_t observed_busy[VLM_RESERVATION_DIRECTION_N];

  // Per-bit mask identifying observed busy positions that contained no X/Z.
  vlm_busy_table_t observed_busy_known[VLM_RESERVATION_DIRECTION_N];

  // Fully known read and write reservation events sampled in this cycle.
  vlm_reservation_event_queue_t reservation_events;

  // Fully known actual MEM read and write events sampled in this cycle.
  vlm_memory_request_event_queue_t memory_request_events;

  // Set when the monitor detects any unknown valid, active payload, or busy.
  bit input_error;
} vlm_reservation_cycle_transaction_t;

`endif // VLM_RESERVATION_TYPES_SVH
