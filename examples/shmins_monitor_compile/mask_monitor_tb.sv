`timescale 1ns/1ps

package shmins_mask_monitor_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;
  import shm_seq_item_package::*;

  `include "uvm_macros.svh"
  `include "shm_transaction_lifecycle_types.svh"
  `include "shmins_monitor.svh"
  `include "shmins_request_coverage.svh"
  `include "shm_expected_report_catcher.svh"

  typedef enum int unsigned {
    MONITOR_PAYLOAD_KNOWN,
    MONITOR_INACTIVE_X,
    MONITOR_INACTIVE_Z,
    MONITOR_ACTIVE_LENGTH_X,
    MONITOR_MASKED_DATA_X,
    MONITOR_MASKED_INDEXED_OFFSET_X,
    MONITOR_ACTIVE_MASK_X,
    MONITOR_SHARED_OFFSET_X,
    MONITOR_ACTIVE_INDEXED_OFFSET_X,
    MONITOR_ACTIVE_DATA_X,
    MONITOR_M2V_DATA_X,
    MONITOR_OUT_OF_LENGTH_X,
    MONITOR_ALL_X
  } monitor_payload_mode_e;

  //----------------------------------------------------------------------------
  // @brief Captures requests published by the production SHMINS monitor.
  //----------------------------------------------------------------------------
  class shmins_mask_monitor_sink extends uvm_subscriber #(shmins_sequence_item);
    // Number of requests published through the production analysis port.
    int unsigned transaction_count;

    // Most recently observed request; the monitor retains ownership.
    shmins_sequence_item last_transaction;

    //----------------------------------------------------------------------------
    // @brief Constructs an empty request sink.
    //
    // @param name UVM component instance name.
    // @param parent Parent component that owns this sink.
    //----------------------------------------------------------------------------
    function new(string name = "shmins_mask_monitor_sink", uvm_component parent = null);
      super.new(name, parent);
      transaction_count = 0;
    endfunction : new

    //----------------------------------------------------------------------------
    // @brief Records one monitor-published request.
    //
    // @param transaction Immutable request published by the monitor.
    //----------------------------------------------------------------------------
    virtual function void write(shmins_sequence_item t);
      transaction_count++;
      last_transaction = t;
    endfunction : write

    `uvm_component_utils(shmins_mask_monitor_sink)
  endclass : shmins_mask_monitor_sink

  //----------------------------------------------------------------------------
  // @brief Verifies thread-mask diagnostics, filtering, and X/Z boundaries.
  //
  // The test directly drives the SHMINS interface without a DUT. It checks that
  // zero tmsk is reported and dropped, inactive payload X/Z is accepted, and an
  // active unknown length is diagnosed exactly once.
  //----------------------------------------------------------------------------
  class shmins_mask_monitor_test extends uvm_test;
    virtual shmins_interface vif;
    shmins_monitor monitor;
    shmins_request_coverage coverage;
    shmins_mask_monitor_sink sink;
    shm_expected_report_catcher report_catcher;

    //----------------------------------------------------------------------------
    // @brief Constructs the monitor component test.
    //
    // @param name UVM component instance name.
    // @param parent Parent component that owns this test.
    //----------------------------------------------------------------------------
    extern function new(string name = "shmins_mask_monitor_test", uvm_component parent = null);

    //----------------------------------------------------------------------------
    // @brief Creates the production monitor, coverage, and capture sink.
    //
    // @param phase UVM build phase.
    //----------------------------------------------------------------------------
    extern virtual function void build_phase(uvm_phase phase);

    //----------------------------------------------------------------------------
    // @brief Connects monitor output to coverage and the local sink.
    //
    // @param phase UVM connect phase.
    //----------------------------------------------------------------------------
    extern virtual function void connect_phase(uvm_phase phase);

    //----------------------------------------------------------------------------
    // @brief Runs the complete MON-MASK-001 through MON-MASK-010 matrix.
    //
    // @param phase UVM run phase controlling the test objection.
    //----------------------------------------------------------------------------
    extern virtual task main_phase(uvm_phase phase);

    //----------------------------------------------------------------------------
    // @brief Drives one request for exactly one sampled clock edge.
    //
    // @param tmsk Four-state thread mask placed on the interface.
    // @param payload_mode Known or targeted X/Z payload mode.
    // @param request_valid When 0, payload is driven but creq_vld remains low.
    //----------------------------------------------------------------------------
    extern protected task drive_request(logic [THD_N-1:0] tmsk,
                                         monitor_payload_mode_e payload_mode,
                                         bit request_valid = 1'b1);

    //----------------------------------------------------------------------------
    // @brief Checks the exact number of monitor-published transactions.
    //
    // @param expected_count Required cumulative transaction count.
    // @param scenario Stable scenario name used in diagnostics.
    //----------------------------------------------------------------------------
    extern protected function void check_transaction_count(int unsigned expected_count,
                                                            string scenario);

    //----------------------------------------------------------------------------
    // @brief Checks that one legal don’t-care request remains interpreted-payload known.
    //
    // @param known_before Interpreted-known count captured before the request.
    // @param x_before Interpreted-X count captured before the request.
    // @param scenario Stable scenario name used in diagnostics.
    //----------------------------------------------------------------------------
    extern protected function void check_interpreted_known_increment(
        longint unsigned known_before,
        longint unsigned x_before,
        string scenario);

    `uvm_component_utils(shmins_mask_monitor_test)
  endclass : shmins_mask_monitor_test

  function shmins_mask_monitor_test::new(string name = "shmins_mask_monitor_test",
                                         uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  function void shmins_mask_monitor_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual shmins_interface)::get(this, "", "vif", vif)) begin
      `uvm_fatal("SHMINS_MASK_MONITOR_NO_VIF", "component test requires virtual shmins_interface")
    end
    monitor = shmins_monitor::type_id::create("monitor", this);
    coverage = shmins_request_coverage::type_id::create("coverage", this);
    coverage.interpreted_payload_xz_log_enable = 1'b1;
    sink = shmins_mask_monitor_sink::type_id::create("sink", this);
    report_catcher = new("report_catcher");
    report_catcher.expect_report("SHMINS_TMSK_ZERO", 1);
    report_catcher.expect_report("SHMINS_TMSK_XZ", 1);
    report_catcher.expect_report("SHMINS_ACTIVE_PAYLOAD_XZ", 5);
    uvm_report_cb::add(null, report_catcher);
  endfunction : build_phase

  function void shmins_mask_monitor_test::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    monitor.shmins_mon_vif = vif;
    monitor.shmins_analysis_port.connect(coverage.analysis_export);
    monitor.shmins_analysis_port.connect(sink.analysis_export);
  endfunction : connect_phase

  task shmins_mask_monitor_test::main_phase(uvm_phase phase);
    longint unsigned interpreted_known_before;
    longint unsigned interpreted_x_before;
    logic [THD_N-1:0] unknown_tmsk;
    shmins_sequence_item zero_coverage_item;

    phase.raise_objection(this);
    wait (vif.rst_n === 1'b1);

    drive_request(16'h0001, MONITOR_PAYLOAD_KNOWN);
    check_transaction_count(1, "MON-MASK-001");
    if (sink.last_transaction.creq_tmsk !== 16'h0001) begin
      `uvm_fatal("SHMINS_MASK_MONITOR_SINGLE_ZERO", "thread-zero mask was not preserved")
    end

    drive_request(16'h8000, MONITOR_PAYLOAD_KNOWN);
    check_transaction_count(2, "MON-MASK-002");
    drive_request(16'h8421, MONITOR_PAYLOAD_KNOWN);
    check_transaction_count(3, "MON-MASK-003");
    drive_request(16'hffff, MONITOR_PAYLOAD_KNOWN);
    check_transaction_count(4, "MON-MASK-004");

    drive_request('0, MONITOR_PAYLOAD_KNOWN);
    check_transaction_count(4, "MON-MASK-005");
    zero_coverage_item = shmins_sequence_item::type_id::create("zero_coverage_item");
    zero_coverage_item.creq_tmsk = '0;
    zero_coverage_item.creq_info = 4'h0;
    zero_coverage_item.creq_rw = SHM_V2M;
    zero_coverage_item.creq_space = SPACE_LOC;
    coverage.write(zero_coverage_item);

    unknown_tmsk = 16'h0001;
    unknown_tmsk[1] = 1'bx;
    drive_request(unknown_tmsk, MONITOR_PAYLOAD_KNOWN);
    check_transaction_count(5, "MON-MASK-006");

    drive_request(16'h0001, MONITOR_INACTIVE_X);
    check_transaction_count(6, "MON-MASK-007");
    if (!$isunknown(sink.last_transaction.creq_len[1]) ||
        sink.last_transaction.creq_tmsk !== 16'h0001) begin
      `uvm_fatal("SHMINS_MASK_MONITOR_INACTIVE_X", "inactive X payload was not sampled intact")
    end

    drive_request(16'h0001, MONITOR_INACTIVE_Z);
    check_transaction_count(7, "MON-MASK-008");
    if (sink.last_transaction.creq_len[1][0] !== 1'bz) begin
      `uvm_fatal("SHMINS_MASK_MONITOR_INACTIVE_Z", "inactive Z payload was not sampled intact")
    end

    drive_request(16'h0001, MONITOR_ACTIVE_LENGTH_X);
    check_transaction_count(8, "MON-MASK-009");

    interpreted_known_before = coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_KNOWN];
    interpreted_x_before = coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_X];
    drive_request(16'h0001, MONITOR_MASKED_DATA_X);
    check_transaction_count(9, "X-MON-002");
    check_interpreted_known_increment(interpreted_known_before, interpreted_x_before, "X-MON-002");

    interpreted_known_before = coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_KNOWN];
    interpreted_x_before = coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_X];
    drive_request(16'h0001, MONITOR_MASKED_INDEXED_OFFSET_X);
    check_transaction_count(10, "X-MON-003");
    check_interpreted_known_increment(interpreted_known_before, interpreted_x_before, "X-MON-003");

    drive_request(16'h0001, MONITOR_ACTIVE_MASK_X);
    check_transaction_count(11, "X-MON-004");
    drive_request(16'h0001, MONITOR_SHARED_OFFSET_X);
    check_transaction_count(12, "X-MON-005");
    drive_request(16'h0001, MONITOR_ACTIVE_INDEXED_OFFSET_X);
    check_transaction_count(13, "X-MON-006");
    drive_request(16'h0001, MONITOR_ACTIVE_DATA_X);
    check_transaction_count(14, "X-MON-007");

    interpreted_known_before = coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_KNOWN];
    interpreted_x_before = coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_X];
    drive_request(16'h0001, MONITOR_M2V_DATA_X);
    check_transaction_count(15, "X-MON-008");
    check_interpreted_known_increment(interpreted_known_before, interpreted_x_before, "X-MON-008");

    interpreted_known_before = coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_KNOWN];
    interpreted_x_before = coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_X];
    drive_request(16'h0001, MONITOR_OUT_OF_LENGTH_X);
    check_transaction_count(16, "X-MON-OUT-OF-LENGTH");
    check_interpreted_known_increment(interpreted_known_before, interpreted_x_before,
                                      "X-MON-OUT-OF-LENGTH");

    drive_request('x, MONITOR_ALL_X, 1'b0);
    check_transaction_count(16, "MON-MASK-010");

    if (!report_catcher.expectations_met()) begin
      `uvm_fatal("SHMINS_MASK_MONITOR_REPORT_COUNT", "expected report IDs did not occur exactly once")
    end
    if (coverage.sampled_mask_class_count[SHMINS_MASK_ZERO] == 0 ||
        coverage.sampled_mask_class_count[SHMINS_MASK_UNKNOWN] == 0 ||
        coverage.sampled_mask_class_count[SHMINS_MASK_SINGLE] == 0 ||
        coverage.sampled_mask_class_count[SHMINS_MASK_SPARSE] == 0 ||
        coverage.sampled_mask_class_count[SHMINS_MASK_FULL] == 0 ||
        coverage.sampled_inactive_payload_xz_count[SHMINS_PAYLOAD_X] == 0 ||
        coverage.sampled_inactive_payload_xz_count[SHMINS_PAYLOAD_Z] == 0 ||
        coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_X] == 0 ||
        coverage.sampled_masked_data_xz_count[SHMINS_PAYLOAD_X] == 0 ||
        coverage.sampled_masked_indexed_offset_xz_count[SHMINS_PAYLOAD_X] == 0 ||
        coverage.sampled_out_of_length_xz_count[SHMINS_PAYLOAD_X] == 0 ||
        coverage.sampled_m2v_unused_vdata_xz_count[SHMINS_PAYLOAD_X] == 0) begin
      `uvm_fatal("SHMINS_MASK_MONITOR_COVERAGE", "component matrix did not reach all required counters")
    end
    if (coverage.interpreted_payload_xz_log_count != 5) begin
      `uvm_fatal("SHMINS_MASK_MONITOR_XZ_LOG_COUNT",
                 $sformatf("expected five interpreted-payload diagnostics, observed %0d",
                           coverage.interpreted_payload_xz_log_count))
    end

    `uvm_info("SHMINS_MASK_MONITOR_TEST", "thread-mask monitor component matrix: PASS", UVM_LOW)
    uvm_report_cb::delete(null, report_catcher);
    phase.drop_objection(this);
  endtask : main_phase

  task shmins_mask_monitor_test::drive_request(logic [THD_N-1:0] tmsk,
                                                monitor_payload_mode_e payload_mode,
                                                bit request_valid = 1'b1);
    @(negedge vif.clk);
    vif.creq_vld = request_valid;
    vif.creq_id = 8'h5a;
    vif.creq_wpid = '0;
    vif.creq_wpnum = 1;
    vif.creq_typ = {4'h0, SPACE_LOC, 4'h0, 1'b0, LDST_S, GAUTO_1B, ATYP_U, ATYP_32,
                    DTYP_8, SHM_V2M};
    vif.creq_vaddr = '0;
    vif.creq_tmsk = tmsk;
    vif.creq_base = '0;
    for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
      vif.creq_prio[thread_idx] = '0;
      vif.creq_len[thread_idx] = 1;
      vif.creq_vmsk[thread_idx] = VEC_BYTE_N'(1);
      vif.creq_offs[thread_idx] = '0;
      vif.creq_vdat[thread_idx] = '0;
      vif.creq_vdat[thread_idx][0] = byte'(8'h40 + thread_idx);
    end

    if (payload_mode inside {MONITOR_INACTIVE_X, MONITOR_INACTIVE_Z}) begin
      for (int unsigned thread_idx = 1; thread_idx < THD_N; thread_idx++) begin
        if (payload_mode == MONITOR_INACTIVE_X) begin
          vif.creq_prio[thread_idx] = 'x;
          vif.creq_len[thread_idx] = 'x;
          vif.creq_vmsk[thread_idx] = 'x;
          vif.creq_offs[thread_idx] = 'x;
          vif.creq_vdat[thread_idx] = 'x;
        end
        else begin
          vif.creq_prio[thread_idx] = 'z;
          vif.creq_len[thread_idx] = 'z;
          vif.creq_vmsk[thread_idx] = 'z;
          vif.creq_offs[thread_idx] = 'z;
          vif.creq_vdat[thread_idx] = 'z;
        end
      end
    end
    else if (payload_mode == MONITOR_ACTIVE_LENGTH_X) begin
      vif.creq_len[0] = 'x;
    end
    else if (payload_mode == MONITOR_MASKED_DATA_X) begin
      vif.creq_len[0] = 8;
      vif.creq_vmsk[0][7:0] = 8'h81;
      vif.creq_vdat[0][1] = 'x;
    end
    else if (payload_mode == MONITOR_MASKED_INDEXED_OFFSET_X) begin
      vif.creq_typ = {4'h0, SPACE_LOC, 4'h0, 1'b0, LDSTE_V, GAUTO_1B, ATYP_U, ATYP_32,
                      DTYP_8, SHM_V2M};
      vif.creq_len[0] = 8;
      vif.creq_vmsk[0][7:0] = 8'h81;
      vif.creq_offs[0][63:32] = 'x;
    end
    else if (payload_mode == MONITOR_ACTIVE_MASK_X) begin
      vif.creq_len[0] = 8;
      vif.creq_vmsk[0][1] = 1'bx;
    end
    else if (payload_mode == MONITOR_SHARED_OFFSET_X) begin
      vif.creq_offs[0][31:0] = 'x;
    end
    else if (payload_mode == MONITOR_ACTIVE_INDEXED_OFFSET_X) begin
      vif.creq_typ = {4'h0, SPACE_LOC, 4'h0, 1'b0, LDSTE_V, GAUTO_1B, ATYP_U, ATYP_32,
                      DTYP_8, SHM_V2M};
      vif.creq_len[0] = 8;
      vif.creq_vmsk[0][7:0] = 8'h81;
      vif.creq_offs[0][255:224] = 'x;
    end
    else if (payload_mode == MONITOR_ACTIVE_DATA_X) begin
      vif.creq_vdat[0][0] = 'x;
    end
    else if (payload_mode == MONITOR_M2V_DATA_X) begin
      vif.creq_typ = {4'h0, SPACE_LOC, 4'h0, 1'b0, LDST_S, GAUTO_1B, ATYP_U, ATYP_32,
                      DTYP_8, SHM_M2V};
      vif.creq_vdat[0] = 'x;
    end
    else if (payload_mode == MONITOR_OUT_OF_LENGTH_X) begin
      vif.creq_typ = {4'h0, SPACE_LOC, 4'h0, 1'b0, LDST_S, GAUTO_1B, ATYP_U, ATYP_16,
                      DTYP_8, SHM_V2M};
      vif.creq_len[0] = 8;
      vif.creq_vmsk[0][VEC_BYTE_N-1:8] = 'x;
      vif.creq_vdat[0][VEC_BYTE_N-1:8] = 'x;
      vif.creq_offs[0][VEC_W-1:16] = 'x;
    end
    else if (payload_mode == MONITOR_ALL_X) begin
      vif.creq_id = 'x;
      vif.creq_wpid = 'x;
      vif.creq_wpnum = 'x;
      vif.creq_typ = 'x;
      vif.creq_vaddr = 'x;
      vif.creq_base = 'x;
      vif.creq_prio = 'x;
      vif.creq_len = 'x;
      vif.creq_vmsk = 'x;
      vif.creq_offs = 'x;
      vif.creq_vdat = 'x;
    end

    @(negedge vif.clk);
    vif.creq_vld = 1'b0;
    repeat (2) @(posedge vif.clk);
  endtask : drive_request

  function void shmins_mask_monitor_test::check_transaction_count(int unsigned expected_count,
                                                                   string scenario);
    if (sink.transaction_count != expected_count) begin
      `uvm_fatal("SHMINS_MASK_MONITOR_COUNT",
                 $sformatf("%s expected %0d published requests, observed %0d",
                           scenario, expected_count, sink.transaction_count))
    end
  endfunction : check_transaction_count

  function void shmins_mask_monitor_test::check_interpreted_known_increment(
      longint unsigned known_before,
      longint unsigned x_before,
      string scenario);
    if (coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_KNOWN] != known_before + 1 ||
        coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_X] != x_before) begin
      `uvm_fatal("SHMINS_MASK_MONITOR_INTERPRETED_CLASS",
                 $sformatf({"%s expected interpreted-known increment without interpreted-X: ",
                            "known=%0d->%0d x=%0d->%0d"},
                           scenario, known_before,
                           coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_KNOWN],
                           x_before, coverage.sampled_active_payload_xz_count[SHMINS_PAYLOAD_X]))
    end
  endfunction : check_interpreted_known_increment
endpackage : shmins_mask_monitor_test_pkg

//------------------------------------------------------------------------------
// @brief Provides a clocked empty-design top for the SHMINS monitor test.
//------------------------------------------------------------------------------
module shmins_mask_monitor_tb;
  import uvm_pkg::*;
  import shmins_mask_monitor_test_pkg::*;

  logic clk;
  logic rst_n;
  clk_if clk_vif(clk);
  shmins_interface shmins_vif(clk, rst_n);

  initial begin
    clk = 1'b0;
    forever #5ns clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    shmins_vif.creq_vld = 1'b0;
    shmins_vif.creq_rls = 1'b0;
    shmins_vif.vack_done = 1'b0;
    shmins_vif.vack_id = '0;
    shmins_vif.mack_done = 1'b0;
    shmins_vif.mack_id = '0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual clk_if)::set(null, "uvm_test_top.monitor", "clk_vif", clk_vif);
    uvm_config_db#(virtual shmins_interface)::set(null, "uvm_test_top", "vif", shmins_vif);
    run_test("shmins_mask_monitor_test");
  end
endmodule : shmins_mask_monitor_tb
