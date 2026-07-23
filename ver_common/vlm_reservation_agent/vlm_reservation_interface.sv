import shm_config_pkg::BANK_N;
import shm_config_pkg::BADDR_W;
import shm_config_pkg::VTAB_D;
import shm_config_pkg::VLM_SUPER_BANK_N;
import shm_config_pkg::VLM_RESERVATION_WRITE_PORT_N;

interface vlm_reservation_interface ();

logic clk;
logic rst_n;

// Busy tables are driven by the reservation slave. Entry [delay][super_bank]
// describes whether that direction is occupied at the corresponding future
// cycle. The super-bank ID is bank_id[1:0].
logic [VTAB_D-1:0][VLM_SUPER_BANK_N-1:0] vlm_reservation_rbusy;
logic [VTAB_D-1:0][VLM_SUPER_BANK_N-1:0] vlm_reservation_wbusy;

// One read reservation port per physical BANK.
logic [BANK_N-1:0] vlm_reservation_rreq;
logic [BANK_N-1:0][BADDR_W-1:0] vlm_reservation_raddr;
logic [BANK_N-1:0][$clog2(VTAB_D)-1:0] vlm_reservation_rdly;

// Two write reservation ports per physical BANK.
logic [BANK_N-1:0][VLM_RESERVATION_WRITE_PORT_N-1:0]
    vlm_reservation_wreq;
logic [BANK_N-1:0][VLM_RESERVATION_WRITE_PORT_N-1:0][BADDR_W-1:0]
    vlm_reservation_waddr;
logic [BANK_N-1:0][VLM_RESERVATION_WRITE_PORT_N-1:0]
      [$clog2(VTAB_D)-1:0] vlm_reservation_wdly;

// DUT/master view: observe busy and drive reservations.
clocking mst_cb @(posedge clk);
  input  vlm_reservation_rbusy;
  input  vlm_reservation_wbusy;

  output vlm_reservation_rreq;
  output vlm_reservation_raddr;
  output vlm_reservation_rdly;

  output vlm_reservation_wreq;
  output vlm_reservation_waddr;
  output vlm_reservation_wdly;
endclocking

// Passive monitor view: sample the complete interface atomically.
clocking mon_cb @(posedge clk);
  input vlm_reservation_rbusy;
  input vlm_reservation_wbusy;

  input vlm_reservation_rreq;
  input vlm_reservation_raddr;
  input vlm_reservation_rdly;

  input vlm_reservation_wreq;
  input vlm_reservation_waddr;
  input vlm_reservation_wdly;
endclocking

// Reservation-slave view: observe requests and drive the busy tables.
clocking slv_cb @(posedge clk);
  output vlm_reservation_rbusy;
  output vlm_reservation_wbusy;

  input  vlm_reservation_rreq;
  input  vlm_reservation_raddr;
  input  vlm_reservation_rdly;

  input  vlm_reservation_wreq;
  input  vlm_reservation_waddr;
  input  vlm_reservation_wdly;
endclocking

endinterface: vlm_reservation_interface
