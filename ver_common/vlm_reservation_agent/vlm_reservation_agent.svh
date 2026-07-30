`ifndef VLM_RESERVATION_AGENT_SVH
`define VLM_RESERVATION_AGENT_SVH

//------------------------------------------------------------------------------
// @brief Coordinates reservation sampling, checking, coverage, and scheduling.
//
// Owns the monitor, checker, coverage collector, and scheduler. Its main_phase
// is the only core cycle loop and always operates actively: it samples one
// normalized transaction, checks and covers the pre-update state, updates the
// scheduler, and drives busy for the next cycle. It never drives MEM data.
//------------------------------------------------------------------------------
class vlm_reservation_agent extends uvm_agent;

  // Minimal interface configuration obtained through UVM Config DB.
  vlm_reservation_agent_config cfg;

  // Reservation interface observed for requests and driven for busy.
  virtual vlm_reservation_interface reservation_vif;

  // Read-only MEM interface used only for actual request valid and address.
  virtual vlm_memory_interface memory_vif;

  // Component owning four-state sampling and two-state normalization.
  vlm_reservation_monitor monitor;

  // Component checking reservation protocol and reservation-to-MEM matching.
  vlm_reservation_checker reservation_checker;

  // Component sampling functional coverage before scheduler state mutation.
  vlm_reservation_coverage coverage;

  // Component owning external busy, SHM records, and final busy generation.
  vlm_reservation_scheduler scheduler;

  // Most recent normalized transaction returned by the monitor.
  vlm_reservation_cycle_transaction_t current_txn;

  // Detailed checker result associated with current_txn.
  vlm_reservation_check_result_t current_check_result;

  //------------------------------------------------------------------------------
  // @brief Constructs the VLM reservation agent.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this agent.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_reservation_agent",
      uvm_component parent = null);

  //------------------------------------------------------------------------------
  // @brief Obtains interface configuration and builds every child component.
  //
  // @param phase UVM build phase used to construct the active agent hierarchy.
  // @post Monitor, checker, coverage, and scheduler are all available.
  //------------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Connects interfaces and scheduler state views between components.
  //
  // @param phase UVM connect phase used to establish component relationships.
  // @post Monitor owns both business vif handles; checker and coverage refer to
  //       the scheduler owned by this agent.
  //------------------------------------------------------------------------------
  extern virtual function void connect_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Runs the single active reservation loop in UVM main phase.
  //
  // @param phase UVM main phase controlling the agent task lifetime.
  // @post Every collected transaction is checked, covered, scheduled, and
  //       followed by a busy drive for the next interface cycle.
  //------------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Processes one transaction in checker, coverage, scheduler order.
  //
  // @param txn Two-state reservation and MEM transaction for one cycle.
  // @pre Scheduler still exposes the state sampled in txn.
  // @post current_check_result contains the checker outcome and scheduler final
  //       busy is prepared for the next drive.
  //------------------------------------------------------------------------------
  extern function void process_cycle(
      const ref vlm_reservation_cycle_transaction_t txn);

  //------------------------------------------------------------------------------
  // @brief Drives scheduler final busy onto the reservation interface.
  //
  // @pre Scheduler final busy represents the next interface cycle.
  // @post Read and write busy outputs equal the scheduler final busy tables.
  //------------------------------------------------------------------------------
  extern protected function void drive_busy();

  `uvm_component_utils(vlm_reservation_agent)

endclass : vlm_reservation_agent

`endif // VLM_RESERVATION_AGENT_SVH
