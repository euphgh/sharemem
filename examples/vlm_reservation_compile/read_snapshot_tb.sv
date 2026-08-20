`timescale 1ns/1ps

package vlm_read_snapshot_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
  `include "vlm_memory_sequence_item.svh"
  `include "vlm_reservation_types.svh"
  `include "vlm_reservation_external_busy_policy.svh"
  `include "vlm_reservation_agent_config.svh"
  `include "vlm_reservation_scheduler.svh"
  `include "vlm_reservation_checker.svh"
  `include "vlm_reservation_coverage.svh"
  `include "vlm_reservation_monitor.svh"
  `include "vlm_reservation_agent.svh"
  `include "vlm_agent.svh"

  //----------------------------------------------------------------------------
  // @brief Provides a byte memory endpoint for synchronous write/read transport.
  //
  // Applies writes immediately and fills read transactions from the current
  // state. It records transport cycles but does not model reservation behavior.
  //----------------------------------------------------------------------------
  class vlm_read_snapshot_memory_sink extends uvm_component;
    uvm_tlm_b_transport_imp #(vlm_memory_sequence_item, vlm_read_snapshot_memory_sink) mem_imp;
    virtual clk_if clk_vif;
    byte unsigned memory[longint unsigned];
    int unsigned write_transport_count;
    int unsigned read_transport_count;
    shm_cycle_t last_read_transport_cycle;

    //------------------------------------------------------------------------
    // @brief Constructs the byte memory endpoint and transport implementation.
    //
    // @param name   UVM component instance name.
    // @param parent Parent component that owns this endpoint.
    //------------------------------------------------------------------------
    function new(string name = "vlm_read_snapshot_memory_sink", uvm_component parent = null);
      super.new(name, parent);
      mem_imp = new("mem_imp", this);
    endfunction : new

    //------------------------------------------------------------------------
    // @brief Obtains the shared cycle service used for transport diagnostics.
    //
    // @param phase UVM build phase.
    //------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
        `uvm_fatal("VLM_READ_SNAPSHOT_NO_CLK", "memory sink requires clk_vif")
      end
    endfunction : build_phase

    //------------------------------------------------------------------------
    // @brief Forms the associative-memory key for one physical byte.
    //
    // @param bank  Logical BANK index.
    // @param gid   Physical low/high bank selector.
    // @param baddr BANK-local byte address.
    // @return Unique physical byte key.
    //------------------------------------------------------------------------
    function longint unsigned byte_key(int unsigned bank, shm_gid_t gid, shm_baddr_t baddr);
      shm_physical_addr_t physical_addr;

      physical_addr.bank_id = shm_bank_id_t'(bank);
      physical_addr.gid = gid;
      physical_addr.baddr = baddr;
      return physical_byte_key(physical_addr);
    endfunction : byte_key

    //------------------------------------------------------------------------
    // @brief Writes one byte directly for component-test setup.
    //
    // @param bank  Logical BANK index.
    // @param gid   Physical low/high bank selector.
    // @param baddr BANK-local byte address.
    // @param data  Byte value to store.
    //------------------------------------------------------------------------
    function void set_byte(int unsigned bank, shm_gid_t gid, shm_baddr_t baddr, byte unsigned data);
      memory[byte_key(bank, gid, baddr)] = data;
    endfunction : set_byte

    //------------------------------------------------------------------------
    // @brief Reads one byte, returning zero for an untouched location.
    //
    // @param bank  Logical BANK index.
    // @param gid   Physical low/high bank selector.
    // @param baddr BANK-local byte address.
    // @return Stored byte or zero when the key has not been initialized.
    //------------------------------------------------------------------------
    function byte unsigned get_byte(int unsigned bank, shm_gid_t gid, shm_baddr_t baddr);
      longint unsigned key = byte_key(bank, gid, baddr);
      return memory.exists(key) ? memory[key] : 8'h00;
    endfunction : get_byte

    //------------------------------------------------------------------------
    // @brief Applies a write or fills a read transaction without consuming time.
    //
    // @param trans Resolved memory transaction with trusted gid metadata.
    // @param delay Unused TLM delay retained by the blocking transport API.
    //------------------------------------------------------------------------
    virtual task b_transport(vlm_memory_sequence_item trans, uvm_tlm_time delay);
      if (trans.vlm_read) begin
        read_transport_count++;
        last_read_transport_cycle = clk_vif.cycle_count;
      end else begin
        write_transport_count++;
      end

      for (int unsigned bank = 0; bank < BANK_N; bank++) begin
        if (!trans.vlm_bken[bank] || !trans.gid_valid[bank] ||
            !trans.reservation_matched[bank]) begin
          continue;
        end
        for (int unsigned byte_offset = 0; byte_offset < VLM_DATA_BYTE_W; byte_offset++) begin
          shm_baddr_t byte_address = trans.vlm_addr[bank] + shm_baddr_t'(byte_offset);
          if (trans.vlm_read) begin
            trans.vlm_data[bank][byte_offset * 8 +: 8] =
                get_byte(bank, trans.vlm_gid[bank], byte_address);
          end else if (trans.vlm_strb[bank][byte_offset]) begin
            set_byte(bank, trans.vlm_gid[bank], byte_address,
                     trans.vlm_data[bank][byte_offset * 8 +: 8]);
          end
        end
      end
    endtask : b_transport

    `uvm_component_utils(vlm_read_snapshot_memory_sink)
  endclass : vlm_read_snapshot_memory_sink

  //----------------------------------------------------------------------------
  // @brief Captures completed read transactions and their publication cycles.
  //----------------------------------------------------------------------------
  class vlm_read_snapshot_sink extends uvm_subscriber #(vlm_memory_sequence_item);
    virtual clk_if clk_vif;
    vlm_memory_sequence_item items[$];
    shm_cycle_t cycles[$];

    //------------------------------------------------------------------------
    // @brief Constructs the completed-read sink.
    //
    // @param name   UVM component instance name.
    // @param parent Parent component that owns this sink.
    //------------------------------------------------------------------------
    function new(string name = "vlm_read_snapshot_sink", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    //------------------------------------------------------------------------
    // @brief Obtains the shared cycle service used for response diagnostics.
    //
    // @param phase UVM build phase.
    //------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
        `uvm_fatal("VLM_READ_RESPONSE_NO_CLK", "read sink requires clk_vif")
      end
    endfunction : build_phase

    //------------------------------------------------------------------------
    // @brief Records one completed response transaction and publication cycle.
    //
    // @param t Completed read transaction from the unified agent.
    //------------------------------------------------------------------------
    virtual function void write(vlm_memory_sequence_item t);
      items.push_back(t);
      cycles.push_back(clk_vif.cycle_count);
    endfunction : write

    `uvm_component_utils(vlm_read_snapshot_sink)
  endclass : vlm_read_snapshot_sink

  //----------------------------------------------------------------------------
  // @brief Exposes the production memory-cycle task while disabling interface sampling.
  //
  // The component test supplies normalized cycle transactions directly. Read
  // workers, transport order, clocking-block data drive, and idle accounting
  // remain the production implementation.
  //----------------------------------------------------------------------------
  class vlm_read_snapshot_test_agent extends vlm_agent;
    //------------------------------------------------------------------------
    // @brief Constructs the test adapter around the production unified agent.
    //
    // @param name   UVM component instance name.
    // @param parent Parent component that owns this adapter.
    //------------------------------------------------------------------------
    function new(string name = "vlm_read_snapshot_test_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    //------------------------------------------------------------------------
    // @brief Initializes read data without starting the production monitor loop.
    //
    // @param phase UVM main phase controlling this component thread.
    //------------------------------------------------------------------------
    virtual task main_phase(uvm_phase phase);
      vif.slv_cb.rdata <= '0;
      forever @(vif.slv_cb);
    endtask : main_phase

    //------------------------------------------------------------------------
    // @brief Processes one caller-built normalized memory cycle.
    //
    // @param txn    Cycle transaction containing optional read/write requests.
    // @param result Trusted gid and reservation-match metadata for those requests.
    //------------------------------------------------------------------------
    task process_test_memory_cycle(const ref vlm_reservation_cycle_transaction_t txn,
                                   const ref vlm_reservation_check_result_t      result);
      process_memory_requests(txn, result);
    endtask : process_test_memory_cycle

    `uvm_component_utils(vlm_read_snapshot_test_agent)
  endclass : vlm_read_snapshot_test_agent

  //----------------------------------------------------------------------------
  // @brief Verifies FFD cutoff, byte strobes, gid isolation, and read pipelining.
  //----------------------------------------------------------------------------
  class vlm_read_snapshot_test extends uvm_test;
    vlm_reservation_agent_config cfg;
    vlm_read_snapshot_test_agent agent;
    vlm_read_snapshot_memory_sink memory_sink;
    vlm_read_snapshot_sink read_sink;
    virtual vlm_interface vif;
    virtual clk_if clk_vif;

    //------------------------------------------------------------------------
    // @brief Constructs the read-snapshot component test.
    //
    // @param name   UVM component instance name.
    // @param parent Parent component that owns this test.
    //------------------------------------------------------------------------
    function new(string name = "vlm_read_snapshot_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    //------------------------------------------------------------------------
    // @brief Builds the production agent adapter and memory/read sinks.
    //
    // @param phase UVM build phase.
    //------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
      int unsigned test_ffd_cyc = FFD_CYC;

      super.build_phase(phase);
      if (!uvm_config_db#(virtual vlm_interface)::get(this, "", "vlm_vif", vif) ||
          !uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
        `uvm_fatal("VLM_READ_SNAPSHOT_NO_VIF", "test requires vlm_vif and clk_vif")
      end
      void'($value$plusargs("TEST_FFD_CYC=%d", test_ffd_cyc));

      cfg = vlm_reservation_agent_config::type_id::create("cfg");
      cfg.vif = vif;
      cfg.ffd_cyc = test_ffd_cyc;
      cfg.rport_dly = RPORT_DLY;
      uvm_config_db#(vlm_reservation_agent_config)::set(this, "agent", "cfg", cfg);

      agent = vlm_read_snapshot_test_agent::type_id::create("agent", this);
      memory_sink = vlm_read_snapshot_memory_sink::type_id::create("memory_sink", this);
      read_sink = vlm_read_snapshot_sink::type_id::create("read_sink", this);
    endfunction : build_phase

    //------------------------------------------------------------------------
    // @brief Connects the production transport and completed-read paths.
    //
    // @param phase UVM connect phase.
    //------------------------------------------------------------------------
    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.mem_port.connect(memory_sink.mem_imp);
      agent.read_analysis_port.connect(read_sink.analysis_export);
    endfunction : connect_phase

    //------------------------------------------------------------------------
    // @brief Clears all request handles and result metadata for one cycle.
    //
    // @param txn    Cycle transaction to initialize.
    // @param result Checker result to initialize.
    // @param cycle  Shared sampled cycle assigned to the transaction.
    //------------------------------------------------------------------------
    function void initialize_cycle(ref vlm_reservation_cycle_transaction_t txn,
                                   ref vlm_reservation_check_result_t      result,
                                   shm_cycle_t                            cycle);
      txn.cycle = cycle;
      txn.input_error = 1'b0;
      txn.observed_busy[VLM_RESERVATION_READ] = '0;
      txn.observed_busy[VLM_RESERVATION_WRITE] = '0;
      result.passed = 1'b1;
      result.reservation_error_count = 0;
      result.busy_error_count = 0;
      result.mem_match_error_count = 0;
      result.dly_zero_error_count = 0;
      result.matched_mem_request_count = 0;

      foreach (txn.mem_rreq_array[bank]) begin
        txn.mem_rreq_array[bank] = null;
        txn.mem_wreq_array[bank] = null;
      end
      foreach (txn.rsv_rreq_array[bank]) begin
        txn.rsv_rreq_array[bank] = null;
      end
      foreach (txn.rsv_wreq_array[bank, port]) begin
        txn.rsv_wreq_array[bank][port] = null;
      end
      for (int unsigned direction = 0; direction < VLM_RESERVATION_DIRECTION_N; direction++) begin
        for (int unsigned bank = 0; bank < BANK_N; bank++) begin
          result.mem_gid[direction][bank] = '0;
          result.mem_gid_valid[direction][bank] = 1'b0;
          result.mem_reservation_matched[direction][bank] = 1'b0;
          result.mem_match_outcome[direction][bank] = '0;
          for (int unsigned port = 0; port < WRITE_PORT_N; port++) begin
            result.reservation_outcome[direction][bank][port] = '0;
          end
        end
      end
    endfunction : initialize_cycle

    //------------------------------------------------------------------------
    // @brief Processes one clock cycle with optional single-BANK read and write.
    //
    // @param read_enable  Enables one trusted MEM read.
    // @param read_bank    BANK carrying the read.
    // @param read_gid     Gid resolved for the read.
    // @param read_address Read base BADDR.
    // @param write_enable Enables one trusted MEM write.
    // @param write_bank   BANK carrying the write.
    // @param write_gid    Gid resolved for the write.
    // @param write_address Write base BADDR.
    // @param write_strb   Per-byte write enables.
    // @param write_data   Write beat payload.
    // @param sampled_data Read-data value sampled at the start of this cycle.
    // @param cycle        Shared cycle assigned to the processed transaction.
    //------------------------------------------------------------------------
    task process_clock_cycle(
        bit                                read_enable,
        int unsigned                       read_bank,
        shm_gid_t                          read_gid,
        shm_baddr_t                        read_address,
        bit                                write_enable,
        int unsigned                       write_bank,
        shm_gid_t                          write_gid,
        shm_baddr_t                        write_address,
        bit [VLM_DATA_BYTE_W-1:0]          write_strb,
        bit [VLM_DATA_BIT_W-1:0]           write_data,
        output logic [VLM_DATA_BIT_W-1:0] sampled_data,
        output shm_cycle_t                 cycle);
      vlm_reservation_cycle_transaction_t txn;
      vlm_reservation_check_result_t result;

      @(vif.mon_cb);
      sampled_data = vif.mon_cb.rdata[read_bank];
      cycle = clk_vif.cycle_count;
      initialize_cycle(txn, result, cycle);

      if (read_enable) begin
        txn.mem_rreq_array[read_bank] = new();
        txn.mem_rreq_array[read_bank].address = read_address;
        result.mem_gid[VLM_RESERVATION_READ][read_bank] = read_gid;
        result.mem_gid_valid[VLM_RESERVATION_READ][read_bank] = 1'b1;
        result.mem_reservation_matched[VLM_RESERVATION_READ][read_bank] = 1'b1;
      end
      if (write_enable) begin
        txn.mem_wreq_array[write_bank] = new();
        txn.mem_wreq_array[write_bank].address = write_address;
        txn.mem_wreq_array[write_bank].strb = write_strb;
        txn.mem_wreq_array[write_bank].data = write_data;
        result.mem_gid[VLM_RESERVATION_WRITE][write_bank] = write_gid;
        result.mem_gid_valid[VLM_RESERVATION_WRITE][write_bank] = 1'b1;
        result.mem_reservation_matched[VLM_RESERVATION_WRITE][write_bank] = 1'b1;
      end

      agent.process_test_memory_cycle(txn, result);
    endtask : process_clock_cycle

    //------------------------------------------------------------------------
    // @brief Stops the test when a required condition is false.
    //
    // @param condition Condition that must be true.
    // @param message   Failure diagnostic.
    //------------------------------------------------------------------------
    function void check_true(bit condition, string message);
      if (!condition) begin
        `uvm_fatal("VLM_READ_SNAPSHOT_CHECK", message)
      end
    endfunction : check_true

    //------------------------------------------------------------------------
    // @brief Verifies the last write through the FFD cutoff is returned.
    //------------------------------------------------------------------------
    task test_cutoff_visibility();
      int unsigned bank = 2;
      shm_gid_t gid = 0;
      shm_baddr_t address = 'h120;
      byte unsigned expected_data;
      int unsigned initial_read_count = memory_sink.read_transport_count;
      shm_cycle_t accept_cycle;

      memory_sink.set_byte(bank, gid, address, 8'h11);
      for (int unsigned relative_cycle = 0; relative_cycle <= cfg.rport_dly; relative_cycle++) begin
        bit write_enable = relative_cycle <= cfg.ffd_cyc;
        bit [VLM_DATA_BIT_W-1:0] write_data = '0;
        logic [VLM_DATA_BIT_W-1:0] sampled_data;
        shm_cycle_t cycle;

        write_data[7:0] = byte'(8'h40 + relative_cycle);
        process_clock_cycle(relative_cycle == 0, bank, gid, address,
                            write_enable, bank, gid, address, VLM_DATA_BYTE_W'(1), write_data,
                            sampled_data, cycle);
        if (relative_cycle == 0) begin
          accept_cycle = cycle;
        end
        if (relative_cycle == cfg.rport_dly) begin
          expected_data = byte'(8'h40 + cfg.ffd_cyc - 1);
          check_true(sampled_data[7:0] == expected_data,
                     $sformatf("FFD %0d returned 0x%02x, expected cutoff value 0x%02x",
                               cfg.ffd_cyc, sampled_data[7:0], expected_data));
        end
      end
      #1ps;
      check_true(memory_sink.read_transport_count == initial_read_count + 1,
                 "cutoff test did not create exactly one snapshot");
      check_true(memory_sink.last_read_transport_cycle == accept_cycle + cfg.ffd_cyc - 1,
                 $sformatf("snapshot cycle %0d, expected %0d",
                           memory_sink.last_read_transport_cycle, accept_cycle + cfg.ffd_cyc - 1));
      check_true(agent.is_memory_idle(), "cutoff read worker did not retire on the response cycle");
    endtask : test_cutoff_visibility

    //------------------------------------------------------------------------
    // @brief Verifies sparse same-cycle writes update only selected read bytes.
    //------------------------------------------------------------------------
    task test_sparse_strobe();
      int unsigned bank = 4;
      shm_gid_t gid = 0;
      shm_baddr_t address = 'h240;
      bit [VLM_DATA_BIT_W-1:0] write_data = '0;
      bit [VLM_DATA_BYTE_W-1:0] write_strb = '0;

      for (int unsigned byte_offset = 0; byte_offset < VLM_DATA_BYTE_W; byte_offset++) begin
        memory_sink.set_byte(bank, gid, address + shm_baddr_t'(byte_offset), byte'(8'h10 + byte_offset));
      end
      foreach (write_strb[byte_offset]) begin
        if (byte_offset == 0 || byte_offset == 7 || byte_offset == 31) begin
          write_strb[byte_offset] = 1'b1;
          write_data[byte_offset * 8 +: 8] = byte'(8'ha0 + byte_offset);
        end
      end

      for (int unsigned relative_cycle = 0; relative_cycle <= cfg.rport_dly; relative_cycle++) begin
        logic [VLM_DATA_BIT_W-1:0] sampled_data;
        shm_cycle_t cycle;

        process_clock_cycle(relative_cycle == 0, bank, gid, address,
                            relative_cycle == 0, bank, gid, address, write_strb, write_data,
                            sampled_data, cycle);
        if (relative_cycle == cfg.rport_dly) begin
          for (int unsigned byte_offset = 0; byte_offset < VLM_DATA_BYTE_W; byte_offset++) begin
            byte unsigned expected = write_strb[byte_offset] ? byte'(8'ha0 + byte_offset) :
                                                               byte'(8'h10 + byte_offset);
            check_true(sampled_data[byte_offset * 8 +: 8] == expected,
                       $sformatf("sparse byte %0d returned 0x%02x, expected 0x%02x",
                                 byte_offset, sampled_data[byte_offset * 8 +: 8], expected));
          end
        end
      end
      #1ps;
      check_true(agent.is_memory_idle(), "sparse read worker did not retire");
    endtask : test_sparse_strobe

    //------------------------------------------------------------------------
    // @brief Verifies a same-BADDR write in the other gid is not read-visible.
    //------------------------------------------------------------------------
    task test_gid_isolation();
      int unsigned bank = 6;
      shm_baddr_t address = 'h360;
      bit [VLM_DATA_BIT_W-1:0] write_data = '0;

      memory_sink.set_byte(bank, 0, address, 8'h35);
      memory_sink.set_byte(bank, 1, address, 8'hca);
      write_data[7:0] = 8'he7;

      for (int unsigned relative_cycle = 0; relative_cycle <= cfg.rport_dly; relative_cycle++) begin
        logic [VLM_DATA_BIT_W-1:0] sampled_data;
        shm_cycle_t cycle;

        process_clock_cycle(relative_cycle == 0, bank, 0, address,
                            relative_cycle == 0, bank, 1, address, VLM_DATA_BYTE_W'(1), write_data,
                            sampled_data, cycle);
        if (relative_cycle == cfg.rport_dly) begin
          check_true(sampled_data[7:0] == 8'h35,
                     $sformatf("gid-zero read returned 0x%02x after gid-one write", sampled_data[7:0]));
        end
      end
      #1ps;
      check_true(memory_sink.get_byte(bank, 0, address) == 8'h35 &&
                 memory_sink.get_byte(bank, 1, address) == 8'he7,
                 "same-BADDR write did not remain isolated by gid");
    endtask : test_gid_isolation

    //------------------------------------------------------------------------
    // @brief Verifies consecutive same-BANK reads return in request order.
    //------------------------------------------------------------------------
    task test_pipelined_reads();
      int unsigned bank = 8;
      shm_gid_t gid = 1;
      shm_baddr_t first_address = 'h480;
      shm_baddr_t second_address = 'h4c0;

      memory_sink.set_byte(bank, gid, first_address, 8'h5a);
      memory_sink.set_byte(bank, gid, second_address, 8'ha5);

      for (int unsigned relative_cycle = 0; relative_cycle <= cfg.rport_dly + 1; relative_cycle++) begin
        bit read_enable = relative_cycle <= 1;
        shm_baddr_t read_address = relative_cycle == 0 ? first_address : second_address;
        logic [VLM_DATA_BIT_W-1:0] sampled_data;
        shm_cycle_t cycle;

        process_clock_cycle(read_enable, bank, gid, read_address,
                            1'b0, bank, gid, '0, '0, '0, sampled_data, cycle);
        if (relative_cycle == cfg.rport_dly) begin
          check_true(sampled_data[7:0] == 8'h5a,
                     $sformatf("first pipelined read returned 0x%02x", sampled_data[7:0]));
        end else if (relative_cycle == cfg.rport_dly + 1) begin
          check_true(sampled_data[7:0] == 8'ha5,
                     $sformatf("second pipelined read returned 0x%02x", sampled_data[7:0]));
        end
      end
      #1ps;
      check_true(agent.is_memory_idle(), "pipelined read workers did not retire");
    endtask : test_pipelined_reads

    //------------------------------------------------------------------------
    // @brief Runs every positive FFD component scenario.
    //
    // @param phase UVM main phase controlling the test objection.
    //------------------------------------------------------------------------
    virtual task main_phase(uvm_phase phase);
      phase.raise_objection(this);
      wait (vif.rst_n === 1'b1);

      test_cutoff_visibility();
      test_sparse_strobe();
      test_gid_isolation();
      test_pipelined_reads();

      check_true(read_sink.items.size() == 5,
                 $sformatf("completed read count %0d, expected 5", read_sink.items.size()));
      `uvm_info("VLM_READ_SNAPSHOT_TEST",
                $sformatf("FFD_CYC=%0d RPORT_DLY=%0d read snapshot component test: PASS",
                          cfg.ffd_cyc, cfg.rport_dly),
                UVM_LOW)
      phase.drop_objection(this);
    endtask : main_phase

    `uvm_component_utils(vlm_read_snapshot_test)
  endclass : vlm_read_snapshot_test
endpackage : vlm_read_snapshot_test_pkg

module read_snapshot_tb;
  import uvm_pkg::*;
  import shm_util_package::*;
  import vlm_read_snapshot_test_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  clk_if clock_service(clk);
  vlm_interface vif(clk, rst_n);

  always #5ns clk = ~clk;

  initial begin
    vif.rreq = '0;
    vif.raddr = '0;
    vif.rdly = '0;
    vif.rgid = '0;
    vif.wreq = '0;
    vif.waddr = '0;
    vif.wdly = '0;
    vif.wgid = '0;
    vif.rvld = '0;
    vif.mem_raddr = '0;
    vif.wvld = '0;
    vif.mem_waddr = '0;
    vif.wstrb = '0;
    vif.wdata = '0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual clk_if)::set(null, "uvm_test_top", "clk_vif", clock_service);
    uvm_config_db#(virtual clk_if)::set(null, "uvm_test_top.*", "clk_vif", clock_service);
    uvm_config_db#(virtual vlm_interface)::set(null, "uvm_test_top", "vlm_vif", vif);
    run_test("vlm_read_snapshot_test");
  end
endmodule : read_snapshot_tb
