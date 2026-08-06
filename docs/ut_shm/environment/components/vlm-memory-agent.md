# vlm_memory_slv_agent

本文说明 VLM memory slave agent 如何观察 MEM 请求、维护实际 memory model，并按固定
延迟返回读数据。端口采样和 `FFD_CYC` 的协议含义见
[MEM/VLM 接口规范](../../spec/mem-vlm-interface.md)；本文只描述当前验证组件的数据流。

## 1. 组件结构

```text
vlm_memory_slv_agent
├── vlm_memory_monitor
├── vlm_memory_slv_driver     active 模式
└── vlm_memory_slv_sequencer  active 模式
```

Agent 从 Config DB 获取 `vlm_memory_slv_agent_config` 和 `memory_vif`。Monitor 始终创建；
active 模式下再创建 driver 和 sequencer，并连接 `seq_item_port`。ut_shm 当前只支持完整
active 环境，sequencer 虽然存在，但不参与读响应的数据来源。

## 2. 主要源文件

|文件|作用|
|---|---|
|`ver_common/uvc/vlm_memory_agent/vlm_memory_interface.sv`|MEM read/write 请求和 read data clocking block|
|`ver_common/uvc/vlm_memory_agent/vlm_memory_sequence_item.svh`|按 bank 保存 enable、地址、数据和 strobe|
|`ver_common/uvc/vlm_memory_agent/vlm_memory_slv_agent_config.svh`|agent active/passive 配置|
|`ver_common/uvc/vlm_memory_agent/vlm_memory_slv_agent.svh`|组件创建、vif 分配和连接|
|`ver_common/uvc/vlm_memory_agent/vlm_memory_slv_driver.svh`|read request 到 read response 的转换|
|`ver_common/uvc/vlm_memory_agent/vlm_memory_monitor.svh`|MEM read/write transaction 采集|

## 3. Transaction

`vlm_memory_sequence_item` 用 `vlm_read` 区分读写，并为每个 bank 保存：

- `vlm_bken`：该 bank 是否参与本笔 transaction；
- `vlm_addr`：MEM beat 的起始 BADDR；
- `vlm_data`：一个完整 MEM beat 的数据；
- `vlm_strb`：逐 byte 写使能，读 transaction 中填为全 1。

它表达的是已经出现在 MEM 端口上的 transaction，不携带原始 creq 指令类型。因此，
普通 V2M、M2V v-write 和 VTRANS 的来源相关 write alignment 不能只靠这个对象判断。

## 4. Read response 路径

Driver 在 `main_phase` 先把 `rdata` 清零，等待初始 `rst_n===1`，随后逐拍观察 `rvld`。
每次看到至少一个 bank 发出 read：

1. 创建 read transaction，复制所有 bank 的 `rvld/raddr`；
2. 立即通过 `mem_port.b_transport()` 向 scoreboard 查询数据；
3. 独立 fork 等待 `RPORT_DLY-1` 个后续 driver clocking event；
4. 把 transaction 中的数据驱动到所有 bank 的 `rdata`。

每笔 read 使用独立 process，因此可以流水重叠。当前 transport 在 T0 就读取 memory
snapshot，尚未实现截止到 `T0+FFD_CYC-1` 的写可见窗口，见 `VMEM-001`。

## 5. Monitor 路径

Monitor 在初始 reset 释放后并行采集 read 和 write：

- read：在 `rvld` 有效时保存 enable 和地址，等待 `RPORT_DLY` 个 monitor clocking
  event 后采样 `rdata`，再从 `read_analysis_port` 发布完整 transaction；
- write：在 `wvld` 有效的同一采样沿保存地址、strobe 和数据，从
  `write_analysis_port` 立即发布。

当前 `shm_environment` 只把 write port 连接到 scoreboard。Read monitor port 可用于协议
调试，但没有进入数据正确性比对主路径；read data 实际由 driver 与 scoreboard 的
blocking transport 生成。

## 6. 实际 memory model 的所有权

Driver 和 monitor 都不直接保存 memory。`shm_scoreboard.rtl_banks` 是实际 memory model：

- monitor 发布的实际 write 先按 strobe 更新 `rtl_banks`；
- driver 的 blocking transport 从 `rtl_banks` 取得 read response；
- reference 使用另一组 `ref_banks`，不能与 `rtl_banks` 共享对象。

这条所有权边界保证 read response 来自 DUT 已经兑现的 write，而不是直接来自期望值。

## 7. X/Z、reset 和错误边界

Driver/monitor 未取得 vif 时报告 `VLM_MEMORY_NO_VIF` fatal。Monitor 目前没有对 valid、
地址、strobe 和有效 data byte 做完整四态检查，见 `VMEM-002`。

Driver 和 monitor 都只等待一次初始 reset。运行中 reset 不会自动取消已经 fork 的 read、
重新清零输出或重建 memory 状态，属于跨组件问题 `ENV-001`。

## 8. 调试观察点

- `read_transaction_count`、`write_transaction_count` 和总 `transaction_count`；
- T0 采样的 `rvld/raddr` 与 `RPORT_DLY` 后的 `rdata`；
- write transaction 的 bank enable、byte strobe 与 `rtl_banks` 更新；
- driver `mem_port` 是否连接到 scoreboard `mem_imp`；
- `+file_debug` 生成的 `vlm_memory.rtl` transaction 记录。

## 9. 相关测试

`ut_shm/tests/shm_unit_test.svh` 间接覆盖 memory monitor、read service 和 scoreboard
连接。`examples/vlm_reservation_compile/tb.sv` 可用于 reservation 与 memory agent 的
联合 elaboration。当前没有覆盖 `FFD_CYC` 边界、MEM X/Z、流水 read 或运行中 reset
取消 response 的独立定向测试。

## 10. 开发 contract

- MEM read 的采样点是 `rvld/raddr` 在 T0 的接口采样，不是更早的 reservation。
- Read response 必须在 `RPORT_DLY` 语义下实现 `FFD_CYC` snapshot；截止周期之后的 write
  不能进入这笔返回值。
- Monitor 只能发布实际接口行为，不能用 reference 修补 transaction。
- 运行中 reset 必须取消 pending response，并阻止 reset 前 transaction 在释放后兑现。
- 现阶段 passive 明确不支持；不能留下 driver 缺失但 scoreboard 仍假定 transport
  存在的半连接组合。

## 11. 当前实现状态

- `VMEM-001`：read snapshot 未实现 `FFD_CYC`。
- `VMEM-002`：MEM transaction 缺少完整 X/Z 检查。
- `VMEM-003`：sequencer 和部分 compare API 没有有效行为。
- `ENV-001`：运行中 reset 未清理 pending read 和 memory 状态。
- `ENV-002`：passive 配置仍可能形成不完整连接。

问题详情和验收方法见[验证实现状态](../../verification-status.md)。
