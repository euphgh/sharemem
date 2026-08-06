module shmins_random_benchmark_tb;
  import uvm_pkg::*;
  import shmins_random_benchmark_pkg::*;

  initial begin
    run_test("shmins_random_benchmark_test");
  end
endmodule : shmins_random_benchmark_tb
