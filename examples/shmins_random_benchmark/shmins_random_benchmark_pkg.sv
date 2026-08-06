package shmins_random_benchmark_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
  `include "shmins_sequence_item.svh"

  import "DPI-C" pure function longint shmins_benchmark_monotonic_ns();

  //----------------------------------------------------------------------------
  // @brief Measures shmins_sequence_item randomization throughput.
  //
  // Selects a repeatable instruction/space profile, optionally disables the
  // two largest diagnostic constraint groups, and reports monotonic wall time
  // for the measured randomize loop. It does not drive a DUT or model creq.
  //----------------------------------------------------------------------------
  class shmins_random_benchmark_test extends uvm_test;
    // Number of randomize attempts included in the measured interval.
    int unsigned iterations = 10;

    // Number of unmeasured attempts used to warm up the solver.
    int unsigned warmup_iterations = 2;

    // Fixed branch selection used by each randomize attempt.
    string profile = "RANDOM";

    // Constraint subset used to isolate expensive address and uniqueness logic.
    string constraint_set = "ALL";

    // Reuses one object by default so object allocation is outside the result.
    bit reuse_item = 1'b1;

    // Suppresses post_randomize range warnings that would distort diagnostic runs.
    bit suppress_item_warnings = 1'b1;

    // Number of successful and failed measured randomize attempts.
    int unsigned success_count;
    int unsigned failure_count;

    // Changes with generated data so the measured result remains observable.
    longint unsigned checksum;

    //------------------------------------------------------------------------
    // @brief Constructs the benchmark UVM test.
    //
    // @param name   UVM component instance name.
    // @param parent Parent component; null when created as uvm_test_top.
    //------------------------------------------------------------------------
    extern function new(
        string        name = "shmins_random_benchmark_test",
        uvm_component parent = null);

    //------------------------------------------------------------------------
    // @brief Reads and validates benchmark plusargs.
    //
    // @param phase UVM build phase used to configure the test before execution.
    // @post Profile and constraint-set names are uppercase and supported.
    //------------------------------------------------------------------------
    extern virtual function void build_phase(uvm_phase phase);

    //------------------------------------------------------------------------
    // @brief Runs warmup and measured randomization loops.
    //
    // @param phase UVM run phase whose objection protects the benchmark loop.
    // @post A SHMINS_RANDOM_BENCH_RESULT line reports throughput and failures.
    //------------------------------------------------------------------------
    extern virtual task run_phase(uvm_phase phase);

    //------------------------------------------------------------------------
    // @brief Creates an item and applies the selected constraint subset.
    //
    // @param item_name Instance name used for debug and randomize diagnostics.
    // @return A configured transaction owned by the caller.
    //------------------------------------------------------------------------
    extern protected function shmins_sequence_item create_item(string item_name);

    //------------------------------------------------------------------------
    // @brief Randomizes one item using the selected fixed branch profile.
    //
    // @param item Transaction to randomize.
    // @return 1 when all active constraints have a solution; otherwise 0.
    //------------------------------------------------------------------------
    extern protected function bit randomize_item(shmins_sequence_item item);

    //------------------------------------------------------------------------
    // @brief Mixes selected randomized fields into the observable checksum.
    //
    // @param item Successfully randomized transaction to sample.
    //------------------------------------------------------------------------
    extern protected function void update_checksum(shmins_sequence_item item);

    `uvm_component_utils(shmins_random_benchmark_test)
  endclass : shmins_random_benchmark_test

  function shmins_random_benchmark_test::new(
      string name = "shmins_random_benchmark_test",
      uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  function void shmins_random_benchmark_test::build_phase(uvm_phase phase);
    int unsigned reuse_item_value;
    int unsigned suppress_item_warnings_value;

    super.build_phase(phase);

    reuse_item_value = reuse_item;
    suppress_item_warnings_value = suppress_item_warnings;
    void'($value$plusargs("BENCH_ITERATIONS=%d", iterations));
    void'($value$plusargs("BENCH_WARMUP=%d", warmup_iterations));
    void'($value$plusargs("BENCH_PROFILE=%s", profile));
    void'($value$plusargs("BENCH_CONSTRAINT_SET=%s", constraint_set));
    void'($value$plusargs("BENCH_REUSE_ITEM=%d", reuse_item_value));
    void'($value$plusargs("BENCH_SUPPRESS_ITEM_WARNINGS=%d", suppress_item_warnings_value));
    reuse_item = reuse_item_value != 0;
    suppress_item_warnings = suppress_item_warnings_value != 0;

    profile = str_toupper(profile);
    constraint_set = str_toupper(constraint_set);

    if (iterations == 0) begin
      `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG", "BENCH_ITERATIONS must be greater than zero")
    end

    case (profile)
      "RANDOM",
      "LDST_V_LOC",
      "LDST_V_WRP",
      "LDST_V_BLK",
      "LDSTE_V_LOC",
      "LDSTE_V_WRP",
      "LDSTE_V_BLK": ;
      default: begin
        `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                   $sformatf("unsupported BENCH_PROFILE=%s", profile))
      end
    endcase

    case (constraint_set)
      "ALL", "NO_ADDR_BOUND", "NO_UNIQUENESS", "CORE": ;
      default: begin
        `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                   $sformatf("unsupported BENCH_CONSTRAINT_SET=%s", constraint_set))
      end
    endcase
  endfunction : build_phase

  task shmins_random_benchmark_test::run_phase(uvm_phase phase);
    shmins_sequence_item item;
    longint start_ns;
    longint stop_ns;
    longint elapsed_ns;
    real ns_per_attempt;
    real attempts_per_second;

    phase.raise_objection(this);

    if (suppress_item_warnings) begin
      uvm_root::get().set_report_id_action_hier("shmins_sequence_item", UVM_NO_ACTION);
    end

    if (reuse_item) begin
      item = create_item("benchmark_item");
    end

    `uvm_info("SHMINS_RANDOM_BENCH_START",
              $sformatf({"profile=%s constraint_set=%s warmup=%0d iterations=%0d ",
                         "reuse_item=%0d suppress_item_warnings=%0d"},
                        profile, constraint_set, warmup_iterations, iterations,
                        reuse_item, suppress_item_warnings),
              UVM_NONE)

    for (int unsigned index = 0; index < warmup_iterations; index++) begin
      if (!reuse_item) begin
        item = create_item($sformatf("warmup_item_%0d", index));
      end
      if (!randomize_item(item)) begin
        `uvm_fatal("SHMINS_RANDOM_BENCH_WARMUP",
                   $sformatf("warmup randomize failed at iteration %0d", index))
      end
    end


    success_count = 0;
    failure_count = 0;
    checksum = 0;
    start_ns = shmins_benchmark_monotonic_ns();
    `uvm_info("SHMINS_RANDOM_BENCH_MEASURE",
              $sformatf("starting measured randomize loop of %0d iterations", iterations),
              UVM_NONE)

    for (int unsigned index = 0; index < iterations; index++) begin
      if (!reuse_item) begin
        item = create_item($sformatf("measured_item_%0d", index));
      end

      if (randomize_item(item)) begin
        success_count++;
        update_checksum(item);
        `uvm_info("SHMINS_RANDOM_BENCH_RANDOMIZE",
                  $sformatf("measured randomize succeeded at iteration %0d", index),
                  UVM_NONE)
      end else begin
        failure_count++;
        `uvm_info("SHMINS_RANDOM_BENCH_RANDOMIZE",
                  $sformatf("measured randomize failed at iteration %0d", index),
                  UVM_NONE)
      end
    end

    stop_ns = shmins_benchmark_monotonic_ns();
    if (start_ns < 0 || stop_ns < start_ns) begin
      `uvm_fatal("SHMINS_RANDOM_BENCH_CLOCK", "monotonic benchmark clock failed")
    end

    elapsed_ns = stop_ns - start_ns;
    ns_per_attempt = real'(elapsed_ns) / real'(iterations);
    attempts_per_second = (elapsed_ns == 0)
        ? 0.0
        : real'(iterations) * 1.0e9 / real'(elapsed_ns);

    `uvm_info("SHMINS_RANDOM_BENCH_RESULT",
              $sformatf({"profile=%s constraint_set=%s iterations=%0d successes=%0d failures=%0d ",
                         "elapsed_ns=%0d ns_per_attempt=%0.3f attempts_per_second=%0.3f ",
                         "reuse_item=%0d checksum=0x%016h"},
                        profile, constraint_set, iterations, success_count, failure_count,
                        elapsed_ns, ns_per_attempt, attempts_per_second, reuse_item, checksum),
              UVM_NONE)

    if (failure_count != 0) begin
      `uvm_error("SHMINS_RANDOM_BENCH_RANDOMIZE",
                 $sformatf("%0d of %0d measured randomize attempts failed",
                           failure_count, iterations))
    end

    phase.drop_objection(this);
  endtask : run_phase

  function shmins_sequence_item shmins_random_benchmark_test::create_item(string item_name);
    shmins_sequence_item item;

    item = new(item_name);
    if (constraint_set inside {"NO_ADDR_BOUND", "CORE"}) begin
      item.c_addr_bound.constraint_mode(0);
    end
    if (constraint_set inside {"NO_UNIQUENESS", "CORE"}) begin
      item.c_addr_offs_elem_ne.constraint_mode(0);
    end

    return item;
  endfunction : create_item

  function bit shmins_random_benchmark_test::randomize_item(shmins_sequence_item item);
    case (profile)
      "RANDOM": begin
        return item.randomize();
      end
      "LDST_V_LOC": begin
        return item.randomize() with {
          creq_dtype == DTYP_8;
          creq_atype_w == ATYP_16;
          creq_atype_s == ATYP_U;
          creq_atype_g == GAUTO_1B;
          creq_itype == LDST_V;
          creq_space == SPACE_LOC;
        };
      end
      "LDST_V_WRP": begin
        return item.randomize() with {
          creq_dtype == DTYP_8;
          creq_atype_w == ATYP_16;
          creq_atype_s == ATYP_U;
          creq_atype_g == GAUTO_1B;
          creq_itype == LDST_V;
          creq_space == SPACE_WRP;
        };
      end
      "LDST_V_BLK": begin
        return item.randomize() with {
          creq_dtype == DTYP_8;
          creq_atype_w == ATYP_16;
          creq_atype_s == ATYP_U;
          creq_atype_g == GAUTO_1B;
          creq_itype == LDST_V;
          creq_space == SPACE_BLK;
        };
      end
      "LDSTE_V_LOC": begin
        return item.randomize() with {
          creq_dtype == DTYP_8;
          creq_atype_w == ATYP_16;
          creq_atype_s == ATYP_U;
          creq_atype_g == GAUTO_1B;
          creq_itype == LDSTE_V;
          creq_space == SPACE_LOC;
        };
      end
      "LDSTE_V_WRP": begin
        return item.randomize() with {
          creq_dtype == DTYP_8;
          creq_atype_w == ATYP_16;
          creq_atype_s == ATYP_U;
          creq_atype_g == GAUTO_1B;
          creq_itype == LDSTE_V;
          creq_space == SPACE_WRP;
        };
      end
      "LDSTE_V_BLK": begin
        return item.randomize() with {
          creq_dtype == DTYP_8;
          creq_atype_w == ATYP_16;
          creq_atype_s == ATYP_U;
          creq_atype_g == GAUTO_1B;
          creq_itype == LDSTE_V;
          creq_space == SPACE_BLK;
        };
      end
      default: begin
        `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                   $sformatf("unsupported BENCH_PROFILE=%s", profile))
        return 1'b0;
      end
    endcase
  endfunction : randomize_item

  function void shmins_random_benchmark_test::update_checksum(shmins_sequence_item item);
    checksum = checksum ^ longint'(item.creq_base);
    checksum = checksum ^ longint'(item.creq_tmsk);
    checksum = checksum ^ longint'(item.offs_elem[0][0]);
    checksum = checksum ^ longint'(item.creq_vdat[THD_N-1]);
  endfunction : update_checksum

endpackage : shmins_random_benchmark_pkg
