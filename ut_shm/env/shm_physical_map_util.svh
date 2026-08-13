`ifndef INC_SHM_PHYSICAL_MAP_UTIL_SVH
`define INC_SHM_PHYSICAL_MAP_UTIL_SVH

//------------------------------------------------------------------------------
// @brief Formats flattened physical SHM maps as BANK/GID/BADDR hierarchies.
//
// The collection containers remain indexed by physical_bank_index() so their
// set operations stay unchanged. This class only provides a domain-aware debug
// view and does not modify, normalize, or compare map content.
//------------------------------------------------------------------------------
class shm_physical_map_util;
    typedef vlm2aa::baddr_t baddr_t;
    typedef vlm2aa::wmap_t wmap_t;
    typedef aa_of_q_array_util#(PHYSICAL_BANK_N, baddr_t, byte) wmmap_util;
    typedef wmmap_util::aa_of_q_array_t wmmap_t;

    //-------------------------------------------------------------------------
    // @brief Formats one queue of historical byte values on a single line.
    //
    // @param values Byte values to format in their stored order.
    // @return Comma-separated hexadecimal values enclosed in braces.
    //-------------------------------------------------------------------------
    static function string sprint_byte_values(const ref byte values[$]);
        string result = "{";

        foreach (values[value_idx]) begin
            if (value_idx > 0) begin
                result = {result, ", "};
            end
            result = {result, $sformatf("0x%02x", values[value_idx])};
        end
        return {result, "}"};
    endfunction : sprint_byte_values

    //-------------------------------------------------------------------------
    // @brief Formats a scalar byte map using BANK, GID, and BADDR labels.
    //
    // @param value Flattened physical byte map to format.
    // @param name Label placed before the formatted hierarchy.
    // @param show_empty When set, includes empty BANK/GID groups.
    // @return Sparse hierarchical text and a non-empty group/entry summary.
    //-------------------------------------------------------------------------
    static function string sprint_wmap(const ref wmap_t value,
                                       input string name = "wmap",
                                       input bit show_empty = 1'b0);
        string body;
        int unsigned entry_count;
        int unsigned group_count;

        for (int unsigned bank_id = 0; bank_id < BANK_N; bank_id++) begin
            string bank_body;

            for (int unsigned gid = 0; gid < GID_N; gid++) begin
                int unsigned physical_bank;
                int unsigned group_entry_count;
                string group_body;

                physical_bank = physical_bank_index(bank_id, gid);
                group_entry_count = value[physical_bank].num();
                if (group_entry_count == 0 && !show_empty) begin
                    continue;
                end
                if (group_entry_count == 0) begin
                    group_body = $sformatf("\n    GID[%0d]: (empty)", gid);
                end else begin
                    group_count++;
                    entry_count += group_entry_count;
                    group_body = $sformatf("\n    GID[%0d] entries=%0d:", gid, group_entry_count);
                    foreach (value[physical_bank][baddr]) begin
                        group_body = {group_body,
                                      $sformatf("\n      BADDR[0x%04x] = 0x%02x",
                                                baddr, value[physical_bank][baddr])};
                    end
                end
                bank_body = {bank_body, group_body};
            end
            if (bank_body.len() > 0) begin
                body = {body, $sformatf("\n  BANK[%02d]:", bank_id), bank_body};
            end
        end

        if (body.len() == 0) begin
            return name.len() > 0 ? {name, ": (empty)"} : "(empty)";
        end
        if (name.len() > 0) begin
            return {$sformatf("%s: groups=%0d entries=%0d", name, group_count, entry_count), body};
        end
        return {$sformatf("groups=%0d entries=%0d", group_count, entry_count), body};
    endfunction : sprint_wmap

    //-------------------------------------------------------------------------
    // @brief Formats a byte multimap using BANK, GID, and BADDR labels.
    //
    // @param value Flattened physical byte multimap to format.
    // @param name Label placed before the formatted hierarchy.
    // @param show_empty When set, includes empty BANK/GID groups.
    // @return Sparse hierarchical text and a non-empty group/entry summary.
    //-------------------------------------------------------------------------
    static function string sprint_wmmap(const ref wmmap_t value,
                                        input string name = "wmmap",
                                        input bit show_empty = 1'b0);
        string body;
        int unsigned entry_count;
        int unsigned group_count;

        for (int unsigned bank_id = 0; bank_id < BANK_N; bank_id++) begin
            string bank_body;

            for (int unsigned gid = 0; gid < GID_N; gid++) begin
                int unsigned physical_bank;
                int unsigned group_entry_count;
                string group_body;

                physical_bank = physical_bank_index(bank_id, gid);
                group_entry_count = value[physical_bank].num();
                if (group_entry_count == 0 && !show_empty) begin
                    continue;
                end
                if (group_entry_count == 0) begin
                    group_body = $sformatf("\n    GID[%0d]: (empty)", gid);
                end else begin
                    group_count++;
                    entry_count += group_entry_count;
                    group_body = $sformatf("\n    GID[%0d] entries=%0d:", gid, group_entry_count);
                    foreach (value[physical_bank][baddr]) begin
                        group_body = {group_body,
                                      $sformatf("\n      BADDR[0x%04x] = %s", baddr,
                                                sprint_byte_values(value[physical_bank][baddr]))};
                    end
                end
                bank_body = {bank_body, group_body};
            end
            if (bank_body.len() > 0) begin
                body = {body, $sformatf("\n  BANK[%02d]:", bank_id), bank_body};
            end
        end

        if (body.len() == 0) begin
            return name.len() > 0 ? {name, ": (empty)"} : "(empty)";
        end
        if (name.len() > 0) begin
            return {$sformatf("%s: groups=%0d entries=%0d", name, group_count, entry_count), body};
        end
        return {$sformatf("groups=%0d entries=%0d", group_count, entry_count), body};
    endfunction : sprint_wmmap
endclass : shm_physical_map_util

`endif // INC_SHM_PHYSICAL_MAP_UTIL_SVH
