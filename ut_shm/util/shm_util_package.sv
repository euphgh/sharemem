package shm_util_package;
    `include "bit_rt_range.svh"

    //-------------------------------------------------------------------------
    // @brief Returns an uppercase copy of a SystemVerilog string.
    //
    // @param value Source string; the input object is not modified.
    // @return A copy with ASCII lowercase letters converted to uppercase.
    //-------------------------------------------------------------------------
    function automatic string str_toupper(input string value);
        string result = value;

        for (int index = 0; index < result.len(); index++) begin
            if (result[index] >= "a" && result[index] <= "z") begin
                result[index] = result[index] - "a" + "A";
            end
        end

        return result;
    endfunction : str_toupper

    parameter WARP_N          = 8                     ;
    parameter GID_N           = 2                     ;
    parameter WARP_PER_GID    = WARP_N / GID_N        ;
    parameter OTF_N           = 4                     ;
    parameter PRIO_W          = 4                     ;
    parameter FFD_CYC         = 1                     ; //feedforward cycle
    parameter RPORT_DLY       = 4                     ;
    parameter VTAB_D          = 6+RPORT_DLY-FFD_CYC+1+1+1; // current default: 12
    parameter ID_W            = 8                     ;
    parameter THD_N           = 16                    ;
    parameter BANK_N          = THD_N                 ;
    parameter WARP_STEP       = 12 * 1024             ; // 12KB for one vlm
    parameter MADDR_W         = 21                    ; //total shm addr space :8KB*16t*4warp=20bit,for 8KB expand,give 21
    parameter BADDR_W         = MADDR_W-$clog2(BANK_N)-$clog2(GID_N); // per-gid bank address space
    parameter VEC_W           = 512;
    parameter VEC_BYTE_N      = (VEC_W / 8);
    parameter VLM_DATA_BIT_W  = 256                   ;
    parameter VLM_DATA_BYTE_W = (VLM_DATA_BIT_W / 8)   ;
    parameter VLM_SUB_BANK_N  = 4;
    parameter WRITE_PORT_N    = 2;
    parameter PHYSICAL_BANK_N = BANK_N * GID_N;

    typedef bit [$clog2(BANK_N)-1:0] shm_bank_id_t;
    typedef bit [$clog2(WARP_N)-1:0] shm_warp_id_t;
    typedef bit [$clog2(WARP_STEP)-1:0] shm_warp_laddr_t;
    typedef bit [$clog2(GID_N)-1:0] shm_gid_t;
    typedef bit [BADDR_W-1:0] shm_baddr_t;

    // Repository-wide monotonically increasing simulation-clock count.
    typedef longint unsigned shm_cycle_t;

    // Monitor-owned identity used to correlate one creq across components.
    typedef longint unsigned shm_transaction_uid_t;

    //-------------------------------------------------------------------------
    // @brief Logical SHM byte address before the downstream bank organization.
    //-------------------------------------------------------------------------
    typedef struct packed {
        shm_bank_id_t    bank_id;
        shm_warp_id_t    warp_id;
        shm_warp_laddr_t laddr;
    } shm_logical_addr_t;

    //-------------------------------------------------------------------------
    // @brief Physical SHM byte address used by the dual-gid VLM interface.
    //-------------------------------------------------------------------------
    typedef struct packed {
        shm_bank_id_t bank_id;
        shm_gid_t     gid;
        shm_baddr_t   baddr;
    } shm_physical_addr_t;

    //-------------------------------------------------------------------------
    // @brief Converts an absolute-warp logical address to the dual-gid layout.
    //
    // @param logical_addr Address expressed as bank, absolute warp, and laddr.
    // @param physical_addr Converted bank, gid, and gid-local BADDR.
    // @return 1 when all logical fields are in range; otherwise 0.
    //-------------------------------------------------------------------------
    function automatic bit logical_to_physical_addr(input shm_logical_addr_t logical_addr,
                                                     output shm_physical_addr_t physical_addr);
        longint unsigned baddr_value;

        physical_addr = '0;
        if (int'(logical_addr.bank_id) >= BANK_N || int'(logical_addr.warp_id) >= WARP_N ||
            int'(logical_addr.laddr) >= WARP_STEP) begin
            return 1'b0;
        end

        baddr_value = longint'((int'(logical_addr.warp_id) % WARP_PER_GID) * WARP_STEP) +
                      longint'(logical_addr.laddr);
        if (baddr_value >= (longint'(1) << BADDR_W)) begin
            return 1'b0;
        end

        physical_addr.bank_id = logical_addr.bank_id;
        physical_addr.gid = shm_gid_t'(int'(logical_addr.warp_id) / WARP_PER_GID);
        physical_addr.baddr = shm_baddr_t'(baddr_value);
        return 1'b1;
    endfunction : logical_to_physical_addr

    //-------------------------------------------------------------------------
    // @brief Forms a unique scalar key for one physical SHM byte.
    //
    // @param physical_addr Physical bank, gid, and byte address.
    // @return Packed scalar suitable for associative-array collision checks.
    //-------------------------------------------------------------------------
    function automatic longint unsigned physical_byte_key(input shm_physical_addr_t physical_addr);
        return (longint'(physical_addr.bank_id) << ($clog2(GID_N) + BADDR_W)) |
               (longint'(physical_addr.gid) << BADDR_W) | longint'(physical_addr.baddr);
    endfunction : physical_byte_key

    //-------------------------------------------------------------------------
    // @brief Flattens a bank and gid for fixed-array storage utilities.
    //
    // @param bank_id Logical bank index.
    // @param gid Physical low/high bank selector.
    // @return Index in the range zero through BANK_N*GID_N-1.
    //-------------------------------------------------------------------------
    function automatic int unsigned physical_bank_index(input int unsigned bank_id, input int unsigned gid);
        return bank_id * GID_N + gid;
    endfunction : physical_bank_index
endpackage : shm_util_package
