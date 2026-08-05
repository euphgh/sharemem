`timescale 1ns/1ps

package vlm_reservation_alignment_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
  `include "vlm_reservation_types.svh"
  `include "vlm_reservation_scheduler.svh"
  `include "vlm_reservation_checker.svh"
endpackage : vlm_reservation_alignment_test_pkg

module alignment_tb;
  import uvm_pkg::*;
  import shm_util_package::*;
  import vlm_reservation_alignment_test_pkg::*;

  logic clk = 1'b0;
  clk_if clock_service(clk);

  vlm_reservation_scheduler scheduler;
  vlm_reservation_checker   reservation_checker;

  //----------------------------------------------------------------------------
  // @brief Clears one transaction and copies the scheduler busy view for a cycle.
  //
  // @param txn   Transaction to initialize with null request handles.
  // @param cycle Cycle number assigned to both the transaction and clock service.
  //----------------------------------------------------------------------------
  function automatic void initialize_transaction(
      ref vlm_reservation_cycle_transaction_t txn,
      input longint unsigned                  cycle);
    clock_service.cycle_count = cycle;
    txn.cycle = cycle;
    txn.observed_busy[VLM_RESERVATION_READ]  = scheduler.final_busy[VLM_RESERVATION_READ];
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
  // @brief Stops the directed regression when a condition is false.
  //
  // @param condition Condition that must evaluate to one.
  // @param message   Failure description printed with the fatal report.
  //----------------------------------------------------------------------------
  function automatic void check_true(bit condition, string message);
    if (!condition) begin
      $fatal(1, "%s", message);
    end
  endfunction : check_true

  initial begin
    vlm_reservation_cycle_transaction_t txn;
    vlm_reservation_check_result_t result;
    longint unsigned accepted_before;
    longint unsigned rejected_before;
    int unsigned bank;

    scheduler           = new("scheduler", null);
    reservation_checker = new("reservation_checker", null);

    scheduler.clk_vif = clock_service;
    reservation_checker.clk_vif   = clock_service;
    reservation_checker.scheduler = scheduler;

    // Expected negative cases are checked through result counters instead of UVM report output.
    reservation_checker.set_report_id_action("VLM_RESERVATION_ALIGNMENT", UVM_NO_ACTION);
    reservation_checker.set_report_id_action("VLM_RESERVATION_MEM_ADDRESS", UVM_NO_ACTION);

    // Write port 0 accepts and preserves a non-32-byte-aligned reservation.
    bank = 2;
    initialize_transaction(txn, 1);
    txn.rsv_wreq_array[bank][0] = new();
    txn.rsv_wreq_array[bank][0].address = 'h123;
    txn.rsv_wreq_array[bank][0].delay   = 2;

    result = reservation_checker.check_cycle(txn);
    check_true(result.passed, "write port 0 nonaligned reservation was rejected by checker");
    scheduler.process_cycle(txn);
    check_true(scheduler.shm_records[VLM_RESERVATION_WRITE][1][bank] != null,
               "write port 0 nonaligned reservation was not scheduled");
    check_true(scheduler.shm_records[VLM_RESERVATION_WRITE][1][bank].address == 'h123,
               "scheduler changed write port 0 address low bits");
    check_true(scheduler.shm_records[VLM_RESERVATION_WRITE][1][bank].write_port == 0,
               "scheduler did not retain write port 0 provenance");

    // Advance the record to its due slot without producing an actual request yet.
    initialize_transaction(txn, 2);
    result = reservation_checker.check_cycle(txn);
    check_true(result.passed, "write port 0 record failed while advancing to its due cycle");
    scheduler.process_cycle(txn);

    // The exact same nonaligned MEM write address satisfies the due reservation.
    initialize_transaction(txn, 3);
    txn.mem_wreq_array[bank] = new();
    txn.mem_wreq_array[bank].address = 'h123;
    result = reservation_checker.check_cycle(txn);
    check_true(result.mem_match_error_count == 0 && result.matched_mem_request_count == 1,
               "exact nonaligned MEM write address did not match its reservation");
    scheduler.process_cycle(txn);

    // Write port 1 retains the original 32-byte alignment requirement.
    bank = 3;
    accepted_before = scheduler.accepted_record_count;
    rejected_before = scheduler.rejected_record_count;
    initialize_transaction(txn, 4);
    txn.rsv_wreq_array[bank][1] = new();
    txn.rsv_wreq_array[bank][1].address = 'h123;
    txn.rsv_wreq_array[bank][1].delay   = 2;
    result = reservation_checker.check_cycle(txn);
    check_true(result.reservation_error_count == 1,
               "write port 1 nonaligned reservation did not report one alignment error");
    scheduler.process_cycle(txn);
    check_true(scheduler.accepted_record_count == accepted_before,
               "write port 1 nonaligned reservation was accepted");
    check_true(scheduler.rejected_record_count == rejected_before + 1,
               "write port 1 nonaligned reservation was not counted as rejected");

    // Issue another legal nonaligned port-0 reservation for an exact-address mismatch test.
    bank = 4;
    initialize_transaction(txn, 5);
    txn.rsv_wreq_array[bank][0] = new();
    txn.rsv_wreq_array[bank][0].address = 'h123;
    txn.rsv_wreq_array[bank][0].delay   = 2;
    result = reservation_checker.check_cycle(txn);
    check_true(result.passed, "second write port 0 nonaligned reservation was rejected");
    scheduler.process_cycle(txn);

    initialize_transaction(txn, 6);
    result = reservation_checker.check_cycle(txn);
    check_true(result.passed, "second write port 0 record failed before its due cycle");
    scheduler.process_cycle(txn);

    // An aligned address in the same 32-byte beat is not an exact match for 0x123.
    initialize_transaction(txn, 7);
    txn.mem_wreq_array[bank] = new();
    txn.mem_wreq_array[bank].address = 'h120;
    result = reservation_checker.check_cycle(txn);
    check_true(result.mem_match_error_count == 1 && result.matched_mem_request_count == 0,
               "MEM write differing only in low address bits was accepted");
    scheduler.process_cycle(txn);

    $display("vlm reservation alignment regression: PASS");
    $finish;
  end

endmodule : alignment_tb
