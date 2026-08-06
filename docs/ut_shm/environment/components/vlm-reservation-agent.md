# vlm_reservation_agent

本文说明 VLM reservation agent 如何按周期联合采样 reservation 和 MEM 请求，检查 busy
与到期匹配，并生成下一周期 busy。协议规则见
[MEM/VLM 接口规范](../../spec/mem-vlm-interface.md)；本文区分稳定检查职责和当前尚未
修复的实现差异。

## 1. 组件结构和支持模式

```text
vlm_reservation_agent
├── vlm_reservation_monitor
├── vlm_reservation_checker
├── vlm_reservation_coverage
└── vlm_reservation_scheduler
```

Agent 必须同时取得 `vlm_reservation_interface`、只读的 `vlm_memory_interface` 和共享
`clk_if`。当前固定创建完整层次并主动驱动 busy；passive 模式明确不支持。

## 2. 主要源文件

|文件|作用|
|---|---|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_interface.sv`|reservation request 与 busy clocking block|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_types.svh`|request、record、cycle transaction 和 result 类型|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_agent.svh`|层次、配置、单周期调度和 busy 驱动|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_monitor.svh`|四态采样和归一化|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_checker.svh`|busy、reservation 与 MEM 到期匹配|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_scheduler.svh`|窗口、record、external/SHM/final busy|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_coverage.svh`|coverage 同步入口，当前为空实现|

## 3. 单周期处理顺序

Agent 的 `main_phase` 是唯一消耗周期的核心循环。每次迭代按以下顺序执行：

```text
monitor.collect_cycle()
        ↓
checker.check_cycle()       读取 scheduler 的 pre-update 状态
        ↓
coverage.sample_cycle()     读取同一个 pre-update 状态
        ↓
scheduler.process_cycle()   窗口推进、接纳请求、生成 external busy
        ↓
agent.drive_busy()          驱动下一接口周期
```

Checker 和 coverage 必须在 scheduler 更新前运行，否则采样到的 busy、record 和
transaction cycle 不再属于同一状态。

## 4. Cycle transaction

Monitor 把同一采样沿的接口值归一化到
`vlm_reservation_cycle_transaction_t`，其中包括：

- read/write busy window；
- 每个 bank 的一条 read reservation；
- 每个 bank、每个 write port 的 write reservation；
- 每个 bank 的实际 MEM read/write valid 和完整地址；
- 共享 `clk_if.cycle_count` 与 `input_error`。

有效 reservation 由地址和相对 delay 组成；实际 MEM request 只表示本周期已经出现在
MEM 端口的请求。Scheduler record 保存 direction、source port、issue cycle/delay 和
完整地址，用于到期周期的一对一匹配。

## 5. Monitor 的四态边界

`collect_cycle()` 每次都先等待采样到 `rst_n===1`。因此 reset 未释放或运行中 reset
期间不执行 busy/request 的 X/Z 检查，也不生成 cycle transaction；复位前 1 ns 的未知
busy 不会再触发 `VLM_RESERVATION_BUSY_XZ`。

Reset 释放后，monitor 对 busy、reservation valid/address/delay 和 MEM valid/address
执行四态检查。X/Z 会被报告，并在 two-state transaction 中归一化为 inactive/0，且
设置 `input_error`，防止 checker 把不可靠的 observed busy 再报成普通 mismatch。

Monitor 只负责采样与归一化，不判断 reservation 是否能接纳，也不匹配 MEM 数据。

## 6. Scheduler 状态

Scheduler 分离保存三组状态：

- `external_busy[direction][delay][sub_bank]`：环境注入的外部占用；
- `shm_records[direction][delay][bank]`：已经接纳、尚未到期的 DUT reservation；
- `shm_busy`：按 record 地址的 `address[6:5]` 对所有 bank 做 OR reduction；
- `final_busy = external_busy | shm_busy`。

不同 bank 的 record 可以映射到同一个 sub-bank busy bit；同一个 direction/delay/bank
只能有一条到期记录，因为实际 MEM 端口每个 bank、每个方向只有一个 request slot。
Write 的两个 reservation port 若在同一 bank 同一周期选择相同 delay，也会竞争同一个
到期 slot。

每周期 scheduler 先推进窗口和清理已到期记录，再重建 busy、接纳当前合法 request，
最后在仍空闲的每个 slot 上独立随机生成 external busy。

## 7. External busy 配置

默认概率来自 config 的大写字段 `EXTERNAL_BUSY_PERCENT`，命令行
`+EXTERNAL_BUSY_PERCENT=<0..100>` 可以覆盖。Agent 在 build phase 校验范围，并把最终
值传给 scheduler 的内部字段 `external_busy_percent`。

随机 busy 只会填充本周期处理后仍无 SHM 所有权的 slot。配置为 0 时不会随机拉起；
配置非零仍属于概率行为，波形上不保证某个指定 slot 或某个短窗口必然为 1。

## 8. Checker 职责

Checker 使用 scheduler 的 pre-update 状态检查四类关系：

1. transaction cycle 与共享 `clk_if`、scheduler 前一周期连续；
2. `shm_records`、`shm_busy`、`external_busy`、`final_busy` 和接口 observed busy 一致；
3. reservation delay、目标 busy、同 bank 到期冲突等接纳条件合法；
4. delay 归零的 record 与同 bank、同方向实际 MEM request 一对一对应，完整地址相等。

目标 slot 在 observed busy 或 scheduler authoritative ownership 任一视图中被占用时，
当前 reservation 都不能合法接纳。使用 OR 是为了同时捕获接口侧占用和环境内部所有权
不一致的情况；若只在两者同时为 1 时拦截，会漏掉单侧已经 busy 的非法请求。

实际 MEM request 没有到期 record 时属于 unreserved access；有到期 record 但没有
MEM request 时属于 missing request。Read MEM beat 仍需 32-byte 对齐，reservation
地址与实际 MEM 地址必须逐 bit 完全相等。

## 9. Write alignment 的职责边界

稳定 spec 不能按 reservation write port 推断 write 来源：

- 普通 V2M m-write 要求对齐；
- M2V v-write 允许非对齐；
- VTRANS write 允许非对齐。

Reservation transaction 不携带足够的原始指令类型，因此 checker 不应做 port-based
write alignment；该检查应在能关联 creq 来源的 scoreboard 完成。当前 types helper、
checker、scheduler 仍把 write port 1 视为对齐、port 0 视为可非对齐，是已知问题
`RSV-001`。完整地址兑现检查不能随之删除。

## 10. Coverage

`vlm_reservation_coverage.sample_cycle()` 已接入正确的 pre-update 采样位置，但当前没有
covergroup，预留计数器也保持为 0。它不能作为 reservation 场景已经覆盖的证据，见
`RSV-002`。

后续 coverage 应观察 reservation direction/delay、external/SHM busy 来源、跨 bank
共享 sub-bank、同 bank 冲突、到期匹配和输入错误，但不得修改 scheduler 或 checker
状态。

## 11. Reset 和错误边界

Monitor 已保证只在 reset 后检查 X/Z，但 scheduler record、external busy 和 checker
累计状态不会因运行中 reset 自动清空。若 reset 期间有在途 reservation，释放后旧 record
仍可能移动或到期，违反“取消所有在途事务”的 DUT 契约，见 `ENV-001`。

常用错误族包括：

- `VLM_RESERVATION_*_XZ`：接口四态错误；
- `VLM_RESERVATION_*BUSY*`、`*_RECORD_*`：busy 所有权和窗口一致性；
- `VLM_RESERVATION_DLY_*`、`*_CONFLICT`、`*_TARGET_BUSY`：reservation 合法性；
- `VLM_RESERVATION_UNEXPECTED_MEM`、`MISSING_MEM`、`MEM_*`：到期 MEM 匹配。

## 12. 相关测试

`examples/vlm_reservation_compile/` 提供联合 elaboration、alignment 和 external busy
定向入口，`ut_shm/tests/shm_unit_test.svh` 则在完整环境中使用该 agent。当前两个 example
case 仍编码旧的 write-port alignment 规则或失效字段名，不能作为新 spec 的通过证据，
见 `RSV-003`。Coverage 为空也意味着集成 smoke 不能替代功能覆盖闭环。

## 13. 调试观察点

- `current_txn.cycle`、`clk_vif.cycle_count` 和 scheduler `last_processed_cycle`；
- 目标 `[direction][delay][sub_bank]` 的 observed/external/SHM/final busy；
- `shm_records[direction][delay][bank]` 的 issue cycle、delay、address 和 due cycle；
- 同一 sub-bank bit 下由哪些 bank record 做 OR；
- 到期 record 与 MEM request 的完整地址；
- build log 中最终采用的 `EXTERNAL_BUSY_PERCENT`。

## 14. 开发 contract

- Agent 始终按 monitor → checker → coverage → scheduler → drive 的顺序处理一拍。
- Reset 期间不做 X/Z 检查；运行中 reset 必须另外清空 scheduler 和在途状态。
- `external_busy` 和 `shm_busy` 不能同时拥有同一 slot，`final_busy` 只能是两者 OR。
- Reservation 与实际 MEM 地址必须完全相等，不能通过清除低位后比较来接受错误地址。
- Write alignment 由原始指令来源决定，不得再按物理 write port 推断。
- 当前只支持 active；任何 passive knob 都不能产生看似可用的半功能 agent。

## 15. 当前实现状态

- `RSV-001`：仍按 write port 检查 alignment。
- `RSV-002`：coverage 是空实现。
- `RSV-003`：alignment 和 external-busy 示例与当前实现不一致。
- `ENV-001`：运行中 reset 未清理 scheduler record 和 busy 状态。

问题详情和验收方法见[验证实现状态](../../verification-status.md)。
