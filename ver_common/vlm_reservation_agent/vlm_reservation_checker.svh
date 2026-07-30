`ifndef VLM_RESERVATION_CHECKER_SVH
`define VLM_RESERVATION_CHECKER_SVH

//------------------------------------------------------------------------------
// @brief Checks reservation semantics, busy ownership, and MEM correspondence.
//
// Consumes the monitor's normalized transaction and the scheduler's pre-update
// state. It checks two-state protocol semantics and exact reservation-to-MEM
// matching. Four-state diagnosis and MEM data checking remain outside this
// component.
//------------------------------------------------------------------------------
class vlm_reservation_checker extends uvm_component;

  // Shared cycle-number service obtained directly through UVM Config DB.
  virtual clk_if clk_vif;

  // Read-only scheduler handle assigned directly by the containing agent.
  vlm_reservation_scheduler scheduler;

  // Detailed checker result associated with the most recently checked cycle.
  vlm_reservation_check_result_t current_result;

  // Total number of reservation protocol violations since construction.
  longint unsigned reservation_error_count;

  // Total number of scheduler busy-state violations since construction.
  longint unsigned busy_error_count;

  // Total number of reservation-to-MEM matching violations since construction.
  longint unsigned mem_match_error_count;

  // Total number of unsupported dly-zero reservations since construction.
  longint unsigned dly_zero_error_count;

  // Total number of MEM requests matched to unique due records since construction.
  longint unsigned matched_mem_request_count;

  //------------------------------------------------------------------------------
  // @brief Constructs the reservation checker component.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this checker.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_reservation_checker",
      uvm_component parent = null);

  //------------------------------------------------------------------------------
  // @brief Obtains the shared clk_if from UVM Config DB.
  //
  // @param phase UVM build phase used to resolve component dependencies.
  // @post clk_vif refers to the repository-wide clock service or a fatal
  //       configuration error has been reported.
  //------------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Runs every reservation check for one normalized cycle transaction.
  //
  // @param txn Reservation, busy, and MEM requests sampled in one cycle.
  // @pre Scheduler exposes its pre-update state for txn.cycle.
  // @return Detailed per-cycle counts and the aggregate pass/fail result.
  //------------------------------------------------------------------------------
  extern function vlm_reservation_check_result_t check_cycle(
      const ref vlm_reservation_cycle_transaction_t txn);

  //------------------------------------------------------------------------------
  // @brief Initializes the result accumulated by one check_cycle() call.
  //
  // @param result Result object to clear before individual checker categories run.
  // @post All per-cycle counts are zero and passed is provisionally set.
  //------------------------------------------------------------------------------
  extern protected function void initialize_result(
      ref vlm_reservation_check_result_t result);

  //------------------------------------------------------------------------------
  // @brief Checks external/SHM ownership, records, and observed final busy.
  //
  // @param txn    Transaction containing normalized observed busy values.
  // @param result Per-cycle result updated for every detected violation.
  // @pre Scheduler exposes busy and record state for txn.cycle.
  //------------------------------------------------------------------------------
  extern protected function void check_busy_state(
      const ref vlm_reservation_cycle_transaction_t txn,
      ref       vlm_reservation_check_result_t      result);

  //------------------------------------------------------------------------------
  // @brief Checks all known read and write reservation requests in one cycle.
  //
  // @param txn    Transaction containing fixed BANK and write-port request arrays.
  // @param result Per-cycle result updated for every detected violation.
  // @pre Scheduler exposes its state before accepting reservations from txn.
  //------------------------------------------------------------------------------
  extern protected function void check_reservation_requests(
      const ref vlm_reservation_cycle_transaction_t txn,
      ref       vlm_reservation_check_result_t      result);

  //------------------------------------------------------------------------------
  // @brief Checks one fully known reservation request against the current state.
  //
  // @param direction  Read or write reservation direction.
  // @param bank       BANK array index carrying the request.
  // @param write_port Write-port index; zero for read reservations.
  // @param rsv        Read-only request instance created by the monitor.
  // @param txn        Transaction containing observed busy and sibling requests.
  // @param result     Per-cycle result updated for every detected violation.
  // @return 1 when the request is legal and schedulable; otherwise 0.
  //------------------------------------------------------------------------------
  extern protected function bit check_reservation_request(
      vlm_reservation_direction_e                 direction,
      int unsigned                                bank,
      int unsigned                                write_port,
      const ref vlm_rsv_req                       rsv,
      const ref vlm_reservation_cycle_transaction_t txn,
      ref       vlm_reservation_check_result_t      result);

  //------------------------------------------------------------------------------
  // @brief Checks actual MEM requests against records due in the sampled cycle.
  //
  // @param txn    Transaction containing fixed per-BANK MEM request arrays.
  // @param result Per-cycle result updated for every match or violation.
  // @pre Scheduler delay-zero records represent txn.cycle.
  //------------------------------------------------------------------------------
  extern protected function void check_mem_requests(
      const ref vlm_reservation_cycle_transaction_t txn,
      ref       vlm_reservation_check_result_t      result);

  //------------------------------------------------------------------------------
  // @brief Checks one BANK's MEM request and due record in one direction.
  //
  // @param direction Read or write MEM direction.
  // @param bank      BANK array index shared by the request and due record.
  // @param req       Nullable actual MEM request handle from the transaction.
  // @param rec       Nullable scheduler record due in the sampled cycle.
  // @param txn       Transaction providing the current cycle number.
  // @param result    Per-cycle result updated for a match or violation.
  //------------------------------------------------------------------------------
  extern protected function void check_mem_request_pair(
      vlm_reservation_direction_e                 direction,
      int unsigned                                bank,
      const ref vlm_mem_req                       req,
      const ref vlm_shm_record_t                  rec,
      const ref vlm_reservation_cycle_transaction_t txn,
      ref       vlm_reservation_check_result_t      result);

  `uvm_component_utils(vlm_reservation_checker)

endclass : vlm_reservation_checker

`endif // VLM_RESERVATION_CHECKER_SVH
