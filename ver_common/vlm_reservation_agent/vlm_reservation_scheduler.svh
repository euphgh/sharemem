`ifndef VLM_RESERVATION_SCHEDULER_SVH
`define VLM_RESERVATION_SCHEDULER_SVH

//------------------------------------------------------------------------------
// @brief Maintains the cycle-relative VLM reservation busy schedule.
//
// Separately tracks external and DUT-owned SHM busy slots for read and write
// directions. It accepts legal known reservation events and prepares the next
// final busy tables for the agent. It does not sample interfaces, drive busy,
// inspect MEM data, or decide whether an actual MEM request satisfies a record.
//------------------------------------------------------------------------------
class vlm_reservation_scheduler extends uvm_component;

  // Agent configuration assigned directly by the containing agent.
  vlm_reservation_agent_config cfg;

  // Shared cycle-number service obtained directly through UVM Config DB.
  virtual clk_if clk_vif;

  // External occupancy indexed by direction, relative delay, and sub bank.
  vlm_busy_table_t external_busy[VLM_RESERVATION_DIRECTION_N];

  // DUT-owned occupancy derived from record addresses by direction and delay.
  vlm_busy_table_t shm_busy[VLM_RESERVATION_DIRECTION_N];

  // Published busy values derived exactly as external_busy OR shm_busy.
  vlm_busy_table_t final_busy[VLM_RESERVATION_DIRECTION_N];

  // Accepted DUT reservations indexed by direction, relative delay, and BANK.
  // One nullable handle per BANK enforces one due request per direction and BANK.
  vlm_shm_record_t shm_records[VLM_RESERVATION_DIRECTION_N][VTAB_D][BANK_N];

  // Indicates whether last_processed_cycle contains a valid transaction cycle.
  bit has_processed_cycle;

  // Cycle snapshot from the most recently processed transaction.
  longint unsigned last_processed_cycle;

  // Total number of DUT reservation records accepted since construction.
  longint unsigned accepted_record_count;

  // Total number of newly generated external busy slots since construction.
  longint unsigned generated_external_slot_count;

  //------------------------------------------------------------------------------
  // @brief Constructs the reservation scheduler component.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this scheduler.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_reservation_scheduler",
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
  // @brief Advances the schedule from one normalized cycle transaction.
  //
  // Consumes due records, advances the busy window, admits legal reservations,
  // applies the configured external policy, and prepares final_busy for the
  // next cycle. Known but illegal events are not committed to scheduler state.
  //
  // @param txn Two-state reservation/MEM transaction for one cycle.
  // @pre txn.cycle equals the current shared clk_if cycle.
  // @post last_processed_cycle equals txn.cycle and final_busy is prepared
  //       for the agent's next busy drive.
  //------------------------------------------------------------------------------
  extern function void process_cycle(
      const ref vlm_reservation_cycle_transaction_t txn);

  `uvm_component_utils(vlm_reservation_scheduler)

endclass : vlm_reservation_scheduler

`endif // VLM_RESERVATION_SCHEDULER_SVH
