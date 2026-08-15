`ifndef INC_SHM_ADDRESS_COVERAGE_SVH
`define INC_SHM_ADDRESS_COVERAGE_SVH

//------------------------------------------------------------------------------
// @brief Samples gid-aware logical and physical addresses produced by reference.
//
// This passive collector consumes the same immutable write transaction as the
// scoreboard. It does not generate expected addresses or alter checking order.
//------------------------------------------------------------------------------
class shm_address_coverage extends uvm_subscriber #(shm_wtrans_item);
  // Number of active bytes sampled at absolute-warp boundary targets.
  longint unsigned sampled_active_byte_count;

  // Number of samples in gid zero and gid one.
  longint unsigned sampled_gid_count[GID_N];

  // Address coverage limited to the first directed dual-gid batch.
  covergroup address_cg with function sample(
      int unsigned direction,
      int unsigned space,
      int unsigned absolute_warp,
      int unsigned gid,
      int unsigned laddr,
      int unsigned wpnum);
    option.per_instance = 1;
    cp_direction: coverpoint direction { bins v2m = {SHM_V2M}; bins m2v = {SHM_M2V}; }
    cp_space: coverpoint space { bins loc = {0}; bins wrp = {1}; bins blk = {2}; }
    cp_warp: coverpoint absolute_warp {
      bins low_first = {0};
      bins low_last = {3};
      bins high_first = {4};
      bins high_last = {7};
      bins other[] = {[1:2], [5:6]};
    }
    cp_gid: coverpoint gid { bins low = {0}; bins high = {1}; }
    cp_laddr: coverpoint laddr {
      bins first = {0};
      bins interior = {[1:WARP_STEP-2]};
      bins last = {WARP_STEP-1};
    }
    cp_wpnum: coverpoint wpnum { bins one = {1}; bins two = {2}; bins four = {4}; }
    cx_space_warp_gid_laddr: cross cp_space, cp_warp, cp_gid, cp_laddr;
  endgroup

  // M2V read/write gid relationship coverage.
  covergroup m2v_gid_cg with function sample(int unsigned read_gid, int unsigned write_gid);
    option.per_instance = 1;
    cp_read_gid: coverpoint read_gid { bins low = {0}; bins high = {1}; }
    cp_write_gid: coverpoint write_gid { bins low = {0}; bins high = {1}; }
    cx_read_write_gid: cross cp_read_gid, cp_write_gid;
  endgroup

  //----------------------------------------------------------------------------
  // @brief Constructs the passive address coverage collector.
  //
  // @param name UVM component instance name.
  // @param parent Parent component that owns this collector.
  //----------------------------------------------------------------------------
  extern function new(string name = "shm_address_coverage", uvm_component parent = null);

  //----------------------------------------------------------------------------
  // @brief Samples all active bytes represented by one reference transaction.
  //
  // @param t Read-only reference transaction with generated address arrays.
  //----------------------------------------------------------------------------
  extern virtual function void write(shm_wtrans_item t);

  `uvm_component_utils(shm_address_coverage)
endclass : shm_address_coverage

function shm_address_coverage::new(string name = "shm_address_coverage", uvm_component parent = null);
  super.new(name, parent);
  sampled_active_byte_count = 0;
  foreach (sampled_gid_count[gid]) begin
    sampled_gid_count[gid] = 0;
  end
  address_cg = new();
  m2v_gid_cg = new();
endfunction : new

function void shm_address_coverage::write(shm_wtrans_item t);
  shm_wtrans_item item = t;
  if (item == null) begin
    `uvm_error("SHM_ADDRESS_COVERAGE_NULL", "received a null reference transaction")
    return;
  end

  for (int unsigned thread_idx = 0; thread_idx < BANK_N; thread_idx++) begin
    foreach (item.logical_addr_2d_array[thread_idx][elem_idx]) begin
      shm_logical_addr_t logical_addr = item.logical_addr_2d_array[thread_idx][elem_idx];
      int unsigned gid = item.gid_2d_array[thread_idx][elem_idx];

      for (int unsigned byte_lane = 0; byte_lane < item.data_byte_w(); byte_lane++) begin
        if (!item.wstrb_2d_array[thread_idx][elem_idx][byte_lane]) begin
          continue;
        end
        address_cg.sample(item.creq_rw, item.creq_space, logical_addr.warp_id, gid,
                          int'(logical_addr.laddr) + byte_lane, item.creq_wpnum);
        sampled_active_byte_count++;
        sampled_gid_count[gid]++;
      end
      if (item.creq_rw == SHM_M2V) begin
        m2v_gid_cg.sample(gid, int'(item.creq_wpid) / WARP_PER_GID);
      end
    end
  end
endfunction : write

`endif // INC_SHM_ADDRESS_COVERAGE_SVH
