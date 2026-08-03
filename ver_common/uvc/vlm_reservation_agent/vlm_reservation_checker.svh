`ifndef INC_VLM_RESERVATION_CHECKER_SVH
`define INC_VLM_RESERVATION_CHECKER_SVH

//------------------------------------------------------------------------------
// @brief Checks reservation semantics, busy ownership, and MEM correspondence.
//
// Consumes the monitor's normalized transaction and the scheduler's pre-update
// state. It checks two-state protocol semantics and exact reservation-to-MEM
// matching. Four-state diagnosis and MEM data checking remain outside this
// component.
//------------------------------------------------------------------------------
class vlm_reservation_checker extends uvm_component;

  // Shared cycle-number service obtained directly through UVM Config DB.
  virtual clk_if clk_vif;

  // Read-only scheduler handle assigned directly by the containing agent.
  vlm_reservation_scheduler scheduler;

  // Detailed checker result associated with the most recently checked cycle.
  vlm_reservation_check_result_t current_result;

  // Total number of reservation protocol violations since construction.
  longint unsigned reservation_error_count;

  // Total number of scheduler busy-state violations since construction.
  longint unsigned busy_error_count;

  // Total number of reservation-to-MEM matching violations since construction.
  longint unsigned mem_match_error_count;

  // Total number of unsupported dly-zero reservations since construction.
  longint unsigned dly_zero_error_count;

  // Total number of MEM requests matched to unique due records since construction.
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
  // @post clk_vif refers to the repository-wide clock service or a fatal
  //       configuration error has been reported.
  //------------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Runs every reservation check for one normalized cycle transaction.
  //
  // @param txn Reservation, busy, and MEM requests sampled in one cycle.
  // @pre Scheduler exposes its pre-update state for txn.cycle.
  // @return Detailed per-cycle counts and the aggregate pass/fail result.
  //------------------------------------------------------------------------------
  extern function vlm_reservation_check_result_t check_cycle(
      const ref vlm_reservation_cycle_transaction_t txn);

  //------------------------------------------------------------------------------
  // @brief Initializes the result accumulated by one check_cycle() call.
  //
  // @param result Result object to clear before individual checker categories run.
  // @post All per-cycle counts are zero and passed is provisionally set.
  //------------------------------------------------------------------------------
  extern protected function void initialize_result(
      ref vlm_reservation_check_result_t result);

  //------------------------------------------------------------------------------
  // @brief Checks external/SHM ownership, records, and observed final busy.
  //
  // @param txn    Transaction containing normalized observed busy values.
  // @param result Per-cycle result updated for every detected violation.
  // @pre Scheduler exposes busy and record state for txn.cycle.
  //------------------------------------------------------------------------------
  extern protected function void check_busy_state(
      const ref vlm_reservation_cycle_transaction_t txn,
      ref       vlm_reservation_check_result_t      result);

  //------------------------------------------------------------------------------
  // @brief Checks all known read and write reservation requests in one cycle.
  //
  // @param txn    Transaction containing fixed BANK and write-port request arrays.
  // @param result Per-cycle result updated for every detected violation.
  // @pre Scheduler exposes its state before accepting reservations from txn.
  //------------------------------------------------------------------------------
  extern protected function void check_reservation_requests(
      const ref vlm_reservation_cycle_transaction_t txn,
      ref       vlm_reservation_check_result_t      result);

  //------------------------------------------------------------------------------
  // @brief Checks one fully known reservation request against the current state.
  //
  // @param direction  Read or write reservation direction.
  // @param bank       BANK array index carrying the request.
  // @param write_port Write-port index; zero for read reservations.
  // @param rsv        Read-only request instance created by the monitor.
  // @param txn        Transaction containing observed busy and sibling requests.
  // @param result     Per-cycle result updated for every detected violation.
  // @return 1 when the request is legal and schedulable; otherwise 0.
  //------------------------------------------------------------------------------
  extern protected function bit check_reservation_request(
      vlm_reservation_direction_e                 direction,
      int unsigned                                bank,
      int unsigned                                write_port,
      const ref vlm_rsv_req                       rsv,
      const ref vlm_reservation_cycle_transaction_t txn,
      ref       vlm_reservation_check_result_t      result);

  //------------------------------------------------------------------------------
  // @brief Checks actual MEM requests against records due in the sampled cycle.
  //
  // @param txn    Transaction containing fixed per-BANK MEM request arrays.
  // @param result Per-cycle result updated for every match or violation.
  // @pre Scheduler delay-zero records represent txn.cycle.
  //------------------------------------------------------------------------------
  extern protected function void check_mem_requests(
      const ref vlm_reservation_cycle_transaction_t txn,
      ref       vlm_reservation_check_result_t      result);

  //------------------------------------------------------------------------------
  // @brief Checks one BANK's MEM request and due record in one direction.
  //
  // @param direction Read or write MEM direction.
  // @param bank      BANK array index shared by the request and due record.
  // @param req       Nullable actual MEM request handle from the transaction.
  // @param rec       Nullable scheduler record due in the sampled cycle.
  // @param txn       Transaction providing the current cycle number.
  // @param result    Per-cycle result updated for a match or violation.
  //------------------------------------------------------------------------------
  extern protected function void check_mem_request_pair(
      vlm_reservation_direction_e                 direction,
      int unsigned                                bank,
      const ref vlm_mem_req                       req,
      const ref vlm_shm_record_t                  rec,
      const ref vlm_reservation_cycle_transaction_t txn,
      ref       vlm_reservation_check_result_t      result);

  `uvm_component_utils(vlm_reservation_checker)

endclass : vlm_reservation_checker

//------------------------------------------------------------------------------
// vlm_reservation_checker method implementations
//------------------------------------------------------------------------------

function vlm_reservation_checker::new(string name = "vlm_reservation_checker", uvm_component parent = null);
  super.new(name, parent);

  reservation_error_count   = 0;
  busy_error_count          = 0;
  mem_match_error_count     = 0;
  dly_zero_error_count      = 0;
  matched_mem_request_count = 0;
  initialize_result(current_result);
endfunction : new

function void vlm_reservation_checker::build_phase(uvm_phase phase);
  super.build_phase(phase);

  // Every cycle-aware component must use the repository-wide cycle source.
  if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
    `uvm_fatal("VLM_RESERVATION_NO_CLK_VIF", "vlm_reservation_checker requires virtual clk_if 'clk_vif'")
  end
endfunction : build_phase

function vlm_reservation_check_result_t vlm_reservation_checker::check_cycle(
    const ref vlm_reservation_cycle_transaction_t txn);
  initialize_result(current_result);

  // The checker cannot interpret relative-delay state without the scheduler's pre-update view.
  if (scheduler == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_SCHEDULER", "check_cycle() requires checker.scheduler")
    current_result.passed = 1'b0;
    return current_result;
  end

  // The transaction cycle must remain tied to the shared clk_if instead of an independent counter.
  if (clk_vif == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_CLK_VIF", "check_cycle() requires checker.clk_vif")
    current_result.passed = 1'b0;
    return current_result;
  end

  // Detect an environment ordering error before using txn.cycle in record due-cycle checks.
  if (txn.cycle != clk_vif.cycle_count) begin
    current_result.busy_error_count++;
    busy_error_count++;
    `uvm_error("VLM_RESERVATION_CYCLE_MISMATCH",
               $sformatf("transaction cycle %0d does not match clk_if cycle %0d",
                         txn.cycle, clk_vif.cycle_count))
  end

  // After the first transaction, the scheduler must still expose the immediately preceding processed cycle.
  if (scheduler.has_processed_cycle && scheduler.last_processed_cycle + 1 != txn.cycle) begin
    current_result.busy_error_count++;
    busy_error_count++;
    `uvm_error("VLM_RESERVATION_SCHEDULER_CYCLE",
               $sformatf("cycle %0d sees scheduler last processed cycle %0d",
                         txn.cycle, scheduler.last_processed_cycle))
  end

  check_busy_state(txn, current_result);
  check_reservation_requests(txn, current_result);
  check_mem_requests(txn, current_result);

  current_result.passed = current_result.reservation_error_count == 0 &&
                          current_result.busy_error_count == 0 &&
                          current_result.mem_match_error_count == 0 &&
                          current_result.dly_zero_error_count == 0;
  return current_result;
endfunction : check_cycle

function void vlm_reservation_checker::initialize_result(ref vlm_reservation_check_result_t result);
  result.passed                    = 1'b1;
  result.reservation_error_count   = 0;
  result.busy_error_count          = 0;
  result.mem_match_error_count     = 0;
  result.dly_zero_error_count      = 0;
  result.matched_mem_request_count = 0;
endfunction : initialize_result

function void vlm_reservation_checker::check_busy_state(
    const ref vlm_reservation_cycle_transaction_t txn,
    ref       vlm_reservation_check_result_t      result);
  bit expected_busy;
  bit has_record;
  int unsigned rec_sub_bank;
  longint unsigned expected_due_cycle;
  vlm_shm_record_t rec;

  // Validate every scheduler-owned record once using its direction, relative-delay, and BANK indices.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    // Every relative-delay entry must describe txn.cycle plus its array offset.
    for (int unsigned delay = 0; delay < VTAB_D; delay++) begin
      // BANK is represented by the fixed array index rather than a field in the record.
      for (int unsigned bank = 0; bank < BANK_N; bank++) begin
        rec = scheduler.shm_records[direction][delay][bank];
        if (rec == null) begin
          continue;
        end

        // Scheduler records may only represent supported nonzero-delay reservations.
        if (rec.issue_delay == 0 || rec.issue_delay >= VTAB_D) begin
          result.busy_error_count++;
          busy_error_count++;
          `uvm_error("VLM_RESERVATION_RECORD_DELAY",
                     $sformatf("cycle %0d direction %0d delay %0d bank %0d record has issue delay %0d",
                               txn.cycle, direction, delay, bank, rec.issue_delay))
        end

        // Every stored beat address must retain the interface's 32-byte alignment.
        if (rec.address[4:0] != 5'b0) begin
          result.busy_error_count++;
          busy_error_count++;
          `uvm_error("VLM_RESERVATION_RECORD_ALIGNMENT",
                     $sformatf("cycle %0d direction %0d delay %0d bank %0d record address 0x%0h is unaligned",
                               txn.cycle, direction, delay, bank, rec.address))
        end

        expected_due_cycle = txn.cycle + delay;

        // Moving a record through the window must not alter its original issue-cycle equation.
        if (rec.issue_cycle + rec.issue_delay != expected_due_cycle) begin
          result.busy_error_count++;
          busy_error_count++;
          `uvm_error("VLM_RESERVATION_RECORD_DUE_CYCLE",
                     $sformatf({"cycle %0d direction %0d delay %0d bank %0d record issue cycle %0d ",
                                "and issue delay %0d produce due cycle %0d, expected %0d"},
                               txn.cycle, direction, delay, bank, rec.issue_cycle, rec.issue_delay,
                               rec.issue_cycle + rec.issue_delay, expected_due_cycle))
        end
      end
    end
  end

  // Check each read/write busy bit and derive SHM ownership by reducing records across all BANKs.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    // Busy state covers every future relative delay in the scheduler window.
    for (int unsigned delay = 0; delay < VTAB_D; delay++) begin
      // Sub-bank ownership is derived from address[6:5] of every record at this direction and delay.
      for (int unsigned sub_bank = 0; sub_bank < VLM_SUB_BANK_N; sub_bank++) begin
        has_record = 1'b0;

        // Multiple different BANK records may legally contribute to the same SHM busy bit.
        for (int unsigned bank = 0; bank < BANK_N; bank++) begin
          rec = scheduler.shm_records[direction][delay][bank];
          if (rec != null) begin
            rec_sub_bank = rec.address[6:5];
            if (rec_sub_bank == sub_bank) begin
              has_record = 1'b1;
            end
          end
        end

        expected_busy = scheduler.external_busy[direction][delay][sub_bank] |
                        scheduler.shm_busy[direction][delay][sub_bank];

        // External and DUT SHM ownership may never occupy the same direction, delay, and sub-bank slot.
        if (scheduler.external_busy[direction][delay][sub_bank] &&
            scheduler.shm_busy[direction][delay][sub_bank]) begin
          result.busy_error_count++;
          busy_error_count++;
          `uvm_error("VLM_RESERVATION_BUSY_OVERLAP",
                     $sformatf("cycle %0d direction %0d delay %0d sub bank %0d has external and SHM ownership",
                               txn.cycle, direction, delay, sub_bank))
        end

        // SHM busy must be exactly the OR reduction of all BANK records selecting this sub bank.
        if (scheduler.shm_busy[direction][delay][sub_bank] != has_record) begin
          result.busy_error_count++;
          busy_error_count++;
          `uvm_error("VLM_RESERVATION_SHM_BUSY_RECORD",
                     $sformatf("cycle %0d direction %0d delay %0d sub bank %0d SHM busy is %0b, expected %0b",
                               txn.cycle, direction, delay, sub_bank,
                               scheduler.shm_busy[direction][delay][sub_bank], has_record))
        end

        // Final busy is a derived view and must never differ from the OR of its two ownership sources.
        if (scheduler.final_busy[direction][delay][sub_bank] != expected_busy) begin
          result.busy_error_count++;
          busy_error_count++;
          `uvm_error("VLM_RESERVATION_FINAL_BUSY",
                     $sformatf("cycle %0d direction %0d delay %0d sub bank %0d final busy is %0b, expected %0b",
                               txn.cycle, direction, delay, sub_bank,
                               scheduler.final_busy[direction][delay][sub_bank], expected_busy))
        end

        // A cycle containing any monitor X/Z cannot provide a reliable normalized observed-busy comparison.
        if (!txn.input_error && txn.observed_busy[direction][delay][sub_bank] != expected_busy) begin
          result.busy_error_count++;
          busy_error_count++;
          `uvm_error("VLM_RESERVATION_OBSERVED_BUSY",
                     $sformatf("cycle %0d direction %0d delay %0d sub bank %0d observed busy is %0b, expected %0b",
                               txn.cycle, direction, delay, sub_bank,
                               txn.observed_busy[direction][delay][sub_bank], expected_busy))
        end
      end
    end
  end
endfunction : check_busy_state

function void vlm_reservation_checker::check_reservation_requests(
    const ref vlm_reservation_cycle_transaction_t txn,
    ref       vlm_reservation_check_result_t      result);
  // Each BANK has one independent read reservation port.
  for (int unsigned bank = 0; bank < BANK_N; bank++) begin
    if (txn.rsv_rreq_array[bank] != null) begin
      void'(check_reservation_request(VLM_RESERVATION_READ, bank, 0, txn.rsv_rreq_array[bank], txn, result));
    end
  end

  // Each BANK has WRITE_PORT_N write reservation ports that share one actual MEM write port.
  for (int unsigned bank = 0; bank < BANK_N; bank++) begin
    // Check every fully known write request independently while preserving its physical port index.
    for (int unsigned port = 0; port < WRITE_PORT_N; port++) begin
      if (txn.rsv_wreq_array[bank][port] != null) begin
        void'(check_reservation_request(
            VLM_RESERVATION_WRITE, bank, port, txn.rsv_wreq_array[bank][port], txn, result));
      end
    end
  end
endfunction : check_reservation_requests

function bit vlm_reservation_checker::check_reservation_request(
    vlm_reservation_direction_e                   direction,
    int unsigned                                  bank,
    int unsigned                                  write_port,
    const ref vlm_rsv_req                         rsv,
    const ref vlm_reservation_cycle_transaction_t txn,
    ref       vlm_reservation_check_result_t       result);
  bit request_is_valid;
  bit observed_target_busy;
  bit owned_target_busy;
  int unsigned sub_bank;
  vlm_rsv_req prev_rsv;

  request_is_valid = 1'b1;

  // The current verification profile reports dly zero and excludes it from normal scheduling.
  if (rsv.delay == 0) begin
    result.dly_zero_error_count++;
    dly_zero_error_count++;
    `uvm_error("VLM_RESERVATION_DLY_ZERO",
               $sformatf("cycle %0d direction %0d bank %0d port %0d uses unsupported dly == 0",
                         txn.cycle, direction, bank, write_port))
    return 1'b0;
  end

  // An out-of-range delay cannot safely index scheduler busy or record state.
  if (rsv.delay >= VTAB_D) begin
    result.reservation_error_count++;
    reservation_error_count++;
    `uvm_error("VLM_RESERVATION_DLY_RANGE",
               $sformatf("cycle %0d direction %0d bank %0d port %0d delay %0d is outside [1, %0d]",
                         txn.cycle, direction, bank, write_port, rsv.delay, VTAB_D - 1))
    return 1'b0;
  end

  // Every reservation represents one 32-byte MEM beat and must use a 32-byte-aligned address.
  if (rsv.address[4:0] != 5'b0) begin
    request_is_valid = 1'b0;
    result.reservation_error_count++;
    reservation_error_count++;
    `uvm_error("VLM_RESERVATION_ALIGNMENT",
               $sformatf("cycle %0d direction %0d bank %0d port %0d address 0x%0h is not 32-byte aligned",
                         txn.cycle, direction, bank, write_port, rsv.address))
  end

  sub_bank = rsv.address[6:5];
  observed_target_busy = !txn.input_error && txn.observed_busy[direction][rsv.delay][sub_bank];
  owned_target_busy = scheduler.external_busy[direction][rsv.delay][sub_bank] |
                      scheduler.shm_busy[direction][rsv.delay][sub_bank];

  // A request is illegal when either reliable observed busy or authoritative scheduler ownership is occupied.
  if (observed_target_busy || owned_target_busy) begin
    request_is_valid = 1'b0;
    result.reservation_error_count++;
    reservation_error_count++;
    `uvm_error("VLM_RESERVATION_TARGET_BUSY",
               $sformatf({"cycle %0d direction %0d bank %0d port %0d targets delay %0d sub bank %0d with ",
                          "observed busy %0b and scheduler ownership %0b"},
                         txn.cycle, direction, bank, write_port, rsv.delay, sub_bank,
                         observed_target_busy, owned_target_busy))
  end

  // A pending record at the same direction, delay, and BANK would require a second actual MEM port.
  if (scheduler.shm_records[direction][rsv.delay][bank] != null) begin
    request_is_valid = 1'b0;
    result.reservation_error_count++;
    reservation_error_count++;
    `uvm_error("VLM_RESERVATION_PENDING_BANK_DUE_CONFLICT",
               $sformatf("cycle %0d direction %0d bank %0d port %0d already has a record due at cycle %0d",
                         txn.cycle, direction, bank, write_port, txn.cycle + rsv.delay))
  end

  if (direction == VLM_RESERVATION_WRITE) begin
    // Compare only earlier ports so one same-cycle BANK conflict produces one checker error.
    for (int unsigned prev_port = 0; prev_port < write_port; prev_port++) begin
      prev_rsv = txn.rsv_wreq_array[bank][prev_port];

      // Two write reservations for one BANK may coexist only when their due cycles differ.
      if (prev_rsv != null && prev_rsv.delay == rsv.delay) begin
        request_is_valid = 1'b0;
        result.reservation_error_count++;
        reservation_error_count++;
        `uvm_error("VLM_RESERVATION_CURRENT_BANK_DUE_CONFLICT",
                   $sformatf({"cycle %0d write bank %0d ports %0d and %0d both become due at cycle %0d, ",
                              "regardless of their sub banks"},
                             txn.cycle, bank, prev_port, write_port, txn.cycle + rsv.delay))
      end
    end
  end

  return request_is_valid;
endfunction : check_reservation_request

function void vlm_reservation_checker::check_mem_requests(
    const ref vlm_reservation_cycle_transaction_t txn,
    ref       vlm_reservation_check_result_t      result);
  vlm_mem_req req;
  vlm_shm_record_t rec;

  // Read and write MEM ports are independent and each direction has one request slot per BANK.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    // Fixed BANK arrays make the direction and BANK portions of the matching key structural.
    for (int unsigned bank = 0; bank < BANK_N; bank++) begin
      if (direction == VLM_RESERVATION_READ) begin
        req = txn.mem_rreq_array[bank];
      end else begin
        req = txn.mem_wreq_array[bank];
      end

      rec = scheduler.shm_records[direction][0][bank];
      check_mem_request_pair(vlm_reservation_direction_e'(direction), bank, req, rec, txn, result);
    end
  end
endfunction : check_mem_requests

function void vlm_reservation_checker::check_mem_request_pair(
    vlm_reservation_direction_e                   direction,
    int unsigned                                  bank,
    const ref vlm_mem_req                         req,
    const ref vlm_shm_record_t                    rec,
    const ref vlm_reservation_cycle_transaction_t txn,
    ref       vlm_reservation_check_result_t       result);
  bit request_matches;
  int unsigned sub_bank;
  longint unsigned rec_due_cycle;

  // No actual request and no due record is the idle, matched state for this direction and BANK.
  if (req == null && rec == null) begin
    return;
  end

  // A fully known actual MEM request without a due record is always an unreserved access.
  if (req != null && rec == null) begin
    result.mem_match_error_count++;
    mem_match_error_count++;
    `uvm_error("VLM_RESERVATION_UNEXPECTED_MEM",
               $sformatf("cycle %0d direction %0d bank %0d address 0x%0h has no due reservation record",
                         txn.cycle, direction, bank, req.address))
    return;
  end

  // With a cycle-level input_error, null cannot reliably prove that this BANK produced no MEM request.
  if (req == null && rec != null) begin
    if (!txn.input_error) begin
      result.mem_match_error_count++;
      mem_match_error_count++;
      `uvm_error("VLM_RESERVATION_MISSING_MEM",
                 $sformatf("cycle %0d direction %0d bank %0d due address 0x%0h produced no MEM request",
                           txn.cycle, direction, bank, rec.address))
    end
    return;
  end

  request_matches = 1'b1;
  sub_bank = req.address[6:5];
  rec_due_cycle = rec.issue_cycle + rec.issue_delay;

  // Actual MEM addresses use the same 32-byte beat alignment as reservations.
  if (req.address[4:0] != 5'b0) begin
    request_matches = 1'b0;
    result.mem_match_error_count++;
    mem_match_error_count++;
    `uvm_error("VLM_RESERVATION_MEM_ALIGNMENT",
               $sformatf("cycle %0d direction %0d bank %0d MEM address 0x%0h is not 32-byte aligned",
                         txn.cycle, direction, bank, req.address))
  end

  // A legal MEM request requires exclusive SHM ownership of its delay-zero sub-bank slot.
  if (!scheduler.shm_busy[direction][0][sub_bank] ||
      scheduler.external_busy[direction][0][sub_bank]) begin
    request_matches = 1'b0;
    result.mem_match_error_count++;
    mem_match_error_count++;
    `uvm_error("VLM_RESERVATION_MEM_BUSY",
               $sformatf("cycle %0d direction %0d bank %0d sub bank %0d lacks exclusive SHM busy",
                         txn.cycle, direction, bank, sub_bank))
  end

  // BANK and direction match structurally; the remaining request-to-record key requires equal addresses.
  if (req.address != rec.address) begin
    request_matches = 1'b0;
    result.mem_match_error_count++;
    mem_match_error_count++;
    `uvm_error("VLM_RESERVATION_MEM_ADDRESS",
               $sformatf("cycle %0d direction %0d bank %0d MEM address 0x%0h, reserved address 0x%0h",
                         txn.cycle, direction, bank, req.address, rec.address))
  end

  // A delay-zero array position is a due match only when the immutable issue equation reaches txn.cycle.
  if (rec_due_cycle != txn.cycle) begin
    request_matches = 1'b0;
    result.mem_match_error_count++;
    mem_match_error_count++;
    `uvm_error("VLM_RESERVATION_MEM_DUE_CYCLE",
               $sformatf("cycle %0d direction %0d bank %0d record is due at cycle %0d",
                         txn.cycle, direction, bank, rec_due_cycle))
  end

  if (request_matches) begin
    result.matched_mem_request_count++;
    matched_mem_request_count++;
  end
endfunction : check_mem_request_pair

`endif // INC_VLM_RESERVATION_CHECKER_SVH
