`timescale 1ns/1ps

package shm_reference_gid_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;
  import collection::*;
  import shm_seq_item_package::*;

  `include "uvm_macros.svh"

  //----------------------------------------------------------------------------
  // @brief Provides the byte-memory API used by the production reference model.
  //
  // This component-only stand-in avoids loading licensed Synopsys VIP while
  // preserving the read, write, and incremental-initialization semantics used
  // by shm_reference. It is not compiled into the production environment.
  //----------------------------------------------------------------------------
  class svt_mem;
    typedef enum int {INCR} meminit_e;

    byte unsigned bytes[longint unsigned];
    longint unsigned init_base;

    //----------------------------------------------------------------------------
    // @brief Constructs an empty component-test memory.
    //
    // @param name Memory instance name retained for API compatibility.
    // @param suite Memory suite name retained for API compatibility.
    // @param data_width Data width retained for API compatibility.
    // @param address_width Address width retained for API compatibility.
    // @param lower_address Lower bound retained for API compatibility.
    // @param upper_address Upper bound retained for API compatibility.
    //----------------------------------------------------------------------------
    function new(string name,
                 string suite,
                 int data_width,
                 int address_width,
                 longint unsigned lower_address,
                 longint unsigned upper_address);
      init_base = 0;
    endfunction : new

    //----------------------------------------------------------------------------
    // @brief Selects deterministic incremental values for unwritten addresses.
    //
    // @param mode Initialization mode; only INCR is used by shm_reference.
    // @param base_value Base byte value for address zero.
    //----------------------------------------------------------------------------
    function void set_meminit(meminit_e mode, longint unsigned base_value);
      init_base = base_value;
    endfunction : set_meminit

    //----------------------------------------------------------------------------
    // @brief Writes one byte at the requested address.
    //
    // @param address Byte address to update.
    // @param value New byte value.
    //----------------------------------------------------------------------------
    function void write(longint unsigned address, byte unsigned value);
      bytes[address] = value;
    endfunction : write

    //----------------------------------------------------------------------------
    // @brief Reads a written byte or its deterministic incremental default.
    //
    // @param address Byte address to read.
    // @return Stored byte, or init_base plus address before the first write.
    //----------------------------------------------------------------------------
    function byte unsigned read(longint unsigned address);
      if (bytes.exists(address)) begin
        return bytes[address];
      end
      return byte'(init_base + address);
    endfunction : read
  endclass : svt_mem

  //----------------------------------------------------------------------------
  // @brief Supplies the configuration handle required by shm_reference build.
  //
  // Production configuration is intentionally not pulled into this standalone
  // component harness because the reference model only stores and prints it.
  //----------------------------------------------------------------------------
  class shm_environment_config extends uvm_object;
    //----------------------------------------------------------------------------
    // @brief Constructs the component-test reference configuration.
    //
    // @param name UVM object instance name.
    //----------------------------------------------------------------------------
    function new(string name = "shm_environment_config");
      super.new(name);
    endfunction : new

    //----------------------------------------------------------------------------
    // @brief Preserves the production configuration initialization call site.
    //----------------------------------------------------------------------------
    function void init();
    endfunction : init

    `uvm_object_utils(shm_environment_config)
  endclass : shm_environment_config

  `include "shm_physical_map_util.svh"
  `include "shm_reference.svh"

  //----------------------------------------------------------------------------
  // @brief Captures immutable reference transactions for independent checking.
  //----------------------------------------------------------------------------
  class shm_reference_gid_sink extends uvm_subscriber #(shm_wtrans_item);
    shm_wtrans_item items[$];

    //----------------------------------------------------------------------------
    // @brief Constructs the reference transaction sink.
    //
    // @param name UVM component instance name.
    // @param parent Parent component that owns this sink.
    //----------------------------------------------------------------------------
    function new(string name = "shm_reference_gid_sink", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    //----------------------------------------------------------------------------
    // @brief Queues one published immutable reference transaction.
    //
    // @param t Transaction published by shm_reference.
    //----------------------------------------------------------------------------
    virtual function void write(shm_wtrans_item t);
      items.push_back(t);
    endfunction : write

    `uvm_component_utils(shm_reference_gid_sink)
  endclass : shm_reference_gid_sink

  //----------------------------------------------------------------------------
  // @brief Checks V2M storage and M2V readback isolation across both gids.
  //----------------------------------------------------------------------------
  class shm_reference_gid_test extends uvm_test;
    shm_environment_config cfg;
    shm_reference reference_model;
    shm_reference_gid_sink sink;

    //----------------------------------------------------------------------------
    // @brief Constructs the reference gid-isolation test.
    //
    // @param name UVM component instance name.
    // @param parent Parent component that owns this test.
    //----------------------------------------------------------------------------
    function new(string name = "shm_reference_gid_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction : new

    //----------------------------------------------------------------------------
    // @brief Creates the standalone reference model and capture sink.
    //
    // @param phase UVM build phase.
    //----------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = shm_environment_config::type_id::create("cfg");
      cfg.init();
      uvm_config_db#(shm_environment_config)::set(this, "reference_model", "shm_environment_config", cfg);
      reference_model = shm_reference::type_id::create("reference_model", this);
      sink = shm_reference_gid_sink::type_id::create("sink", this);
    endfunction : build_phase

    //----------------------------------------------------------------------------
    // @brief Connects the reference output to the local capture sink.
    //
    // @param phase UVM connect phase.
    //----------------------------------------------------------------------------
    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      reference_model.wdata_ass_arr_port.connect(sink.analysis_export);
    endfunction : connect_phase

    //----------------------------------------------------------------------------
    // @brief Checks VTRANS transpose data and physical gid at one boundary wpid.
    //
    // @param wpid Absolute warp selecting gid zero or gid one.
    //----------------------------------------------------------------------------
    virtual function void check_vtrans_wpid(int unsigned wpid);
      shmins_vtrans_sequence_item item;
      shm_wtrans_item published_item;
      int unsigned previous_count;

      item = shmins_vtrans_sequence_item::type_id::create($sformatf("vtrans_wpid_%0d", wpid));
      if (!item.randomize() with {
            creq_dtype == DTYP_8;
            creq_itype == LDST_S;
            creq_wpid == wpid;
          }) begin
        `uvm_fatal("SHM_REFERENCE_VTRANS_RANDOMIZE",
                   $sformatf("failed to randomize VTRANS wpid %0d", wpid))
      end
      for (int unsigned source_thread = 0; source_thread < THD_N; source_thread++) begin
        for (int unsigned source_element = 0; source_element < 16; source_element++) begin
          item.creq_vdat[source_thread][source_element] = byte'((source_thread << 4) | source_element);
        end
      end

      previous_count = sink.items.size();
      reference_model.write_shmins_reference(item);
      if (sink.items.size() != previous_count + 1) begin
        `uvm_fatal("SHM_REFERENCE_VTRANS_COUNT", "reference did not publish the VTRANS transaction")
      end
      published_item = sink.items[previous_count];
      for (int unsigned target_thread = 0; target_thread < THD_N; target_thread++) begin
        for (int unsigned target_element = 0; target_element < 16; target_element++) begin
          int unsigned bank = published_item.bid_2d_array[target_thread][target_element];
          int unsigned gid = published_item.gid_2d_array[target_thread][target_element];
          int unsigned baddr = published_item.baddr_2d_array[target_thread][target_element];
          int unsigned physical_bank = physical_bank_index(bank, gid);
          byte unsigned expected = byte'((target_element << 4) | target_thread);

          if (gid != wpid / WARP_PER_GID || !published_item.wmap[physical_bank].exists(baddr) ||
              published_item.wmap[physical_bank][baddr] != expected) begin
            `uvm_fatal("SHM_REFERENCE_VTRANS_DATA",
                       $sformatf({"wpid %0d target [%0d][%0d] bank %0d gid %0d baddr 0x%0h ",
                                  "does not contain transposed byte 0x%0h"},
                                 wpid, target_thread, target_element, bank, gid, baddr, expected))
          end
        end
      end
    endfunction : check_vtrans_wpid

    //----------------------------------------------------------------------------
    // @brief Checks M2V writeback gid and encoded vaddr at one boundary wpid.
    //
    // @param wpid Absolute warp selecting the expected write gid.
    //----------------------------------------------------------------------------
    virtual function void check_m2v_wpid(int unsigned wpid);
      shmins_contiguous_sequence_item item;
      shm_wtrans_item published_item;
      int unsigned previous_count;
      int unsigned expected_physical_bank;

      item = shmins_contiguous_sequence_item::type_id::create($sformatf("m2v_wpid_%0d", wpid));
      if (!item.randomize() with {
            creq_rw == SHM_M2V;
            creq_dtype == DTYP_8;
            creq_itype == LDST_S;
            creq_space == SPACE_LOC;
            creq_wpid == wpid;
            creq_tmsk == 16'h0001;
            elem_num[0] == 1;
            creq_vmsk[0][0] == 1'b1;
          }) begin
        `uvm_fatal("SHM_REFERENCE_M2V_RANDOMIZE",
                   $sformatf("failed to randomize M2V wpid %0d", wpid))
      end

      previous_count = sink.items.size();
      reference_model.write_shmins_reference(item);
      if (sink.items.size() != previous_count + 1) begin
        `uvm_fatal("SHM_REFERENCE_M2V_COUNT", "reference did not publish the M2V transaction")
      end
      published_item = sink.items[previous_count];
      expected_physical_bank = physical_bank_index(0, wpid / WARP_PER_GID);
      if (!published_item.wmap[expected_physical_bank].exists(item.creq_vaddr)) begin
        `uvm_fatal("SHM_REFERENCE_M2V_VADDR",
                   $sformatf("wpid %0d did not write encoded vaddr 0x%0h in expected gid", wpid,
                             item.creq_vaddr))
      end
      for (int unsigned physical_bank = 0; physical_bank < PHYSICAL_BANK_N; physical_bank++) begin
        if (published_item.wmap[physical_bank].size() != 0 &&
            physical_bank % GID_N != wpid / WARP_PER_GID) begin
          `uvm_fatal("SHM_REFERENCE_M2V_GID",
                     $sformatf("wpid %0d wrote unexpected flattened physical bank %0d", wpid, physical_bank))
        end
      end
    endfunction : check_m2v_wpid

    //----------------------------------------------------------------------------
    // @brief Verifies that inactive thread payload X/Z is never interpreted.
    //
    // @param unknown_value X or Z value assigned to every inactive payload bit.
    //----------------------------------------------------------------------------
    virtual function void check_inactive_payload_xz(logic unknown_value);
      shmins_contiguous_sequence_item item;
      shm_wtrans_item published_item;
      int unsigned previous_count;

      item = shmins_contiguous_sequence_item::type_id::create(
          unknown_value === 1'bx ? "inactive_payload_x" : "inactive_payload_z");
      if (!item.randomize() with {
            creq_rw == SHM_V2M;
            creq_dtype == DTYP_8;
            creq_atype_w == ATYP_32;
            creq_atype_s == ATYP_U;
            creq_atype_g == GAUTO_1B;
            creq_itype == LDST_S;
            creq_space == SPACE_LOC;
            creq_wpid == 0;
            creq_tmsk == 16'h0001;
            elem_num[0] == 1;
            creq_vmsk[0] == VEC_BYTE_N'(1);
          }) begin
        `uvm_fatal("SHM_REFERENCE_INACTIVE_RANDOMIZE", "failed to randomize inactive-payload item")
      end
      for (int unsigned thread_idx = 1; thread_idx < THD_N; thread_idx++) begin
        item.creq_prio[thread_idx] = {PRIO_W{unknown_value}};
        item.creq_len[thread_idx] = {8{unknown_value}};
        item.creq_vmsk[thread_idx] = {VEC_BYTE_N{unknown_value}};
        item.set_creq_offs(thread_idx, {VEC_W{unknown_value}});
        item.creq_vdat[thread_idx] = {VEC_W{unknown_value}};
      end

      previous_count = sink.items.size();
      reference_model.write_shmins_reference(item);
      if (sink.items.size() != previous_count + 1) begin
        `uvm_fatal("SHM_REFERENCE_INACTIVE_COUNT", "reference did not publish inactive-payload item")
      end
      published_item = sink.items[previous_count];
      if (published_item.baddr_2d_array[0].size() != 1 ||
          published_item.wstrb_2d_array[0].size() != 1) begin
        `uvm_fatal("SHM_REFERENCE_ACTIVE_ARRAY", "active thread did not retain its one-byte access")
      end
      for (int unsigned thread_idx = 1; thread_idx < THD_N; thread_idx++) begin
        if (published_item.baddr_2d_array[thread_idx].size() != 0 ||
            published_item.bid_2d_array[thread_idx].size() != 0 ||
            published_item.gid_2d_array[thread_idx].size() != 0 ||
            published_item.logical_addr_2d_array[thread_idx].size() != 0 ||
            published_item.wstrb_2d_array[thread_idx].size() != 0) begin
          `uvm_fatal("SHM_REFERENCE_INACTIVE_ARRAY",
                     $sformatf("inactive thread %0d produced derived reference state", thread_idx))
        end
      end
    endfunction : check_inactive_payload_xz

    //----------------------------------------------------------------------------
    // @brief Creates one sparse-mask topology item for reference don’t-care tests.
    //
    // @param topology 0 for contiguous, 1 for strided, or 2 for indexed.
    // @param direction V2M or M2V request direction.
    // @param item_name UVM object instance name.
    // @return Generated item with thread zero and elements 0/7 active.
    //----------------------------------------------------------------------------
    virtual function shmins_sequence_item create_dontcare_item(int unsigned topology,
                                                                creq_rw_e direction,
                                                                string item_name);
      shmins_sequence_item item;

      case (topology)
        0: item = shmins_contiguous_sequence_item::type_id::create(item_name);
        1: item = shmins_strided_sequence_item::type_id::create(item_name);
        2: item = shmins_indexed_sequence_item::type_id::create(item_name);
        default: begin
          `uvm_fatal("SHM_REFERENCE_DONTCARE_TOPOLOGY", $sformatf("unsupported topology %0d", topology))
          return null;
        end
      endcase
      if (!item.randomize() with {
            creq_rw == local::direction;
            creq_dtype == DTYP_8;
            creq_atype_w == ATYP_16;
            creq_atype_s == ATYP_U;
            creq_atype_g == GAUTO_1B;
            creq_space == SPACE_LOC;
            creq_wpid == 0;
            creq_tmsk == 16'h0001;
            elem_num[0] == 8;
            creq_vmsk[0][7:0] == 8'h81;
          }) begin
        `uvm_fatal("SHM_REFERENCE_DONTCARE_RANDOMIZE", $sformatf("failed to randomize %s", item_name))
      end
      return item;
    endfunction : create_dontcare_item

    //----------------------------------------------------------------------------
    // @brief Counts active bytes in one flattened reference write map.
    //
    // @param item Published reference item containing the write map.
    // @return Sum of associative byte entries across all physical BANKs.
    //----------------------------------------------------------------------------
    virtual function int unsigned wmap_byte_count(shm_wtrans_item item);
      int unsigned count = 0;

      foreach (item.wmap[physical_bank]) begin
        count += item.wmap[physical_bank].size();
      end
      return count;
    endfunction : wmap_byte_count

    //----------------------------------------------------------------------------
    // @brief Verifies masked offsets/data and M2V unused data are never consumed.
    //----------------------------------------------------------------------------
    virtual function void check_dontcare_payload_xz();
      shmins_sequence_item item;
      int unsigned previous_count;

      item = create_dontcare_item(0, SHM_V2M, "reference_contiguous_x");
      void'(shmins_dontcare_x_util::poison_masked_element_data(item, 1'bx));
      void'(shmins_dontcare_x_util::poison_unused_offset_slices(item, 1'bx));
      void'(shmins_dontcare_x_util::poison_out_of_length_payload(item, 1'bx));
      previous_count = sink.items.size();
      reference_model.write_shmins_reference(item);
      if (sink.items.size() != previous_count + 1 || wmap_byte_count(sink.items[previous_count]) != 2) begin
        `uvm_fatal("X_REF_002", "masked contiguous payload changed the two-byte reference result")
      end

      item = create_dontcare_item(2, SHM_V2M, "reference_indexed_x");
      void'(shmins_dontcare_x_util::poison_masked_element_data(item, 1'bx));
      void'(shmins_dontcare_x_util::poison_indexed_masked_offsets(item, 1'bx));
      void'(shmins_dontcare_x_util::poison_out_of_length_payload(item, 1'bx));
      previous_count = sink.items.size();
      reference_model.write_shmins_reference(item);
      if (sink.items.size() != previous_count + 1 || wmap_byte_count(sink.items[previous_count]) != 2) begin
        `uvm_fatal("X_REF_003", "masked indexed offset/data changed the two-byte reference result")
      end

      item = create_dontcare_item(1, SHM_V2M, "reference_strided_x");
      void'(shmins_dontcare_x_util::poison_masked_element_data(item, 1'bx));
      void'(shmins_dontcare_x_util::poison_unused_offset_slices(item, 1'bx));
      previous_count = sink.items.size();
      reference_model.write_shmins_reference(item);
      if (sink.items.size() != previous_count + 1 || wmap_byte_count(sink.items[previous_count]) != 2) begin
        `uvm_fatal("X_REF_004", "unused strided offsets changed the two-byte reference result")
      end

      item = create_dontcare_item(0, SHM_M2V, "reference_m2v_x");
      void'(shmins_dontcare_x_util::poison_m2v_vdata(item, 1'bx));
      previous_count = sink.items.size();
      reference_model.write_shmins_reference(item);
      if (sink.items.size() != previous_count + 1 || wmap_byte_count(sink.items[previous_count]) != 2) begin
        `uvm_fatal("X_REF_005", "M2V input-data X changed the two-byte read/writeback result")
      end
    endfunction : check_dontcare_payload_xz

    //----------------------------------------------------------------------------
    // @brief Runs equal-BADDR V2M writes and M2V reads in gid zero and gid one.
    //
    // @param phase UVM run phase controlling the test objection.
    //----------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
      shmins_contiguous_sequence_item low_write;
      shmins_contiguous_sequence_item high_write;
      shmins_contiguous_sequence_item low_read;
      shmins_contiguous_sequence_item high_read;
      int unsigned bank;
      int unsigned baddr;
      int unsigned low_index;
      int unsigned high_index;

      phase.raise_objection(this);
      low_write = shmins_contiguous_sequence_item::type_id::create("low_write");
      if (!low_write.randomize() with {
            creq_rw == SHM_V2M;
            creq_dtype == DTYP_8;
            creq_itype == LDST_S;
            creq_space == SPACE_LOC;
            creq_wpid == 0;
            creq_tmsk == 16'h0001;
            elem_num[0] == 1;
            creq_vmsk[0][0] == 1'b1;
          }) begin
        `uvm_fatal("SHM_REFERENCE_GID_RANDOMIZE", "failed to randomize gid-zero V2M item")
      end
      low_write.creq_vdat[0][7:0] = 8'h35;

      high_write = shmins_contiguous_sequence_item::type_id::create("high_write");
      high_write.copy(low_write);
      high_write.creq_wpid = 4;
      high_write.creq_vdat[0][7:0] = 8'hca;
      reference_model.write_shmins_reference(low_write);
      reference_model.write_shmins_reference(high_write);

      if (sink.items.size() != 2) begin
        `uvm_fatal("SHM_REFERENCE_GID_V2M_COUNT", "reference did not publish both V2M transactions")
      end
      bank = sink.items[0].bid_2d_array[0][0];
      baddr = sink.items[0].baddr_2d_array[0][0];
      if (sink.items[0].gid_2d_array[0][0] != 0 || sink.items[1].gid_2d_array[0][0] != 1 ||
          sink.items[1].bid_2d_array[0][0] != bank || sink.items[1].baddr_2d_array[0][0] != baddr) begin
        `uvm_fatal("SHM_REFERENCE_GID_ADDRESS", "equal logical addresses did not produce equal BADDR/different gid")
      end
      if (reference_model.ref_banks[bank][0].read(baddr) != 8'h35 ||
          reference_model.ref_banks[bank][1].read(baddr) != 8'hca) begin
        `uvm_fatal("SHM_REFERENCE_GID_STORAGE", "gid-specific reference bytes were merged or overwritten")
      end
      low_index = physical_bank_index(bank, 0);
      high_index = physical_bank_index(bank, 1);
      if (!sink.items[0].wmap[low_index].exists(baddr) || !sink.items[1].wmap[high_index].exists(baddr) ||
          low_index == high_index) begin
        `uvm_fatal("SHM_REFERENCE_GID_WMAP", "flattened wmap did not preserve gid isolation")
      end

      low_read = shmins_contiguous_sequence_item::type_id::create("low_read");
      low_read.copy(low_write);
      low_read.creq_rw = SHM_M2V;
      if (!low_read.generate_m2v_writeback_address()) begin
        `uvm_fatal("SHM_REFERENCE_GID_LOW_VADDR", "failed to generate gid-zero M2V writeback")
      end
      high_read = shmins_contiguous_sequence_item::type_id::create("high_read");
      high_read.copy(high_write);
      high_read.creq_rw = SHM_M2V;
      if (!high_read.generate_m2v_writeback_address()) begin
        `uvm_fatal("SHM_REFERENCE_GID_HIGH_VADDR", "failed to generate gid-one M2V writeback")
      end
      reference_model.write_shmins_reference(low_read);
      reference_model.write_shmins_reference(high_read);

      if (sink.items.size() != 4 ||
          !sink.items[2].wmap[physical_bank_index(0, 0)].exists(low_read.creq_vaddr) ||
          !sink.items[3].wmap[physical_bank_index(0, 1)].exists(high_read.creq_vaddr) ||
          sink.items[2].wmap[physical_bank_index(0, 0)][low_read.creq_vaddr] != 8'h35 ||
          sink.items[3].wmap[physical_bank_index(0, 1)][high_read.creq_vaddr] != 8'hca) begin
        `uvm_fatal("SHM_REFERENCE_GID_M2V", "M2V readback did not preserve gid-specific source data")
      end

      check_vtrans_wpid(3);
      check_vtrans_wpid(4);
      check_m2v_wpid(3);
      check_inactive_payload_xz(1'bx);
      check_inactive_payload_xz(1'bz);
      check_dontcare_payload_xz();

      `uvm_info("SHM_REFERENCE_GID_TEST", "reference gid-isolation component test: PASS", UVM_LOW)
      phase.drop_objection(this);
    endtask : run_phase

    `uvm_component_utils(shm_reference_gid_test)
  endclass : shm_reference_gid_test
endpackage : shm_reference_gid_test_pkg

module shm_reference_gid_tb;
  import uvm_pkg::*;
  import shm_reference_gid_test_pkg::*;

  initial begin
    run_test("shm_reference_gid_test");
  end
endmodule : shm_reference_gid_tb
