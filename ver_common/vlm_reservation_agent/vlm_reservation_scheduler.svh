`ifndef VLM_RESERVATION_SCHEDULER_SVH
`define VLM_RESERVATION_SCHEDULER_SVH

//------------------------------------------------------------------------------
// @brief Maintains the cycle-relative VLM reservation busy schedule.
//
// Separately tracks external and DUT-owned SHM busy slots for read and write
// directions. It accepts sampled DUT reservations and provides the final busy
// tables to the cycle controller. It does not inspect MEM read data or decide
// whether an actual MEM request satisfies a reservation.
//------------------------------------------------------------------------------
class vlm_reservation_scheduler extends uvm_component;

  // Agent configuration controlling active mode and external busy policy.
  vlm_reservation_agent_config cfg;

  // External occupancy indexed by direction, relative delay, and sub bank.
  vlm_busy_table_t external_busy[VLM_RESERVATION_DIRECTION_N];

  // DUT-owned occupancy indexed by direction, relative delay, and sub bank.
  vlm_busy_table_t shm_busy[VLM_RESERVATION_DIRECTION_N];

  // Final busy values exposed to the DUT as external_busy OR shm_busy.
  vlm_busy_table_t final_busy[VLM_RESERVATION_DIRECTION_N];

  // Accepted DUT reservations grouped by direction, delay, and sub bank.
  // Each slot is a queue because different BANKs may legally share one slot.
  vlm_shm_record_queue_t shm_records[VLM_RESERVATION_DIRECTION_N][VTAB_D][VLM_SUB_BANK_N];

  // Absolute cycle represented by delay index zero in the current tables.
  longint unsigned current_cycle;

  // Total number of DUT reservation records accepted since the last reset.
  longint unsigned accepted_record_count;

  // Total number of external slots generated since the last reset.
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
  // @brief Assigns the validated agent configuration used by the scheduler.
  //
  // @param cfg Configuration handle shared by the reservation agent.
  // @pre cfg is non-null and remains valid for the scheduler lifetime.
  // @post Subsequent scheduler API calls use the supplied configuration.
  //------------------------------------------------------------------------------
  extern function void set_config(vlm_reservation_agent_config cfg);

  //------------------------------------------------------------------------------
  // @brief Clears busy tables, reservation records, cycle state, and counters.
  //
  // @post All external and SHM slots are free and no record remains pending.
  //------------------------------------------------------------------------------
  extern function void reset_state();

  //------------------------------------------------------------------------------
  // @brief Updates scheduler state from one atomically sampled active cycle.
  //
  // Accepts legal DUT reservations with dly greater than zero, advances the
  // busy window, applies the configured external busy policy, and prepares the
  // final busy tables for the next active cycle.
  //
  // @param sample Reservation and MEM request snapshot for the current cycle.
  // @pre sample.cycle_id identifies the current scheduler cycle.
  // @post final_busy contains the next busy values requested by the controller.
  //------------------------------------------------------------------------------
  extern function void process_cycle(
      const ref vlm_reservation_cycle_sample_t sample);

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
  // @brief Returns the final busy table driven for one reservation direction.
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

  `uvm_component_utils(vlm_reservation_scheduler)

endclass : vlm_reservation_scheduler

`endif // VLM_RESERVATION_SCHEDULER_SVH
