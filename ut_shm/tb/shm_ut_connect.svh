`ifndef INC_SHM_UT_CONNECT_SVH
`define INC_SHM_UT_CONNECT_SVH

initial begin
  uvm_config_db#(virtual shmins_interface)::set(
      null, "*", "shmins_vif", shmins_intf);
  uvm_config_db#(virtual vlm_memory_interface)::set(
      null, "*", "memory_vif", vlm_memory_intf);
  uvm_config_db#(virtual vlm_reservation_interface)::set(
      null, "*", "reservation_vif", vlm_reservation_intf);
  uvm_config_db#(virtual clk_if)::set(
      null, "*", "clk_vif", clock_intf);
end

`endif // INC_SHM_UT_CONNECT_SVH
