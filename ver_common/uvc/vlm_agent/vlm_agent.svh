`ifndef INC_VLM_AGENT_SVH
`define INC_VLM_AGENT_SVH

//------------------------------------------------------------------------------
// @brief Public unified VLM agent type used by the SHM environment.
//
// The inherited implementation owns one atomic monitor, reservation checker,
// scheduler, coverage collector, gid resolver, MEM publisher, and read-data
// response path. The legacy base-class name is retained only to limit churn in
// the reservation implementation files.
//------------------------------------------------------------------------------
class vlm_agent extends vlm_reservation_agent;

  //------------------------------------------------------------------------------
  // @brief Constructs the unified VLM agent.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this agent.
  //------------------------------------------------------------------------------
  extern function new(string name = "vlm_agent", uvm_component parent = null);

  `uvm_component_utils(vlm_agent)

endclass : vlm_agent

function vlm_agent::new(string name = "vlm_agent", uvm_component parent = null);
  super.new(name, parent);
endfunction : new

`endif // INC_VLM_AGENT_SVH
