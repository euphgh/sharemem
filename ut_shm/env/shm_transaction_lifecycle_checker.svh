`ifndef INC_SHM_TRANSACTION_LIFECYCLE_CHECKER_SVH
`define INC_SHM_TRANSACTION_LIFECYCLE_CHECKER_SVH

`uvm_analysis_imp_decl(_shm_lifecycle_accept)
`uvm_analysis_imp_decl(_shm_lifecycle_ack)
`uvm_analysis_imp_decl(_shm_lifecycle_completion)

//------------------------------------------------------------------------------
// @brief Correlates accepted creq, scoreboard data completion, and ack events.
//
// The checker enforces ack direction, ID, enable, and exactly-once semantics.
// It preserves independent V2M and M2V acceptance order when deciding when a
// fully observed transaction becomes eligible for an ack grace diagnostic. It
// does not impose a maximum latency from creq acceptance to completion.
//------------------------------------------------------------------------------
class shm_transaction_lifecycle_checker extends uvm_component;
  class lifecycle_record;
    shm_transaction_uid_t   transaction_uid;
    creq_rw_e               direction;
    logic [ID_W-1:0]        transaction_id;
    bit                     ack_required;
    shm_cycle_t             accept_cycle;
    longint unsigned        reset_epoch;
    bit                     ack_received;
    shm_cycle_t             ack_cycle;
    bit                     data_resolved;
    bit                     data_observed;
    shm_cycle_t             completion_cycle;
    bit                     grace_started;
    shm_cycle_t             grace_start_cycle;
    bit                     missing_ack_reported;

    function new();
      ack_received = 1'b0;
      data_resolved = 1'b0;
      data_observed = 1'b0;
      grace_started = 1'b0;
      grace_start_cycle = 0;
      missing_ack_reported = 1'b0;
    endfunction : new
  endclass : lifecycle_record

  shm_environment_config cfg;
  virtual clk_if clk_vif;
  virtual shmins_interface shmins_vif;

  uvm_analysis_imp_shm_lifecycle_accept
      #(shmins_sequence_item, shm_transaction_lifecycle_checker) accept_imp;
  uvm_analysis_imp_shm_lifecycle_ack
      #(shmins_ack_event, shm_transaction_lifecycle_checker) ack_imp;
  uvm_analysis_imp_shm_lifecycle_completion
      #(shm_completion_event, shm_transaction_lifecycle_checker) completion_imp;

  lifecycle_record records[shm_transaction_uid_t];
  shm_transaction_uid_t uid_by_ack_key[longint unsigned];
  bit retired_ack_keys[longint unsigned];

  // Accepted transaction order for the independent V2M and M2V ack channels.
  shm_transaction_uid_t direction_order[2][$];

  bit in_reset;

  //----------------------------------------------------------------------------
  // @brief Constructs the lifecycle checker and its analysis implementations.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this checker.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_transaction_lifecycle_checker", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Obtains environment configuration and shared interfaces.
  //
  // @param phase UVM build phase used to resolve dependencies.
  //----------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //----------------------------------------------------------------------------
  // @brief Scans ordered-head ack grace and reset transitions.
  //
  // @param phase UVM main phase controlling the checker lifetime.
  //----------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  //----------------------------------------------------------------------------
  // @brief Reports lifecycle records still incomplete at end of test.
  //
  // @param phase UVM check phase used for final consistency checks.
  //----------------------------------------------------------------------------
  extern virtual function void check_phase(uvm_phase phase);

  //----------------------------------------------------------------------------
  // @brief Records one accepted creq as a new lifecycle entry.
  //
  // @param transaction Monitor-owned transaction containing stable metadata.
  //----------------------------------------------------------------------------
  extern function void write_shm_lifecycle_accept(shmins_sequence_item transaction);

  //----------------------------------------------------------------------------
  // @brief Associates one sampled ack with its outstanding lifecycle entry.
  //
  // @param ack_event Direction, ID, cycle, and reset epoch sampled by monitor.
  //----------------------------------------------------------------------------
  extern function void write_shm_lifecycle_ack(shmins_ack_event ack_event);

  //----------------------------------------------------------------------------
  // @brief Associates scoreboard data resolution with a lifecycle entry.
  //
  // @param completion_event Scoreboard-owned completion classification.
  //----------------------------------------------------------------------------
  extern function void write_shm_lifecycle_completion(shm_completion_event completion_event);

  //----------------------------------------------------------------------------
  // @brief Returns whether no accepted lifecycle entry remains outstanding.
  //
  // @return 1 when every accepted transaction is resolved and has any required ack.
  //----------------------------------------------------------------------------
  extern function bit is_idle();

  //----------------------------------------------------------------------------
  // @brief Formats all outstanding lifecycle records for drain-time diagnostics.
  //
  // @return Multi-line summary of pending lifecycle state.
  //----------------------------------------------------------------------------
  extern function string pending_state_sprint();

  //----------------------------------------------------------------------------
  // @brief Builds the lookup key used to correlate a raw ack with one creq.
  //
  // @param direction      Ack channel direction.
  // @param transaction_id Interface request ID carried by creq and ack.
  // @return Stable key containing both direction and transaction ID.
  //----------------------------------------------------------------------------
  extern protected function longint unsigned ack_key(
      creq_rw_e direction, logic [ID_W-1:0] transaction_id);

  //----------------------------------------------------------------------------
  // @brief Advances ordered retirement and arms the new channel head grace.
  //
  // @param direction     V2M or M2V acceptance-order queue to advance.
  // @param current_cycle Shared clock cycle of the ack or completion event.
  // @post Every consecutively retired head is deleted. A fully observed
  //       ack-required new head starts grace exactly once.
  //----------------------------------------------------------------------------
  extern protected function void advance_direction(
      creq_rw_e direction, shm_cycle_t current_cycle);

  //----------------------------------------------------------------------------
  // @brief Deletes one record that has retired from its ordered channel head.
  //
  // @param transaction_uid Monitor-owned identity of the record to delete.
  // @pre The record is the current direction queue head and satisfies the
  //      ordered retirement condition.
  //----------------------------------------------------------------------------
  extern protected function void retire_record(shm_transaction_uid_t transaction_uid);

  //----------------------------------------------------------------------------
  // @brief Clears all lifecycle, ordering, and ack-correlation state on reset.
  //----------------------------------------------------------------------------
  extern protected function void clear_for_reset();

  `uvm_component_utils(shm_transaction_lifecycle_checker)
endclass : shm_transaction_lifecycle_checker

function shm_transaction_lifecycle_checker::new(
  string name = "shm_transaction_lifecycle_checker", uvm_component parent = null);
  super.new(name, parent);
  accept_imp = new("accept_imp", this);
  ack_imp = new("ack_imp", this);
  completion_imp = new("completion_imp", this);
  in_reset = 1'b1;
endfunction : new

function void shm_transaction_lifecycle_checker::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(shm_environment_config)::get(this, "", "shm_environment_config", cfg) || cfg == null) begin
    `uvm_fatal("SHM_LIFECYCLE_NO_CFG", "lifecycle checker requires shm_environment_config")
  end
  if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
    `uvm_fatal("SHM_LIFECYCLE_NO_CLK_VIF", "lifecycle checker requires virtual clk_if 'clk_vif'")
  end
  if (!uvm_config_db#(virtual shmins_interface)::get(this, "", "shmins_vif", shmins_vif)) begin
    `uvm_fatal("SHM_LIFECYCLE_NO_SHMINS_VIF", "lifecycle checker requires virtual shmins_interface 'shmins_vif'")
  end
endfunction : build_phase

task shm_transaction_lifecycle_checker::main_phase(uvm_phase phase);
  super.main_phase(phase);
  forever begin
    clk_vif.wait_cycles(1);

    if (shmins_vif.rst_n !== 1'b1) begin
      if (!in_reset) begin
        clear_for_reset();
      end
      in_reset = 1'b1;
      continue;
    end
    in_reset = 1'b0;

    if (cfg.ack_post_complete_grace_cycles == 0) begin
      continue;
    end
    foreach (records[transaction_uid]) begin
      lifecycle_record record = records[transaction_uid];
      if (record.ack_required && record.grace_started && !record.ack_received &&
          !record.missing_ack_reported &&
          clk_vif.cycle_count > record.grace_start_cycle + cfg.ack_post_complete_grace_cycles) begin
        `uvm_error("SHM_ACK_POST_COMPLETE_TIMEOUT",
                   $sformatf({"transaction uid=%0d direction=%s id=%0d has no ack %0d cycles after ",
                              "becoming the ordered ack-channel head at cycle %0d"},
                             record.transaction_uid, record.direction.name(), record.transaction_id,
                             cfg.ack_post_complete_grace_cycles, record.grace_start_cycle))
        record.missing_ack_reported = 1'b1;
      end
    end
  end
endtask : main_phase

function void shm_transaction_lifecycle_checker::check_phase(uvm_phase phase);
  super.check_phase(phase);
  foreach (records[transaction_uid]) begin
    lifecycle_record record = records[transaction_uid];
    if (record.ack_required && !record.ack_received && !record.missing_ack_reported) begin
      `uvm_error("SHM_ACK_MISSING",
                 $sformatf("transaction uid=%0d direction=%s id=%0d ended without required ack",
                           record.transaction_uid, record.direction.name(), record.transaction_id))
    end
  end
endfunction : check_phase

function void shm_transaction_lifecycle_checker::write_shm_lifecycle_accept(
  shmins_sequence_item transaction);
  lifecycle_record record;
  longint unsigned key;

  if (records.exists(transaction.transaction_uid)) begin
    `uvm_error("SHM_LIFECYCLE_DUPLICATE_UID",
               $sformatf("transaction uid=%0d was accepted more than once", transaction.transaction_uid))
    return;
  end

  key = ack_key(transaction.creq_rw, transaction.creq_id);
  if (uid_by_ack_key.exists(key)) begin
    `uvm_error("SHM_ACK_ID_REUSED",
               $sformatf("direction=%s id=%0d reused while uid=%0d remains outstanding",
                         transaction.creq_rw.name(), transaction.creq_id, uid_by_ack_key[key]))
  end

  retired_ack_keys.delete(key);
  record = new();
  record.transaction_uid = transaction.transaction_uid;
  record.direction = transaction.creq_rw;
  record.transaction_id = transaction.creq_id;
  record.ack_required = transaction.creq_ack_en;
  record.accept_cycle = transaction.accept_cycle;
  record.reset_epoch = transaction.reset_epoch;
  records[record.transaction_uid] = record;
  uid_by_ack_key[key] = record.transaction_uid;
  direction_order[int'(record.direction)].push_back(record.transaction_uid);
endfunction : write_shm_lifecycle_accept

function void shm_transaction_lifecycle_checker::write_shm_lifecycle_ack(shmins_ack_event ack_event);
  longint unsigned key = ack_key(ack_event.direction, ack_event.transaction_id);
  creq_rw_e opposite_direction = ack_event.direction == SHM_V2M ? SHM_M2V : SHM_V2M;
  longint unsigned opposite_key = ack_key(opposite_direction, ack_event.transaction_id);
  shm_transaction_uid_t transaction_uid;
  lifecycle_record record;

  if (retired_ack_keys.exists(key)) begin
    `uvm_error("SHM_ACK_DUPLICATE",
               $sformatf("duplicate %s ack id=%0d at cycle %0d",
                         ack_event.direction.name(), ack_event.transaction_id, ack_event.cycle))
    return;
  end
  if (!uid_by_ack_key.exists(key)) begin
    if (uid_by_ack_key.exists(opposite_key)) begin
      transaction_uid = uid_by_ack_key[opposite_key];
      `uvm_error("SHM_ACK_WRONG_DIRECTION",
                 $sformatf("transaction uid=%0d expects %s ack id=%0d but observed %s ack",
                           transaction_uid, opposite_direction.name(), ack_event.transaction_id,
                           ack_event.direction.name()))
      return;
    end
    `uvm_error("SHM_ACK_UNEXPECTED",
               $sformatf("unexpected %s ack id=%0d at cycle %0d",
                         ack_event.direction.name(), ack_event.transaction_id, ack_event.cycle))
    return;
  end

  transaction_uid = uid_by_ack_key[key];
  record = records[transaction_uid];
  if (ack_event.reset_epoch != record.reset_epoch) begin
    `uvm_error("SHM_ACK_RESET_EPOCH",
               $sformatf("ack epoch=%0d does not match transaction uid=%0d epoch=%0d",
                         ack_event.reset_epoch, transaction_uid, record.reset_epoch))
    return;
  end
  if (!record.ack_required) begin
    `uvm_error("SHM_ACK_DISABLED",
               $sformatf("transaction uid=%0d direction=%s id=%0d produced ack while disabled",
                         transaction_uid, record.direction.name(), record.transaction_id))
  end
  if (record.ack_received) begin
    `uvm_error("SHM_ACK_DUPLICATE",
               $sformatf("transaction uid=%0d direction=%s id=%0d produced duplicate ack",
                         transaction_uid, record.direction.name(), record.transaction_id))
    return;
  end

  record.ack_received = 1'b1;
  record.ack_cycle = ack_event.cycle;

  // Ack correlation ends at the ack event even if ordered data retirement is
  // still blocked by an older transaction on this direction channel.
  uid_by_ack_key.delete(key);
  retired_ack_keys[key] = 1'b1;
  advance_direction(record.direction, ack_event.cycle);
endfunction : write_shm_lifecycle_ack

function void shm_transaction_lifecycle_checker::write_shm_lifecycle_completion(
    shm_completion_event completion_event);
  lifecycle_record record;

  if (!records.exists(completion_event.transaction_uid)) begin
    `uvm_error("SHM_LIFECYCLE_UNKNOWN_COMPLETION",
               $sformatf("scoreboard completed unknown transaction uid=%0d",
                         completion_event.transaction_uid))
    return;
  end

  record = records[completion_event.transaction_uid];
  record.data_resolved = 1'b1;
  record.data_observed = completion_event.kind == SHM_COMPLETION_OBSERVED;
  record.completion_cycle = completion_event.cycle;
  advance_direction(record.direction, completion_event.cycle);
endfunction : write_shm_lifecycle_completion

function bit shm_transaction_lifecycle_checker::is_idle();
  return records.num() == 0 && direction_order[int'(SHM_V2M)].size() == 0 &&
         direction_order[int'(SHM_M2V)].size() == 0;
endfunction : is_idle

function string shm_transaction_lifecycle_checker::pending_state_sprint();
  string result = $sformatf("lifecycle pending records=%0d\n", records.num());
  for (int unsigned direction_index = 0; direction_index < 2; direction_index++) begin
    creq_rw_e direction = creq_rw_e'(direction_index);
    result = {result,
              $sformatf("  %s order depth=%0d\n", direction.name(),
                        direction_order[direction_index].size())};
    foreach (direction_order[direction_index][position]) begin
      shm_transaction_uid_t transaction_uid = direction_order[direction_index][position];
      if (!records.exists(transaction_uid)) begin
        result = {result,
                  $sformatf("    position=%0d uid=%0d missing record\n", position,
                            transaction_uid)};
        continue;
      end
      begin
        lifecycle_record record = records[transaction_uid];
        result = {result,
                  $sformatf({"    position=%0d uid=%0d id=%0d ack_required=%0d ack_received=%0d ",
                             "data_resolved=%0d data_observed=%0d grace_started=%0d ",
                             "grace_start_cycle=%0d accept_cycle=%0d\n"},
                            position, record.transaction_uid, record.transaction_id,
                            record.ack_required, record.ack_received, record.data_resolved,
                            record.data_observed, record.grace_started,
                            record.grace_start_cycle, record.accept_cycle)};
      end
    end
  end
  return result;
endfunction : pending_state_sprint

function longint unsigned shm_transaction_lifecycle_checker::ack_key(
    creq_rw_e direction, logic [ID_W-1:0] transaction_id);
  return (longint'(direction) << ID_W) | longint'(transaction_id);
endfunction : ack_key

function void shm_transaction_lifecycle_checker::advance_direction(
    creq_rw_e direction, shm_cycle_t current_cycle);
  int unsigned direction_index = int'(direction);

  while (direction_order[direction_index].size() != 0) begin
    shm_transaction_uid_t transaction_uid = direction_order[direction_index][0];
    lifecycle_record record;

    if (!records.exists(transaction_uid)) begin
      `uvm_error("SHM_LIFECYCLE_ORDER_MISSING_RECORD",
                 $sformatf("direction=%s head uid=%0d has no lifecycle record",
                           direction.name(), transaction_uid))
      void'(direction_order[direction_index].pop_front());
      continue;
    end

    record = records[transaction_uid];
    if (!record.data_resolved || (record.ack_required && !record.ack_received)) begin
      break;
    end

    void'(direction_order[direction_index].pop_front());
    retire_record(transaction_uid);
  end

  if (direction_order[direction_index].size() != 0) begin
    shm_transaction_uid_t transaction_uid = direction_order[direction_index][0];
    lifecycle_record record = records[transaction_uid];

    if (record.ack_required && record.data_observed && !record.ack_received &&
        !record.grace_started) begin
      record.grace_started = 1'b1;
      record.grace_start_cycle = current_cycle;
    end
  end
endfunction : advance_direction

function void shm_transaction_lifecycle_checker::retire_record(
    shm_transaction_uid_t transaction_uid);
  longint unsigned key;
  lifecycle_record record;

  if (!records.exists(transaction_uid)) begin
    return;
  end
  record = records[transaction_uid];
  key = ack_key(record.direction, record.transaction_id);

  // A newer transaction may already reuse the same ID after this record's ack.
  // Delete only a correlation entry still owned by the retiring record.
  if (uid_by_ack_key.exists(key) && uid_by_ack_key[key] == transaction_uid) begin
    uid_by_ack_key.delete(key);
  end
  records.delete(transaction_uid);
endfunction : retire_record

function void shm_transaction_lifecycle_checker::clear_for_reset();
  records.delete();
  uid_by_ack_key.delete();
  retired_ack_keys.delete();
  direction_order[int'(SHM_V2M)].delete();
  direction_order[int'(SHM_M2V)].delete();
endfunction : clear_for_reset

`endif // INC_SHM_TRANSACTION_LIFECYCLE_CHECKER_SVH
