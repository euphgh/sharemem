`ifndef VLM_MEMORY_SLV_SEQUENCER_SV
`define VLM_MEMORY_SLV_SEQUENCER_SV

//------------------------------------------------------------------------------
// @brief Sequences VLM memory transactions for the memory slave driver.
//
// Provides the standard typed UVM sequencer endpoint. It does not sample the
// memory interface, model storage contents, or drive MEM read data.
//------------------------------------------------------------------------------
class vlm_memory_slv_sequencer extends uvm_sequencer #(vlm_memory_sequence_item);

  //------------------------------------------------------------------------------
  // @brief Constructs the typed VLM memory slave sequencer.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this sequencer.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_memory_slv_sequencer",
      uvm_component parent = null);

  `uvm_component_utils(vlm_memory_slv_sequencer)

endclass : vlm_memory_slv_sequencer

function vlm_memory_slv_sequencer::new(
    string        name = "vlm_memory_slv_sequencer",
    uvm_component parent = null);
  super.new(name, parent);
endfunction : new

`endif // VLM_MEMORY_SLV_SEQUENCER_SV
