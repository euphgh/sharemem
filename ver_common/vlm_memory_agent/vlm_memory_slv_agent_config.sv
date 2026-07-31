`ifndef VLM_MEMORY_SLV_AGENT_CONFIG_SV
`define VLM_MEMORY_SLV_AGENT_CONFIG_SV

//------------------------------------------------------------------------------
// @brief Configures the active components of a VLM memory slave agent.
//
// Selects whether the complete agent, its monitor, and its slave-side driver
// are active. It does not contain a virtual interface or memory model state.
//------------------------------------------------------------------------------
class vlm_memory_slv_agent_config extends uvm_object;

  // Overall agent operating mode.
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // Operating mode of the VLM memory monitor.
  uvm_active_passive_enum vlm_memory_mon_is_active = UVM_ACTIVE;

  // Operating mode of the VLM memory slave driver and sequencer.
  uvm_active_passive_enum vlm_memory_slv_is_active = UVM_ACTIVE;

  //------------------------------------------------------------------------------
  // @brief Constructs a VLM memory slave agent configuration.
  //
  // @param name UVM object instance name.
  //------------------------------------------------------------------------------
  extern function new(string name = "vlm_memory_slv_agent_config");

  `uvm_object_utils(vlm_memory_slv_agent_config)

endclass : vlm_memory_slv_agent_config

function vlm_memory_slv_agent_config::new(string name = "vlm_memory_slv_agent_config");
  super.new(name);
endfunction : new

`endif // VLM_MEMORY_SLV_AGENT_CONFIG_SV
