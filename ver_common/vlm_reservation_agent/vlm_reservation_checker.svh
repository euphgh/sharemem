`ifndef VLM_RESERVATION_CHECKER_SVH
`define VLM_RESERVATION_CHECKER_SVH

//------------------------------------------------------------------------------
// @brief Checks reservation semantics, busy ownership, and MEM correspondence.
//
// Consumes the monitor's normalized transaction and a read-only scheduler
// view. It checks known protocol events and exact reservation-to-MEM matching.
// Four-state interface diagnosis belongs to the monitor; MEM data, strobe, and
// read-response timing remain outside this component.
//------------------------------------------------------------------------------
class vlm_reservation_checker extends uvm_component;

  // Agent configuration assigned directly by the containing agent.
  vlm_reservation_agent_config cfg;

  // Shared cycle-number service obtained directly through UVM Config DB.
  virtual clk_if clk_vif;

  // Read-only scheduler handle assigned directly by the containing agent.
  vlm_reservation_scheduler scheduler;

  // Number of reservation protocol violations observed since construction.
  int unsigned reservation_error_count;

  // Number of scheduler busy-state violations observed since construction.
  int unsigned busy_error_count;

  // Number of reservation-to-MEM matching violations since construction.
  int unsigned mem_match_error_count;

  // Number of unsupported dly-zero reservations observed since construction.
  int unsigned dly_zero_error_count;

  // Number of cycle transactions containing monitor input errors.
  int unsigned input_error_cycle_count;

  // Number of MEM requests successfully matched to unique due records.
  longint unsigned matched_mem_request_count;

  //------------------------------------------------------------------------------
  // @brief Constructs the reservation checker component.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this checker.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_reservation_checker",
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
  // @brief Runs all enabled checks for one normalized cycle transaction.
  //
  // @param transaction Reservation, busy, and MEM request events for one cycle.
  // @pre Scheduler still exposes its pre-update state for transaction.cycle.
  // @return 1 when all enabled checks pass for the cycle; otherwise 0.
  //------------------------------------------------------------------------------
  extern function bit check_cycle(
      const ref vlm_reservation_cycle_transaction_t transaction);

  //------------------------------------------------------------------------------
  // @brief Accounts for interface errors already reported by the monitor.
  //
  // @param transaction Transaction containing the monitor input_error status.
  // @post Transactions with input_error increment input_error_cycle_count.
  //------------------------------------------------------------------------------
  extern function void check_monitor_input_status(
      const ref vlm_reservation_cycle_transaction_t transaction);

  //------------------------------------------------------------------------------
  // @brief Checks external/SHM ownership and observed final busy values.
  //
  // @param transaction Transaction containing observed busy and known masks.
  // @pre Scheduler exposes busy state for transaction.cycle.
  // @post Busy-source and driven-value violations update busy_error_count.
  //------------------------------------------------------------------------------
  extern function void check_busy_state(
      const ref vlm_reservation_cycle_transaction_t transaction);

  //------------------------------------------------------------------------------
  // @brief Checks all known read and write reservation events in one cycle.
  //
  // @param transaction Transaction containing normalized reservation events.
  // @post Semantic violations update the corresponding checker counters.
  //------------------------------------------------------------------------------
  extern function void check_reservation_requests(
      const ref vlm_reservation_cycle_transaction_t transaction);

  //------------------------------------------------------------------------------
  // @brief Checks actual MEM requests against records due in the sampled cycle.
  //
  // @param transaction Transaction containing normalized MEM request events.
  // @pre Scheduler delay-zero records represent transaction.cycle.
  // @post Missing, unexpected, duplicate, or mismatched requests are counted.
  //------------------------------------------------------------------------------
  extern function void check_mem_requests(
      const ref vlm_reservation_cycle_transaction_t transaction);

  `uvm_component_utils(vlm_reservation_checker)

endclass : vlm_reservation_checker

//------------------------------------------------------------------------------
// vlm_reservation_checker method implementations
//------------------------------------------------------------------------------

function vlm_reservation_checker::new(string name = "vlm_reservation_checker", uvm_component parent = null);
  super.new(name, parent);

  reservation_error_count    = 0;
  busy_error_count           = 0;
  mem_match_error_count      = 0;
  dly_zero_error_count       = 0;
  input_error_cycle_count    = 0;
  matched_mem_request_count  = 0;
endfunction : new

function void vlm_reservation_checker::build_phase(uvm_phase phase);
  super.build_phase(phase);

  // A shared clock interface is mandatory because all cycle-aware components must use the same cycle source.
  if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
    `uvm_fatal(
        "VLM_RESERVATION_NO_CLK_VIF",
        "vlm_reservation_checker requires virtual clk_if 'clk_vif'")
  end
endfunction : build_phase

function bit vlm_reservation_checker::check_cycle(
    const ref vlm_reservation_cycle_transaction_t transaction);
  longint unsigned error_count_before;
  longint unsigned error_count_after;

  // Missing configuration is an environment construction error, so protocol checking cannot continue.
  if (cfg == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_CFG", "check_cycle() requires the agent to assign checker.cfg")
    return 1'b0;
  end

  if (!cfg.checker_enable) begin
    return 1'b1;
  end

  // The checker must observe the scheduler's pre-update state for all busy and due-record checks.
  if (scheduler == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_SCHEDULER", "check_cycle() requires the agent to assign checker.scheduler")
    return 1'b0;
  end

  error_count_before = reservation_error_count + busy_error_count + mem_match_error_count +
                       dly_zero_error_count + input_error_cycle_count;

  check_monitor_input_status(transaction);
  check_busy_state(transaction);
  check_reservation_requests(transaction);
  check_mem_requests(transaction);

  error_count_after = reservation_error_count + busy_error_count + mem_match_error_count +
                      dly_zero_error_count + input_error_cycle_count;

  return error_count_after == error_count_before;
endfunction : check_cycle

function void vlm_reservation_checker::check_monitor_input_status(
    const ref vlm_reservation_cycle_transaction_t transaction);
  // The monitor has already reported each X/Z error; the checker only records that this cycle is invalid.
  if (transaction.input_error) begin
    input_error_cycle_count++;
  end
endfunction : check_monitor_input_status

function void vlm_reservation_checker::check_busy_state(
    const ref vlm_reservation_cycle_transaction_t transaction);
  bit expected_busy;
  bit has_records;
  bit record_is_valid;
  vlm_shm_record_t record;

  // Busy checks require direct access to the scheduler-owned occupancy tables and reservation records.
  if (scheduler == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_SCHEDULER", "check_busy_state() requires checker.scheduler")
    return;
  end

  // Check read and write busy tables independently.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    // Check every relative delay represented by the current scheduler window.
    for (int unsigned delay = 0; delay < VTAB_D; delay++) begin
      // Check each sub-bank ownership bit and the records represented by that bit.
      for (int unsigned sub_bank = 0; sub_bank < VLM_SUB_BANK_N; sub_bank++) begin
        expected_busy = scheduler.external_busy[direction][delay][sub_bank] |
                        scheduler.shm_busy[direction][delay][sub_bank];
        has_records = scheduler.shm_records[direction][delay][sub_bank].size() != 0;

        // A slot cannot be owned by both an external module and an SHM reservation.
        if (scheduler.external_busy[direction][delay][sub_bank] &&
            scheduler.shm_busy[direction][delay][sub_bank]) begin
          busy_error_count++;
          `uvm_error("VLM_RESERVATION_BUSY_OVERLAP",
                     $sformatf("cycle %0d direction %0d delay %0d sub bank %0d is owned by external and SHM busy",
                               transaction.cycle, direction, delay, sub_bank))
        end

        // The scheduler's final busy table must be exactly the OR of its two ownership tables.
        if (scheduler.final_busy[direction][delay][sub_bank] != expected_busy) begin
          busy_error_count++;
          `uvm_error("VLM_RESERVATION_FINAL_BUSY",
                     $sformatf("cycle %0d direction %0d delay %0d sub bank %0d final busy %0b, expected %0b",
                               transaction.cycle, direction, delay, sub_bank,
                               scheduler.final_busy[direction][delay][sub_bank], expected_busy))
        end

        // SHM busy must be asserted if and only if the corresponding record queue is non-empty.
        if (scheduler.shm_busy[direction][delay][sub_bank] != has_records) begin
          busy_error_count++;
          `uvm_error("VLM_RESERVATION_SHM_BUSY_RECORD",
                     $sformatf("cycle %0d direction %0d delay %0d sub bank %0d SHM busy %0b, record count %0d",
                               transaction.cycle, direction, delay, sub_bank,
                               scheduler.shm_busy[direction][delay][sub_bank],
                               scheduler.shm_records[direction][delay][sub_bank].size()))
        end

        // In active mode, every known interface busy bit must equal the scheduler value driven by the agent.
        if (cfg != null && cfg.is_active == UVM_ACTIVE &&
            transaction.observed_busy_known[direction][delay][sub_bank] &&
            transaction.observed_busy[direction][delay][sub_bank] != expected_busy) begin
          busy_error_count++;
          `uvm_error("VLM_RESERVATION_OBSERVED_BUSY",
                     $sformatf("cycle %0d direction %0d delay %0d sub bank %0d observed busy %0b, expected %0b",
                               transaction.cycle, direction, delay, sub_bank,
                               transaction.observed_busy[direction][delay][sub_bank], expected_busy))
        end

        // Validate that every queued record agrees with the direction, delay, and sub-bank indices of its slot.
        foreach (scheduler.shm_records[direction][delay][sub_bank][record_index]) begin
          record = scheduler.shm_records[direction][delay][sub_bank][record_index];
          record_is_valid = record.bank_id < BANK_N && record.address[4:0] == 5'b0 &&
                            record.address[6:5] == sub_bank &&
                            record.due_cycle == transaction.cycle + delay &&
                            ((direction == VLM_RESERVATION_READ && record.write_port == 0) ||
                             (direction == VLM_RESERVATION_WRITE && record.write_port < WRITE_PORT_N));

          // An invalid record means scheduler state no longer represents the reservation contract.
          if (!record_is_valid) begin
            busy_error_count++;
            `uvm_error("VLM_RESERVATION_RECORD_SLOT",
                       $sformatf({"cycle %0d record %0d in direction %0d delay %0d sub bank %0d has bank %0d ",
                                  "port %0d address 0x%0h and due cycle %0d"},
                                 transaction.cycle, record_index, direction, delay, sub_bank, record.bank_id,
                                 record.write_port, record.address, record.due_cycle))
          end
        end
      end
    end
  end
endfunction : check_busy_state

function void vlm_reservation_checker::check_reservation_requests(
    const ref vlm_reservation_cycle_transaction_t transaction);
  bit event_is_valid;
  bit target_is_busy;
  int unsigned sub_bank;
  vlm_reservation_event_t reservation;
  vlm_reservation_event_t previous_reservation;
  vlm_shm_record_t existing_record;

  // Reservation checks require scheduler state from before the current transaction is admitted.
  if (scheduler == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_SCHEDULER", "check_reservation_requests() requires checker.scheduler")
    return;
  end

  // Validate every known reservation event produced by the monitor in this cycle.
  foreach (transaction.reservation_events[event_index]) begin
    reservation = transaction.reservation_events[event_index];
    event_is_valid = 1'b1;

    // The BANK index must identify one of the physical DUT BANK ports.
    if (reservation.bank_id >= BANK_N) begin
      reservation_error_count++;
      event_is_valid = 1'b0;
      `uvm_error("VLM_RESERVATION_BANK_ID",
                 $sformatf("cycle %0d reservation %0d has invalid bank ID %0d",
                           transaction.cycle, event_index, reservation.bank_id))
    end

    // Read reservations use port zero; write reservations must identify one of the configured write ports.
    if ((reservation.direction == VLM_RESERVATION_READ &&
         reservation.write_port != 0) ||
        (reservation.direction == VLM_RESERVATION_WRITE &&
         reservation.write_port >= WRITE_PORT_N)) begin
      reservation_error_count++;
      event_is_valid = 1'b0;
      `uvm_error("VLM_RESERVATION_WRITE_PORT",
                 $sformatf("cycle %0d reservation %0d direction %0d has invalid write port %0d",
                           transaction.cycle, event_index, reservation.direction, reservation.write_port))
    end

    // The current verification profile rejects dly zero instead of entering normal scheduling and matching.
    if (reservation.delay == 0) begin
      dly_zero_error_count++;
      `uvm_error("VLM_RESERVATION_DLY_ZERO",
                 $sformatf("cycle %0d reservation %0d uses unsupported dly == 0",
                           transaction.cycle, event_index))
      continue;
    end

    // Delay encodings outside the scheduler window cannot be used to index busy or record state.
    if (reservation.delay >= VTAB_D) begin
      reservation_error_count++;
      `uvm_error("VLM_RESERVATION_DLY_RANGE",
                 $sformatf("cycle %0d reservation %0d delay %0d is outside [1, %0d]",
                           transaction.cycle, event_index, reservation.delay, VTAB_D - 1))
      continue;
    end

    // Every reservation represents one 32-byte MEM beat and therefore requires a 32-byte-aligned address.
    if (reservation.address[4:0] != 5'b0) begin
      reservation_error_count++;
      event_is_valid = 1'b0;
      `uvm_error("VLM_RESERVATION_ALIGNMENT",
                 $sformatf("cycle %0d reservation %0d address 0x%0h is not 32-byte aligned",
                           transaction.cycle, event_index, reservation.address))
    end

    sub_bank = reservation.address[6:5];
    target_is_busy = cfg != null && cfg.is_active == UVM_ACTIVE &&
                     (scheduler.external_busy[reservation.direction][reservation.delay][sub_bank] |
                      scheduler.shm_busy[reservation.direction][reservation.delay][sub_bank]);

    // A reservation is legal only when its observed target slot is known and free from all existing owners.
    if (!transaction.observed_busy_known[reservation.direction][reservation.delay][sub_bank] ||
        transaction.observed_busy[reservation.direction][reservation.delay][sub_bank] ||
        target_is_busy) begin
      reservation_error_count++;
      event_is_valid = 1'b0;
      `uvm_error("VLM_RESERVATION_TARGET_BUSY",
                 $sformatf("cycle %0d reservation %0d direction %0d delay %0d sub bank %0d is not known free",
                           transaction.cycle, event_index, reservation.direction, reservation.delay, sub_bank))
    end

    if (!event_is_valid) begin
      continue;
    end

    // Compare against earlier events to detect two current-cycle reservations due on the same BANK port.
    for (int previous_index = 0; previous_index < event_index; previous_index++) begin
      previous_reservation = transaction.reservation_events[previous_index];

      if (previous_reservation.delay > 0 &&
          previous_reservation.delay < VTAB_D &&
          previous_reservation.bank_id == reservation.bank_id &&
          previous_reservation.direction == reservation.direction &&
          previous_reservation.delay == reservation.delay) begin
        // One BANK has only one actual MEM request port per direction and cannot retire both reservations.
        reservation_error_count++;
        `uvm_error("VLM_RESERVATION_BANK_DUE_CONFLICT",
                   $sformatf("cycle %0d reservations %0d and %0d make bank %0d direction %0d due together",
                             transaction.cycle, previous_index, event_index,
                             reservation.bank_id, reservation.direction))
      end
    end

    // Search every sub bank because same-BANK due conflicts are independent of the reserved sub bank.
    for (int unsigned existing_sub_bank = 0; existing_sub_bank < VLM_SUB_BANK_N; existing_sub_bank++) begin
      // Compare the new reservation with each previously accepted record at the same direction and delay.
      foreach (scheduler.shm_records[reservation.direction][reservation.delay][existing_sub_bank][record_index]) begin
        existing_record =
            scheduler.shm_records[reservation.direction][reservation.delay][existing_sub_bank][record_index];

        if (existing_record.bank_id == reservation.bank_id) begin
          // A pending reservation already consumes this BANK's actual MEM request port in the due cycle.
          reservation_error_count++;
          `uvm_error("VLM_RESERVATION_PENDING_BANK_DUE_CONFLICT",
                     $sformatf("cycle %0d reservation %0d makes bank %0d direction %0d due at occupied cycle %0d",
                               transaction.cycle, event_index, reservation.bank_id, reservation.direction,
                               transaction.cycle + reservation.delay))
        end
      end
    end
  end
endfunction : check_reservation_requests

function void vlm_reservation_checker::check_mem_requests(
    const ref vlm_reservation_cycle_transaction_t transaction);
  bit request_is_unique;
  int unsigned sub_bank;
  int unsigned record_match_count;
  int unsigned request_match_count;
  vlm_memory_request_event_t memory_request;
  vlm_memory_request_event_t other_request;
  vlm_shm_record_t due_record;

  // MEM matching requires the complete set of scheduler records due in the sampled cycle.
  if (scheduler == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_SCHEDULER", "check_mem_requests() requires checker.scheduler")
    return;
  end

  // Check that every observed MEM request consumes exactly one due reservation record.
  foreach (transaction.memory_request_events[request_index]) begin
    memory_request = transaction.memory_request_events[request_index];
    request_is_unique = 1'b1;

    // The MEM event must identify one of the physical DUT BANK ports.
    if (memory_request.bank_id >= BANK_N) begin
      mem_match_error_count++;
      `uvm_error("VLM_RESERVATION_MEM_BANK_ID",
                 $sformatf("cycle %0d MEM request %0d has invalid bank ID %0d",
                           transaction.cycle, request_index, memory_request.bank_id))
      continue;
    end

    // Actual MEM requests use the same 32-byte beat alignment as their reservations.
    if (memory_request.address[4:0] != 5'b0) begin
      mem_match_error_count++;
      request_is_unique = 1'b0;
      `uvm_error("VLM_RESERVATION_MEM_ALIGNMENT",
                 $sformatf("cycle %0d MEM request %0d address 0x%0h is not 32-byte aligned",
                           transaction.cycle, request_index, memory_request.address))
    end

    sub_bank = memory_request.address[6:5];

    // A legal actual request requires exclusive SHM ownership of its delay-zero sub-bank slot.
    if (!scheduler.shm_busy[memory_request.direction][0][sub_bank] ||
        scheduler.external_busy[memory_request.direction][0][sub_bank]) begin
      mem_match_error_count++;
      request_is_unique = 1'b0;
      `uvm_error("VLM_RESERVATION_MEM_BUSY",
                 $sformatf("cycle %0d MEM request %0d direction %0d sub bank %0d lacks exclusive SHM busy",
                           transaction.cycle, request_index, memory_request.direction, sub_bank))
    end

    record_match_count = 0;
    // Count exact due-record matches using direction, BANK, address, and current due cycle.
    foreach (scheduler.shm_records[memory_request.direction][0][sub_bank][record_index]) begin
      due_record = scheduler.shm_records[memory_request.direction][0][sub_bank][record_index];

      if (due_record.bank_id == memory_request.bank_id &&
          due_record.address == memory_request.address &&
          due_record.due_cycle == transaction.cycle) begin
        record_match_count++;
      end
    end

    // Zero matches indicate an unreserved request; multiple matches indicate ambiguous or duplicate records.
    if (record_match_count != 1) begin
      mem_match_error_count++;
      request_is_unique = 1'b0;
      `uvm_error("VLM_RESERVATION_MEM_TO_RECORD",
                 $sformatf("cycle %0d MEM request %0d direction %0d bank %0d address 0x%0h matched %0d records",
                           transaction.cycle, request_index, memory_request.direction, memory_request.bank_id,
                           memory_request.address, record_match_count))
    end

    request_match_count = 0;
    // Count identical MEM events so one due record cannot be consumed more than once.
    foreach (transaction.memory_request_events[other_request_index]) begin
      other_request = transaction.memory_request_events[other_request_index];

      if (other_request.direction == memory_request.direction &&
          other_request.bank_id == memory_request.bank_id &&
          other_request.address == memory_request.address) begin
        request_match_count++;
      end
    end

    // The normalized transaction must contain one and only one actual request for this matching key.
    if (request_match_count != 1) begin
      mem_match_error_count++;
      request_is_unique = 1'b0;
      `uvm_error("VLM_RESERVATION_DUPLICATE_MEM",
                 $sformatf("cycle %0d direction %0d bank %0d address 0x%0h appears in %0d MEM request events",
                           transaction.cycle, memory_request.direction, memory_request.bank_id,
                           memory_request.address, request_match_count))
    end

    if (request_is_unique) begin
      matched_mem_request_count++;
    end
  end

  // Check both directions so every due reservation is required to produce an actual MEM request.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    // Visit every sub bank that can contain delay-zero records.
    for (int unsigned sub_bank = 0; sub_bank < VLM_SUB_BANK_N; sub_bank++) begin
      // Check each due record independently because multiple BANKs may legally share one SHM busy bit.
      foreach (scheduler.shm_records[direction][0][sub_bank][record_index]) begin
        due_record = scheduler.shm_records[direction][0][sub_bank][record_index];
        request_match_count = 0;

        // Count actual requests matching this record's direction, BANK, address, and due cycle.
        foreach (transaction.memory_request_events[request_index]) begin
          memory_request = transaction.memory_request_events[request_index];

          if (memory_request.direction == direction &&
              memory_request.bank_id == due_record.bank_id &&
              memory_request.address == due_record.address &&
              due_record.due_cycle == transaction.cycle) begin
            request_match_count++;
          end
        end

        // Missing or duplicate requests violate the reservation-to-MEM one-to-one relationship.
        if (request_match_count != 1) begin
          mem_match_error_count++;
          `uvm_error("VLM_RESERVATION_RECORD_TO_MEM",
                     $sformatf({"cycle %0d due record %0d direction %0d sub bank %0d bank %0d address 0x%0h ",
                                "matched %0d MEM requests"},
                               transaction.cycle, record_index, direction, sub_bank, due_record.bank_id,
                               due_record.address, request_match_count))
        end
      end
    end
  end
endfunction : check_mem_requests

`endif // VLM_RESERVATION_CHECKER_SVH
