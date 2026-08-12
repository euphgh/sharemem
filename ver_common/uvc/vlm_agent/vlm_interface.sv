interface vlm_interface (
  input logic clk,
  input logic rst_n
);

  import shm_util_package::*;

  logic [VTAB_D-1:0][GID_N-1:0][VLM_SUB_BANK_N-1:0] rbusy;
  logic [VTAB_D-1:0][GID_N-1:0][VLM_SUB_BANK_N-1:0] wbusy;

  logic [BANK_N-1:0] rreq;
  logic [BANK_N-1:0][BADDR_W-1:0] raddr;
  logic [BANK_N-1:0][$clog2(VTAB_D)-1:0] rdly;
  logic [BANK_N-1:0] rgid;

  logic [BANK_N-1:0][WRITE_PORT_N-1:0] wreq;
  logic [BANK_N-1:0][WRITE_PORT_N-1:0][BADDR_W-1:0] waddr;
  logic [BANK_N-1:0][WRITE_PORT_N-1:0][$clog2(VTAB_D)-1:0] wdly;
  logic [BANK_N-1:0][WRITE_PORT_N-1:0] wgid;

  logic [BANK_N-1:0] rvld;
  logic [BANK_N-1:0][BADDR_W-1:0] mem_raddr;
  logic [BANK_N-1:0][VLM_DATA_BIT_W-1:0] rdata;

  logic [BANK_N-1:0] wvld;
  logic [BANK_N-1:0][BADDR_W-1:0] mem_waddr;
  logic [BANK_N-1:0][VLM_DATA_BYTE_W-1:0] wstrb;
  logic [BANK_N-1:0][VLM_DATA_BIT_W-1:0] wdata;

  // Passive view used to atomically sample reservation and MEM signals.
  clocking mon_cb @(posedge clk);
    input rst_n;
    input rbusy, wbusy;
    input rreq, raddr, rdly, rgid;
    input wreq, waddr, wdly, wgid;
    input rvld, mem_raddr, rdata;
    input wvld, mem_waddr, wstrb, wdata;
  endclocking

  // Active slave view used to drive busy and fixed-latency read data.
  clocking slv_cb @(posedge clk);
    output rbusy, wbusy;
    output rdata;
    input rreq, raddr, rdly, rgid;
    input wreq, waddr, wdly, wgid;
    input rvld, mem_raddr;
    input wvld, mem_waddr, wstrb, wdata;
  endclocking

endinterface : vlm_interface
