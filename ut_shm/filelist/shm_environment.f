$RPU_DIR/RhCommon/usr_ref.sv
//-f $RPU_DIR/RpuCommon/RpuCommon.f

# Sub-Environment List Files
+incdir+$AXI_VIP_DIR/src/sverilog/vcs
+incdir+$AXI_VIP_DIR/src/include/sverilog
+incdir+$AXI_VIP_DIR/src/sverilog/vcs
+incdir+$AXI_VIP_DIR/include/sverilog
$AXI_VIP_DIR/include/sverilog/svt_axi.uvm.pkg
$AXI_VIP_DIR/include/sverilog/svt_mem.uvm.pkg

# define parameter
$TB_DIR/util/shm_util_package.sv

# Environment Directory
+incdir+$TB_DIR
+incdir+$TB_DIR/env
+incdir+$TB_DIR/util

# Environment Scoreboard Files Directory
+incdir+$TB_DIR/env/scoreboards

# Agents Directory
# AUTO_GEN_FILELIST_AGENT_BEGIN
+incdir+$VER_CMN/uvc/shmins_agent
+incdir+$VER_CMN/uvc/vlm_agent
# AUTO_GEN_FILELIST_AGENT_END

# Agents Sequence Directory
# AUTO_GEN_FILELIST_AGENT_SEQ_BEGIN
+incdir+$VER_CMN/rpu_inst
+incdir+$VER_CMN/uvc/sequences
+incdir+$VER_CMN/uvc/shmins_agent/sequences
+incdir+$VER_CMN/uvc/vlm_agent/sequences
# AUTO_GEN_FILELIST_AGENT_SEQ_END

# Environment Checkers Directory

# Test Directory
+incdir+$TB_DIR/env
+incdir+$TB_DIR/env/scoreboards
+incdir+$TB_DIR/env/collection/libs
+incdir+$TB_DIR/env/tests
$TB_DIR/env/collection/libs/collection_pkg.sv

# Env Sequence Item Package
$TB_DIR/env/shm_seq_item_package.sv

$VER_CMN/uvc/shmins_agent/shmins_interface.sv
$VER_CMN/uvc/vlm_agent/vlm_interface.sv

# Env Package
$TB_DIR/env/shm_env_package.sv

# Env Sequence Package
$TB_DIR/env/shm_seq_package.sv

# Env Test Package
$TB_DIR/tests/shm_test_package.sv
