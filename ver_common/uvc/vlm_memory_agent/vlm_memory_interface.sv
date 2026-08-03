interface vlm_memory_interface(
  input logic clk,
  input logic rst_n
);

import shm_util_package::BANK_N;
import shm_util_package::BADDR_W;
import shm_util_package::VTAB_D;

logic   [BANK_N-1:0]               rvld  ;
logic   [BANK_N-1:0][BADDR_W-1:0]  raddr ;
logic   [BANK_N-1:0][255:0]        rdata ;

logic   [BANK_N-1:0]               wvld  ;
logic   [BANK_N-1:0][BADDR_W-1:0]  waddr ;
logic   [BANK_N-1:0][ 31:0]        wstrb ;
logic   [BANK_N-1:0][255:0]        wdata ;

clocking mon_cb @(posedge clk);
  input  rvld  ;
  input  raddr ;
  input  rdata ;

  input  wvld  ;
  input  waddr ;
  input  wstrb ;
  input  wdata ;
endclocking

clocking slv_cb @(posedge clk);
  input  rvld  ;
  input  raddr ;
  output rdata ;

  input  wvld  ;
  input  waddr ;
  input  wstrb ;
  input  wdata ;
endclocking

endinterface: vlm_memory_interface
