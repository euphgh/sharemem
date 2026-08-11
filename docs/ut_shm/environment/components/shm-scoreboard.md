# shm_scoreboard

本文说明 scoreboard 如何接收顺序 reference、容纳 DUT 合法乱序写入，并在测试结束时
检查最终 memory 状态。它采用当前的 outstanding 新算法；旧文档中的逐 transaction
严格顺序匹配不再代表实现。

## 1. 端口和内部状态

|对象|来源或去向|用途|
|---|---|---|
|`ref_wrvlm_analysis_export`|`shm_reference.wdata_ass_arr_port`|接收每笔 creq 的期望 byte map|
|`rtl_wrvlm_analysis_export`|统一 VLM monitor write port|接收已补全 gid/match status 的 DUT 实际 MEM write|
|`mem_imp`|memory slave driver|为 MEM read response 提供 blocking transport|
|`ref_wrvlm_analysis_fifo`|reference export 后端|解耦期望收集|
|`rtl_wrvlm_analysis_fifo`|actual export 后端|解耦实际写比较|
|`rtl_banks[BANK_N][GID_N]`|scoreboard 所有|保存 DUT 已兑现 write 的实际 memory model|

核心匹配状态为：

- `wmap_final`：每个地址按 creq 顺序计算出的最新未兑现值；
- `wmap_expired`：被后续 creq 覆盖、但 DUT 乱序执行时仍可合法出现的旧值队列；
- `ref_record_q`：每笔 creq 的原始 `wmap`，以及逐地址 `matched/expired` 时间。

## 2. 三条并行主路径

`main_phase` 启动三个常驻任务：

```text
collect_ref()            建立/覆盖期望
compare_dut_with_ref()   更新实际 memory 并匹配实际写
scan_timeout_creq()      输出完成或超时诊断
```

三个任务共享上述 associative array 和 record queue。调试时应把 reference 到达、实际
write 到达和 timeout 扫描视为同一状态机的三个入口。

## 3. 收集 reference 与过期值

`collect_ref()` 每收到一笔 `shm_wtrans_item` 就调用 `compare_with_old_trans()`：

1. 计算新 `wmap` 与现有 `wmap_final` 的地址交集；
2. 把交集中的旧值加入 `wmap_expired`；
3. 用新 `wmap` 覆盖 `wmap_final`；
4. 在所有旧 `ref_record` 中，把重叠地址记为在新事务 `issue_time` 过期；
5. 将新事务加入 `ref_record_q`。

这里的“expired”表示旧期望已经被后续 creq 覆盖，不表示 DUT 错误，也不同于 timeout。

## 4. 实际 write 比对

`compare_dut_with_ref()` 只接纳已经匹配唯一到期 reservation 的 MEM transaction。它先按
`<bank_id,gid>` 和 byte strobe 更新 `rtl_banks`，再把实际 MEM write 转成 byte map。
每个实际写 byte 必须满足：

- 地址存在于 `wmap_final` 或 `wmap_expired`；
- 数据等于该地址的最新最终值，或等于仍未消费的合法旧值。

命中最终值时从 `wmap_final` 删除；命中过期旧值时只消费对应旧值。整笔实际 write
合法后，再给所有相关 `ref_record` 写入 matched 时间。

这允许 DUT 把地址重叠的 creq 乱序兑现，但不会改变顺序语义：测试结束时
`wmap_final` 必须为空，所以每个地址最终仍需出现按 creq 顺序计算出的最后值。若最终
结果与顺序执行不一致，即使中间写入曾匹配某个旧值，也属于 DUT 错误。

## 5. Record 完成与 timeout 日志

一笔 `ref_record` 的所有原始地址只要分别进入 `matched` 或 `expired` 集合，就视为该
record 已被后续状态解释完毕。扫描任务每 10 个 `CLK_PERIOD` 检查一次：

- 已完成：保留原有 “all data is matched or expired” info，并打印 transaction、
  expired table 和 matched table；
- 超过固定 128 cycles 且未完成：保留原有 expired 报错，同时打印 expired、matched
  和没有进入两者的 unmatched table。

协议本身没有最大完成延迟。128-cycle 只是当前环境策略，可能误报合法长延迟，见
`SCB-002`。

## 6. MEM read service

`b_transport()` 对 transaction 中每个 active bank，要求 `gid_valid` 和
`reservation_matched`，再从 `rtl_banks[bank][gid]` 的起始地址连续读取一个 MEM beat，
并把结果写回 transaction。Memory driver 随后按 `RPORT_DLY` 驱动
接口。

当前读取发生在 T0 调用 transport 时，只包含当时已经进入 `rtl_banks` 的 write，尚未
实现 `FFD_CYC` 截止窗口。该问题归入 memory model 的 `VMEM-001`。

## 7. `check_phase`

测试结束时 scoreboard 检查：

- actual write FIFO 为空；
- reference FIFO 为空；
- `wmap_final` 中没有仍未兑现的最终 byte。

`wmap_expired` 不要求为空，因为被覆盖的旧值允许从未实际出现。`ref_record_q` 的中间
诊断状态也不能替代 `wmap_final` 的最终一致性检查。

## 8. MEM beat 地址检查边界

下游 SRAM 支持从任意 byte address 开始的 32-Byte read/write，scoreboard 不按原始
creq 类型检查 MEM beat base alignment，也不需要为此把一笔实际 write 唯一归属于某个
`shm_wtrans_item`。

Write checker 继续把实际 strobe 展开成逐 byte `<bank_id, gid, BADDR, data>`，并要求每个有效
byte 命中 `wmap_final` 或仍合法的 `wmap_expired`。因此普通 V2M 的验收条件是最终写数据
和 byte 地址正确，而不是 DUT 选择某个特定的 32-Byte beat base。Reservation checker
独立负责 busy/时序以及 reservation 与 MEM 完整地址相等。

## 9. 调试观察点

- 新 reference 到达前后的 `wmap_final/wmap_expired`；
- 每个 `ref_record` 的 `issue_time`、matched、expired 和 unmatched table；
- 实际 MEM write 转换后的 byte map 与 bank strobe；
- MEM transaction 的 gid、gid_valid、reservation match status 及对应到期 record；
- 命中 final 还是 expired，以及相应条目是否只被消费一次；
- `rtl_banks` 的更新发生在 read snapshot 截止周期之前还是之后；
- `check_phase` 剩余的最终地址和值。

## 10. 主要源文件和测试

|文件|作用|
|---|---|
|`ut_shm/env/shm_scoreboard.svh`|期望/实际 FIFO、outstanding 算法、read service 和结束检查|
|`ut_shm/env/shm_wtrans_item.svh`|保留原始 creq 上下文的期望 byte map|
|`ut_shm/env/vlm2aa.svh`|实际 MEM transaction 到 byte map 的转换|
|`ut_shm/util/sv-collection/`|set、associative array 和 queue 的集合运算工具|

`ut_shm/tests/shm_unit_test.svh` 提供完整数据路径 smoke。当前没有针对交叠 creq 乱序
兑现、只出现旧值而没有最终值、未知实际地址或 timeout 配置的
独立 scoreboard 测试；新增算法时应先用小规模 byte map 定向场景固定这些边界。

## 11. 开发 contract

- DUT 可以乱序调度，但 scoreboard 的最终判定必须等价于 creq 顺序执行。
- `expired` 只能表示被后续 creq 覆盖的旧值，不能用来吞掉未知地址或错误数据。
- 新日志必须保留现有 completed/expired 消息，并补充定位信息，不能让回归工具失去
  原有关键字。
- Timeout 是可配置诊断策略，不得被解释成 DUT 最大延迟协议。
- Read model、reference model 和 actual model 必须保持独立所有权。
- 只有唯一 reservation 匹配成功的 MEM request 才能更新 `rtl_banks`；无 gid 或地址/到期
  不匹配的事件只报告协议错误，不能污染可信数据状态。
- 所有 address set、wmap 和 outstanding key 必须包含 gid。
- Runtime reset 必须原子地清理 FIFO、outstanding map、record queue 和 pending read。

## 12. 当前实现状态

- `SCB-002`：timeout 固定为 128 cycles。
- `VMEM-001`：read service 未实现 `FFD_CYC` snapshot。
- `ENV-001`：运行中 reset 未清理 outstanding 和实际 memory 状态。
- 当前 scoreboard memory 和 wmap 仍缺少 gid 维度，待按双 gid 开发计划迁移。

问题详情和验收方法见[验证实现状态](../../verification-status.md)。
