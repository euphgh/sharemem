`ifndef INC_VLM_MEMORY_SLV_DRIVER_SVH
`define INC_VLM_MEMORY_SLV_DRIVER_SVH

//------------------------------------------------------------------------------
// @brief Returns fixed-latency read data on the VLM memory interface.
//
// Converts each observed MEM read request into a vlm_memory_sequence_item,
// sends it to the memory model through mem_port, and drives the returned data
// after RPORT_DLY cycles. It does not drive reservation busy or check MEM data.
//------------------------------------------------------------------------------
class vlm_memory_slv_driver extends uvm_driver #(vlm_memory_sequence_item);

  // VLM memory interface whose read-data signal is driven by this component.
  virtual vlm_memory_interface memory_vif;

  // Blocking transport port used to obtain read data from the memory model.
  uvm_tlm_b_transport_port #(vlm_memory_sequence_item) mem_port;

  //------------------------------------------------------------------------------
  // @brief Constructs the VLM memory slave driver and its transport port.
  //
  // @param name   UVM component instance name.
  // @param parent Parent component that owns this driver.
  //------------------------------------------------------------------------------
  extern function new(
      string        name = "vlm_memory_slv_driver",
      uvm_component parent = null);

  //------------------------------------------------------------------------------
  // @brief Resets read data, waits for reset release, and serves read requests.
  //
  // @param phase UVM run phase controlling the driver lifetime.
  //------------------------------------------------------------------------------
  extern virtual task main_phase(uvm_phase phase);

  //------------------------------------------------------------------------------
  // @brief Drives the MEM read-data output to a known reset value.
  //
  // @pre memory_vif has been assigned by the containing agent.
  // @post Every BANK read-data lane is zero.
  //------------------------------------------------------------------------------
  extern protected task reset_signals();

  //------------------------------------------------------------------------------
  // @brief Continuously converts MEM reads into fixed-latency responses.
  //
  // @pre Reset has been released and memory_vif is valid.
  //------------------------------------------------------------------------------
  extern protected task drive_signals();

  `uvm_component_utils(vlm_memory_slv_driver)

endclass : vlm_memory_slv_driver

function vlm_memory_slv_driver::new(
    string        name = "vlm_memory_slv_driver",
    uvm_component parent = null);
  super.new(name, parent);
  mem_port = new("mem_port", this);
endfunction : new

task vlm_memory_slv_driver::main_phase(uvm_phase phase);
  super.main_phase(phase);

  if (memory_vif == null) begin
    `uvm_fatal("VLM_MEMORY_NO_VIF", "vlm_memory_slv_driver requires memory_vif")
  end

  reset_signals();
  wait (memory_vif.rst_n === 1'b1);
  drive_signals();
endtask : main_phase

task vlm_memory_slv_driver::reset_signals();
  memory_vif.slv_cb.rdata <= '0;
endtask : reset_signals

task vlm_memory_slv_driver::drive_signals();
  forever begin
    @(memory_vif.slv_cb);

    if (|memory_vif.slv_cb.rvld) begin
      fork
        begin
          automatic vlm_memory_sequence_item transaction;
          automatic uvm_tlm_time delay = new("delay");

          transaction = vlm_memory_sequence_item::type_id::create("read_transaction");
          transaction.vlm_read = 1'b1;

          for (int unsigned bank = 0; bank < BANK_N; bank++) begin
            transaction.vlm_bken[bank] = memory_vif.slv_cb.rvld[bank];
            transaction.vlm_addr[bank] = memory_vif.slv_cb.raddr[bank];
          end

          mem_port.b_transport(transaction, delay);

          repeat (RPORT_DLY - 1) begin
            @(memory_vif.slv_cb);
          end

          for (int unsigned bank = 0; bank < BANK_N; bank++) begin
            memory_vif.slv_cb.rdata[bank] <= transaction.vlm_data[bank];
          end
        end
      join_none
    end
  end
endtask : drive_signals

`endif // INC_VLM_MEMORY_SLV_DRIVER_SVH
