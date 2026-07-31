+libext+.v+.sv
-y $SNPS_DC_HOME/dw/sim_ver
+incdir+$SNPS_DC_HOME/dw/sim_ver

-f $RPU_DIR/RhCommon/phy/vlib/sim.f
-f $RPU_DIR/RpuCommon/dwfc.f
-f $RPU_DIR/RhCommon/base/rhc_base.f
-f $RPU_DIR/RhCommon/fusa/rhc_fusa.f
-f $RPU_DIR/RpuCommon/RpuCommon.f

-f $RPU_DIR/RpuTop/src/RpuShm/RpuShm.f
$RPU_DIR/RpuTop/src/RpuShm/RpuShmTop.sv