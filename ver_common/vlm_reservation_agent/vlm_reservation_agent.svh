`ifndef VLM_RESERVATION_AGENT_SVH
`define VLM_RESERVATION_AGENT_SVH

//------------------------------------------------------------------------------
// @brief Contains the VLM reservation scheduler, checker, and cycle controller.
//
// Owns the reservation-side verification components and shares one config
// object across them. In active mode it drives reservation busy; it observes
// MEM request valid and address through a read-only interface and never drives
// or checks MEM read data.
//------------------------------------------------------------------------------
class vlm_reservation_agent extends uvm_agent;

  // Shared configuration defining interfaces, mode, and component enables.
  vlm_reservation_agent_config cfg;

  // Reservation interface owned by this agent for request sampling and busy.
  virtual vlm_reservation_interface reservation_vif;

  // Read-only MEM interface used only for actual request timing and addresses.
  virtual vlm_memory_interface memory_vif;

  // Sole component responsible for common cycle sampling and busy drive timing.
  vlm_reservation_cycle_controller cycle_controller;

  // Component maintaining external/SHM busy tables and accepted DUT records.
  vlm_reservation_scheduler scheduler;

  // Component checking reservation protocol and reservation-to-MEM matching.
  vlm_reservation_checker reservation_checker;

  // Component exposing the reservation functional coverage sampling API.
  vlm_reservation_coverage coverage;

  //------------------------------------------------------------------------------
  // @brief Constructs the VLM reservation agent.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this agent.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_reservation_agent",
      uvm_component parent = null);

  //------------------------------------------------------------------------------
  // @brief Builds enabled child components and obtains agent configuration.
  //
  // @param phase UVM build phase used to construct the agent hierarchy.
  // @post Controller and scheduler are available; checker and coverage are
  //       constructed according to their enable fields in cfg.
  //------------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Connects config, scheduler, checker, coverage, and controller APIs.
  //
  // @param phase UVM connect phase used to establish component relationships.
  // @post All constructed child components refer to the same config and cycle.
  //------------------------------------------------------------------------------
  extern virtual function void connect_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Assigns an explicit configuration before child construction.
  //
  // @param cfg Configuration handle to use for this agent and all children.
  // @pre cfg is non-null and validate() returns 1.
  // @post reservation_vif and memory_vif are taken from the supplied config.
  //------------------------------------------------------------------------------
  extern function void set_config(vlm_reservation_agent_config cfg);

  //------------------------------------------------------------------------------
  // @brief Returns the configuration currently owned by this agent.
  //
  // @return Shared agent configuration handle, or null before configuration.
  //------------------------------------------------------------------------------
  extern function vlm_reservation_agent_config get_config();

  //------------------------------------------------------------------------------
  // @brief Returns the scheduler created by this agent.
  //
  // @return Scheduler handle, or null before child construction completes.
  //------------------------------------------------------------------------------
  extern function vlm_reservation_scheduler get_scheduler();

  //------------------------------------------------------------------------------
  // @brief Returns the checker created by this agent.
  //
  // @return Checker handle, or null when checker_enable is clear.
  //------------------------------------------------------------------------------
  extern function vlm_reservation_checker get_checker();

  //------------------------------------------------------------------------------
  // @brief Returns the coverage collector created by this agent.
  //
  // @return Coverage handle, or null when coverage_enable is clear.
  //------------------------------------------------------------------------------
  extern function vlm_reservation_coverage get_coverage();

  `uvm_component_utils(vlm_reservation_agent)

endclass : vlm_reservation_agent

`endif // VLM_RESERVATION_AGENT_SVH
