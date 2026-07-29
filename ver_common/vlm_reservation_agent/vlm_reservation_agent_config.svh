`ifndef VLM_RESERVATION_AGENT_CONFIG_SVH
`define VLM_RESERVATION_AGENT_CONFIG_SVH

//------------------------------------------------------------------------------
// @brief Configures the VLM reservation reactive agent.
//
// Carries the reservation and read-only MEM virtual interfaces, active/passive
// mode, component enables, and external busy policy. The shared clk_if is
// supplied directly to cycle-aware components through UVM Config DB and is not
// stored in this object.
//------------------------------------------------------------------------------
class vlm_reservation_agent_config extends uvm_object;

  // Reservation interface observed for requests and driven for busy in active mode.
  virtual vlm_reservation_interface reservation_vif;

  // Read-only MEM interface used only for actual request valid and address.
  virtual vlm_memory_interface memory_vif;

  // Selects whether the agent drives busy or operates as a passive observer.
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // Enables reservation protocol and reservation-to-MEM checks when set.
  bit checker_enable = 1'b1;

  // Enables reservation functional coverage sampling when set.
  bit coverage_enable = 1'b1;

  // Selects all-free, directed, or random external busy generation.
  vlm_external_busy_mode_e external_busy_mode =
      VLM_EXTERNAL_BUSY_ALL_FREE;

  // Random-mode external occupancy target in the inclusive range 0 through 100.
  int unsigned external_busy_percent = 0;

  // Directed external busy tables indexed by read/write direction.
  vlm_busy_table_t directed_external_busy[VLM_RESERVATION_DIRECTION_N];

  //------------------------------------------------------------------------------
  // @brief Constructs an agent configuration object with default settings.
  //
  // @param name UVM object instance name used for factory and report context.
  //------------------------------------------------------------------------------
  extern function new(string name = "vlm_reservation_agent_config");

  //------------------------------------------------------------------------------
  // @brief Validates configuration values and required business interfaces.
  //
  // @return 1 when the configuration is internally consistent; otherwise 0.
  //------------------------------------------------------------------------------
  extern function bit validate();

  `uvm_object_utils(vlm_reservation_agent_config)

endclass : vlm_reservation_agent_config

`endif // VLM_RESERVATION_AGENT_CONFIG_SVH
