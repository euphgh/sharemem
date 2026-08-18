# shmins_mst_agent

本文说明 shmins master agent 的 transaction、sequence、credit driver、creq monitor 和
raw ack 采集路径。creq 字段和 credit/ack 协议由
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
|`ver_common/uvc/shmins_agent/shmins_monitor.svh`|creq 和 raw direction-specific ack 采集|
|`ver_common/uvc/shmins_agent/sequences/shmins_sequence_item.svh`|正式公共 creq transaction、编码和 helper|
|`ver_common/uvc/shmins_agent/sequences/shmins_mst_unit_sequence.svh`|domain 和 plusarg 可配置的 master unit sequence|
|`ver_common/uvc/shmins_agent/sequences/shmins_contiguous_sequence_item.svh`|LDST_S/LDST_V 地址生成|
|`ver_common/uvc/shmins_agent/sequences/shmins_strided_sequence_item.svh`|LDSTE_S 地址生成|
|`ver_common/uvc/shmins_agent/sequences/shmins_indexed_sequence_item.svh`|LDSTE_V 地址生成|
|`ver_common/uvc/shmins_agent/sequences/shmins_vtrans_sequence_item.svh`|继承 contiguous 的 VTRANS 请求|
|`ver_common/uvc/shmins_agent/sequences/shmins_dontcare_x_util.svh`|在已验证 item 上注入合法 don’t-care X/Z|

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
当前每个 thread 的 `creq_offs` 和 `creq_vdat` 均为 256 bit，`creq_vmsk` 为
32 bit；sequence item、interface、driver 和 monitor 均以 `VEC_W=256`、`VEC_BYTE_N=32`
解释这些字段。

双 gid 地址迁移后，transaction helper 必须分成两层：各 itype/space 算法只生成
`shm_logical_addr_t{bank_id, absolute_warp_id, laddr}`，公共 helper 再生成
`shm_physical_addr_t{bank_id, gid, baddr}`。Collision、uniqueness 和 M2V hazard 均使用
完整物理 byte key，不能只比较 bank 和 BADDR。

SPACE_BLK 的 MADDR 是当前 WARP group 内的相对编码，范围为
`[0, C*BANK_N*creq_wpnum)`。公共第一层 helper 必须用 `creq_wpid/creq_wpnum` 生成 group
base，再加 MADDR 中的 `warp_offs`；不得从 MADDR 高位恢复 `warp_group`。

## 4. Sequence 配置

`shmins_mst_unit_sequence` 支持以下大写 plusarg：

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

枚举字符串通过 `shmins_enum_field.svh` 转换。未出现的 `CREQ_*` 保持完整 normal
allowed-value domain；出现的字段通过 `set_fix_*()` 缩小为 singleton。`VTRANS_EN` 是
0～100 的全局 transaction 概率，不再是 bit enable。

VTRANS 使用独立 dtype/atype/itype domain，并由 `shmins_vtrans_sequence_item` 强制 V2M、
SPACE_LOC、16 个 element、全 element mask 和全 thread mask。Normal 配置不覆盖 VTRANS
配置，两类请求可以在同一个 sequence 中混合生成。

## 5. Driver 和 credit

Driver 在 `main_phase` 中：

1. 把 creq 输出初始化为 0；
2. 等待 `rst_n===1`，把显式可用 credit 计数恢复为 `OTF_N`；
3. 每个 `mst_cb` 周期先采样 `creq_rls`，归还 credit 并检查计数不得超过 `OTF_N`；
4. 消耗尚未结束的 `delay_cycle`，并在没有 credit 时保持 `creq_vld==0`；
5. 使用非阻塞 `try_next_item()` 查询 sequencer，没有可用 item 时不等待；
6. 对取得的 item 编码 `creq_typ`，用递增计数生成 `creq_id`；
7. 在当前 clocking event 后驱动请求，使 DUT 在下一个采样沿接收；
8. 消耗一个 credit，并根据 `delay_cycle` 插入下一笔请求前的完整空闲周期。

`delay_cycle==0` 允许 `creq_vld` 连续保持为 1，此时每个采样沿接收不同请求；大于 0
时，该值表示相邻两笔 accepted creq 之间完整的 `creq_vld==0` 周期数。

Credit 与 ack 相互独立。Driver 不等待 ack 才发送下一笔，也不把 ack 当作 credit
release。

## 6. Monitor、ack 与 transaction lifecycle

Monitor 在 `creq_vld===1` 的采样沿创建新的 `shmins_sequence_item`，复制 payload、
解码 `creq_typ`，再通过 `shmins_analysis_port` 同步发布给 reference。每笔 accepted creq
同时带有共享 `accept_cycle`、monitor-owned `transaction_uid` 和 `reset_epoch`。

Monitor 不再为每笔请求创建固定 200-cycle timeout process。它独立采样：

- `mack_done/mack_id` 为 V2M raw ack；
- `vack_done/vack_id` 为 M2V raw ack；
- done 和有效 ID 的 X/Z；
- ack 的共享 cycle 和 reset epoch。

Environment 中的 `shm_transaction_lifecycle_checker` 关联 accepted creq、scoreboard
completion 和 raw ack，检查 ack enable、方向、ID、reset epoch 和 exactly-once。只有
scoreboard 把全部期望 byte 分类为 `OBSERVED`，并且该事务成为同方向 ordered lifecycle
队头后，才可选启动 `ACK_POST_COMPLETE_GRACE_CYCLES` 诊断；默认 20 cycles，0 表示关闭。
V2M/mack 和 M2V/vack 使用独立接收顺序，互不阻塞。前序 ack-disabled 事务在 data
resolved 后退休；前序 ack-enabled 事务在 data resolved 且 ack received 后退休。年轻
transaction 提前完成或提前收到 ack 只更新状态，当前不单独报告 out-of-order ack。

该 grace 不限制从 creq accepted 到数据完成的时延，也不包含年轻事务等待前序退休的
时间，因此不是 DUT protocol timeout。测试结束时 required ack 仍必须存在。

## 7. X/Z 和错误边界

Agent/driver 缺少 config 或 vif 时分别使用 `SHMINS_NO_CFG`、`SHMINS_NO_VIF` fatal。
Monitor 先检查 `creq_tmsk`：含 X/Z 时报告并停止 per-thread 分类，全零时报告后直接丢弃，
不分配 UID，也不写 production analysis port。tmsk 合法时，monitor 只检查 active thread
实际参与解释的 priority、length、vmsk、offset slice 和 V2M data byte；inactive payload
允许 X/Z。公共控制字段和完整字段矩阵仍由 `SHMINS-006` 跟踪。

Agent 在 monitor 存在时创建并连接 `shmins_request_coverage`。该 subscriber 只读采样
normal/VTRANS、direction、space、mask class/population、active thread 和 VTRANS
dtype/itype，并把 interpreted、inactive、masked data、masked indexed offset、length 外和
M2V 未使用 data 的 X/Z 分开统计。全零事务只允许由组件 harness 直接采样 coverage，
不经过 production monitor 数据流。

Transaction 的 `do_copy()` 已覆盖公共 creq、生成地址模型和统计字段；contiguous override
额外复制 `start_maddr`。`compare_item()` 使用 UVM 注册字段比较，不再无条件 fatal。
四 topology 独立 copy/compare 正反例已于 2026-08-13 在远端 VCS 通过，
`SHMINS-002/011` 已关闭。

## 8. 调试观察点

- `drv_tr_cnt`：driver 已发送事务数量和自动分配 ID 的来源；
- `credit_cnt` 是否耗尽、`creq_rls` 是否按预期归还 credit，以及是否报告上溢；
- `shmins_cnt`：monitor 采样事务数量；
- lifecycle direction queue：transaction UID、队列位置、方向、ID、ack/data completion、
  grace 状态和 cycle；
- sequence 打印的最终 item 与 monitor 重建 item 是否一致；
- `creq_typ` 的编码/解码字段，尤其是 `creq_info` 和 VTRANS。

## 9. 相关测试

`ut_shm/tests/shm_unit_test.svh` 通过 `shmins_mst_unit_sequence` 覆盖当前集成激励入口，
可用 plusarg 改变 transaction 数量、normal domain 和 VTRANS 比例。当前没有独立的
credit/release、ack 完整性或 reset 静默测试；thread-mask、四态边界及
sequencer→driver→monitor 保真测试位于 `examples/shmins_monitor_compile/`，transaction
copy/VTRANS 和 don’t-care utility 精确 slice 测试位于
`examples/shmins_sequence_compile/`。Strided item 已为 V2M `LDSTE_S + SPACE_WRP/SPACE_BLK`
生成 element-0 mask，V2M/M2V 共 24 个叶子 case 已随扩容后的 109-case 主列表
通过真实 DUT regression，`SHMINS-007` 已关闭。其余缺口由验证实现状态中的
开放项追踪。

## 10. 开发 contract

- Reference 的架构顺序以 monitor 发布的 creq 顺序为准；DUT 乱序调度不得改变最终
  memory 结果。
- 修改 `creq_tmsk` 时必须保持 interface、transaction、copy、factory field、constraints、
  driver、monitor 和 reference 同步；inactive thread 不得产生 reference 期望。
- 生成约束必须以地址 spec 为输入，并为 12 KiB 空洞提供定向测试。
- `creq_vaddr` 使用 `BADDR_W`，sequence 必须加入 `(creq_wpid%4)*WARP_STEP`，并保证
  有效写回 byte 留在当前 WARP；DUT 不再补加 WARP 基址。
- M2V 生成完成后必须复查所有有效 m-read/v-write 物理 byte 集合不相交，冲突粒度为 byte。
- LOC/WRP/BLK 不得分别实现 gid/BADDR 拆分；物理 BANK 组织只能由公共第二层 helper 定义。
- Public sequence knob 必须实际约束 item；不能只解析 plusarg 而忽略字段。
- Runtime reset 必须释放 credit wait、清除 lifecycle pending 状态，并阻止 reset 前 item
  继续驱动。

## 11. 当前实现状态

- `SHMINS-012`：topology-based 正式 sequence item、benchmark、consumer 和真实 RTL 集成
  已于 2026-08-13 验证完成并关闭。
- `SHMINS-001`：组件矩阵、24个 normal mask cell、4个 VTRANS cell和18笔inactive-X
  transaction已在正式design上通过；`normal_mask_cg`、`active_thread_cg`和`vtrans_cg`
  均为100%，2026-08-18关闭。
- `SHMINS-002/011`：transaction copy/compare 已通过 reference consumer 交叉测试及
  `examples/shmins_sequence_compile/copy_tb.sv` 的四 topology 正反例，2026-08-13 关闭。
- `SHMINS-003`：过程式 MADDR 生成、12 KiB/空洞检查和两层映射已按 group-relative BLK
  公式更新；432 组合、无 inline constraint benchmark、两轮各 1248 个独立 BLK 公式检查
  和实际 RTL BLK regression 均已通过，2026-08-13 关闭。
- `SHMINS-004`：RW/DTYPE/ATYPE_W/ITYPE/SPACE 固定配置已通过 109-case 真实 RTL 回归；
  ATYPE_S/G 仍等待 testcase 配置到 monitor 的端到端定向验证。
- `SHMINS-005`：存在固定 16-thread/4-bit 参数硬编码。
- `SHMINS-006`：active interpreted payload 局部 X/Z 检查、合法 don’t-care X utility、
  component matrix、18+12笔真实 RTL test和ignored-X coverage已实现并通过正式design；
  `dontcare_xz_cg=58.33%`且本批目标X counter均命中。完整Z/XZ及公共/active非法字段
  矩阵仍缺。
- `SHMINS-007`：V2M `LDSTE_S + WRP/BLK` 的 element-0 mask 和 V2M/M2V 24 个 case
  已随 109-case 主列表通过真实 RTL regression，2026-08-14 关闭。
- `SHMINS-008`：固定 ack timeout 已移除，改为 scoreboard observed 后可配置 grace；
  2026-08-14 空 design VCS 编译通过，待长延迟 ack 定向验证。
- `SHMINS-009`：ack enable、unexpected、duplicate、wrong-direction、wrong-ID 的 lifecycle
  checker 和 driver credit/release 上溢检查已实现但待定向正负例验证。
- `SHMINS-010`：复位期间 release/ack 静默没有检查。
- `ENV-001`：运行中 reset 未取消 driver/monitor pending 状态。
- 双 gid 地址结构、`creq_vaddr` 和 M2V byte-overlap 正向主路径已通过 109-case 真实 RTL 回归；
  第一批 gid边界、数据隔离和 ownership directed LST也已通过，coverage和未覆盖失败路径仍由
  verification status 跟踪。

问题详情和验收方法见[验证实现状态](../../verification-status.md)。
