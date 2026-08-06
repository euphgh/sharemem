`ifndef INC_SHMINS_UNIT_SEQUENCE_SVH
`define INC_SHMINS_UNIT_SEQUENCE_SVH

//-----------------------------------------------------------------------------
// Class: shmins_unit_sequence
// Generate unit test case sequence
// can be integrated into virtual sequence or test env
//-----------------------------------------------------------------------------
class shmins_unit_sequence extends shmins_mst_sequence;

    rand int                m_seq_trans_num      = 8;
    rand int                m_seq_delay_max      = 16;
    rand int                m_seq_delay_min      = 8;
         bit                m_seq_vtrans_en      = 0;

    rand creq_rw_e          m_seq_rw             = SHM_V2M  ;
    rand creq_dtype_e       m_seq_dtype          = DTYP_32  ;
    rand creq_atype_w_e     m_seq_atype_w        = ATYP_32  ;
    rand creq_atype_s_e     m_seq_atype_s        = ATYP_U   ;
    rand creq_atype_g_e     m_seq_atype_g        = GAUTO_1B ;
    rand creq_itype_e       m_seq_itype          = LDST_V   ;
    rand creq_space_e       m_seq_space          = SPACE_LOC;

    extern function void config_item(
        creq_rw_e       rw      = SHM_V2M  ,
        creq_dtype_e    dtype   = DTYP_32  ,
        creq_atype_w_e  atype_w = ATYP_32  ,
        creq_atype_s_e  atype_s = ATYP_U   ,
        creq_atype_g_e  atype_g = GAUTO_1B ,
        creq_itype_e    itype   = LDST_V   ,
        creq_space_e    space   = SPACE_LOC
    );

    extern function void config_time(
        int trans_num = 8,
        int delay_max = 16,
        int delay_min = 0
    );

    extern function void plusargs_override_config();
    extern function      new(string name= "shmins_unit_sequence");
    extern virtual task  body();

    `uvm_object_utils_begin(shmins_unit_sequence)

    `uvm_field_int(m_seq_trans_num      , UVM_DEFAULT)
    `uvm_field_int(m_seq_delay_max      , UVM_DEFAULT)
    `uvm_field_int(m_seq_delay_min      , UVM_DEFAULT)
    `uvm_field_enum(creq_rw_e,      m_seq_rw      , UVM_DEFAULT)
    `uvm_field_enum(creq_dtype_e,   m_seq_dtype   , UVM_DEFAULT)
    `uvm_field_enum(creq_atype_w_e, m_seq_atype_w , UVM_DEFAULT)
    `uvm_field_enum(creq_atype_s_e, m_seq_atype_s , UVM_DEFAULT)
    `uvm_field_enum(creq_atype_g_e, m_seq_atype_g , UVM_DEFAULT)
    `uvm_field_enum(creq_itype_e,   m_seq_itype   , UVM_DEFAULT)
    `uvm_field_enum(creq_space_e,   m_seq_space   , UVM_DEFAULT)
    `uvm_object_utils_end
endclass: shmins_unit_sequence

function void shmins_unit_sequence::config_item(
    creq_rw_e       rw,
    creq_dtype_e    dtype,
    creq_atype_w_e  atype_w,
    creq_atype_s_e  atype_s,
    creq_atype_g_e  atype_g,
    creq_itype_e    itype,
    creq_space_e    space
);
    m_seq_rw      = rw;
    m_seq_dtype   = dtype;
    m_seq_atype_w = atype_w;
    m_seq_atype_s = atype_s;
    m_seq_atype_g = atype_g;
    m_seq_itype   = itype;
    m_seq_space   = space;
endfunction

function void shmins_unit_sequence::config_time(
    int trans_num = 8,
    int delay_max = 16,
    int delay_min = 0
);
    m_seq_trans_num = trans_num;
    m_seq_delay_max = delay_max;
    m_seq_delay_min = delay_min;
endfunction

function void shmins_unit_sequence::plusargs_override_config();
    $value$plusargs("TRANS_NUM=%d", m_seq_trans_num);
    $value$plusargs("TRANS_DELAY_MIN=%d", m_seq_delay_min);
    $value$plusargs("TRANS_DELAY_MAX=%d", m_seq_delay_max);
    $value$plusargs("VTRANS_EN=%d", m_seq_vtrans_en);
    value_creq_rw_e_plusargs("CREQ_RW", m_seq_rw);
    value_creq_dtype_e_plusargs("CREQ_DTYPE", m_seq_dtype);
    value_creq_atype_w_e_plusargs("CREQ_ATYPE_W", m_seq_atype_w);
    value_creq_atype_s_e_plusargs("CREQ_ATYPE_S", m_seq_atype_s);
    value_creq_atype_g_e_plusargs("CREQ_ATYPE_G", m_seq_atype_g);
    value_creq_itype_e_plusargs("CREQ_ITYPE", m_seq_itype);
    value_creq_space_e_plusargs("CREQ_SPACE", m_seq_space);
endfunction

function shmins_unit_sequence::new(string name="shmins_unit_sequence");
    super.new(name);
endfunction: new

//-----------------------------------------------------------------------------
// Task: body
//-----------------------------------------------------------------------------
task shmins_unit_sequence::body();

    `uvm_info(get_type_name(), "shmins_unit_sequence::body sequence starting", UVM_HIGH)

    for (int i = 0; i < m_seq_trans_num; i++) begin
        `uvm_info(get_type_name(), $sformatf("shmins_unit_sequence::start %-dth shmins_trans!!", i), UVM_HIGH)
        `uvm_create(req);
        assert(req.randomize() with {
            delay_cycle inside {[m_seq_delay_min : m_seq_delay_max]};
            if (m_seq_vtrans_en) {
                creq_rw     == SHM_V2M;
                creq_info   == '1;
                creq_dtype inside {DTYP_16, DTYP_8};
                creq_itype inside {LDST_S, LDST_V};
                creq_space  == SPACE_LOC;
                creq_tmsk   == '1;
                foreach (elem_num[tidx]) { elem_num[tidx] == 16 };
                foreach (creq_vmsk[tidx]) { creq_vmsk[tidx] == '1; }
            }
            else {
                creq_rw     == m_seq_rw;
                creq_info   == '0;
                creq_dtype  == m_seq_dtype;
                creq_atype_w== m_seq_atype_w;
                creq_itype  == m_seq_itype;
                creq_space  == m_seq_space;
            }
            creq_wpid   == 0;
        });
        req.item_to_rtl();
        `uvm_send(req);
        get_response(rsp);
        `uvm_info(get_type_name(), $sformatf("shmins_unit_sequence::end %-dth shmins_trans!!", i), UVM_HIGH)
    end
    `uvm_info(get_type_name(), "shmins_unit_sequence::body sequence completed", UVM_HIGH)
endtask: body

`endif // INC_SHMINS_UNIT_SEQUENCE_SVH
