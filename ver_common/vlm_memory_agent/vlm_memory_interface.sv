import shm_config_pkg::BANK_N;
import shm_config_pkg::BADDR_W;
import shm_config_pkg::VTAB_D;

interface vlm_memory_interface ();

logic                   clk     ;
logic                   rst_n   ;

logic   [BANK_N-1:0]               vlm_memory_rvld  ;
logic   [BANK_N-1:0][BADDR_W-1:0]  vlm_memory_raddr ;
logic   [BANK_N-1:0][255:0]        vlm_memory_rdata ;

logic   [BANK_N-1:0]               vlm_memory_wvld  ;
logic   [BANK_N-1:0][BADDR_W-1:0]  vlm_memory_waddr ;
logic   [BANK_N-1:0][ 31:0]        vlm_memory_wstrb ;
logic   [BANK_N-1:0][255:0]        vlm_memory_wdata ;

clocking mst_cb @(posedge clk);
  output vlm_memory_rvld  ;
  output vlm_memory_raddr ;
  input  vlm_memory_rdata ;

  output vlm_memory_wvld  ;
  output vlm_memory_waddr ;
  output vlm_memory_wstrb ;
  output vlm_memory_wdata ;
endclocking

clocking mon_cb @(posedge clk);
  input  vlm_memory_rvld  ;
  input  vlm_memory_raddr ;
  input  vlm_memory_rdata ;

  input  vlm_memory_wvld  ;
  input  vlm_memory_waddr ;
  input  vlm_memory_wstrb ;
  input  vlm_memory_wdata ;
endclocking

clocking slv_cb @(posedge clk);
  input  vlm_memory_rvld  ;
  input  vlm_memory_raddr ;
  output vlm_memory_rdata ;

  input  vlm_memory_wvld  ;
  input  vlm_memory_waddr ;
  input  vlm_memory_wstrb ;
  input  vlm_memory_wdata ;
endclocking

endinterface: vlm_memory_interface
