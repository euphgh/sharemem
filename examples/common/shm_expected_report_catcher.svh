`ifndef INC_SHM_EXPECTED_REPORT_CATCHER_SVH
`define INC_SHM_EXPECTED_REPORT_CATCHER_SVH

//------------------------------------------------------------------------------
// @brief Demotes only explicitly declared negative-test reports and counts them.
//------------------------------------------------------------------------------
class shm_expected_report_catcher extends uvm_report_catcher;
  protected int unsigned expected_count[string];
  protected int unsigned observed_count[string];

  //----------------------------------------------------------------------------
  // @brief Constructs an empty expected-report table.
  //
  // @param name UVM object instance name.
  //----------------------------------------------------------------------------
  function new(string name = "shm_expected_report_catcher");
    super.new(name);
  endfunction : new

  //----------------------------------------------------------------------------
  // @brief Declares the exact allowed count for one error or fatal report ID.
  //
  // @param report_id Stable UVM report identifier.
  // @param count Exact number of reports expected by the test.
  //----------------------------------------------------------------------------
  function void expect_report(string report_id, int unsigned count = 1);
    expected_count[report_id] = count;
    observed_count[report_id] = 0;
  endfunction : expect_report

  //----------------------------------------------------------------------------
  // @brief Demotes a declared error/fatal while leaving all other reports intact.
  //
  // @return THROW so the report continues with its possibly demoted severity.
  //----------------------------------------------------------------------------
  virtual function action_e catch();
    string report_id = get_id();

    if ((get_severity() == UVM_ERROR || get_severity() == UVM_FATAL) && expected_count.exists(report_id)) begin
      observed_count[report_id]++;
      set_severity(UVM_INFO);
    end
    return THROW;
  endfunction : catch

  //----------------------------------------------------------------------------
  // @brief Checks that every declared report occurred exactly as requested.
  //
  // @return 1 when all expected and observed counts are equal; otherwise 0.
  //----------------------------------------------------------------------------
  function bit expectations_met();
    foreach (expected_count[report_id]) begin
      if (observed_count[report_id] != expected_count[report_id]) begin
        return 1'b0;
      end
    end
    return 1'b1;
  endfunction : expectations_met
endclass : shm_expected_report_catcher

`endif // INC_SHM_EXPECTED_REPORT_CATCHER_SVH
