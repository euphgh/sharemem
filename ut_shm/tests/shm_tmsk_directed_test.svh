`ifndef INC_SHM_TMSK_DIRECTED_TEST_SVH
`define INC_SHM_TMSK_DIRECTED_TEST_SVH

//------------------------------------------------------------------------------
// @brief Verifies legal thread masks across both directions and all spaces.
//
// Each matrix cell sends one byte per active thread while retaining legal,
// byte-unique payload and addresses for inactive threads. Existing reservation,
// scoreboard, and lifecycle checks detect any DUT access outside the active set.
//------------------------------------------------------------------------------
class shm_tmsk_directed_test extends shm_directed_base_test;

  //----------------------------------------------------------------------------
  // @brief Constructs the thread-mask directed test.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this test.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_tmsk_directed_test", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Runs the complete 2-direction by 3-space by 4-mask matrix.
  //
  // @param phase UVM main phase controlling the test objection.
  //----------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  //----------------------------------------------------------------------------
  // @brief Sends and checks one isolated normal-request matrix cell.
  //
  // @param direction V2M or M2V direction.
  // @param space LOC, WRP, or BLK address space.
  // @param target_tmsk One of the directed legal thread masks.
  // @param mask_name Stable M0, M15, MS, or MF label.
  //----------------------------------------------------------------------------
  extern protected task run_mask_cell(creq_rw_e direction,
                                      creq_space_e space,
                                      logic [THD_N-1:0] target_tmsk,
                                      string mask_name);

  //----------------------------------------------------------------------------
  // @brief Returns the coverage mask class for one legal directed mask.
  //
  // @param target_tmsk Known non-zero mask used by the current cell.
  // @return Single, sparse, or full mask class.
  //----------------------------------------------------------------------------
  extern protected function shmins_mask_class_e expected_mask_class(logic [THD_N-1:0] target_tmsk);

  `uvm_component_utils(shm_tmsk_directed_test)
endclass : shm_tmsk_directed_test

function shm_tmsk_directed_test::new(string name = "shm_tmsk_directed_test",
                                     uvm_component parent = null);
  super.new(name, parent);
endfunction : new

task shm_tmsk_directed_test::main_phase(uvm_phase phase);
  creq_rw_e directions[2] = '{SHM_V2M, SHM_M2V};
  creq_space_e spaces[3] = '{SPACE_LOC, SPACE_WRP, SPACE_BLK};
  logic [THD_N-1:0] masks[4] = '{16'h0001, 16'h8000, 16'h8421, 16'hffff};
  string mask_names[4] = '{"m0", "m15", "ms", "mf"};

  phase.raise_objection(this);
  if (shm_env.shmins_mst_agt.coverage == null || shm_env.address_coverage == null) begin
    `uvm_fatal("SHM_TMSK_COVERAGE_MISSING", "thread-mask test requires request and address coverage")
  end

  foreach (directions[direction_idx]) begin
    foreach (spaces[space_idx]) begin
      foreach (masks[mask_idx]) begin
        run_mask_cell(directions[direction_idx], spaces[space_idx], masks[mask_idx], mask_names[mask_idx]);
      end
    end
  end

  `uvm_info("SHM_TMSK_DIRECTED_TEST", "24-cell legal thread-mask matrix completed", UVM_LOW)
  phase.drop_objection(this);
endtask : main_phase

task shm_tmsk_directed_test::run_mask_cell(creq_rw_e direction,
                                            creq_space_e space,
                                            logic [THD_N-1:0] target_tmsk,
                                            string mask_name);
  shmins_contiguous_sequence_item item;
  shmins_mask_class_e mask_class;
  longint unsigned request_count_before;
  longint unsigned address_byte_count_before;
  longint unsigned cross_count_before;
  longint unsigned thread_count_before[THD_N];
  string item_name;

  item_name = $sformatf("%s_%s_%s", direction == SHM_V2M ? "v2m" : "m2v",
                        creq_space_e_to_str(space).tolower(), mask_name);
  item = build_masked_byte_item(item_name, direction, space, target_tmsk);
  mask_class = expected_mask_class(target_tmsk);
  request_count_before = shm_env.shmins_mst_agt.coverage.sampled_request_count;
  address_byte_count_before = shm_env.address_coverage.sampled_active_byte_count;
  cross_count_before = shm_env.shmins_mst_agt.coverage.normal_cross_count(direction, space, mask_class);
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    thread_count_before[thread_idx] =
        shm_env.shmins_mst_agt.coverage.sampled_active_thread_count[thread_idx][direction];
  end

  send_directed_item(item);
  shm_env.wait_for_idle();

  if (shm_env.shmins_mst_agt.coverage.sampled_request_count != request_count_before + 1 ||
      shm_env.shmins_mst_agt.coverage.normal_cross_count(direction, space, mask_class) !=
          cross_count_before + 1) begin
    `uvm_fatal("SHM_TMSK_REQUEST_COVERAGE",
               $sformatf("%s did not increment its request coverage cell exactly once", item_name))
  end
  if (shm_env.address_coverage.sampled_active_byte_count !=
      address_byte_count_before + $countones(target_tmsk)) begin
    `uvm_fatal("SHM_TMSK_REFERENCE_BYTE_COUNT",
               $sformatf("%s expected %0d active reference bytes", item_name, $countones(target_tmsk)))
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    longint unsigned expected_count = thread_count_before[thread_idx] + target_tmsk[thread_idx];
    if (shm_env.shmins_mst_agt.coverage.sampled_active_thread_count[thread_idx][direction] !=
        expected_count) begin
      `uvm_fatal("SHM_TMSK_ACTIVE_THREAD_COUNT",
                 $sformatf("%s thread %0d active coverage count changed unexpectedly",
                           item_name, thread_idx))
    end
  end
  `uvm_info("SHM_TMSK_MATRIX_CELL", $sformatf("%s: PASS", item_name), UVM_LOW)
endtask : run_mask_cell

function shmins_mask_class_e shm_tmsk_directed_test::expected_mask_class(
    logic [THD_N-1:0] target_tmsk);
  int unsigned population = $countones(target_tmsk);
  if (population == 1) return SHMINS_MASK_SINGLE;
  if (population == THD_N) return SHMINS_MASK_FULL;
  return SHMINS_MASK_SPARSE;
endfunction : expected_mask_class

`endif // INC_SHM_TMSK_DIRECTED_TEST_SVH
