`ifndef INC_SHM_TRANSACTION_LIFECYCLE_TYPES_SVH
`define INC_SHM_TRANSACTION_LIFECYCLE_TYPES_SVH

//------------------------------------------------------------------------------
// @brief Classifies scoreboard progress for one accepted SHM transaction.
//------------------------------------------------------------------------------
typedef enum bit {
  SHM_COMPLETION_RESOLVED,
  SHM_COMPLETION_OBSERVED
} shm_completion_kind_e;

//------------------------------------------------------------------------------
// @brief Carries one sampled V2M or M2V completion-ack event.
//
// The monitor creates this event from the interface. It does not determine
// whether the ack is expected, duplicated, or associated with completed data.
//------------------------------------------------------------------------------
class shmins_ack_event extends uvm_object;
  creq_rw_e            direction;
  logic [ID_W-1:0]     transaction_id;
  shm_cycle_t           cycle;
  longint unsigned      reset_epoch;

  //----------------------------------------------------------------------------
  // @brief Constructs an empty sampled ack event.
  //
  // @param name UVM object instance name.
  //----------------------------------------------------------------------------
  function new(string name = "shmins_ack_event");
    super.new(name);
  endfunction : new

  `uvm_object_utils_begin(shmins_ack_event)
    `uvm_field_enum(creq_rw_e, direction, UVM_DEFAULT)
    `uvm_field_int(transaction_id, UVM_DEFAULT)
    `uvm_field_int(cycle, UVM_DEFAULT)
    `uvm_field_int(reset_epoch, UVM_DEFAULT)
  `uvm_object_utils_end
endclass : shmins_ack_event

//------------------------------------------------------------------------------
// @brief Reports that scoreboard data for one SHM transaction is resolved.
//
// OBSERVED means every expected byte was matched by an actual DUT write.
// RESOLVED may also include bytes made unobservable by a later transaction.
//------------------------------------------------------------------------------
class shm_completion_event extends uvm_object;
  shm_transaction_uid_t transaction_uid;
  shm_completion_kind_e kind;
  shm_cycle_t            cycle;

  //----------------------------------------------------------------------------
  // @brief Constructs an empty scoreboard completion event.
  //
  // @param name UVM object instance name.
  //----------------------------------------------------------------------------
  function new(string name = "shm_completion_event");
    super.new(name);
  endfunction : new

  `uvm_object_utils_begin(shm_completion_event)
    `uvm_field_int(transaction_uid, UVM_DEFAULT)
    `uvm_field_enum(shm_completion_kind_e, kind, UVM_DEFAULT)
    `uvm_field_int(cycle, UVM_DEFAULT)
  `uvm_object_utils_end
endclass : shm_completion_event

`endif // INC_SHM_TRANSACTION_LIFECYCLE_TYPES_SVH
