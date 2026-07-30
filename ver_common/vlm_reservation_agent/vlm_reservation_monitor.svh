`ifndef VLM_RESERVATION_MONITOR_SVH
`define VLM_RESERVATION_MONITOR_SVH

//------------------------------------------------------------------------------
// @brief Samples reservation and MEM request interfaces into one transaction.
//
// Owns the four-state sampling and normalization boundary. It obtains the
// shared clk_if through UVM Config DB, reports unknown interface values, and
// returns one two-state cycle transaction per collect_cycle() call. It does not
// drive busy, schedule reservations, check MEM correspondence, or inspect MEM
// data payloads.
//------------------------------------------------------------------------------
class vlm_reservation_monitor extends uvm_component;

  // Agent configuration providing both business virtual interfaces.
  vlm_reservation_agent_config cfg;

  // Reservation interface sampled for requests and observed busy values.
  virtual vlm_reservation_interface reservation_vif;

  // Read-only MEM interface sampled for actual request valid and addresses.
  virtual vlm_memory_interface memory_vif;

  // Shared cycle-number service obtained directly through UVM Config DB.
  virtual clk_if clk_vif;

  // Most recent normalized two-state transaction returned to the agent.
  vlm_reservation_cycle_transaction_t current_txn;

  // Number of cycle transactions collected since component construction.
  longint unsigned collected_cycle_count;

  // Number of interface X/Z violations reported since component construction.
  int unsigned input_error_count;

  //------------------------------------------------------------------------------
  // @brief Constructs the VLM reservation monitor.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this monitor.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_reservation_monitor",
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
  // @brief Assigns business interfaces used by the monitor.
  //
  // @param cfg Valid configuration owned by the containing reservation agent.
  // @pre cfg provides non-null reservation_vif and memory_vif handles.
  // @post Subsequent collection uses the supplied business interfaces.
  //------------------------------------------------------------------------------
  extern function void set_config(vlm_reservation_agent_config cfg);

  //------------------------------------------------------------------------------
  // @brief Waits for, checks, and returns one normalized reservation/MEM cycle.
  //
  // @param txn Output receiving the two-state cycle transaction.
  // @pre clk_vif, reservation_vif, and memory_vif are non-null.
  // @post txn contains direct clocking-block samples normalized at the monitor's
  //       four-state boundary, and txn.cycle identifies the sampling edge.
  //------------------------------------------------------------------------------
  extern task collect_cycle(
      output vlm_reservation_cycle_transaction_t txn);

  `uvm_component_utils(vlm_reservation_monitor)

endclass : vlm_reservation_monitor

//------------------------------------------------------------------------------
// vlm_reservation_monitor method implementations
//------------------------------------------------------------------------------

function vlm_reservation_monitor::new(string name = "vlm_reservation_monitor", uvm_component parent = null);
  super.new(name, parent);

  collected_cycle_count = 0;
  input_error_count = 0;
endfunction : new

function void vlm_reservation_monitor::build_phase(uvm_phase phase);
  super.build_phase(phase);

  // All cycle-aware components must obtain the same monotonically increasing cycle source.
  if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
    `uvm_fatal("VLM_RESERVATION_NO_CLK_VIF", "vlm_reservation_monitor requires virtual clk_if 'clk_vif'")
  end
endfunction : build_phase

function void vlm_reservation_monitor::set_config(vlm_reservation_agent_config cfg);
  // A null config cannot provide the two business interfaces required by the monitor.
  if (cfg == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_CFG", "set_config() requires a non-null reservation agent config")
    return;
  end

  // Both interfaces are sampled together and therefore must be configured before collection starts.
  if (cfg.reservation_vif == null || cfg.memory_vif == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_VIF", "monitor config requires reservation_vif and memory_vif")
    return;
  end

  this.cfg = cfg;
  reservation_vif = cfg.reservation_vif;
  memory_vif = cfg.memory_vif;
endfunction : set_config

task vlm_reservation_monitor::collect_cycle(output vlm_reservation_cycle_transaction_t txn);
  // Missing interfaces would prevent atomic cycle sampling and indicate an environment connection error.
  if (clk_vif == null || reservation_vif == null || memory_vif == null) begin
    `uvm_fatal("VLM_RESERVATION_MONITOR_NOT_READY", "collect_cycle() requires clk_vif and both business interfaces")
    return;
  end

  // The reservation monitor clocking block is the only timing control in the reactive processing path.
  @(reservation_vif.mon_cb);

  sample_interfaces(current_raw);
  normalize_sample(current_raw, current_txn);

  collected_cycle_count++;
  txn = current_txn;
endtask : collect_cycle

function void vlm_reservation_monitor::sample_interfaces(output vlm_reservation_raw_sample_t raw);
  // Sampling without all interface handles would make the raw snapshot incomplete.
  if (clk_vif == null || reservation_vif == null || memory_vif == null) begin
    `uvm_fatal("VLM_RESERVATION_MONITOR_NOT_READY", "sample_interfaces() requires clk_vif and both business interfaces")
    return;
  end

  raw.cycle = clk_vif.cycle_count;
  raw.observed_busy[VLM_RESERVATION_READ] = reservation_vif.mon_cb.rbusy;
  raw.observed_busy[VLM_RESERVATION_WRITE] = reservation_vif.mon_cb.wbusy;

  raw.rreq = reservation_vif.mon_cb.rreq;
  raw.raddr = reservation_vif.mon_cb.raddr;
  raw.rdly = reservation_vif.mon_cb.rdly;
  raw.wreq = reservation_vif.mon_cb.wreq;
  raw.waddr = reservation_vif.mon_cb.waddr;
  raw.wdly = reservation_vif.mon_cb.wdly;

  raw.mem_rvld = memory_vif.mon_cb.rvld;
  raw.mem_raddr = memory_vif.mon_cb.raddr;
  raw.mem_wvld = memory_vif.mon_cb.wvld;
  raw.mem_waddr = memory_vif.mon_cb.waddr;
endfunction : sample_interfaces

function void vlm_reservation_monitor::normalize_sample(
    const ref vlm_reservation_raw_sample_t raw,
    output vlm_reservation_cycle_transaction_t txn);
  bit payload_known;
  vlm_reservation_event_t rsv;
  vlm_memory_request_event_t mem_req;

  txn.cycle = raw.cycle;
  txn.rsv_events.delete();
  txn.mem_req_events.delete();
  txn.input_error = 1'b0;

  // Normalize every busy bit independently so an X/Z location is reported precisely and converted to zero.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    // Visit each relative delay represented by the sampled busy window.
    for (int unsigned delay = 0; delay < VTAB_D; delay++) begin
      // Normalize each sub-bank bit independently to preserve the exact error location.
      for (int unsigned sub_bank = 0; sub_bank < VLM_SUB_BANK_N; sub_bank++) begin
        txn.observed_busy[direction][delay][sub_bank] =
            raw.observed_busy[direction][delay][sub_bank] === 1'b1;

        // Busy X/Z is a monitor-owned interface violation; the two-state placeholder remains zero.
        if ($isunknown(raw.observed_busy[direction][delay][sub_bank])) begin
          input_error_count++;
          txn.input_error = 1'b1;
          `uvm_error("VLM_RESERVATION_BUSY_XZ",
                     $sformatf("cycle %0d direction %0d delay %0d sub bank %0d busy contains X/Z",
                               raw.cycle, direction, delay, sub_bank))
        end
      end
    end
  end

  // Convert each read reservation port only when its valid and active payload are fully known.
  for (int unsigned bank = 0; bank < BANK_N; bank++) begin
    // Unknown request valid cannot be interpreted as either an active event or an idle port.
    if ($isunknown(raw.rreq[bank])) begin
      input_error_count++;
      txn.input_error = 1'b1;
      `uvm_error("VLM_RESERVATION_RREQ_XZ",
                 $sformatf("cycle %0d read reservation bank %0d request contains X/Z", raw.cycle, bank))
      continue;
    end

    if (raw.rreq[bank] === 1'b1) begin
      payload_known = 1'b1;

      // An active read reservation address must be fully known before creating a two-state event.
      if ($isunknown(raw.raddr[bank])) begin
        input_error_count++;
        txn.input_error = 1'b1;
        payload_known = 1'b0;
        `uvm_error("VLM_RESERVATION_RADDR_XZ",
                   $sformatf("cycle %0d read reservation bank %0d address contains X/Z", raw.cycle, bank))
      end

      // An active read reservation delay must be fully known before creating a two-state event.
      if ($isunknown(raw.rdly[bank])) begin
        input_error_count++;
        txn.input_error = 1'b1;
        payload_known = 1'b0;
        `uvm_error("VLM_RESERVATION_RDLY_XZ",
                   $sformatf("cycle %0d read reservation bank %0d delay contains X/Z", raw.cycle, bank))
      end

      if (payload_known) begin
        rsv.direction = VLM_RESERVATION_READ;
        rsv.bank_id = bank;
        rsv.write_port = 0;
        rsv.address = raw.raddr[bank];
        rsv.delay = raw.rdly[bank];
        txn.rsv_events.push_back(rsv);
      end
    end
  end

  // Convert each write reservation port independently because both ports may be active in one cycle.
  for (int unsigned bank = 0; bank < BANK_N; bank++) begin
    // Each configured write reservation port can independently produce one event.
    for (int unsigned port = 0; port < WRITE_PORT_N; port++) begin
      // Unknown request valid cannot create a write reservation event.
      if ($isunknown(raw.wreq[bank][port])) begin
        input_error_count++;
        txn.input_error = 1'b1;
        `uvm_error("VLM_RESERVATION_WREQ_XZ",
                   $sformatf("cycle %0d write reservation bank %0d port %0d request contains X/Z",
                             raw.cycle, bank, port))
        continue;
      end

      if (raw.wreq[bank][port] === 1'b1) begin
        payload_known = 1'b1;

        // An active write reservation address must be fully known before creating a two-state event.
        if ($isunknown(raw.waddr[bank][port])) begin
          input_error_count++;
          txn.input_error = 1'b1;
          payload_known = 1'b0;
          `uvm_error("VLM_RESERVATION_WADDR_XZ",
                     $sformatf("cycle %0d write reservation bank %0d port %0d address contains X/Z",
                               raw.cycle, bank, port))
        end

        // An active write reservation delay must be fully known before creating a two-state event.
        if ($isunknown(raw.wdly[bank][port])) begin
          input_error_count++;
          txn.input_error = 1'b1;
          payload_known = 1'b0;
          `uvm_error("VLM_RESERVATION_WDLY_XZ",
                     $sformatf("cycle %0d write reservation bank %0d port %0d delay contains X/Z",
                               raw.cycle, bank, port))
        end

        if (payload_known) begin
          rsv.direction = VLM_RESERVATION_WRITE;
          rsv.bank_id = bank;
          rsv.write_port = port;
          rsv.address = raw.waddr[bank][port];
          rsv.delay = raw.wdly[bank][port];
          txn.rsv_events.push_back(rsv);
        end
      end
    end
  end

  // Convert each BANK's actual read and write MEM ports into independent request events.
  for (int unsigned bank = 0; bank < BANK_N; bank++) begin
    // Unknown MEM read valid cannot be interpreted as an actual request.
    if ($isunknown(raw.mem_rvld[bank])) begin
      input_error_count++;
      txn.input_error = 1'b1;
      `uvm_error("VLM_RESERVATION_MEM_RVLD_XZ",
                 $sformatf("cycle %0d MEM read bank %0d valid contains X/Z", raw.cycle, bank))
    end else if (raw.mem_rvld[bank] === 1'b1) begin
      // An active MEM read address must be fully known before creating a two-state event.
      if ($isunknown(raw.mem_raddr[bank])) begin
        input_error_count++;
        txn.input_error = 1'b1;
        `uvm_error("VLM_RESERVATION_MEM_RADDR_XZ",
                   $sformatf("cycle %0d MEM read bank %0d address contains X/Z", raw.cycle, bank))
      end else begin
        mem_req.direction = VLM_RESERVATION_READ;
        mem_req.bank_id = bank;
        mem_req.address = raw.mem_raddr[bank];
        txn.mem_req_events.push_back(mem_req);
      end
    end

    // Unknown MEM write valid cannot be interpreted as an actual request.
    if ($isunknown(raw.mem_wvld[bank])) begin
      input_error_count++;
      txn.input_error = 1'b1;
      `uvm_error("VLM_RESERVATION_MEM_WVLD_XZ",
                 $sformatf("cycle %0d MEM write bank %0d valid contains X/Z", raw.cycle, bank))
    end else if (raw.mem_wvld[bank] === 1'b1) begin
      // An active MEM write address must be fully known before creating a two-state event.
      if ($isunknown(raw.mem_waddr[bank])) begin
        input_error_count++;
        txn.input_error = 1'b1;
        `uvm_error("VLM_RESERVATION_MEM_WADDR_XZ",
                   $sformatf("cycle %0d MEM write bank %0d address contains X/Z", raw.cycle, bank))
      end else begin
        mem_req.direction = VLM_RESERVATION_WRITE;
        mem_req.bank_id = bank;
        mem_req.address = raw.mem_waddr[bank];
        txn.mem_req_events.push_back(mem_req);
      end
    end
  end
endfunction : normalize_sample

`endif // VLM_RESERVATION_MONITOR_SVH
