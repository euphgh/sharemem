interface vlm_reservation_interface (
  input logic clk,
  input logic rst_n
);

import shm_util_package::BANK_N;
import shm_util_package::BADDR_W;
import shm_util_package::VTAB_D;
import shm_util_package::VLM_SUB_BANK_N;
import shm_util_package::WRITE_PORT_N;

// Busy tables are driven by the reservation slave. Entry [delay][sub_bank]
// describes whether that direction is occupied at the corresponding future
// cycle. The sub-bank ID is the reservation address field address[6:5].
logic [VTAB_D-1:0][VLM_SUB_BANK_N-1:0] rbusy;
logic [VTAB_D-1:0][VLM_SUB_BANK_N-1:0] wbusy;

// One read reservation port per physical BANK.
logic [BANK_N-1:0] rreq;
logic [BANK_N-1:0][BADDR_W-1:0] raddr;
logic [BANK_N-1:0][$clog2(VTAB_D)-1:0] rdly;

// Two write reservation ports per physical BANK.
logic [BANK_N-1:0][WRITE_PORT_N-1:0] wreq;
logic [BANK_N-1:0][WRITE_PORT_N-1:0][BADDR_W-1:0] waddr;
logic [BANK_N-1:0][WRITE_PORT_N-1:0][$clog2(VTAB_D)-1:0] wdly;

// Passive monitor view: sample the complete interface atomically.
clocking mon_cb @(posedge clk);
  input rst_n;
  input rbusy;
  input wbusy;

  input rreq;
  input raddr;
  input rdly;

  input wreq;
  input waddr;
  input wdly;
endclocking

// Reservation-slave view: observe requests and drive the busy tables.
clocking slv_cb @(posedge clk);
  output rbusy;
  output wbusy;

  input  rreq;
  input  raddr;
  input  rdly;

  input  wreq;
  input  waddr;
  input  wdly;
endclocking

endinterface: vlm_reservation_interface
