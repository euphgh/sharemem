`ifndef VLM_RESERVATION_CHECKER_SVH
`define VLM_RESERVATION_CHECKER_SVH

//------------------------------------------------------------------------------
// @brief Checks reservation semantics, busy ownership, and MEM correspondence.
//
// Consumes the monitor's normalized transaction and a read-only scheduler
// view. It checks known protocol events and exact reservation-to-MEM matching.
// Four-state interface diagnosis belongs to the monitor; MEM data, strobe, and
// read-response timing remain outside this component.
//------------------------------------------------------------------------------
class vlm_reservation_checker extends uvm_component;

  // Agent configuration controlling checker enable and active/passive policy.
  vlm_reservation_agent_config cfg;

  // Shared cycle-number service obtained directly through UVM Config DB.
  virtual clk_if clk_vif;

  // Read-only scheduler handle used to query busy origin and due records.
  vlm_reservation_scheduler scheduler;

  // Number of reservation protocol violations observed since construction.
  int unsigned reservation_error_count;

  // Number of scheduler busy-state violations observed since construction.
  int unsigned busy_error_count;

  // Number of reservation-to-MEM matching violations since construction.
  int unsigned mem_match_error_count;

  // Number of unsupported dly-zero reservations observed since construction.
  int unsigned dly_zero_error_count;

  // Number of cycle transactions containing monitor input errors.
  int unsigned input_error_cycle_count;

  // Number of MEM requests successfully matched to unique due records.
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
  // @post clk_vif refers to the environment clock service or a fatal
  //       configuration error has been reported.
  //------------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Assigns the agent configuration used to enable checker behavior.
  //
  // @param cfg Configuration handle shared by the reservation agent.
  // @pre cfg is non-null and remains valid for the checker lifetime.
  // @post Subsequent checks use the supplied configuration.
  //------------------------------------------------------------------------------
  extern function void set_config(vlm_reservation_agent_config cfg);

  //------------------------------------------------------------------------------
  // @brief Assigns the scheduler that owns busy state and SHM records.
  //
  // @param scheduler Scheduler handle queried by all checker APIs.
  // @pre scheduler is non-null and represents the same reservation interface.
  // @post Checker state queries are directed to the supplied scheduler.
  //------------------------------------------------------------------------------
  extern function void set_scheduler(
      vlm_reservation_scheduler scheduler);

  //------------------------------------------------------------------------------
  // @brief Runs all enabled checks for one normalized cycle transaction.
  //
  // @param transaction Reservation, busy, and MEM request events for one cycle.
  // @pre Scheduler still exposes its pre-update state for transaction.cycle.
  // @return 1 when all enabled checks pass for the cycle; otherwise 0.
  //------------------------------------------------------------------------------
  extern function bit check_cycle(
      const ref vlm_reservation_cycle_transaction_t transaction);

  //------------------------------------------------------------------------------
  // @brief Accounts for interface errors already reported by the monitor.
  //
  // @param transaction Transaction containing the monitor input_error status.
  // @post Transactions with input_error increment input_error_cycle_count.
  //------------------------------------------------------------------------------
  extern function void check_monitor_input_status(
      const ref vlm_reservation_cycle_transaction_t transaction);

  //------------------------------------------------------------------------------
  // @brief Checks external/SHM ownership and observed final busy values.
  //
  // @param transaction Transaction containing observed busy and known masks.
  // @pre Scheduler exposes busy state for transaction.cycle.
  // @post Busy-source and driven-value violations update busy_error_count.
  //------------------------------------------------------------------------------
  extern function void check_busy_state(
      const ref vlm_reservation_cycle_transaction_t transaction);

  //------------------------------------------------------------------------------
  // @brief Checks all known read and write reservation events in one cycle.
  //
  // @param transaction Transaction containing normalized reservation events.
  // @post Semantic violations update the corresponding checker counters.
  //------------------------------------------------------------------------------
  extern function void check_reservation_requests(
      const ref vlm_reservation_cycle_transaction_t transaction);

  //------------------------------------------------------------------------------
  // @brief Checks actual MEM requests against records due in the sampled cycle.
  //
  // @param transaction Transaction containing normalized MEM request events.
  // @pre Scheduler delay-zero records represent transaction.cycle.
  // @post Missing, unexpected, duplicate, or mismatched requests are counted.
  //------------------------------------------------------------------------------
  extern function void check_mem_requests(
      const ref vlm_reservation_cycle_transaction_t transaction);

  //------------------------------------------------------------------------------
  // @brief Returns the total number of checker errors since construction.
  //
  // @return Sum of reservation, busy, MEM-match, dly-zero, and monitor-input
  //         error-cycle counters.
  //------------------------------------------------------------------------------
  extern function int unsigned get_error_count();

  `uvm_component_utils(vlm_reservation_checker)

endclass : vlm_reservation_checker

`endif // VLM_RESERVATION_CHECKER_SVH
