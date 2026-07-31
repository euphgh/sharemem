`ifndef INC_VLM_SLV_AGENT_SV
`define INC_VLM_SLV_AGENT_SV


//------------------------------------------------------------
// Class: vlm_slv_agent
//
//------------------------------------------------------------

class vlm_slv_agent extends uvm_agent;

  //------------------------------------------------
  // Data Members
  //------------------------------------------------
  int unsigned vlm_slv_agent_id;

  //------------------------------------------------
  // Agent Interface Instantiation
  //------------------------------------------------
  virtual vlm_interface vlm_slv_vif;

  //------------------------------------------------
  // Agent Configuration Instantiation
  //------------------------------------------------
  vlm_slv_agent_config vlm_slv_agent_cfg;

  //------------------------------------------------
  // Agent Driver-Sequencer Instantiation
  //------------------------------------------------
  vlm_slv_sequencer  vlm_slv_sqr;
  vlm_slv_driver     vlm_slv_drv;

  //------------------------------------------------
  // Agent Monitor Instantiation
  //------------------------------------------------
  vlm_monitor        vlm_mon;

  //------------------------------------------------
  // Constraints
  //------------------------------------------------

  //------------------------------------------------
  // Methods
  //------------------------------------------------

  //--------------------
  // Standard UVM Methods
  //--------------------
  extern function new(string name = "vlm_slv_agent", uvm_component parent);

  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);

  //--------------------
  // User Defined APIs
  //--------------------

  //--------------------
  // UVM Factory Registration
  //--------------------

  //-----------------------------------------------------------------------------
// UVM Factory Registration
//-----------------------------------------------------------------------------
`uvm_component_utils_begin(vlm_slv_agent)
    // Add field configurations
    `uvm_field_int(vlm_slv_agent_id, UVM_ALL_ON)
`uvm_component_utils_end
endclass : vlm_slv_agent

//-----------------------------------------------------------------------------
// Function: new
//-----------------------------------------------------------------------------
function vlm_slv_agent::new(string name = "vlm_slv_agent", uvm_component parent);
    super.new(name, parent);
endfunction : new

//-----------------------------------------------------------------------------
// Function: build_phase
//-----------------------------------------------------------------------------
// Create and configure of testbench structure
function void vlm_slv_agent::build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_info(get_type_name(), "In build_phase...!", UVM_DEBUG);

    //---------------------------------------------------------------------
    // Get configuration
    //---------------------------------------------------------------------
    // Get Agent Configuration
    if (!uvm_config_db#(vlm_slv_agent_config)::get(this, "", "vlm_slv_agent_config", vlm_slv_agent_cfg))
    begin
        `uvm_error(get_type_name(), "vlm_slv_agent_config object is not found in config db!");
    end
    else
    begin
        vlm_slv_agent_cfg.print();
    end

    //---------------------------------------------------------------------
    // Construct children
    //---------------------------------------------------------------------
    // Construct Agent Monitors
    if (vlm_slv_agent_cfg.vlm_mon_is_active) vlm_mon = vlm_monitor::type_id::create("vlm_mon", this);

    // Construct Agent Driver-Sequencers
    if (vlm_slv_agent_cfg.vlm_slv_is_active) begin
        vlm_slv_sqr = vlm_slv_sequencer::type_id::create("vlm_slv_sqr", this);
        uvm_config_db#(vlm_slv_sequencer)::set(null, "*", $sprintf("vlm_slv_sqr"), vlm_slv_sqr);
        vlm_slv_drv = vlm_slv_driver::type_id::create("vlm_slv_drv", this);
    end

    //---------------------------------------------------------------------
    // Configure children
    //---------------------------------------------------------------------

endfunction: build_phase


//-----------------------------------------------------------------------------
// Function: connect_phase
//-----------------------------------------------------------------------------
// Establish cross-component connections

function void vlm_slv_agent::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    `uvm_info(get_type_name(), "In connect_phase...!!", UVM_DEBUG);

    //---------------------------------------------------------------------
    // Connect Virtual Interface to Monitor
    //---------------------------------------------------------------------
    if (vlm_slv_agent_cfg.vlm_mon_is_active) begin
        vlm_mon.vlm_mon_vif = vlm_slv_vif;
    end

    if (vlm_slv_agent_cfg.vlm_slv_is_active) begin
        vlm_slv_drv.vlm_slv_vif = vlm_slv_vif;
    end

    //---------------------------------------------------------------------
    // Connect Analysis Port
    //---------------------------------------------------------------------

    //---------------------------------------------------------------------
    // Connect children
    //---------------------------------------------------------------------

    // Connect Agent Driver-Sequencers
    if (vlm_slv_agent_cfg.vlm_slv_is_active) begin
        vlm_slv_drv.seq_item_port.connect(vlm_slv_sqr.seq_item_export);
    end

endfunction: connect_phase