`ifndef INC_VLM_RESERVATION_EXTERNAL_BUSY_POLICY_SVH
`define INC_VLM_RESERVATION_EXTERNAL_BUSY_POLICY_SVH

//------------------------------------------------------------------------------
// @brief Selects deterministic external-busy slots for the reservation scheduler.
//
// The scheduler queries this read-only policy only for slots that are not
// already owned by external or SHM state. A policy never modifies scheduler
// state and never consumes checker outcomes.
//------------------------------------------------------------------------------
virtual class vlm_reservation_external_busy_policy extends uvm_object;
  //----------------------------------------------------------------------------
  // @brief Constructs an external-busy policy object.
  //
  // @param name UVM object instance name.
  //----------------------------------------------------------------------------
  function new(string name = "vlm_reservation_external_busy_policy");
    super.new(name);
  endfunction : new

  //----------------------------------------------------------------------------
  // @brief Returns whether one free slot should become externally busy.
  //
  // @param drive_cycle Interface cycle that will observe the generated busy.
  // @param direction   Read or write reservation table.
  // @param delay       Relative delay index in the generated busy window.
  // @param gid         Low/high physical-bank identifier.
  // @param sub_bank    Sub-bank identifier derived from address bits [6:5].
  // @return 1 when the scheduler should occupy this free slot; otherwise 0.
  //----------------------------------------------------------------------------
  pure virtual function bit should_occupy(
      longint unsigned            drive_cycle,
      vlm_reservation_direction_e direction,
      int unsigned                delay,
      int unsigned                gid,
      int unsigned                sub_bank);
endclass : vlm_reservation_external_busy_policy

//------------------------------------------------------------------------------
// @brief Implements an explicit cycle/range-based external-busy schedule.
//
// Tests add inclusive drive-cycle ranges for exact direction/delay/gid/subbank
// slots. Slots not covered by a directive remain free unless retained external
// state has shifted into them from an earlier cycle.
//------------------------------------------------------------------------------
class vlm_reservation_directed_busy_policy extends vlm_reservation_external_busy_policy;
  typedef struct {
    longint unsigned first_drive_cycle;
    longint unsigned last_drive_cycle;
    int unsigned     direction;
    int unsigned     delay;
    int unsigned     gid;
    int unsigned     sub_bank;
  } directive_t;

  // Ordered directives installed by the controlling component or test.
  protected directive_t directives[$];

  //----------------------------------------------------------------------------
  // @brief Constructs an empty directed external-busy schedule.
  //
  // @param name UVM object instance name.
  //----------------------------------------------------------------------------
  extern function new(string name = "vlm_reservation_directed_busy_policy");

  //----------------------------------------------------------------------------
  // @brief Adds one exact drive-cycle busy directive.
  //
  // @param drive_cycle Interface cycle that must observe the selected busy.
  // @param direction   Read or write reservation table.
  // @param delay       Relative delay in the range 0 through VTAB_D-1.
  // @param gid         Physical gid in the range 0 through GID_N-1.
  // @param sub_bank    Sub-bank in the range 0 through VLM_SUB_BANK_N-1.
  //----------------------------------------------------------------------------
  extern function void add_busy_cycle(
      longint unsigned            drive_cycle,
      vlm_reservation_direction_e direction,
      int unsigned                delay,
      int unsigned                gid,
      int unsigned                sub_bank);

  //----------------------------------------------------------------------------
  // @brief Adds one inclusive drive-cycle range for an exact busy slot.
  //
  // @param first_drive_cycle First interface cycle covered by the directive.
  // @param last_drive_cycle  Last interface cycle covered by the directive.
  // @param direction         Read or write reservation table.
  // @param delay             Relative delay in the range 0 through VTAB_D-1.
  // @param gid               Physical gid in the range 0 through GID_N-1.
  // @param sub_bank          Sub-bank in the range 0 through VLM_SUB_BANK_N-1.
  //----------------------------------------------------------------------------
  extern function void add_busy_range(
      longint unsigned            first_drive_cycle,
      longint unsigned            last_drive_cycle,
      vlm_reservation_direction_e direction,
      int unsigned                delay,
      int unsigned                gid,
      int unsigned                sub_bank);

  //----------------------------------------------------------------------------
  // @brief Removes every previously installed directive.
  //----------------------------------------------------------------------------
  extern function void clear();

  //----------------------------------------------------------------------------
  // @brief Matches one free scheduler slot against the installed directives.
  //
  // @param drive_cycle Interface cycle that will observe the generated busy.
  // @param direction   Read or write reservation table.
  // @param delay       Relative delay index in the generated busy window.
  // @param gid         Low/high physical-bank identifier.
  // @param sub_bank    Sub-bank identifier derived from address bits [6:5].
  // @return 1 when any directive covers the complete key; otherwise 0.
  //----------------------------------------------------------------------------
  extern virtual function bit should_occupy(
      longint unsigned            drive_cycle,
      vlm_reservation_direction_e direction,
      int unsigned                delay,
      int unsigned                gid,
      int unsigned                sub_bank);

  `uvm_object_utils(vlm_reservation_directed_busy_policy)
endclass : vlm_reservation_directed_busy_policy

function vlm_reservation_directed_busy_policy::new(
    string name = "vlm_reservation_directed_busy_policy");
  super.new(name);
endfunction : new

function void vlm_reservation_directed_busy_policy::add_busy_cycle(
    longint unsigned            drive_cycle,
    vlm_reservation_direction_e direction,
    int unsigned                delay,
    int unsigned                gid,
    int unsigned                sub_bank);
  add_busy_range(drive_cycle, drive_cycle, direction, delay, gid, sub_bank);
endfunction : add_busy_cycle

function void vlm_reservation_directed_busy_policy::add_busy_range(
    longint unsigned            first_drive_cycle,
    longint unsigned            last_drive_cycle,
    vlm_reservation_direction_e direction,
    int unsigned                delay,
    int unsigned                gid,
    int unsigned                sub_bank);
  directive_t directive;

  if (first_drive_cycle > last_drive_cycle || delay >= VTAB_D || gid >= GID_N ||
      sub_bank >= VLM_SUB_BANK_N) begin
    `uvm_fatal("VLM_DIRECTED_BUSY_RANGE",
               $sformatf({"invalid directive cycles [%0d, %0d], direction %0d, delay %0d, ",
                          "gid %0d, sub-bank %0d"},
                         first_drive_cycle, last_drive_cycle, direction, delay, gid, sub_bank))
    return;
  end

  directive.first_drive_cycle = first_drive_cycle;
  directive.last_drive_cycle = last_drive_cycle;
  directive.direction = direction;
  directive.delay = delay;
  directive.gid = gid;
  directive.sub_bank = sub_bank;
  directives.push_back(directive);
endfunction : add_busy_range

function void vlm_reservation_directed_busy_policy::clear();
  directives.delete();
endfunction : clear

function bit vlm_reservation_directed_busy_policy::should_occupy(
    longint unsigned            drive_cycle,
    vlm_reservation_direction_e direction,
    int unsigned                delay,
    int unsigned                gid,
    int unsigned                sub_bank);
  foreach (directives[directive_idx]) begin
    directive_t directive = directives[directive_idx];

    if (drive_cycle >= directive.first_drive_cycle && drive_cycle <= directive.last_drive_cycle &&
        int'(direction) == directive.direction && delay == directive.delay && gid == directive.gid &&
        sub_bank == directive.sub_bank) begin
      return 1'b1;
    end
  end
  return 1'b0;
endfunction : should_occupy

`endif // INC_VLM_RESERVATION_EXTERNAL_BUSY_POLICY_SVH
