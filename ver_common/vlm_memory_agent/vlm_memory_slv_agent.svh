`ifndef VLM_MEMORY_SLV_AGENT_SVH
`define VLM_MEMORY_SLV_AGENT_SVH

//------------------------------------------------------------------------------
// @brief Contains the monitor and active components for the VLM memory port.
//
// Always constructs a monitor. In active mode it also constructs and connects
// the read-data driver and its typed sequencer. The agent does not implement
// reservation scheduling or MEM data checking.
//------------------------------------------------------------------------------
class vlm_memory_slv_agent extends uvm_agent;

  // Shared VLM memory interface obtained through UVM Config DB.
  virtual vlm_memory_interface memory_vif;

  // Passive component that publishes observed MEM read and write transactions.
  vlm_memory_monitor monitor;

  // Active component that returns fixed-latency MEM read data.
  vlm_memory_slv_driver driver;

  // Typed sequencer connected to the active memory slave driver.
  vlm_memory_slv_sequencer sequencer;

  //------------------------------------------------------------------------------
  // @brief Constructs the VLM memory slave agent.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this agent.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_memory_slv_agent",
      uvm_component parent = null);

  //------------------------------------------------------------------------------
  // @brief Obtains memory_vif and constructs the configured component hierarchy.
  //
  // @param phase UVM build phase used to create the monitor and active children.
  // @post The monitor exists; driver and sequencer exist only in active mode.
  //------------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Assigns memory_vif and connects the active driver to its sequencer.
  //
  // @param phase UVM connect phase used to establish component relationships.
  //------------------------------------------------------------------------------
  extern virtual function void connect_phase(uvm_phase phase);

  `uvm_component_utils(vlm_memory_slv_agent)

endclass : vlm_memory_slv_agent

function vlm_memory_slv_agent::new(
    string        name = "vlm_memory_slv_agent",
    uvm_component parent = null);
  super.new(name, parent);
endfunction : new

function void vlm_memory_slv_agent::build_phase(uvm_phase phase);
  super.build_phase(phase);

  if (!uvm_config_db#(virtual vlm_memory_interface)::get(this, "", "memory_vif", memory_vif)) begin
    `uvm_fatal("VLM_MEMORY_NO_VIF", "vlm_memory_slv_agent requires virtual interface 'memory_vif'")
  end

  monitor = vlm_memory_monitor::type_id::create("monitor", this);

  if (get_is_active() == UVM_ACTIVE) begin
    sequencer = vlm_memory_slv_sequencer::type_id::create("sequencer", this);
    driver    = vlm_memory_slv_driver::type_id::create("driver", this);
  end
endfunction : build_phase

function void vlm_memory_slv_agent::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  // The monitor retains its existing public vif field until its own migration.
  monitor.vlm_mon_vif = memory_vif;

  if (get_is_active() == UVM_ACTIVE) begin
    driver.memory_vif = memory_vif;
    driver.seq_item_port.connect(sequencer.seq_item_export);
  end
endfunction : connect_phase

`endif // VLM_MEMORY_SLV_AGENT_SVH
