# ut_shm 验证状态

本文只维护当前尚未闭环的验证实现问题。问题完成后从本文删除，ID 保留且不再复用。
历史开发过程由 [development](../development/index.md) 和 Git 历史追踪；当前回归组成与结果见
[测试与回归](plan/testcases-and-regression.md)，覆盖率数据与 closure 方法见
[覆盖率与收敛](plan/coverage-and-closure.md)，需求与测试映射见 [测试点](plan/testpoints.md)。

## 1. 状态定义

| 状态 | 含义 |
|---|---|
| `待实现` | 尚无满足需求的实现 |
| `实现中` | 已有部分实现，但仍存在明确缺口 |
| `待验证` | 实现已具备，尚缺独立验收证据 |
| `已完成` | 已满足验收条件；更新归属文档后从本文删除 |

状态通常按照以下方向推进：

```text
待实现 -> 实现中 -> 待验证 -> 已完成并移出本文
```

| 优先级 | 含义 |
|---|---|
| `P0` | 阻塞核心功能验证或可能掩盖严重 DUT 问题 |
| `P1` | 影响主要场景的完整性、可观测性或收敛效率 |
| `P2` | 非阻塞的健壮性、维护性或扩展性问题 |

关闭问题前，应先把仍有长期价值的接口、用法、回归和覆盖率信息更新到对应的当前文档。

## 2. 当前支持边界

- 当前只支持完整 active 环境；不支持的 passive 或半连接配置必须在 build 阶段明确拒绝。
- DUT 可以乱序调度多笔 creq，但最终 memory 结果必须与 creq 顺序执行的结果一致。
- 当前双 gid spec 是目标协议；物理 storage key 是 `<bank_id,gid,BADDR>`，MEM transaction
  的 gid 由唯一到期 reservation record 恢复。
- SHMINS 使用生成式 post-randomize sequence item，支持 V2M、M2V、VTRANS 和三种 space。
- Directed queue 已支持发送前的跨 transaction V-write/M-access byte hazard 检查；
  scoreboard 已支持 drain 后的 touched-byte `ref_banks/rtl_banks` 最终比较。四个最小顺序
  RTL case 已编译，正式 design 结果仍按 [TP-DATA-004](plan/testpoints.md) 跟踪。
- 真实设计回归和覆盖率的最新结论不在本文重复，统一以
  [测试与回归](plan/testcases-and-regression.md) 和 [覆盖率与收敛](plan/coverage-and-closure.md) 为准。

## 3. 开放问题总表

| ID | 优先级 | 状态 | 开放问题 |
|---|---:|---|---|
| ENV-001 | P0 | 待实现 | 运行期 reset 支持尚未闭环 |
| ENV-002 | P2 | 待实现 | unsupported passive 配置可能形成半连接环境 |
| COV-001 | P1 | 实现中 | 功能覆盖率模型仍未覆盖全部测试点 |
| DBANK-001 | P0 | 待验证 | 双 gid 地址映射尚缺逐 bin closure 证据 |
| DBANK-002 | P0 | 待验证 | M2V 双 gid 数据路径尚缺逐 bin closure 证据 |
| DBANK-004 | P0 | 待验证 | reservation/MEM 双 gid 归属尚缺完整负向与覆盖证据 |
| DBANK-005 | P1 | 待验证 | 双 gid 定向用例尚未完成覆盖率归档与回归准入 |
| SHMINS-004 | P1 | 待验证 | unit sequence 的 ATYPE_S/G 配置尚缺端到端验证 |
| SHMINS-005 | P2 | 待实现 | SHMINS package 仍依赖固定参数组合 |
| SHMINS-006 | P1 | 实现中 | X/Z don't-care 验证矩阵仍不完整 |
| SHMINS-008 | P1 | 待验证 | ACK lifecycle 的超时边界尚缺定向验证 |
| SHMINS-009 | P1 | 待验证 | credit 与 ACK 完备性检查尚缺定向正负例 |
| SHMINS-010 | P1 | 待实现 | reset 期间 release/ACK 静默尚未检查 |
| VMEM-001 | P0 | 实现中 | `FFD_CYC>=1` read snapshot 已实现，0-cycle 窗口尚未支持 |
| VMEM-002 | P1 | 待实现 | memory interface 的 X/Z 检查不完整 |
| VMEM-003 | P2 | 实现中 | 旧 agent 辅助结构已删除，保留 transaction compare API 尚待处理 |
| SCB-002 | P1 | 待验证 | scoreboard timeout 边界与诊断尚缺定向验收 |
| RSV-002 | P1 | 实现中 | reservation 功能覆盖率模型仍未闭环 |
| RSV-004 | P1 | 待实现 | 全局 `input_error` 会抑制无关 slot 的检查 |
| RSV-005 | P1 | 待实现 | reset 期间 reservation/MEM request 静默尚未检查 |

## 4. 开放问题详情

### ENV-001：运行期 reset 支持

- 当前实现：环境支持上电复位后的正常启动，但组件状态机、队列和预期模型没有统一的运行期 reset 协议。
- 剩余缺口：缺少 reset 期间的 stimulus 停止、outstanding 清理、monitor 重新同步和 scoreboard 重启规则。
- 影响：事务在 reset 前后跨界时，可能产生假超时、幽灵匹配或遗留 reservation。
- 验收条件：定义统一 reset contract，补齐各组件实现，并通过 idle、active request 和 outstanding transaction 三类 reset 场景。
- 关联 testpoint：[TP-RST-002](plan/testpoints.md)。

### ENV-002：unsupported passive 配置

- 当前实现：config 仍暴露多组 active/passive knob，但 reservation agent 固定为 active；关闭
  scoreboard 时，active memory driver 的 blocking transport 也会失去目标。
- 剩余缺口：公开配置允许选择当前架构无法组成完整连接的组合。
- 影响：非默认配置可能在 elaboration 或运行时形成半连接环境并挂起。
- 验收条件：删除无效 knob，或让每个不支持的组合在 build 阶段给出明确 fatal；所有保留组合均能形成完整连接。
- 关联 testpoint：无直接 DUT testpoint；属于环境支持边界。

### COV-001：功能覆盖率模型完整性

- 当前实现：已具备 request、mask、VTRANS、X/Z、地址、M2V gid、reservation admission 和 MEM match 等覆盖组；当前数据统一记录在
  [覆盖率与收敛](plan/coverage-and-closure.md)。
- 剩余缺口：ACK、异常/边界时序、reset、scoreboard lifecycle、ordered-access 类型与最终
  收敛结果，以及现有未满覆盖组的逐 bin 分析尚未闭环。
- 影响：回归通过只能证明已执行用例未报错，不能证明测试计划中的关键交叉已命中。
- 验收条件：为开放 testpoint 建立 coverage mapping，逐项关闭 uncovered bin，或记录可审查的 waiver。
- 关联 testpoint：[测试点总表](plan/testpoints.md) 中所有尚未 closure 的条目。

### DBANK-001：双 gid 地址映射

- 当前实现：reference 已采用逻辑地址到 `<bank_id, warp_id, laddr>`、再到 `<gid, baddr>` 的两层映射；双 gid 定向地址用例已具备。
- 剩余缺口：地址边界、warp 3/4 分界、gid 交叉和 BLK/WRP/LOC 组合尚缺逐 bin 分析与归档。
- 影响：无法仅凭用例通过证明所有双 gid 映射边界均已命中。
- 验收条件：完成 `address_cg` 与相关 testpoint 的逐 bin 映射，补齐未覆盖场景或形成 waiver。
- 关联 testpoint：[TP-ADDR-004～TP-ADDR-009](plan/testpoints.md)。

### DBANK-002：M2V 双 gid 数据路径

- 当前实现：reference 和 scoreboard 以 gid 区分上下 BANK，M2V vaddr 边界与 gid 定向用例已具备。
- 剩余缺口：warp 3/4、dtype、mask、byte lane 和读写回填组合尚缺逐 bin closure。
- 影响：可能遗漏地址正确但 gid、byte enable 或回填数据错误的组合。
- 验收条件：完成 `m2v_gid_cg` 及数据路径相关 coverage bin 分析，并对缺口补用例或 waiver。
- 关联 testpoint：[TP-DATA-001、TP-DATA-002、TP-ADDR-009](plan/testpoints.md)。

### DBANK-004：reservation/MEM 双 gid 归属

- 当前实现：reservation record、scheduler、monitor 和 scoreboard 均携带 gid；MEM 无 gid 时由唯一到期 reservation record 恢复归属。
- 剩余缺口：错误 gid、无匹配、歧义匹配、同 delay 冲突和 other-gid external busy 等负向场景尚缺完整断言与覆盖证据。
- 影响：归属算法错误可能把 MEM transaction 匹配到错误 BANK，进而掩盖数据或时序问题。
- 验收条件：正向场景全部通过，负向注入触发预期 checker，相关 admission/match bins 有明确 closure 结论。
- 关联 testpoint：[TP-RSV-002～TP-RSV-008](plan/testpoints.md)。

### DBANK-005：双 gid 定向用例归档

- 当前实现：已具备 warp 边界、gid isolation、M2V vaddr boundary 和 reservation ownership 等定向测试资产。
- 剩余缺口：尚未依据逐 bin 结果确定哪些用例进入主回归、哪些仅作为诊断用例，以及失败场景是否需要 waiver。
- 影响：测试资产存在但没有稳定的回归准入和 closure 口径。
- 验收条件：在 [测试与回归](plan/testcases-and-regression.md) 中明确用例分组、预期结果和主回归准入，并关联覆盖率证据。
- 关联 testpoint：[TP-ADDR-009、TP-RSV-007、TP-RSV-008](plan/testpoints.md)。

### SHMINS-004：unit sequence 配置贯通

- 当前实现：`shmins_mst_unit_sequence` 使用 allowed-value domain 约束 ATYPE_W/S/G、dtype、
  RW、itype 和 space，并支持 `set_fixed_*()` 将对应 domain 缩为单值。
- 剩余缺口：RW、DTYPE、ATYPE_W、ITYPE 和 SPACE 已经经过系统回归，ATYPE_S/G 尚缺从
  testcase 配置入口到 monitor transaction 的端到端定向证据。
- 影响：item 生成侧配置已经贯通，但 testcase/plusarg 集成路径仍可能遗漏 signedness 或 granularity。
- 验收条件：分别设置 ATYPE_S 和 ATYPE_G 的公开配置入口，确认 monitor transaction 与配置一致。
- 关联 testpoint：[TP-ADDR-001](plan/testpoints.md)。

### SHMINS-005：SHMINS package 参数化

- 当前实现：当前 package 和多数 test 以项目默认参数组合编译。
- 剩余缺口：类型、数组维度和 helper 中仍存在固定宽度或固定规模假设。
- 影响：复用于不同 SHM 参数的 UT 时可能编译失败或产生错误布局。
- 验收条件：列出公共参数化边界，消除固定假设，并使用至少一组非默认参数完成组件编译测试。
- 关联 testpoint：无直接 DUT testpoint；属于公共 UVC 可复用性要求。

### SHMINS-006：X/Z don't-care 验证矩阵

- 当前实现：inactive thread meta、active thread masked element payload 等合法 X 场景已有定向用例、monitor 分类和功能覆盖。
- 剩余缺口：Z/XZ 形态，以及 invalid public field、active meta 和 interpreted payload 的完整负向矩阵尚未覆盖。
- 影响：可能把合法 don't-care 误报为错误，也可能漏掉会被 DUT 解释的未知值。
- 验收条件：完成字段分类矩阵；合法 X/Z/XZ 不报错，非法未知值稳定触发 checker，相关 coverage bin 完成 closure。
- 关联 testpoint：[TP-CREQ-002、TP-CREQ-004](plan/testpoints.md)。

### SHMINS-008：ACK lifecycle 超时边界

- 当前实现：lifecycle checker 按方向维护有序退休，ACK grace 从事务及同方向前序事务退休后开始计算。
- 剩余缺口：grace 为 0、边界周期到达、超一周期、无需 ACK 的前序事务和年轻事务提前完成等场景尚缺独立定向测试。
- 影响：边界实现错误可能造成假超时或漏报迟到 ACK。
- 验收条件：无 DUT 组件测试覆盖所有边界，并在真实设计上验证至少一个前序阻塞场景。
- 关联 testpoint：[TP-ACK-001](plan/testpoints.md)。

### SHMINS-009：credit 与 ACK 完备性检查

- 当前实现：driver 使用 `credit_cnt` 限制发送，并检查 `creq_rls` 不得令 credit 超过 `OTF_N`；
  lifecycle checker 已实现 ack-disabled、unexpected、duplicate、wrong-direction、wrong-ID、
  reset-epoch 关联和 exactly-once 状态。
- 剩余缺口：credit 上溢以及各类错误 ACK 尚未完成独立负例验收。
- 影响：没有负例证据时，无法确认每种违例均能被唯一、准确地分类和定位。
- 验收条件：定向覆盖 credit 上溢及各类错误 ACK；每类违例只产生预期错误，合法 release/ACK 独立顺序不误报。
- 关联 testpoint：[TP-CREQ-001、TP-ACK-001](plan/testpoints.md)。

### SHMINS-010：reset 期间 release/ACK 静默

- 当前实现：driver 和 monitor 等待初始 reset 释放后进入业务循环。
- 剩余缺口：没有独立检查 `rst_n==0` 时 `creq_rls`、`vack_done` 和 `mack_done` 必须为 0。
- 影响：DUT 在初始或运行期 reset 中错误归还 credit 或发送 ACK 时可能不被报告。
- 验收条件：reset 已知为 0 时分别注入 release、V2M ACK 和 M2V ACK，均得到明确错误；
  reset 为 X/Z 时不启动正常 payload 检查，done 为 0 时不检查 ID。
- 关联 testpoint：[TP-RST-001](plan/testpoints.md)。

### VMEM-001：`FFD_CYC` read snapshot

- 当前实现：统一 VLM agent 对 `FFD_CYC>=1` 在 `T0+FFD_CYC-1` 形成 snapshot，并在
  `T0+RPORT_DLY` 返回；同步 write transport 与 committed-cycle watermark 消除了同周期
  process-order 依赖。组件测试已覆盖 `FFD_CYC=1/2`、截止边界、边界后写、partial strobe、
  多次覆盖、连续同 BANK read 和双 gid 隔离，空 design 全量 VCS 编译通过。
- 剩余缺口：`FFD_CYC=0` 尚未支持。
- 影响：正参数窗口已经可信；若未来参数取 0，环境会在 build 阶段 fatal，不能用于验证该配置。
- 验收条件：覆盖 `FFD_CYC=0`、1 和大于 1，验证截止前、边界和截止后的重叠 write 可见性。
- 关联 testpoint：[TP-MEM-003](plan/testpoints.md)。

### VMEM-002：memory interface X/Z 检查

- 当前实现：统一 VLM monitor 能采集有效读写 transaction 并完成基础字段转换。
- 剩余缺口：valid 拉起时的 addr、data、mask、delay 关联字段未知值检查不完整。
- 影响：X/Z 可能进入 reference 或 scoreboard，形成不稳定比较或掩盖 DUT 接口问题。
- 验收条件：明确 valid 与 don't-care 字段矩阵，合法未知值不报错，非法未知值由定向注入稳定触发错误。
- 关联 testpoint：[TP-MEM-001、TP-MEM-002](plan/testpoints.md)。

### VMEM-003：无效辅助结构

- 当前实现：旧的独立 interface、monitor、driver、sequencer、config 和 agent 已删除；
  `vlm_memory_sequence_item` 作为统一 VLM agent 与 scoreboard 的公共 transaction 保留。
- 剩余缺口：`vlm_memory_sequence_item.compare_item()` 不会累计错误，且循环硬编码为 16。
- 影响：调用方可能依赖静默返回错误结果的 API，维护者也难以判断真实数据流。
- 验收条件：删除无意义结构，或补齐可验证用途；所有保留 compare API 均有定向组件测试。
- 关联 testpoint：无直接 DUT testpoint；属于 memory agent API 健壮性要求。

### SCB-002：scoreboard timeout 边界与诊断

- 当前实现：record age 和 no-progress timeout 可由 plusarg 按 case 配置，默认可关闭；错误日志包含事务身份与 unresolved bytes。
- 剩余缺口：关闭、最小非零值、恰好边界、超过边界和持续有进展等场景尚缺独立测试。
- 影响：timeout 判断可能在高冲突场景误报，或因边界错误漏掉真正卡死。
- 验收条件：用可控 clock 和人工 progress 事件完成边界组件测试，确认错误次数、周期和诊断字段均符合预期。
- 关联 testpoint：[TP-DATA-004](plan/testpoints.md)。

### RSV-002：reservation 功能覆盖率

- 当前实现：已有 reservation admission 和 MEM match 覆盖组，覆盖 gid、busy 来源和匹配结果等基础维度。
- 剩余缺口：同/异 gid、同/异 subbank、delay、内部/外部 busy、接受/拒绝以及 resolver 负向结果的交叉尚未全部 closure。
- 影响：checker 通过不能证明关键并发与阻塞组合都被执行。
- 验收条件：建立 coverage-to-testpoint mapping，逐 bin 分析并通过定向用例或 waiver 关闭缺口。
- 关联 testpoint：[TP-RSV-001～TP-RSV-008](plan/testpoints.md)。

### RSV-004：`input_error` 抑制粒度

- 当前实现：cycle transaction 只有一个全局 `input_error`；任意 busy、reservation 或 MEM
  端口出现 X/Z 后，checker 会跳过本周期全部 observed-busy 比较，并抑制所有到期 record 的 `MISSING_MEM`。
- 剩余缺口：错误可靠性没有细化到受影响的 busy bit 或 request port。
- 影响：一个 BANK 或方向的四态错误会掩盖其他独立 slot 的 busy mismatch 或 missing MEM。
- 验收条件：改为局部抑制；向一个端口注入 X/Z 时，该端口不产生级联误报，同周期其他独立
  BANK/direction 的真实错误仍能被报告。
- 关联 testpoint：[TP-RSV-004](plan/testpoints.md)。

### RSV-005：reset 期间 request quiescence

- 当前实现：`collect_cycle()` 在 `rst_n!==1` 时等待，不采样 reservation 或 MEM request。
- 剩余缺口：没有检查 reset 期间 `vlm_rreq`、`vlm_wreq`、`mem_rvld` 和 `mem_wvld` 必须为 0。
- 影响：DUT 在初始或运行期 reset 中错误发出 reservation/MEM request 时不会被报告。
- 验收条件：通过独立 assertion 或 reset-only monitor 路径检查四类信号；reset 已知为 0 时的
  逐类违例均有明确错误，reset 为 X/Z 时不创建正常 transaction。
- 关联 testpoint：[TP-RST-001](plan/testpoints.md)。
