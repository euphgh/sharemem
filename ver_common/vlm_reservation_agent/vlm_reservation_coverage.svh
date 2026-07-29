`ifndef VLM_RESERVATION_COVERAGE_SVH
`define VLM_RESERVATION_COVERAGE_SVH

//------------------------------------------------------------------------------
// @brief Defines the coverage-facing API for reservation scheduling behavior.
//
// Receives the same normalized transaction used by scheduler and checker and
// observes scheduler ownership state. The current API-shape stage declares no
// covergroups and does not influence checker, scheduler, or busy-drive state.
//------------------------------------------------------------------------------
class vlm_reservation_coverage extends uvm_component;

  // Agent configuration assigned directly by the containing agent.
  vlm_reservation_agent_config cfg;

  // Read-only scheduler handle assigned directly by the containing agent.
  vlm_reservation_scheduler scheduler;

  // Number of cycle transactions presented to coverage since construction.
  longint unsigned sampled_cycle_count;

  // Number of legal cycles containing multiple BANKs in one SHM slot.
  longint unsigned shared_shm_slot_cycle_count;

  // Number of reservation attempts blocked by external busy ownership.
  longint unsigned external_block_count;

  // Number of unsupported dly-zero reservation events observed.
  longint unsigned dly_zero_sample_count;

  // Number of cycle transactions containing monitor input errors.
  longint unsigned input_error_cycle_count;

  //------------------------------------------------------------------------------
  // @brief Constructs the reservation coverage component.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this coverage collector.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_reservation_coverage",
      uvm_component parent = null);

  //------------------------------------------------------------------------------
  // @brief Samples one transaction and its checker result for coverage.
  //
  // @param transaction       Normalized reservation and MEM cycle transaction.
  // @param cycle_check_passed Result returned by the checker for this cycle.
  // @pre Scheduler state and transaction refer to the same cycle.
  // @post Coverage-facing counters include all enabled cycle observations.
  //------------------------------------------------------------------------------
  extern function void sample_cycle(
      const ref vlm_reservation_cycle_transaction_t transaction,
      bit                                           cycle_check_passed);

  `uvm_component_utils(vlm_reservation_coverage)

endclass : vlm_reservation_coverage

`endif // VLM_RESERVATION_COVERAGE_SVH
