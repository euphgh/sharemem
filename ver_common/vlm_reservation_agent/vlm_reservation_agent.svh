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

function vlm_reservation_agent::new(string name = "vlm_reservation_agent", uvm_component parent = null);
  super.new(name, parent);
endfunction : new

function void vlm_reservation_agent::build_phase(uvm_phase phase);
  super.build_phase(phase);

  // The agent requires one configuration object containing both business interfaces.
  if (!uvm_config_db#(vlm_reservation_agent_config)::get(this, "", "cfg", cfg) || cfg == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_CFG",
               "vlm_reservation_agent requires vlm_reservation_agent_config under Config DB field 'cfg'")
  end

  // Both interfaces are mandatory because every cycle combines reservation and actual MEM observations.
  if (cfg.reservation_vif == null || cfg.memory_vif == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_VIF", "reservation agent config requires reservation_vif and memory_vif")
  end

  reservation_vif = cfg.reservation_vif;
  memory_vif      = cfg.memory_vif;

  // Always construct the complete active reservation hierarchy; passive mode is not supported yet.
  monitor             = vlm_reservation_monitor::type_id::create("monitor", this);
  reservation_checker = vlm_reservation_checker::type_id::create("reservation_checker", this);
  coverage            = vlm_reservation_coverage::type_id::create("coverage", this);
  scheduler           = vlm_reservation_scheduler::type_id::create("scheduler", this);
endfunction : build_phase

function void vlm_reservation_agent::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  // Give the monitor the same configuration already validated and retained by the agent.
  monitor.set_config(cfg);

  // Checker and coverage inspect the scheduler directly before its state is advanced for the next cycle.
  reservation_checker.scheduler = scheduler;
  coverage.scheduler             = scheduler;
endfunction : connect_phase

task vlm_reservation_agent::main_phase(uvm_phase phase);
  super.main_phase(phase);

  // Establish a deterministic all-idle busy value before the first sampled reservation cycle.
  drive_busy();

  forever begin
    // collect_cycle() is the only API in the reactive loop that consumes simulation time.
    monitor.collect_cycle(current_txn);

    // Checking, empty coverage sampling, scheduling, and driving all complete in the sampled cycle.
    process_cycle(current_txn);
    drive_busy();
  end
endtask : main_phase

function void vlm_reservation_agent::process_cycle(const ref vlm_reservation_cycle_transaction_t txn);
  // Preserve the latest normalized transaction for direct inspection and debug.
  current_txn = txn;

  // Checker and coverage must see the scheduler state that produced the busy sampled in txn.
  current_check_result = reservation_checker.check_cycle(txn);
  coverage.sample_cycle(txn, current_check_result);

  // Advance the window only after all current-cycle observations have been checked and sampled.
  scheduler.process_cycle(txn);
endfunction : process_cycle

function void vlm_reservation_agent::drive_busy();
  if (reservation_vif == null || scheduler == null) begin
    `uvm_fatal("VLM_RESERVATION_AGENT_NOT_READY", "drive_busy() requires reservation_vif and scheduler")
  end

  // Publish the scheduler's read and write tables together so the next edge observes one coherent window.
  reservation_vif.rbusy <= scheduler.final_busy[VLM_RESERVATION_READ];
  reservation_vif.wbusy <= scheduler.final_busy[VLM_RESERVATION_WRITE];
endfunction : drive_busy

`endif // VLM_RESERVATION_AGENT_SVH
