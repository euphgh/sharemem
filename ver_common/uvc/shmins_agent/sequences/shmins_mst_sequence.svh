`ifndef INC_SHMINS_MST_SEQUENCE_SVH
`define INC_SHMINS_MST_SEQUENCE_SVH

//-----------------------------------------------------------------------------
// Class: shmins_mst_sequence
//-----------------------------------------------------------------------------
class shmins_mst_sequence extends uvm_sequence #(shmins_sequence_item);

    // Data Members
    //---------------------------------------------------------------------
    rand int trans_num = 10;

    // Interface Instantiation
    //---------------------------------------------------------------------
    virtual shmins_interface vif;

    // Constraints
    //---------------------------------------------------------------------

    // Methods
    //---------------------------------------------------------------------

    // Standard UVM Methods
    //---------------------------------------------------------------------
    extern function new(string name="shmins_mst_sequence");
    extern virtual task body();

    task pre_start();
        uvm_phase phase = get_starting_phase();
        if (phase != null)
            phase.raise_objection(this);

        if (!uvm_config_db#(virtual shmins_interface)::get(
                .cntxt(null), .inst_name(""), .field_name("shmins_vif"), .value(vif)))
            `uvm_error(get_type_name(), "Unable to find the SHMINS interface")
    endtask: pre_start

        task post_start();
        uvm_phase phase = get_starting_phase();
        if (phase != null)
            phase.drop_objection(this);
    endtask: post_start

    // User Defined APIs
    //---------------------------------------------------------------------

    // UVM Factory Registration
    //---------------------------------------------------------------------
    `uvm_object_utils(shmins_mst_sequence)
endclass: shmins_mst_sequence

//-----------------------------------------------------------------------------
// Function: new
//-----------------------------------------------------------------------------
function shmins_mst_sequence::new(string name="shmins_mst_sequence");
    super.new(name);
endfunction: new

//-----------------------------------------------------------------------------
// Task: body
//-----------------------------------------------------------------------------
task shmins_mst_sequence::body();

    `uvm_info(get_type_name(), "shmins_mst_sequence::body sequence starting", UVM_HIGH)

    for (int i=0; i<trans_num; i++) begin
        `uvm_info(get_type_name(), $sformatf("shmins_mst_sequence::start %-dth shmins_trans!!", i), UVM_HIGH)
        `uvm_create(req);
        assert(req.randomize() with {
            delay_cycle   == 10;
            creq_rw       == SHM_V2M ; // V2M
            creq_dtype    == DTYP_32 ;
            creq_atype_w  == ATYP_32 ;
            creq_atype_s  == ATYP_U ;
            creq_atype_g  == GAUTO_1B;
            creq_itype    == LDST_V ;
            creq_ack_en   == '1     ;
            creq_inv_size == '0     ;
            creq_space    == '0     ;
            creq_id       == '0     ;
            creq_wpid     == '0     ;
            creq_wpnum    == 4      ;
            creq_vaddr    == '0     ;
            creq_base     == '0     ;

            foreach (creq_prio[i]) {creq_prio[i] == '0};
            foreach (creq_len[i])  {creq_len[i]  == 8 };
            foreach (creq_vmsk[i]) {creq_vmsk[i] == '1};
        });
        req.item_to_rtl();
        `uvm_send(req);
        get_response(rsp);
        `uvm_info(get_type_name(), $sformatf("shmins_mst_sequence::end %-dth shmins_trans!!", i), UVM_HIGH)
    end
    `uvm_info(get_type_name(), "shmins_mst_sequence::body sequence completed", UVM_HIGH)
endtask: body

`endif //INC_SHMINS_MST_SEQUENCE_SVH
