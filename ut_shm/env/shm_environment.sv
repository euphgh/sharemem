`ifndef INC_SHM_ENVIRONMENT_SV
`define INC_SHM_ENVIRONMENT_SV

class shm_environment extends uvm_env;

    shm_reference    shm_ref;
    shm_scoreboard   shm_scb;
    shmins_mst_agent    shmins_mst_agt;
    vlm_slv_agent       vlm_slv_agt;
    shm_environment_config   shm_environment_cfg;

    int unsigned shm_env_id;
    string env_inst_name, agent_inst_name, mon_inst_name, scb_inst_name, ref_inst_name;

    extern function        new(string name = "shm_environment", uvm_component parent);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);
 `uvm_component_utils_begin(shm_environment)
 `uvm_field_int(shm_env_id, UVM_ALL_ON)
  // -----------------
 `uvm_component_utils_end
endclass: shm_environment

function shm_environment::new(string name = "shm_environment", uvm_component parent);
 super.new(name, parent);
endfunction: new

function void shm_environment::build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info(get_type_name(), "In build_phase...!", UVM_DEBUG);

    if (!uvm_config_db#(shm_environment_config)::get(this, "", "shm_environment_config", shm_environment_cfg))
    begin
        `uvm_error(get_type_name(), "shm_environment_config object is not found in config db!");
    end
    else
    begin
        shm_environment_cfg.print();
    end

    $sformat(scb_inst_name, "shm_scb");
    if (shm_environment_cfg.shm_is_active) begin
        shm_scb = shm_scoreboard::type_id::create(scb_inst_name, this);
        uvm_config_db#(shm_scoreboard)::set(null, "*", "shm_scb", shm_scb);
    end

    $sformat(ref_inst_name, "shm_ref");
    if (shm_environment_cfg.shm_is_active) begin
        shm_ref = shm_reference::type_id::create(ref_inst_name, this);
        uvm_config_db#(shm_reference)::set(null, "*", "shm_ref", shm_ref);
    end

    $sformat(agent_inst_name, "shmins_mst_agt");
    if (shm_environment_cfg.shminus_mst_agent_cfg.is_active) shmins_mst_agt = shmins_mst_agent::type_id::create(agent_inst_name, this);
    $sformat(agent_inst_name, "vlm_slv_agt");
    if (shm_environment_cfg.vlm_slv_agent_cfg.is_active) vlm_slv_agt = vlm_slv_agent::type_id::create(agent_inst_name, this);

    if (!uvm_config_db#(virtual shmins_interface)::get(.cntxt(this), .inst_name(""), .field_name($sprintf("shmins_mst_vif")), .value(shmins_mst_agt.shminus_mst_vif))) `uvm_error(get_type_name(), "Unable to find the shmins interface!")
    if (!uvm_config_db#(virtual vlm_interface)::get(.cntxt(this), .inst_name(""), .field_name($sprintf("vlm_slv_vif")), .value(vlm_slv_agt.vlm_slv_vif))) `uvm_error(get_type_name(), "Unable to find the vlm interface!")

    $sformat(scb_inst_name, "*shm_scb*");
    uvm_config_db#(shm_environment_config)::set(this, scb_inst_name, "shm_environment_config", shm_environment_cfg);

    $sformat(ref_inst_name, "*shm_ref*");
    uvm_config_db#(shm_environment_config)::set(this, ref_inst_name, "shm_environment_config", shm_environment_cfg);

    $sformat(agent_inst_name, "*shmins_mst_agt*");
    uvm_config_db#(shmins_mst_agent_config)::set(this, agent_inst_name, "shmins_mst_agent_config", shm_environment_cfg.shminus_mst_agent_cfg);
    $sformat(agent_inst_name, "*vlm_slv_agt*");
    uvm_config_db#(vlm_slv_agent_config)::set(this, agent_inst_name, "vlm_slv_agent_config", shm_environment_cfg.vlm_slv_agent_cfg);

endfunction: build_phase

function void shm_environment::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    `uvm_info(get_type_name(), "In connect_phase...!!", UVM_DEBUG);

    if (shm_environment_cfg.shm_is_active && shm_environment_cfg.shminus_mst_agent_cfg.shminus_mon_is_active) begin
        shmins_mst_agt.shminus_mon.shminus_analysis_port.connect(shm_ref.shminus_analysis_export);
    end

    if (shm_environment_cfg.shm_is_active && shm_environment_cfg.vlm_slv_agent_cfg.vlm_mon_is_active) begin
        vlm_slv_agt.vlm_mon.wrvlm_analysis_port.connect(shm_scb.rtl_wrvlm_analysis_export);
        vlm_slv_agt.vlm_slv_drv.mem_port.connect(shm_scb.mem_imp);
    end

    if (shm_environment_cfg.shm_is_active) begin
        shm_ref.wdata_ass_arr_port.connect(shm_scb.ref_wrvlm_analysis_export);
    end

endfunction: connect_phase

`endif //INC_SHM_ENVIRONMENT_SV
