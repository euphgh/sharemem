`ifndef INC_SHMINS_MST_AGENT_SVH
`define INC_SHMINS_MST_AGENT_SVH

//-----------------------------------------------------------------------------
// Class: shmins_mst_agent
//-----------------------------------------------------------------------------
class shmins_mst_agent extends uvm_agent;


    virtual shmins_interface shmins_mst_vif;

    shmins_mst_agent_config shmins_mst_agent_cfg;

    shmins_mst_sequencer   shmins_mst_sqr;
    shmins_mst_driver      shmins_mst_drv;
    shmins_monitor         shmins_mon;

    extern function        new(string name= "shmins_mst_agent", uvm_component parent);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);

    `uvm_component_utils_begin(shmins_mst_agent)
    `uvm_component_utils_end
endclass :shmins_mst_agent

//-----------------------------------------------------------------------------
// Function: new
//-----------------------------------------------------------------------------
function shmins_mst_agent::new(string name = "shmins_mst_agent", uvm_component parent);
    super.new(name, parent);
endfunction :new

function void shmins_mst_agent::build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info(get_type_name(), "In build_phase...!!", UVM_DEBUG);

    //---------------------------------------------------------------------
    // Get configuration
    //---------------------------------------------------------------------

    // Get Agent Configuration
    if (!uvm_config_db#(shmins_mst_agent_config)::get(this, "", "shmins_mst_agent_config", shmins_mst_agent_cfg))
    begin
        `uvm_error(get_type_name(), "shmins_mst_agent_config object is not found in config db!");
    end
    else
    begin
        shmins_mst_agent_cfg.print();
    end

    //---------------------------------------------------------------------
    // Construct children
    //---------------------------------------------------------------------

    // Construct Agent Monitors
    if (shmins_mst_agent_cfg.shmins_mon_is_active) shmins_mon = shmins_monitor::type_id::create("shmins_mon", this);

    // Construct Agent Driver-Sequencers
    if (shmins_mst_agent_cfg.shmins_mst_is_active) begin
        shmins_mst_sqr = shmins_mst_sequencer::type_id::create("shmins_mst_sqr", this);
        uvm_config_db#(shmins_mst_sequencer)::set(null, "", $sprintf("shmins_mst_sqr"), shmins_mst_sqr);
        shmins_mst_drv = shmins_mst_driver::type_id::create("shmins_mst_drv", this);
    end

    //---------------------------------------------------------------------
    // Configure children
    //---------------------------------------------------------------------

endfunction: build_phase

//-----------------------------------------------------------------------------
// Function: connect_phase
//-----------------------------------------------------------------------------
// Establish cross-component connections
//-----------------------------------------------------------------------------
function void shmins_mst_agent::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    `uvm_info(get_type_name(), "In connect_phase...!!", UVM_DEBUG);

    //---------------------------------------------------------------------
    // Connect Virtual Interface to Monitor
    //---------------------------------------------------------------------
    if (shmins_mst_agent_cfg.shmins_mon_is_active) begin
        shmins_mon.shmins_mon_vif = shmins_mst_vif;
    end

    if (shmins_mst_agent_cfg.shmins_mst_is_active) begin
        shmins_mst_drv.shmins_mst_vif = shmins_mst_vif;
    end

    if (shmins_mst_agent_cfg.shmins_mst_is_active) begin
        shmins_mst_drv.seq_item_port.connect(shmins_mst_sqr.seq_item_export);
    end
endfunction: connect_phase
