`timescale 1ns/1ps

package vlm_reservation_compile_test_pkg;
  import uvm_pkg::*;
  import vlm_reservation_pkg::*;

  `include "uvm_macros.svh"

  //----------------------------------------------------------------------------
  // @brief Builds one reservation agent connected to interfaces from tb.
  //
  // This test only proves UVM construction and elaboration. It does not raise
  // an objection, drive requests, or require the DUT shell to produce behavior.
  //----------------------------------------------------------------------------
  class vlm_reservation_compile_test extends uvm_test;

    // Interface-only configuration passed to the reservation agent.
    vlm_reservation_agent_config cfg;

    // Reservation agent whose complete child hierarchy is elaborated.
    vlm_reservation_agent agent;

    //--------------------------------------------------------------------------
    // @brief Constructs the compile-only UVM test.
    //
    // @param name   UVM component instance name.
    // @param parent Parent component that owns this test.
    //--------------------------------------------------------------------------
    function new(string name = "vlm_reservation_compile_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    //--------------------------------------------------------------------------
    // @brief Retrieves both interfaces and constructs the reservation agent.
    //
    // @param phase UVM build phase used for configuration and construction.
    // @post The agent receives one config containing both connected interfaces.
    //--------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      cfg = vlm_reservation_agent_config::type_id::create("cfg");

      if (!uvm_config_db#(virtual vlm_reservation_interface)::get(this, "", "reservation_vif",
                                                                 cfg.reservation_vif)) begin
        `uvm_fatal("COMPILE_NO_RESERVATION_VIF", "compile test requires reservation_vif")
      end

      if (!uvm_config_db#(virtual vlm_memory_interface)::get(this, "", "memory_vif", cfg.memory_vif)) begin
        `uvm_fatal("COMPILE_NO_MEMORY_VIF", "compile test requires memory_vif")
      end

      uvm_config_db#(vlm_reservation_agent_config)::set(this, "agent", "cfg", cfg);
      agent = vlm_reservation_agent::type_id::create("agent", this);
    endfunction

    `uvm_component_utils(vlm_reservation_compile_test)

  endclass : vlm_reservation_compile_test

endpackage : vlm_reservation_compile_test_pkg

module tb;
  import uvm_pkg::*;
  import shm_config_pkg::*;
  import vlm_reservation_compile_test_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  // Shared clock service used by monitor, checker, and scheduler.
  clk_if clk_vif (
      .clk(clk)
  );

  // Reservation interface connecting DUT requests and agent-driven busy.
  vlm_reservation_interface reservation_vif();

  // MEM interface exposing DUT requests to the reservation monitor.
  vlm_memory_interface memory_vif();

  always #5ns clk = ~clk;

  assign reservation_vif.clk   = clk;
  assign reservation_vif.rst_n = rst_n;
  assign memory_vif.clk        = clk;
  assign memory_vif.rst_n      = rst_n;

  // No memory slave is needed for compile-only elaboration.
  assign memory_vif.rdata = '0;

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
      .VADDR_W   (VADDR_W),
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
      .creq_base  ('0),
      .creq_offs  ('0),
      .creq_vdat  ('0),
      .vack_done  (),
      .vack_id    (),
      .mack_done  (),
      .mack_id    (),
      .mem_rvld   (memory_vif.rvld),
      .mem_raddr  (memory_vif.raddr),
      .mem_rdata  (memory_vif.rdata),
      .mem_wvld   (memory_vif.wvld),
      .mem_waddr  (memory_vif.waddr),
      .mem_wstrb  (memory_vif.wstrb),
      .mem_wdata  (memory_vif.wdata),
      .vlm_wbusy  (reservation_vif.wbusy),
      .vlm_rbusy  (reservation_vif.rbusy),
      .vlm_wreq   (reservation_vif.wreq),
      .vlm_waddr  (reservation_vif.waddr),
      .vlm_wdly   (reservation_vif.wdly),
      .vlm_rreq   (reservation_vif.rreq),
      .vlm_raddr  (reservation_vif.raddr),
      .vlm_rdly   (reservation_vif.rdly)
  );

  initial begin
    uvm_config_db#(virtual clk_if)::set(null, "uvm_test_top.agent.*", "clk_vif", clk_vif);
    uvm_config_db#(virtual vlm_reservation_interface)::set(null, "uvm_test_top", "reservation_vif",
                                                          reservation_vif);
    uvm_config_db#(virtual vlm_memory_interface)::set(null, "uvm_test_top", "memory_vif", memory_vif);
    run_test("vlm_reservation_compile_test");
  end

endmodule : tb
