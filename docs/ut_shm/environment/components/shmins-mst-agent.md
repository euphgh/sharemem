# shmins_mst_agent

本文说明 shmins master agent 的 transaction、sequence、credit driver、creq monitor 和
ack timeout 路径。creq 字段和 credit/ack 协议由
[creq/ack 接口规范](../../spec/creq-ack-interface.md)定义；本文只解释验证组件如何
产生和观察这些行为。

## 1. 组件结构

```text
shmins_mst_agent
├── shmins_mst_sequencer
├── shmins_mst_driver
└── shmins_monitor
```

Agent 从 Config DB 获取 `shmins_mst_agent_config` 和 `shmins_vif`。默认完整 active
模式下创建 sequencer、driver 和 monitor，并在 connect phase 分配 vif、连接
`seq_item_port`。当前 ut_shm 明确不支持 passive 模式。

## 2. 主要源文件

|文件|作用|
|---|---|
|`ver_common/uvc/shmins_agent/shmins_interface.sv`|creq、release 和 ack clocking block|
|`ver_common/uvc/shmins_agent/shmins_mst_agent.svh`|agent 创建和连接|
|`ver_common/uvc/shmins_agent/shmins_mst_driver.svh`|credit 控制和 creq 驱动|
|`ver_common/uvc/shmins_agent/shmins_monitor.svh`|creq 采集和 ack timeout|
|`ver_common/uvc/shmins_agent/sequences/shmins_sequence_item.svh`|creq transaction、编码和 helper|
|`ver_common/uvc/shmins_agent/sequences/shmins_seq_item_constraints.svh`|生成的随机约束|
|`ver_common/uvc/shmins_agent/sequences/shmins_unit_sequence.svh`|plusarg 可配置的 unit sequence|

## 3. Transaction 与 `creq_typ`

`shmins_sequence_item` 同时保存解码后的 enum 字段和 RTL 使用的 20-bit `creq_typ`。
`item_to_rtl()` 按以下顺序打包：

```text
{creq_info, creq_space, creq_inv_size, creq_ack_en,
 creq_itype, creq_atype_g, creq_atype_s, creq_atype_w,
 creq_dtype, creq_rw}
```

Driver 在驱动前调用 `item_to_rtl()`；monitor 采样后调用 `rtl_to_item()`。地址相关
helper 从 dtype、atype 和 itype 计算 element 数、offset 宽度和 MADDR，详细地址规则
应引用[地址模型](../../spec/address-model.md)，不能以当前 constraint 反向定义 spec。

## 4. Sequence 配置

`shmins_unit_sequence` 支持以下大写 plusarg：

```text
TRANS_NUM
TRANS_DELAY_MIN
TRANS_DELAY_MAX
VTRANS_EN
CREQ_RW
CREQ_DTYPE
CREQ_ATYPE_W
CREQ_ATYPE_S
CREQ_ATYPE_G
CREQ_ITYPE
CREQ_SPACE
```

枚举字符串通过 `shmins_enum_field.svh` 转换。普通请求从这些配置约束 item；VTRANS
强制 V2M、SPACE_LOC、16 个 element、全 element mask 和全 thread mask。普通请求的
`creq_tmsk` 随机化约束为非全零，driver 和 monitor 已贯通该字段。

## 5. Driver 和 credit

Driver 在 `main_phase` 中：

1. 把 creq 输出初始化为 0；
2. 等待 `rst_n===1`，创建容量为 `OTF_N` 的 semaphore；
3. 每笔 item 先取得一个 credit，再从 sequencer 取请求；
4. 编码 `creq_typ`，用递增计数生成 `creq_id`；
5. 将 `creq_vld` 和 payload 驱动一个时钟周期；
6. 根据 `delay_cycle` 插入下一笔请求前的空闲周期；
7. 独立线程观察 `creq_rls`，每个有效周期归还一个 semaphore token。

Credit 与 ack 相互独立。Driver 不等待 ack 才发送下一笔，也不把 ack 当作 credit
release。

## 6. Monitor 和 ack timeout

Monitor 在 `creq_vld===1` 的采样沿创建新的 `shmins_sequence_item`，复制 payload、
解码 `creq_typ`，再通过 `shmins_analysis_port` 同步发布给 reference。

对于 `creq_ack_en==1` 的事务，monitor 按方向和 `creq_id` 保存 timeout process：

- V2M 等待 `mack_done/mack_id`；
- M2V 等待 `vack_done/vack_id`；
- 200 个周期内收到匹配 ack 时终止 timeout process；
- 超时则报告 `UVM_ERROR`。

该 timeout 是环境诊断策略，不是 DUT 最大延迟协议。运行中 reset 对这些 process 的
取消属于 `ENV-001`。

## 7. X/Z 和错误边界

Agent/driver 缺少 config 或 vif 时分别使用 `SHMINS_NO_CFG`、`SHMINS_NO_VIF` fatal。
Monitor 当前只严格判断 `creq_vld`，没有按 active/inactive thread 规则检查 payload
四态，见 `SHMINS-006`。

Transaction 的 `compare_item()` 仍是 placeholder，调用会 fatal；字段复制也存在已知
问题。开发者不应把这些 helper 当作已经验证的公共 API。

## 8. 调试观察点

- `drv_tr_cnt`：driver 已发送事务数量和自动分配 ID 的来源；
- semaphore 是否耗尽、`creq_rls` 是否按预期归还 credit；
- `shmins_cnt`：monitor 采样事务数量；
- `thread_handles[direction][id]`：等待 ack 的 timeout process；
- sequence 打印的最终 item 与 monitor 重建 item 是否一致；
- `creq_typ` 的编码/解码字段，尤其是 `creq_info` 和 VTRANS。

## 9. 相关测试

`ut_shm/tests/shm_unit_test.svh` 通过 `shmins_unit_sequence` 覆盖当前集成激励入口，可用
plusarg 改变 transaction 数量和部分 creq 字段。当前没有独立的 credit/release、ack
完整性、四态输入、transaction copy 或 reset 静默单元测试；V2M
`LDSTE_S + SPACE_WRP/SPACE_BLK` 也缺少 element-0 mask 激励。相关缺口由
`SHMINS-001`～`SHMINS-010` 的验收项追踪。

## 10. 开发 contract

- Reference 的架构顺序以 monitor 发布的 creq 顺序为准；DUT 乱序调度不得改变最终
  memory 结果。
- 修改 `creq_tmsk` 时必须保持 interface、transaction、copy、factory field、constraints、
  driver、monitor 和 reference 同步；inactive thread 不得产生 reference 期望。
- 生成约束必须以地址 spec 为输入，并为 12 KiB 空洞提供定向测试。
- Public sequence knob 必须实际约束 item；不能只解析 plusarg 而忽略字段。
- Runtime reset 必须释放 credit wait、取消 ack timeout，并阻止 reset 前 item 继续驱动。

## 11. 当前实现状态

- `SHMINS-001`：`creq_tmsk` 数据链已实现，等待远端 DUT/VCS 定向验证。
- `SHMINS-002`：transaction copy 不完整。
- `SHMINS-003`：地址约束与 12 KiB 地址模型不一致。
- `SHMINS-004`：部分 unit-sequence 配置未作用到 item。
- `SHMINS-005`：存在固定 16-thread/4-bit 参数硬编码。
- `SHMINS-006`：缺少 active payload X/Z 检查。
- `SHMINS-007`：V2M `LDSTE_S + WRP/BLK` 缺少 element-0 mask 激励。
- `SHMINS-008`：固定 ack timeout 与协议无最大延迟冲突。
- `SHMINS-009`：credit/release 和 ack 完备性检查不足。
- `SHMINS-010`：复位期间 release/ack 静默没有检查。
- `ENV-001`：运行中 reset 未取消 driver/monitor pending 状态。

问题详情和验收方法见[验证实现状态](../../verification-status.md)。
