# ut_shm 验证实现状态

本文集中记录 ut_shm 验证环境与当前 DUT spec 之间的实现差异，以及组件开发中已经
确认的问题。组件文档只引用这里的稳定问题 ID，不重复维护修复过程。当前清单基于
2026-08-06 的源码提交 `d719f0b`；本轮仅迁移文档，没有据此声明新的编译或仿真结果。

## 1. 状态和优先级

问题状态按以下顺序流转：

```text
待确认 → 待实现 → 实现中 → 待验证 → 已完成
                         ↘ 暂缓
```

|优先级|含义|
|---|---|
|P0|违反当前 spec、破坏核心数据正确性，或阻止主要功能验证|
|P1|检查、配置或定向测试明显不完整，可能漏报或误报|
|P2|参数化、冗余结构或辅助 API 问题，不影响默认配置的主要路径|

“已完成”必须同时具备代码修改和可重复的验收证据。只有文档更新不能关闭实现问题。

## 2. 当前支持边界

- 当前只支持完整 active 环境，passive 模式明确不支持。相关配置应当明确拒绝，或在
  后续清理中移除，不能让环境进入半连接状态。
- DUT 可以乱序调度多笔 creq，但最终 memory 结果必须与 creq 顺序执行的结果一致。
  Reference 按 creq 采样顺序建立架构期望，scoreboard 可以接受合法中间写入，但测试
  结束时必须收敛到顺序执行的最终状态。
- 阶段 2 spec 是目标协议。下表中的缺口不能被当前源码行为反向解释为协议例外。

## 3. 开放问题总表

|ID|优先级|状态|组件|主题|
|---|---:|---|---|---|
|`ENV-001`|P0|待实现|跨组件|运行中 reset 未统一取消 pending 状态|
|`ENV-002`|P2|待实现|environment config|仍暴露不能组成完整环境的 passive 配置组合|
|`SHMINS-001`|P0|待实现|shmins agent|`creq_tmsk` 尚未进入验证数据通路|
|`SHMINS-002`|P0|待实现|shmins transaction|`do_copy()` 遗漏或错误复制关键字段|
|`SHMINS-003`|P0|待实现|shmins constraints|地址约束没有实现 12 KiB 编码和地址空洞规则|
|`SHMINS-004`|P1|待实现|unit sequence|signedness/granularity 配置没有约束到 item|
|`SHMINS-005`|P2|待实现|shmins agent|部分循环和位宽硬编码为当前 16-thread/4-bit 配置|
|`SHMINS-006`|P1|待实现|shmins monitor|active creq payload 缺少系统性的 X/Z 检查|
|`VMEM-001`|P0|待实现|memory model|MEM read 未实现 `FFD_CYC` 写可见窗口|
|`VMEM-002`|P1|待实现|memory monitor|MEM valid、地址、strobe 和有效数据缺少完整 X/Z 检查|
|`VMEM-003`|P2|待实现|memory agent|sequencer 和部分 compare API 没有有效行为|
|`REF-001`|P0|待实现|reference|SPACE_BLK 映射没有处理非零 `warp_group`|
|`SCB-001`|P0|待实现|scoreboard|尚未按原始指令类型检查 write alignment|
|`SCB-002`|P1|待实现|scoreboard|128-cycle timeout 固定，可能把合法长延迟误报为失败|
|`RSV-001`|P0|待实现|reservation agent|仍按 write port 推断 write alignment|
|`RSV-002`|P1|待实现|reservation coverage|coverage 组件目前为空实现|
|`RSV-003`|P1|待实现|reservation example|定向测试仍编码旧 port 对齐规则，external busy 测试字段名也已失效|

## 4. 问题详情

### `ENV-001` 运行中 reset 状态清理

- 现状：driver、monitor 多数只等待初始 reset 释放；reference memory、scoreboard
  outstanding、MEM read fork 和 reservation scheduler 没有统一取消或重建。
- 影响：运行中 reset 后可能继续兑现 reset 前事务，违反 DUT reset 契约。
- 目标依据：[DUT 概览的 reset 行为](spec/dut-overview.md#6-reset-行为)。
- 验收：在 creq、reservation 和 MEM read 均有在途状态时拉低 reset；释放后不得出现
  旧 ack、旧 MEM response、旧 reservation 到期或旧 scoreboard timeout。

### `ENV-002` Unsupported passive 配置

- 现状：config 中仍有多组 active/passive knob，但 reservation agent 固定 active；
  关闭 scoreboard 时，active memory driver 的 blocking transport 也会失去目标。
- 影响：非默认组合可能在 elaboration 或运行时形成半连接环境。
- 目标：现阶段只支持完整 active；不支持的组合应尽早 fatal，或删除无效 knob。
- 验收：所有公开配置组合要么形成完整连接，要么在 build 阶段给出明确错误。

### `SHMINS-001` `creq_tmsk` 数据通路

- 现状：DUT 规范已有 `creq_tmsk`，当前 top、interface、transaction、constraints、
  driver、monitor 和 reference 均没有该字段。
- 影响：无法生成或验证 inactive thread，VTRANS 也无法约束 `creq_tmsk=='1`。
- 目标依据：[creq/ack 接口](spec/creq-ack-interface.md)。
- 验收：覆盖非全零普通 mask、inactive thread X/Z、全零非法请求和 VTRANS 全 1。

### `SHMINS-002` Transaction copy 完整性

- 现状：`shmins_sequence_item.do_copy()` 未复制 `creq_info`，并对 `elem_num`、
  `creq_vmsk`、`creq_offs_packed` 使用了 self-assignment。
- 影响：`shm_wtrans_item.init_from()` 得不到完整 creq，VTRANS 识别、mask 和地址计算
  可能错误。
- 目标：所有影响驱动、reference 和 scoreboard 的字段必须从 rhs 完整复制。
- 验收：构造非默认字段 transaction，copy 后逐字段一致，并覆盖 VTRANS transaction。

### `SHMINS-003` 地址合法性约束

- 现状：生成约束仍以 2 的幂范围限制 LOC/WRP/BLK，没有完整表达 12 KiB WARP、
  8/16 KiB interleave 编码差异和地址空洞禁止规则。
- 影响：激励可能生成 spec 非法地址，也可能错误排除合法边界。
- 目标依据：[地址模型](spec/address-model.md)。
- 验收：三种 space、全部支持 interleave size 和边界值的约束定向测试；随机请求不得
  落入地址空洞。

### `SHMINS-004` Unit sequence 配置丢失

- 现状：`CREQ_ATYPE_S` 和 `CREQ_ATYPE_G` 能写入 sequence 配置，但普通请求的 inline
  constraint 没有把它们约束到 `req.creq_atype_s/g`。
- 影响：plusarg 输出与实际 creq 可能不一致。
- 目标：所有公开 sequence 配置必须确定对应 item 字段。
- 验收：分别设置 signedness 和 granularity plusarg，monitor transaction 与配置一致。

### `SHMINS-005` 参数硬编码

- 现状：driver/monitor 使用固定 16-thread 循环，interface priority 宽度固定为 4 bit，
  部分辅助函数也使用固定 BANK 数。
- 影响：修改 `THD_N` 或 `PRIO_W` 时环境不能可靠复用。
- 目标：循环和位宽来自 `shm_util_package` 参数。
- 验收：至少使用一个非默认 `THD_N/PRIO_W` 配置完成语法和 elaboration 检查。

### `SHMINS-006` creq 四态检查

- 现状：monitor 只用 `creq_vld===1` 选择事务，没有按 active payload 逐字段报告 X/Z。
- 影响：非法输入可能进入 reference，错误被延迟或转化成难以定位的数据差异。
- 目标依据：`CREQ-002`。
- 验收：为公共字段、active thread payload 和 inactive thread payload 分别注入 X/Z，
  只报告协议禁止的组合。

### `VMEM-001` `FFD_CYC` read snapshot

- 现状：memory driver 在采样 `mem_rvld/mem_raddr` 后立即调用 scoreboard
  `b_transport()` 读取 `rtl_banks`，再延迟输出。
- 影响：不能表示 read 在未来截止周期之前可见的 write。
- 目标依据：[MEM/VLM 接口的写可见窗口](spec/mem-vlm-interface.md#24-ffd_cyc-写可见窗口)。
- 验收：覆盖 `FFD_CYC=0`、1 和大于 1，确认截止周期之后的 write 不进入返回值。

### `VMEM-002` MEM 四态检查

- 现状：memory monitor 采集 valid/address/strobe/data，但没有系统性的 `$isunknown`
  检查；reservation monitor 只覆盖 MEM valid 和地址。
- 影响：strobe 或有效 data lane 的 X/Z 可能污染 `rtl_banks` 或形成误导性比对。
- 目标依据：`MEM-002`、`MEM-003`。
- 验收：分别向 read valid/address 和 write valid/address/strobe/有效 data lane 注入 X/Z。

### `VMEM-003` 无效辅助结构

- 现状：active memory agent 创建 sequencer，但 driver 不消费 sequence item；
  `vlm_memory_sequence_item.compare_item()` 也不会累计错误，且循环硬编码为 16。
- 影响：组件 API 暗示了并不存在的控制和比较能力。
- 目标：删除无意义结构，或补齐可验证的用途，避免保留会静默返回错误结果的 API。
- 验收：组件公开结构与实际数据流一致，所有保留 compare API 有定向单元测试。

### `REF-001` SPACE_BLK `warp_group`

- 现状：`shm_wtrans_item.generate_wdata()` 把 `warp_index` 直接设为 `warp_offs`，没有
  加入 `warp_group * creq_wpnum`。
- 影响：非零 MADDR 高位对应的 SPACE_BLK BADDR 和 WARP 选择错误。
- 目标依据：[地址模型的 SPACE_BLK 映射](spec/address-model.md#7-space_blk-映射)。
- 验收：使用非零 `warp_group`、`creq_wpnum` 为 1/2/4 的定向 reference 测试。

### `SCB-001` 来源相关 write alignment

- 现状：scoreboard 持有原始 creq 类型和实际 write transaction，但尚未实施普通
  V2M 对齐、M2V v-write 可非对齐、VTRANS 可非对齐的分类检查。
- 影响：最终 MEM/VLM beat alignment 的 spec 规则缺少正确的功能检查位置。
- 目标依据：[地址模型的访问来源与对齐](spec/address-model.md#8-访问来源与-mem-beat-对齐)。
- 验收：普通 V2M、M2V、VTRANS 的 aligned/nonaligned 正反例均有定向测试。

### `SCB-002` 可配置 timeout

- 现状：scoreboard 固定在 128 cycles 后把未完成 reference record 报为 expired。
- 影响：协议没有最大完成延迟，合法长延迟可能被误报。
- 目标依据：[DUT 概览的协议边界](spec/dut-overview.md#7-协议边界)。
- 验收：timeout 可配置或关闭；超过默认诊断阈值但最终正确的事务不会被强制判错。

### `RSV-001` 移除 port-based write alignment

- 现状：types helper、checker 和 scheduler 仍规定 write port 1 对齐、port 0 可非对齐。
- 影响：VTRANS 与 M2V/V2M 的实际来源不能由 reservation port 稳定区分。
- 目标依据：`VLM-003`；reservation/MEM 地址仍必须完整相等。
- 验收：reservation agent 只固定检查 read alignment 和完整地址兑现；write alignment
  转移到 `SCB-001` 路径。

### `RSV-002` Reservation coverage

- 现状：coverage class 只保留空的同步 API，所有计数器恒为 0，没有 covergroup。
- 影响：reservation delay、busy 来源、共享 slot 和匹配结果没有功能覆盖闭环。
- 目标：阶段 5 定义 testpoint 后实现对应 coverpoint/cross，且不改变 scheduler 状态。
- 验收：覆盖报告能追踪主要合法场景和错误注入场景。

### `RSV-003` Reservation example 失效

- 现状：`alignment_tb.sv` 仍断言旧 port 对齐规则；`external_busy_tb.sv` 访问 scheduler
  中不存在的 `EXTERNAL_BUSY_PERCENT` 大写字段。
- 影响：示例不能作为当前 spec 的可靠回归证据，部分目标可能无法编译。
- 目标：示例改为检查 read alignment、write 完整地址匹配和 plusarg 覆盖的实际字段。
- 验收：`alignment-test`、`external-busy-test` 在远端 VCS 环境编译并通过。

## 5. 已解决记录

当前没有在本轮文档迁移中关闭的实现问题。问题完成后应保留 ID，并记录修改文件、
commit、验证命令、结果和日期。
