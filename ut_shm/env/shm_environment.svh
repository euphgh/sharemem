`ifndef INC_SHM_ENVIRONMENT_SVH
`define INC_SHM_ENVIRONMENT_SVH

//------------------------------------------------------------------------------
// @brief Connects SHM stimulus, reservation, reference, and lifecycle checking.
//
// The environment exposes clock-based idle and drain APIs to tests. It does not
// define testcase stimulus domains or impose a DUT protocol completion bound.
//------------------------------------------------------------------------------
class shm_environment extends uvm_env;

    shm_reference  shm_ref;
    shm_address_coverage address_coverage;
    shm_scoreboard shm_scb;
    shm_transaction_lifecycle_checker lifecycle_checker;

    shmins_mst_agent       shmins_mst_agt;
    vlm_agent              vlm_agt;

    shm_environment_config shm_environment_cfg;

    virtual shmins_interface          shmins_vif;
    virtual vlm_interface             vlm_vif;
    virtual clk_if                    clk_vif;

    int unsigned shm_env_id;

    extern function new(string name = "shm_environment", uvm_component parent = null);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);

    //-------------------------------------------------------------------------
    // @brief Returns whether transaction data, ack, and reservation state is idle.
    //
    // @return 1 when the scoreboard, lifecycle checker, and reservation window
    //         contain no pending DUT transaction state.
    //-------------------------------------------------------------------------
    extern function bit is_idle();

    //-------------------------------------------------------------------------
    // @brief Waits for environment transaction state to drain after stimulus.
    //
    // Uses TEST_DRAIN_TIMEOUT_CYCLES as a testbench watchdog. The value is not
    // a DUT protocol latency requirement.
    //-------------------------------------------------------------------------
    extern task wait_for_idle();

    //-------------------------------------------------------------------------
    // @brief Formats pending component state when drain does not converge.
    //
    // @return Multi-line scoreboard and lifecycle diagnostic state.
    //-------------------------------------------------------------------------
    extern function string pending_state_sprint();

    `uvm_component_utils_begin(shm_environment)
        `uvm_field_int(shm_env_id, UVM_ALL_ON)
    `uvm_component_utils_end

endclass : shm_environment

function shm_environment::new(string name = "shm_environment", uvm_component parent = null);
    super.new(name, parent);
endfunction : new

function void shm_environment::build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(shm_environment_config)::get(
            this, "", "shm_environment_config", shm_environment_cfg) ||
        shm_environment_cfg == null) begin
        `uvm_fatal("SHM_ENV_NO_CFG", "shm_environment requires 'shm_environment_config'")
    end

    if (shm_environment_cfg.shmins_mst_agent_cfg == null ||
        shm_environment_cfg.vlm_reservation_agent_cfg == null) begin
        `uvm_fatal("SHM_ENV_CFG_NOT_INITIALIZED",
                   "shm_environment_config.init() must create both agent configs")
    end

    if (!uvm_config_db#(virtual shmins_interface)::get(
            this, "", "shmins_vif", shmins_vif)) begin
        `uvm_fatal("SHM_ENV_NO_SHMINS_VIF", "shm_environment requires virtual interface 'shmins_vif'")
    end

    if (!uvm_config_db#(virtual vlm_interface)::get(this, "", "vlm_vif", vlm_vif)) begin
        `uvm_fatal("SHM_ENV_NO_VLM_VIF", "shm_environment requires virtual interface 'vlm_vif'")
    end

    if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
        `uvm_fatal("SHM_ENV_NO_CLK_VIF", "shm_environment requires virtual interface 'clk_vif'")
    end

    shm_environment_cfg.vlm_reservation_agent_cfg.vif = vlm_vif;

    uvm_config_db#(shmins_mst_agent_config)::set(
        this, "shmins_mst_agt", "cfg", shm_environment_cfg.shmins_mst_agent_cfg);
    uvm_config_db#(virtual shmins_interface)::set(
        this, "shmins_mst_agt", "shmins_vif", shmins_vif);

    uvm_config_db#(vlm_reservation_agent_config)::set(
        this, "vlm_agt", "cfg", shm_environment_cfg.vlm_reservation_agent_cfg);
    uvm_config_db#(virtual clk_if)::set(
        this, "vlm_agt.*", "clk_vif", clk_vif);

    shmins_mst_agt = shmins_mst_agent::type_id::create("shmins_mst_agt", this);
    vlm_agt = vlm_agent::type_id::create("vlm_agt", this);

    if (shm_environment_cfg.shm_is_active == UVM_ACTIVE) begin
        uvm_config_db#(shm_environment_config)::set(
            this, "shm_ref", "shm_environment_config", shm_environment_cfg);
        uvm_config_db#(shm_environment_config)::set(
            this, "shm_scb", "shm_environment_config", shm_environment_cfg);
        uvm_config_db#(shm_environment_config)::set(
            this, "lifecycle_checker", "shm_environment_config", shm_environment_cfg);

        shm_ref = shm_reference::type_id::create("shm_ref", this);
        address_coverage = shm_address_coverage::type_id::create("address_coverage", this);
        shm_scb = shm_scoreboard::type_id::create("shm_scb", this);
        lifecycle_checker =
            shm_transaction_lifecycle_checker::type_id::create("lifecycle_checker", this);
    end
endfunction : build_phase

function void shm_environment::connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (shm_ref != null && shmins_mst_agt.monitor != null) begin
        shmins_mst_agt.monitor.shmins_analysis_port.connect(shm_ref.shmins_analysis_export);
    end

    if (lifecycle_checker != null && shmins_mst_agt.monitor != null) begin
        shmins_mst_agt.monitor.shmins_analysis_port.connect(lifecycle_checker.accept_imp);
        shmins_mst_agt.monitor.ack_analysis_port.connect(lifecycle_checker.ack_imp);
    end

    if (shm_scb != null && vlm_agt != null) begin
        vlm_agt.write_analysis_port.connect(shm_scb.rtl_wrvlm_analysis_export);
    end

    if (shm_scb != null && vlm_agt != null) begin
        vlm_agt.mem_port.connect(shm_scb.mem_imp);
    end

    if (shm_ref != null && shm_scb != null) begin
        shm_ref.wdata_ass_arr_port.connect(shm_scb.ref_wrvlm_analysis_export);
    end

    if (shm_ref != null && address_coverage != null) begin
        shm_ref.wdata_ass_arr_port.connect(address_coverage.analysis_export);
    end

    if (shm_scb != null && lifecycle_checker != null) begin
        shm_scb.completion_analysis_port.connect(lifecycle_checker.completion_imp);
    end
endfunction : connect_phase

function bit shm_environment::is_idle();
    if (shm_scb != null && !shm_scb.is_idle()) begin
        return 1'b0;
    end
    if (lifecycle_checker != null && !lifecycle_checker.is_idle()) begin
        return 1'b0;
    end
    if (vlm_agt != null && vlm_agt.scheduler != null && !vlm_agt.scheduler.is_idle()) begin
        return 1'b0;
    end
    return 1'b1;
endfunction : is_idle

task shm_environment::wait_for_idle();
    int unsigned stable_idle_cycles = 0;

    for (int unsigned elapsed_cycles = 0;
         elapsed_cycles < shm_environment_cfg.test_drain_timeout_cycles;
         elapsed_cycles++) begin
        clk_vif.wait_cycles(1);
        if (is_idle()) begin
            stable_idle_cycles++;
            if (stable_idle_cycles >= 2) begin
                return;
            end
        end
        else begin
            stable_idle_cycles = 0;
        end
    end

    `uvm_error("SHM_ENV_DRAIN_TIMEOUT",
               $sformatf("environment did not drain within %0d cycles:\n%s",
                         shm_environment_cfg.test_drain_timeout_cycles,
                         pending_state_sprint()))
endtask : wait_for_idle

function string shm_environment::pending_state_sprint();
    string result = "";
    if (shm_scb != null) begin
        result = {result, shm_scb.pending_state_sprint(), "\n"};
    end
    if (lifecycle_checker != null) begin
        result = {result, lifecycle_checker.pending_state_sprint(), "\n"};
    end
    if (vlm_agt != null && vlm_agt.scheduler != null) begin
        result = {result, $sformatf("reservation scheduler idle=%0d\n", vlm_agt.scheduler.is_idle())};
    end
    return result;
endfunction : pending_state_sprint

`endif // INC_SHM_ENVIRONMENT_SVH
