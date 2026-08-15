`timescale 1ns/1ps

package vlm_compile_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
  `include "vlm_memory_sequence_item.svh"
  `include "vlm_reservation_types.svh"
  `include "vlm_reservation_external_busy_policy.svh"
  `include "vlm_reservation_agent_config.svh"
  `include "vlm_reservation_scheduler.svh"
  `include "vlm_reservation_checker.svh"
  `include "vlm_reservation_coverage.svh"
  `include "vlm_reservation_monitor.svh"
  `include "vlm_reservation_agent.svh"
  `include "vlm_agent.svh"

  //----------------------------------------------------------------------------
  // @brief Builds the unified VLM agent against an empty DUT shell.
  //----------------------------------------------------------------------------
  class vlm_compile_test extends uvm_test;
    vlm_reservation_agent_config cfg;
    vlm_agent agent;

    //------------------------------------------------------------------------
    // @brief Constructs the compile-only test.
    //
    // @param name UVM component instance name.
    // @param parent Parent component that owns this test.
    //------------------------------------------------------------------------
    function new(string name = "vlm_compile_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    //------------------------------------------------------------------------
    // @brief Retrieves the unified interface and builds one VLM agent.
    //
    // @param phase UVM build phase.
    //------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = vlm_reservation_agent_config::type_id::create("cfg");
      if (!uvm_config_db#(virtual vlm_interface)::get(this, "", "vlm_vif", cfg.vif)) begin
        `uvm_fatal("COMPILE_NO_VLM_VIF", "compile test requires vlm_vif")
      end
      uvm_config_db#(vlm_reservation_agent_config)::set(this, "agent", "cfg", cfg);
      agent = vlm_agent::type_id::create("agent", this);
    endfunction : build_phase

    `uvm_component_utils(vlm_compile_test)
  endclass : vlm_compile_test

endpackage : vlm_compile_test_pkg

module tb;
  import uvm_pkg::*;
  import shm_util_package::*;
  import vlm_compile_test_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  clk_if clk_vif(.clk(clk));
  vlm_interface vlm_vif(.clk(clk), .rst_n(rst_n));

  RpuShmTop #(
      .WARP_STEP (WARP_STEP),
      .WARP_N    (WARP_N),
      .OTF_N     (OTF_N),
      .PRIO_W    (PRIO_W),
      .FFD_CYC   (FFD_CYC),
      .RPORT_DLY (RPORT_DLY),
      .VTAB_D    (VTAB_D),
      .ID_W      (ID_W),
      .THD_N     (THD_N),
      .BANK_N    (BANK_N),
      .MADDR_W   (MADDR_W),
      .BADDR_W   (BADDR_W)
  ) dut (
      .clk        (clk),
      .rst_n      (rst_n),
      .creq_vld   (1'b0),
      .creq_rls   (),
      .creq_id    ('0),
      .creq_wpid  ('0),
      .creq_wpnum ('0),
      .creq_prio  ('0),
      .creq_len   ('0),
      .creq_typ   ('0),
      .creq_vaddr ('0),
      .creq_vmsk  ('0),
      .creq_tmsk  ('0),
      .creq_base  ('0),
      .creq_offs  ('0),
      .creq_vdat  ('0),
      .vack_done  (),
      .vack_id    (),
      .mack_done  (),
      .mack_id    (),
      .mem_rvld   (vlm_vif.rvld),
      .mem_raddr  (vlm_vif.mem_raddr),
      .mem_rdata  (vlm_vif.rdata),
      .mem_wvld   (vlm_vif.wvld),
      .mem_waddr  (vlm_vif.mem_waddr),
      .mem_wstrb  (vlm_vif.wstrb),
      .mem_wdata  (vlm_vif.wdata),
      .vlm_wbusy  (vlm_vif.wbusy),
      .vlm_rbusy  (vlm_vif.rbusy),
      .vlm_wreq   (vlm_vif.wreq),
      .vlm_waddr  (vlm_vif.waddr),
      .vlm_wdly   (vlm_vif.wdly),
      .vlm_wgid   (vlm_vif.wgid),
      .vlm_rreq   (vlm_vif.rreq),
      .vlm_raddr  (vlm_vif.raddr),
      .vlm_rdly   (vlm_vif.rdly),
      .vlm_rgid   (vlm_vif.rgid)
  );

  always #5ns clk = ~clk;

  initial begin
    uvm_config_db#(virtual clk_if)::set(null, "uvm_test_top.agent.*", "clk_vif", clk_vif);
    uvm_config_db#(virtual vlm_interface)::set(null, "uvm_test_top", "vlm_vif", vlm_vif);
    run_test("vlm_compile_test");
  end

endmodule : tb
