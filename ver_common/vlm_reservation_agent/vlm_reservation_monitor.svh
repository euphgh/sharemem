`ifndef VLM_RESERVATION_MONITOR_SVH
`define VLM_RESERVATION_MONITOR_SVH

//------------------------------------------------------------------------------
// @brief Samples reservation and MEM request interfaces into one transaction.
//
// Owns the four-state sampling and normalization boundary. It obtains the
// shared clk_if through UVM Config DB, reports unknown interface values, and
// returns one two-state cycle transaction per collect_cycle() call. It does not
// drive busy, schedule reservations, check MEM correspondence, or inspect MEM
// data payloads.
//------------------------------------------------------------------------------
class vlm_reservation_monitor extends uvm_component;

  // Agent configuration providing both business virtual interfaces.
  vlm_reservation_agent_config cfg;

  // Reservation interface sampled for requests and observed busy values.
  virtual vlm_reservation_interface reservation_vif;

  // Read-only MEM interface sampled for actual request valid and addresses.
  virtual vlm_memory_interface memory_vif;

  // Shared cycle-number service obtained directly through UVM Config DB.
  virtual clk_if clk_vif;

  // Most recent raw four-state values captured from the two interfaces.
  vlm_reservation_raw_sample_t current_raw_sample;

  // Most recent normalized two-state transaction returned to the agent.
  vlm_reservation_cycle_transaction_t current_transaction;

  // Number of cycle transactions collected since component construction.
  longint unsigned collected_cycle_count;

  // Number of interface X/Z violations reported since component construction.
  int unsigned input_error_count;

  //------------------------------------------------------------------------------
  // @brief Constructs the VLM reservation monitor.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this monitor.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_reservation_monitor",
      uvm_component parent = null);

  //------------------------------------------------------------------------------
  // @brief Obtains the shared clk_if from UVM Config DB.
  //
  // @param phase UVM build phase used to resolve component dependencies.
  // @post clk_vif refers to the environment clock service or a fatal
  //       configuration error has been reported.
  //------------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Assigns business interfaces used by the monitor.
  //
  // @param cfg Valid configuration owned by the containing reservation agent.
  // @pre cfg provides non-null reservation_vif and memory_vif handles.
  // @post Subsequent collection uses the supplied business interfaces.
  //------------------------------------------------------------------------------
  extern function void set_config(vlm_reservation_agent_config cfg);

  //------------------------------------------------------------------------------
  // @brief Waits for and returns one normalized reservation/MEM cycle.
  //
  // @param transaction Output receiving the two-state cycle transaction.
  // @pre clk_vif, reservation_vif, and memory_vif are non-null.
  // @post transaction.cycle is the clk_if cycle sampled with both interfaces.
  //------------------------------------------------------------------------------
  extern task collect_cycle(
      output vlm_reservation_cycle_transaction_t transaction);

  //------------------------------------------------------------------------------
  // @brief Atomically captures four-state values from both business interfaces.
  //
  // @param sample Output receiving raw reservation, busy, and MEM request data.
  // @pre The caller is synchronized to the reservation monitor clocking block.
  // @post sample.cycle is a snapshot of clk_vif.cycle_count.
  //------------------------------------------------------------------------------
  extern function void sample_interfaces(
      output vlm_reservation_raw_sample_t sample);

  //------------------------------------------------------------------------------
  // @brief Checks and converts one raw sample into a two-state transaction.
  //
  // @param sample      Raw four-state values captured at one sampling edge.
  // @param transaction Output receiving known events, busy masks, and status.
  // @post Unknown active inputs are reported and do not create valid events.
  //------------------------------------------------------------------------------
  extern function void normalize_sample(
      const ref vlm_reservation_raw_sample_t sample,
      output vlm_reservation_cycle_transaction_t transaction);

  `uvm_component_utils(vlm_reservation_monitor)

endclass : vlm_reservation_monitor

`endif // VLM_RESERVATION_MONITOR_SVH
