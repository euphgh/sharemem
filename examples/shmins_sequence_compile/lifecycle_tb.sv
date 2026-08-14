`timescale 1ns/1ps

package shmins_lifecycle_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;
  import shm_seq_item_package::*;

  `include "uvm_macros.svh"

  // Minimal component-test configuration required by the production checker.
  class shm_environment_config extends uvm_object;
    int unsigned ack_post_complete_grace_cycles = 20;

    function new(string name = "shm_environment_config");
      super.new(name);
    endfunction : new

    `uvm_object_utils(shm_environment_config)
  endclass : shm_environment_config

  `include "shm_transaction_lifecycle_types.svh"
  `include "shm_transaction_lifecycle_checker.svh"
endpackage : shmins_lifecycle_test_pkg

//------------------------------------------------------------------------------
// @brief Verifies ordered ack-grace eligibility without instantiating a DUT.
//
// Exercises slow-old/fast-young completion, ack-disabled predecessors,
// independent directions, and a young transaction that acks before the old
// direction head. It does not execute checker clock/reset phase behavior.
//------------------------------------------------------------------------------
module shmins_lifecycle_order_tb;
  import uvm_pkg::*;
  import shm_util_package::*;
  import shm_seq_item_package::*;
  import shmins_lifecycle_test_pkg::*;

  shm_transaction_lifecycle_checker checker;

  //----------------------------------------------------------------------------
  // @brief Stops the directed test when a condition is false.
  //
  // @param condition Condition that must evaluate to one.
  // @param message   Failure description printed with the fatal report.
  //----------------------------------------------------------------------------
  function automatic void check_true(bit condition, string message);
    if (!condition) begin
      $fatal(1, "%s", message);
    end
  endfunction : check_true

  //----------------------------------------------------------------------------
  // @brief Creates and submits one accepted transaction to the checker.
  //
  // @param uid          Monotonic monitor-owned transaction identity.
  // @param direction    V2M or M2V ordered channel.
  // @param id           Interface transaction ID.
  // @param ack_required Whether this transaction requires an ack.
  // @param cycle        Accepted transaction cycle.
  //----------------------------------------------------------------------------
  function automatic void accept_transaction(
      shm_transaction_uid_t uid,
      creq_rw_e             direction,
      logic [ID_W-1:0]      id,
      bit                   ack_required,
      shm_cycle_t           cycle);
    shmins_sequence_item transaction = shmins_sequence_item::type_id::create($sformatf("txn_%0d", uid));

    transaction.transaction_uid = uid;
    transaction.creq_rw = direction;
    transaction.creq_id = id;
    transaction.creq_ack_en = ack_required;
    transaction.accept_cycle = cycle;
    transaction.reset_epoch = 0;
    checker.write_shm_lifecycle_accept(transaction);
  endfunction : accept_transaction

  //----------------------------------------------------------------------------
  // @brief Submits an observed data completion for one transaction.
  //
  // @param uid   Transaction identity being completed.
  // @param cycle Shared clock cycle of completion.
  //----------------------------------------------------------------------------
  function automatic void observe_completion(
      shm_transaction_uid_t uid, shm_cycle_t cycle);
    shm_completion_event completion = shm_completion_event::type_id::create(
        $sformatf("completion_%0d", uid));

    completion.transaction_uid = uid;
    completion.kind = SHM_COMPLETION_OBSERVED;
    completion.cycle = cycle;
    checker.write_shm_lifecycle_completion(completion);
  endfunction : observe_completion

  //----------------------------------------------------------------------------
  // @brief Submits one raw ack event to the checker.
  //
  // @param direction Ack channel direction.
  // @param id        Interface transaction ID.
  // @param cycle     Shared clock cycle of the ack.
  //----------------------------------------------------------------------------
  function automatic void submit_ack(
      creq_rw_e direction, logic [ID_W-1:0] id, shm_cycle_t cycle);
    shmins_ack_event ack_event = shmins_ack_event::type_id::create(
        $sformatf("ack_%s_%0d", direction.name(), id));

    ack_event.direction = direction;
    ack_event.transaction_id = id;
    ack_event.cycle = cycle;
    ack_event.reset_epoch = 0;
    checker.write_shm_lifecycle_ack(ack_event);
  endfunction : submit_ack

  initial begin
    checker = new("checker", null);

    // A fast young V2M completion remains ineligible until the slow old
    // ack-required transaction completes and receives its ordered ack.
    accept_transaction(1, SHM_V2M, 8'h00, 1'b1, 10);
    accept_transaction(2, SHM_V2M, 8'h01, 1'b1, 11);
    observe_completion(2, 30);
    check_true(!checker.records[2].grace_started,
               "young V2M transaction started grace before old data completion");
    observe_completion(1, 100);
    check_true(checker.records[1].grace_started &&
               checker.records[1].grace_start_cycle == 100,
               "old V2M direction head did not start grace at data completion");
    check_true(!checker.records[2].grace_started,
               "young V2M transaction started grace before old ack retirement");
    submit_ack(SHM_V2M, 8'h00, 103);
    check_true(!checker.records.exists(1), "old V2M transaction did not retire after ack");
    check_true(checker.records[2].grace_started &&
               checker.records[2].grace_start_cycle == 103,
               "young V2M transaction did not start grace after old retirement");
    submit_ack(SHM_V2M, 8'h01, 104);

    // An ack-disabled predecessor still blocks the ordered channel until its
    // data is resolved, then the already-observed young request becomes head.
    accept_transaction(3, SHM_V2M, 8'h02, 1'b0, 200);
    accept_transaction(4, SHM_V2M, 8'h03, 1'b1, 201);
    observe_completion(4, 210);
    check_true(!checker.records[4].grace_started,
               "young transaction bypassed unresolved ack-disabled predecessor");
    observe_completion(3, 220);
    check_true(!checker.records.exists(3), "ack-disabled predecessor did not retire on data resolution");
    check_true(checker.records[4].grace_started &&
               checker.records[4].grace_start_cycle == 220,
               "young transaction did not start grace after ack-disabled predecessor retired");
    submit_ack(SHM_V2M, 8'h03, 221);

    // V2M and M2V maintain independent ordered channels.
    accept_transaction(5, SHM_V2M, 8'h04, 1'b1, 300);
    accept_transaction(6, SHM_M2V, 8'h05, 1'b1, 301);
    observe_completion(6, 310);
    check_true(checker.records[6].grace_started &&
               checker.records[6].grace_start_cycle == 310,
               "slow V2M transaction incorrectly blocked M2V grace");
    submit_ack(SHM_M2V, 8'h05, 311);
    observe_completion(5, 320);
    submit_ack(SHM_V2M, 8'h04, 321);

    // A young early ack is accepted without an out-of-order error. Its record
    // remains ordered behind the old request and retires when the old head does.
    accept_transaction(7, SHM_V2M, 8'h06, 1'b1, 400);
    accept_transaction(8, SHM_V2M, 8'h07, 1'b1, 401);
    observe_completion(8, 410);
    submit_ack(SHM_V2M, 8'h07, 411);
    check_true(checker.records.exists(8) && checker.records[8].ack_received,
               "young early ack did not update state while ordered behind old request");
    check_true(!checker.records[8].grace_started,
               "young early-acked transaction incorrectly started grace");
    observe_completion(7, 420);
    submit_ack(SHM_V2M, 8'h06, 421);
    check_true(!checker.records.exists(7) && !checker.records.exists(8),
               "ordered retirement did not drain old and already-complete young records");

    check_true(checker.is_idle(), "lifecycle checker did not become idle after all scenarios");
    $display("[SHMINS_LIFECYCLE_TEST] ordered ack grace regression: PASS");
    $finish;
  end
endmodule : shmins_lifecycle_order_tb
