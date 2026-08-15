# 统一 VLM agent 的 reservation 路径

本文说明当前双 gid 架构中统一 VLM agent 如何按周期联合采样 reservation 和 MEM 请求，
检查 busy 与到期匹配，为 MEM transaction 恢复 gid，并生成下一周期 busy。协议规则见
[MEM/VLM 接口规范](../../spec/mem-vlm-interface.md)；本文区分稳定检查职责和当前尚未
修复的实现差异。

## 1. 组件结构和支持模式

```text
vlm_agent
├── vlm_monitor
├── vlm_reservation_checker
├── vlm_reservation_coverage
├── vlm_reservation_scheduler
└── external_busy_policy       可选的 config-owned uvm_object，不是子 component
```

Agent 取得统一 `vlm_interface` 和共享 `clk_if`，固定创建完整层次并主动驱动 busy 与 read
data；passive 模式明确不支持。第一版由 checker 返回唯一到期 record 的 gid/match metadata，
agent 自身负责发布 MEM transaction 和组织 read response，因此没有单独的 resolver/driver
子组件，也不会产生第二个 MEM transaction 发布者。

## 2. 主要源文件

|文件|作用|
|---|---|
|`ver_common/uvc/vlm_agent/vlm_interface.sv`|统一 reservation、busy 和 MEM clocking block|
|`ver_common/uvc/vlm_agent/vlm_agent.svh`|主环境使用的统一 agent 公共类型|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_types.svh`|request、record、cycle transaction 和 result 类型|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_agent.svh`|层次、配置、单周期调度和 busy 驱动|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_monitor.svh`|四态采样和归一化|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_checker.svh`|busy、reservation 与 MEM 到期匹配|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_scheduler.svh`|窗口、record、external/SHM/final busy|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_external_busy_policy.svh`|可定向 external busy 策略及 cycle-range 实现|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_coverage.svh`|第一批 ownership、admission 和 MEM match coverage|

## 3. 单周期处理顺序

Agent 的 `main_phase` 是唯一消耗周期的核心循环。每次迭代按以下顺序执行：

```text
monitor.collect_cycle()
        ↓
checker.check_cycle()       读取 pre-update 状态并返回 gid/match status
        ↓
publish/serve MEM           发布 write 或组织 read response
        ↓
coverage.sample_cycle()     读取同一个 pre-update 状态
        ↓
scheduler.process_cycle()   窗口推进、接纳请求、生成 external busy
        ↓
agent.drive_busy()          驱动下一接口周期
```

Checker、resolver 和 coverage 必须在 scheduler 更新前运行，否则采样到的 busy、record 和
transaction cycle 不再属于同一状态。

环境连接和周期调度异常使用以下 report ID：

|位置|条件|Report ID|
|---|---|---|
|Agent/monitor 配置|缺少 config 或统一 VLM interface|`VLM_RESERVATION_NO_CFG`、`VLM_RESERVATION_NO_VIF`|
|External busy 配置|`EXTERNAL_BUSY_PERCENT` 超出 0～100；合法值也用同一 ID 打印最终配置|`VLM_RESERVATION_EXTERNAL_PERCENT`|
|Monitor|开始采样时缺少 clock 或统一 VLM interface|`VLM_RESERVATION_MONITOR_NOT_READY`|
|Agent|驱动 busy 时缺少统一 VLM interface 或 scheduler|`VLM_RESERVATION_AGENT_NOT_READY`|
|Scheduler|transaction cycle 与共享 cycle 不同，或相邻 transaction 不连续|`VLM_RESERVATION_CYCLE_MISMATCH`、`VLM_RESERVATION_NONCONSECUTIVE_CYCLE`|

这些错误表示 testbench 连接、配置或内部处理顺序损坏，不属于 DUT 协议失败。

## 4. Cycle transaction

Monitor 把同一采样沿的接口值归一化到
`vlm_reservation_cycle_transaction_t`，其中包括：

- read/write `[delay][gid][sub_bank]` busy window；
- 每个 bank 的一条带 gid read reservation；
- 每个 bank、每个 write port 的带 gid write reservation；
- 每个 bank 的实际 MEM read/write valid 和完整地址；
- 共享 `clk_if.cycle_count` 与 `input_error`。

有效 reservation 由地址、gid 和相对 delay 组成；实际 MEM request 只表示本周期已经
出现在 MEM 端口的请求。Scheduler record 保存 direction、gid、source port、issue
cycle/delay 和完整地址，用于到期周期的一对一匹配。

## 5. Monitor 的四态边界

`collect_cycle()` 每次都先等待采样到 `rst_n===1`。因此 reset 未释放或运行中 reset
期间不执行 busy/request 的 X/Z 检查，也不生成 cycle transaction；复位前 1 ns 的未知
busy 不会再触发 `VLM_RESERVATION_BUSY_XZ`。

这条门控也意味着当前 monitor 不检查已知 `rst_n==0` 时 DUT request/valid 必须保持
为 0，相关协议检查缺口见 `RSV-005`。

Reset 释放后，monitor 对 busy、reservation valid/address/delay 和 MEM valid/address
执行四态检查。X/Z 会被报告，并在 two-state transaction 中归一化为 inactive/0，且
设置 `input_error`，防止 checker 把不可靠的 observed busy 再报成普通 mismatch。

|采样内容|触发条件|Error ID|
|---|---|---|
|Read/write busy bit|任意 delay、gid、sub-bank 的值含 X/Z|`VLM_RESERVATION_BUSY_XZ`|
|Read reservation request|`rreq` 含 X/Z|`VLM_RESERVATION_RREQ_XZ`|
|Read reservation payload|active `raddr` 或 `rdly` 含 X/Z|`VLM_RESERVATION_RADDR_XZ`、`VLM_RESERVATION_RDLY_XZ`|
|Read reservation gid|active `rgid` 含 X/Z|`VLM_RESERVATION_RGID_XZ`|
|Write reservation request|任一 port 的 `wreq` 含 X/Z|`VLM_RESERVATION_WREQ_XZ`|
|Write reservation payload|active `waddr` 或 `wdly` 含 X/Z|`VLM_RESERVATION_WADDR_XZ`、`VLM_RESERVATION_WDLY_XZ`|
|Write reservation gid|active `wgid` 含 X/Z|`VLM_RESERVATION_WGID_XZ`|
|MEM request valid|`mem_rvld` 或 `mem_wvld` 含 X/Z|`VLM_RESERVATION_MEM_RVLD_XZ`、`VLM_RESERVATION_MEM_WVLD_XZ`|
|MEM request address|active `mem_raddr` 或 `mem_waddr` 含 X/Z|`VLM_RESERVATION_MEM_RADDR_XZ`、`VLM_RESERVATION_MEM_WADDR_XZ`|

Monitor 只负责采样与归一化，不判断 reservation 是否能接纳，也不匹配 MEM 数据。

## 6. Scheduler 状态

Scheduler 分离保存三组状态：

- `external_busy[direction][delay][gid][sub_bank]`：环境注入的外部占用；
- `shm_records[direction][delay][bank]`：已经接纳、尚未到期的 DUT reservation；
- `shm_busy`：按 record 的 gid 和 `address[6:5]` 对所有 bank 做 OR reduction；
- `final_busy = external_busy | shm_busy`。

不同 bank 的 record 可以映射到同一个 gid/sub-bank busy bit；同一个
direction/delay/bank 只能有一条到期记录，因为实际 MEM 端口每个 bank、每个方向只有
一个 request slot。`shm_records` 故意不增加 gid 维度：它表达 MEM 端口所有权，而不是
物理 BANK busy 所有权。
Write 的两个 reservation port 若在同一 bank 同一周期选择相同 delay，也会竞争同一个
到期 slot。

每周期 scheduler 先推进窗口和清理已到期记录，再重建 busy、接纳当前合法 request，
最后在仍空闲的每个 slot 上生成 external busy。生成来源是 optional policy 或百分比随机
模式，二者不会在同一个周期混用。

## 7. External busy 配置

Config 的 `external_busy_policy` 默认为 null。null 表示使用原百分比随机模式：概率来自
大写字段 `EXTERNAL_BUSY_PERCENT`，命令行 `+EXTERNAL_BUSY_PERCENT=<0..100>` 可以覆盖。
Agent 在 build phase 校验范围，并把最终值传给 scheduler 的内部字段
`external_busy_percent`。

随机 busy 只会填充本周期处理后仍无 SHM 所有权的 slot。配置为 0 时不会随机拉起；
配置非零仍属于概率行为，波形上不保证某个指定 slot 或某个短窗口必然为 1。

`external_busy_policy` 非空时优先于百分比随机模式。当前
`vlm_reservation_directed_busy_policy` 用一组 inclusive cycle range 指定
`<direction,delay,gid,sub_bank>`；cycle 表示 scheduler 本次处理完成后将要驱动到接口的
`drive_cycle`，即 transaction cycle 的下一拍，而不是 monitor 已采样的 cycle。Policy
只会填充仍空闲的 slot，不能覆盖已有 external 或 SHM ownership，也不读取 checker
outcome。这样测试可以稳定构造 ownership 场景，同时保持默认随机 regression 行为不变。

## 8. Checker 职责

Checker 的入口是同步 function `check_cycle(const ref txn)`。它不消耗仿真时间，也不
修改 scheduler；所有检查都读取产生当前接口 busy 的 pre-update scheduler 状态。
`check_cycle()` 每次先清零 `current_result`，依次执行 cycle/busy、reservation 和 MEM
检查，最后返回 `vlm_reservation_check_result_t`。

### 8.1 检查结果和累计计数

|结果字段|含义|
|---|---|
|`reservation_error_count`|本周期 reservation delay、busy 或到期冲突错误数|
|`busy_error_count`|本周期 cycle、record 和 busy 状态错误数|
|`mem_match_error_count`|本周期到期 record 与实际 MEM request 的匹配错误数|
|`dly_zero_error_count`|本周期不支持的 `dly==0` 请求数|
|`matched_mem_request_count`|本周期完整通过到期匹配的 MEM request 数|
|`reservation_outcome[direction][bank][port]`|逐请求 present/accepted/delay/target-busy/pending/current-conflict flags|
|`mem_match_outcome[direction][bank]`|逐 MEM slot request/record/matched/unexpected/missing/busy/address/due flags|
|`passed`|上述四类 error count 均为 0；matched 数不参与 pass 判定|

Checker class 还维护同名的仿真期累计计数器。Monitor 报告的 X/Z 不直接增加这些
checker counter，也不直接把 `current_result.passed` 置 0；该状态通过
`txn.input_error` 单独传给 checker 和 coverage。结构化 outcome 与现有 report ID 同时
填写，只供 assertion/checker 证据、组件断言、coverage 和调试使用；它们不反馈给
scheduler，也不能控制 RTL request/busy 输出。

### 8.2 依赖和 cycle 一致性

|检查|失败条件|错误 ID|
|---|---|---|
|共享 cycle source|build phase 取不到 `clk_vif`，或调用时 handle 为空|`VLM_RESERVATION_NO_CLK_VIF`|
|Scheduler 连接|调用 `check_cycle()` 时 `scheduler==null`|`VLM_RESERVATION_NO_SCHEDULER`|
|Transaction cycle|`txn.cycle != clk_vif.cycle_count`|`VLM_RESERVATION_CYCLE_MISMATCH`|
|Pre-update 顺序|已有历史时，`scheduler.last_processed_cycle+1 != txn.cycle`|`VLM_RESERVATION_SCHEDULER_CYCLE`|

前两项是 testbench 连接错误，使用 `UVM_FATAL`。后两项表示 agent 调用顺序或共享周期
视图损坏，计入 `busy_error_count`；即使发生，checker 仍继续检查当周期其他状态，以便
一次日志暴露更多内部不一致。

### 8.3 Scheduler record 自洽性

Checker 遍历所有 `shm_records[direction][relative_delay][bank]`，对每个非空 record
执行以下检查：

|检查|失败条件|错误 ID|
|---|---|---|
|来源端口|read record 的 `write_port!=0`，或 write record 端口越界|`VLM_RESERVATION_RECORD_WRITE_PORT`|
|原始 delay|`issue_delay==0` 或 `issue_delay>=VTAB_D`|`VLM_RESERVATION_RECORD_DELAY`|
|到期方程|`issue_cycle+issue_delay != txn.cycle+relative_delay`|`VLM_RESERVATION_RECORD_DUE_CYCLE`|

Record 的来源、原始 delay、地址和 issue cycle 应在窗口移动过程中保持不变；到期方程
保证 scheduler 没有把 record 提前、延后或放入错误的 relative-delay 位置。Reservation
agent 不再根据 direction 或 write port 对 record 地址执行 alignment policy。

### 8.4 Busy 来源一致性

对每个 `<direction, relative_delay, gid, sub_bank>`，checker 先遍历全部 bank record，按
`record.gid` 和 `record.address[6:5]` 计算 `has_record`，再执行：

|检查|失败条件|错误 ID|
|---|---|---|
|来源互斥|同一 slot 的 `external_busy && shm_busy`|`VLM_RESERVATION_BUSY_OVERLAP`|
|Record 归约|`shm_busy != has_record`|`VLM_RESERVATION_SHM_BUSY_RECORD`|
|最终 busy|`final_busy` 不等于 external 与 SHM busy 的 OR|`VLM_RESERVATION_FINAL_BUSY`|
|接口观察值|`txn.input_error==0` 且 `observed_busy != final_busy`|`VLM_RESERVATION_OBSERVED_BUSY`|

`has_record` 是跨 bank_id 的 OR reduction，因此不同 bank_id 可以合法共享相同
direction、delay、gid 和 sub-bank busy bit。Checker 检查的是这个共享 bit 是否与所有 record 的归约
结果一致，不会因为共享本身报错。

### 8.5 Reservation 请求合法性

Checker 只处理 monitor 已经创建的完整已知 request handle：

|检查|失败条件|错误 ID|
|---|---|---|
|零 delay|`delay==0`；立即返回，不进入其他 reservation 检查|`VLM_RESERVATION_DLY_ZERO`|
|Delay 范围|`delay>=VTAB_D`；立即返回，避免数组越界|`VLM_RESERVATION_DLY_RANGE`|
|目标 busy|目标 `[delay][gid][sub_bank]` 的可靠 observed busy 或 scheduler-owned busy 任一个为 1|`VLM_RESERVATION_TARGET_BUSY`|
|Pending record 冲突|同一 direction/delay/bank 已有 record|`VLM_RESERVATION_PENDING_BANK_DUE_CONFLICT`|
|同周期 write-port 冲突|同一 BANK 的较早 write port 使用相同 delay|`VLM_RESERVATION_CURRENT_BANK_DUE_CONFLICT`|

目标 busy 使用 OR 条件：接口观察值和 scheduler authoritative ownership 任一视图已经
占用，当前 reservation 都不合法。只在两者同时为 1 时拒绝会漏掉单侧占用或状态视图
失配。其他 gid 的 external busy 不参与目标 busy 判断；其他 gid 若已有同 bank、方向和
due 的 DUT record，则由 pending conflict 拒绝。Pending conflict 检查历史 record，同周期 write-port conflict 检查当前
transaction 的两个物理 write port；read 和 write 方向使用不同数组，互不构成该类
BANK 冲突。

Checker 只报告错误并返回该 request 是否有效，不会接纳或删除 record。Scheduler 随后
使用自己的接纳逻辑更新状态，并保留 request 的完整地址低位。

### 8.6 到期 MEM 请求匹配

Checker/resolver 对每个 `<direction, bank>` 配对：

```text
txn.mem_[r/w]req_array[bank]
shm_records[direction][0][bank]
```

Direction 和 BANK 由数组位置构成匹配键。两边都为空表示本周期该位置空闲；其他组合和
检查如下：

|检查|失败条件|错误 ID|
|---|---|---|
|Unexpected MEM|有完整已知 MEM request，但没有到期 record|`VLM_RESERVATION_UNEXPECTED_MEM`|
|Missing MEM|有到期 record、没有 MEM request，且 `txn.input_error==0`|`VLM_RESERVATION_MISSING_MEM`|
|到期 slot 所有权|request 对应 sub-bank 没有 `shm_busy`，或仍有 `external_busy`|`VLM_RESERVATION_MEM_BUSY`|
|完整地址|`req.address != record.address`|`VLM_RESERVATION_MEM_ADDRESS`|
|绝对到期周期|`record.issue_cycle+record.issue_delay != txn.cycle`|`VLM_RESERVATION_MEM_DUE_CYCLE`|

Unexpected 和 missing 分支报告后立即返回；两边都存在时，其余三项可以在同一次调用中
分别报错。只有三项全部通过才增加 `matched_mem_request_count`。Read/write MEM 都不在
这里执行 alignment policy，但 reservation 与 MEM 地址始终逐 bit 比较，禁止清除低 5 bit
或只比较 beat 编号。

固定数组保证每个 direction/bank 每周期最多有一个 MEM request 和一个到期 record，
因此上述配对同时完成“一笔 request 对一笔 record”和“一笔 record 对一笔 request”的
结构性检查。

MEM 接口没有 gid。Resolver 先按 `<direction, bank, current cycle>` 取得上述唯一到期
record，再把 `record.gid` 写入 memory transaction，并保存 `gid_valid` 与
`reservation_matched`：

- 完全匹配时允许 transaction 更新 scoreboard/memory；
- 有唯一 record 但地址错误时可保留期望 gid 用于诊断，但不得更新可信 memory；
- 没有唯一 record 时 `gid_valid=0`，不得猜测 gid；
- read driver 必须复用同一解析结果，不得再次查找或消费 record。

### 8.7 `input_error` 的影响

`input_error` 是 monitor 在本周期发现任意 busy、request valid 或 active payload X/Z
后设置的单个全局 bit。Checker 不重复报告四态错误，并继续检查 scheduler 内部不变量
以及仍然完整已知的 request。

当前源码只在两处用它抑制可能由归一化造成的二次报错：

- 跳过全部 `observed_busy` 与 `final_busy` 比较；
- 到期 record 没有 MEM handle 时，不报告 `MISSING_MEM`。

因为该 bit 没有 bank、direction 或信号粒度，一个无关端口的 X/Z 会让同周期所有 busy
观察检查和 missing-MEM 检查一起失效。这个漏检风险记录为 `RSV-004`。

### 8.8 Checker 不负责的检查

- 接口 X/Z：由 reservation monitor 报告；
- `mem_rdata`、read response 延迟、`mem_wdata` 和 `mem_wstrb`：由 memory agent、
  memory model 和 scoreboard 负责；
- memory 内容以及 creq 到 MEM 的功能映射：由 reference 和 scoreboard 负责；
- MEM 数据内容和 byte strobe：由 memory model 和 scoreboard 检查。

## 9. Alignment 的职责边界

下游 SRAM 支持从任意 byte address 开始的 32-Byte read/write，稳定 spec 不要求
reservation 或 MEM beat base 对齐。Checker 和 scheduler 不执行 alignment policy，
也不按 direction、原始访问类型或 write port 拒绝低 5 bit 非零的请求。

完整地址低位仍属于 reservation/MEM 匹配键。旧的 port-based helper 以及
checker/scheduler 中的 alignment 判断已经删除，但完整地址兑现检查不能删除。

## 10. Coverage

`vlm_reservation_coverage.sample_cycle()` 在正确的 pre-update 位置消费 normalized
transaction、checker result 和只读 scheduler ownership。第一批 covergroup 已采样：

- reservation direction、bank、gid、subbank、delay 和 accepted/target-busy/
  pending-conflict/current-conflict outcome；
- candidate gid、other-gid external/SHM owner 和 admission outcome 的交叉；
- MEM direction、resolved gid、gid-valid、matched、unexpected、missing 和 address mismatch；
- 可供组件测试检查的 accepted、external block、dly-zero、matched MEM 等计数器。

这些 outcome 和 coverage 只提供 checker/assertion 证据与诊断，不参与 request admission、
scheduler 更新或 busy 输出。完整 reservation testpoint 和真实 RTL bin 命中证据仍由
`RSV-002` 跟踪；第一批暂不要求全项目 coverage merge 或总百分比阈值。

## 11. Reset 和错误边界

Monitor 已保证只在 reset 后检查 X/Z，但 scheduler record、external busy 和 checker
累计状态不会因运行中 reset 自动清空。若 reset 期间有在途 reservation，释放后旧 record
仍可能移动或到期，违反“取消所有在途事务”的 DUT 契约，见 `ENV-001`。

Reset 期间不创建 transaction 是正确的数据流边界，但还需要独立检查 DUT 的
reservation/MEM request 是否保持为 0，见 `RSV-005`。

常用错误族包括：

- `VLM_RESERVATION_*_XZ`：接口四态错误；
- `VLM_RESERVATION_*BUSY*`、`*_RECORD_*`：busy 所有权和窗口一致性；
- `VLM_RESERVATION_DLY_*`、`*_CONFLICT`、`*_TARGET_BUSY`：reservation 合法性；
- `VLM_RESERVATION_UNEXPECTED_MEM`、`MISSING_MEM`、`MEM_*`：到期 MEM 匹配。

## 12. 相关测试

`examples/vlm_reservation_compile/` 提供联合 elaboration、alignment、随机/定向 external
busy、`gid-contract` 和 `agent-metadata` 入口，`ut_shm/tests/shm_unit_test.svh` 则在完整环境中
使用该 agent。Alignment case 验证非对齐 read/write reservation 的地址保留和完整地址
兑现；external-busy 验证 plusarg/drive；directed-busy 验证 policy range、窗口前移、随机
优先级和已有 ownership 保护；gid-contract 使用严格 expected-report catcher 检查
target/other-gid external ownership、historical/current conflict、跨 BANK/方向合法对照，
以及 gid 0/1 match、unexpected、missing 和 address mismatch；agent-metadata 检查 policy
handle 传播和 unmatched MEM 的无效 gid/match metadata。2026-08-15 远端
`scripts/ubuntu/check_vlm_reservation_vcs.sh all` 全部通过。
这些组件结果不替代真实 RTL directed case 和功能覆盖闭环。

## 13. 调试观察点

- `current_txn.cycle`、`clk_vif.cycle_count` 和 scheduler `last_processed_cycle`；
- 目标 `[direction][delay][gid][sub_bank]` 的 observed/external/SHM/final busy；
- `shm_records[direction][delay][bank]` 的 issue cycle、delay、gid、address 和 due cycle；
- 同一 gid/sub-bank bit 下由哪些 bank record 做 OR；
- 到期 record 与 MEM request 的完整地址，以及 resolver 返回的 gid/match status；
- build log 中最终采用的 `EXTERNAL_BUSY_PERCENT`，以及是否配置 external busy policy。

## 14. 开发 contract

- Agent 始终按 monitor → checker/resolver → MEM publish/service → coverage → scheduler →
  drive 的顺序处理一拍。
- Reset 期间不做 X/Z 检查；运行中 reset 必须另外清空 scheduler 和在途状态。
- `external_busy` 和 `shm_busy` 不能同时拥有同一 slot，`final_busy` 只能是两者 OR。
- Reservation 与实际 MEM 地址必须完全相等，不能通过清除低位后比较来接受错误地址。
- Busy ownership 使用 `[direction][delay][gid][sub_bank]`，MEM port ownership 继续使用
  `[direction][delay][bank]`；二者不能合并成一张表。
- MEM gid 只能来自唯一到期 record；monitor 不直接访问 scheduler 私有数组，driver 不得
  独立重复解析。
- Reservation agent 不执行 alignment policy，也不得按物理 write port 推断来源。
- 当前只支持 active；任何 passive knob 都不能产生看似可用的半功能 agent。

## 15. 当前实现状态

- `RSV-002`：第一批 ownership/admission/MEM-match coverage 已实现，完整 testpoint 和
  真实 RTL bin 命中证据仍缺。
- `RSV-003`：external-busy 示例已验证 config 默认值、plusarg 覆盖为 100 和 busy drive，
  远端 VCS 报告 0 error、0 fatal，2026-08-13 关闭。
- `RSV-004`：全局 `input_error` 会屏蔽无关 slot 的检查。
- `RSV-005`：复位期间没有检查 DUT request/valid 必须为 0。
- `ENV-001`：运行中 reset 未清理 scheduler record 和 busy 状态。
- gid busy、record gid、resolver 和统一 interface/agent 已接入，并于 2026-08-13 随真实
  RTL 集成 testcase 跑通；2026-08-15 已补齐 P0-1 ownership/resolver/agent metadata 组件
  场景，并增加 P0-2 deterministic external busy policy。完整组合 coverage 和真实 RTL
  directed case 仍按
  [SHM 定向验证开发计划](../../../development/shm-directed-verification-development-plan.md)
  继续实施。

问题详情和验收方法见[验证实现状态](../../verification-status.md)。
