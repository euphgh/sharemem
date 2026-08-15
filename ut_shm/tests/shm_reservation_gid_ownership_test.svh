`ifndef INC_SHM_RESERVATION_GID_OWNERSHIP_TEST_SVH
`define INC_SHM_RESERVATION_GID_OWNERSHIP_TEST_SVH

//------------------------------------------------------------------------------
// @brief Verifies target-gid blocking and other-gid external-busy admission.
//------------------------------------------------------------------------------
class shm_reservation_gid_ownership_test extends shm_directed_base_test;
  localparam longint unsigned EXTERNAL_BUSY_FIRST_CYCLE = 1;
  localparam longint unsigned EXTERNAL_BUSY_LAST_CYCLE = 200;

  vlm_reservation_directed_busy_policy external_busy_policy;

  //----------------------------------------------------------------------------
  // @brief Constructs the reservation gid-ownership test.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this test.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_reservation_gid_ownership_test", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Installs deterministic gid-zero write busy before the agent builds.
  //
  // @param phase UVM build phase.
  //----------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //----------------------------------------------------------------------------
  // @brief Sends gid-one and gid-zero writes while gid zero is externally busy.
  //
  // @param phase UVM main phase controlling the test objection.
  //----------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  `uvm_component_utils(shm_reservation_gid_ownership_test)
endclass : shm_reservation_gid_ownership_test

function shm_reservation_gid_ownership_test::new(
    string name = "shm_reservation_gid_ownership_test",
    uvm_component parent = null);
  super.new(name, parent);
endfunction : new

function void shm_reservation_gid_ownership_test::build_phase(uvm_phase phase);
  super.build_phase(phase);

  external_busy_policy = vlm_reservation_directed_busy_policy::type_id::create("external_busy_policy");
  for (int unsigned delay = 0; delay < VTAB_D; delay++) begin
    for (int unsigned sub_bank = 0; sub_bank < VLM_SUB_BANK_N; sub_bank++) begin
      external_busy_policy.add_busy_range(EXTERNAL_BUSY_FIRST_CYCLE, EXTERNAL_BUSY_LAST_CYCLE,
                                          VLM_RESERVATION_WRITE, delay, 0, sub_bank);
    end
  end
  shm_environment_cfg.vlm_reservation_agent_cfg.external_busy_policy = external_busy_policy;
endfunction : build_phase

task shm_reservation_gid_ownership_test::main_phase(uvm_phase phase);
  shmins_contiguous_sequence_item high_gid_item;
  shmins_contiguous_sequence_item low_gid_item;
  longint unsigned maddr;

  phase.raise_objection(this);
  wait (shm_env.shmins_vif.rst_n === 1'b1);
  shm_env.clk_vif.wait_cycles(3);
  if (shm_env.clk_vif.cycle_count + 32 >= EXTERNAL_BUSY_LAST_CYCLE) begin
    `uvm_fatal("SHM_RESERVATION_OWNERSHIP_SETUP",
               $sformatf("stimulus started too late at cycle %0d", shm_env.clk_vif.cycle_count))
  end

  maddr = encode_directed_maddr(SPACE_LOC, 0, 0, 0, 32'h140, 1);
  high_gid_item = build_single_byte_item("other_gid_external_allowed", SHM_V2M, SPACE_LOC, 4, 1, 0, 0,
                                         maddr, -1, 8'h4e);
  low_gid_item = build_single_byte_item("target_gid_external_blocked", SHM_V2M, SPACE_LOC, 0, 1, 0, 0,
                                        maddr, -1, 8'h0b);
  check_single_byte_mapping(high_gid_item, 0, 0, 4, 32'h140);
  check_single_byte_mapping(low_gid_item, 0, 0, 0, 32'h140);

  send_directed_item(high_gid_item);
  send_directed_item(low_gid_item);
  shm_env.clk_vif.wait_cycles(16);
  if (shm_env.clk_vif.cycle_count < EXTERNAL_BUSY_LAST_CYCLE && shm_env.is_idle()) begin
    `uvm_fatal("SHM_RESERVATION_TARGET_NOT_HELD",
               "gid-zero transaction retired while every target write slot was externally busy")
  end

  shm_env.wait_for_idle();
  if (shm_env.vlm_agt.scheduler.external_busy_policy != external_busy_policy ||
      shm_env.vlm_agt.scheduler.generated_external_slot_count == 0) begin
    `uvm_fatal("SHM_RESERVATION_POLICY_UNUSED", "directed external-busy policy was not active")
  end
  if (shm_env.vlm_agt.coverage.accepted_with_other_gid_external_count == 0) begin
    `uvm_fatal("SHM_RESERVATION_OTHER_GID_NOT_COVERED",
               "no gid-one reservation was accepted while gid zero had external ownership")
  end

  `uvm_info("SHM_RESERVATION_GID_OWNERSHIP_TEST", "reservation gid-ownership scenarios completed", UVM_LOW)
  phase.drop_objection(this);
endtask : main_phase

`endif // INC_SHM_RESERVATION_GID_OWNERSHIP_TEST_SVH
