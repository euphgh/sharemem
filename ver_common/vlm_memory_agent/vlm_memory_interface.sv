import shm_config_pkg::BANK_N;
import shm_config_pkg::BADDR_W;
import shm_config_pkg::VTAB_D;

interface vlm_memory_interface(
  input logic clk,
  input logic rst_n
);

logic   [BANK_N-1:0]               rvld  ;
logic   [BANK_N-1:0][BADDR_W-1:0]  raddr ;
logic   [BANK_N-1:0][255:0]        rdata ;

logic   [BANK_N-1:0]               wvld  ;
logic   [BANK_N-1:0][BADDR_W-1:0]  waddr ;
logic   [BANK_N-1:0][ 31:0]        wstrb ;
logic   [BANK_N-1:0][255:0]        wdata ;

clocking mst_cb @(posedge clk);
  output rvld  ;
  output raddr ;
  input  rdata ;

  output wvld  ;
  output waddr ;
  output wstrb ;
  output wdata ;
endclocking

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
