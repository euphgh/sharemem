`ifndef INC_VLM_SLV_DRIVER_SV
`define INC_VLM_SLV_DRIVER_SV

//--------------------------------------------------------------
// Class: vlm_slv_driver
//
//--------------------------------------------------------------

class vlm_slv_driver extends uvm_driver #(vlm_sequence_item);

  //------------------------------------------------------------
  // Data Members
  //------------------------------------------------------------
  int unsigned vlm_agent_id;
  bit [31:0]  drv_tr_cnt = 0;

  //------------------------------------------------------------
  // Interface Instantiation
  //------------------------------------------------------------
  virtual vlm_interface vlm_slv_vif;

  //------------------------------------------------------------
  // Agent Configuration Instantiation
  //------------------------------------------------------------
  vlm_slv_agent_config vlm_slv_agent_cfg;
  uvm_tlm_b_transport_port #(vlm_sequence_item) mem_port;

  //------------------------------------------------------------
  // Constraints
  //------------------------------------------------------------

  //------------------------------------------------------------
  // Methods
  //------------------------------------------------------------

  //--------------------
  // Standard UVM Methods
  //--------------------
  extern function new(string name = "vlm_slv_driver",
                      uvm_component parent);

  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);
  extern virtual function void end_of_elaboration_phase(uvm_phase phase);
  extern virtual function void start_of_simulation_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern virtual function void extract_phase(uvm_phase phase);
  extern virtual function void check_phase(uvm_phase phase);
  extern virtual function void report_phase(uvm_phase phase);
  extern virtual function void final_phase(uvm_phase phase);

  //--------------------
  // User Defined APIs
  //--------------------
  extern task reset_signals();
  extern task drive_signals();

  //----------------------------
  // UVM Factory Registration
  //----------------------------
  `uvm_component_utils_begin(vlm_slv_driver)

    // Add field configurations
    //------------------------
    `uvm_field_int(vlm_agent_id, UVM_ALL_ON)

  `uvm_component_utils_end

endclass : vlm_slv_driver

//-----------------------------------------------------------------
// Function: new
//-----------------------------------------------------------------

function vlm_slv_driver::new(string name = "vlm_slv_driver",
                             uvm_component parent);
  super.new(name, parent);
  mem_port = new("mem_port", this);
endfunction : new


//-----------------------------------------------------------------
// Function: build_phase
//
// Create and configure of testbench structure
//-----------------------------------------------------------------

function void vlm_slv_driver::build_phase(uvm_phase phase);
  super.build_phase(phase);

  `uvm_info(get_type_name(),
            "In build_phase...!!",
            UVM_DEBUG);

  //----------------
  // Get configuration
  //----------------

  // Get Agent Configuration
  if (!uvm_config_db#(vlm_slv_agent_config)::get(this,
                                                 "*",
                                                 "vlm_slv_agent_config",
                                                 vlm_slv_agent_cfg))
  begin
    `uvm_error(get_type_name(),
               "vlm_slv_agent_config object is not found in config_db!")
  end
  else
  begin
    vlm_slv_agent_cfg.print();
  end

  //----------------
  // Construct children
  //----------------

  //----------------
  // Configure children
  //----------------

endfunction : build_phase


//-----------------------------------------------------------------
// Function: connect_phase
//
// Establish cross-component connections
//-----------------------------------------------------------------

function void vlm_slv_driver::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  `uvm_info(get_type_name(),
            "In connect_phase...!!",
            UVM_DEBUG);

endfunction : connect_phase


//-----------------------------------------------------------------
// Function: end_of_elaboration_phase
//
// Fine-tune the testbench
//-----------------------------------------------------------------

function void vlm_slv_driver::end_of_elaboration_phase(uvm_phase phase);
  super.end_of_elaboration_phase(phase);

  `uvm_info(get_type_name(),
            "In end_of_elaboration_phase...!!",
            UVM_DEBUG);

endfunction : end_of_elaboration_phase


//-----------------------------------------------------------------
// Function: start_of_simulation_phase
//
// Get ready for DUT to be simulated
//-----------------------------------------------------------------

function void vlm_slv_driver::start_of_simulation_phase(uvm_phase phase);
  super.start_of_simulation_phase(phase);

  `uvm_info(get_type_name(),
            "In start_of_simulation_phase...!!",
            UVM_DEBUG);

endfunction : start_of_simulation_phase

//-----------------------------------------------------------------
// Function: report_phase
//
// Report results of the test
//-----------------------------------------------------------------

function void vlm_slv_driver::report_phase(uvm_phase phase);

  super.report_phase(phase);

  `uvm_info(get_type_name(),
            "In report_phase...!!",
            UVM_DEBUG);

endfunction : report_phase


//-----------------------------------------------------------------
// Function: final_phase
//
// Tie up loose ends. All Simulation activities are done.
//
// Closing files, Ending co-simulation engines etc.
//-----------------------------------------------------------------

function void vlm_slv_driver::final_phase(uvm_phase phase);

  super.final_phase(phase);

  `uvm_info(get_type_name(), "In final_phase...!!", UVM_DEBUG);

endfunction : final_phase


//-----------------------------------------------------------------
// User Defined
// Task: reset_signals
//
// Reset VLM Master Output.
//-----------------------------------------------------------------

task vlm_slv_driver::reset_signals();

  vlm_slv_vif.slv_cb.vlm_rdata <= '0;
  vlm_slv_vif.slv_cb.vlm_rbusy <= '0;
  vlm_slv_vif.slv_cb.vlm_wbusy <= '0;

  `uvm_info(get_type_name(),
            "Reset vlm_slv interface...!!",
            UVM_DEBUG);

endtask : reset_signals


//-----------------------------------------------------------------
// User Defined
// Task: drive_signals
//
// Driver VLM Master Output
//-----------------------------------------------------------------

task vlm_slv_driver::drive_signals();

  forever begin

    vlm_sequence_item trans;
    uvm_tlm_time delay = new("delay");    // TLM-2.0 need a time parameter

    @(vlm_slv_vif.slv_cb);

    if (|vlm_slv_vif.slv_cb.vlm_rvld) begin

      fork

        begin

          trans = vlm_sequence_item::type_id::create("trans");

          trans.vlm_read = 1'b1;

          for (int idx = 0; idx < BANK_N; idx++) begin
            trans.vlm_bken[idx] = vlm_slv_vif.slv_cb.vlm_rvld[idx];
            trans.vlm_addr[idx] = vlm_slv_vif.slv_cb.vlm_raddr[idx];
          end

          mem_port.b_transport(trans, delay);

          repeat(RPORT_DLY - 1)
            @(vlm_slv_vif.mon_cb);

          `uvm_info(get_type_name(),
                    $sformatf("Check b_trans at drv Thd[0] rdata = %x",
                              trans.vlm_data[0]),
                    UVM_FULL);

          for (int idx = 0; idx < BANK_N; idx++) begin
            vlm_slv_vif.slv_cb.vlm_rdata[idx] <= trans.vlm_data[idx];
          end

        end

      join_none

    end

  end

endtask : drive_signals

`endif // INC_VLM_SLV_DRIVER_SV