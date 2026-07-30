`ifndef VLM_RESERVATION_AGENT_CONFIG_SVH
`define VLM_RESERVATION_AGENT_CONFIG_SVH

//------------------------------------------------------------------------------
// @brief Carries the two business interfaces used by the reservation agent.
//
// This first-stage environment always builds an active reservation agent with
// checker, coverage, and scheduler enabled. External busy policy belongs to the
// scheduler. The shared clk_if is supplied directly to cycle-aware components
// through UVM Config DB and is not stored in this object.
//------------------------------------------------------------------------------
class vlm_reservation_agent_config extends uvm_object;

  // Reservation interface observed for requests and driven for busy.
  virtual vlm_reservation_interface reservation_vif;

  // Read-only MEM interface used only for actual request valid and address.
  virtual vlm_memory_interface memory_vif;

  //------------------------------------------------------------------------------
  // @brief Constructs an agent configuration object with default settings.
  //
  // @param name UVM object instance name used for factory and report context.
  //------------------------------------------------------------------------------
  extern function new(string name = "vlm_reservation_agent_config");

  //------------------------------------------------------------------------------
  // @brief Validates that both required business interfaces are available.
  //
  // @return 1 when the configuration is internally consistent; otherwise 0.
  //------------------------------------------------------------------------------
  extern function bit validate();

  `uvm_object_utils(vlm_reservation_agent_config)

endclass : vlm_reservation_agent_config

`endif // VLM_RESERVATION_AGENT_CONFIG_SVH
