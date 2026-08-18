`ifndef INC_SHMINS_DONTCARE_X_UTIL_SVH
`define INC_SHMINS_DONTCARE_X_UTIL_SVH

//------------------------------------------------------------------------------
// @brief Injects X or Z only into SHMINS payload slices ignored by the protocol.
//
// The utility edits an already generated and validated transaction without
// changing its semantic address model. It does not randomize, repack offsets,
// validate the transaction, or send it through a sequencer.
//------------------------------------------------------------------------------
class shmins_dontcare_x_util;
  //----------------------------------------------------------------------------
  // @brief Replaces every inactive thread payload field with one four-state value.
  //
  // @param item Transaction whose inactive payload is poisoned.
  // @param poison_value X or Z value replicated across each target field.
  // @return 1 when arguments are valid and all inactive threads are updated.
  //----------------------------------------------------------------------------
  extern static function bit poison_inactive_threads(shmins_sequence_item item, logic poison_value);

  //----------------------------------------------------------------------------
  // @brief Poisons data bytes belonging to masked, length-bounded elements.
  //
  // @param item Transaction whose masked element data is poisoned.
  // @param poison_value X or Z value replicated across each target byte.
  // @return 1 when every inspected mask bit is known and no active byte is changed.
  //----------------------------------------------------------------------------
  extern static function bit poison_masked_element_data(shmins_sequence_item item, logic poison_value);

  //----------------------------------------------------------------------------
  // @brief Poisons packed offsets belonging to masked indexed elements.
  //
  // @param item LDSTE_V transaction whose masked offsets are poisoned.
  // @param poison_value X or Z value replicated across each target offset slice.
  // @return 1 when the item is indexed and every inspected mask bit is known.
  //----------------------------------------------------------------------------
  extern static function bit poison_indexed_masked_offsets(shmins_sequence_item item, logic poison_value);

  //----------------------------------------------------------------------------
  // @brief Poisons packed offset slices unused by a contiguous or strided request.
  //
  // Offset element zero remains known because it is the shared start offset or
  // stride. Indexed requests are rejected and must use the indexed APIs.
  //
  // @param item Contiguous or strided transaction whose unused slices are poisoned.
  // @param poison_value X or Z value replicated across each target offset slice.
  // @return 1 when the topology is supported and no shared offset is changed.
  //----------------------------------------------------------------------------
  extern static function bit poison_unused_offset_slices(shmins_sequence_item item, logic poison_value);

  //----------------------------------------------------------------------------
  // @brief Poisons mask, data, and indexed offset payload beyond each thread length.
  //
  // @param item Transaction whose out-of-length payload is poisoned.
  // @param poison_value X or Z value replicated across each target slice.
  // @return 1 when thread masks and lengths are known and all targets are ignored.
  //----------------------------------------------------------------------------
  extern static function bit poison_out_of_length_payload(shmins_sequence_item item, logic poison_value);

  //----------------------------------------------------------------------------
  // @brief Replaces active-thread input data of an M2V request with X or Z.
  //
  // @param item M2V transaction whose unused input data is poisoned.
  // @param poison_value X or Z value replicated across each active-thread vector.
  // @return 1 when the request direction and arguments are valid.
  //----------------------------------------------------------------------------
  extern static function bit poison_m2v_vdata(shmins_sequence_item item, logic poison_value);

  //----------------------------------------------------------------------------
  // @brief Checks common item, poison-value, and thread-mask preconditions.
  //
  // @param item Transaction supplied to a public poisoning API.
  // @param poison_value Requested X or Z value.
  // @return 1 when the item is non-null, poison value is X/Z, and tmsk is known.
  //----------------------------------------------------------------------------
  extern protected static function bit valid_arguments(shmins_sequence_item item, logic poison_value);

  //----------------------------------------------------------------------------
  // @brief Writes one packed offset slice without changing other slices.
  //
  // @param item Transaction containing the packed offset vector.
  // @param thread_idx Thread whose vector is updated.
  // @param offset_idx Offset element index within the vector.
  // @param poison_value X or Z value replicated across the selected slice.
  // @return 1 when the selected offset slice exists.
  //----------------------------------------------------------------------------
  extern protected static function bit poison_offset_slice(shmins_sequence_item item,
                                                            int unsigned thread_idx,
                                                            int unsigned offset_idx,
                                                            logic poison_value);
endclass : shmins_dontcare_x_util

function bit shmins_dontcare_x_util::valid_arguments(shmins_sequence_item item, logic poison_value);
  if (item == null) begin
    `uvm_error("SHMINS_DONTCARE_NULL", "don’t-care poisoning requires a non-null transaction")
    return 1'b0;
  end
  if (poison_value !== 1'bx && poison_value !== 1'bz) begin
    `uvm_error("SHMINS_DONTCARE_VALUE", "don’t-care poison value must be X or Z")
    return 1'b0;
  end
  if ($isunknown(item.creq_tmsk)) begin
    `uvm_error("SHMINS_DONTCARE_TMSK", "don’t-care poisoning requires a known thread mask")
    return 1'b0;
  end
  return 1'b1;
endfunction : valid_arguments

function bit shmins_dontcare_x_util::poison_offset_slice(shmins_sequence_item item,
                                                          int unsigned thread_idx,
                                                          int unsigned offset_idx,
                                                          logic poison_value);
  logic [VEC_W-1:0] packed_offsets;

  if (thread_idx >= THD_N || offset_idx >= item.offs_elem_max()) begin
    `uvm_error("SHMINS_DONTCARE_OFFSET_INDEX",
               $sformatf("thread=%0d offset=%0d is outside the packed offset vector", thread_idx, offset_idx))
    return 1'b0;
  end
  packed_offsets = item.creq_offs(thread_idx);
  case (item.offs_bit_w())
    16: packed_offsets[offset_idx * 16 +: 16] = {16{poison_value}};
    32: packed_offsets[offset_idx * 32 +: 32] = {32{poison_value}};
    default: begin
      `uvm_error("SHMINS_DONTCARE_OFFSET_WIDTH",
                 $sformatf("unsupported packed offset width %0d", item.offs_bit_w()))
      return 1'b0;
    end
  endcase
  item.set_creq_offs(thread_idx, packed_offsets);
  return 1'b1;
endfunction : poison_offset_slice

function bit shmins_dontcare_x_util::poison_inactive_threads(shmins_sequence_item item, logic poison_value);
  if (!valid_arguments(item, poison_value)) begin
    return 1'b0;
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    if (item.creq_tmsk[thread_idx] !== 1'b0) begin
      continue;
    end
    item.creq_prio[thread_idx] = {PRIO_W{poison_value}};
    item.creq_len[thread_idx] = {8{poison_value}};
    item.creq_vmsk[thread_idx] = {VEC_BYTE_N{poison_value}};
    item.set_creq_offs(thread_idx, {VEC_W{poison_value}});
    item.creq_vdat[thread_idx] = {VEC_W{poison_value}};
  end
  return 1'b1;
endfunction : poison_inactive_threads

function bit shmins_dontcare_x_util::poison_masked_element_data(shmins_sequence_item item,
                                                                 logic poison_value);
  if (!valid_arguments(item, poison_value)) begin
    return 1'b0;
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    int unsigned element_count;

    if (item.creq_tmsk[thread_idx] !== 1'b1) begin
      continue;
    end
    if ($isunknown(item.creq_len[thread_idx])) begin
      `uvm_error("SHMINS_DONTCARE_LENGTH", $sformatf("thread %0d length contains X/Z", thread_idx))
      return 1'b0;
    end
    element_count = item.thread_elem_cnt(thread_idx);
    if (element_count > item.max_elem_cnt()) begin
      element_count = item.max_elem_cnt();
    end
    for (int unsigned elem_idx = 0; elem_idx < element_count; elem_idx++) begin
      if ($isunknown(item.creq_vmsk[thread_idx][elem_idx])) begin
        `uvm_error("SHMINS_DONTCARE_MASK",
                   $sformatf("thread %0d element %0d mask contains X/Z", thread_idx, elem_idx))
        return 1'b0;
      end
      if (item.creq_vmsk[thread_idx][elem_idx] === 1'b0) begin
        for (int unsigned byte_lane = 0; byte_lane < item.data_byte_w(); byte_lane++) begin
          item.creq_vdat[thread_idx][elem_idx * item.data_byte_w() + byte_lane] = {8{poison_value}};
        end
      end
    end
  end
  return 1'b1;
endfunction : poison_masked_element_data

function bit shmins_dontcare_x_util::poison_indexed_masked_offsets(shmins_sequence_item item,
                                                                   logic poison_value);
  if (!valid_arguments(item, poison_value)) begin
    return 1'b0;
  end
  if (item.creq_itype != LDSTE_V) begin
    `uvm_error("SHMINS_DONTCARE_INDEXED_ONLY", "masked per-element offset poisoning requires LDSTE_V")
    return 1'b0;
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    int unsigned element_count;

    if (item.creq_tmsk[thread_idx] !== 1'b1) begin
      continue;
    end
    if ($isunknown(item.creq_len[thread_idx])) begin
      `uvm_error("SHMINS_DONTCARE_LENGTH", $sformatf("thread %0d length contains X/Z", thread_idx))
      return 1'b0;
    end
    element_count = item.thread_elem_cnt(thread_idx);
    if (element_count > item.max_elem_cnt()) begin
      element_count = item.max_elem_cnt();
    end
    for (int unsigned elem_idx = 0; elem_idx < element_count; elem_idx++) begin
      if ($isunknown(item.creq_vmsk[thread_idx][elem_idx])) begin
        `uvm_error("SHMINS_DONTCARE_MASK",
                   $sformatf("thread %0d element %0d mask contains X/Z", thread_idx, elem_idx))
        return 1'b0;
      end
      if (item.creq_vmsk[thread_idx][elem_idx] === 1'b0 &&
          !poison_offset_slice(item, thread_idx, elem_idx, poison_value)) begin
        return 1'b0;
      end
    end
  end
  return 1'b1;
endfunction : poison_indexed_masked_offsets

function bit shmins_dontcare_x_util::poison_unused_offset_slices(shmins_sequence_item item,
                                                                 logic poison_value);
  if (!valid_arguments(item, poison_value)) begin
    return 1'b0;
  end
  if (!(item.creq_itype inside {LDST_S, LDST_V, LDSTE_S})) begin
    `uvm_error("SHMINS_DONTCARE_SHARED_ONLY", "unused shared-offset poisoning rejects indexed requests")
    return 1'b0;
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    if (item.creq_tmsk[thread_idx] !== 1'b1) begin
      continue;
    end
    for (int unsigned offset_idx = 1; offset_idx < item.offs_elem_max(); offset_idx++) begin
      if (!poison_offset_slice(item, thread_idx, offset_idx, poison_value)) begin
        return 1'b0;
      end
    end
  end
  return 1'b1;
endfunction : poison_unused_offset_slices

function bit shmins_dontcare_x_util::poison_out_of_length_payload(shmins_sequence_item item,
                                                                  logic poison_value);
  if (!valid_arguments(item, poison_value)) begin
    return 1'b0;
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    int unsigned byte_count;
    int unsigned element_count;

    if (item.creq_tmsk[thread_idx] !== 1'b1) begin
      continue;
    end
    if ($isunknown(item.creq_len[thread_idx])) begin
      `uvm_error("SHMINS_DONTCARE_LENGTH", $sformatf("thread %0d length contains X/Z", thread_idx))
      return 1'b0;
    end
    byte_count = int'(item.creq_len[thread_idx]);
    element_count = item.thread_elem_cnt(thread_idx);
    if (element_count > item.max_elem_cnt()) begin
      element_count = item.max_elem_cnt();
    end
    for (int unsigned elem_idx = element_count; elem_idx < VEC_BYTE_N; elem_idx++) begin
      item.creq_vmsk[thread_idx][elem_idx] = poison_value;
    end
    for (int unsigned byte_idx = byte_count; byte_idx < VEC_BYTE_N; byte_idx++) begin
      item.creq_vdat[thread_idx][byte_idx] = {8{poison_value}};
    end
    if (item.creq_itype == LDSTE_V) begin
      for (int unsigned offset_idx = element_count; offset_idx < item.offs_elem_max(); offset_idx++) begin
        if (!poison_offset_slice(item, thread_idx, offset_idx, poison_value)) begin
          return 1'b0;
        end
      end
    end
  end
  return 1'b1;
endfunction : poison_out_of_length_payload

function bit shmins_dontcare_x_util::poison_m2v_vdata(shmins_sequence_item item, logic poison_value);
  if (!valid_arguments(item, poison_value)) begin
    return 1'b0;
  end
  if (item.creq_rw != SHM_M2V) begin
    `uvm_error("SHMINS_DONTCARE_M2V_ONLY", "unused input-data poisoning requires an M2V transaction")
    return 1'b0;
  end
  for (int unsigned thread_idx = 0; thread_idx < THD_N; thread_idx++) begin
    if (item.creq_tmsk[thread_idx] === 1'b1) begin
      item.creq_vdat[thread_idx] = {VEC_W{poison_value}};
    end
  end
  return 1'b1;
endfunction : poison_m2v_vdata

`endif // INC_SHMINS_DONTCARE_X_UTIL_SVH
