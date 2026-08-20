`ifndef INC_VLM_RESERVATION_AGENT_SVH
`define INC_VLM_RESERVATION_AGENT_SVH

//------------------------------------------------------------------------------
// @brief Coordinates reservation sampling, checking, coverage, and scheduling.
//
// Owns the monitor, checker, coverage collector, scheduler, and fixed-latency
// MEM read response path. Its main_phase is the only core cycle loop: it
// samples one normalized transaction, resolves gid metadata, synchronously
// commits actual writes, schedules read snapshots, and advances reservation
// state. It does not own the byte memory or compare expected write data.
//------------------------------------------------------------------------------
class vlm_reservation_agent extends uvm_agent;

  // Minimal interface configuration obtained through UVM Config DB.
  vlm_reservation_agent_config cfg;

  // Unified reservation and MEM business interface.
  virtual vlm_interface vif;

  // Publishes resolved MEM reads and writes with immutable gid metadata.
  uvm_analysis_port #(vlm_memory_sequence_item) read_analysis_port;
  uvm_analysis_port #(vlm_memory_sequence_item) write_analysis_port;

  // Obtains read data from the scoreboard memory model.
  uvm_tlm_b_transport_port #(vlm_memory_sequence_item) mem_port;

  // Component owning four-state sampling and two-state normalization.
  vlm_reservation_monitor monitor;

  // Component checking reservation protocol and reservation-to-MEM matching.
  vlm_reservation_checker reservation_checker;

  // Component sampling functional coverage before scheduler state mutation.
  vlm_reservation_coverage coverage;

  // Component owning external busy, SHM records, and final busy generation.
  vlm_reservation_scheduler scheduler;

  // Most recent normalized transaction returned by the monitor.
  vlm_reservation_cycle_transaction_t current_txn;

  // Detailed checker result associated with current_txn.
  vlm_reservation_check_result_t current_check_result;

  // Latest sampled cycle whose matched MEM write has been synchronously committed.
  shm_cycle_t memory_committed_cycle;

  // Set after the first post-reset cycle has committed its MEM write state.
  bit memory_cycle_committed;

  // Number of accepted read responses that have not reached their DUT sampling cycle.
  int unsigned pending_read_response_count;

  //------------------------------------------------------------------------------
  // @brief Constructs the VLM reservation agent.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this agent.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_reservation_agent",
      uvm_component parent = null);

  //------------------------------------------------------------------------------
  // @brief Obtains interface configuration and builds every child component.
  //
  // @param phase UVM build phase used to construct the active agent hierarchy.
  // @post Monitor, checker, coverage, and scheduler are all available.
  //------------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Connects interfaces and scheduler state views between components.
  //
  // @param phase UVM connect phase used to establish component relationships.
  // @post Monitor owns both business vif handles; checker and coverage refer to
  //       the scheduler owned by this agent.
  //------------------------------------------------------------------------------
  extern virtual function void connect_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Runs the single active reservation loop in UVM main phase.
  //
  // @param phase UVM main phase controlling the agent task lifetime.
  // @post Every collected transaction is checked, covered, scheduled, and
  //       followed by a busy drive for the next interface cycle.
  //------------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Checks and covers one transaction against pre-update scheduler state.
  //
  // @param txn Two-state reservation and MEM transaction for one cycle.
  // @pre Scheduler still exposes the state sampled in txn.
  // @post current_check_result contains immutable MEM gid/match metadata; the
  //       scheduler has not yet advanced.
  //------------------------------------------------------------------------------
  extern function void process_cycle(
      const ref vlm_reservation_cycle_transaction_t txn);

  //------------------------------------------------------------------------------
  // @brief Publishes resolved writes and schedules resolved read responses.
  //
  // @param txn Atomically sampled reservation and MEM transaction.
  // @param result Pre-update checker result containing per-BANK gid resolution.
  //------------------------------------------------------------------------------
  extern protected task process_memory_requests(const ref vlm_reservation_cycle_transaction_t txn,
                                                const ref vlm_reservation_check_result_t result);

  //------------------------------------------------------------------------------
  // @brief Returns whether no MEM read response remains in flight.
  //
  // @return 1 when every accepted read has reached its response cycle.
  //------------------------------------------------------------------------------
  extern function bit is_memory_idle();

  //------------------------------------------------------------------------------
  // @brief Formats the read-response pipeline state for drain diagnostics.
  //
  // @return Pending count and the latest synchronously committed memory cycle.
  //------------------------------------------------------------------------------
  extern function string pending_memory_state_sprint();

  //------------------------------------------------------------------------------
  // @brief Builds resolved read and write transactions for one sampled cycle.
  //
  // @param txn               Atomically sampled reservation/MEM transaction.
  // @param result            Checker result containing trusted gid metadata.
  // @param read_transaction  Newly allocated aggregate read transaction.
  // @param write_transaction Newly allocated aggregate write transaction.
  // @param has_read          Set when at least one BANK carries a MEM read.
  // @param has_write         Set when at least one BANK carries a MEM write.
  //------------------------------------------------------------------------------
  extern protected function void build_memory_transactions(
      const ref vlm_reservation_cycle_transaction_t txn,
      const ref vlm_reservation_check_result_t      result,
      output    vlm_memory_sequence_item             read_transaction,
      output    vlm_memory_sequence_item             write_transaction,
      output    bit                                  has_read,
      output    bit                                  has_write);

  //------------------------------------------------------------------------------
  // @brief Applies one actual MEM write to the synchronous byte-memory endpoint.
  //
  // @param write_transaction Resolved write payload and immutable gid metadata.
  // @pre mem_port is connected and the transport implementation consumes no time.
  //------------------------------------------------------------------------------
  extern protected task commit_memory_write(vlm_memory_sequence_item write_transaction);

  //------------------------------------------------------------------------------
  // @brief Marks all actual MEM writes through one sampled cycle as committed.
  //
  // @param cycle Sampled cycle whose write state is now visible to read workers.
  //------------------------------------------------------------------------------
  extern protected function void commit_memory_cycle(shm_cycle_t cycle);

  //------------------------------------------------------------------------------
  // @brief Starts one nonblocking fixed-latency read-response worker.
  //
  // @param read_transaction Resolved read request whose gid metadata is immutable.
  // @param accept_cycle     Cycle in which the DUT issued the MEM read.
  //------------------------------------------------------------------------------
  extern protected task launch_read_response(vlm_memory_sequence_item read_transaction,
                                             shm_cycle_t              accept_cycle);

  //------------------------------------------------------------------------------
  // @brief Snapshots one read at its FFD cutoff and drives it at fixed latency.
  //
  // @param read_transaction Resolved read request filled by the memory transport.
  // @param accept_cycle     Cycle in which the DUT issued the MEM read.
  //------------------------------------------------------------------------------
  extern protected task serve_read_response(vlm_memory_sequence_item read_transaction,
                                            shm_cycle_t              accept_cycle);

  //------------------------------------------------------------------------------
  // @brief Drives scheduler final busy onto the reservation interface.
  //
  // @pre Scheduler final busy represents the next interface cycle.
  // @post Read and write busy outputs equal the scheduler final busy tables.
  //------------------------------------------------------------------------------
  extern protected function void drive_busy();

  `uvm_component_utils(vlm_reservation_agent)

endclass : vlm_reservation_agent

function vlm_reservation_agent::new(string name = "vlm_reservation_agent", uvm_component parent = null);
  super.new(name, parent);
  read_analysis_port = new("read_analysis_port", this);
  write_analysis_port = new("write_analysis_port", this);
  mem_port = new("mem_port", this);
  memory_committed_cycle = 0;
  memory_cycle_committed = 1'b0;
  pending_read_response_count = 0;
endfunction : new

function void vlm_reservation_agent::build_phase(uvm_phase phase);
  int unsigned configured_external_busy_percent;

  super.build_phase(phase);

  // The agent requires one configuration object containing both business interfaces.
  if (!uvm_config_db#(vlm_reservation_agent_config)::get(this, "", "cfg", cfg) || cfg == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_CFG",
               "vlm_reservation_agent requires vlm_reservation_agent_config under Config DB field 'cfg'")
  end

  // Both interfaces are mandatory because every cycle combines reservation and actual MEM observations.
  if (cfg.vif == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_VIF", "reservation agent config requires unified vif")
  end

  if (cfg.ffd_cyc < 1 || cfg.ffd_cyc > cfg.rport_dly) begin
    `uvm_fatal("VLM_MEMORY_TIMING_CONFIG",
               $sformatf("requires 1 <= ffd_cyc <= rport_dly, got ffd_cyc=%0d rport_dly=%0d",
                         cfg.ffd_cyc, cfg.rport_dly))
  end

  vif = cfg.vif;

  // The command-line setting has higher priority than the value supplied by the test config object.
  configured_external_busy_percent = cfg.EXTERNAL_BUSY_PERCENT;
  void'($value$plusargs("EXTERNAL_BUSY_PERCENT=%d", configured_external_busy_percent));

  if (configured_external_busy_percent > 100) begin
    `uvm_fatal("VLM_RESERVATION_EXTERNAL_PERCENT",
               $sformatf("EXTERNAL_BUSY_PERCENT %0d is outside [0, 100]",
                         configured_external_busy_percent))
  end

  // Always construct the complete active reservation hierarchy; passive mode is not supported yet.
  monitor             = vlm_reservation_monitor::type_id::create("monitor", this);
  reservation_checker = vlm_reservation_checker::type_id::create("reservation_checker", this);
  coverage            = vlm_reservation_coverage::type_id::create("coverage", this);
  scheduler           = vlm_reservation_scheduler::type_id::create("scheduler", this);
  scheduler.external_busy_percent = configured_external_busy_percent;
  scheduler.external_busy_policy = cfg.external_busy_policy;

  `uvm_info("VLM_RESERVATION_EXTERNAL_PERCENT",
            $sformatf("using EXTERNAL_BUSY_PERCENT=%0d", scheduler.external_busy_percent),
            UVM_LOW)
  if (scheduler.external_busy_policy != null) begin
    `uvm_info("VLM_RESERVATION_EXTERNAL_POLICY",
              $sformatf("using deterministic external busy policy %s",
                        scheduler.external_busy_policy.get_type_name()),
              UVM_LOW)
  end
endfunction : build_phase

function void vlm_reservation_agent::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  // Give the monitor the same configuration already validated and retained by the agent.
  monitor.set_config(cfg);

  // Checker and coverage inspect the scheduler directly before its state is advanced for the next cycle.
  reservation_checker.scheduler = scheduler;
  coverage.scheduler             = scheduler;
endfunction : connect_phase

task vlm_reservation_agent::main_phase(uvm_phase phase);
  super.main_phase(phase);

  // Establish a deterministic all-idle busy value before the first sampled reservation cycle.
  vif.slv_cb.rdata <= '0;
  drive_busy();

  forever begin
    // collect_cycle() is the only API in the reactive loop that consumes simulation time.
    monitor.collect_cycle(current_txn);

    // Checking, coverage sampling, scheduling, and driving all complete in the sampled cycle.
    process_cycle(current_txn);
    process_memory_requests(current_txn, current_check_result);
    scheduler.process_cycle(current_txn);
    drive_busy();
  end
endtask : main_phase

function void vlm_reservation_agent::process_cycle(const ref vlm_reservation_cycle_transaction_t txn);
  // Preserve the latest normalized transaction for direct inspection and debug.
  current_txn = txn;

  // Checker and coverage must see the scheduler state that produced the busy sampled in txn.
  current_check_result = reservation_checker.check_cycle(txn);
  coverage.sample_cycle(txn, current_check_result);

endfunction : process_cycle

task vlm_reservation_agent::process_memory_requests(
    const ref vlm_reservation_cycle_transaction_t txn,
    const ref vlm_reservation_check_result_t result);
  vlm_memory_sequence_item read_transaction;
  vlm_memory_sequence_item write_transaction;
  bit has_read;
  bit has_write;

  build_memory_transactions(txn, result, read_transaction, write_transaction, has_read, has_write);

  // Commit actual memory before releasing this cycle to a read worker. The
  // analysis path remains responsible only for expected-data matching.
  if (has_write) begin
    commit_memory_write(write_transaction);
    write_analysis_port.write(write_transaction);
  end

  // Advance the watermark on every sampled cycle, including cycles without a
  // write, so a future-cutoff read cannot wait forever on an idle cycle.
  commit_memory_cycle(txn.cycle);

  if (has_read) begin
    launch_read_response(read_transaction, txn.cycle);
  end
endtask : process_memory_requests

function void vlm_reservation_agent::build_memory_transactions(
    const ref vlm_reservation_cycle_transaction_t txn,
    const ref vlm_reservation_check_result_t      result,
    output    vlm_memory_sequence_item             read_transaction,
    output    vlm_memory_sequence_item             write_transaction,
    output    bit                                  has_read,
    output    bit                                  has_write);
  has_read = 1'b0;
  has_write = 1'b0;
  read_transaction = vlm_memory_sequence_item::type_id::create("resolved_read_transaction");
  write_transaction = vlm_memory_sequence_item::type_id::create("resolved_write_transaction");
  read_transaction.vlm_read = 1'b1;
  write_transaction.vlm_read = 1'b0;

  for (int unsigned bank = 0; bank < BANK_N; bank++) begin
    if (txn.mem_rreq_array[bank] != null) begin
      has_read = 1'b1;
      read_transaction.vlm_bken[bank] = 1'b1;
      read_transaction.vlm_addr[bank] = txn.mem_rreq_array[bank].address;
      read_transaction.vlm_gid[bank] = result.mem_gid[VLM_RESERVATION_READ][bank];
      read_transaction.gid_valid[bank] = result.mem_gid_valid[VLM_RESERVATION_READ][bank];
      read_transaction.reservation_matched[bank] = result.mem_reservation_matched[VLM_RESERVATION_READ][bank];
    end
    if (txn.mem_wreq_array[bank] != null) begin
      has_write = 1'b1;
      write_transaction.vlm_bken[bank] = 1'b1;
      write_transaction.vlm_addr[bank] = txn.mem_wreq_array[bank].address;
      write_transaction.vlm_strb[bank] = txn.mem_wreq_array[bank].strb;
      write_transaction.vlm_data[bank] = txn.mem_wreq_array[bank].data;
      write_transaction.vlm_gid[bank] = result.mem_gid[VLM_RESERVATION_WRITE][bank];
      write_transaction.gid_valid[bank] = result.mem_gid_valid[VLM_RESERVATION_WRITE][bank];
      write_transaction.reservation_matched[bank] = result.mem_reservation_matched[VLM_RESERVATION_WRITE][bank];
    end
  end
endfunction : build_memory_transactions

task vlm_reservation_agent::commit_memory_write(vlm_memory_sequence_item write_transaction);
  uvm_tlm_time delay = new("write_memory_delay");
  mem_port.b_transport(write_transaction, delay);
endtask : commit_memory_write

function void vlm_reservation_agent::commit_memory_cycle(shm_cycle_t cycle);
  memory_committed_cycle = cycle;
  memory_cycle_committed = 1'b1;
endfunction : commit_memory_cycle

task vlm_reservation_agent::launch_read_response(vlm_memory_sequence_item read_transaction,
                                                 shm_cycle_t              accept_cycle);
  pending_read_response_count++;
  fork
    begin
      automatic vlm_memory_sequence_item completed_transaction = read_transaction;
      automatic shm_cycle_t completed_accept_cycle = accept_cycle;
      serve_read_response(completed_transaction, completed_accept_cycle);
    end
  join_none
endtask : launch_read_response

task vlm_reservation_agent::serve_read_response(vlm_memory_sequence_item read_transaction,
                                                shm_cycle_t              accept_cycle);
  uvm_tlm_time delay = new("read_memory_delay");
  shm_cycle_t snapshot_cycle = accept_cycle + cfg.ffd_cyc - 1;

  // Wake on the configured cutoff edge, then wait for the main cycle loop to
  // synchronously apply that edge's write before reading the memory model.
  repeat (cfg.ffd_cyc - 1) @(vif.slv_cb);
  wait (memory_cycle_committed && memory_committed_cycle >= snapshot_cycle);
  mem_port.b_transport(read_transaction, delay);

  // Drive one edge before the architectural response edge so the clocking-block
  // output is stable when the DUT samples at accept_cycle + rport_dly.
  repeat (cfg.rport_dly - cfg.ffd_cyc) @(vif.slv_cb);
  for (int unsigned bank = 0; bank < BANK_N; bank++) begin
    if (read_transaction.vlm_bken[bank] && read_transaction.reservation_matched[bank]) begin
      vif.slv_cb.rdata[bank] <= read_transaction.vlm_data[bank];
    end
  end

  // Publish completion and retire the worker on the DUT sampling edge, not on
  // the preceding clocking-block drive edge.
  @(vif.slv_cb);
  read_analysis_port.write(read_transaction);
  if (pending_read_response_count == 0) begin
    `uvm_error("VLM_MEMORY_PENDING_UNDERFLOW", "read-response pending count is already zero")
  end else begin
    pending_read_response_count--;
  end
endtask : serve_read_response

function bit vlm_reservation_agent::is_memory_idle();
  return pending_read_response_count == 0;
endfunction : is_memory_idle

function string vlm_reservation_agent::pending_memory_state_sprint();
  return $sformatf("memory read responses pending=%0d committed=%0d committed_cycle=%0d",
                   pending_read_response_count, memory_cycle_committed, memory_committed_cycle);
endfunction : pending_memory_state_sprint

function void vlm_reservation_agent::drive_busy();
  if (vif == null || scheduler == null) begin
    `uvm_fatal("VLM_RESERVATION_AGENT_NOT_READY", "drive_busy() requires unified vif and scheduler")
  end

  // Publish the scheduler's read and write tables together so the next edge observes one coherent window.
  vif.slv_cb.rbusy <= scheduler.final_busy[VLM_RESERVATION_READ];
  vif.slv_cb.wbusy <= scheduler.final_busy[VLM_RESERVATION_WRITE];
endfunction : drive_busy

`endif // INC_VLM_RESERVATION_AGENT_SVH
