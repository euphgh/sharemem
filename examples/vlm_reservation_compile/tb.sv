`timescale 1ns/1ps

package vlm_reservation_compile_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"

  `include "vlm_reservation_types.svh"
  `include "vlm_reservation_agent_config.svh"
  `include "vlm_reservation_scheduler.svh"
  `include "vlm_reservation_checker.svh"
  `include "vlm_reservation_coverage.svh"
  `include "vlm_reservation_monitor.svh"
  `include "vlm_reservation_agent.svh"

  `include "vlm_memory_sequence_item.svh"
  `include "vlm_memory_slv_agent_config.svh"
  `include "vlm_memory_monitor.svh"
  `include "vlm_memory_slv_driver.svh"
  `include "vlm_memory_slv_sequencer.svh"
  `include "vlm_memory_slv_agent.svh"

  //----------------------------------------------------------------------------
  // @brief Builds reservation and memory agents connected to interfaces from tb.
  //
  // This test only proves UVM construction and elaboration. It does not raise
  // an objection, drive requests, or require the DUT shell to produce behavior.
  //----------------------------------------------------------------------------
  class vlm_reservation_compile_test extends uvm_test;

    // Interface configuration passed to the reservation agent.
    vlm_reservation_agent_config reservation_cfg;

    // Activation policy passed to the VLM memory slave agent.
    vlm_memory_slv_agent_config memory_cfg;

    // Reservation agent whose complete child hierarchy is compiled.
    vlm_reservation_agent reservation_agent;

    // VLM memory slave agent whose complete child hierarchy is compiled.
    vlm_memory_slv_agent memory_agent;

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
    // @brief Retrieves interfaces and constructs both VLM agents.
    //
    // @param phase UVM build phase used for configuration and construction.
    // @post Both agents receive their required configuration and interfaces.
    //--------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      reservation_cfg = vlm_reservation_agent_config::type_id::create("reservation_cfg");
      memory_cfg      = vlm_memory_slv_agent_config::type_id::create("memory_cfg");

      if (!uvm_config_db#(virtual vlm_reservation_interface)::get(this, "", "reservation_vif",
                                                                 reservation_cfg.reservation_vif)) begin
        `uvm_fatal("COMPILE_NO_RESERVATION_VIF", "compile test requires reservation_vif")
      end

      if (!uvm_config_db#(virtual vlm_memory_interface)::get(this, "", "memory_vif",
                                                            reservation_cfg.memory_vif)) begin
        `uvm_fatal("COMPILE_NO_MEMORY_VIF", "compile test requires memory_vif")
      end

      uvm_config_db#(vlm_reservation_agent_config)::set(this, "reservation_agent", "cfg", reservation_cfg);
      uvm_config_db#(vlm_memory_slv_agent_config)::set(this, "memory_agent", "cfg", memory_cfg);
      uvm_config_db#(virtual vlm_memory_interface)::set(this, "memory_agent", "memory_vif", reservation_cfg.memory_vif);

      reservation_agent = vlm_reservation_agent::type_id::create("reservation_agent", this);
      memory_agent      = vlm_memory_slv_agent::type_id::create("memory_agent", this);
    endfunction

    `uvm_component_utils(vlm_reservation_compile_test)

  endclass : vlm_reservation_compile_test

endpackage : vlm_reservation_compile_test_pkg

module tb;
  import uvm_pkg::*;
  import shm_util_package::*;
  import vlm_reservation_compile_test_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  // Shared clock service used by monitor, checker, and scheduler.
  clk_if clk_vif (
      .clk(clk)
  );

  // Reservation interface connecting DUT requests and agent-driven busy.
  vlm_reservation_interface reservation_vif(clk, rst_n);

  // MEM interface exposing DUT requests to the reservation monitor.
  vlm_memory_interface memory_vif(clk, rst_n);

  always #5ns clk = ~clk;

  logic [BANK_N-1:0]         mem_rvld         ;
  logic [BANK_N-1:0][BADDR_W-1:0] mem_raddr   ;
  logic [BANK_N-1:0][255:0]  mem_rdata        ;
  logic [BANK_N-1:0]         mem_wvld         ;
  logic [BANK_N-1:0][BADDR_W-1:0] mem_waddr   ;
  logic [BANK_N-1:0][31:0]   mem_wstrb        ;
  logic [BANK_N-1:0][255:0]  mem_wdata        ;

    //BANK REQUEST IO
  logic [VTAB_D-1:0][3:0]    vlm_wbusy        ;
  logic [VTAB_D-1:0][3:0]    vlm_rbusy        ;
  logic [BANK_N-1:0][1:0]    vlm_wreq         ;
  logic [BANK_N-1:0][1:0][BADDR_W-1:0] vlm_waddr ;
  logic [BANK_N-1:0][1:0][$clog2(VTAB_D)-1:0] vlm_wdly ;
  logic [BANK_N-1:0]         vlm_rreq         ;
  logic [BANK_N-1:0][BADDR_W-1:0] vlm_raddr     ;
  logic [BANK_N-1:0][$clog2(VTAB_D)-1:0] vlm_rdly;

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
      .creq_tmsk  ('0),
      .creq_base  ('0),
      .creq_offs  ('0),
      .creq_vdat  ('0),
      .vack_done  (),
      .vack_id    (),
      .mack_done  (),
      .mack_id    (),
      .mem_rvld   (mem_rvld),
      .mem_raddr  (mem_raddr),
      .mem_rdata  (mem_rdata),
      .mem_wvld   (mem_wvld),
      .mem_waddr  (mem_waddr),
      .mem_wstrb  (mem_wstrb),
      .mem_wdata  (mem_wdata),
      .vlm_wbusy  (vlm_wbusy),
      .vlm_rbusy  (vlm_rbusy),
      .vlm_wreq   (vlm_wreq),
      .vlm_waddr  (vlm_waddr),
      .vlm_wdly   (vlm_wdly),
      .vlm_rreq   (vlm_rreq),
      .vlm_raddr  (vlm_raddr),
      .vlm_rdly   (vlm_rdly)
  );

  always @(*) begin
    memory_vif.rvld = mem_rvld;
    memory_vif.raddr = mem_raddr;
    mem_rdata = memory_vif.rdata; 
    memory_vif.wvld = mem_wvld;
    memory_vif.waddr = mem_waddr;
    memory_vif.wstrb = mem_wstrb;
    memory_vif.wdata = mem_wdata;

    vlm_wbusy = reservation_vif.wbusy; 
    vlm_rbusy = reservation_vif.rbusy; 

    reservation_vif.wreq = vlm_wreq;
    reservation_vif.waddr = vlm_waddr;
    reservation_vif.wdly = vlm_wdly;
    reservation_vif.rreq = vlm_rreq;
    reservation_vif.raddr = vlm_raddr;
    reservation_vif.rdly = vlm_rdly;
  end

  initial begin
    uvm_config_db#(virtual clk_if)::set(null, "uvm_test_top.reservation_agent.*", "clk_vif", clk_vif);
    uvm_config_db#(virtual vlm_reservation_interface)::set(null, "uvm_test_top", "reservation_vif",
                                                          reservation_vif);
    uvm_config_db#(virtual vlm_memory_interface)::set(null, "uvm_test_top", "memory_vif", memory_vif);
    run_test("vlm_reservation_compile_test");
  end

endmodule : tb
