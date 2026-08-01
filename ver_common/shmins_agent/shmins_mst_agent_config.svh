`ifndef INC_SHMINS_MST_AGENT_CONFIG_SVH
`define INC_SHMINS_MST_AGENT_CONFIG_SVH

//-----------------------------------------------------------------------------
// Class: shmins_mst_agent_config
//-----------------------------------------------------------------------------
class shmins_mst_agent_config extends uvm_object;

    // Data Members
    //---------------------------------------------------------------------
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    // Agent Interface Instantiation
    //---------------------------------------------------------------------

    // Agent Monitor Knobs
    //---------------------------------------------------------------------
    uvm_active_passive_enum shmins_mon_is_active = UVM_ACTIVE;

    // Agent Driver Knobs
    //---------------------------------------------------------------------
    uvm_active_passive_enum shmins_mst_is_active = UVM_ACTIVE;

    // Constraints
    //---------------------------------------------------------------------

    // Methods
    //---------------------------------------------------------------------

    // Standard UVM Methods
    //---------------------------------------------------------------------
    extern function        new(string name="shmins_mst_agent_config");

    // User Defined APIs
    //---------------------------------------------------------------------
        `uvm_object_utils_begin(shmins_mst_agent_config)
    // Add field configurations
    //---------------------------------------------------------------------
    //`uvm_field_int(wait_shmins_ack_enable  , UVM_DEFAULT)
    `uvm_object_utils_end
endclass: shmins_mst_agent_config

//-----------------------------------------------------------------------------
// Function: new
//-----------------------------------------------------------------------------
function shmins_mst_agent_config::new(string name="shmins_mst_agent_config");
    super.new(name);

    //---------------------------------------------------------------------
    // Get configuration
    //---------------------------------------------------------------------

    //---------------------------------------------------------------------
    // Construct children
    //---------------------------------------------------------------------

    //---------------------------------------------------------------------
    // Configure children
    //---------------------------------------------------------------------

endfunction: new

`endif //INC_SHMINS_MST_AGENT_CONFIG_SVH
