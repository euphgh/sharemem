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

// Busy state indexed by relative delay and sub-bank identifier.
typedef logic [VTAB_D-1:0][VLM_SUB_BANK_N-1:0] vlm_busy_table_t;

//------------------------------------------------------------------------------
// @brief Describes one accepted DUT reservation stored in an SHM busy slot.
//
// Direction, relative delay, and sub-bank identifier are represented by the
// indices of the queue containing this record.
//------------------------------------------------------------------------------
typedef struct {
  // Physical BANK that issued the reservation.
  int unsigned bank_id;

  // Reservation write-port index; read reservations use zero.
  int unsigned write_port;

  // BANK-local, 32-byte-aligned address reserved by the DUT.
  logic [BADDR_W-1:0] address;

  // Cycle in which the DUT reservation request was sampled.
  longint unsigned issue_cycle;

  // Absolute cycle in which the matching MEM request must occur.
  longint unsigned due_cycle;
} vlm_shm_record_t;

// Queue of DUT records sharing one direction, delay, and sub-bank slot.
typedef vlm_shm_record_t vlm_shm_record_queue_t[$];

//------------------------------------------------------------------------------
// @brief Captures reservation and MEM request signals sampled in one cycle.
//
// The cycle controller creates this snapshot so scheduler, checker, and
// coverage components observe the same cycle without relying on TLM callback
// ordering. MEM read data and write payload are intentionally excluded.
//------------------------------------------------------------------------------
typedef struct {
  // Monotonic identifier assigned to the sampled active cycle.
  longint unsigned cycle_id;

  // Reset value sampled with the cycle; zero marks a reset cycle.
  logic rst_n;

  // Busy values observed at the DUT interface, indexed by direction.
  vlm_busy_table_t observed_busy[VLM_RESERVATION_DIRECTION_N];

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
} vlm_reservation_cycle_sample_t;

`endif // VLM_RESERVATION_TYPES_SVH
