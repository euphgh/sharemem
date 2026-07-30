`ifndef VLM_RESERVATION_SCHEDULER_SVH
`define VLM_RESERVATION_SCHEDULER_SVH

//------------------------------------------------------------------------------
// @brief Maintains the cycle-relative VLM reservation busy schedule.
//
// Owns external busy, DUT SHM records, derived SHM busy, and final driven busy
// for both directions. Each cycle it advances the window, admits legal known
// reservations, and may occupy any currently free slot according to the
// external busy percentage. It does not sample interfaces or check MEM data.
//------------------------------------------------------------------------------
class vlm_reservation_scheduler extends uvm_component;

  // Shared cycle-number service obtained directly through UVM Config DB.
  virtual clk_if clk_vif;

  // Percentage probability, from 0 through 100, applied independently to every
  // free slot across the full busy window during external busy generation.
  int unsigned external_busy_percent = 0;

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

  // Total number of known but illegal DUT reservations rejected since construction.
  longint unsigned rejected_record_count;

  // Total number of free slots changed to external busy since construction.
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
  // @post clk_vif refers to the repository-wide clock service or a fatal
  //       configuration error has been reported.
  //------------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Advances the schedule from one normalized cycle transaction.
  //
  // Consumes due records, advances the busy window, admits legal reservations,
  // generates external busy in any remaining free slot, and prepares final_busy
  // for the next cycle.
  //
  // @param txn Two-state reservation/MEM transaction for one cycle.
  // @pre txn.cycle equals the current shared clk_if cycle.
  // @post last_processed_cycle equals txn.cycle and final_busy represents the
  //       next interface cycle.
  //------------------------------------------------------------------------------
  extern function void process_cycle(
      const ref vlm_reservation_cycle_transaction_t txn);

  //------------------------------------------------------------------------------
  // @brief Removes the current due entries and advances all retained state.
  //
  // @post Old relative delay d+1 occupies d, the last delay is free, and
  //       accepted record issue metadata remains unchanged.
  //------------------------------------------------------------------------------
  extern protected function void advance_window();

  //------------------------------------------------------------------------------
  // @brief Admits all legal read and write reservations from one transaction.
  //
  // @param txn Transaction whose reservation arrays are evaluated as one batch.
  // @pre Existing SHM busy represents only reservations accepted before txn.
  // @post Accepted requests have independent scheduler-owned records; legal
  //       different-BANK requests may share one SHM sub-bank slot.
  //------------------------------------------------------------------------------
  extern protected function void admit_reservations(
      const ref vlm_reservation_cycle_transaction_t txn);

  //------------------------------------------------------------------------------
  // @brief Attempts to admit one fully known reservation request.
  //
  // @param direction  Read or write reservation direction.
  // @param bank       BANK array index carrying the request.
  // @param write_port Write-port index; zero for read reservations.
  // @param rsv        Read-only request instance created by the monitor.
  // @param issue_cycle Shared cycle in which the request was sampled.
  // @return 1 when a new scheduler-owned record is committed; otherwise 0.
  // @pre SHM busy still represents only records accepted before the current
  //      transaction; records inserted earlier in the same transaction must
  //      not block a legal different-BANK request sharing the same sub bank.
  //------------------------------------------------------------------------------
  extern protected function bit admit_reservation(
      vlm_reservation_direction_e direction,
      int unsigned                bank,
      int unsigned                write_port,
      const ref vlm_rsv_req       rsv,
      longint unsigned            issue_cycle);

  //------------------------------------------------------------------------------
  // @brief Rebuilds SHM busy by reducing record addresses across all BANKs.
  //
  // @post A SHM busy slot is set exactly when at least one record at the same
  //       direction and delay selects that sub bank through address[6:5].
  //------------------------------------------------------------------------------
  extern protected function void rebuild_shm_busy();

  //------------------------------------------------------------------------------
  // @brief Randomly occupies currently free external busy slots.
  //
  // Applies external_busy_percent independently to every slot in the complete
  // direction, delay, and sub-bank window. Slots already owned by external or
  // SHM busy remain unchanged, so the two ownership tables never overlap.
  //
  // @pre SHM busy has been rebuilt after all current reservations are admitted.
  // @post Only previously free slots may transition to external busy.
  //------------------------------------------------------------------------------
  extern protected function void generate_external_busy();

  //------------------------------------------------------------------------------
  // @brief Rebuilds the final driven busy tables from their ownership sources.
  //
  // @post Every final busy bit equals external_busy OR shm_busy at the same
  //       direction, relative delay, and sub-bank index.
  //------------------------------------------------------------------------------
  extern protected function void rebuild_final_busy();

  `uvm_component_utils(vlm_reservation_scheduler)

endclass : vlm_reservation_scheduler

`endif // VLM_RESERVATION_SCHEDULER_SVH
