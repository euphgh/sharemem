`ifndef VLM_RESERVATION_CHECKER_SVH
`define VLM_RESERVATION_CHECKER_SVH

//------------------------------------------------------------------------------
// @brief Checks reservation protocol, busy ownership, and MEM request matching.
//
// Consumes the cycle controller's atomic sample and a read-only scheduler view.
// It verifies dly, address, sub-bank, external/SHM ownership, and exact
// reservation-to-MEM correspondence. It does not check MEM data, strobe, or
// read-response timing.
//------------------------------------------------------------------------------
class vlm_reservation_checker extends uvm_component;

  // Agent configuration controlling checker enable and active/passive policy.
  vlm_reservation_agent_config cfg;

  // Read-only scheduler handle used to query busy origin and due records.
  vlm_reservation_scheduler scheduler;

  // Number of reservation protocol violations observed since the last reset.
  int unsigned reservation_error_count;

  // Number of scheduler busy-state violations observed since the last reset.
  int unsigned busy_error_count;

  // Number of reservation-to-MEM matching violations since the last reset.
  int unsigned mem_match_error_count;

  // Number of unsupported dly-zero reservations observed since the last reset.
  int unsigned dly_zero_error_count;

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
  // @brief Clears checker counters and transient matching state.
  //
  // @post No pre-reset observation contributes to subsequent error totals.
  //------------------------------------------------------------------------------
  extern function void reset_state();

  //------------------------------------------------------------------------------
  // @brief Runs all enabled checks for one atomically sampled active cycle.
  //
  // @param sample Reservation, busy, and MEM request values for one cycle.
  // @pre scheduler exposes the state corresponding to sample.cycle_id.
  // @return 1 when all enabled checks pass for the cycle; otherwise 0.
  //------------------------------------------------------------------------------
  extern function bit check_cycle(
      const ref vlm_reservation_cycle_sample_t sample);

  //------------------------------------------------------------------------------
  // @brief Checks external/SHM ownership and the final driven busy values.
  //
  // @param sample Cycle sample containing the busy values observed by the DUT.
  // @pre scheduler exposes busy state for sample.cycle_id.
  // @post Busy-source and driven-value violations update busy_error_count.
  //------------------------------------------------------------------------------
  extern function void check_busy_state(
      const ref vlm_reservation_cycle_sample_t sample);

  //------------------------------------------------------------------------------
  // @brief Checks all read and write reservation requests in one cycle.
  //
  // @param sample Cycle sample containing reservation req, addr, and dly.
  // @post Protocol violations update the corresponding checker counters.
  //------------------------------------------------------------------------------
  extern function void check_reservation_requests(
      const ref vlm_reservation_cycle_sample_t sample);

  //------------------------------------------------------------------------------
  // @brief Checks actual MEM requests against records due in the sampled cycle.
  //
  // @param sample Cycle sample containing MEM valid and address signals.
  // @pre scheduler delay-zero records represent reservations due this cycle.
  // @post Missing, unexpected, duplicate, or mismatched requests are counted.
  //------------------------------------------------------------------------------
  extern function void check_mem_requests(
      const ref vlm_reservation_cycle_sample_t sample);

  //------------------------------------------------------------------------------
  // @brief Returns the total number of checker errors since the last reset.
  //
  // @return Sum of reservation, busy, MEM-match, and dly-zero error counters.
  //------------------------------------------------------------------------------
  extern function int unsigned get_error_count();

  `uvm_component_utils(vlm_reservation_checker)

endclass : vlm_reservation_checker

`endif // VLM_RESERVATION_CHECKER_SVH
