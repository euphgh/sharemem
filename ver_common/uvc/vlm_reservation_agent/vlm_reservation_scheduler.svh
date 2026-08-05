`ifndef INC_VLM_RESERVATION_SCHEDULER_SVH
`define INC_VLM_RESERVATION_SCHEDULER_SVH

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
  int unsigned external_busy_percent;

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

//------------------------------------------------------------------------------
// vlm_reservation_scheduler method implementations
//------------------------------------------------------------------------------

function vlm_reservation_scheduler::new(string name = "vlm_reservation_scheduler", uvm_component parent = null);
  super.new(name, parent);

  external_busy_percent         = 0;
  has_processed_cycle           = 1'b0;
  last_processed_cycle          = 0;
  accepted_record_count         = 0;
  rejected_record_count         = 0;
  generated_external_slot_count = 0;

  // Initialize every read/write ownership table so the agent can drive known-zero busy before the first cycle.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    external_busy[direction] = '0;
    shm_busy[direction]      = '0;
    final_busy[direction]    = '0;
  end

  // Explicitly clear every nullable record slot in the initial scheduler window.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    // Each relative delay initially contains no accepted DUT reservation.
    for (int unsigned delay = 0; delay < VTAB_D; delay++) begin
      // BANK identity is represented by the final fixed-array index.
      for (int unsigned bank = 0; bank < BANK_N; bank++) begin
        shm_records[direction][delay][bank] = null;
      end
    end
  end
endfunction : new

function void vlm_reservation_scheduler::build_phase(uvm_phase phase);
  super.build_phase(phase);

  // Every cycle-aware component must use the same repository-wide cycle source.
  if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
    `uvm_fatal("VLM_RESERVATION_NO_CLK_VIF", "vlm_reservation_scheduler requires virtual clk_if 'clk_vif'")
  end
endfunction : build_phase

function void vlm_reservation_scheduler::process_cycle(
    const ref vlm_reservation_cycle_transaction_t txn);
  // Relative-delay state cannot be advanced safely without the shared cycle source.
  if (clk_vif == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_CLK_VIF", "process_cycle() requires scheduler.clk_vif")
    return;
  end

  // The transaction must carry the same cycle snapshot observed through clk_if.
  if (txn.cycle != clk_vif.cycle_count) begin
    `uvm_fatal("VLM_RESERVATION_CYCLE_MISMATCH",
               $sformatf("transaction cycle %0d does not match clk_if cycle %0d",
                         txn.cycle, clk_vif.cycle_count))
    return;
  end

  // A missing or repeated cycle would invalidate every relative-delay index in the scheduler window.
  if (has_processed_cycle && last_processed_cycle + 1 != txn.cycle) begin
    `uvm_fatal("VLM_RESERVATION_NONCONSECUTIVE_CYCLE",
               $sformatf("transaction cycle %0d follows scheduler cycle %0d",
                         txn.cycle, last_processed_cycle))
    return;
  end

  // Consume the sampled cycle and express all retained state relative to the next interface cycle.
  advance_window();

  // This first rebuild is a stable pre-batch view containing only reservations accepted before txn.
  rebuild_shm_busy();

  // Admit current requests without changing the stable SHM busy view between requests.
  admit_reservations(txn);

  // Include every newly accepted record before external busy selects from the remaining free slots.
  rebuild_shm_busy();
  generate_external_busy();
  rebuild_final_busy();

  has_processed_cycle  = 1'b1;
  last_processed_cycle = txn.cycle;
endfunction : process_cycle

function void vlm_reservation_scheduler::advance_window();
  // Read and write schedules advance independently but use the same relative-delay transformation.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    // Ascending order preserves each old d+1 entry until it is copied into the new d entry.
    for (int unsigned delay = 0; delay + 1 < VTAB_D; delay++) begin
      external_busy[direction][delay] = external_busy[direction][delay + 1];

      // Move every BANK record handle without modifying its immutable issue metadata.
      for (int unsigned bank = 0; bank < BANK_N; bank++) begin
        shm_records[direction][delay][bank] = shm_records[direction][delay + 1][bank];
      end
    end

    // The farthest future external slot enters the next window as free.
    external_busy[direction][VTAB_D - 1] = '0;

    // No previous DUT reservation can enter the new farthest future delay.
    for (int unsigned bank = 0; bank < BANK_N; bank++) begin
      shm_records[direction][VTAB_D - 1][bank] = null;
    end

    // Derived tables are rebuilt after movement and must not be consumed while stale.
    shm_busy[direction]   = '0;
    final_busy[direction] = '0;
  end
endfunction : advance_window

function void vlm_reservation_scheduler::admit_reservations(
    const ref vlm_reservation_cycle_transaction_t txn);
  // Each BANK has one read reservation request that is independent of the write direction.
  for (int unsigned bank = 0; bank < BANK_N; bank++) begin
    if (txn.rsv_rreq_array[bank] != null) begin
      void'(admit_reservation(VLM_RESERVATION_READ, bank, 0, txn.rsv_rreq_array[bank], txn.cycle));
    end
  end

  // Process both write reservation ports in deterministic port order for every BANK.
  for (int unsigned bank = 0; bank < BANK_N; bank++) begin
    // Different delays may be accepted from both write ports because they retire in different cycles.
    for (int unsigned port = 0; port < WRITE_PORT_N; port++) begin
      if (txn.rsv_wreq_array[bank][port] != null) begin
        void'(admit_reservation(
            VLM_RESERVATION_WRITE, bank, port, txn.rsv_wreq_array[bank][port], txn.cycle));
      end
    end
  end
endfunction : admit_reservations

function bit vlm_reservation_scheduler::admit_reservation(
    vlm_reservation_direction_e direction,
    int unsigned                bank,
    int unsigned                write_port,
    const ref vlm_rsv_req       rsv,
    longint unsigned            issue_cycle);
  int unsigned target_delay;
  int unsigned sub_bank;
  vlm_shm_record_t rec;

  // Reject an invalid structural call instead of indexing outside a fixed scheduler array.
  if (bank >= BANK_N ||
      (direction == VLM_RESERVATION_READ && write_port != 0) ||
      (direction == VLM_RESERVATION_WRITE && write_port >= WRITE_PORT_N)) begin
    rejected_record_count++;
    return 1'b0;
  end

  // The current verification profile does not schedule dly zero or out-of-window reservations.
  if (rsv.delay == 0 || rsv.delay >= VTAB_D) begin
    rejected_record_count++;
    return 1'b0;
  end

  // Read reservations and write port 1 require alignment; write port 0 preserves all address bits.
  if (vlm_reservation_requires_32byte_alignment(direction, write_port) &&
      rsv.address[4:0] != 5'b0) begin
    rejected_record_count++;
    return 1'b0;
  end

  target_delay = rsv.delay - 1;
  sub_bank     = rsv.address[6:5];

  // The shifted target must be free of ownership established before this transaction.
  if (external_busy[direction][target_delay][sub_bank] ||
      shm_busy[direction][target_delay][sub_bank]) begin
    rejected_record_count++;
    return 1'b0;
  end

  // One BANK and direction can retire only one request at a given due cycle.
  if (shm_records[direction][target_delay][bank] != null) begin
    rejected_record_count++;
    return 1'b0;
  end

  // Copy the monitor-owned request into an independent immutable scheduler record.
  rec = new();
  rec.address     = rsv.address;
  rec.write_port  = write_port;
  rec.issue_cycle = issue_cycle;
  rec.issue_delay = rsv.delay;

  shm_records[direction][target_delay][bank] = rec;
  accepted_record_count++;
  return 1'b1;
endfunction : admit_reservation

function void vlm_reservation_scheduler::rebuild_shm_busy();
  // Clear both direction tables before reducing the complete record array.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    shm_busy[direction] = '0;
  end

  // Reduce every non-null BANK record into the sub bank selected by its address.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    // Records at different relative delays contribute to different busy rows.
    for (int unsigned delay = 0; delay < VTAB_D; delay++) begin
      // Multiple BANK records may set the same bit without creating a DUT-internal conflict.
      for (int unsigned bank = 0; bank < BANK_N; bank++) begin
        if (shm_records[direction][delay][bank] != null) begin
          shm_busy[direction][delay][shm_records[direction][delay][bank].address[6:5]] = 1'b1;
        end
      end
    end
  end
endfunction : rebuild_shm_busy

function void vlm_reservation_scheduler::generate_external_busy();
  int unsigned random_percent;

  // External read and write reservations are generated independently.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    // Every relative delay is eligible; generation is not restricted to the newest window entry.
    for (int unsigned delay = 0; delay < VTAB_D; delay++) begin
      // Apply one independent percentage decision to each currently unowned sub-bank slot.
      for (int unsigned sub_bank = 0; sub_bank < VLM_SUB_BANK_N; sub_bank++) begin
        if (external_busy[direction][delay][sub_bank] ||
            shm_busy[direction][delay][sub_bank]) begin
          continue;
        end

        random_percent = $urandom_range(99, 0);

        // A result below the configured percentage changes this free slot to external ownership.
        if (random_percent < EXTERNAL_BUSY_PERCENT) begin
          external_busy[direction][delay][sub_bank] = 1'b1;
          generated_external_slot_count++;
        end
      end
    end
  end
endfunction : generate_external_busy

function void vlm_reservation_scheduler::rebuild_final_busy();
  // Publish one deterministic busy view for each independently scheduled direction.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    final_busy[direction] = external_busy[direction] | shm_busy[direction];
  end
endfunction : rebuild_final_busy

`endif // INC_VLM_RESERVATION_SCHEDULER_SVH
