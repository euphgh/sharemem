package shm_seq_package;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import shm_seq_item_package::*;
    import shm_env_package::*;
    `include "shmins_mst_sequence.sv"
    `include "shmins_unit_sequence.sv"
    `include "vlm_slv_sequence.sv"

endpackage : shm_seq_package
