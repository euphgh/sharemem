`ifndef INC_VLM_RESERVATION_COVERAGE_SVH
`define INC_VLM_RESERVATION_COVERAGE_SVH

//------------------------------------------------------------------------------
// @brief Defines the coverage-facing API for reservation scheduling behavior.
//
// Receives the same normalized transaction used by scheduler and checker and
// observes scheduler ownership state. Coverage consumes checker outcomes and
// never participates in request admission, scheduling, or busy-drive state.
//------------------------------------------------------------------------------
class vlm_reservation_coverage extends uvm_component;

  // Read-only scheduler handle assigned directly by the containing agent.
  vlm_reservation_scheduler scheduler;

  // Number of normalized cycle transactions sampled.
  longint unsigned sampled_cycle_count;

  // Number of request samples whose target slot has SHM ownership.
  longint unsigned shared_shm_slot_cycle_count;

  // Number of requests rejected by target-gid external ownership.
  longint unsigned external_block_count;

  // Number of unsupported dly-zero request samples.
  longint unsigned dly_zero_sample_count;

  // Number of sampled cycles containing normalized input errors.
  longint unsigned input_error_cycle_count;

  // Number of accepted reservation requests sampled.
  longint unsigned accepted_request_count;

  // Number of accepted requests observed while the opposite gid had external ownership.
  longint unsigned accepted_with_other_gid_external_count;

  // Number of MEM requests successfully resolved to a gid.
  longint unsigned matched_mem_request_sample_count;

  // Reservation admission coverage for this batch's gid/ownership contract.
  covergroup reservation_admission_cg with function sample(
      int unsigned direction,
      int unsigned bank,
      int unsigned gid,
      int unsigned sub_bank,
      int unsigned delay,
      bit          other_gid_external,
      bit          other_gid_shm,
      bit          accepted,
      bit          target_busy,
      bit          pending_conflict,
      bit          current_conflict);
    option.per_instance = 1;
    cp_direction: coverpoint direction { bins read = {0}; bins write = {1}; }
    cp_bank: coverpoint bank { bins first = {0}; bins middle[] = {[1:BANK_N-2]}; bins last = {BANK_N-1}; }
    cp_gid: coverpoint gid { bins low = {0}; bins high = {1}; }
    cp_sub_bank: coverpoint sub_bank { bins values[] = {[0:VLM_SUB_BANK_N-1]}; }
    cp_delay: coverpoint delay { bins supported[] = {[1:VTAB_D-1]}; bins zero = {0}; }
    cp_other_external: coverpoint other_gid_external;
    cp_other_shm: coverpoint other_gid_shm;
    cp_accepted: coverpoint accepted;
    cp_target_busy: coverpoint target_busy;
    cp_pending: coverpoint pending_conflict;
    cp_current: coverpoint current_conflict;
    cx_gid_other_owner_outcome: cross cp_gid, cp_other_external, cp_other_shm, cp_accepted;
  endgroup

  // Actual-MEM resolver coverage for direction, resolved gid, and outcome.
  covergroup mem_match_cg with function sample(
      int unsigned direction,
      int unsigned gid,
      bit          gid_valid,
      bit          matched,
      bit          unexpected,
      bit          missing,
      bit          address_mismatch);
    option.per_instance = 1;
    cp_direction: coverpoint direction { bins read = {0}; bins write = {1}; }
    cp_gid: coverpoint gid iff (gid_valid) { bins low = {0}; bins high = {1}; }
    cp_gid_valid: coverpoint gid_valid;
    cp_matched: coverpoint matched;
    cp_unexpected: coverpoint unexpected;
    cp_missing: coverpoint missing;
    cp_address_mismatch: coverpoint address_mismatch;
    cx_direction_gid_match: cross cp_direction, cp_gid, cp_matched;
  endgroup

  //------------------------------------------------------------------------------
  // @brief Constructs the reservation coverage component.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this coverage collector.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_reservation_coverage",
      uvm_component parent = null);

  //------------------------------------------------------------------------------
  // @brief Samples reservation admission and actual-MEM resolution outcomes.
  //
  // @param txn          Normalized reservation and MEM cycle transaction.
  // @param check_result Detailed result returned by the checker for this cycle.
  // @pre Scheduler state and transaction refer to the same cycle.
  // @post Coverage and diagnostic counters are updated; scheduler/checker state
  //       is unchanged.
  //------------------------------------------------------------------------------
  extern function void sample_cycle(
      const ref vlm_reservation_cycle_transaction_t txn,
      const ref vlm_reservation_check_result_t      check_result);

  `uvm_component_utils(vlm_reservation_coverage)

endclass : vlm_reservation_coverage

function vlm_reservation_coverage::new(string name = "vlm_reservation_coverage", uvm_component parent = null);
  super.new(name, parent);

  // Initialize the directed-batch diagnostic counters before sampling begins.
  sampled_cycle_count         = 0;
  shared_shm_slot_cycle_count = 0;
  external_block_count        = 0;
  dly_zero_sample_count       = 0;
  input_error_cycle_count     = 0;
  accepted_request_count      = 0;
  accepted_with_other_gid_external_count = 0;
  matched_mem_request_sample_count = 0;
  reservation_admission_cg = new();
  mem_match_cg = new();
endfunction : new

function void vlm_reservation_coverage::sample_cycle(
    const ref vlm_reservation_cycle_transaction_t txn,
    const ref vlm_reservation_check_result_t      check_result);
  sampled_cycle_count++;
  if (txn.input_error) begin
    input_error_cycle_count++;
  end

  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    for (int unsigned bank = 0; bank < BANK_N; bank++) begin
      vlm_mem_match_outcome_t mem_outcome = check_result.mem_match_outcome[direction][bank];

      if (mem_outcome.request_present || mem_outcome.record_present) begin
        mem_match_cg.sample(direction, check_result.mem_gid[direction][bank],
                            check_result.mem_gid_valid[direction][bank], mem_outcome.matched,
                            mem_outcome.unexpected, mem_outcome.missing, mem_outcome.address_mismatch);
      end
      if (mem_outcome.matched) begin
        matched_mem_request_sample_count++;
      end

      for (int unsigned port = 0; port < WRITE_PORT_N; port++) begin
        vlm_reservation_admission_outcome_t outcome = check_result.reservation_outcome[direction][bank][port];
        vlm_rsv_req rsv;
        int unsigned sub_bank;
        int unsigned other_gid;
        bit other_gid_external;
        bit other_gid_shm;

        if (!outcome.present || (direction == VLM_RESERVATION_READ && port != 0)) begin
          continue;
        end
        rsv = direction == VLM_RESERVATION_READ ? txn.rsv_rreq_array[bank] : txn.rsv_wreq_array[bank][port];
        if (rsv == null) begin
          continue;
        end
        sub_bank = rsv.address[6:5];
        other_gid = (int'(rsv.gid) + 1) % GID_N;
        other_gid_external = rsv.delay < VTAB_D && scheduler.external_busy[direction][rsv.delay][other_gid][sub_bank];
        other_gid_shm = rsv.delay < VTAB_D && scheduler.shm_busy[direction][rsv.delay][other_gid][sub_bank];
        reservation_admission_cg.sample(direction, bank, rsv.gid, sub_bank, rsv.delay,
                                        other_gid_external, other_gid_shm, outcome.accepted, outcome.target_busy,
                                        outcome.pending_bank_due_conflict, outcome.current_bank_due_conflict);
        if (outcome.accepted) begin
          accepted_request_count++;
          if (other_gid_external) begin
            accepted_with_other_gid_external_count++;
          end
        end
        if (outcome.target_busy) begin
          external_block_count++;
        end
        if (outcome.dly_zero) begin
          dly_zero_sample_count++;
        end
        if (rsv.delay < VTAB_D && scheduler.shm_busy[direction][rsv.delay][rsv.gid][sub_bank]) begin
          shared_shm_slot_cycle_count++;
        end
      end
    end
  end
endfunction : sample_cycle

`endif // INC_VLM_RESERVATION_COVERAGE_SVH
