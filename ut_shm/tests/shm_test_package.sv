package shm_test_package;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import shm_util_package::*;
    import shm_seq_item_package::*;
    import shm_seq_package::*;
    import shm_env_package::*;

    `include "shm_base_test.svh"
    `include "shm_unit_test.svh"
    `include "shm_directed_base_test.svh"
    `include "shm_dbank_wpid_boundary_test.svh"
    `include "shm_dbank_gid_isolation_test.svh"
    `include "shm_m2v_vaddr_boundary_test.svh"
    `include "shm_reservation_gid_ownership_test.svh"
    `include "shm_tmsk_directed_test.svh"
    `include "shm_vtrans_full_mask_test.svh"
endpackage : shm_test_package
