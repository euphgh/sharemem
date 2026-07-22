`ifndef INC_vlm_memory_monitor_SV
`define INC_vlm_memory_monitor_SV

//-------------------------------------------------------------------
// Class: vlm_memory_monitor
//
//-------------------------------------------------------------------

class vlm_memory_monitor extends uvm_monitor;
//-------------------------------------------------------------------
// Data Members
//-------------------------------------------------------------------

int unsigned vlm_agent_id;
int unsigned trans_cnt=0;
int unsigned read_trans_cnt=0;
int unsigned write_trans_cnt=0;
int unsigned write_port_trans_cnt[16]='{16{0}};

vlm_sequence_item vlm_trans;

string filename = "vlm.rtl";
int    vlm_rtl_fp;


//-------------------------------------------------------------------
// Interface Instantiation
//-------------------------------------------------------------------
virtual vlm_memory_interface vlm_mon_vif;

//-------------------------------------------------------------------
// Agent Configuration Instantiation
//-------------------------------------------------------------------

//-------------------------------------------------------------------
// Coverage
//-------------------------------------------------------------------
//`include "vlm_vlm_covergroup.sv"

//-------------------------------------------------------------------
// Port Declaration
//-------------------------------------------------------------------
uvm_analysis_port #(vlm_sequence_item) rdvlm_analysis_port;
uvm_analysis_port #(vlm_sequence_item) wrvlm_analysis_port;

//-------------------------------------------------------------------
// Methods
//-------------------------------------------------------------------

// ------------------
// Standard UVM Methods
// ------------------
extern function        new(string name= "vlm_memory_monitor", uvm_component parent);
extern virtual function void build_phase(uvm_phase phase);
extern virtual function void connect_phase(uvm_phase phase);
extern virtual function void end_of_elaboration_phase(uvm_phase phase);
extern virtual function void start_of_simulation_phase(uvm_phase phase);
extern virtual task         run_phase(uvm_phase phase);
extern virtual function void extract_phase(uvm_phase phase);
extern virtual function void check_phase(uvm_phase phase);
extern virtual function void report_phase(uvm_phase phase);
extern virtual function void final_phase(uvm_phase phase);

// ------------------
// User Defined APIs
// ------------------
extern task monitor_signals();


// ------------------
// UVM Factory Registration
// ------------------
`uvm_component_utils_begin(vlm_memory_monitor)
// ------------------
// Add field configurations
// ------------------
`uvm_field_int(vlm_agent_id, UVM_ALL_ON)
// ------------------
`uvm_component_utils_end

endclass :vlm_memory_monitor


//-------------------------------------------------------------------
// Function: new
//
//-------------------------------------------------------------------

function vlm_memory_monitor::new(string name = "vlm_memory_monitor", uvm_component parent);
  super.new(name, parent);

  if ($test$plusargs("file_debug")) begin
    vlm_rtl_fp = $fopen(filename, "w");
  end

endfunction :new


//-------------------------------------------------------------------
// Function: build_phase
//
// Create and configure of testbench structure
//-------------------------------------------------------------------

function void vlm_memory_monitor::build_phase(uvm_phase phase);
  super.build_phase(phase);
  `uvm_info(get_type_name(), "In build_phase...!!", UVM_DEBUG);

  // ------------------
  // Port Construction
  // ------------------
  rdvlm_analysis_port = new("vlm_read___analysis_port", this);
  wrvlm_analysis_port = new("vlm_write___analysis_port", this);

  // ------------------
  // Get configuration
  // ------------------

  // ------------------
  // Construct children
  // ------------------

  // ------------------
  // Configure children
  // ------------------

endfunction: build_phase


//-------------------------------------------------------------------
// Function: connect_phase
//
// Establish cross-component connections
//-------------------------------------------------------------------

function void vlm_memory_monitor::connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  `uvm_info(get_type_name(), "In connect_phase...!!", UVM_DEBUG);
endfunction: connect_phase


//-------------------------------------------------------------------
// Task: run_phase
//
// Stimulate the DUT
//-------------------------------------------------------------------

task vlm_memory_monitor::run_phase(uvm_phase phase);
  super.run_phase(phase);
  `uvm_info(get_type_name(), "In run_phase...!!", UVM_DEBUG);
  monitor_signals();
endtask: run_phase


//-------------------------------------------------------------------
// Function: end_of_elaboration_phase
//
// Fine-tune the testbench
//-------------------------------------------------------------------

function void vlm_memory_monitor::end_of_elaboration_phase(uvm_phase phase);
  super.end_of_elaboration_phase(phase);
  `uvm_info(get_type_name(), "In end_of_elaboration_phase...!!", UVM_DEBUG);
endfunction: end_of_elaboration_phase


//-------------------------------------------------------------------
// Function: start_of_simulation_phase
//
// Get ready for DUT to be simulated
//-------------------------------------------------------------------

function void vlm_memory_monitor::start_of_simulation_phase(uvm_phase phase);
  super.start_of_simulation_phase(phase);
  `uvm_info(get_type_name(), "In start_of_simulation_phase...!!", UVM_DEBUG);
endfunction: start_of_simulation_phase


//-------------------------------------------------------------------
// Function: extract_phase
//
// Extract data from different points of the verification environment
//-------------------------------------------------------------------

function void vlm_memory_monitor::extract_phase(uvm_phase phase);
  super.extract_phase(phase);
  `uvm_info(get_type_name(), "In extract_phase...!!", UVM_DEBUG);
endfunction: extract_phase


//-------------------------------------------------------------------
// Function: check_phase
//
// Check for any unexpected conditions in the verification environment
//-------------------------------------------------------------------

function void vlm_memory_monitor::check_phase(uvm_phase phase);
  super.check_phase(phase);
  `uvm_info(get_type_name(), "In check_phase...!!", UVM_DEBUG);
endfunction: check_phase


//-------------------------------------------------------------------
// Function: report_phase
//
// Report results of the test
//-------------------------------------------------------------------

function void vlm_memory_monitor::report_phase(uvm_phase phase);
  super.report_phase(phase);
  `uvm_info(get_type_name(), "In report phase...!!", UVM_DEBUG);
endfunction: report_phase


//-------------------------------------------------------------------
// Function: final_phase
//
// Tie up loose ends. All Simulation activities are done.
//
// Closing files, Ending co-simulation engines etc.
//-------------------------------------------------------------------

function void vlm_memory_monitor::final_phase(uvm_phase phase);
  super.final_phase(phase);
  `uvm_info(get_type_name(), "In final_phase...!!", UVM_DEBUG);
endfunction: final_phase


//-------------------------------------------------------------------
// User Defined
// Task: monitor_signals
//
// Monitor VLM sequence items.
//-------------------------------------------------------------------

task vlm_memory_monitor::monitor_signals();
  wait (vlm_mon_vif.rst_n === 1);

  fork

    // read
    while(1) begin
      vlm_memory_sequence_item vlm_read_trans;

      @(vlm_mon_vif.mon_cb iff (|vlm_mon_vif.mon_cb.vlm_rvld) === 1'b1);
      `uvm_info(get_type_name(), $sformatf("monitor %0dth vlm_read_trans", read_trans_cnt), UVM_LOW)

      vlm_read_trans = vlm_memory_sequence_item::type_id::create($sformatf("rtl_vlm_read_trans[%0d]", write_trans_cnt));

      vlm_read_trans.vlm_read = 1'b1;
      for (int idx=0; idx<16; idx++) begin
        vlm_read_trans.vlm_bken[idx] = vlm_mon_vif.mon_cb.vlm_rvld[idx];
        vlm_read_trans.vlm_addr[idx] = vlm_mon_vif.mon_cb.vlm_raddr[idx];
      end

      fork
        begin

          repeat(RPORT_DLY) @(vlm_mon_vif.mon_cb);

          for (int idx=0; idx<16; idx++) begin
            vlm_read_trans.vlm_data[idx] = vlm_mon_vif.mon_cb.vlm_rdata[idx];
            vlm_read_trans.vlm_strb[idx] = '1;
          end

          if ($test$plusargs("file_debug")) begin
            vlm_read_trans.write_file(vlm_rtl_fp);
          end

          rdvlm_analysis_port.write(vlm_read_trans);
        end
      join_none

      read_trans_cnt++;
      trans_cnt++;

    end

    // write
    while(1) begin
      vlm_memory_sequence_item vlm_write_trans;

      @(vlm_mon_vif.mon_cb iff (|vlm_mon_vif.mon_cb.vlm_wvld) === 1'b1);
      `uvm_info(get_type_name(), $sformatf("monitor %0dth vlm_write_trans", write_trans_cnt), UVM_LOW)
      vlm_write_trans = vlm_memory_sequence_item::type_id::create($sformatf("rtl_vlm_write_trans[%0d]", write_trans_cnt));

      vlm_write_trans.vlm_read = 1'b0;
      for (int idx=0; idx<16; idx++) begin
        vlm_write_trans.vlm_bken[idx] = vlm_mon_vif.mon_cb.vlm_wvld[idx];
        vlm_write_trans.vlm_addr[idx] = vlm_mon_vif.mon_cb.vlm_waddr[idx];
        vlm_write_trans.vlm_strb[idx] = vlm_mon_vif.mon_cb.vlm_wstrb[idx];
        vlm_write_trans.vlm_data[idx] = vlm_mon_vif.mon_cb.vlm_wdata[idx];
      end

      if ($test$plusargs("file_debug")) begin
        vlm_write_trans.write_file(vlm_rtl_fp);
      end

      wrvlm_analysis_port.write(vlm_write_trans);
      write_trans_cnt++;
      trans_cnt++;
    end
  join

endtask: monitor_signals

`endif //INC_vlm_memory_monitor_SV