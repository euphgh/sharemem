`ifndef INC_SHM_ENVIRONMENT_SVH
`define INC_SHM_ENVIRONMENT_SVH

class shm_environment extends uvm_env;

    shm_reference  shm_ref;
    shm_scoreboard shm_scb;

    shmins_mst_agent       shmins_mst_agt;
    vlm_agent              vlm_agt;

    shm_environment_config shm_environment_cfg;

    virtual shmins_interface          shmins_vif;
    virtual vlm_interface             vlm_vif;
    virtual clk_if                    clk_vif;

    int unsigned shm_env_id;

    extern function new(string name = "shm_environment", uvm_component parent = null);
    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);

    `uvm_component_utils_begin(shm_environment)
        `uvm_field_int(shm_env_id, UVM_ALL_ON)
    `uvm_component_utils_end

endclass : shm_environment

function shm_environment::new(string name = "shm_environment", uvm_component parent = null);
    super.new(name, parent);
endfunction : new

function void shm_environment::build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(shm_environment_config)::get(
            this, "", "shm_environment_config", shm_environment_cfg) ||
        shm_environment_cfg == null) begin
        `uvm_fatal("SHM_ENV_NO_CFG", "shm_environment requires 'shm_environment_config'")
    end

    if (shm_environment_cfg.shmins_mst_agent_cfg == null ||
        shm_environment_cfg.vlm_reservation_agent_cfg == null) begin
        `uvm_fatal("SHM_ENV_CFG_NOT_INITIALIZED",
                   "shm_environment_config.init() must create both agent configs")
    end

    if (!uvm_config_db#(virtual shmins_interface)::get(
            this, "", "shmins_vif", shmins_vif)) begin
        `uvm_fatal("SHM_ENV_NO_SHMINS_VIF", "shm_environment requires virtual interface 'shmins_vif'")
    end

    if (!uvm_config_db#(virtual vlm_interface)::get(this, "", "vlm_vif", vlm_vif)) begin
        `uvm_fatal("SHM_ENV_NO_VLM_VIF", "shm_environment requires virtual interface 'vlm_vif'")
    end

    if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", clk_vif)) begin
        `uvm_fatal("SHM_ENV_NO_CLK_VIF", "shm_environment requires virtual interface 'clk_vif'")
    end

    shm_environment_cfg.vlm_reservation_agent_cfg.vif = vlm_vif;

    uvm_config_db#(shmins_mst_agent_config)::set(
        this, "shmins_mst_agt", "cfg", shm_environment_cfg.shmins_mst_agent_cfg);
    uvm_config_db#(virtual shmins_interface)::set(
        this, "shmins_mst_agt", "shmins_vif", shmins_vif);

    uvm_config_db#(vlm_reservation_agent_config)::set(
        this, "vlm_agt", "cfg", shm_environment_cfg.vlm_reservation_agent_cfg);
    uvm_config_db#(virtual clk_if)::set(
        this, "vlm_agt.*", "clk_vif", clk_vif);

    shmins_mst_agt = shmins_mst_agent::type_id::create("shmins_mst_agt", this);
    vlm_agt = vlm_agent::type_id::create("vlm_agt", this);

    if (shm_environment_cfg.shm_is_active == UVM_ACTIVE) begin
        uvm_config_db#(shm_environment_config)::set(
            this, "shm_ref", "shm_environment_config", shm_environment_cfg);
        uvm_config_db#(shm_environment_config)::set(
            this, "shm_scb", "shm_environment_config", shm_environment_cfg);

        shm_ref = shm_reference::type_id::create("shm_ref", this);
        shm_scb = shm_scoreboard::type_id::create("shm_scb", this);
    end
endfunction : build_phase

function void shm_environment::connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (shm_ref != null && shmins_mst_agt.monitor != null) begin
        shmins_mst_agt.monitor.shmins_analysis_port.connect(shm_ref.shmins_analysis_export);
    end

    if (shm_scb != null && vlm_agt != null) begin
        vlm_agt.write_analysis_port.connect(shm_scb.rtl_wrvlm_analysis_export);
    end

    if (shm_scb != null && vlm_agt != null) begin
        vlm_agt.mem_port.connect(shm_scb.mem_imp);
    end

    if (shm_ref != null && shm_scb != null) begin
        shm_ref.wdata_ass_arr_port.connect(shm_scb.ref_wrvlm_analysis_export);
    end
endfunction : connect_phase

`endif // INC_SHM_ENVIRONMENT_SVH
