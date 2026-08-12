`ifndef INC_VLM_RESERVATION_MONITOR_SVH
`define INC_VLM_RESERVATION_MONITOR_SVH

//------------------------------------------------------------------------------
// @brief Samples reservation and MEM request interfaces into one transaction.
//
// Owns the four-state sampling and normalization boundary. It obtains the
// shared clk_if through UVM Config DB, waits until reset is released, reports
// unknown interface values, and returns one two-state cycle transaction per
// collect_cycle() call. It does not drive busy, schedule reservations, check
// MEM correspondence, or inspect MEM data payloads.
//------------------------------------------------------------------------------
class vlm_reservation_monitor extends uvm_component;

  // Agent configuration providing both business virtual interfaces.
  vlm_reservation_agent_config cfg;

  // Unified interface sampled atomically for reservation and MEM activity.
  virtual vlm_interface vif;

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
  // @pre cfg provides a non-null unified vif handle.
  // @post Subsequent collection uses the supplied business interfaces.
  //------------------------------------------------------------------------------
  extern function void set_config(vlm_reservation_agent_config cfg);

  //------------------------------------------------------------------------------
  // @brief Waits for reset release, then returns one normalized reservation/MEM cycle.
  //
  // @param txn Output receiving the two-state cycle transaction.
  // @pre clk_vif and vif are non-null.
  // @post No X/Z checks occur while sampled rst_n is not exactly 1. After
  //       reset release, txn contains direct clocking-block samples normalized
  //       at the monitor's four-state boundary, and txn.cycle identifies the
  //       sampling edge.
  //------------------------------------------------------------------------------
  extern task collect_cycle(
      output vlm_reservation_cycle_transaction_t txn);

  //------------------------------------------------------------------------------
  // @brief Resets all per-cycle transaction fields before direct interface sampling.
  //
  // @param txn Transaction whose class handles and status are reset.
  // @post Every request handle is null and input_error is cleared.
  //------------------------------------------------------------------------------
  extern protected function void initialize_transaction(
      ref vlm_reservation_cycle_transaction_t txn);

  //------------------------------------------------------------------------------
  // @brief Normalizes the sampled four-state busy tables into two-state values.
  //
  // @param txn Transaction receiving observed read and write busy tables.
  // @pre The caller is synchronized to vif.mon_cb.
  // @post Each busy X/Z is reported, converted to zero, and reflected in input_error.
  //------------------------------------------------------------------------------
  extern protected function void collect_busy(
      ref vlm_reservation_cycle_transaction_t txn);

  //------------------------------------------------------------------------------
  // @brief Converts sampled VLM reservation ports into nullable request handles.
  //
  // @param txn Transaction receiving per-BANK read and write reservation handles.
  // @pre The caller is synchronized to vif.mon_cb.
  // @post Fully known active ports own new request instances; all other handles remain null.
  //------------------------------------------------------------------------------
  extern protected function void collect_reservation_requests(
      ref vlm_reservation_cycle_transaction_t txn);

  //------------------------------------------------------------------------------
  // @brief Converts sampled actual MEM ports into nullable request handles.
  //
  // @param txn Transaction receiving per-BANK actual read and write handles.
  // @pre The caller is synchronized to vif.mon_cb at the same clock edge.
  // @post Fully known active ports own new request instances; all other handles remain null.
  //------------------------------------------------------------------------------
  extern protected function void collect_memory_requests(
      ref vlm_reservation_cycle_transaction_t txn);

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
  if (cfg.vif == null) begin
    `uvm_fatal("VLM_RESERVATION_NO_VIF", "monitor config requires unified vif")
    return;
  end

  this.cfg = cfg;
  vif = cfg.vif;
endfunction : set_config

task vlm_reservation_monitor::collect_cycle(output vlm_reservation_cycle_transaction_t txn);
  // Missing interfaces would prevent atomic cycle sampling and indicate an environment connection error.
  if (clk_vif == null || vif == null) begin
    `uvm_fatal("VLM_RESERVATION_MONITOR_NOT_READY", "collect_cycle() requires clk_vif and unified vif")
    return;
  end

  // Reset values and interface payloads share the same clocking-block sampling boundary.
  // Treat X/Z reset as asserted so interface X/Z checks cannot run before a known release.
  do begin
    @(vif.mon_cb);
  end while (vif.mon_cb.rst_n !== 1'b1);

  initialize_transaction(current_txn);
  current_txn.cycle = clk_vif.cycle_count;

  // All helper functions read clocking-block values sampled at this same edge and consume no simulation time.
  collect_busy(current_txn);
  collect_reservation_requests(current_txn);
  collect_memory_requests(current_txn);

  collected_cycle_count++;
  txn = current_txn;
endtask : collect_cycle

function void vlm_reservation_monitor::initialize_transaction(ref vlm_reservation_cycle_transaction_t txn);
  // Clear every fixed read-port slot so inactive or invalid ports cannot retain a previous cycle's handle.
  foreach (txn.rsv_rreq_array[bank]) begin
    txn.rsv_rreq_array[bank] = null;
  end

  // Clear both write reservation ports independently for every BANK.
  foreach (txn.rsv_wreq_array[bank, port]) begin
    txn.rsv_wreq_array[bank][port] = null;
  end

  // Clear actual MEM request handles independently for read and write directions.
  foreach (txn.mem_rreq_array[bank]) begin
    txn.mem_rreq_array[bank] = null;
    txn.mem_wreq_array[bank] = null;
  end

  txn.input_error = 1'b0;
endfunction : initialize_transaction

function void vlm_reservation_monitor::collect_busy(ref vlm_reservation_cycle_transaction_t txn);
  logic busy_value;

  // Normalize read and write busy tables independently because their resource ownership is independent.
  for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
    // Visit every relative delay represented by the sampled busy window.
    for (int unsigned delay = 0; delay < VTAB_D; delay++) begin
      // Normalize each gid/sub-bank bit separately so every X/Z location is diagnosed precisely.
      for (int unsigned gid = 0; gid < GID_N; gid++) begin
        for (int unsigned sub_bank = 0; sub_bank < VLM_SUB_BANK_N; sub_bank++) begin
          if (direction == VLM_RESERVATION_READ) begin
            busy_value = vif.mon_cb.rbusy[delay][gid][sub_bank];
          end else begin
            busy_value = vif.mon_cb.wbusy[delay][gid][sub_bank];
          end

          txn.observed_busy[direction][delay][gid][sub_bank] = busy_value === 1'b1;

        // Busy X/Z is converted to zero only after the monitor records the four-state interface violation.
          if ($isunknown(busy_value)) begin
            input_error_count++;
            txn.input_error = 1'b1;
            `uvm_error("VLM_RESERVATION_BUSY_XZ",
                       $sformatf("cycle %0d direction %0d delay %0d gid %0d sub bank %0d busy contains X/Z",
                                 txn.cycle, direction, delay, gid, sub_bank))
          end
        end
      end
    end
  end
endfunction : collect_busy

function void vlm_reservation_monitor::collect_reservation_requests(
    ref vlm_reservation_cycle_transaction_t txn);
  bit payload_known;

  // Convert each read reservation port only when request, address, and delay are fully known.
  for (int unsigned bank = 0; bank < BANK_N; bank++) begin
    // Unknown request valid cannot be interpreted as either an active event or an idle port.
    if ($isunknown(vif.mon_cb.rreq[bank])) begin
      input_error_count++;
      txn.input_error = 1'b1;
      `uvm_error("VLM_RESERVATION_RREQ_XZ",
                 $sformatf("cycle %0d read reservation bank %0d request contains X/Z", txn.cycle, bank))
      continue;
    end

    if (vif.mon_cb.rreq[bank] === 1'b1) begin
      payload_known = 1'b1;

      // An active read reservation address must be fully known before creating a request instance.
      if ($isunknown(vif.mon_cb.raddr[bank])) begin
        input_error_count++;
        txn.input_error = 1'b1;
        payload_known = 1'b0;
        `uvm_error("VLM_RESERVATION_RADDR_XZ",
                   $sformatf("cycle %0d read reservation bank %0d address contains X/Z", txn.cycle, bank))
      end

      // An active read reservation delay must be fully known before creating a request instance.
      if ($isunknown(vif.mon_cb.rdly[bank])) begin
        input_error_count++;
        txn.input_error = 1'b1;
        payload_known = 1'b0;
        `uvm_error("VLM_RESERVATION_RDLY_XZ",
                   $sformatf("cycle %0d read reservation bank %0d delay contains X/Z", txn.cycle, bank))
      end

      if ($isunknown(vif.mon_cb.rgid[bank])) begin
        input_error_count++;
        txn.input_error = 1'b1;
        payload_known = 1'b0;
        `uvm_error("VLM_RESERVATION_RGID_XZ",
                   $sformatf("cycle %0d read reservation bank %0d gid contains X/Z", txn.cycle, bank))
      end

      if (payload_known) begin
        txn.rsv_rreq_array[bank] = new();
        txn.rsv_rreq_array[bank].address = vif.mon_cb.raddr[bank];
        txn.rsv_rreq_array[bank].delay = vif.mon_cb.rdly[bank];
        txn.rsv_rreq_array[bank].gid = vif.mon_cb.rgid[bank];
      end
    end
  end

  // Convert each write reservation port independently because both physical ports may be active.
  for (int unsigned bank = 0; bank < BANK_N; bank++) begin
    // Each configured write reservation port can independently produce one request handle.
    for (int unsigned port = 0; port < WRITE_PORT_N; port++) begin
      // Unknown request valid cannot create a write reservation request instance.
      if ($isunknown(vif.mon_cb.wreq[bank][port])) begin
        input_error_count++;
        txn.input_error = 1'b1;
        `uvm_error("VLM_RESERVATION_WREQ_XZ",
                   $sformatf("cycle %0d write reservation bank %0d port %0d request contains X/Z",
                             txn.cycle, bank, port))
        continue;
      end

      if (vif.mon_cb.wreq[bank][port] === 1'b1) begin
        payload_known = 1'b1;

        // An active write reservation address must be fully known before creating a request instance.
        if ($isunknown(vif.mon_cb.waddr[bank][port])) begin
          input_error_count++;
          txn.input_error = 1'b1;
          payload_known = 1'b0;
          `uvm_error("VLM_RESERVATION_WADDR_XZ",
                     $sformatf("cycle %0d write reservation bank %0d port %0d address contains X/Z",
                               txn.cycle, bank, port))
        end

        // An active write reservation delay must be fully known before creating a request instance.
        if ($isunknown(vif.mon_cb.wdly[bank][port])) begin
          input_error_count++;
          txn.input_error = 1'b1;
          payload_known = 1'b0;
          `uvm_error("VLM_RESERVATION_WDLY_XZ",
                     $sformatf("cycle %0d write reservation bank %0d port %0d delay contains X/Z",
                               txn.cycle, bank, port))
        end

        if ($isunknown(vif.mon_cb.wgid[bank][port])) begin
          input_error_count++;
          txn.input_error = 1'b1;
          payload_known = 1'b0;
          `uvm_error("VLM_RESERVATION_WGID_XZ",
                     $sformatf("cycle %0d write reservation bank %0d port %0d gid contains X/Z",
                               txn.cycle, bank, port))
        end

        if (payload_known) begin
          txn.rsv_wreq_array[bank][port] = new();
          txn.rsv_wreq_array[bank][port].address = vif.mon_cb.waddr[bank][port];
          txn.rsv_wreq_array[bank][port].delay = vif.mon_cb.wdly[bank][port];
          txn.rsv_wreq_array[bank][port].gid = vif.mon_cb.wgid[bank][port];
        end
      end
    end
  end
endfunction : collect_reservation_requests

function void vlm_reservation_monitor::collect_memory_requests(ref vlm_reservation_cycle_transaction_t txn);
  // Convert each BANK's actual read and write MEM ports into independent nullable handles.
  for (int unsigned bank = 0; bank < BANK_N; bank++) begin
    // Unknown MEM read valid cannot be interpreted as an actual request.
    if ($isunknown(vif.mon_cb.rvld[bank])) begin
      input_error_count++;
      txn.input_error = 1'b1;
      `uvm_error("VLM_RESERVATION_MEM_RVLD_XZ",
                 $sformatf("cycle %0d MEM read bank %0d valid contains X/Z", txn.cycle, bank))
    end else if (vif.mon_cb.rvld[bank] === 1'b1) begin
      // An active MEM read address must be fully known before creating a request instance.
      if ($isunknown(vif.mon_cb.mem_raddr[bank])) begin
        input_error_count++;
        txn.input_error = 1'b1;
        `uvm_error("VLM_RESERVATION_MEM_RADDR_XZ",
                   $sformatf("cycle %0d MEM read bank %0d address contains X/Z", txn.cycle, bank))
      end else begin
        txn.mem_rreq_array[bank] = new();
        txn.mem_rreq_array[bank].address = vif.mon_cb.mem_raddr[bank];
      end
    end

    // Unknown MEM write valid cannot be interpreted as an actual request.
    if ($isunknown(vif.mon_cb.wvld[bank])) begin
      input_error_count++;
      txn.input_error = 1'b1;
      `uvm_error("VLM_RESERVATION_MEM_WVLD_XZ",
                 $sformatf("cycle %0d MEM write bank %0d valid contains X/Z", txn.cycle, bank))
    end else if (vif.mon_cb.wvld[bank] === 1'b1) begin
      // An active MEM write address must be fully known before creating a request instance.
      if ($isunknown(vif.mon_cb.mem_waddr[bank])) begin
        input_error_count++;
        txn.input_error = 1'b1;
        `uvm_error("VLM_RESERVATION_MEM_WADDR_XZ",
                   $sformatf("cycle %0d MEM write bank %0d address contains X/Z", txn.cycle, bank))
      end else begin
        txn.mem_wreq_array[bank] = new();
        txn.mem_wreq_array[bank].address = vif.mon_cb.mem_waddr[bank];
        txn.mem_wreq_array[bank].strb = vif.mon_cb.wstrb[bank];
        txn.mem_wreq_array[bank].data = vif.mon_cb.wdata[bank];
      end
    end
  end
endfunction : collect_memory_requests

`endif // INC_VLM_RESERVATION_MONITOR_SVH
