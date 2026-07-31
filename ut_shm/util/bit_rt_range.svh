`ifndef INC_BIT_RT_RANGE_SVH
`define INC_BIT_RT_RANGE_SVH

class bit_rt_range #(parameter int W = 32);

    /**
     * @return: 返回 [msb:lsb] 间的数据，且已右移 lsb 位（即结果从 bit 0 开始）
     */
    static function bit [W-1:0] get_range(bit [W-1:0] in_data, int msb, int lsb);
        bit [W-1:0] mask;
        bit [W-1:0] all_ones = {W{1'b1}};
        int len;

        if (lsb < 0 || msb >= W || msb < lsb) return {W{1'b0}};

        len = msb - lsb + 1;
        mask = (all_ones >> (W - len)) << lsb;

        // 核心修改：掩码后右移 lsb，实现归一化
        return (in_data & mask) >> lsb;
    endfunction

    // 变体 1: [base +: width] 向上截取
    // 等价于 [base + width - 1 : base]
    static function bit [W-1:0] get_plus_range(bit [W-1:0] in_data, int base, int width);
        if (width <= 0) return {W{1'b0}};
        // 计算对应的 MSB 和 LSB 后调用基础函数
        return get_range(in_data, base + width - 1, base);
    endfunction

    // 变体 2: [base -: width] 向下截取
    // 等价于 [base : base - width + 1]
    static function bit [W-1:0] get_minus_range(bit [W-1:0] in_data, int base, int width);
        if (width <= 0) return {W{1'b0}};
        // 计算对应的 MSB 和 LSB 后调用基础函数
        return get_range(in_data, base, base - width + 1);
    endfunction

    // --- Set 系列（核心逻辑：先清零，再按位或） ---

    /**
     * @param original_data: 原始完整向量
     * @param field_value:   要填入的新字段值（假设该值从 bit 0 开始）
     * @param msb, lsb:      目标位置
     */
    static function bit [W-1:0] set_range(
        bit [W-1:0] original_data,
        bit [W-1:0] field_value,
        int         msb,
        int         lsb
    );
        bit [W-1:0] mask;
        bit [W-1:0] all_ones = {W{1'b1}};
        int         len;
        bit [W-1:0] v = field_value[W-1:0];

        // 1. 安全检查
        if (lsb < 0 || msb >= W || msb < lsb) return original_data;

        // 2. 生成掩码：[msb:lsb] 为 1，其余为 0
        len = msb - lsb + 1;
        mask = (all_ones >> (W - len)) << lsb;

        // 3. 执行修改逻辑：
        // (original_data & ~mask) : 将目标区域清零
        // (field_value << lsb) & mask : 确保新值不越界，并移位到目标位置
        return (original_data & ~mask) | ((v << lsb) & mask);
    endfunction

    // 变体 1: set_plus_range [base +: width]
    static function bit [W-1:0] set_plus_range(bit [W-1:0] data, bit [W-1:0] val, int base, int width);
        if (width <= 0) return data;
        return set_range(data, val, base + width - 1, base);
    endfunction

    // 变体 2: set_minus_range [base -: width]
    static function bit [W-1:0] set_minus_range(bit [W-1:0] data, bit [W-1:0] val, int base, int width);
        if (width <= 0) return data;
        return set_range(data, val, base, base - width + 1);
    endfunction

endclass

`endif //INC_BIT_RT_RANGE_SVH
