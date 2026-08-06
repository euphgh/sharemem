# shm_reference

本文说明 reference 如何把按序采样的 creq 转换为 byte 级期望写集合，并维护架构
reference memory。地址和转置规则以[地址模型](../../spec/address-model.md)为准；共享
transaction 的所有权见[数据流与数据模型](../data-flow-and-models.md)。

## 1. 输入、输出和状态

```text
shmins_monitor
    │ shmins_sequence_item
    ▼
shm_reference
    ├── ref_banks[BANK_N]       顺序架构 memory
    └── shm_wtrans_item.wmap ──► shm_scoreboard
```

Reference 通过 `shmins_analysis_export` 同步接收每笔 creq，通过
`wdata_ass_arr_port` 发布一笔 `shm_wtrans_item`。它持有每个 bank 一份 byte-addressable
`svt_mem`，初值与 scoreboard 实际 memory model 相同，但两者是相互独立的对象。

## 2. 主要源文件

|文件|作用|
|---|---|
|`ut_shm/env/shm_reference.svh`|reference memory、V2M/VTRANS/M2V 数据语义和输出|
|`ut_shm/env/shm_wtrans_item.svh`|从 creq 计算 MADDR、bank、BADDR、strobe 和 `wmap`|
|`ut_shm/env/vlm2aa.svh`|MEM transaction 与 byte associative array 的转换工具|
|`ver_common/uvc/shmins_agent/sequences/shmins_sequence_item.svh`|reference 的 creq 输入对象|

## 3. 初始化和架构顺序

`build_phase` 为每个 bank 创建一个 8-bit `svt_mem`，地址范围由 `BADDR_W` 决定；
`configure_phase` 使用 `svt_mem::INCR` 和 `bank_id<<4` 初始化。Scoreboard 的
`rtl_banks` 使用同一初始化规则，便于没有 write 历史时比较 read 数据。

Reference 按 `shmins_monitor` 发布 creq 的顺序立即更新 `ref_banks`。DUT 可以乱序调度
多笔 creq，包括地址重叠的事务；但最终 memory 状态必须等价于这些 creq 的顺序执行。
乱序只允许改变中间兑现次序，不能改变架构最终值。

## 4. `shm_wtrans_item` 地址展开

`write_shmins_reference()` 先创建 `shm_wtrans_item`，调用 `init_from()` 复制原始 creq，
再由 transaction helper 计算：

1. 每个 active thread/element 的 MADDR；
2. MADDR 映射得到的 bank id 和 BADDR；
3. element mask 展开的逐 byte strobe；
4. 本笔指令预期写出的 `wmap[bank][baddr]=byte`。

这些计算必须与地址 spec 的 LOC/WRP/BLK、interleave 和地址空洞规则一致。当前
SPACE_BLK 对非零 `warp_group` 的展开不完整，见 `REF-001`。

## 5. V2M 和 VTRANS

普通 V2M 从 `creq_vdat[thread]` 取每个 element 的 byte，按计算出的目标 bank/BADDR
写入 `wmap` 和 `ref_banks`。

当 `creq_info=='1` 表示 VTRANS 时，reference 把 16 个 thread、每个 thread 16 个
element 视为 16×16 方阵。目标 `[thread][element]` 的数据来自转置前
`creq_vdat[element][thread]` 对应位置；转置只改变数据选择，MADDR、offset、mask 之外
的地址控制仍沿用普通 V2M 计算。`creq_tmsk` 加入后，VTRANS 必须要求全 1。

## 6. M2V

M2V 分两步执行：

1. 按 creq MADDR 映射得到的 bank/BADDR 从 `ref_banks` 读取 element 数据；
2. 以 `creq_vaddr + WARP_STEP*creq_wpid` 为写回基址，把各 thread 的数据写入对应
   VLM bank，并把逐 byte 结果加入本笔 `wmap`。

因此同一 `shm_wtrans_item.wmap` 对 V2M/VTRANS 表示 m-write，对 M2V 表示 v-write。
Scoreboard 后续必须保留原始指令类型，才能实施来源相关的 alignment 检查。

## 7. 重叠地址

`write_wmap()` 如果发现同一笔 `shm_wtrans_item` 内重复写同一 byte，会立即报告 overlap；
跨 creq 的重叠则是合法输入，由 scoreboard 记录旧值过期和新最终值。

Reference 无论 DUT 调度顺序如何，都按 creq 顺序覆盖 `ref_banks`。因此后一笔 creq 的
byte 是该地址的架构最终值；前一笔的旧值只能作为乱序执行期间允许观察到的过渡值。

## 8. 调试观察点

- 原始 `shmins_sequence_item` 与 `shm_wtrans_item` 复制后的字段；
- thread/element 的 MADDR、bank、BADDR 和逐 byte strobe；
- VTRANS 的 source `[element][thread]` 与 target `[thread][element]`；
- M2V 从 `ref_banks` 读取的值和 VLM 写回地址；
- `wmap` 内 overlap error 以及每笔 transaction 的 `issue_time`。

## 9. 相关测试

`ut_shm/tests/shm_unit_test.svh` 是当前 reference 的集成使用入口。现阶段没有把地址
映射、VTRANS 转置、M2V 读写回或跨 creq 重叠拆成独立 reference 单元测试；尤其需要
按 `REF-001` 增加非零 `warp_group` 定向场景，并按 `SHMINS-002` 验证 copy 后字段完整。

## 10. 开发 contract

- Reference 只按 creq 采样顺序建立架构结果，不模拟 DUT 的内部调度策略。
- 对地址重叠的 creq，最终值必须来自顺序上最后一次有效写；scoreboard 只能放宽中间
  顺序，不能放宽最终状态。
- 地址 helper 必须直接落实 spec 公式，不能依赖现有 testcase 的受限地址分布。
- Transaction copy 必须保留所有影响地址、mask、数据和 VTRANS 识别的字段。
- Runtime reset 必须取消在途期望并把 reference memory 恢复到 reset 后定义状态。

## 11. 当前实现状态

- `REF-001`：SPACE_BLK 映射遗漏非零 `warp_group`。
- `SHMINS-001`：reference 尚未处理 `creq_tmsk`。
- `SHMINS-002`：输入 transaction copy 会丢失关键字段。
- `SHMINS-003`：生成约束可能给 reference 输入非法地址。
- `ENV-001`：运行中 reset 未重建 `ref_banks` 或取消旧期望。

问题详情和验收方法见[验证实现状态](../../verification-status.md)。
