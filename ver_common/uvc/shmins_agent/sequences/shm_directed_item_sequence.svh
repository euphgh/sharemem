`ifndef INC_SHM_DIRECTED_ITEM_SEQUENCE_SVH
`define INC_SHM_DIRECTED_ITEM_SEQUENCE_SVH

//------------------------------------------------------------------------------
// @brief Sends one already-built topology request without changing its fields.
//
// A caller owns request construction, randomization, address backfill, and final
// validation. This reusable sequence deliberately provides transport only.
//------------------------------------------------------------------------------
class shm_directed_item_sequence extends uvm_sequence #(shmins_sequence_item);
  // Request supplied by the directed sequence or test builder.
  protected shmins_sequence_item directed_request;

  //----------------------------------------------------------------------------
  // @brief Constructs an empty directed-item sequence.
  //
  // @param name UVM object instance name.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_directed_item_sequence");

  //----------------------------------------------------------------------------
  // @brief Installs the fully prepared request that body() will send.
  //
  // @param request Validated contiguous, strided, indexed, or VTRANS item.
  //----------------------------------------------------------------------------
  extern function void set_request(shmins_sequence_item request);

  //----------------------------------------------------------------------------
  // @brief Checks and sends the installed request without further randomizing it.
  //----------------------------------------------------------------------------
  extern virtual task body();

  `uvm_object_utils(shm_directed_item_sequence)
endclass : shm_directed_item_sequence

function shm_directed_item_sequence::new(string name = "shm_directed_item_sequence");
  super.new(name);
endfunction : new

function void shm_directed_item_sequence::set_request(shmins_sequence_item request);
  directed_request = request;
endfunction : set_request

task shm_directed_item_sequence::body();
  shmins_contiguous_sequence_item contiguous_item;
  shmins_strided_sequence_item strided_item;
  shmins_indexed_sequence_item indexed_item;

  if (directed_request == null) begin
    `uvm_fatal("SHM_DIRECTED_NULL_REQUEST", "set_request() must be called before body()")
  end
  if (!$cast(contiguous_item, directed_request) && !$cast(strided_item, directed_request) &&
      !$cast(indexed_item, directed_request)) begin
    `uvm_fatal("SHM_DIRECTED_BASE_REQUEST", "directed request must be a supported topology sequence item")
  end
  if (directed_request.validation_error_count != 0) begin
    `uvm_fatal("SHM_DIRECTED_INVALID_REQUEST",
               $sformatf("directed request has %0d validation errors", directed_request.validation_error_count))
  end

  start_item(directed_request);
  finish_item(directed_request);
endtask : body

`endif // INC_SHM_DIRECTED_ITEM_SEQUENCE_SVH
