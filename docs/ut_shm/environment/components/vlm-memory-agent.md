# 统一 VLM agent 的 MEM 路径

本文说明统一 `vlm_agent` 中的 MEM transaction、gid 解析和 read response。接口协议见
[MEM/VLM 接口规范](../../spec/mem-vlm-interface.md)，reservation 窗口见
[统一 VLM agent 的 reservation 路径](vlm-reservation-agent.md)。

## 1. 当前结构

主环境不再实例化独立 `vlm_memory_slv_agent`。统一 monitor 在同一个采样沿收集
reservation、busy 和 MEM 请求；checker 使用 scheduler 的 pre-update 到期 record 为每个
MEM bank 产生以下 metadata：

- `vlm_gid`：唯一到期 reservation 携带的 gid；
- `gid_valid`：gid 是否来自有效解析；
- `reservation_matched`：direction、bank、到期周期和完整地址是否全部匹配。

Agent 在 scheduler 推进前固定这组 metadata。实际 MEM 接口没有 gid，任何 monitor、
driver、reference 或 scoreboard 都不得根据地址猜测 gid。

## 2. 主要源文件

|文件|作用|
|---|---|
|`ver_common/uvc/vlm_agent/vlm_interface.sv`|统一 reservation/MEM interface|
|`ver_common/uvc/vlm_memory_agent/vlm_memory_sequence_item.svh`|按 bank 保存 MEM payload 和 match metadata|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_monitor.svh`|原子采样 reservation 与 MEM|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_checker.svh`|唯一到期 record 匹配和 gid 解析|
|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_agent.svh`|发布 write、查询 read data 和定时返回|
|`ut_shm/env/shm_scoreboard.svh`|实际 memory model 与 read transport 实现|

旧的 `vlm_memory_interface`、monitor、driver、sequencer 和 agent 文件暂时保留为迁移历史，
但不再进入主环境 filelist 或 UVM hierarchy。

## 3. Transaction

`vlm_memory_sequence_item` 用 `vlm_read` 区分方向，并为每个 logical bank 保存：

- `vlm_bken`、`vlm_addr`、`vlm_data` 和 `vlm_strb`；
- `vlm_gid`、`gid_valid` 和 `reservation_matched`。

Write transaction 在请求周期发布。Read transaction 在请求周期固定地址和 gid metadata，
从 scoreboard 查询对应 `<bank,gid,BADDR>` 数据，再在 `RPORT_DLY` 语义下驱动 `rdata`。
返回时不得重新读取 scheduler record。

## 4. 可信数据边界

只有 `gid_valid && reservation_matched` 的 transaction 可以访问可信 memory model：

- matched write 按有效 strobe 更新 `rtl_banks[bank][gid]` 并进入 byte-map 比对；
- matched read 从 `rtl_banks[bank][gid]` 获取 response；
- unexpected、missing、地址不匹配或到期不匹配只产生协议诊断，不得污染 memory。

`ref_banks` 与 `rtl_banks` 仍是两个独立模型。Reference 表示 creq 顺序架构结果；实际模型
只表示 DUT 已经通过 MEM 接口兑现的 matched write。

## 5. 当前缺口

- `VMEM-001`：read snapshot 尚未实现 `FFD_CYC` 写可见窗口；
- `VMEM-002`：MEM strobe 和有效 write data 的 X/Z 检查仍不完整；
- `ENV-001`：运行中 reset 尚未取消 pending read response 和重建 memory；
- 双 gid 正向主路径已通过 VCS 编译和当前真实 design 的 109-case `shm.lst`
  回归；gid 0/1 数据隔离和 reservation 失败路径仍缺独立定向证据。

问题状态和验收方法见[验证实现状态](../../verification-status.md)。
