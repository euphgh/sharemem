`ifndef VLM_RESERVATION_COVERAGE_SVH
`define VLM_RESERVATION_COVERAGE_SVH

//------------------------------------------------------------------------------
// @brief Defines the coverage-facing API for reservation scheduling behavior.
//
// Receives the same normalized transaction used by scheduler and checker and
// observes scheduler ownership state. The current implementation is an empty
// placeholder: it declares no covergroups, leaves all counters at zero, and
// does not influence checker, scheduler, or busy-drive state.
//------------------------------------------------------------------------------
class vlm_reservation_coverage extends uvm_component;

  // Read-only scheduler handle assigned directly by the containing agent.
  vlm_reservation_scheduler scheduler;

  // Reserved cycle-sample counter; remains zero in the empty implementation.
  longint unsigned sampled_cycle_count;

  // Reserved shared-SHM-slot counter; remains zero in the empty implementation.
  longint unsigned shared_shm_slot_cycle_count;

  // Reserved external-block counter; remains zero in the empty implementation.
  longint unsigned external_block_count;

  // Reserved dly-zero counter; remains zero in the empty implementation.
  longint unsigned dly_zero_sample_count;

  // Reserved input-error counter; remains zero in the empty implementation.
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
  // @brief Accepts one cycle sample without collecting coverage yet.
  //
  // @param txn          Normalized reservation and MEM cycle transaction.
  // @param check_result Detailed result returned by the checker for this cycle.
  // @pre Scheduler state and transaction refer to the same cycle.
  // @post No coverage state, scheduler state, or checker state is changed.
  //------------------------------------------------------------------------------
  extern function void sample_cycle(
      const ref vlm_reservation_cycle_transaction_t txn,
      const ref vlm_reservation_check_result_t      check_result);

  `uvm_component_utils(vlm_reservation_coverage)

endclass : vlm_reservation_coverage

function vlm_reservation_coverage::new(string name = "vlm_reservation_coverage", uvm_component parent = null);
  super.new(name, parent);

  // Keep every reserved statistic deterministic until functional coverage is implemented.
  sampled_cycle_count         = 0;
  shared_shm_slot_cycle_count = 0;
  external_block_count        = 0;
  dly_zero_sample_count       = 0;
  input_error_cycle_count     = 0;
endfunction : new

function void vlm_reservation_coverage::sample_cycle(
    const ref vlm_reservation_cycle_transaction_t txn,
    const ref vlm_reservation_check_result_t      check_result);
  // Functional coverage is intentionally deferred; retain the synchronous API for agent integration.
endfunction : sample_cycle

`endif // VLM_RESERVATION_COVERAGE_SVH
