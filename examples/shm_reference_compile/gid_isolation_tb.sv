`timescale 1ns/1ps

package shm_reference_gid_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;
  import shm_seq_item_package::*;
  import shm_env_package::*;

  `include "uvm_macros.svh"

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
