module RpuShmTop
#(
    parameter WARP_STEP   = 12 * 1024          , //WARP VLM STEP,BYTE ADDR
    parameter WARP_N      = 8                  ,
    parameter OTF_N       = 4                  ,
    parameter PRIO_W      = 4                  ,
    parameter FFD_CYC     = 1                  , //feedforward cycle
    parameter RPORT_DLY   = 4                  ,
    parameter VTAB_D      = 6+RPORT_DLY-FFD_CYC+1+1+1, //12
    parameter ID_W        = 8                  ,
    parameter THD_N       = 16                 ,
    parameter BANK_N      = 16                 ,
    parameter VADDR_W     = 14                 , //vlm addr space
    parameter MADDR_W     = 21                 , //total shm addr space :8KB*16t*4warp=20bit,for 8KB expand,give 21
    parameter BADDR_W     = MADDR_W-$clog2(BANK_N) //perbank shm addr space
)(
    //clk && rst
    input                             clk              ,
    input                             rst_n            ,

    //INS IO
    input  logic                      creq_vld         ,
    output logic                      creq_rls         ,
    input  logic [ID_W-1:0]           creq_id          ,
    input  logic [$clog2(WARP_N)-1:0] creq_wpid        ,
    input  logic [$clog2(WARP_N+1)-1:0] creq_wpnum     ,
    input  logic [THD_N-1:0][3:0]     creq_prio        ,
    input  logic [THD_N-1:0][7:0]     creq_len         ,
    input  logic [19:0]               creq_typ         ,
    input  logic [VADDR_W-1:0]        creq_vaddr       ,
    input  logic [THD_N-1:0][63:0]    creq_vmsk        ,
    input  logic [THD_N-1:0]          creq_tmsk        ,       
    input  logic [47:0]               creq_base        ,
    input  logic [THD_N-1:0][511:0]   creq_offs        , 
    input  logic [THD_N-1:0][511:0]   creq_vdat        ,

    output logic                      vack_done        ,
    output logic [ID_W-1:0]           vack_id          ,

    output logic                      mack_done        ,
    output logic [ID_W-1:0]           mack_id          ,

    //MEMORY IO
    output logic [BANK_N-1:0]         mem_rvld         ,
    output logic [BANK_N-1:0][BADDR_W-1:0] mem_raddr   ,
    input  logic [BANK_N-1:0][255:0]  mem_rdata        ,

    output logic [BANK_N-1:0]         mem_wvld         ,
    output logic [BANK_N-1:0][BADDR_W-1:0] mem_waddr   ,
    output logic [BANK_N-1:0][31:0]   mem_wstrb        ,
    output logic [BANK_N-1:0][255:0]  mem_wdata        ,

    //BANK REQUEST IO
    input  logic [VTAB_D-1:0][3:0]    vlm_wbusy        ,
    input  logic [VTAB_D-1:0][3:0]    vlm_rbusy        ,

    output logic [BANK_N-1:0][1:0]    vlm_wreq         ,
    output logic [BANK_N-1:0][1:0][BADDR_W-1:0] vlm_waddr ,
    output logic [BANK_N-1:0][1:0][$clog2(VTAB_D)-1:0] vlm_wdly ,

    output logic [BANK_N-1:0]         vlm_rreq         ,
    output logic [BANK_N-1:0][BADDR_W-1:0] vlm_raddr     ,
    output logic [BANK_N-1:0][$clog2(VTAB_D)-1:0] vlm_rdly
);
endmodule
