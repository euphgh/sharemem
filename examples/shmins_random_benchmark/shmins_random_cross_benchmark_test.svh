`ifndef INC_SHMINS_RANDOM_CROSS_BENCHMARK_TEST_SVH
`define INC_SHMINS_RANDOM_CROSS_BENCHMARK_TEST_SVH

typedef enum int unsigned {
  SHMINS_BENCH_CONTIGUOUS,
  SHMINS_BENCH_STRIDED,
  SHMINS_BENCH_INDEXED
} shmins_benchmark_topology_e;

//------------------------------------------------------------------------------
// @brief Provides shared configuration and accounting for split-item benchmarks.
//------------------------------------------------------------------------------
class shmins_split_benchmark_base_test extends uvm_test;
  // Number of measured randomize calls per directed combination or topology.
  int unsigned iterations = 100;

  // Number of unmeasured solver warmup calls per directed combination or topology.
  int unsigned warmup_iterations = 5;

  //------------------------------------------------------------------------
  // @brief Constructs the common split benchmark test base.
  //
  // @param name UVM component instance name.
  // @param parent Parent component; null when created as uvm_test_top.
  //------------------------------------------------------------------------
  extern function new(string name = "shmins_split_benchmark_base_test", uvm_component parent = null);

  //------------------------------------------------------------------------
  // @brief Reads common iteration controls from benchmark plusargs.
  //
  // @param phase UVM build phase used for configuration.
  //------------------------------------------------------------------------
  extern virtual function void build_phase(uvm_phase phase);

  //------------------------------------------------------------------------
  // @brief Creates the concrete sequence item for one address topology.
  //
  // @param topology Address-generation topology to construct.
  // @param item_name UVM object instance name.
  // @return A concrete split sequence item through the common base handle.
  //------------------------------------------------------------------------
  extern protected function shmins_sequence_item create_topology_item(shmins_benchmark_topology_e topology,
                                                                      string item_name);

  //------------------------------------------------------------------------
  // @brief Accumulates one successful item's diagnostics and observable data.
  //
  // @param item Successfully randomized item.
  // @param retries Aggregate internal retry count updated in place.
  // @param validation_errors Aggregate validator error count updated in place.
  // @param checksum Aggregate observable checksum updated in place.
  //------------------------------------------------------------------------
  extern protected function void sample_item(shmins_sequence_item item,
                                             ref longint unsigned retries,
                                             ref longint unsigned validation_errors,
                                             ref longint unsigned checksum);

  //------------------------------------------------------------------------
  // @brief Reconstructs one MADDR from the packed public transaction fields.
  //
  // @param item Transaction whose packed offset is decoded.
  // @param thread_idx Source thread index.
  // @param elem_idx Data element index.
  // @return MADDR reconstructed independently of topology intermediate arrays.
  //------------------------------------------------------------------------
  extern protected function longint signed reconstruct_packed_maddr(shmins_sequence_item item,
                                                                    int thread_idx,
                                                                    int elem_idx);

  //------------------------------------------------------------------------
  // @brief Checks the real reference consumer against one randomized item.
  //
  // @param item Randomized topology item with packed offsets.
  // @param validation_errors Aggregate error count updated in place.
  // @post Active element addresses match the generated model; masked and
  //       zero-length payload slots produce no reference access.
  //------------------------------------------------------------------------
  extern protected function void validate_reference_consumer(shmins_sequence_item item,
                                                              ref longint unsigned validation_errors);

  //------------------------------------------------------------------------
  // @brief Returns the stable result label for one topology.
  //
  // @param topology Address-generation topology.
  // @return CONTIGUOUS, STRIDED, or INDEXED.
  //------------------------------------------------------------------------
  extern protected function string topology_name(shmins_benchmark_topology_e topology);
endclass : shmins_split_benchmark_base_test

function shmins_split_benchmark_base_test::new(string name = "shmins_split_benchmark_base_test",
                                               uvm_component parent = null);
  super.new(name, parent);
endfunction : new

function void shmins_split_benchmark_base_test::build_phase(uvm_phase phase);
  super.build_phase(phase);
  void'($value$plusargs("BENCH_ITERATIONS=%d", iterations));
  void'($value$plusargs("BENCH_WARMUP=%d", warmup_iterations));
  if (iterations == 0) begin
    `uvm_fatal("SHMINS_SPLIT_BENCH_CONFIG", "BENCH_ITERATIONS must be greater than zero")
  end
endfunction : build_phase

function shmins_sequence_item shmins_split_benchmark_base_test::create_topology_item(
    shmins_benchmark_topology_e topology,
    string item_name);
  shmins_sequence_item item;

  case (topology)
    SHMINS_BENCH_CONTIGUOUS: item = shmins_contiguous_sequence_item::type_id::create(item_name);
    SHMINS_BENCH_STRIDED: item = shmins_strided_sequence_item::type_id::create(item_name);
    SHMINS_BENCH_INDEXED: item = shmins_indexed_sequence_item::type_id::create(item_name);
    default: `uvm_fatal("SHMINS_SPLIT_BENCH_TOPOLOGY", $sformatf("unsupported topology=%0d", topology))
  endcase
  item.m2v_unique_enable = 1'b0;
  return item;
endfunction : create_topology_item

function void shmins_split_benchmark_base_test::sample_item(
    shmins_sequence_item item,
    ref longint unsigned retries,
    ref longint unsigned validation_errors,
    ref longint unsigned checksum);
  retries += item.generation_retry_count;
  validation_errors += item.validation_error_count;
  for (int thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    for (int elem_idx = 0; elem_idx < item.thread_elem_cnt(thread_idx); elem_idx++) begin
      longint signed reconstructed_maddr;
      shmins_sequence_item::shmins_address_result_t mapped;

      if (!item.is_active_element(thread_idx, elem_idx)) begin
        continue;
      end
      reconstructed_maddr = reconstruct_packed_maddr(item, thread_idx, elem_idx);
      mapped = item.map_maddr(thread_idx, reconstructed_maddr);
      if (reconstructed_maddr != item.elem_maddr[thread_idx][elem_idx] || !mapped.valid) begin
        validation_errors++;
        `uvm_error("SHMINS_CONSUMER_MADDR",
                   $sformatf("thread=%0d elem=%0d generated=0x%0h reconstructed=0x%0h valid=%0b",
                             thread_idx, elem_idx, item.elem_maddr[thread_idx][elem_idx],
                             reconstructed_maddr, mapped.valid))
      end
    end
  end
  checksum ^= longint'(item.creq_base);
  checksum ^= longint'(item.creq_tmsk);
  checksum ^= longint'(item.offs_elem[0][0]);
  checksum ^= longint'(item.creq_vdat[THD_N-1]);
endfunction : sample_item

function longint signed shmins_split_benchmark_base_test::reconstruct_packed_maddr(
    shmins_sequence_item item,
    int thread_idx,
    int elem_idx);
  longint signed base;

  base = longint'(item.creq_base[MADDR_W-1:0]);
  case (item.creq_itype)
    LDST_S, LDST_V: begin
      return base + item.decode_packed_offset(thread_idx, 0) +
             longint'(elem_idx) * longint'(item.data_byte_w());
    end
    LDSTE_S: return base + longint'(elem_idx) * item.decode_packed_offset(thread_idx, 0);
    LDSTE_V: return base + item.decode_packed_offset(thread_idx, elem_idx);
    default: return -1;
  endcase
endfunction : reconstruct_packed_maddr

function void shmins_split_benchmark_base_test::validate_reference_consumer(
    shmins_sequence_item item,
    ref longint unsigned validation_errors);
  shm_wtrans_item consumer;
  int zero_length_thread;

  consumer = shm_wtrans_item::type_id::create("reference_consumer");
  consumer.init_from(item);
  zero_length_thread = -1;

  for (int thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    int unsigned expected_count;

    expected_count = 0;
    if (item.creq_tmsk[thread_idx] === 1'b1) begin
      expected_count = item.thread_elem_cnt(thread_idx);
      if (expected_count > item.max_elem_cnt()) begin
        expected_count = item.max_elem_cnt();
      end
      if (zero_length_thread < 0) begin
        zero_length_thread = thread_idx;
      end
    end
    if (consumer.baddr_2d_array[thread_idx].size() != expected_count) begin
      validation_errors++;
      `uvm_error("SHMINS_REFERENCE_LENGTH",
                 $sformatf("thread=%0d expected_slots=%0d actual_slots=%0d",
                           thread_idx, expected_count, consumer.baddr_2d_array[thread_idx].size()))
    end

    for (int elem_idx = 0; elem_idx < expected_count; elem_idx++) begin
      if (item.is_active_element(thread_idx, elem_idx)) begin
        shmins_sequence_item::shmins_address_result_t mapped;

        mapped = item.map_maddr(thread_idx, reconstruct_packed_maddr(item, thread_idx, elem_idx));
        if (!mapped.valid || consumer.wstrb_2d_array[thread_idx][elem_idx] == 0 ||
            consumer.bid_2d_array[thread_idx][elem_idx] != mapped.physical_addr.bank_id ||
            consumer.gid_2d_array[thread_idx][elem_idx] != mapped.physical_addr.gid ||
            consumer.baddr_2d_array[thread_idx][elem_idx] != mapped.physical_addr.baddr) begin
          validation_errors++;
          `uvm_error("SHMINS_REFERENCE_MADDR",
                     $sformatf("thread=%0d elem=%0d reference consumer mismatch", thread_idx, elem_idx))
        end
      end else if (consumer.wstrb_2d_array[thread_idx][elem_idx] != 0) begin
        validation_errors++;
        `uvm_error("SHMINS_REFERENCE_MASK",
                   $sformatf("thread=%0d elem=%0d inactive slot has strobe=0x%0h",
                             thread_idx, elem_idx, consumer.wstrb_2d_array[thread_idx][elem_idx]))
      end
    end
  end

  if (zero_length_thread >= 0) begin
    shm_wtrans_item zero_length_consumer;
    logic [7:0] saved_length;
    byte unsigned saved_elem_num;

    saved_length = item.creq_len[zero_length_thread];
    saved_elem_num = item.elem_num[zero_length_thread];
    item.creq_len[zero_length_thread] = 0;
    item.elem_num[zero_length_thread] = 0;
    zero_length_consumer = shm_wtrans_item::type_id::create("zero_length_consumer");
    zero_length_consumer.init_from(item);
    if (zero_length_consumer.baddr_2d_array[zero_length_thread].size() != 0) begin
      validation_errors++;
      `uvm_error("SHMINS_REFERENCE_ZERO_LENGTH",
                 $sformatf("thread=%0d zero-length payload produced %0d slots",
                           zero_length_thread,
                           zero_length_consumer.baddr_2d_array[zero_length_thread].size()))
    end
    item.creq_len[zero_length_thread] = saved_length;
    item.elem_num[zero_length_thread] = saved_elem_num;
  end
endfunction : validate_reference_consumer

function string shmins_split_benchmark_base_test::topology_name(shmins_benchmark_topology_e topology);
  case (topology)
    SHMINS_BENCH_CONTIGUOUS: return "CONTIGUOUS";
    SHMINS_BENCH_STRIDED: return "STRIDED";
    SHMINS_BENCH_INDEXED: return "INDEXED";
    default: return "UNKNOWN";
  endcase
endfunction : topology_name

//------------------------------------------------------------------------------
// @brief Measures the complete topology/space/RW/dtype/ATYPE override matrix.
//
// Contiguous uses LDST_V because LDST_S and LDST_V share the same generator.
// INV_SIZE is fixed at 10. LOC/WRP use WPID 0 and WPNUM 1; BLK uses the last
// implemented WPID and WPNUM 4. M2V optional uniqueness remains disabled.
//------------------------------------------------------------------------------
class shmins_random_cross_benchmark_test extends shmins_split_benchmark_base_test;
  int unsigned combination_count;
  int unsigned combination_failure_count;

  //------------------------------------------------------------------------
  // @brief Constructs the directed cross benchmark.
  //
  // @param name UVM component instance name.
  // @param parent Parent component; null when created as uvm_test_top.
  //------------------------------------------------------------------------
  extern function new(string name = "shmins_random_cross_benchmark_test", uvm_component parent = null);

  //------------------------------------------------------------------------
  // @brief Iterates over and measures all 432 supported field combinations.
  //
  // @param phase UVM run phase whose objection protects the benchmark loop.
  //------------------------------------------------------------------------
  extern virtual task run_phase(uvm_phase phase);

  //------------------------------------------------------------------------
  // @brief Measures one complete directed field combination.
  //
  // @param topology Address-generation topology.
  // @param rw_value Fixed transfer direction.
  // @param dtype_value Fixed data width.
  // @param atype_w_value Fixed offset encoding width.
  // @param atype_s_value Fixed offset signedness.
  // @param atype_g_value Fixed offset granularity.
  // @param space_value Fixed address space.
  //------------------------------------------------------------------------
  extern protected task measure_combination(shmins_benchmark_topology_e topology,
                                             creq_rw_e rw_value,
                                             creq_dtype_e dtype_value,
                                             creq_atype_w_e atype_w_value,
                                             creq_atype_s_e atype_s_value,
                                             creq_atype_g_e atype_g_value,
                                             creq_space_e space_value);

  //------------------------------------------------------------------------
  // @brief Randomizes one item with the selected matrix field overrides.
  //
  // @param item Concrete topology item to randomize.
  // @param topology Address-generation topology selecting the instruction type.
  // @param rw_value Fixed transfer direction.
  // @param dtype_value Fixed data width.
  // @param atype_w_value Fixed offset encoding width.
  // @param atype_s_value Fixed offset signedness.
  // @param atype_g_value Fixed offset granularity.
  // @param space_value Fixed address space.
  // @return 1 when randomization and post-randomize generation succeed.
  //------------------------------------------------------------------------
  extern protected function bit randomize_combination(shmins_sequence_item item,
                                                       shmins_benchmark_topology_e topology,
                                                       creq_rw_e rw_value,
                                                       creq_dtype_e dtype_value,
                                                       creq_atype_w_e atype_w_value,
                                                       creq_atype_s_e atype_s_value,
                                                       creq_atype_g_e atype_g_value,
                                                       creq_space_e space_value);

  //------------------------------------------------------------------------
  // @brief Returns the directed instruction type for one topology.
  //
  // @param topology Address-generation topology.
  // @return LDST_V, LDSTE_S, or LDSTE_V.
  //------------------------------------------------------------------------
  extern protected function creq_itype_e topology_itype(shmins_benchmark_topology_e topology);

  //------------------------------------------------------------------------
  // @brief Returns a stable transfer-direction result label.
  //
  // @param value Transfer direction.
  // @return V2M or M2V.
  //------------------------------------------------------------------------
  extern protected function string rw_name(creq_rw_e value);

  //------------------------------------------------------------------------
  // @brief Returns a stable dtype result label.
  //
  // @param value Data width selection.
  // @return DTYP_32, DTYP_16, or DTYP_8.
  //------------------------------------------------------------------------
  extern protected function string dtype_name(creq_dtype_e value);

  //------------------------------------------------------------------------
  // @brief Returns a stable ATYPE width result label.
  //
  // @param value Offset encoding width.
  // @return ATYP_32 or ATYP_16.
  //------------------------------------------------------------------------
  extern protected function string atype_w_name(creq_atype_w_e value);

  //------------------------------------------------------------------------
  // @brief Returns a stable ATYPE signedness result label.
  //
  // @param value Offset signedness.
  // @return ATYP_U or ATYP_S.
  //------------------------------------------------------------------------
  extern protected function string atype_s_name(creq_atype_s_e value);

  //------------------------------------------------------------------------
  // @brief Returns a stable ATYPE granularity result label.
  //
  // @param value Offset granularity.
  // @return GAUTO_1B or GAUTO_DW.
  //------------------------------------------------------------------------
  extern protected function string atype_g_name(creq_atype_g_e value);

  //------------------------------------------------------------------------
  // @brief Returns a stable address-space result label.
  //
  // @param value Address space.
  // @return LOC, WRP, or BLK.
  //------------------------------------------------------------------------
  extern protected function string space_name(creq_space_e value);

  `uvm_component_utils(shmins_random_cross_benchmark_test)
endclass : shmins_random_cross_benchmark_test

function shmins_random_cross_benchmark_test::new(string name = "shmins_random_cross_benchmark_test",
                                                 uvm_component parent = null);
  super.new(name, parent);
endfunction : new

task shmins_random_cross_benchmark_test::run_phase(uvm_phase phase);
  phase.raise_objection(this);
  combination_count = 0;
  combination_failure_count = 0;

  `uvm_info("SHMINS_CROSS_START",
            $sformatf("combinations=432 iterations=%0d warmup=%0d", iterations, warmup_iterations),
            UVM_NONE)

  for (int topology_idx = 0; topology_idx < 3; topology_idx++) begin
    for (int space_idx = 0; space_idx < 3; space_idx++) begin
      for (int rw_idx = 0; rw_idx < 2; rw_idx++) begin
        for (int dtype_idx = 0; dtype_idx < 3; dtype_idx++) begin
          for (int atype_w_idx = 0; atype_w_idx < 2; atype_w_idx++) begin
            for (int atype_s_idx = 0; atype_s_idx < 2; atype_s_idx++) begin
              for (int atype_g_idx = 0; atype_g_idx < 2; atype_g_idx++) begin
                measure_combination(shmins_benchmark_topology_e'(topology_idx),
                                    creq_rw_e'(rw_idx),
                                    creq_dtype_e'(dtype_idx),
                                    creq_atype_w_e'(atype_w_idx),
                                    creq_atype_s_e'(atype_s_idx),
                                    creq_atype_g_e'(atype_g_idx),
                                    creq_space_e'(space_idx));
              end
            end
          end
        end
      end
    end
  end

  `uvm_info("SHMINS_CROSS_SUMMARY",
            $sformatf("combinations=%0d failed_combinations=%0d", combination_count, combination_failure_count),
            UVM_NONE)
  if (combination_failure_count != 0) begin
    `uvm_error("SHMINS_CROSS_FAILURE", $sformatf("%0d combinations had randomize failures", combination_failure_count))
  end
  phase.drop_objection(this);
endtask : run_phase

task shmins_random_cross_benchmark_test::measure_combination(
    shmins_benchmark_topology_e topology,
    creq_rw_e rw_value,
    creq_dtype_e dtype_value,
    creq_atype_w_e atype_w_value,
    creq_atype_s_e atype_s_value,
    creq_atype_g_e atype_g_value,
    creq_space_e space_value);
  shmins_sequence_item item;
  int unsigned successes;
  int unsigned failures;
  longint unsigned retries;
  longint unsigned validation_errors;
  longint unsigned checksum;
  longint start_ns;
  longint stop_ns;
  real elapsed_ms;
  real ms_per_attempt;

  item = create_topology_item(topology, $sformatf("cross_item_%0d", combination_count));
  for (int unsigned warmup_idx = 0; warmup_idx < warmup_iterations; warmup_idx++) begin
    if (!randomize_combination(item, topology, rw_value, dtype_value, atype_w_value, atype_s_value, atype_g_value,
                               space_value)) begin
      `uvm_fatal("SHMINS_CROSS_WARMUP", $sformatf("combination=%0d warmup=%0d failed", combination_count, warmup_idx))
    end
  end

  successes = 0;
  failures = 0;
  retries = 0;
  validation_errors = 0;
  checksum = 0;
  if (!randomize_combination(item, topology, rw_value, dtype_value, atype_w_value, atype_s_value, atype_g_value,
                             space_value)) begin
    `uvm_fatal("SHMINS_REFERENCE_CONSUMER_RANDOMIZE",
               $sformatf("combination=%0d reference-consumer setup failed", combination_count))
  end
  validate_reference_consumer(item, validation_errors);
  start_ns = shmins_benchmark_monotonic_ns();
  for (int unsigned iteration_idx = 0; iteration_idx < iterations; iteration_idx++) begin
    if (randomize_combination(item, topology, rw_value, dtype_value, atype_w_value, atype_s_value, atype_g_value,
                              space_value)) begin
      successes++;
      sample_item(item, retries, validation_errors, checksum);
    end else begin
      failures++;
    end
  end
  stop_ns = shmins_benchmark_monotonic_ns();
  if (start_ns < 0 || stop_ns < start_ns) begin
    `uvm_fatal("SHMINS_CROSS_CLOCK", "monotonic benchmark clock failed")
  end
  elapsed_ms = real'(stop_ns - start_ns) / 1.0e6;
  ms_per_attempt = elapsed_ms / real'(iterations);

  combination_count++;
  if (failures != 0 || validation_errors != 0) begin
    combination_failure_count++;
  end
  `uvm_info("SHMINS_CROSS_RESULT",
            $sformatf({"topology=%s space=%s rw=%s dtype=%s atype_w=%s atype_s=%s atype_g=%s ",
                       "iterations=%0d successes=%0d failures=%0d retries=%0d validation_errors=%0d ",
                       "elapsed_ms=%0.6f ms_per_attempt=%0.6f checksum=0x%016h"},
                      topology_name(topology), space_name(space_value), rw_name(rw_value), dtype_name(dtype_value),
                      atype_w_name(atype_w_value), atype_s_name(atype_s_value), atype_g_name(atype_g_value),
                      iterations, successes, failures, retries, validation_errors,
                      elapsed_ms, ms_per_attempt, checksum),
            UVM_NONE)
endtask : measure_combination

function bit shmins_random_cross_benchmark_test::randomize_combination(
    shmins_sequence_item item,
    shmins_benchmark_topology_e topology,
    creq_rw_e rw_value,
    creq_dtype_e dtype_value,
    creq_atype_w_e atype_w_value,
    creq_atype_s_e atype_s_value,
    creq_atype_g_e atype_g_value,
    creq_space_e space_value);
  creq_itype_e itype_value;
  int unsigned wpid_value;
  int unsigned wpnum_value;

  itype_value = topology_itype(topology);
  wpid_value = (space_value == SPACE_BLK) ? WARP_N - 1 : 0;
  wpnum_value = (space_value == SPACE_BLK) ? 4 : 1;
  return item.randomize() with {
    creq_rw == local::rw_value;
    creq_dtype == local::dtype_value;
    creq_atype_w == local::atype_w_value;
    creq_atype_s == local::atype_s_value;
    creq_atype_g == local::atype_g_value;
    creq_itype == local::itype_value;
    creq_space == local::space_value;
    creq_inv_size == 10;
    creq_wpid == local::wpid_value;
    creq_wpnum == local::wpnum_value;
  };
endfunction : randomize_combination

function creq_itype_e shmins_random_cross_benchmark_test::topology_itype(shmins_benchmark_topology_e topology);
  case (topology)
    SHMINS_BENCH_CONTIGUOUS: return LDST_V;
    SHMINS_BENCH_STRIDED: return LDSTE_S;
    SHMINS_BENCH_INDEXED: return LDSTE_V;
    default: return LDST_V;
  endcase
endfunction : topology_itype

function string shmins_random_cross_benchmark_test::rw_name(creq_rw_e value);
  return (value == SHM_V2M) ? "V2M" : "M2V";
endfunction : rw_name

function string shmins_random_cross_benchmark_test::dtype_name(creq_dtype_e value);
  case (value)
    DTYP_32: return "DTYP_32";
    DTYP_16: return "DTYP_16";
    DTYP_8: return "DTYP_8";
    default: return "UNKNOWN";
  endcase
endfunction : dtype_name

function string shmins_random_cross_benchmark_test::atype_w_name(creq_atype_w_e value);
  return (value == ATYP_32) ? "ATYP_32" : "ATYP_16";
endfunction : atype_w_name

function string shmins_random_cross_benchmark_test::atype_s_name(creq_atype_s_e value);
  return (value == ATYP_U) ? "ATYP_U" : "ATYP_S";
endfunction : atype_s_name

function string shmins_random_cross_benchmark_test::atype_g_name(creq_atype_g_e value);
  return (value == GAUTO_1B) ? "GAUTO_1B" : "GAUTO_DW";
endfunction : atype_g_name

function string shmins_random_cross_benchmark_test::space_name(creq_space_e value);
  case (value)
    SPACE_LOC: return "LOC";
    SPACE_WRP: return "WRP";
    SPACE_BLK: return "BLK";
    default: return "UNKNOWN";
  endcase
endfunction : space_name

//------------------------------------------------------------------------------
// @brief Measures each concrete topology using item.randomize() without inline constraints.
//------------------------------------------------------------------------------
class shmins_random_unconstrained_benchmark_test extends shmins_split_benchmark_base_test;
  int unsigned topology_failure_count;

  //------------------------------------------------------------------------
  // @brief Constructs the no-inline-constraint benchmark.
  //
  // @param name UVM component instance name.
  // @param parent Parent component; null when created as uvm_test_top.
  //------------------------------------------------------------------------
  extern function new(string name = "shmins_random_unconstrained_benchmark_test", uvm_component parent = null);

  //------------------------------------------------------------------------
  // @brief Measures direct randomize() calls for each concrete topology item.
  //
  // @param phase UVM run phase whose objection protects the benchmark loop.
  //------------------------------------------------------------------------
  extern virtual task run_phase(uvm_phase phase);

  //------------------------------------------------------------------------
  // @brief Measures direct randomize() calls for one concrete topology item.
  //
  // @param topology Address-generation topology to measure.
  //------------------------------------------------------------------------
  extern protected task measure_topology(shmins_benchmark_topology_e topology);

  `uvm_component_utils(shmins_random_unconstrained_benchmark_test)
endclass : shmins_random_unconstrained_benchmark_test

function shmins_random_unconstrained_benchmark_test::new(
    string name = "shmins_random_unconstrained_benchmark_test",
    uvm_component parent = null);
  super.new(name, parent);
endfunction : new

task shmins_random_unconstrained_benchmark_test::run_phase(uvm_phase phase);
  phase.raise_objection(this);
  topology_failure_count = 0;
  `uvm_info("SHMINS_UNCONSTRAINED_START",
            $sformatf("topologies=3 iterations=%0d warmup=%0d inline_constraints=0", iterations, warmup_iterations),
            UVM_NONE)

  for (int topology_idx = 0; topology_idx < 3; topology_idx++) begin
    measure_topology(shmins_benchmark_topology_e'(topology_idx));
  end

  `uvm_info("SHMINS_UNCONSTRAINED_SUMMARY",
            $sformatf("topologies=3 failed_topologies=%0d", topology_failure_count),
            UVM_NONE)
  if (topology_failure_count != 0) begin
    `uvm_error("SHMINS_UNCONSTRAINED_FAILURE",
               $sformatf("%0d topologies had randomize failures", topology_failure_count))
  end
  phase.drop_objection(this);
endtask : run_phase

task shmins_random_unconstrained_benchmark_test::measure_topology(shmins_benchmark_topology_e topology);
  shmins_sequence_item item;
  int unsigned successes;
  int unsigned failures;
  longint unsigned retries;
  longint unsigned validation_errors;
  longint unsigned checksum;
  longint start_ns;
  longint stop_ns;
  real elapsed_ms;
  real ms_per_attempt;

  item = create_topology_item(topology, $sformatf("unconstrained_item_%0d", topology));
  for (int unsigned warmup_idx = 0; warmup_idx < warmup_iterations; warmup_idx++) begin
    if (!item.randomize()) begin
      `uvm_fatal("SHMINS_UNCONSTRAINED_WARMUP",
                 $sformatf("topology=%s warmup=%0d failed", topology_name(topology), warmup_idx))
    end
  end

  successes = 0;
  failures = 0;
  retries = 0;
  validation_errors = 0;
  checksum = 0;
  if (!item.randomize()) begin
    `uvm_fatal("SHMINS_REFERENCE_CONSUMER_RANDOMIZE",
               $sformatf("topology=%s reference-consumer setup failed", topology_name(topology)))
  end
  validate_reference_consumer(item, validation_errors);
  start_ns = shmins_benchmark_monotonic_ns();
  for (int unsigned iteration_idx = 0; iteration_idx < iterations; iteration_idx++) begin
    if (item.randomize()) begin
      successes++;
      sample_item(item, retries, validation_errors, checksum);
    end else begin
      failures++;
    end
  end
  stop_ns = shmins_benchmark_monotonic_ns();
  if (start_ns < 0 || stop_ns < start_ns) begin
    `uvm_fatal("SHMINS_UNCONSTRAINED_CLOCK", "monotonic benchmark clock failed")
  end
  elapsed_ms = real'(stop_ns - start_ns) / 1.0e6;
  ms_per_attempt = elapsed_ms / real'(iterations);

  if (failures != 0 || validation_errors != 0) begin
    topology_failure_count++;
  end
  `uvm_info("SHMINS_UNCONSTRAINED_RESULT",
            $sformatf({"topology=%s inline_constraints=0 iterations=%0d successes=%0d failures=%0d retries=%0d ",
                       "validation_errors=%0d elapsed_ms=%0.6f ms_per_attempt=%0.6f checksum=0x%016h"},
                      topology_name(topology), iterations, successes, failures, retries, validation_errors,
                      elapsed_ms, ms_per_attempt, checksum),
            UVM_NONE)
endtask : measure_topology

`endif // INC_SHMINS_RANDOM_CROSS_BENCHMARK_TEST_SVH
