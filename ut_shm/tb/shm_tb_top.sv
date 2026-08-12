module shm_tb_top;

  import uvm_pkg::*;
  import shm_util_package::*;
  import shm_test_package::*;

  logic clk;
  logic rst_n;

  shmins_interface shmins_intf (
      .clk   (clk),
      .rst_n (rst_n)
  );

  vlm_interface vlm_intf (
      .clk   (clk),
      .rst_n (rst_n)
  );

  clk_if clock_intf (
      .clk (clk)
  );

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
  ) DUT (
      .clk        (clk),
      .rst_n      (rst_n),

      .creq_vld   (shmins_intf.creq_vld),
      .creq_rls   (shmins_intf.creq_rls),
      .creq_id    (shmins_intf.creq_id),
      .creq_wpid  (shmins_intf.creq_wpid),
      .creq_wpnum (shmins_intf.creq_wpnum),
      .creq_prio  (shmins_intf.creq_prio),
      .creq_len   (shmins_intf.creq_len),
      .creq_typ   (shmins_intf.creq_typ),
      .creq_vaddr (shmins_intf.creq_vaddr),
      .creq_tmsk  (shmins_intf.creq_tmsk),
      .creq_vmsk  (shmins_intf.creq_vmsk),
      .creq_base  (shmins_intf.creq_base),
      .creq_offs  (shmins_intf.creq_offs),
      .creq_vdat  (shmins_intf.creq_vdat),
      .vack_done  (shmins_intf.vack_done),
      .vack_id    (shmins_intf.vack_id),
      .mack_done  (shmins_intf.mack_done),
      .mack_id    (shmins_intf.mack_id),

      .mem_rvld   (vlm_intf.rvld),
      .mem_raddr  (vlm_intf.mem_raddr),
      .mem_rdata  (vlm_intf.rdata),
      .mem_wvld   (vlm_intf.wvld),
      .mem_waddr  (vlm_intf.mem_waddr),
      .mem_wstrb  (vlm_intf.wstrb),
      .mem_wdata  (vlm_intf.wdata),

      .vlm_rbusy  (vlm_intf.rbusy),
      .vlm_wbusy  (vlm_intf.wbusy),
      .vlm_rreq   (vlm_intf.rreq),
      .vlm_raddr  (vlm_intf.raddr),
      .vlm_rdly   (vlm_intf.rdly),
      .vlm_rgid   (vlm_intf.rgid),
      .vlm_wreq   (vlm_intf.wreq),
      .vlm_waddr  (vlm_intf.waddr),
      .vlm_wdly   (vlm_intf.wdly),
      .vlm_wgid   (vlm_intf.wgid)
  );

  `include "shm_ut_connect.svh"

  initial begin
    clk = 1'b0;
    forever #0.5 clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  initial begin
    run_test();
  end

endmodule : shm_tb_top
