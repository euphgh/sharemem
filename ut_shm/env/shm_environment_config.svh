`ifndef INC_SHM_ENVIRONMENT_CONFIG_SVH
`define INC_SHM_ENVIRONMENT_CONFIG_SVH

//------------------------------------------------------------------------------
// @brief Configures SHM agents and cycle-based environment diagnostics.
//
// Tests own this object and may override lifecycle, scoreboard, and drain
// thresholds with plusargs. Zero diagnostic timeouts disable intermediate
// reports without disabling final consistency checks.
//------------------------------------------------------------------------------
class shm_environment_config extends uvm_object;

    // Environment Data Members
    //---------------------------------------------------------------------
    string env_inst_name;
    uvm_active_passive_enum env_is_active = UVM_ACTIVE;

    // Environment Interface Instantiation
    //---------------------------------------------------------------------

    // Environment Monitor Knobs
    //---------------------------------------------------------------------

    // Environment Scoreboard Knobs
    //---------------------------------------------------------------------
    rand uvm_active_passive_enum shm_is_active = UVM_ACTIVE;

    // Scoreboard diagnostics measured in shared clock cycles; zero disables
    // the corresponding timeout while retaining end-of-test consistency checks.
    int unsigned scb_no_progress_timeout_cycles = 0;
    int unsigned scb_record_age_timeout_cycles = 0;
    int unsigned scb_timeout_scan_interval_cycles = 10;

    // Diagnostic grace after all bytes of one transaction are observed.
    // Zero disables the intermediate deadline; end-of-test ack checking remains.
    int unsigned ack_post_complete_grace_cycles = 20;

    // Case-level drain watchdog used after the stimulus sequence completes.
    int unsigned test_drain_timeout_cycles = 10000;

    // Environment Agent Variables
    //---------------------------------------------------------------------
    string agent_inst_name;

    // Environment Agent Config Instantiation
    //---------------------------------------------------------------------
    shmins_mst_agent_config shmins_mst_agent_cfg;
    vlm_reservation_agent_config vlm_reservation_agent_cfg;

    extern function new(string name = "shm_environment_config");

    // User Defined APIs
    //---------------------------------------------------------------------
    extern function void init();

    //-------------------------------------------------------------------------
    // @brief Applies case-specific lifecycle and scoreboard plusargs.
    //
    // Missing plusargs preserve the defaults above. A zero timeout disables
    // that intermediate diagnostic without disabling final consistency checks.
    //-------------------------------------------------------------------------
    extern function void plusargs_override_config();

    //-------------------------------------------------------------------------
    // @brief Validates cycle-based diagnostic configuration.
    //-------------------------------------------------------------------------
    extern function void validate();

    // UVM Factory Registration
    //---------------------------------------------------------------------
    `uvm_object_utils_begin(shm_environment_config)
    // Add field configurations

    `uvm_object_utils_end
endclass: shm_environment_config

function shm_environment_config::new(string name = "shm_environment_config");
    super.new(name);
endfunction: new

function void shm_environment_config::init();
    shmins_mst_agent_cfg = shmins_mst_agent_config::type_id::create("shmins_mst_agent_cfg");
    vlm_reservation_agent_cfg =
        vlm_reservation_agent_config::type_id::create("vlm_reservation_agent_cfg");
    
    shmins_mst_agent_cfg.is_active             = env_is_active;
    shmins_mst_agent_cfg.shmins_mst_is_active  = env_is_active;
endfunction: init

function void shm_environment_config::plusargs_override_config();
    void'($value$plusargs("SCB_NO_PROGRESS_TIMEOUT_CYCLES=%d", scb_no_progress_timeout_cycles));
    void'($value$plusargs("SCB_RECORD_AGE_TIMEOUT_CYCLES=%d", scb_record_age_timeout_cycles));
    void'($value$plusargs("SCB_TIMEOUT_SCAN_INTERVAL_CYCLES=%d", scb_timeout_scan_interval_cycles));
    void'($value$plusargs("ACK_POST_COMPLETE_GRACE_CYCLES=%d", ack_post_complete_grace_cycles));
    void'($value$plusargs("TEST_DRAIN_TIMEOUT_CYCLES=%d", test_drain_timeout_cycles));
    validate();
endfunction : plusargs_override_config

function void shm_environment_config::validate();
    if (scb_timeout_scan_interval_cycles == 0) begin
        `uvm_fatal("SHM_ENV_SCB_SCAN_INTERVAL", "SCB_TIMEOUT_SCAN_INTERVAL_CYCLES must be greater than zero")
    end
    if (test_drain_timeout_cycles == 0) begin
        `uvm_fatal("SHM_ENV_DRAIN_TIMEOUT", "TEST_DRAIN_TIMEOUT_CYCLES must be greater than zero")
    end
endfunction : validate

`endif // INC_SHM_ENVIRONMENT_CONFIG_SVH
