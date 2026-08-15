`ifndef INC_VLM_RESERVATION_AGENT_CONFIG_SVH
`define INC_VLM_RESERVATION_AGENT_CONFIG_SVH

//------------------------------------------------------------------------------
// @brief Carries the interfaces and external busy policy used by the reservation agent.
//
// This first-stage environment always builds an active reservation agent with
// checker, coverage, and scheduler enabled. The shared clk_if is supplied
// directly to cycle-aware components through UVM Config DB and is not stored in
// this object.
//------------------------------------------------------------------------------
class vlm_reservation_agent_config extends uvm_object;

  // Unified interface observed for reservation/MEM requests and driven for busy/read data.
  virtual vlm_interface vif;

  // Percentage probability applied independently to every free external busy slot.
  int unsigned EXTERNAL_BUSY_PERCENT;

  // Optional deterministic policy; when non-null it replaces percentage-based generation.
  vlm_reservation_external_busy_policy external_busy_policy;

  //------------------------------------------------------------------------------
  // @brief Constructs an agent configuration object with default settings.
  //
  // @param name UVM object instance name used for factory and report context.
  //------------------------------------------------------------------------------
  extern function new(string name = "vlm_reservation_agent_config");

  //------------------------------------------------------------------------------
  // @brief Validates the required interfaces and external busy percentage.
  //
  // @return 1 when both interfaces exist and the percentage is in [0, 100].
  //------------------------------------------------------------------------------
  extern function bit validate();

  `uvm_object_utils(vlm_reservation_agent_config)

endclass : vlm_reservation_agent_config

function vlm_reservation_agent_config::new(string name = "vlm_reservation_agent_config");
  super.new(name);
  EXTERNAL_BUSY_PERCENT = 0;
  external_busy_policy = null;
endfunction : new

function bit vlm_reservation_agent_config::validate();
  // Both interfaces and a bounded percentage are required before the active agent can run.
  return vif != null && EXTERNAL_BUSY_PERCENT <= 100;
endfunction : validate

`endif // INC_VLM_RESERVATION_AGENT_CONFIG_SVH
