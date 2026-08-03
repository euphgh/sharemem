$RPU_DIR/RhCommon/usr_ref.sv
//-f $RPU_DIR/RpuCommon/RpuCommon.f

# Sub-Environment List Files
+incdir+$AXI_VIP_DIR/src/sverilog/vcs
+incdir+$AXI_VIP_DIR/src/include/sverilog
+incdir+$AXI_VIP_DIR/src/sverilog/vcs
+incdir+$AXI_VIP_DIR/include/sverilog
$AXI_VIP_DIR/include/sverilog/svt_axi.uvm.pkg
$AXI_VIP_DIR/include/sverilog/svt_mem.uvm.pkg

# Collection utility package
+incdir+$TB_DIR/util/sv-collection/libs
$TB_DIR/util/sv-collection/libs/collection_pkg.sv

# Shared parameters and utilities
+incdir+$TB_DIR/util
$TB_DIR/util/shm_util_package.sv

# Agents Directory
+incdir+$VER_CMN/uvc/clock
$VER_CMN/uvc/clock/clk_if.sv

+incdir+$VER_CMN/uvc/shmins_agent
+incdir+$VER_CMN/uvc/shmins_agent/sequence
$VER_CMN/uvc/shmins_agent/shmins_interface.sv

+incdir+$VER_CMN/uvc/vlm_memory_agent
$VER_CMN/uvc/vlm_memory_agent/vlm_memory_interface.sv

+incdir+$VER_CMN/uvc/vlm_reservation_agent
$VER_CMN/uvc/vlm_reservation_agent/vlm_reservation_interface.sv

# Environment Checkers Directory
+incdir+$TB_DIR/env
$TB_DIR/env/shm_seq_item_package.sv
$TB_DIR/env/shm_seq_package.sv
$TB_DIR/env/shm_env_package.sv

# Env Test Package
+incdir+$TB_DIR/tests
$TB_DIR/tests/shm_test_package.sv
