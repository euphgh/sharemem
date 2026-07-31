always @(*) begin
    shmins_mst_intf.clk    = clk;
    shmins_mst_intf.rst_n  = rst_n;

    shmins_mst_intf.creq_rls  = tb_creq_rls    ;
    shmins_mst_intf.vack_done = tb_vack_done   ;
    shmins_mst_intf.vack_id   = tb_vack_id     ;
    shmins_mst_intf.mack_done = tb_mack_done   ;
    shmins_mst_intf.mack_id   = tb_mack_id     ;

    tb_creq_vld   = shmins_mst_intf.creq_vld   ;
    tb_creq_id    = shmins_mst_intf.creq_id    ;
    tb_creq_wpid  = shmins_mst_intf.creq_wpid  ;
    tb_creq_wpnum = shmins_mst_intf.creq_wpnum ;
    tb_creq_prio  = shmins_mst_intf.creq_prio  ;
    tb_creq_len   = shmins_mst_intf.creq_len   ;
    tb_creq_typ   = shmins_mst_intf.creq_typ   ;
    tb_creq_vaddr = shmins_mst_intf.creq_vaddr ;
    tb_creq_vmsk  = shmins_mst_intf.creq_vmsk  ;
    tb_creq_base  = shmins_mst_intf.creq_base  ;
    tb_creq_offs  = shmins_mst_intf.creq_offs  ;
    tb_creq_vdat  = shmins_mst_intf.creq_vdat  ;
end

always @(*) begin
    vlm_slv_intf.clk    = clk;
    vlm_slv_intf.rst_n  = rst_n;

    vlm_slv_intf.vlm_rvld  = tb_mem_rvld  ;
    vlm_slv_intf.vlm_raddr = tb_mem_raddr ;
    vlm_slv_intf.vlm_wvld  = tb_mem_wvld  ;
    vlm_slv_intf.vlm_waddr = tb_mem_waddr ;
    vlm_slv_intf.vlm_wstrb = tb_mem_wstrb ;
    vlm_slv_intf.vlm_wdata = tb_mem_wdata ;

    tb_mem_rdata = vlm_slv_intf.vlm_rdata  ;
    tb_vlm_rbusy = vlm_slv_intf.vlm_rbusy  ;
    tb_vlm_wbusy = vlm_slv_intf.vlm_wbusy  ;
end

initial begin
    uvm_config_db#(virtual shmins_interface)::set(null, "", $sprintf("shmins_mst_vif"), shmins_mst_intf);
end
initial begin
    uvm_config_db#(virtual vlm_interface)::set(null, "", $sprintf("vlm_slv_vif"), vlm_slv_intf);
end