package shm_config_pkg;
    parameter WARP_N          = 8                     ;
    parameter OTF_N           = 4                     ;
    parameter PRIO_W          = 4                     ;
    parameter FFD_CYC         = 1                     ; //feedforward cycle
    parameter RPORT_DLY       = 4                     ;
    parameter VTAB_D          = 6+RPORT_DLY-FFD_CYC+1+1+1; //11
    parameter ID_W            = 8                     ;
    parameter THD_N           = 16                    ;
    parameter BANK_N          = THD_N                 ;
    parameter VADDR_W         = 14                    ; // vlm addr space
    parameter WARP_STEP       = 12 * 1024             ; // 12KB for one vlm
    parameter MADDR_W         = 21                    ; //total shm addr space :8KB*16t*4warp=20bit,for 8KB expand,give 21
    parameter BADDR_W         = MADDR_W-$clog2(BANK_N); //perbank shm addr space
    parameter VEC_W           = 512;
    parameter VEC_BYTE_N      = (VEC_W / 8);
    parameter VLM_DATA_BIT_W  = 256                   ;
    parameter VLM_DATA_BYTE_W = (VLM_DATA_BIT_W / 8)   ;
    parameter VLM_SUB_BANK_N  = 4;
    parameter WRITE_PORT_N    = 2;
endpackage
