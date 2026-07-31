`ifndef INC_VLM_SLV_SEQUENCER_SV
`define INC_VLM_SLV_SEQUENCER_SV

//----------------------------------------------------------------------
// Class: vlm_slv_sequencer
//
//----------------------------------------------------------------------

class vlm_slv_sequencer extends uvm_sequencer #(vlm_sequence_item);

  // Standard UVM Methods
  extern function        new   (string name= "vlm_slv_sequencer", uvm_component parent);
  extern function void   build_phase(uvm_phase phase);

  // User Defined APIs

  // UVM Factory Registration Macro
  `uvm_component_utils(vlm_slv_sequencer)
endclass: vlm_slv_sequencer


//----------------------------------------------------------------------
// Function: new
//
//----------------------------------------------------------------------

function vlm_slv_sequencer::new(string name = "vlm_slv_sequencer", uvm_component parent);
  super.new(name, parent);
endfunction: new


//----------------------------------------------------------------------
// Function: build_phase
//
// Create and configure of testbench structure
//----------------------------------------------------------------------

function void vlm_slv_sequencer::build_phase(uvm_phase phase);
  super.build_phase(phase);
  `uvm_info(get_type_name(), "In build_phase...!!", UVM_DEBUG);
endfunction: build_phase

`endif //INC_VLM_SLV_SEQUENCER_SV