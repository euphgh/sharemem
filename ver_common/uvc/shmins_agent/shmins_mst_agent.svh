`ifndef INC_SHMINS_MST_AGENT_SVH
`define INC_SHMINS_MST_AGENT_SVH

//-----------------------------------------------------------------------------
// Class: shmins_mst_agent
//-----------------------------------------------------------------------------
class shmins_mst_agent extends uvm_agent;


    virtual shmins_interface shmins_vif;

    shmins_mst_agent_config cfg;

    shmins_mst_sequencer   sequencer;
    shmins_mst_driver      driver;
    shmins_monitor         monitor;

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
    if (!uvm_config_db#(shmins_mst_agent_config)::get(this, "", "cfg", cfg) || cfg == null) begin
        `uvm_fatal("SHMINS_NO_CFG", "shmins_mst_agent requires config object 'cfg'")
    end

    if (!uvm_config_db#(virtual shmins_interface)::get(this, "", "shmins_vif", shmins_vif)) begin
        `uvm_fatal("SHMINS_NO_VIF", "shmins_mst_agent requires virtual interface 'shmins_vif'")
    end

    is_active = cfg.is_active;

    //---------------------------------------------------------------------
    // Construct children
    //---------------------------------------------------------------------

    // Construct Agent Monitors
    if (cfg.shmins_mon_is_active == UVM_ACTIVE) begin
        monitor = shmins_monitor::type_id::create("monitor", this);
    end

    // Construct Agent Driver-Sequencers
    if (get_is_active() == UVM_ACTIVE && cfg.shmins_mst_is_active == UVM_ACTIVE) begin
        sequencer = shmins_mst_sequencer::type_id::create("sequencer", this);
        driver    = shmins_mst_driver::type_id::create("driver", this);
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
    //---------------------------------------------------------------------
    // Connect Virtual Interface to Monitor
    //---------------------------------------------------------------------
    if (monitor != null) begin
        monitor.shmins_mon_vif = shmins_vif;
    end

    if (driver != null && sequencer != null) begin
        driver.shmins_mst_vif = shmins_vif;
        driver.seq_item_port.connect(sequencer.seq_item_export);
    end
endfunction: connect_phase

`endif // INC_SHMINS_MST_AGENT_SVH
