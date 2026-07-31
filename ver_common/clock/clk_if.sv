//------------------------------------------------------------------------------
// @brief Provides one repository-wide simulation clock and cycle counter.
//
// Components that require a cycle number obtain the same virtual clk_if
// through UVM Config DB. The counter starts at zero, advances at every positive
// clock edge, and intentionally does not depend on any reset signal.
//------------------------------------------------------------------------------
interface clk_if (
    input wire clk
);

  // Monotonically increasing number of observed positive clock edges.
  longint unsigned cycle_count = 0;

  // Advance the shared cycle count after every positive clock edge.
  always @(posedge clk) begin
    cycle_count <= cycle_count + 1'b1;
  end

  //----------------------------------------------------------------------------
  // @brief Waits for a requested number of positive clock edges.
  //
  // @param count Number of positive clock edges to wait; zero returns
  //              immediately.
  // @post The requested number of positive clock edges has occurred unless
  //       simulation was terminated.
  //----------------------------------------------------------------------------
  task automatic wait_cycles(input int unsigned count);
    repeat (count) @(posedge clk);
  endtask

endinterface : clk_if
