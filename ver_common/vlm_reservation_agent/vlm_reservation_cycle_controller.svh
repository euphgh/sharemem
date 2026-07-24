`ifndef VLM_RESERVATION_CYCLE_CONTROLLER_SVH
`define VLM_RESERVATION_CYCLE_CONTROLLER_SVH

//------------------------------------------------------------------------------
// @brief Coordinates cycle-accurate reservation sampling and busy updates.
//
// Owns the common cycle identifier, atomically samples reservation and MEM
// request interfaces, invokes scheduler/checker/coverage in a defined cycle,
// and drives reservation busy. It never drives or checks MEM read data.
//------------------------------------------------------------------------------
class vlm_reservation_cycle_controller extends uvm_component;

  // Agent configuration containing both virtual interfaces and mode controls.
  vlm_reservation_agent_config cfg;

  // Reservation interface sampled for requests and driven for busy values.
  virtual vlm_reservation_interface reservation_vif;

  // Read-only MEM interface sampled for actual request valid and addresses.
  virtual vlm_memory_interface memory_vif;

  // Scheduler invoked to update busy ownership and produce final busy values.
  vlm_reservation_scheduler scheduler;

  // Checker invoked with the atomic cycle sample and scheduler state.
  vlm_reservation_checker reservation_checker;

  // Coverage collector invoked after checking each active cycle.
  vlm_reservation_coverage coverage;

  // Monotonic identifier assigned to each active cycle after reset release.
  longint unsigned cycle_id;

  // Most recent atomic sample shared with all internal components.
  vlm_reservation_cycle_sample_t current_sample;

  // Checker pass/fail result associated with current_sample.
  bit current_cycle_check_passed;

  //------------------------------------------------------------------------------
  // @brief Constructs the reservation cycle controller component.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this controller.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_reservation_cycle_controller",
      uvm_component parent = null);

  //------------------------------------------------------------------------------
  // @brief Assigns configuration and virtual interfaces to the controller.
  //
  // @param cfg Configuration handle shared by the reservation agent.
  // @pre cfg is valid and provides both required virtual interfaces.
  // @post reservation_vif and memory_vif refer to cfg interface handles.
  //------------------------------------------------------------------------------
  extern function void set_config(vlm_reservation_agent_config cfg);

  //------------------------------------------------------------------------------
  // @brief Connects the scheduler invoked by the cycle controller.
  //
  // @param scheduler Scheduler belonging to the same reservation agent.
  // @pre scheduler is non-null.
  // @post Each active cycle is forwarded to the supplied scheduler.
  //------------------------------------------------------------------------------
  extern function void set_scheduler(
      vlm_reservation_scheduler scheduler);

  //------------------------------------------------------------------------------
  // @brief Connects the checker invoked by the cycle controller.
  //
  // @param checker_handle Checker belonging to the same reservation agent.
  // @pre checker_handle is non-null when checking is enabled.
  // @post Each enabled active cycle is checked by the supplied component.
  //------------------------------------------------------------------------------
  extern function void set_checker(
      vlm_reservation_checker checker_handle);

  //------------------------------------------------------------------------------
  // @brief Connects the coverage collector invoked by the controller.
  //
  // @param coverage Coverage component belonging to the same reservation agent.
  // @pre coverage is non-null when coverage is enabled.
  // @post Each enabled active cycle is offered to the supplied collector.
  //------------------------------------------------------------------------------
  extern function void set_coverage(vlm_reservation_coverage coverage);

  //------------------------------------------------------------------------------
  // @brief Runs the cycle-accurate sample, process, and busy-drive loop.
  //
  // @param phase Active UVM run phase controlling this task's lifetime.
  // @post Reset cycles clear component state and drive known idle busy values.
  //------------------------------------------------------------------------------
  extern virtual task run_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Samples both interfaces into one cycle snapshot.
  //
  // @param sample Output snapshot receiving reservation, busy, and MEM request
  //               signals sampled for the same cycle.
  // @post sample.cycle_id equals the controller's current cycle identifier.
  //------------------------------------------------------------------------------
  extern task sample_interfaces(
      output vlm_reservation_cycle_sample_t sample);

  //------------------------------------------------------------------------------
  // @brief Coordinates checking, scheduler update, and coverage for one sample.
  //
  // @param sample Atomic cycle sample to distribute to internal components.
  // @pre sample was produced by sample_interfaces for the current active cycle.
  // @post Internal component state is prepared for the next busy drive.
  //------------------------------------------------------------------------------
  extern function void process_sample(
      const ref vlm_reservation_cycle_sample_t sample);

  //------------------------------------------------------------------------------
  // @brief Drives scheduler final busy values onto the reservation interface.
  //
  // @pre scheduler final busy tables represent the next interface cycle.
  // @post Read and write busy outputs are stable for the next sampling edge.
  //------------------------------------------------------------------------------
  extern task drive_busy();

  //------------------------------------------------------------------------------
  // @brief Resets controller, scheduler, checker, and coverage cycle state.
  //
  // @post cycle_id is reset and reservation busy is prepared as known idle.
  //------------------------------------------------------------------------------
  extern function void reset_state();

  //------------------------------------------------------------------------------
  // @brief Returns the active cycle identifier owned by this controller.
  //
  // @return Monotonic active-cycle identifier since the most recent reset.
  //------------------------------------------------------------------------------
  extern function longint unsigned get_cycle_id();

  `uvm_component_utils(vlm_reservation_cycle_controller)

endclass : vlm_reservation_cycle_controller

`endif // VLM_RESERVATION_CYCLE_CONTROLLER_SVH
