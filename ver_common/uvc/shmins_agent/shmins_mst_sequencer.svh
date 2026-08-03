//================================================================================
// File Name       : shmins_mst_sequencer
// Author          : chao.ma
// Copyright       : HX
//================================================================================
// NOTE: Please Don't Remove Any Comments or //--- Given Below
//================================================================================

`ifndef INC_SHMINS_MST_SEQUENCER_SVH
`define INC_SHMINS_MST_SEQUENCER_SVH

//-----------------------------------------------------------------------------
// Class: shmins_mst_sequencer
//-----------------------------------------------------------------------------
class shmins_mst_sequencer extends uvm_sequencer #(shmins_sequence_item);

    // Standard UVM Methods
    extern function  new   (string name= "shmins_mst_sequencer", uvm_component parent);

    // User Defined APIs

    // UVM Factory Registration Macro
    `uvm_component_utils(shmins_mst_sequencer)
endclass: shmins_mst_sequencer

//-----------------------------------------------------------------------------
// Function: new
//-----------------------------------------------------------------------------
function shmins_mst_sequencer::new(string name = "shmins_mst_sequencer", uvm_component parent);
    super.new(name, parent);
endfunction: new

`endif // INC_SHMINS_MST_SEQUENCER_SVH
