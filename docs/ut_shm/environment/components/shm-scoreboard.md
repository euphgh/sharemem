# shm_scoreboard

本文说明 scoreboard 如何接收顺序 reference、容纳 DUT 合法乱序写入，并在测试结束时
检查最终 memory 状态。它采用当前的 outstanding 新算法；旧文档中的逐 transaction
严格顺序匹配不再代表实现。

## 1. 端口和内部状态

|对象|来源或去向|用途|
|---|---|---|
|`ref_wrvlm_analysis_export`|`shm_reference.wdata_ass_arr_port`|接收每笔 creq 的期望 byte map|
|`rtl_wrvlm_analysis_export`|统一 VLM monitor write port|接收已补全 gid/match status 的 DUT 实际 MEM write|
|`mem_imp`|统一 VLM agent|同步提交实际 MEM write，并为 MEM read snapshot 提供 blocking transport|
|`ref_wrvlm_analysis_fifo`|reference export 后端|解耦期望收集|
|`rtl_wrvlm_analysis_fifo`|actual export 后端|解耦实际写比较|
|`completion_analysis_port`|transaction lifecycle checker|发布每笔 reference 的 data completion 分类和 cycle|
|`rtl_banks[BANK_N][GID_N]`|scoreboard 所有|保存 DUT 已兑现 write 的实际 memory model|
|`touched_waddrs`|reference byte map|保存本 epoch 被 reference 写过的物理 byte key，不复制 expected data|

核心匹配状态为：

- `wmap_final`：每个地址按 creq 顺序计算出的最新未兑现值；
- `wmap_expired`：被后续 creq 覆盖、但 DUT 乱序执行时仍可合法出现的旧值队列；
- `ref_record_q`：每笔 creq 的原始 `wmap`，以及逐地址 `matched/expired` cycle。

`wmap/wmmap` 的底层 collection 仍使用
`physical_bank_index=bank_id*GID_N+gid` 的一维索引，以保持集合运算接口不变。日志通过
`shm_physical_map_util` 恢复为稀疏的 `BANK → GID → BADDR` 层次，只显示非空 group，
并在表头给出 group 和地址条目数量。单地址 mismatch 也使用显式 BANK/GID/BADDR，
不再暴露容易误读的 flattened index。

## 2. 三条并行主路径

`main_phase` 启动三个常驻任务：

```text
collect_ref()            建立/覆盖期望
compare_dut_with_ref()   匹配已经同步提交的实际写
scan_timeout_creq()      输出完成或超时诊断
```

三个任务共享上述 associative array 和 record queue。调试时应把 reference 到达、实际
write 到达和 timeout 扫描视为同一状态机的三个入口。

## 3. 收集 reference 与过期值

`collect_ref()` 每收到一笔 `shm_wtrans_item` 就调用 `compare_with_old_trans()`：

1. 计算新 `wmap` 与现有 `wmap_final` 的地址交集；
2. 把交集中的旧值加入 `wmap_expired`；
3. 用新 `wmap` 覆盖 `wmap_final`；
4. 在所有旧 `ref_record` 中，把重叠地址记为在新事务 `issue_cycle` 过期；
5. 将新事务加入 `ref_record_q`。

这里的“expired”表示旧期望已经被后续 creq 覆盖，不表示 DUT 错误，也不同于 timeout。

## 4. 实际 write 比对

统一 VLM agent 在请求周期先通过 `b_transport()` 按 `<bank_id,gid>` 和 byte strobe 同步更新
`rtl_banks`，再通过 analysis port 发布同一实际 MEM write。`compare_dut_with_ref()` 只负责
接纳已经匹配唯一到期 reservation 的 transaction，并把它转成 byte map；它不再重复更新
memory。
每个实际写 byte 必须满足：

- 地址存在于 `wmap_final` 或 `wmap_expired`；
- 数据等于该地址的最新最终值，或等于仍未消费的合法旧值。

命中最终值时从 `wmap_final` 删除；命中过期旧值时只消费对应旧值。整笔实际 write
合法后，再给所有相关 `ref_record` 写入 `clk_if.cycle_count`。

这允许 DUT 把地址重叠的 creq 乱序兑现，但不会改变顺序语义：测试结束时
`wmap_final` 必须为空，所以每个地址最终仍需出现按 creq 顺序计算出的最后值。若最终
结果与顺序执行不一致，即使中间写入曾匹配某个旧值，也属于 DUT 错误。

## 5. Record 完成、生命周期事件与 timeout

一笔 `ref_record` 的所有原始地址只要分别进入 `matched` 或 `expired` 集合，就视为该
record 已被后续状态解释完毕。Scoreboard 使用共享 `clk_if.cycle_count`，不再用绝对
simulation time 推导 cycle。每个 record 只发布一次 completion event：

- `SHM_COMPLETION_OBSERVED`：非空期望 map 的全部 byte 都由实际 DUT write 匹配；
- `SHM_COMPLETION_RESOLVED`：全部 byte 已解释完，但至少包含被后续 creq 覆盖的 byte，
  或该事务本来没有期望 byte。

扫描间隔由 `SCB_TIMEOUT_SCAN_INTERVAL_CYCLES` 配置。两类可选诊断彼此独立：

- `SCB_NO_PROGRESS_TIMEOUT_CYCLES`：存在 pending record，且 reference 到达、byte
  supersession 或实际 write match 均没有进展的 cycle 数；
- `SCB_RECORD_AGE_TIMEOUT_CYCLES`：单笔 record 从 creq accepted cycle 起的总年龄。

两者默认均为 0，即关闭中途 timeout，只保留 drain/check phase 的最终一致性检查。即使
打开并触发，scoreboard 也只报告一次，不删除 record、不把 unmatched byte 改成 expired，
后续正确结果仍可继续匹配。它们是 case 可调的 hang 诊断，不是 DUT 最大延迟协议。

完成 UVM info、`SHM_SCB_RECORD_AGE_TIMEOUT` 和 `SHM_SCB_NO_PROGRESS_TIMEOUT` 使用相同
的首行格式，打印 transaction UID、creq ID、方向、issue cycle、年龄，以及
expected/matched/expired/unresolved byte 数。两个 timeout 紧接着按 BANK/GID/BADDR/data
展开该 record 的全部 unresolved byte；drain 诊断的 `pending_state_sprint()` 还会继续打印
`wmap_final`。

## 6. MEM read service

`b_transport()` 根据 transaction 方向分派：write 要求 `gid_valid` 和
`reservation_matched`，并按有效 strobe 同步更新 `rtl_banks`；read 从对应
`rtl_banks[bank][gid]` 连续读取一个 MEM beat，并把 snapshot 写回 transaction。

`FFD_CYC` 的等待与截止周期编排由统一 VLM agent 负责。Agent 只在
`T0+FFD_CYC-1` 周期 write 已提交后调用 read transport，并在 `T0+RPORT_DLY` 返回数据。
当前支持 `FFD_CYC>=1`；`FFD_CYC=0` 仍归入 `VMEM-001`。

## 7. 最终 memory 比较与 `check_phase`

测试结束时 scoreboard 检查：

- actual write FIFO 为空；
- reference FIFO 为空；
- `wmap_final` 中没有仍未兑现的最终 byte。

`wmap_expired` 不要求为空，因为被覆盖的旧值允许从未实际出现。`ref_record_q` 的中间
诊断状态也不能替代 `wmap_final` 的最终一致性检查。

环境在稳定 idle 后调用 `shm_scoreboard.compare_final_memory()`，逐项遍历
`touched_waddrs` 并直接比较 reference 所有的 `ref_banks` 与 scoreboard 所有的
`rtl_banks`。该集合只保存 `<bank,gid,BADDR>`，expected byte 始终在比较时从
`ref_banks` 读取，因此没有建立第三份 expected memory。Mismatch 逐 byte 打印 BANK、
GID、BADDR、reference 和 actual。

`shm_environment.check_phase()` 总会执行一次该比较；定向 test 也可在
`wait_for_idle()` 后调用 `check_final_memory()` 提前得到同一诊断。若 environment 尚未
idle，显式入口先打印 pending state，不把瞬态内容误判为最终 memory。当前比较范围是
本仿真 epoch 中 reference 实际触及的 byte，未触及且保持初始化值的地址不遍历。

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
- 每个 `ref_record` 的 `issue_cycle`、matched、expired 和 unmatched table；
- timeout 摘要中的 UID、creq ID、方向、byte 计数和 unresolved byte 地址表；
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
|`ut_shm/env/shm_transaction_lifecycle_types.svh`|scoreboard completion 和 raw ack event 类型|
|`ut_shm/env/shm_transaction_lifecycle_checker.svh`|把 completion 与 creq/ack 生命周期关联|
|`ut_shm/env/vlm2aa.svh`|实际 MEM transaction 到 byte map 的转换|
|`ut_shm/env/shm_physical_map_util.svh`|把 flattened wmap/wmmap 格式化为 BANK/GID/BADDR 层次|
|`ut_shm/util/sv-collection/`|set、associative array 和 queue 的集合运算工具|
|`examples/shm_reference_compile/final_memory_compare_tb.sv`|最终 memory 正反例组件矩阵|

`ut_shm/tests/shm_unit_test.svh` 提供完整数据路径集成测试。最终 memory compare 已由
`ORDER-SCB-001`～`005` 固定单/多 byte、反序最终值和双 gid 边界；交叠 creq 的正式
RTL 顺序结果由独立 `shm_ordered_access.lst` 验证。未知实际地址、completion 分类和
timeout 配置仍缺独立 scoreboard 测试。

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

- `SCB-002`：固定 128-cycle timeout 已移除并改为可关闭的 no-progress/record-age
  plusarg；2026-08-14 空 design VCS 编译通过，仍待长延迟和 timeout 触发定向验证。
- `VMEM-001`：`FFD_CYC>=1` snapshot 已实现并通过组件测试，`FFD_CYC=0` 尚未支持。
- `ENV-001`：运行中 reset 未清理 outstanding 和实际 memory 状态。
- scoreboard memory、wmap 和 read service 已接入 reservation match metadata，并通过
  当前真实 design 的 109-case `shm.lst` 回归；仍缺 gid 数据隔离和 mismatch
  失败路径定向证据。

问题详情和验收方法见[验证实现状态](../../verification-status.md)。
