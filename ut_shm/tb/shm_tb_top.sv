module shm_tb_top();

// Including & Importing Required UVM Libraries
//---------------------------------------------------------------------
import uvm_pkg::*;
import RpuCommon::*;
import shm_util_package::*;

// Importing User Defined Packages
//---------------------------------------------------------------------

// Local Variables
//---------------------------------------------------------------------

// Event
//---------------------------------------------------------------------

// Clock Instantiation
//---------------------------------------------------------------------
reg clk;
reg rst_n;

// Interfaces Instantiation
//---------------------------------------------------------------------
//AUTO_GEN_INTERFACE_OBJECT_BEGIN
shmins_interface shmins_mst_intf();

//AUTO_GEN_INTERFACE_OBJECT_END
vlm_interface vlm_slv_intf();

    logic           tb_creq_vld             ;
    logic           tb_creq_rls             ;
    logic   [ID_W-1:0]          tb_creq_id              ;
    logic   [$clog2(WARP_N)-1:0] tb_creq_wpid            ;
    logic   [$clog2(WARP_N)-1:0] tb_creq_wpnum           ;
    logic   [THD_N-1:0][3:0]    tb_creq_prio             ;
    logic   [THD_N-1:0][7:0]    tb_creq_len              ;
    logic   [19:0]              tb_creq_type             ;
    logic   [VADDR_W-1:0]       tb_creq_vaddr            ;
    logic   [THD_N-1:0][VEC_BYTE_N-1:0] tb_creq_vmsk     ;
    logic   [47:0]              tb_creq_base             ;
    logic   [THD_N-1:0][VEC_W-1:0] tb_creq_offs          ;
    logic   [THD_N-1:0][VEC_BYTE_N-1:0][7:0] tb_creq_vdat ;
    
    logic           tb_vack_done            ;
    logic   [ID_W-1:0]          tb_vack_id              ;
    logic           tb_mack_done            ;
    logic   [ID_W-1:0]          tb_mack_id              ;
    //MEMORY IO
    logic   [BANK_N-1:0]                 tb_mem_rvld          ;
    logic   [BANK_N-1:0][BADDR_W-1:0]    tb_mem_raddr         ;
    logic   [BANK_N-1:0][255:0]          tb_mem_rdata         ;

    logic   [BANK_N-1:0]                 tb_mem_wvld          ;
    logic   [BANK_N-1:0][BADDR_W-1:0]    tb_mem_waddr         ;
    logic   [BANK_N-1:0][    31:0]       tb_mem_wstrb         ;
    logic   [BANK_N-1:0][255:0]          tb_mem_wdata         ;

    //BANK REQUEST IO
    logic   [VTAB_D-1:0][3:0]            tb_vlm_rbusy         ;
    logic   [VTAB_D-1:0][3:0]            tb_vlm_wbusy         ;

    logic   [BANK_N-1:0][1:0]            tb_vlm_wreq          ;
    logic   [BANK_N-1:0][1:0][BADDR_W-1:0] tb_vlm_waddr       ;
    logic   [BANK_N-1:0][1:0][$clog2(VTAB_D)-1:0] tb_vlm_wdly ;

    logic   [BANK_N-1:0]                 tb_vlm_rreq          ;
    logic   [BANK_N-1:0][BADDR_W-1:0]    tb_vlm_raddr         ;
    logic   [BANK_N-1:0][$clog2(VTAB_D)-1:0] tb_vlm_rdly      ;

    RpuShmTop DUT(
        .clk            (clk            ),
        .rst_n          (rst_n          ),
        .creq_vld       (tb_creq_vld    ),
        .creq_rls       (tb_creq_rls    ),
        .creq_id        (tb_creq_id     ),
        .creq_wpid      (tb_creq_wpid   ),
        .creq_wpnum     (tb_creq_wpnum  ),
        .creq_prio      (tb_creq_prio   ),
        .creq_len       (tb_creq_len    ),
        .creq_typ       (tb_creq_typ    ),
        .creq_vaddr     (tb_creq_vaddr  ),
        .creq_vmsk      (tb_creq_vmsk   ),
        .creq_base      (tb_creq_base   ),
        .creq_offs      (tb_creq_offs   ),
        .creq_vdat      (tb_creq_vdat   ),
        .vack_done      (tb_vack_done   ),
        .vack_id        (tb_vack_id     ),
        .mack_done      (tb_mack_done   ),
        .mack_id        (tb_mack_id     ),
        .vlm_rbusy      (tb_vlm_rbusy   ),
        .vlm_wbusy      (tb_vlm_wbusy   ),
        .vlm_wreq       (tb_vlm_wreq    ),
        .vlm_waddr      (tb_vlm_waddr   ),
        .vlm_wdly       (tb_vlm_wdly    ),
        .vlm_rreq       (tb_vlm_rreq    ),
        .vlm_raddr      (tb_vlm_raddr   ),
        .vlm_rdly       (tb_vlm_rdly    ),
        .mem_rvld       (tb_mem_rvld    ),
        .mem_raddr      (tb_mem_raddr   ),
        .mem_rdata      (tb_mem_rdata   ),
        .mem_wvld       (tb_mem_wvld    ),
        .mem_waddr      (tb_mem_waddr   ),
        .mem_wstrb      (tb_mem_wstrb   ),
        .mem_wdata      (tb_mem_wdata   )
    );

     `include "./shm_ut_connect.sv"

    initial begin
        run_test();
    end

    initial begin
        rst_n = 1'b0;
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
    end

    initial begin
        clck = 1'b0;
        forever #0.5 clk = ~clk;
    end
endmodule: shm_tb_top
