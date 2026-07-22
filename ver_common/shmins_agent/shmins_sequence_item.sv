typedef enum bit[1:0] {
    DTYP_32 = 2'h0,
    DTYP_16 = 2'h1,
    DTYP_8  = 2'h2
} creq_dtype_e;

typedef enum bit[1:0] {
    ATYP_32 = 2'h0,
    ATYP_16 = 2'h1,
    ATYP_8  = 2'h2
} creq_atype_w_e;

typedef enum bit {
    ATYP_U = 1'h0,
    ATYP_S = 1'h1
} creq_atype_s_e;

typedef enum bit {
    GAUTO_1B = 1'h0,
    GAUTO_DW = 1'h1
} creq_atype_g_e;

typedef enum bit[1:0] {
    LDST_S  = 2'h0,
    LDST_V  = 2'h1,
    LDSTE_S = 2'h2,
    LDSTE_V = 2'h3
} creq_itype_e;

typedef enum bit[1:0] {
    SPACE_LOC = 2'd0,
    SPACE_WRP = 2'd1,
    SPACE_BLK = 2'd2
} creq_space_e;

// 请编写满足如下条件的约束，不用考虑和编写要求中没有提到的位域：
// 这个sequence item代表一个写请求，将不同线程creq_vdat，按照不同线程的creq_offs和creq_base写入对应的物理地址。
// 一个线程的creq_vdat的宽度是256，它会根据creq_dtype被拆分成多个元素，例如int [8], bit [15:0] [16], byte [32]
// 每个元素写入的物理地址的计算方式，与creq_offs，creq_atype_w, creq_atype_s creq_atype_g，creq_dtype，creq_len还有creq_itype有高度的耦合关系
// creq_offs的定义是16个线程，每一个线程有一个256宽度的offs，需要按如下的要求拆分
// 1. 首先根据creq_atype_w的定义，creq_offs的每个元素的256位宽度会被分成 ATYPE_WIDTH * Offs Num。
// 2. creq_atype_s决定每个offset elem是否被看作是有符号数还是无符号数，这决定了他们用符号扩展还是0扩展扩展到int
// 3. creq_atype_g决定了得到了offset elem是否需要进行左移，如果是GAUTO_1B则不需要左移，否则需要按照creq_dtype来进行左移，比如数据元素宽度为32位的需要左移2位，数据宽度为8不需要左移
// 4. 根据以上计算出来的最终的物理offset elem，需要根据creq_dtype进行对齐。如果数据宽度是32位，那么计算出的offset elem需要最低2为为0；16位需要最低一位为0
// 5. 如果creq_itype规定了物理offset elem和creq_base相加的法则
//      1. creq_itype inside {[LDST_S, LDST_V]}: 每个线程的物理offset数组只取第一个元素，与creq_base相加，不同数据元素的物理地址在此基础上自动偏移对应的数据宽度，即第k个数据元素的写入地址为creq_base + offset elem[0] + k * Data Byte Width
//      2. creq_itype == LDSTE_V: 每个线程的物理offset数组的元素和数据数组的元素一一对应，与creq_base相加，第k个数据元素的写入地址为creq_base + offset elem[k]
//      3. creq_itype == LDSTE_S: 每个线程的物理offset数组只取第一个元素，第k个数据元素的写入地址为creq_base + k * offset elem[0]
// 6. 计算出每个元素的物理地址后，他们都要小于一个特定的数值addr_max，这个数值由creq_space确定，规则如下
//      1. creq_space = = SPACE_LOC: addr_max == 1 << VADDR_W;
//      2. creq_space = = SPACE_WRP: addr_max == 1 << BADDR_W;
//      3. creq_space = = SPACE_BLK: addr_max == 1 << MADDR_W;
// 7. creq_len表示本次可以写入的元素的总字节数目，也就是元素个数 * 单个元素字节数。元素字节数由creq_dtype确定。元素个数的最大值有如下约束
//      1. creq_itype == LDSTE_V: 数据元素个数由数据元素个数和offset元素个数的最小值确定，即min(256 / creq_atype_w, 256 / creq_dtype)
//      2. 其他情况下都由数据元素的个数确定，即256 / creq_dtype
//
// 编写提示与技巧：
// 1. 可以添加一些用于保存计算结果的中间rand变量
// 2. 可以在post_random函数中进行检查、对于不符号要求位域进行直接赋值或者小范围的随机化
// 3. 可以更改已有的rand变量，创建一个更加方便的rand代替变量用于约束设定，然后定义一个与原有rand变量同名的函数，方便兼容与使用。
// 4. 如果无法使用简便写法，可以编写Python脚本生成大量的约束
// 5. 使用slang来进行语法检查
class shmins_sequence_item;

    parameter    WARP_N  = 8  ;
    parameter    THD_N   = 16 ;
    parameter    ID_W    = 4  ;
    parameter    VADDR_W = 13 ;
    parameter    BANK_N  = THD_N;
    parameter    BADDR_W = VADDR_W + $clog2(WARP_N);
    parameter    MADDR_W = BADDR_W + $clog2(BANK_N);
    // item data
    rand creq_dtype_e                      creq_dtype    = DTYP_32 ;
    rand creq_atype_w_e                    creq_atype_w  = ATYP_32 ; // the offset width
    rand creq_atype_s_e                    creq_atype_s  = ATYP_U  ; // offset and base are signed or unsigned
    rand creq_atype_g_e                    creq_atype_g  = GAUTO_1B; // the granularity of offset (0: byte, 1: data word)
    rand creq_itype_e                      creq_itype    = LDST_V  ;
    rand creq_space_e                      creq_space    = SPACE_LOC;
    rand logic [47:0]                      creq_base = '0; // byte addr
    rand logic [7:0]                       creq_len [THD_N] = '{THD_N{'0}}; // element total byte number length:0~32, align with data type
    logic [255:0]                          creq_offs_packed[THD_N]; // packed form, filled in post_randomize
    rand logic [31:0][7:0]                 creq_vdat[THD_N] = '{THD_N{'0}};

    // Accessor function matching original field name (hint #3)
    function logic [255:0] creq_offs(int t);
        return creq_offs_packed[t];
    endfunction

    // ========================================================================
    // Intermediate rand variables for offset elements (after extraction,
    // sign/zero-extension to 32-bit, granularity shift, and alignment).
    // offs_elem[thread][element_index] is the final physical offset for
    // thread t, element k.  Only indices < active element count are used.
    // ========================================================================
    rand int offs_elem[THD_N][32];

    // Maximum active data elements allowed for each thread in this transaction.
    // The actual per-thread element count is derived from creq_len[t].
    rand int unsigned elem_cnt_max;

    // ========================================================================
    // Helper functions
    // ========================================================================

    // Data element byte width from creq_dtype
    function int unsigned data_byte_w();
        case (creq_dtype)
            DTYP_32: return 4;
            DTYP_16: return 2;
            DTYP_8 : return 1;
            default: return 4;
        endcase
    endfunction

    // Data element bit width
    function int unsigned data_bit_w();
        return data_byte_w() * 8;
    endfunction

    // Max data elements that fit in 256 bits
    function int unsigned data_elem_max();
        return 256 / data_bit_w();
    endfunction

    // Offset element bit width from creq_atype_w
    function int unsigned offs_bit_w();
        case (creq_atype_w)
            ATYP_32: return 32;
            ATYP_16: return 16;
            ATYP_8 : return 8;
            default: return 32;
        endcase
    endfunction

    // Max offset elements that fit in 256 bits
    function int unsigned offs_elem_max();
        return 256 / offs_bit_w();
    endfunction

    // Granularity left-shift amount
    function int unsigned gran_shift();
        if (creq_atype_g == GAUTO_1B) return 0;
        case (creq_dtype)
            DTYP_32: return 2;
            DTYP_16: return 1;
            DTYP_8 : return 0;
            default: return 0;
        endcase
    endfunction

    // Alignment mask: aligned offset must have (offset & align_mask) == 0
    function int unsigned align_mask();
        case (creq_dtype)
            DTYP_32: return 32'h3;
            DTYP_16: return 32'h1;
            DTYP_8 : return 32'h0;
            default: return 32'h0;
        endcase
    endfunction

    // Address space upper bound
    function int unsigned addr_max();
        case (creq_space)
            SPACE_LOC: return 1 << VADDR_W;
            SPACE_WRP: return 1 << BADDR_W;
            SPACE_BLK: return 1 << MADDR_W;
            default:   return 1 << VADDR_W;
        endcase
    endfunction

    // Max element count considering itype
    function int unsigned max_elem_cnt();
        if (creq_itype == LDSTE_V)
            return (data_elem_max() < offs_elem_max()) ? data_elem_max() : offs_elem_max();
        else
            return data_elem_max();
    endfunction

    // Active element count for thread t, derived from per-thread byte length.
    function automatic int unsigned thread_elem_cnt(int t);
        case (creq_dtype)
            DTYP_32: return int'(creq_len[t]) / 4;
            DTYP_16: return int'(creq_len[t]) / 2;
            DTYP_8 : return int'(creq_len[t]);
            default: return 0;
        endcase
    endfunction

    // Compute physical address for thread t, element k
    function int phys_addr(int t, int k);
        int base_20b = int'(creq_base[MADDR_W-1:0]); // truncate base to max address width
        int res;
        case (creq_itype)
            LDST_S, LDST_V:
                res = base_20b + offs_elem[t][0] + k * int'(data_byte_w());
            LDSTE_V:
                res = base_20b + offs_elem[t][k];
            LDSTE_S:
                res = base_20b + k * offs_elem[t][0];
            default:
                res = 0;
        endcase
        return res;
    endfunction

    // ========================================================================
    // Constraints (auto-generated — run: python scripts/gen_shmins_constraints.py)
    // ========================================================================
    `include "shmins_constraints.svh"

    // ── base range and alignment ─────────────────────────────────
    constraint c_base_range_and_align {
        creq_base inside { [0 : (1 << MADDR_W) - 1] } ;
        if (creq_dtype == DTYP_32) creq_base[1:0] == 0;
        else if (creq_dtype == DTYP_16) creq_base[0] == 0  ;
    }

    // ── inactive offsets ─────────────────────────────────────────
    constraint c_offs_inactive {
        foreach (offs_elem[t,k]) {
            (k >= int'(elem_cnt_max)) -> offs_elem[t][k] == 0;
        }
    }

    // ========================================================================
    // post_randomize: pack offs_elem back into creq_offs[THD_N] (256-bit)
    //
    // creq_offs encoding:
    //   offs_elem[k] is stored in creq_offs[offs_bit_w*k +: offs_bit_w]
    //   The raw offset element (before sign-ext, shift, alignment) is what
    //   lives in creq_offs.  We reverse-compute it from offs_elem.
    // ========================================================================
    function void post_randomize();
        int unsigned obw   = offs_bit_w();
        int unsigned omax  = offs_elem_max();
        int unsigned gsh   = gran_shift();

        for (int t = 0; t < THD_N; t++) begin
            int count_t = int'(thread_elem_cnt(t));
            creq_offs_packed[t] = '0;
            for (int k = 0; k < int'(omax) && k < 32; k++) begin
                // Reverse the pipeline:
                // Forward: raw (obw bits) -> sign/zero extend to 32b -> << gsh -> aligned offs_elem
                // Reverse: offs_elem >> gsh -> truncate to obw bits -> pack into creq_offs
                int raw_extended;
                bit [31:0] raw_bits;

                if (k < count_t) begin
                    raw_extended = offs_elem[t][k] >>> gsh;
                end else begin
                    raw_extended = 0;
                end

                // Truncate to offset bit width and pack
                raw_bits = $unsigned(raw_extended);
                case (obw)
                    32: creq_offs_packed[t][k*32 +: 32] = raw_bits[31:0];
                    16: creq_offs_packed[t][k*16 +: 16] = raw_bits[15:0];
                     8: creq_offs_packed[t][k*8  +:  8] = raw_bits[ 7:0];
                    default: ;
                endcase
            end
        end

        // Verify all physical addresses in debug
        for (int t = 0; t < THD_N; t++) begin
            int count_t = int'(thread_elem_cnt(t));
            for (int k = 0; k < count_t; k++) begin
                int pa = phys_addr(t, k);
                if (pa < 0 || pa >= addr_max()) begin
                    $warning("post_randomize: phys_addr[%0d][%0d] = %0d out of range [0, %0d)",
                             t, k, pa, addr_max());
                end
            end
        end
    endfunction

endclass
