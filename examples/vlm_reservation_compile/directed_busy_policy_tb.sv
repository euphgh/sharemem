`timescale 1ns/1ps

package vlm_directed_busy_policy_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
  `include "vlm_reservation_types.svh"
  `include "vlm_reservation_external_busy_policy.svh"
  `include "vlm_reservation_scheduler.svh"
endpackage : vlm_directed_busy_policy_test_pkg

module directed_busy_policy_tb;
  import uvm_pkg::*;
  import shm_util_package::*;
  import vlm_directed_busy_policy_test_pkg::*;

  logic clk = 1'b0;
  clk_if clock_service(clk);

  vlm_reservation_scheduler scheduler;
  vlm_reservation_directed_busy_policy directed_policy;

  //----------------------------------------------------------------------------
  // @brief Clears one scheduler input transaction for an exact cycle.
  //
  // @param txn   Transaction to initialize.
  // @param cycle Shared clock cycle assigned to the transaction.
  //----------------------------------------------------------------------------
  function automatic void initialize_transaction(
      ref   vlm_reservation_cycle_transaction_t txn,
      input longint unsigned                    cycle);
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
  // @brief Stops the policy test when one required condition is false.
  //
  // @param condition Condition that must be true.
  // @param message   Failure diagnostic.
  //----------------------------------------------------------------------------
  function automatic void check_true(bit condition, string message);
    if (!condition) begin
      $fatal(1, "%s", message);
    end
  endfunction : check_true

  initial begin
    vlm_reservation_cycle_transaction_t txn;
    int unsigned bank = 4;

    scheduler = new("scheduler", null);
    directed_policy = new("directed_policy");
    scheduler.clk_vif = clock_service;
    scheduler.external_busy_percent = 100;
    scheduler.external_busy_policy = directed_policy;

    directed_policy.add_busy_cycle(11, VLM_RESERVATION_READ, 2, 1, 3);
    directed_policy.add_busy_cycle(11, VLM_RESERVATION_WRITE, 2, 0, 1);
    directed_policy.add_busy_cycle(12, VLM_RESERVATION_WRITE, 1, 0, 2);
    directed_policy.add_busy_range(13, 14, VLM_RESERVATION_READ, 3, 0, 0);

    initialize_transaction(txn, 10);
    txn.rsv_wreq_array[bank][0] = new();
    txn.rsv_wreq_array[bank][0].address = BADDR_W'(1 << 5);
    txn.rsv_wreq_array[bank][0].delay = 3;
    txn.rsv_wreq_array[bank][0].gid = 0;
    scheduler.process_cycle(txn);

    check_true(scheduler.external_busy[VLM_RESERVATION_READ][2][1][3],
               "exact drive-cycle directive did not set the selected read slot");
    check_true(scheduler.shm_busy[VLM_RESERVATION_WRITE][2][0][1] &&
               !scheduler.external_busy[VLM_RESERVATION_WRITE][2][0][1],
               "directed external busy overlapped an admitted SHM-owned slot");
    check_true(scheduler.generated_external_slot_count == 1,
               "deterministic policy did not take precedence over 100-percent random generation");

    initialize_transaction(txn, 11);
    scheduler.process_cycle(txn);
    check_true(scheduler.external_busy[VLM_RESERVATION_READ][1][1][3],
               "existing external busy did not advance with the scheduler window");
    check_true(scheduler.external_busy[VLM_RESERVATION_WRITE][1][0][2],
               "second exact drive-cycle directive did not set the selected write slot");
    check_true(scheduler.generated_external_slot_count == 2,
               "an out-of-cycle directive or random fallback occupied an unexpected slot");

    initialize_transaction(txn, 12);
    scheduler.process_cycle(txn);
    check_true(scheduler.external_busy[VLM_RESERVATION_READ][3][0][0],
               "inclusive range did not start on its first drive cycle");

    initialize_transaction(txn, 13);
    scheduler.process_cycle(txn);
    check_true(scheduler.external_busy[VLM_RESERVATION_READ][2][0][0] &&
               scheduler.external_busy[VLM_RESERVATION_READ][3][0][0],
               "range policy did not retain shifted state and generate its final-cycle slot");

    $display("[VLM_DIRECTED_BUSY_POLICY_TEST] deterministic external-busy policy component test: PASS");
    $finish;
  end
endmodule : directed_busy_policy_tb
