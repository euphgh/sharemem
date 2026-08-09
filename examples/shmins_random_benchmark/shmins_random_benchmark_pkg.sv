package shmins_random_benchmark_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
`ifdef SHMINS_USE_SPLIT_ITEM
  `include "shmins_split_sequence_item.svh"
  `include "shmins_contiguous_sequence_item.svh"
  `include "shmins_strided_sequence_item.svh"
  `include "shmins_indexed_sequence_item.svh"
`elsif SHMINS_USE_POST_RANDOMIZE_ITEM
  `include "shmins_post_randomize_sequence_item.svh"
`else
  `include "shmins_sequence_item.svh"
`endif

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
`ifdef SHMINS_USE_SPLIT_ITEM
    string profile = "LDST_V_LOC";
`else
    string profile = "LDSTE_V_BLK";
`endif

    // Compile-time-selected transaction implementation reported in results.
`ifdef SHMINS_USE_SPLIT_ITEM
    string item_implementation = "SPLIT";
`elsif SHMINS_USE_POST_RANDOMIZE_ITEM
    string item_implementation = "POST_RANDOMIZE";
`else
    string item_implementation = "ORIGINAL";
`endif

    // Fixed instruction direction used by non-RANDOM profiles.
    string rw = "V2M";

    // Fixed dtype and ATYPE fields used by non-RANDOM profiles.
    string dtype = "DTYP_8";
    string atype_w = "ATYP_16";
    string atype_s = "ATYP_U";
    string atype_g = "GAUTO_1B";

    // Optional directed address-space controls. A negative value leaves the
    // field randomized; WARP ID defaults to group zero for baseline parity.
    int benchmark_inv_size = -1;
    int benchmark_wpid = 0;
    int benchmark_wpnum = -1;

    // Allows optional uniqueness checks for M2V. V2M always checks uniqueness.
    bit m2v_unique_enable = 1'b0;

    // Decoded profile fields used by the inline randomize constraint.
    bit random_profile;
    creq_rw_e benchmark_rw;
    creq_dtype_e benchmark_dtype;
    creq_atype_w_e benchmark_atype_w;
    creq_atype_s_e benchmark_atype_s;
    creq_atype_g_e benchmark_atype_g;
    creq_itype_e benchmark_itype;
    creq_space_e benchmark_space;

    // Constraint subset used to isolate expensive address and uniqueness logic.
    string constraint_set = "ALL";

    // Reuses one object by default so object allocation is outside the result.
    bit reuse_item = 1'b1;

    // Suppresses post_randomize range warnings that would distort diagnostic runs.
    bit suppress_item_warnings = 1'b1;

    // Number of successful and failed measured randomize attempts.
    int unsigned success_count;
    int unsigned failure_count;

    // Aggregate generator diagnostics for measured successful attempts.
    longint unsigned total_retry_count;
    longint unsigned total_validation_error_count;

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
    int unsigned m2v_unique_value;

    super.build_phase(phase);

    reuse_item_value = reuse_item;
    suppress_item_warnings_value = suppress_item_warnings;
    m2v_unique_value = m2v_unique_enable;
    void'($value$plusargs("BENCH_ITERATIONS=%d", iterations));
    void'($value$plusargs("BENCH_WARMUP=%d", warmup_iterations));
    void'($value$plusargs("BENCH_PROFILE=%s", profile));
    void'($value$plusargs("BENCH_RW=%s", rw));
    void'($value$plusargs("BENCH_DTYPE=%s", dtype));
    void'($value$plusargs("BENCH_ATYPE_W=%s", atype_w));
    void'($value$plusargs("BENCH_ATYPE_S=%s", atype_s));
    void'($value$plusargs("BENCH_ATYPE_G=%s", atype_g));
    void'($value$plusargs("BENCH_INV_SIZE=%d", benchmark_inv_size));
    void'($value$plusargs("BENCH_WPID=%d", benchmark_wpid));
    void'($value$plusargs("BENCH_WPNUM=%d", benchmark_wpnum));
    void'($value$plusargs("M2V_UNIQUE=%d", m2v_unique_value));
    void'($value$plusargs("BENCH_CONSTRAINT_SET=%s", constraint_set));
    void'($value$plusargs("BENCH_REUSE_ITEM=%d", reuse_item_value));
    void'($value$plusargs("BENCH_SUPPRESS_ITEM_WARNINGS=%d", suppress_item_warnings_value));
    reuse_item = reuse_item_value != 0;
    suppress_item_warnings = suppress_item_warnings_value != 0;
    m2v_unique_enable = m2v_unique_value != 0;

    profile = str_toupper(profile);
    rw = str_toupper(rw);
    dtype = str_toupper(dtype);
    atype_w = str_toupper(atype_w);
    atype_s = str_toupper(atype_s);
    atype_g = str_toupper(atype_g);
    constraint_set = str_toupper(constraint_set);

    if (iterations == 0) begin
      `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG", "BENCH_ITERATIONS must be greater than zero")
    end
    if (benchmark_inv_size < -1 || benchmark_inv_size > 12) begin
      `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                 "BENCH_INV_SIZE must be -1 or in the range 0 through 12")
    end
    if (benchmark_wpid < 0 || benchmark_wpid >= WARP_N) begin
      `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                 "BENCH_WPID must select an implemented WARP")
    end
    if (!(benchmark_wpnum inside {-1, 1, 2, 4})) begin
      `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                 "BENCH_WPNUM must be -1, 1, 2, or 4")
    end

    random_profile = 1'b0;
    case (profile)
      "RANDOM": random_profile = 1'b1;
      "LDST_S_LOC":  begin benchmark_itype = LDST_S;  benchmark_space = SPACE_LOC; end
      "LDST_S_WRP":  begin benchmark_itype = LDST_S;  benchmark_space = SPACE_WRP; end
      "LDST_S_BLK":  begin benchmark_itype = LDST_S;  benchmark_space = SPACE_BLK; end
      "LDST_V_LOC":  begin benchmark_itype = LDST_V;  benchmark_space = SPACE_LOC; end
      "LDST_V_WRP":  begin benchmark_itype = LDST_V;  benchmark_space = SPACE_WRP; end
      "LDST_V_BLK":  begin benchmark_itype = LDST_V;  benchmark_space = SPACE_BLK; end
      "LDSTE_S_LOC": begin benchmark_itype = LDSTE_S; benchmark_space = SPACE_LOC; end
      "LDSTE_S_WRP": begin benchmark_itype = LDSTE_S; benchmark_space = SPACE_WRP; end
      "LDSTE_S_BLK": begin benchmark_itype = LDSTE_S; benchmark_space = SPACE_BLK; end
      "LDSTE_V_LOC": begin benchmark_itype = LDSTE_V; benchmark_space = SPACE_LOC; end
      "LDSTE_V_WRP": begin benchmark_itype = LDSTE_V; benchmark_space = SPACE_WRP; end
      "LDSTE_V_BLK": begin benchmark_itype = LDSTE_V; benchmark_space = SPACE_BLK; end
      default: begin
        `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                   $sformatf("unsupported BENCH_PROFILE=%s", profile))
      end
    endcase

    case (rw)
      "V2M": benchmark_rw = SHM_V2M;
      "M2V": benchmark_rw = SHM_M2V;
      default: begin
        `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                   $sformatf("unsupported BENCH_RW=%s", rw))
      end
    endcase

    case (dtype)
      "DTYP_32": benchmark_dtype = DTYP_32;
      "DTYP_16": benchmark_dtype = DTYP_16;
      "DTYP_8":  benchmark_dtype = DTYP_8;
      default: begin
        `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                   $sformatf("unsupported BENCH_DTYPE=%s", dtype))
      end
    endcase

    case (atype_w)
      "ATYP_32": benchmark_atype_w = ATYP_32;
      "ATYP_16": benchmark_atype_w = ATYP_16;
      default: begin
        `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                   $sformatf("unsupported BENCH_ATYPE_W=%s", atype_w))
      end
    endcase

    case (atype_s)
      "ATYP_U": benchmark_atype_s = ATYP_U;
      "ATYP_S": benchmark_atype_s = ATYP_S;
      default: begin
        `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                   $sformatf("unsupported BENCH_ATYPE_S=%s", atype_s))
      end
    endcase

    case (atype_g)
      "GAUTO_1B": benchmark_atype_g = GAUTO_1B;
      "GAUTO_DW": benchmark_atype_g = GAUTO_DW;
      default: begin
        `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                   $sformatf("unsupported BENCH_ATYPE_G=%s", atype_g))
      end
    endcase

    case (constraint_set)
      "ALL",
      "NO_ADDR_BOUND",
      "NO_SOLVE_ORDER",
      "NO_LDSTE_LOC_UNIQUE",
      "NO_LDSTE_GLOBAL_UNIQUE",
      "NO_LDST_RANGE",
      "NO_COLLISION",
      "NO_UNIQUENESS",
      "CORE": ;
      default: begin
        `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                   $sformatf("unsupported BENCH_CONSTRAINT_SET=%s", constraint_set))
      end
    endcase

`ifdef SHMINS_USE_SPLIT_ITEM
    if (random_profile) begin
      `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                 "SPLIT currently supports only fixed topology profiles")
    end
    if (constraint_set != "ALL") begin
      `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                 "SPLIT supports only BENCH_CONSTRAINT_SET=ALL")
    end
`endif

  endfunction : build_phase

  task shmins_random_benchmark_test::run_phase(uvm_phase phase);
    shmins_sequence_item item;
    longint start_ns;
    longint stop_ns;
    longint elapsed_ns;
    real elapsed_ms;
    real ms_per_attempt;
    real attempts_per_second;

    phase.raise_objection(this);

    if (suppress_item_warnings) begin
      uvm_root::get().set_report_id_action_hier("shmins_sequence_item", UVM_NO_ACTION);
    end

    if (reuse_item) begin
      item = create_item("benchmark_item");
    end

    `uvm_info("SHMINS_RANDOM_BENCH_START",
              $sformatf({"profile=%s rw=%s dtype=%s atype_w=%s atype_s=%s atype_g=%s ",
                         "inv_size=%0d wpid=%0d wpnum=%0d ",
                         "item_impl=%s m2v_unique=%0d constraint_set=%s ",
                         "warmup=%0d iterations=%0d reuse_item=%0d suppress_item_warnings=%0d"},
                        profile, rw, dtype, atype_w, atype_s, atype_g,
                        benchmark_inv_size, benchmark_wpid, benchmark_wpnum,
                        item_implementation, m2v_unique_enable, constraint_set,
                        warmup_iterations, iterations,
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
    total_retry_count = 0;
    total_validation_error_count = 0;
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
                  UVM_HIGH)
      end else begin
        failure_count++;
        `uvm_info("SHMINS_RANDOM_BENCH_RANDOMIZE",
                  $sformatf("measured randomize failed at iteration %0d", index),
                  UVM_HIGH)
      end
    end

    stop_ns = shmins_benchmark_monotonic_ns();
    if (start_ns < 0 || stop_ns < start_ns) begin
      `uvm_fatal("SHMINS_RANDOM_BENCH_CLOCK", "monotonic benchmark clock failed")
    end

    elapsed_ns = stop_ns - start_ns;
    elapsed_ms = real'(elapsed_ns) / 1.0e6;
    ms_per_attempt = elapsed_ms / real'(iterations);
    attempts_per_second = (elapsed_ns == 0)
        ? 0.0
        : real'(iterations) * 1.0e9 / real'(elapsed_ns);

    `uvm_info("SHMINS_RANDOM_BENCH_RESULT",
              $sformatf({"profile=%s item_impl=%s constraint_set=%s iterations=%0d ",
                         "successes=%0d failures=%0d ",
                         "rw=%s dtype=%s atype_w=%s atype_s=%s atype_g=%s ",
                         "inv_size=%0d wpid=%0d wpnum=%0d ",
                         "m2v_unique=%0d retries=%0d validation_errors=%0d ",
                         "elapsed_ms=%0.6f ms_per_attempt=%0.6f ",
                         "attempts_per_second=%0.3f ",
                         "reuse_item=%0d checksum=0x%016h"},
                        profile, item_implementation, constraint_set,
                        iterations, success_count, failure_count,
                        rw, dtype, atype_w, atype_s, atype_g,
                        benchmark_inv_size, benchmark_wpid, benchmark_wpnum,
                        m2v_unique_enable, total_retry_count,
                        total_validation_error_count, elapsed_ms, ms_per_attempt,
                        attempts_per_second, reuse_item, checksum),
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

`ifdef SHMINS_USE_SPLIT_ITEM
    case (benchmark_itype)
      LDST_S, LDST_V: item = shmins_contiguous_sequence_item::type_id::create(item_name);
      LDSTE_S: item = shmins_strided_sequence_item::type_id::create(item_name);
      LDSTE_V: item = shmins_indexed_sequence_item::type_id::create(item_name);
      default: begin
        `uvm_fatal("SHMINS_RANDOM_BENCH_CONFIG",
                   $sformatf("SPLIT does not support itype=%0d", benchmark_itype))
      end
    endcase
    item.m2v_unique_enable = m2v_unique_enable;
`else
    item = shmins_sequence_item::type_id::create(item_name);
`ifdef SHMINS_USE_POST_RANDOMIZE_ITEM
    item.m2v_unique_enable = m2v_unique_enable;
`endif
    if (constraint_set inside {"NO_ADDR_BOUND", "CORE"}) begin
      item.c_addr_bound.constraint_mode(0);
    end
    if (constraint_set inside {"NO_SOLVE_ORDER", "NO_UNIQUENESS", "CORE"}) begin
      item.c_offs_elem_solve_order.constraint_mode(0);
    end
    if (constraint_set inside {"NO_LDSTE_LOC_UNIQUE", "NO_COLLISION", "NO_UNIQUENESS", "CORE"}) begin
      item.c_ldste_v_loc_unique.constraint_mode(0);
    end
    if (constraint_set inside {"NO_LDSTE_GLOBAL_UNIQUE", "NO_COLLISION", "NO_UNIQUENESS", "CORE"}) begin
      item.c_ldste_v_global_unique.constraint_mode(0);
    end
    if (constraint_set inside {"NO_LDST_RANGE", "NO_COLLISION", "NO_UNIQUENESS", "CORE"}) begin
      item.c_ldst_thread_range_no_overlap.constraint_mode(0);
    end
`endif

    return item;
  endfunction : create_item

  function bit shmins_random_benchmark_test::randomize_item(shmins_sequence_item item);
    if (random_profile) begin
      return item.randomize() with {
        creq_rw == local::benchmark_rw;
      };
    end

`ifdef SHMINS_USE_SPLIT_ITEM
    return item.randomize() with {
      creq_rw == local::benchmark_rw;
      creq_dtype == local::benchmark_dtype;
      creq_atype_w == local::benchmark_atype_w;
      creq_atype_s == local::benchmark_atype_s;
      creq_atype_g == local::benchmark_atype_g;
      creq_itype == local::benchmark_itype;
      creq_space == local::benchmark_space;
      creq_wpid == local::benchmark_wpid;
      (local::benchmark_inv_size < 0) ||
          (creq_inv_size == local::benchmark_inv_size);
      (local::benchmark_wpnum < 0) ||
          (creq_wpnum == local::benchmark_wpnum);
    };
`else
    return item.randomize() with {
      creq_rw == local::benchmark_rw;
      creq_dtype == local::benchmark_dtype;
      creq_atype_w == local::benchmark_atype_w;
      creq_atype_s == local::benchmark_atype_s;
      creq_atype_g == local::benchmark_atype_g;
      creq_itype == local::benchmark_itype;
      creq_space == local::benchmark_space;
      creq_wpid == local::benchmark_wpid;
      (local::benchmark_inv_size < 0) ||
          (creq_inv_size == local::benchmark_inv_size);
      (local::benchmark_wpnum < 0) ||
          (creq_wpnum == local::benchmark_wpnum);
      if (local::benchmark_space == SPACE_LOC) {
        creq_base < (1 << VADDR_W) - 4096;
      } else if (local::benchmark_space == SPACE_WRP) {
        creq_base < (1 << BADDR_W) - 4096;
      } else if (local::benchmark_space == SPACE_BLK) {
        if (creq_inv_size <= 10) {
          creq_base >= (creq_wpid / creq_wpnum) *
                       WARP_STEP * BANK_N * creq_wpnum;
          creq_base < ((creq_wpid / creq_wpnum) + 1) *
                      WARP_STEP * BANK_N * creq_wpnum - 4096;
        } else {
          creq_base >= (creq_wpid / creq_wpnum) *
                       16 * 1024 * BANK_N * creq_wpnum;
          creq_base < ((creq_wpid / creq_wpnum) + 1) *
                      16 * 1024 * BANK_N * creq_wpnum - 4096;
        }
      }
      if (local::benchmark_rw == SHM_V2M &&
          local::benchmark_itype == LDSTE_S &&
          local::benchmark_space inside {SPACE_WRP, SPACE_BLK}) {
        foreach (creq_vmsk[thread_idx]) {
          creq_tmsk[thread_idx] -> creq_vmsk[thread_idx][0] == 1'b0;
        }
      }
    };
`endif
  endfunction : randomize_item

  function void shmins_random_benchmark_test::update_checksum(shmins_sequence_item item);
    checksum = checksum ^ longint'(item.creq_base);
    checksum = checksum ^ longint'(item.creq_tmsk);
    checksum = checksum ^ longint'(item.offs_elem[0][0]);
    checksum = checksum ^ longint'(item.creq_vdat[THD_N-1]);
`ifdef SHMINS_USE_SPLIT_ITEM
    total_retry_count += item.generation_retry_count;
    total_validation_error_count += item.validation_error_count;
`elsif SHMINS_USE_POST_RANDOMIZE_ITEM
    total_retry_count += item.post_randomize_retry_count;
`endif
  endfunction : update_checksum

`ifdef SHMINS_USE_SPLIT_ITEM
  `include "shmins_random_cross_benchmark_test.svh"
`endif

endpackage : shmins_random_benchmark_pkg
