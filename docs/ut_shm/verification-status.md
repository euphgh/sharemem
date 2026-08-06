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
|`COV-001`|P1|待实现|跨组件|ut_shm 尚未建立 functional coverage 模型|
|`SHMINS-001`|P0|待验证|shmins agent|`creq_tmsk` 数据通路和 reference mask 已实现，待远端验证|
|`SHMINS-002`|P0|待实现|shmins transaction|`do_copy()` 遗漏或错误复制关键字段|
|`SHMINS-003`|P0|待实现|shmins constraints|地址约束没有实现 12 KiB 编码和地址空洞规则|
|`SHMINS-004`|P1|待实现|unit sequence|signedness/granularity 配置没有约束到 item|
|`SHMINS-005`|P2|待实现|shmins agent|部分循环和位宽硬编码为当前 16-thread/4-bit 配置|
|`SHMINS-006`|P1|待实现|shmins monitor|active creq payload 缺少系统性的 X/Z 检查|
|`SHMINS-007`|P1|待实现|unit sequence/TC|V2M `LDSTE_S + WRP/BLK` 缺少屏蔽 element 0 的合法激励|
|`SHMINS-008`|P1|待实现|shmins monitor|固定 200-cycle ack timeout 与协议无最大延迟冲突|
|`SHMINS-009`|P1|待实现|shmins monitor|credit/release 和 unexpected/duplicate ack 缺少完备检查|
|`SHMINS-010`|P1|待实现|shmins monitor|复位期间 release 和 ack 静默缺少检查|
|`VMEM-001`|P0|待实现|memory model|MEM read 未实现 `FFD_CYC` 写可见窗口|
|`VMEM-002`|P1|待实现|memory monitor|MEM valid、地址、strobe 和有效数据缺少完整 X/Z 检查|
|`VMEM-003`|P2|待实现|memory agent|sequencer 和部分 compare API 没有有效行为|
|`REF-001`|P0|待实现|reference|SPACE_BLK 映射没有处理非零 `warp_group`|
|`SCB-001`|P0|待实现|scoreboard|尚未按原始指令类型检查 write alignment|
|`SCB-002`|P1|待实现|scoreboard|128-cycle timeout 固定，可能把合法长延迟误报为失败|
|`RSV-001`|P0|待实现|reservation agent|仍按 write port 推断 write alignment|
|`RSV-002`|P1|待实现|reservation coverage|coverage 组件目前为空实现|
|`RSV-003`|P1|待实现|reservation example|定向测试仍编码旧 port 对齐规则，external busy 测试字段名也已失效|
|`RSV-004`|P1|待实现|reservation checker|全局 `input_error` 会屏蔽无关 slot 的检查|
|`RSV-005`|P1|待实现|reservation monitor|复位期间没有检查 DUT request/valid 必须为 0|

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

### `COV-001` ut_shm functional coverage

- 现状：shmins monitor 只有注释掉的历史 coverage include；reservation coverage 是空
  API；reference、scoreboard 和 memory agent 均没有有效 covergroup/coverpoint。
- 影响：case 运行和 checker 通过不能证明 spec 场景实际发生，所有 testpoint 都缺少
  功能覆盖关闭证据。
- 目标依据：[Testpoints](plan/testpoints.md)和
  [Coverage 与关闭条件](plan/coverage-and-closure.md)。
- 验收：每个 required testpoint 都能映射到已实现的 functional bin/cross，报告可按
  testpoint ID 回溯，未命中项有定向激励或有效 waiver。

### `SHMINS-001` `creq_tmsk` 数据通路

- 现状：tb top、interface、transaction、copy、factory field、driver 和 monitor 已贯通
  `THD_N` bit `creq_tmsk`。普通请求约束非全零，VTRANS 约束全 1；monitor 报告 X/Z 和
  全零值，reference 为非 active thread 创建空的地址/BANK/strobe 数组，不解释 inactive
  payload，也不生成对应读写期望。本地 Slang 语义检查已通过，尚未在远端 DUT/VCS
  环境执行定向场景。
- 影响：代码路径已具备 mask 行为，但在稀疏 mask、inactive payload X/Z 和 DUT 意外
  输出场景验证完成前，不能确认功能关闭。
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

### `SHMINS-007` V2M `LDSTE_S + SPACE_WRP/SPACE_BLK`

- 现状：不同 thread 的 element 0 都按 `creq_base + 0*offset` 生成相同 MADDR。V2M
  对该地址形成多笔写，结果未定义；当前根 TC 注释了 `v2m/es_warp.tc` 和
  `v2m/es_blk.tc`，unit sequence 也没有提供 element-0 mask 配置。
- 影响：不能验证这两种 address space 下 element 1 及之后的合法 `LDSTE_S` V2M
  地址和数据行为。M2V 不存在重叠写问题，仍属于支持组合。
- 目标：V2M 定向激励至少约束所有 thread 的 `creq_vmsk[*][0]==0`，同时保证其余有效
  element 不产生未定义的同地址多写；M2V 不应用该限制。
- 验收：新增合法 V2M WRP/BLK case，波形和 monitor transaction 中 element 0 全部
  masked，其余 element 由 reference/scoreboard 正确检查；原始未 mask 组合不进入
  正常正向 regression。

### `SHMINS-008` Ack timeout 不是协议时限

- 现状：shmins monitor 为 ack-enabled 请求启动固定 200-cycle timeout，并在到期时
  报告 `UVM_ERROR`；spec 明确 ack 没有最大延迟。
- 影响：超过 200 周期后仍正确完成的 DUT 请求会被误判失败。
- 目标：timeout 可配置或关闭，并明确属于 hang 诊断；默认策略不得被解释成 DUT
  protocol checker。
- 验收：关闭 timeout 时长延迟 ack 不报错；配置诊断阈值时日志能区分协议错误与
  hang 诊断；最终正确 ack 仍按方向和 ID 完成匹配。

### `SHMINS-009` Credit 与 ack 完备性检查

- 现状：driver semaphore 限制环境自身发送并在每个 `creq_rls` 上 `put()`，但没有检查
  credit 是否超过 `OTF_N`；monitor 只为 ack-enabled 请求等待一次匹配事件，没有完整
  报告 ack-disabled 请求的 unexpected ack、重复 ack 或错误方向事件。
- 影响：DUT 的 release 上溢和部分 ack 协议违例可能漏报，或只表现为后续间接错误。
- 目标依据：`CREQ-005`、`ACK-001` 和 `ACK-002`。
- 验收：定向覆盖 credit 下溢/上溢、unexpected/duplicate/wrong-direction/wrong-ID ack，
  每类违例均得到唯一且可定位的错误；合法 release/ack 独立顺序不误报。

### `SHMINS-010` 复位期间 release/ack 静默

- 现状：driver 和 monitor 等待初始 reset 释放后才进入正常业务循环，没有独立检查
  `rst_n==0` 时 DUT 的 `creq_rls/vack_done/mack_done` 必须为 0。
- 影响：DUT 在初始或运行中 reset 期间错误归还 credit 或发送 ack 时可能不被报告。
- 目标依据：[creq/ack 接口的复位规则](spec/creq-ack-interface.md#8-复位与检查规则)。
- 验收：reset 已知为 0 时分别拉高 release、vack 和 mack，均得到明确错误；reset X/Z
  不启动正常 payload 检查，done 为 0 时不检查 ID。

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

### `RSV-004` `input_error` 抑制粒度

- 现状：cycle transaction 只有一个全局 `input_error`。任意 busy、reservation 或 MEM
  端口出现 X/Z 后，checker 会跳过本周期全部 observed-busy 比较，并抑制所有到期
  record 的 `MISSING_MEM`。
- 影响：一个 BANK 或方向上的四态错误可能掩盖其他 BANK、方向和 slot 上彼此独立的
  busy mismatch 或 missing MEM，降低 checker 的并发诊断能力。
- 目标：保留 monitor 的原始 X/Z 报错，同时把“该观察值是否可靠”记录到实际受影响的
  busy bit 和 request port，或采用等价的局部抑制机制。
- 验收：向一个无关端口注入 X/Z 时，该端口不产生归一化后的级联误报；同周期其他
  BANK/direction 上的 busy mismatch 和 missing MEM 仍能被 checker 报告。

### `RSV-005` 复位期间 request quiescence

- 现状：`collect_cycle()` 在 `rst_n!==1` 时只等待，不采样 reservation 或 MEM
  request，因此没有检查复位期间 `vlm_rreq/vlm_wreq` 和 `mem_rvld/mem_wvld` 必须为 0。
- 影响：DUT 在初始或运行中复位期间错误发出 reservation/MEM request 时，验证环境
  不会报告 `MEM-001` 或 `VLM-001` 违例。
- 目标依据：[MEM/VLM 接口的复位和 X/Z](spec/mem-vlm-interface.md#5-复位和-xz)。正常
  cycle transaction 仍只在 reset 释放后创建；复位静默检查应使用独立的 assertion、
  reset-only monitor 路径或等价机制。
- 验收：在已知 `rst_n==0` 的周期分别拉高四类 request/valid，均能得到明确错误；reset
  为 X/Z 时不启动业务 X/Z 检查，也不产生正常 transaction。

## 5. 已解决记录

当前没有在本轮文档迁移中关闭的实现问题。问题完成后应保留 ID，并记录修改文件、
commit、验证命令、结果和日期。
