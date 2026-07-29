`ifndef VLM_RESERVATION_AGENT_SVH
`define VLM_RESERVATION_AGENT_SVH

//------------------------------------------------------------------------------
// @brief Coordinates VLM reservation sampling, checking, scheduling, and busy.
//
// Owns the reservation-side monitor, scheduler, checker, and coverage
// components. Its main_phase is the only core cycle-processing loop: it obtains
// one normalized transaction from the monitor, invokes the other components in
// a deterministic order, and drives final reservation busy in active mode. It
// observes MEM request valid and address but never drives or checks MEM data.
//------------------------------------------------------------------------------
class vlm_reservation_agent extends uvm_agent;

  // Shared configuration defining business interfaces, mode, and enables.
  vlm_reservation_agent_config cfg;

  // Reservation interface observed for requests and driven for busy.
  virtual vlm_reservation_interface reservation_vif;

  // Read-only MEM interface used only for actual request valid and addresses.
  virtual vlm_memory_interface memory_vif;

  // Component owning four-state sampling and two-state normalization.
  vlm_reservation_monitor monitor;

  // Component maintaining external/SHM busy tables and accepted DUT records.
  vlm_reservation_scheduler scheduler;

  // Component checking reservation protocol and reservation-to-MEM matching.
  vlm_reservation_checker reservation_checker;

  // Component exposing the reservation functional coverage sampling API.
  vlm_reservation_coverage coverage;

  // Most recent normalized transaction returned by the monitor.
  vlm_reservation_cycle_transaction_t current_transaction;

  // Checker pass/fail result associated with current_transaction.
  bit current_cycle_check_passed;

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
  // @brief Builds enabled child components and obtains agent configuration.
  //
  // @param phase UVM build phase used to construct the agent hierarchy.
  // @post Monitor and scheduler are available; checker and coverage are
  //       constructed according to their enable fields in cfg.
  //------------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Connects config, monitor, scheduler, checker, and coverage APIs.
  //
  // @param phase UVM connect phase used to establish component relationships.
  // @post All constructed children use the same business interfaces and
  //       scheduler state owner.
  //------------------------------------------------------------------------------
  extern virtual function void connect_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Runs the single reservation reactive loop in UVM main phase.
  //
  // @param phase UVM main phase controlling the agent task lifetime.
  // @post Each collected transaction is checked, scheduled, covered, and
  //       followed by a final busy drive when the agent is active.
  //------------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Processes one normalized transaction in deterministic component order.
  //
  // Calls the checker before scheduler mutation, then updates the scheduler and
  // samples coverage using the same transaction and checker result.
  //
  // @param transaction Two-state reservation/MEM transaction for one cycle.
  // @post current_cycle_check_passed records the checker result and scheduler
  //       final busy is prepared for drive_busy().
  //------------------------------------------------------------------------------
  extern function void process_cycle(
      const ref vlm_reservation_cycle_transaction_t transaction);

  //------------------------------------------------------------------------------
  // @brief Drives scheduler final busy values onto the reservation interface.
  //
  // @pre scheduler final busy tables represent the next interface cycle.
  // @post In active mode, read and write busy outputs contain scheduler final
  //       busy; passive mode leaves interface outputs untouched.
  //------------------------------------------------------------------------------
  extern task drive_busy();

  //------------------------------------------------------------------------------
  // @brief Assigns an explicit configuration before child construction.
  //
  // @param cfg Configuration handle to use for this agent and all children.
  // @pre cfg is non-null and validate() returns 1.
  // @post reservation_vif and memory_vif are taken from the supplied config.
  //------------------------------------------------------------------------------
  extern function void set_config(vlm_reservation_agent_config cfg);

  `uvm_component_utils(vlm_reservation_agent)

endclass : vlm_reservation_agent

//------------------------------------------------------------------------------
// vlm_reservation_agent method implementations
//------------------------------------------------------------------------------

function void vlm_reservation_agent::process_cycle(
    const ref vlm_reservation_cycle_transaction_t transaction);
  current_transaction        = transaction;
  current_cycle_check_passed = 1'b1;

  if (scheduler == null) begin
    `uvm_fatal(
        "VLM_RESERVATION_NO_SCHEDULER",
        "process_cycle() requires a constructed reservation scheduler")
    return;
  end

  if (reservation_checker != null) begin
    current_cycle_check_passed =
        reservation_checker.check_cycle(current_transaction);
  end

  scheduler.process_cycle(current_transaction);

  if (coverage != null) begin
    coverage.sample_cycle(
        current_transaction,
        current_cycle_check_passed);
  end
endfunction : process_cycle

task vlm_reservation_agent::drive_busy();
  if (cfg == null) begin
    `uvm_fatal(
        "VLM_RESERVATION_NO_CFG",
        "drive_busy() requires a valid agent configuration")
    return;
  end

  if (cfg.is_active == UVM_PASSIVE) begin
    return;
  end

  if (reservation_vif == null) begin
    `uvm_fatal(
        "VLM_RESERVATION_NO_VIF",
        "active drive_busy() requires reservation_vif")
    return;
  end

  if (scheduler == null) begin
    `uvm_fatal(
        "VLM_RESERVATION_NO_SCHEDULER",
        "active drive_busy() requires a reservation scheduler")
    return;
  end

  reservation_vif.rbusy <= scheduler.final_busy[VLM_RESERVATION_READ];
  reservation_vif.wbusy <= scheduler.final_busy[VLM_RESERVATION_WRITE];
endtask : drive_busy

task vlm_reservation_agent::main_phase(uvm_phase phase);
  super.main_phase(phase);

  if (monitor == null) begin
    `uvm_fatal(
        "VLM_RESERVATION_NO_MONITOR",
        "main_phase requires a constructed reservation monitor")
    return;
  end

  if (scheduler == null) begin
    `uvm_fatal(
        "VLM_RESERVATION_NO_SCHEDULER",
        "main_phase requires a constructed reservation scheduler")
    return;
  end

  // Establish a known initial value before the first sampled clock edge.
  drive_busy();

  forever begin
    monitor.collect_cycle(current_transaction);
    process_cycle(current_transaction);
    drive_busy();
  end
endtask : main_phase

`endif // VLM_RESERVATION_AGENT_SVH
