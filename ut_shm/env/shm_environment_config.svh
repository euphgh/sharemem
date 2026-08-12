`ifndef INC_SHM_ENVIRONMENT_CONFIG_SVH
`define INC_SHM_ENVIRONMENT_CONFIG_SVH

//-----------------------------------------------------------------------------
// Class: shm_environment_config
//-----------------------------------------------------------------------------
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

`endif // INC_SHM_ENVIRONMENT_CONFIG_SVH
