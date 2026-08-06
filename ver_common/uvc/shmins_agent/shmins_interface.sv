interface shmins_interface (
  input logic clk,
  input logic rst_n
);

  import shm_util_package::*;

  // Instruction
  logic                              creq_vld ;
  logic                              creq_rls ;
  logic        [ID_W-1:0]            creq_id  ;
  logic        [$clog2(WARP_N)-1:0]  creq_wpid ;
  logic        [$clog2(WARP_N+1)-1:0] creq_wpnum ;
  logic        [THD_N-1:0][3:0]      creq_prio ; //thd prio
  logic        [THD_N-1:0][7:0]      creq_len  ; //element length:0~32
  logic        [19:0]                creq_typ  ; //[15:14]:space[1:0]+[13:10]:ilv_size+[9]:ack_en+[8:7]typ+[6:3]atyp+[2:1]dwidth+[0:0]rw
  logic        [VADDR_W-1:0]         creq_vaddr;
  logic        [THD_N-1:0]                 creq_tmsk ; //thread mask
  logic        [THD_N-1:0][VEC_BYTE_N-1:0] creq_vmsk ; //element mask
  logic        [47:0]                creq_base ; //byte addr
  logic        [THD_N-1:0][VEC_W-1:0] creq_offs ; //rs2_val,element mode only support 16 element;vector only have 1 addr
  logic        [THD_N-1:0][VEC_BYTE_N-1:0][7:0] creq_vdat ;

  logic                              vack_done ;
  logic        [ID_W-1:0]            vack_id  ;
  logic                              mack_done ;
  logic        [ID_W-1:0]            mack_id  ;

  clocking mst_cb @(posedge clk);
    output creq_vld   ;
    input  creq_rls   ;
    output creq_id    ;
    output creq_wpid  ;
    output creq_wpnum ;
    output creq_prio  ;
    output creq_len   ;
    output creq_typ   ;
    output creq_vaddr ;
    output creq_vmsk  ;
    output creq_base  ;
    output creq_offs  ;
    output creq_vdat  ;

    input  vack_done  ;
    input  vack_id    ;
    input  mack_done  ;
    input  mack_id    ;
  endclocking

  clocking mon_cb @(posedge clk);
    input  creq_vld   ;
    input  creq_rls   ;
    input  creq_id    ;
    input  creq_wpid  ;
    input  creq_wpnum ;
    input  creq_prio  ;
    input  creq_len   ;
    input  creq_typ   ;
    input  creq_vaddr ;
    input  creq_vmsk  ;
    input  creq_base  ;
    input  creq_offs  ;
    input  creq_vdat  ;

    input  vack_done  ;
    input  vack_id    ;
    input  mack_done  ;
    input  mack_id    ;
  endclocking

endinterface: shmins_interface
