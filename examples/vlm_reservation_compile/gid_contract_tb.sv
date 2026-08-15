`timescale 1ns/1ps

package vlm_gid_contract_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
  `include "shm_expected_report_catcher.svh"
  `include "vlm_reservation_types.svh"
  `include "vlm_reservation_external_busy_policy.svh"
  `include "vlm_reservation_scheduler.svh"
  `include "vlm_reservation_checker.svh"
  `include "vlm_reservation_coverage.svh"
endpackage : vlm_gid_contract_test_pkg

module gid_contract_tb;
  import uvm_pkg::*;
  import shm_util_package::*;
  import vlm_gid_contract_test_pkg::*;

  logic clk = 1'b0;
  clk_if clock_service(clk);

  vlm_reservation_scheduler scheduler;
  vlm_reservation_checker checker;
  vlm_reservation_coverage coverage_collector;
  shm_expected_report_catcher report_catcher;

  //----------------------------------------------------------------------------
  // @brief Clears a transaction and copies the current scheduler busy view.
  //
  // @param txn Transaction to initialize.
  // @param cycle Shared clock cycle assigned to the transaction.
  //----------------------------------------------------------------------------
  function automatic void initialize_transaction(ref vlm_reservation_cycle_transaction_t txn,
                                                  input longint unsigned cycle);
    clock_service.cycle_count = cycle;
    txn.cycle = cycle;
    txn.observed_busy[VLM_RESERVATION_READ] = scheduler.final_busy[VLM_RESERVATION_READ];
    txn.observed_busy[VLM_RESERVATION_WRITE] = scheduler.final_busy[VLM_RESERVATION_WRITE];
    txn.input_error = 1'b0;
    foreach (txn.rsv_rreq_array[bank]) begin
      txn.rsv_rreq_array[bank] = null;
      txn.mem_rreq_array[bank] = null;
      txn.mem_wreq_array[bank] = null;
    end
    foreach (txn.rsv_wreq_array[bank, port]) begin
      txn.rsv_wreq_array[bank][port] = null;
    end
  endfunction : initialize_transaction

  //----------------------------------------------------------------------------
  // @brief Stops the component test when a required condition is false.
  //
  // @param condition Condition that must be true.
  // @param message Failure diagnostic.
  //----------------------------------------------------------------------------
  function automatic void check_true(bit condition, string message);
    if (!condition) begin
      $fatal(1, "%s", message);
    end
  endfunction : check_true

  //----------------------------------------------------------------------------
  // @brief Clears all mutable scheduler ownership and record state.
  //----------------------------------------------------------------------------
  function automatic void clear_scheduler_state();
    for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
      scheduler.external_busy[direction] = '0;
      scheduler.shm_busy[direction] = '0;
      scheduler.final_busy[direction] = '0;
    end
    foreach (scheduler.shm_records[direction, delay, bank]) begin
      scheduler.shm_records[direction][delay][bank] = null;
    end
  endfunction : clear_scheduler_state

  initial begin
    vlm_reservation_cycle_transaction_t txn;
    vlm_reservation_check_result_t result;
    vlm_shm_record_t rec;
    int unsigned bank = 2;
    int unsigned delay = 3;
    int unsigned sub_bank = 1;

    scheduler = new("scheduler", null);
    checker = new("checker", null);
    coverage_collector = new("coverage_collector", null);
    scheduler.clk_vif = clock_service;
    checker.clk_vif = clock_service;
    checker.scheduler = scheduler;
    coverage_collector.scheduler = scheduler;

    report_catcher = new();
    report_catcher.expect_report("VLM_RESERVATION_TARGET_BUSY");
    report_catcher.expect_report("VLM_RESERVATION_PENDING_BANK_DUE_CONFLICT");
    report_catcher.expect_report("VLM_RESERVATION_CURRENT_BANK_DUE_CONFLICT");
    report_catcher.expect_report("VLM_RESERVATION_UNEXPECTED_MEM");
    report_catcher.expect_report("VLM_RESERVATION_MISSING_MEM");
    report_catcher.expect_report("VLM_RESERVATION_MEM_ADDRESS");
    uvm_report_cb::add(null, report_catcher);

    // Target-gid external ownership blocks the request and is visible in structured metadata.
    scheduler.external_busy[VLM_RESERVATION_WRITE][delay][0][sub_bank] = 1'b1;
    scheduler.final_busy[VLM_RESERVATION_WRITE][delay][0][sub_bank] = 1'b1;
    initialize_transaction(txn, 10);
    txn.rsv_wreq_array[bank][0] = new();
    txn.rsv_wreq_array[bank][0].address = BADDR_W'(sub_bank << 5);
    txn.rsv_wreq_array[bank][0].delay = delay;
    txn.rsv_wreq_array[bank][0].gid = 0;
    result = checker.check_cycle(txn);
    coverage_collector.sample_cycle(txn, result);
    check_true(result.reservation_outcome[VLM_RESERVATION_WRITE][bank][0].target_busy,
               "target-gid busy outcome was not recorded");

    // The same external slot in the other gid does not block this request.
    clear_scheduler_state();
    scheduler.external_busy[VLM_RESERVATION_WRITE][delay][1][sub_bank] = 1'b1;
    scheduler.final_busy[VLM_RESERVATION_WRITE][delay][1][sub_bank] = 1'b1;
    initialize_transaction(txn, 11);
    txn.rsv_wreq_array[bank][0] = new();
    txn.rsv_wreq_array[bank][0].address = BADDR_W'(sub_bank << 5);
    txn.rsv_wreq_array[bank][0].delay = delay;
    txn.rsv_wreq_array[bank][0].gid = 0;
    result = checker.check_cycle(txn);
    coverage_collector.sample_cycle(txn, result);
    check_true(result.passed && result.reservation_outcome[VLM_RESERVATION_WRITE][bank][0].accepted,
               "other-gid external busy incorrectly blocked request");

    // Two current write ports for one BANK/due cycle have one accepted and one rejected outcome.
    clear_scheduler_state();
    initialize_transaction(txn, 12);
    for (int unsigned port = 0; port < WRITE_PORT_N; port++) begin
      txn.rsv_wreq_array[bank][port] = new();
      txn.rsv_wreq_array[bank][port].address = BADDR_W'((sub_bank << 5) + port);
      txn.rsv_wreq_array[bank][port].delay = delay;
      txn.rsv_wreq_array[bank][port].gid = shm_gid_t'(port);
    end
    result = checker.check_cycle(txn);
    coverage_collector.sample_cycle(txn, result);
    check_true(result.reservation_outcome[VLM_RESERVATION_WRITE][bank][0].accepted &&
               result.reservation_outcome[VLM_RESERVATION_WRITE][bank][1].current_bank_due_conflict,
               "same-BANK/current-due port conflict metadata is incorrect");

    // A historical record for the same direction/BANK/due cycle blocks either gid.
    clear_scheduler_state();
    rec = new();
    rec.address = BADDR_W'(sub_bank << 5);
    rec.gid = 1;
    rec.write_port = 0;
    rec.issue_cycle = 12;
    rec.issue_delay = delay + 1;
    scheduler.shm_records[VLM_RESERVATION_WRITE][delay][bank] = rec;
    scheduler.shm_busy[VLM_RESERVATION_WRITE][delay][1][sub_bank] = 1'b1;
    scheduler.final_busy[VLM_RESERVATION_WRITE][delay][1][sub_bank] = 1'b1;
    initialize_transaction(txn, 13);
    txn.rsv_wreq_array[bank][0] = new();
    txn.rsv_wreq_array[bank][0].address = BADDR_W'(sub_bank << 5);
    txn.rsv_wreq_array[bank][0].delay = delay;
    txn.rsv_wreq_array[bank][0].gid = 0;
    result = checker.check_cycle(txn);
    coverage_collector.sample_cycle(txn, result);
    check_true(result.reservation_outcome[VLM_RESERVATION_WRITE][bank][0].pending_bank_due_conflict,
               "historical same-BANK/due record did not block the other gid");

    // Different BANK records and a new request may share one SHM gid/sub-bank busy slot.
    clear_scheduler_state();
    for (int unsigned shared_bank = 0; shared_bank < 2; shared_bank++) begin
      rec = new();
      rec.address = BADDR_W'(sub_bank << 5);
      rec.gid = 0;
      rec.write_port = 0;
      rec.issue_cycle = 14;
      rec.issue_delay = delay;
      scheduler.shm_records[VLM_RESERVATION_WRITE][delay][shared_bank] = rec;
    end
    scheduler.shm_busy[VLM_RESERVATION_WRITE][delay][0][sub_bank] = 1'b1;
    scheduler.final_busy[VLM_RESERVATION_WRITE][delay][0][sub_bank] = 1'b1;
    initialize_transaction(txn, 14);
    txn.rsv_wreq_array[bank][0] = new();
    txn.rsv_wreq_array[bank][0].address = BADDR_W'(sub_bank << 5);
    txn.rsv_wreq_array[bank][0].delay = delay;
    txn.rsv_wreq_array[bank][0].gid = 0;
    result = checker.check_cycle(txn);
    coverage_collector.sample_cycle(txn, result);
    check_true(result.passed && result.reservation_outcome[VLM_RESERVATION_WRITE][bank][0].accepted,
               "different BANK request was blocked from sharing an SHM busy slot");

    // Read and write directions have independent BANK/due ownership.
    clear_scheduler_state();
    initialize_transaction(txn, 15);
    txn.rsv_rreq_array[bank] = new();
    txn.rsv_rreq_array[bank].address = BADDR_W'(sub_bank << 5);
    txn.rsv_rreq_array[bank].delay = delay;
    txn.rsv_rreq_array[bank].gid = 0;
    txn.rsv_wreq_array[bank][0] = new();
    txn.rsv_wreq_array[bank][0].address = BADDR_W'(sub_bank << 5);
    txn.rsv_wreq_array[bank][0].delay = delay;
    txn.rsv_wreq_array[bank][0].gid = 0;
    result = checker.check_cycle(txn);
    coverage_collector.sample_cycle(txn, result);
    check_true(result.passed && result.reservation_outcome[VLM_RESERVATION_READ][bank][0].accepted &&
               result.reservation_outcome[VLM_RESERVATION_WRITE][bank][0].accepted,
               "same-BANK/read-write requests were not treated as direction-independent");

    // An actual MEM request without a due record remains unresolved.
    clear_scheduler_state();
    initialize_transaction(txn, 16);
    txn.mem_wreq_array[bank] = new();
    txn.mem_wreq_array[bank].address = 'h123;
    result = checker.check_cycle(txn);
    coverage_collector.sample_cycle(txn, result);
    check_true(result.mem_match_outcome[VLM_RESERVATION_WRITE][bank].unexpected &&
               !result.mem_gid_valid[VLM_RESERVATION_WRITE][bank],
               "unexpected MEM request received trusted gid metadata");

    // A due record resolves its gid only when the complete MEM address matches.
    rec = new();
    rec.address = 'h123;
    rec.gid = 1;
    rec.write_port = 0;
    rec.issue_cycle = 15;
    rec.issue_delay = 2;
    scheduler.shm_records[VLM_RESERVATION_WRITE][0][bank] = rec;
    scheduler.shm_busy[VLM_RESERVATION_WRITE][0][1][1] = 1'b1;
    scheduler.final_busy[VLM_RESERVATION_WRITE][0][1][1] = 1'b1;
    initialize_transaction(txn, 17);
    txn.mem_wreq_array[bank] = new();
    txn.mem_wreq_array[bank].address = 'h123;
    result = checker.check_cycle(txn);
    coverage_collector.sample_cycle(txn, result);
    check_true(result.mem_match_outcome[VLM_RESERVATION_WRITE][bank].matched &&
               result.mem_gid_valid[VLM_RESERVATION_WRITE][bank] &&
               result.mem_gid[VLM_RESERVATION_WRITE][bank] == 1,
               "matching due record did not resolve gid one");

    initialize_transaction(txn, 17);
    txn.mem_wreq_array[bank] = new();
    txn.mem_wreq_array[bank].address = 'h120;
    result = checker.check_cycle(txn);
    coverage_collector.sample_cycle(txn, result);
    check_true(result.mem_match_outcome[VLM_RESERVATION_WRITE][bank].address_mismatch &&
               !result.mem_gid_valid[VLM_RESERVATION_WRITE][bank],
               "address mismatch produced trusted gid metadata");

    // A due record without an actual MEM request produces an explicit missing outcome.
    clear_scheduler_state();
    rec = new();
    rec.address = 'h321;
    rec.gid = 0;
    rec.write_port = 0;
    rec.issue_cycle = 16;
    rec.issue_delay = 2;
    scheduler.shm_records[VLM_RESERVATION_WRITE][0][bank] = rec;
    scheduler.shm_busy[VLM_RESERVATION_WRITE][0][0][1] = 1'b1;
    scheduler.final_busy[VLM_RESERVATION_WRITE][0][0][1] = 1'b1;
    initialize_transaction(txn, 18);
    result = checker.check_cycle(txn);
    coverage_collector.sample_cycle(txn, result);
    check_true(result.mem_match_outcome[VLM_RESERVATION_WRITE][bank].missing &&
               !result.mem_gid_valid[VLM_RESERVATION_WRITE][bank],
               "missing MEM request did not produce an unresolved outcome");

    // A complete gid-zero record/address match also produces trusted gid metadata.
    clear_scheduler_state();
    rec = new();
    rec.address = 'h40;
    rec.gid = 0;
    rec.write_port = 0;
    rec.issue_cycle = 18;
    rec.issue_delay = 2;
    scheduler.shm_records[VLM_RESERVATION_WRITE][0][bank] = rec;
    scheduler.shm_busy[VLM_RESERVATION_WRITE][0][0][2] = 1'b1;
    scheduler.final_busy[VLM_RESERVATION_WRITE][0][0][2] = 1'b1;
    initialize_transaction(txn, 20);
    txn.mem_wreq_array[bank] = new();
    txn.mem_wreq_array[bank].address = 'h40;
    result = checker.check_cycle(txn);
    coverage_collector.sample_cycle(txn, result);
    check_true(result.mem_match_outcome[VLM_RESERVATION_WRITE][bank].matched &&
               result.mem_gid_valid[VLM_RESERVATION_WRITE][bank] &&
               result.mem_gid[VLM_RESERVATION_WRITE][bank] == 0,
               "matching due record did not resolve gid zero");

    check_true(coverage_collector.accepted_request_count != 0 &&
               coverage_collector.external_block_count != 0 &&
               coverage_collector.matched_mem_request_sample_count != 0,
               "reservation coverage did not sample required outcomes");
    check_true(report_catcher.expectations_met(), "expected report counts do not match observed counts");
    $display("[VLM_GID_CONTRACT_TEST] reservation ownership and resolver component test: PASS");
    $finish;
  end
endmodule : gid_contract_tb
