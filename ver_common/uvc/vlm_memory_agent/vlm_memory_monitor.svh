`ifndef INC_VLM_MEMORY_MONITOR_SVH
`define INC_VLM_MEMORY_MONITOR_SVH

//------------------------------------------------------------------------------
// @brief Publishes read and write transactions observed on the MEM interface.
//
// Samples fully known VLM memory requests, collects fixed-latency read data,
// and publishes typed transactions through separate read and write analysis
// ports. It does not drive MEM data or perform reservation checks.
//------------------------------------------------------------------------------
class vlm_memory_monitor extends uvm_monitor;

  // Total number of read and write transactions sampled by this monitor.
  int unsigned transaction_count;

  // Number of read transactions sampled by this monitor.
  int unsigned read_transaction_count;

  // Number of write transactions sampled by this monitor.
  int unsigned write_transaction_count;

  // Optional debug output filename used when +file_debug is present.
  string debug_filename = "vlm_memory.rtl";

  // Optional debug output file descriptor; zero means no file is open.
  int debug_file;

  // Read-only VLM memory interface assigned by the containing agent.
  virtual vlm_memory_interface memory_vif;

  // Publishes completed MEM read transactions after their fixed-latency data.
  uvm_analysis_port #(vlm_memory_sequence_item) read_analysis_port;

  // Publishes MEM write transactions sampled from the request cycle.
  uvm_analysis_port #(vlm_memory_sequence_item) write_analysis_port;

  //------------------------------------------------------------------------------
  // @brief Constructs the VLM memory monitor and opens optional debug output.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this monitor.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_memory_monitor",
      uvm_component parent = null);

  //------------------------------------------------------------------------------
  // @brief Constructs the read and write analysis ports.
  //
  // @param phase UVM build phase used to construct monitor ports.
  //------------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Waits for reset release and continuously samples MEM transactions.
  //
  // @param phase UVM run phase controlling the monitor lifetime.
  //------------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Closes the optional debug output file.
  //
  // @param phase UVM final phase invoked after simulation activity completes.
  //------------------------------------------------------------------------------
  extern virtual function void final_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Samples read and write request streams in parallel.
  //
  // @pre memory_vif is valid and reset has been released.
  //------------------------------------------------------------------------------
  extern protected task monitor_signals();

  `uvm_component_utils(vlm_memory_monitor)

endclass : vlm_memory_monitor

function vlm_memory_monitor::new(
    string        name = "vlm_memory_monitor",
    uvm_component parent = null);
  super.new(name, parent);

  if ($test$plusargs("file_debug")) begin
    debug_file = $fopen(debug_filename, "w");
  end
endfunction : new

function void vlm_memory_monitor::build_phase(uvm_phase phase);
  super.build_phase(phase);
  read_analysis_port  = new("read_analysis_port", this);
  write_analysis_port = new("write_analysis_port", this);
endfunction : build_phase

task vlm_memory_monitor::main_phase(uvm_phase phase);
  super.main_phase(phase);

  if (memory_vif == null) begin
    `uvm_fatal("VLM_MEMORY_NO_VIF", "vlm_memory_monitor requires memory_vif")
  end

  wait (memory_vif.rst_n === 1'b1);
  monitor_signals();
endtask : main_phase

function void vlm_memory_monitor::final_phase(uvm_phase phase);
  super.final_phase(phase);

  if (debug_file != 0) begin
    $fclose(debug_file);
    debug_file = 0;
  end
endfunction : final_phase

task vlm_memory_monitor::monitor_signals();
  fork
    forever begin
      vlm_memory_sequence_item read_transaction;

      @(memory_vif.mon_cb iff (|memory_vif.mon_cb.rvld) === 1'b1);

      read_transaction =
          vlm_memory_sequence_item::type_id::create($sformatf("read_transaction_%0d", read_transaction_count));
      read_transaction.vlm_read = 1'b1;

      for (int unsigned bank = 0; bank < BANK_N; bank++) begin
        read_transaction.vlm_bken[bank] = memory_vif.mon_cb.rvld[bank];
        read_transaction.vlm_addr[bank] = memory_vif.mon_cb.raddr[bank];
      end

      fork
        begin
          automatic vlm_memory_sequence_item completed_transaction = read_transaction;

          repeat (RPORT_DLY) begin
            @(memory_vif.mon_cb);
          end

          for (int unsigned bank = 0; bank < BANK_N; bank++) begin
            completed_transaction.vlm_data[bank] = memory_vif.mon_cb.rdata[bank];
            completed_transaction.vlm_strb[bank] = '1;
          end

          if (debug_file != 0) begin
            completed_transaction.write_file(debug_file);
          end

          read_analysis_port.write(completed_transaction);
        end
      join_none

      read_transaction_count++;
      transaction_count++;
    end

    forever begin
      vlm_memory_sequence_item write_transaction;

      @(memory_vif.mon_cb iff (|memory_vif.mon_cb.wvld) === 1'b1);

      write_transaction =
          vlm_memory_sequence_item::type_id::create($sformatf("write_transaction_%0d", write_transaction_count));
      write_transaction.vlm_read = 1'b0;

      for (int unsigned bank = 0; bank < BANK_N; bank++) begin
        write_transaction.vlm_bken[bank] = memory_vif.mon_cb.wvld[bank];
        write_transaction.vlm_addr[bank] = memory_vif.mon_cb.waddr[bank];
        write_transaction.vlm_strb[bank] = memory_vif.mon_cb.wstrb[bank];
        write_transaction.vlm_data[bank] = memory_vif.mon_cb.wdata[bank];
      end

      if (debug_file != 0) begin
        write_transaction.write_file(debug_file);
      end

      write_analysis_port.write(write_transaction);
      write_transaction_count++;
      transaction_count++;
    end
  join
endtask : monitor_signals

`endif // INC_VLM_MEMORY_MONITOR_SVH
