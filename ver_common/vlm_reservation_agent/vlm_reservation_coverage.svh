`ifndef VLM_RESERVATION_COVERAGE_SVH
`define VLM_RESERVATION_COVERAGE_SVH

//------------------------------------------------------------------------------
// @brief Defines the coverage-facing API for reservation scheduling behavior.
//
// Receives the same atomic cycle sample used by scheduler and checker and
// observes scheduler ownership state. The current API-shape stage declares no
// covergroups and does not influence scheduler or checker state.
//------------------------------------------------------------------------------
class vlm_reservation_coverage extends uvm_component;

  // Agent configuration controlling whether coverage sampling is enabled.
  vlm_reservation_agent_config cfg;

  // Read-only scheduler handle providing busy source and slot occupancy data.
  vlm_reservation_scheduler scheduler;

  // Number of active cycles presented to the coverage API since reset.
  longint unsigned sampled_cycle_count;

  // Number of legal cycles containing multiple BANKs in one SHM slot.
  longint unsigned shared_shm_slot_cycle_count;

  // Number of reservation attempts blocked by external busy ownership.
  longint unsigned external_block_count;

  // Number of unsupported dly-zero reservation requests observed.
  longint unsigned dly_zero_sample_count;

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
  // @brief Assigns the configuration controlling coverage enable behavior.
  //
  // @param cfg Configuration handle shared by the reservation agent.
  // @pre cfg is non-null and remains valid for the collector lifetime.
  // @post Subsequent samples honor cfg.coverage_enable.
  //------------------------------------------------------------------------------
  extern function void set_config(vlm_reservation_agent_config cfg);

  //------------------------------------------------------------------------------
  // @brief Assigns the scheduler used for read-only occupancy observations.
  //
  // @param scheduler Scheduler associated with the sampled reservation agent.
  // @pre scheduler is non-null and corresponds to the same cycle controller.
  // @post Coverage queries use the supplied scheduler.
  //------------------------------------------------------------------------------
  extern function void set_scheduler(
      vlm_reservation_scheduler scheduler);

  //------------------------------------------------------------------------------
  // @brief Clears coverage-facing counters and transient sample state.
  //
  // @post No counter retains observations from before the reset.
  //------------------------------------------------------------------------------
  extern function void reset_state();

  //------------------------------------------------------------------------------
  // @brief Samples reservation behavior and scheduler ownership for one cycle.
  //
  // @param sample             Atomic reservation and MEM request cycle sample.
  // @param cycle_check_passed Result returned by the checker for this cycle.
  // @pre scheduler state and sample refer to the same cycle identifier.
  // @post Coverage counters reflect all enabled observations in this cycle.
  //------------------------------------------------------------------------------
  extern function void sample_cycle(
      const ref vlm_reservation_cycle_sample_t sample,
      bit                                      cycle_check_passed);

  //------------------------------------------------------------------------------
  // @brief Returns the number of active cycles presented to this collector.
  //
  // @return Sampled active-cycle count since the most recent reset.
  //------------------------------------------------------------------------------
  extern function longint unsigned get_sampled_cycle_count();

  `uvm_component_utils(vlm_reservation_coverage)

endclass : vlm_reservation_coverage

`endif // VLM_RESERVATION_COVERAGE_SVH
