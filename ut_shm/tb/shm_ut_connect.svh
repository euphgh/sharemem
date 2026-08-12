`ifndef INC_SHM_UT_CONNECT_SVH
`define INC_SHM_UT_CONNECT_SVH

initial begin
  uvm_config_db#(virtual shmins_interface)::set(
      null, "*", "shmins_vif", shmins_intf);
  uvm_config_db#(virtual vlm_interface)::set(
      null, "*", "vlm_vif", vlm_intf);
  uvm_config_db#(virtual clk_if)::set(
      null, "*", "clk_vif", clock_intf);
end

`endif // INC_SHM_UT_CONNECT_SVH
