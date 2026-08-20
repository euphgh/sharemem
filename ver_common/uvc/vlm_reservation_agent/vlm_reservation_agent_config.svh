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

  // Number of write cycles visible to one MEM read; values below one are not yet supported.
  int unsigned ffd_cyc;

  // Number of cycles from a MEM read request to the DUT read-data sampling edge.
  int unsigned rport_dly;

  //------------------------------------------------------------------------------
  // @brief Constructs an agent configuration object with default settings.
  //
  // @param name UVM object instance name used for factory and report context.
  //------------------------------------------------------------------------------
  extern function new(string name = "vlm_reservation_agent_config");

  //------------------------------------------------------------------------------
  // @brief Validates the interface, busy percentage, and read timing window.
  //
  // @return 1 when the interface exists and all configuration values are supported.
  //------------------------------------------------------------------------------
  extern function bit validate();

  `uvm_object_utils(vlm_reservation_agent_config)

endclass : vlm_reservation_agent_config

function vlm_reservation_agent_config::new(string name = "vlm_reservation_agent_config");
  super.new(name);
  EXTERNAL_BUSY_PERCENT = 0;
  external_busy_policy = null;
  ffd_cyc = FFD_CYC;
  rport_dly = RPORT_DLY;
endfunction : new

function bit vlm_reservation_agent_config::validate();
  // The first read-snapshot implementation intentionally supports only positive feed-forward windows.
  return vif != null && EXTERNAL_BUSY_PERCENT <= 100 && ffd_cyc >= 1 &&
         ffd_cyc <= rport_dly;
endfunction : validate

`endif // INC_VLM_RESERVATION_AGENT_CONFIG_SVH
