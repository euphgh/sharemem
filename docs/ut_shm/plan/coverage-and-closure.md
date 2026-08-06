# ut_shm Coverage 与关闭条件

本文定义 ut_shm 如何使用 functional coverage、代码 coverage、断言 coverage 和
waiver 判断验证是否收敛。逐功能点的目标 bin/cross 见
[Testpoints](testpoints.md)；本文不重复 DUT spec 或 case 列表。

## 1. 当前状态

当前仓库没有有效的 functional covergroup、coverpoint 或 cross：

- shmins monitor 中只有被注释的历史 coverage include；
- reservation coverage class 只有空的同步入口和恒为 0 的计数器；
- reference、scoreboard 和 memory agent 没有 functional coverage model。

因此，当前 regression case 数、checker error 数为 0、reservation matched counter 或
代码执行日志都不能作为 functional coverage 已完成的证据。所有 testpoint 的
functional coverage 状态统一为“未实现”，总体不能标记为已闭环。全局缺口见
`COV-001`，reservation 子组件缺口另见 `RSV-002`。

## 2. Functional coverage

### 2.1 目标来源

Functional coverage 必须从 spec-first testpoint 派生。每个 testpoint 至少定义一个
可观察的合法场景 bin；需要证明组合关系时定义 cross。当前随机约束能生成什么不能用来
删除 spec 要求的 bin，只能决定该 bin 的激励状态是完整、部分还是缺失。

### 2.2 建议采样边界

|Coverage 领域|建议采样对象|原因|
|---|---|---|
|creq 字段和合法性|shmins monitor 采样后的 transaction|代表 DUT 实际接受的输入，不依赖 sequence 生成意图|
|地址和数据语义|reference 计算出的 thread/element/byte 派生信息|能观察 MADDR、BANK、BADDR、空洞边界和 byte mask|
|MEM 请求|memory monitor transaction|代表实际 MEM read/write 行为|
|Reservation|reservation cycle transaction、checker result、scheduler pre-update view|能区分方向、delay、busy 来源、共享 slot 和匹配结果|
|乱序与最终状态|scoreboard reference/actual 匹配事件|能区分 final、expired、overlap、timeout 和最终收敛|
|Reset|统一 reset event 与各组件 pending-state 快照|能证明在不同在途阶段进入 reset|

Coverage 采样不得修改 transaction、scheduler 或 checker 状态。需要跨组件关联时，应
建立只读 coverage transaction，而不是从层次路径读取临时变量。

### 2.3 基础 coverpoint

Phase 5 规划的基础维度包括：

- creq direction、info、ack enable、tmsk population、DTYPE、ATYPE width/sign/granularity、
  ITYPE、SPACE、interleave size、wpid、wpnum 和 priority；
- thread/element/byte mask，length 最小值、最大值、尾部 byte 和 32-Byte beat 跨界；
- MADDR 合法边界、WRP/BLK 12 KiB 与 16 KiB 编码、地址空洞相邻值、BANK、BADDR 和
  WARP group；
- MEM direction、BANK、source alignment 类别、strobe 形状、read pipeline 深度和
  read/write 相对周期；
- reservation direction、delay、sub bank、external/SHM busy、共享 slot、到期冲突和
  match 结果；
- creq overlap、DUT 中间兑现为 final/expired、最终顺序收敛和 reset 时 pending 类型。

详细 bin 和 cross 以 [Testpoints](testpoints.md)为准。实现时可以合并共享 coverpoint，
但报告必须能回溯到 testpoint ID。

### 2.4 Cross 原则

只建立能回答功能问题的 cross，避免对全部字段做笛卡尔积。优先 cross：

- direction × ITYPE × SPACE × DTYPE × ATYPE_W；
- ATYPE_W × signedness × granularity × DTYPE；
- SPACE × interleave size × MADDR boundary class；
- SPACE_BLK 的 wpnum × warp_group × interleave size；
- access source × aligned/nonaligned × MEM/VLM direction；
- reservation direction × delay × busy source × match result；
- overlap class × DUT 兑现次序 × final convergence；
- reset stage × pending state type。

不可能或 spec 明确排除的组合应使用 `ignore_bins`，协议非法且由负向测试注入的组合可用
`illegal_bins` 或独立 error-injection coverage 表达。不能用 ignore bin 隐藏当前
sequence 生成不了的合法场景。

## 3. 代码 coverage

代码 coverage 用于发现 RTL 或 testbench 未执行路径，不能替代 functional coverage。
关闭时至少区分 statement/line、branch/condition、toggle 和 FSM；第三方 VIP、生成代码
或不可达配置应通过明确 exclusion 处理。

当前仓库没有确认的数字阈值，也没有可重复的 coverage merge 基线。在项目确定阈值前，
代码 coverage 只能作为开放指标，不能仅凭一次报告宣称关闭。阈值、采集选项和 merge
命令后续放入 guide 或回归配置，不写入 testpoint。

## 4. 断言 coverage

协议时序适合使用 assertion，包括：

- reset 期间 valid/req/done/release 静默；
- credit 不下溢、不上溢；
- ack 方向、ID 和 exactly-once；
- reservation delay、busy admission 和到期兑现；
- MEM read 的固定返回周期。

Assertion pass 证明检查没有失败，assertion coverage 还必须证明 antecedent 被触发。
从未触发的 assertion 不能作为对应 testpoint 的关闭证据。当前尚未建立 assertion
coverage 清单，实施后应把 assertion 名称映射回 testpoint ID。

## 5. Waiver

每个 waiver 必须记录：

- waiver ID 和对应 testpoint/coverage bin；
- 未命中的原因以及为什么不是 DUT 或激励缺陷；
- spec 依据或不可达证明；
- 影响范围；
- 复查条件和当前状态。

“随机次数不够”“当前 sequence 不支持”或“checker 没报错”不能作为 waiver 理由。
这些情况分别属于 regression 深度、激励缺口或检查缺口。

## 6. Testpoint 关闭条件

一个 testpoint 只有同时满足以下条件，才能从“部分实现/可运行未闭环”进入“已闭环”：

1. Spec 稳定，testpoint 的验证目标和边界明确；
2. 激励能够定向或受约束地产生所有要求场景，不依赖不可证明的低概率随机命中；
3. Checker 能独立判断正确结果和必要的错误边界；
4. 所有必需 functional bin/cross 已命中，或有有效 waiver；
5. 对应 testcase 已进入目标 regression，seed 失败可复现；
6. 没有会使本 testpoint 结果不可信的开放 P0 问题；
7. 相关 regression 在真实 design 环境中通过，且没有未解释的 UVM error/fatal。

如果 checker 和 case 已存在但 functional coverage 未实现，只能标为“可运行未闭环”。
如果激励、checker 或 reference 本身与 spec 不一致，应标为“部分实现”，不能用回归通过
覆盖该缺口。

## 7. 功能级关闭条件

一个功能领域关闭前，还必须：

- 该领域所有 required testpoint 已闭环或具有有效 waiver；
- 该领域 coverage 报告能够按 testpoint ID 回溯；
- 相关代码和断言 coverage 的未覆盖项已经分析，而不是只看总百分比；
- regression 列表、TC 定义和文档映射一致；
- `verification-status.md` 中影响该领域的 P0/P1 问题已经处理或明确批准暂缓。

整个 ut_shm 关闭需要所有功能领域满足上述条件。当前没有 functional coverage，且仍有
多项 P0 实现缺口，因此 Phase 5 的产物是完整验证目标和缺口基线，不是验证完成声明。

