import shm_config_pkg::BANK_N;
import shm_config_pkg::BADDR_W;
import shm_config_pkg::VTAB_D;
import shm_config_pkg::VLM_SUB_BANK_N;
import shm_config_pkg::WRITE_PORT_N;

interface vlm_reservation_interface (
  input logic clk, 
  input logic rst_n
);

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

// DUT/master view: observe busy and drive reservations.
clocking mst_cb @(posedge clk);
  input  rbusy;
  input  wbusy;

  output rreq;
  output raddr;
  output rdly;

  output wreq;
  output waddr;
  output wdly;
endclocking

// Passive monitor view: sample the complete interface atomically.
clocking mon_cb @(posedge clk);
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
