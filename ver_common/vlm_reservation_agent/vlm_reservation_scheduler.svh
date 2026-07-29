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

  // Agent configuration controlling active mode and external busy policy.
  vlm_reservation_agent_config cfg;

  // Shared cycle-number service obtained directly through UVM Config DB.
  virtual clk_if clk_vif;

  // External occupancy indexed by direction, relative delay, and sub bank.
  vlm_busy_table_t external_busy[VLM_RESERVATION_DIRECTION_N];

  // DUT-owned occupancy indexed by direction, relative delay, and sub bank.
  vlm_busy_table_t shm_busy[VLM_RESERVATION_DIRECTION_N];

  // Final busy values exposed as external_busy OR shm_busy.
  vlm_busy_table_t final_busy[VLM_RESERVATION_DIRECTION_N];

  // Accepted DUT reservations grouped by direction, delay, and sub bank.
  // Each slot is a queue because different BANKs may legally share one slot.
  vlm_shm_record_queue_t
      shm_records[VLM_RESERVATION_DIRECTION_N][VTAB_D][VLM_SUB_BANK_N];

  // Cycle snapshot associated with the most recently processed transaction.
  longint unsigned current_cycle;

  // Total number of DUT reservation records accepted since construction.
  longint unsigned accepted_record_count;

  // Total number of external busy slots generated since construction.
  longint unsigned external_slot_count;

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
  // @brief Assigns the validated agent configuration used by the scheduler.
  //
  // @param cfg Configuration handle shared by the reservation agent.
  // @pre cfg is non-null and remains valid for the scheduler lifetime.
  // @post Subsequent scheduler API calls use the supplied configuration.
  //------------------------------------------------------------------------------
  extern function void set_config(vlm_reservation_agent_config cfg);

  //------------------------------------------------------------------------------
  // @brief Advances the schedule from one normalized cycle transaction.
  //
  // Consumes due records, advances the busy window, admits legal reservations,
  // applies the configured external policy, and prepares final_busy for the
  // next cycle. Known but illegal events are not committed to scheduler state.
  //
  // @param transaction Two-state reservation/MEM transaction for one cycle.
  // @pre transaction.cycle equals the current shared clk_if cycle.
  // @post current_cycle equals transaction.cycle and final_busy is prepared
  //       for the agent's next busy drive.
  //------------------------------------------------------------------------------
  extern function void process_cycle(
      const ref vlm_reservation_cycle_transaction_t transaction);

  //------------------------------------------------------------------------------
  // @brief Replaces one direction's directed external busy table.
  //
  // @param direction Read or write table to update.
  // @param busy      Directed external occupancy indexed by delay and sub bank.
  // @pre No set bit in busy overlaps an accepted SHM reservation slot.
  // @post Directed mode uses the supplied table for subsequent busy updates.
  //------------------------------------------------------------------------------
  extern function void set_directed_external_busy(
      vlm_reservation_direction_e direction,
      vlm_busy_table_t            busy);

  //------------------------------------------------------------------------------
  // @brief Returns the current external busy table for one direction.
  //
  // @param direction Read or write table to query.
  // @return A copy of the selected external busy table.
  //------------------------------------------------------------------------------
  extern function vlm_busy_table_t get_external_busy(
      vlm_reservation_direction_e direction);

  //------------------------------------------------------------------------------
  // @brief Returns the current DUT-owned SHM busy table for one direction.
  //
  // @param direction Read or write table to query.
  // @return A copy of the selected SHM busy table.
  //------------------------------------------------------------------------------
  extern function vlm_busy_table_t get_shm_busy(
      vlm_reservation_direction_e direction);

  //------------------------------------------------------------------------------
  // @brief Returns the final busy table for one reservation direction.
  //
  // @param direction Read or write table to query.
  // @return A copy of external_busy OR shm_busy for the selected direction.
  //------------------------------------------------------------------------------
  extern function vlm_busy_table_t get_final_busy(
      vlm_reservation_direction_e direction);

  //------------------------------------------------------------------------------
  // @brief Reports whether one slot is occupied by an external source.
  //
  // @param direction Read or write table to query.
  // @param delay     Relative delay index in the current scheduler window.
  // @param sub_bank  Sub-bank index in the range zero through three.
  // @return 1 when the selected external slot is occupied; otherwise 0.
  //------------------------------------------------------------------------------
  extern function bit is_external_busy(
      vlm_reservation_direction_e direction,
      int unsigned                delay,
      int unsigned                sub_bank);

  //------------------------------------------------------------------------------
  // @brief Reports whether one slot contains at least one DUT reservation.
  //
  // @param direction Read or write table to query.
  // @param delay     Relative delay index in the current scheduler window.
  // @param sub_bank  Sub-bank index in the range zero through three.
  // @return 1 when the selected SHM slot contains a record; otherwise 0.
  //------------------------------------------------------------------------------
  extern function bit is_shm_busy(
      vlm_reservation_direction_e direction,
      int unsigned                delay,
      int unsigned                sub_bank);

  //------------------------------------------------------------------------------
  // @brief Returns the number of DUT records stored in one scheduler slot.
  //
  // @param direction Read or write table to query.
  // @param delay     Relative delay index in the current scheduler window.
  // @param sub_bank  Sub-bank index in the range zero through three.
  // @return Number of records sharing the selected SHM slot.
  //------------------------------------------------------------------------------
  extern function int unsigned get_shm_record_count(
      vlm_reservation_direction_e direction,
      int unsigned                delay,
      int unsigned                sub_bank);

  //------------------------------------------------------------------------------
  // @brief Copies all DUT records stored in one scheduler slot.
  //
  // @param direction Read or write table to query.
  // @param delay     Relative delay index in the current scheduler window.
  // @param sub_bank  Sub-bank index in the range zero through three.
  // @param records   Output queue receiving a copy of the selected records.
  // @post records is empty when the selected slot has no accepted reservation.
  //------------------------------------------------------------------------------
  extern function void get_shm_records(
      vlm_reservation_direction_e direction,
      int unsigned                delay,
      int unsigned                sub_bank,
      output vlm_shm_record_queue_t records);

  //------------------------------------------------------------------------------
  // @brief Returns the cycle of the most recently processed transaction.
  //
  // @return Last transaction cycle copied from the shared clk_if snapshot.
  //------------------------------------------------------------------------------
  extern function longint unsigned get_current_cycle();

  `uvm_component_utils(vlm_reservation_scheduler)

endclass : vlm_reservation_scheduler

`endif // VLM_RESERVATION_SCHEDULER_SVH
