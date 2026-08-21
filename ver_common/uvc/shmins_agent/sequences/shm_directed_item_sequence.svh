`ifndef INC_SHM_DIRECTED_ITEM_SEQUENCE_SVH
`define INC_SHM_DIRECTED_ITEM_SEQUENCE_SVH

//------------------------------------------------------------------------------
// @brief Atomically validates and sends already-built topology requests.
//
// A caller owns request construction, address backfill, and item validation.
// This sequence adds pairwise cross-transaction hazard validation and ordered
// transport without randomizing or modifying caller-owned payload objects.
//------------------------------------------------------------------------------
class shm_directed_item_sequence extends uvm_sequence #(shmins_sequence_item);
  // Requests supplied in the exact order in which they must be issued.
  protected shmins_sequence_item directed_requests[$];

  // Complete idle cycles inserted before every request after the first.
  protected int unsigned inter_item_delay_cycles;

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
  // @brief Installs one ordered batch and its uniform inter-item issue delay.
  //
  // @param requests Fully prepared requests; handles are retained but not modified.
  // @param delay_cycles Complete idle cycles between adjacent accepted requests.
  //----------------------------------------------------------------------------
  extern function void set_requests(ref shmins_sequence_item requests[$],
                                    input int unsigned delay_cycles = 0);

  //----------------------------------------------------------------------------
  // @brief Returns the number of currently installed requests.
  //
  // @return Queue size installed through set_request() or set_requests().
  //----------------------------------------------------------------------------
  extern function int unsigned request_count();

  //----------------------------------------------------------------------------
  // @brief Validates every item and pair before any request is sent.
  //
  // @param diagnostic Empty on success; otherwise identifies the failing item
  //                   or pair and all relevant byte-overlap details.
  // @return 1 when the complete batch can be issued atomically.
  //----------------------------------------------------------------------------
  extern function bit validate_batch(output string diagnostic);

  //----------------------------------------------------------------------------
  // @brief Checks and sends the installed request without further randomizing it.
  //----------------------------------------------------------------------------
  extern virtual task body();

  `uvm_object_utils(shm_directed_item_sequence)
endclass : shm_directed_item_sequence

function shm_directed_item_sequence::new(string name = "shm_directed_item_sequence");
  super.new(name);
  inter_item_delay_cycles = 0;
endfunction : new

function void shm_directed_item_sequence::set_request(shmins_sequence_item request);
  directed_requests.delete();
  directed_requests.push_back(request);
  inter_item_delay_cycles = 0;
endfunction : set_request

function void shm_directed_item_sequence::set_requests(ref shmins_sequence_item requests[$],
                                                       input int unsigned delay_cycles = 0);
  directed_requests = requests;
  inter_item_delay_cycles = delay_cycles;
endfunction : set_requests

function int unsigned shm_directed_item_sequence::request_count();
  return directed_requests.size();
endfunction : request_count

function bit shm_directed_item_sequence::validate_batch(output string diagnostic);
  diagnostic = "";
  if (directed_requests.size() == 0) begin
    diagnostic = "set_request() or set_requests() must install at least one request";
    return 1'b0;
  end

  foreach (directed_requests[index]) begin
    shmins_contiguous_sequence_item contiguous_item;
    shmins_strided_sequence_item strided_item;
    shmins_indexed_sequence_item indexed_item;

    if (directed_requests[index] == null) begin
      diagnostic = $sformatf("request[%0d] is null", index);
      return 1'b0;
    end
    if (!$cast(contiguous_item, directed_requests[index]) &&
        !$cast(strided_item, directed_requests[index]) &&
        !$cast(indexed_item, directed_requests[index])) begin
      diagnostic = $sformatf("request[%0d] is not a supported topology sequence item", index);
      return 1'b0;
    end
    if (directed_requests[index].validation_error_count != 0) begin
      diagnostic = $sformatf("request[%0d] has %0d validation errors", index,
                             directed_requests[index].validation_error_count);
      return 1'b0;
    end
  end

  for (int first_index = 0; first_index < directed_requests.size(); first_index++) begin
    for (int second_index = first_index + 1; second_index < directed_requests.size(); second_index++) begin
      int unsigned overlap_count = directed_requests[first_index].unordered_cross_transaction_overlap_count(
          directed_requests[second_index]);

      if (overlap_count != 0) begin
        diagnostic = {$sformatf({"request pair [%0d,%0d] has %0d unordered ",
                                 "V-write/M-access overlapping bytes\n"},
                                first_index, second_index, overlap_count),
                      directed_requests[first_index].cross_transaction_overlap_sprint(
                          directed_requests[second_index])};
        return 1'b0;
      end
    end
  end
  return 1'b1;
endfunction : validate_batch

task shm_directed_item_sequence::body();
  string diagnostic;

  if (!validate_batch(diagnostic)) begin
    `uvm_fatal("SHM_DIRECTED_INVALID_BATCH", diagnostic)
    return;
  end

  foreach (directed_requests[index]) begin
    shmins_sequence_item request_to_send;

    if (!$cast(request_to_send, directed_requests[index].clone())) begin
      `uvm_fatal("SHM_DIRECTED_CLONE_FAILED",
                 $sformatf("failed to clone request[%0d] before transport", index))
      return;
    end
    if (directed_requests.size() > 1) begin
      request_to_send.delay_cycle = index + 1 < directed_requests.size() ? inter_item_delay_cycles : 0;
    end
    start_item(request_to_send);
    finish_item(request_to_send);
  end
endtask : body

`endif // INC_SHM_DIRECTED_ITEM_SEQUENCE_SVH
