# SHM 读写顺序定向验证开发计划

本文根据 [creq/ack 接口规范](../ut_shm/spec/creq-ack-interface.md)、
[MEM/VLM 接口规范](../ut_shm/spec/mem-vlm-interface.md)、
[Testpoints](../ut_shm/plan/testpoints.md) 和
[验证实现状态](../ut_shm/verification-status.md)，规定同一 thread 的 M-read/M-write
顺序、V-write 顺序、跨 transaction 地址安全检查及其验收方法。

本计划优先增加能够在真实 RTL 上直接暴露顺序错误的定向 case。普通随机 sequence 的
跨 transaction 防冲突属于低优先级扩展，不阻塞首批定向验证。

## 1. 目标与范围

本批验证以下架构要求：

1. 同一 thread 的 M-read 和 M-write 必须按 creq 接收顺序生效；
2. 同一 thread 的多个 M-write 最终结果必须等价于 creq 顺序执行；
3. 同一 thread 的多个 V-write 最终结果必须等价于 creq 顺序执行；
4. V-write 与其他 transaction 的 M-read/M-write 不保证顺序，激励必须保证它们没有
   physical byte overlap；
5. reference 和 scoreboard 必须能够区分合法的中间乱序兑现与错误的最终 memory 状态；
6. MEM read model 必须按 `FFD_CYC` 生成与 testbench 进程调度顺序无关的 read snapshot。

首批真实 RTL case 固定使用单 thread、`DTYP8`、单个 active element、`SPACE_LOC` 和精确
byte overlap，先验证最小可诊断场景。DTYPE、mask、gid、space 和 partial overlap 的扩展
不阻塞首批验收。

以下内容不属于首批高优先级范围：

- 普通 `m2v.tc`、`v2m.tc` 的跨 transaction 防冲突；当前 case 的 transaction delay 较大，
  可以保证前一笔请求完成后再开始下一笔；
- 全项目 coverage merge 或总覆盖率百分比阈值；
- 运行中 reset、ACK/credit 负例和 reservation 调度压力；
- 强制 RTL 按固定周期或固定 MEM beat 顺序执行；只检查架构可见结果。

## 2. 术语与顺序 contract

### 2.1 三类访问集合

每笔 SHMINS transaction 按物理 byte 地址形成以下集合：

|集合|来源|含义|
|---|---|---|
|`m_read_set`|普通 M2V|从 M 侧读取的有效 byte|
|`m_write_set`|普通 V2M 或 VTRANS|写入 M 侧的有效 byte|
|`v_write_set`|普通 M2V|按 `creq_vaddr` 写回 V 侧的有效 byte|

物理 byte key 必须包含：

```text
<bank_id, gid, BADDR>
```

比较时需要按 dtype 展开 element 占用的全部 byte，不能只比较 element 起始地址。相同
`BADDR` 但不同 gid 的地址不重合；相邻但没有共同 byte 的地址也不重合。

### 2.2 必须保证顺序的关系

同一 thread 中以下关系必须等价于 creq 接收顺序执行：

|先发 transaction|后发 transaction|被检查的关系|架构结果|
|---|---|---|---|
|M2V|V2M|M-read → M-write|M2V 读到旧值，M 最终为新值|
|V2M|M2V|M-write → M-read|M2V 读到新值|
|V2M|V2M|M-write → M-write|M 最终为第二笔写入值|
|M2V|M2V|V-write → V-write|V 最终为第二笔写回值|

M-read/M-write、M-write/M-write 和 V-write/V-write 的 overlap 是本计划需要主动构造的
合法激励，不能被通用 hazard checker 拒绝。

### 2.3 激励必须避免的关系

V-write 与其他 transaction 的 M 访问没有顺序保证。对于任意两笔 transaction `A/B`，
以下任一交集非空时，激励组合非法：

```text
A.v_write_set intersect (B.m_read_set union B.m_write_set)
(A.m_read_set union A.m_write_set) intersect B.v_write_set
```

检查必须覆盖两个 issue 方向：

1. M2V V-write 在前，后续 M2V M-read 与它重合；
2. M2V M-read 在前，后续 M2V V-write 与它重合；
3. M2V V-write 在前，后续 V2M M-write 与它重合；
4. V2M M-write 在前，后续 M2V V-write 与它重合。

单笔 M2V transaction 内部的 M-read/V-write byte overlap 已由现有 sequence item 规则禁止；
本计划新增的是多笔 directed item 组成一个 batch 时的 pairwise 检查。

## 3. 首批真实 RTL Case 矩阵

每个 test 先使用独立 V2M transaction 预置 source memory，并调用
`shm_env.wait_for_idle()` 确认 setup 已完成。目标 transaction 必须背靠背发送，中间不得
调用 `wait_for_idle()`；整个 batch 发出后再统一 drain 和检查最终状态。

### 3.1 基础矩阵

|Case ID|建议 test class|Setup|连续目标 transaction|最终判定|
|---|---|---|---|---|
|`ORDER-M-001`|`shm_m_read_then_write_order_test`|`Msrc=OLD`|M2V `Msrc→Vdst`，然后 V2M `NEW→Msrc`|`Vdst=OLD`，`Msrc=NEW`|
|`ORDER-M-002`|`shm_m_write_then_read_order_test`|`Msrc=OLD`|V2M `NEW→Msrc`，然后 M2V `Msrc→Vdst`|`Vdst=NEW`，`Msrc=NEW`|
|`ORDER-M-003`|`shm_m_write_then_write_order_test`|无需旧值依赖|V2M `FIRST→Mdst`，然后 V2M `SECOND→Mdst`|`Mdst=SECOND`|
|`ORDER-V-001`|`shm_v_write_then_write_order_test`|`Msrc0=FIRST`，`Msrc1=SECOND`|M2V `Msrc0→Vdst`，然后 M2V `Msrc1→Vdst`|`Vdst=SECOND`|

`OLD`、`FIRST`、`SECOND` 必须互不相同。`ORDER-M-001/002` 中 `Vdst` 必须与 `Msrc`
不重合；`ORDER-V-001` 中 `Vdst` 必须与 `Msrc0/Msrc1` 都不重合，但两笔 V-write 必须完全
重合。

### 3.2 首批固定参数

|维度|首批取值|后续扩展|
|---|---|---|
|thread|单一 thread 0|thread 15、多个 thread|
|dtype|`DTYP8`|`DTYP16/32`|
|element|单个 active element|sparse mask、多个连续 element|
|space|`SPACE_LOC`|`SPACE_WRP/BLK`|
|gid|先固定一个 gid|gid 0/1、wpid 3/4 边界|
|overlap|单 byte 完全重合|多 byte 完全/部分 overlap|
|topology|contiguous|strided、indexed、VTRANS M-write|

每个基础 test 独立注册到 TC，便于一个顺序关系失败时单独保存 waveform 和 coverage。新增
`shm_ordered_access.lst` 聚合四个 test，首轮不直接加入 `shm.lst`。

## 4. Directed batch 激励基础设施

### 4.1 Queue sequence

在 `ver_common/uvc/shmins_agent/sequences/` 增加可复用的 directed queue sequence。它应：

1. 接受由 testcase 完整构造并验证的 `shmins_sequence_item` queue；
2. 发送前对 queue 内所有 item 做跨 transaction V-write/M-access hazard 检查；
3. 严格按 queue 顺序调用 `start_item()/finish_item()`；
4. 不重新 randomize、不重新 pack offset、不修改 payload；
5. 支持 item 间 issue delay，首批顺序 case 使用 0；
6. 对非法 pair 给出 item index、direction、thread、bank、gid、BADDR 和重叠 byte 数。

`shm_directed_base_test` 增加 `send_directed_items()`。现有 `send_directed_item()` 保留，并可
封装为只含一个 item 的 queue，以维持已有 testcase API。

在同一个 sequencer 上先后启动两个单 item sequence 也能按 sequencer 仲裁顺序发送，但两个
sequence 之间没有共同的 batch 上下文，无法统一检查跨 transaction 地址关系。因此顺序
case 使用 queue sequence，不依赖 testcase 对多个独立 sequence 做隐式协调。

### 4.2 Pairwise hazard helper

公共 sequence item 或独立公共 utility 至少提供：

```text
collect_m_access_bytes()
collect_v_write_bytes()
has_unordered_cross_transaction_overlap(other)
cross_transaction_overlap_sprint(other)
```

helper 只描述物理 byte 集合和协议不保证顺序的关系，不负责 outstanding 生命周期，也不应
拒绝本计划需要验证的 M/M 或 V-write/V-write overlap。

## 5. MEM read 的 `FFD_CYC` 前置修复

正参数窗口的前置修复已经落地：统一 VLM agent 以同步 write transport 和
committed-cycle watermark 固定 `T0+FFD_CYC-1` 截止周期，并在
`T0+RPORT_DLY` 返回 snapshot。当前实现边界为 `1 <= FFD_CYC <= RPORT_DLY`；
`FFD_CYC=0` 仍是 `VMEM-001` 的剩余缺口。

Memory model 必须：

1. 在 T0 记录 read bank、gid、地址和接受 cycle；
2. 在 `T0+FFD_CYC-1` 截止后形成逐 byte snapshot；
3. snapshot 包含截止周期及之前接受的有效 strobe write；
4. snapshot 排除截止周期之后、即使早于 read return 的 write；
5. 在 `T0+RPORT_DLY` 返回对应 snapshot；
6. 同一 bank 连续 read 时保持请求和返回顺序；
7. 同周期 read/write 结果不依赖 monitor、driver 或 scoreboard 的进程调度顺序。

组件测试已覆盖 `FFD_CYC=1/2`、截止周期/截止后、full/partial byte overlap、连续覆盖、
同 BANK 连续 read 和双 gid 隔离。`FFD_CYC=0` 仍需单独设计 snapshot 语义和调度实现；该项
对应 `VMEM-001/TP-MEM-003`。

## 6. 最终 memory 一致性检查

### 6.1 保留在线匹配算法

现有 `wmap_final/wmap_expired` 继续用于接受 DUT 合法的中间乱序写：

- 实际 byte 可以匹配当前 final value；
- 被后续 creq 覆盖的旧值可以匹配 expired value；
- `wmap_final` 在 drain 时必须为空。

这套在线匹配不应改成严格按 transaction 顺序逐笔等待，否则会错误限制 RTL 的内部调度。

### 6.2 直接比较 `ref_banks` 与 `rtl_banks`

最终状态不新增 `architectural_final_map`。Reference 已经按 creq 接收顺序更新
`ref_banks[BANK_N][GID_N]`，它就是架构最终值；scoreboard 的 `rtl_banks` 保存 DUT 实际
兑现结果。环境 drain 后直接比较二者：

```text
ref_banks[bank][gid][baddr] == rtl_banks[bank][gid][baddr]
```

实现要求：

1. 比较只在 scoreboard、lifecycle 和 reservation 都进入稳定 idle 后执行；
2. 比较 key 必须包含 bank、gid 和完整 BADDR；
3. 可以遍历完整 modeled address domain；若为效率只比较 touched byte，则只保存物理 key
   集合，不复制 expected data；expected data 必须在比较时从 `ref_banks` 读取；
4. mismatch 日志打印 bank、gid、BADDR、reference byte 和 RTL byte；
5. `check_phase` 至少执行一次最终比较，顺序 testcase 也可以在 batch drain 后显式调用；
6. `ref_banks` 与 `rtl_banks` 必须保持相同初始化和 reset epoch。

该检查能够发现以下漏报：reference 期望 `FIRST→SECOND`，DUT 实际输出
`SECOND→FIRST`。两笔实际 write 可能分别命中 final/expired，但最终 `rtl_banks=FIRST` 与
`ref_banks=SECOND` 不同，测试必须失败。

建议由 `shm_environment` 提供统一的 final-memory compare 入口，因为 environment 同时拥有
reference 和 scoreboard；具体 byte 比较和 report helper 可以放在 scoreboard 或公共 memory
utility 中。不得建立第三份 expected value memory。

## 7. 组件测试矩阵

不需要真实 DUT 的测试全部放在 `examples/`。

### 7.1 Cross-transaction hazard

|场景 ID|关系|预期|
|---|---|---|
|`ORDER-HAZ-001`|前一笔 V-write 与后一笔 M-read byte overlap|拒绝|
|`ORDER-HAZ-002`|前一笔 M-read 与后一笔 V-write byte overlap|拒绝|
|`ORDER-HAZ-003`|前一笔 V-write 与后一笔 M-write byte overlap|拒绝|
|`ORDER-HAZ-004`|前一笔 M-write 与后一笔 V-write byte overlap|拒绝|
|`ORDER-HAZ-005`|M-read/M-write overlap|接受|
|`ORDER-HAZ-006`|M-write/M-write overlap|接受|
|`ORDER-HAZ-007`|V-write/V-write overlap|接受|
|`ORDER-HAZ-008`|相邻 byte，无 overlap|接受|
|`ORDER-HAZ-009`|相同 BANK/BADDR、不同 gid|接受|
|`ORDER-HAZ-010`|DTYP16/32 只有部分 byte overlap|拒绝并准确打印 overlap byte|

### 7.2 Directed queue transport

|场景 ID|场景|预期|
|---|---|---|
|`ORDER-SEQ-001`|两个合法 item、delay 0|monitor 观察到两笔且 accept cycle 连续|
|`ORDER-SEQ-002`|三个合法 item、delay 1|顺序不变且相邻 accept cycle 有一个空闲周期|
|`ORDER-SEQ-003`|第二笔与第一笔形成非法 V/M overlap|发送前失败，不发布部分 batch|
|`ORDER-SEQ-004`|原单 item API|既有 directed component tests 无回归|

### 7.3 Final memory comparison

|场景 ID|Reference 顺序|实际写顺序|预期|
|---|---|---|---|
|`ORDER-SCB-001`|`FIRST→SECOND`|`FIRST→SECOND`|final/expired 与 bank compare 均通过|
|`ORDER-SCB-002`|`FIRST→SECOND`|`SECOND→FIRST`|在线 byte 可被解释，但 final bank compare 失败|
|`ORDER-SCB-003`|多 byte 部分覆盖|正确最终组合|逐 byte比较通过|
|`ORDER-SCB-004`|多 byte 部分覆盖|overlap byte 保留旧值|只报告错误 byte|
|`ORDER-SCB-005`|相同 BADDR、不同 gid|两个 gid 使用不同最终值|双 gid 比较通过|

负例使用 report catcher 或返回 `bit` 的无副作用 compare helper，确保组件测试本身最终仍为
`UVM_ERROR: 0`、`UVM_FATAL: 0`。

### 7.4 `FFD_CYC` read snapshot

|场景 ID|写相对 read T0 的周期|预期可见性|
|---|---|---|
|`ORDER-MEM-001`|截止周期之前|可见|
|`ORDER-MEM-002`|截止周期|可见|
|`ORDER-MEM-003`|截止周期之后|不可见|
|`ORDER-MEM-004`|同一 beat 的部分 strobe overlap|只更新重叠有效 byte|
|`ORDER-MEM-005`|同一 byte 多次覆盖|返回截止周期前最后一次写值|
|`ORDER-MEM-006`|同一 bank 连续 read|按请求顺序、固定 `RPORT_DLY` 返回|

## 8. 普通随机 sequence 的后续保护

普通 `m2v.tc` 和 `v2m.tc` 当前使用较大的 transaction delay，首批不修改
`shmins_mst_unit_sequence`，也不把随机 sequence 防冲突作为定向 case 的前置条件。

后续实现时采用固定深度滑动窗口：

1. sequence 保存最近生成并发送的最多 `OTF_N` 笔 transaction 地址摘要；
2. 每笔新 transaction 只与前 `OTF_N` 笔检查 V-write/M-access overlap；
3. 允许 M/M overlap 和 V-write/V-write overlap；
4. 发现非法 overlap 时重新生成 candidate，并设置有上限的 retry；
5. 超过 retry 上限时报告 candidate 与历史 item 的完整冲突位置；
6. 新 item 接受后压入窗口，窗口超过 `OTF_N` 时移除最老 item。

该策略利用最大 outstanding 数为 `OTF_N` 的系统边界，不引入 ACK、release 或 scoreboard
completion feedback。它可能比精确 outstanding 状态更保守，但不会漏掉仍可能并行执行的
最近 transaction，且实现复杂度较低。

## 9. 逐文件实施顺序

|顺序|优先级|文件或目录|修改|
|---:|---:|---|---|
|1|P0|`ver_common/uvc/shmins_agent/sequences/`|增加物理 byte 集合、pairwise hazard helper 和 directed queue sequence|
|2|P0|`examples/shmins_sequence_compile/`、`examples/shmins_monitor_compile/`|完成 hazard 和 queue transport 组件矩阵|
|3|P0|统一 VLM agent、scoreboard memory service|实现 `FFD_CYC` snapshot 和固定延迟返回|
|4|P0|新增或现有 memory component harness|完成 `ORDER-MEM-001`～`006`|
|5|P0|`shm_environment`、`shm_scoreboard`、memory compare utility|增加 drain 后 `ref_banks/rtl_banks` 直接比较|
|6|P0|新增 scoreboard/reference component harness|完成 `ORDER-SCB-001`～`005`|
|7|P0|`ut_shm/tests/shm_directed_base_test.svh`|增加 batch 构造、发送和 final-memory compare API|
|8|P0|`ut_shm/tests/`|增加四个真实 RTL 顺序 test|
|9|P0|test package、TC、独立 LST|登记 `shm_ordered_access.lst`，暂不加入主列表|
|10|P1|coverage、testpoint、status 和 regression 文档|记录实际组件/RTL/coverage 证据|
|11|P2|`shmins_mst_unit_sequence.svh`|实现最近 `OTF_N` 笔的随机 sequence hazard 滑动窗口|

必须先完成 `FFD_CYC` 和 final bank compare 的组件门禁，再把四个顺序 test 的通过结果作为
RTL 功能证据。空 design 只能证明编译、elaboration 和 package 集成，不能证明顺序行为。

## 10. EDA 验证顺序与判定标准

### 阶段 A：组件门禁

1. hazard 正负矩阵全部通过；
2. directed queue 能准确发送连续 item，非法 batch 在发送前被拒绝；
3. `FFD_CYC` 截止窗口不依赖 testbench 进程调度顺序；
4. final bank compare 能抓到 `SECOND→FIRST` 的错误最终结果；
5. 原 SHMINS sequence、driver/monitor、reference、reservation 组件测试无回归。

### 阶段 B：环境编译

1. 远端 VCS 空 design compile/elaboration 通过；
2. 四个新 test、TC 和 LST 均进入编译；
3. `TRANS_NUM=0` smoke 无新增 UVM error/fatal。

### 阶段 C：真实 RTL

每个基础 test 必须同时满足：

1. setup transaction 完成后才开始目标 batch；
2. monitor 按预期顺序观察到两笔目标 creq，且中间没有 testcase drain；
3. batch 中不存在 V-write/M-access byte overlap；
4. reference 结果与 Case 矩阵一致；
5. scoreboard 在线 write 全部为 final 或 expired 合法匹配；
6. batch drain 后 `ref_banks` 与 `rtl_banks` 一致；
7. scoreboard、lifecycle 和 reservation 无 pending transaction；
8. 最终 `UVM_ERROR: 0`、`UVM_FATAL: 0`，并输出稳定的 cell/test PASS marker。

四个基础 test 全部通过后运行 `shm_ordered_access.lst`，再重跑 `shm.lst`。只有正式 design
结果可以作为顺序功能证据。

## 11. 完成状态

- [ ] P0：建立可信的顺序验证基础设施
  - [x] 跨 transaction physical byte hazard
    - [x] 实现 M-access/V-write byte 集合 helper
    - [x] 实现双向 V-write/M-access overlap 检查和诊断
    - [x] `ORDER-HAZ-001`～`010` 组件测试通过
  - [x] Directed batch sequence
    - [x] 实现 item queue、delay 和发送前原子校验
    - [x] `send_directed_items()` 接入 directed base test
    - [x] 原 `send_directed_item()` API 和既有 tests 无回归
    - [x] `ORDER-SEQ-001`～`004` 组件测试通过
  - [ ] `FFD_CYC` memory read snapshot
    - [x] 实现 `FFD_CYC>=1` 截止周期 snapshot 和 `RPORT_DLY` 固定周期返回
    - [x] 消除正参数窗口同周期读写的 testbench process-order 依赖
    - [x] `ORDER-MEM-001`～`006` 正参数组件矩阵通过
    - [x] `VMEM-001/TP-MEM-003` 状态按正参数证据更新
    - [ ] 支持并验证 `FFD_CYC=0`
  - [x] 最终 memory 一致性
    - [x] 实现 drain 后 `ref_banks/rtl_banks` 直接比较
    - [x] 未增加第三份 expected value memory
    - [x] 实现 BANK/GID/BADDR/expected/actual mismatch 诊断
    - [x] `ORDER-SCB-001`～`005` 组件测试通过
- [ ] P0：增加真实 RTL 定向 Case
  - [ ] `ORDER-M-001`：M-read → M-write
    - [x] testcase、TC 和最终结果判定完成
    - [x] 空 design 编译通过
    - [ ] 正式 design 运行通过
  - [ ] `ORDER-M-002`：M-write → M-read
    - [x] testcase、TC 和最终结果判定完成
    - [x] 空 design 编译通过
    - [ ] 正式 design 运行通过
  - [ ] `ORDER-M-003`：M-write → M-write
    - [x] testcase、TC 和最终结果判定完成
    - [x] 空 design 编译通过
    - [ ] 正式 design 运行通过
  - [ ] `ORDER-V-001`：V-write → V-write
    - [x] testcase、TC 和最终结果判定完成
    - [x] 空 design 编译通过
    - [ ] 正式 design 运行通过
  - [ ] `shm_ordered_access.lst`
    - [x] 四个基础 test 全部登记
    - [ ] 正式 design 独立列表通过
    - [ ] `shm.lst` 无新增回归
- [ ] P1：覆盖率与扩展矩阵
  - [ ] 增加顺序类型、overlap class、gid 和 final-result coverage
  - [ ] 扩展 `DTYP16/32` 和 partial byte overlap
  - [ ] 扩展 thread 15、gid 0/1 和 wpid 3/4
  - [ ] 扩展 WRP、BLK、strided、indexed 和 VTRANS M-write
  - [ ] 更新 testpoints、verification status、regression 和 coverage 文档
- [ ] P2：普通随机 sequence 的跨 transaction 防冲突
  - [ ] 保存最近最多 `OTF_N` 笔 transaction 地址摘要
  - [ ] candidate 只与前 `OTF_N` 笔做双向 V-write/M-access 检查
  - [ ] 实现 bounded retry、窗口淘汰和冲突诊断
  - [ ] 增加窗口首笔、满窗口、淘汰和 retry 组件测试
  - [ ] 评估是否需要启用到普通 `m2v.tc/v2m.tc`

### 11.1 当前验证证据

2026-08-20 已完成以下非 DUT 门禁：

- `scripts/ubuntu/check_shmins_sequence_vcs.sh all`：完整 SHMINS 组件集通过，其中
  `ORDER-HAZ-001`～`010`、`ORDER-SEQ-001`～`004` 均输出 PASS；
- `scripts/ubuntu/check_shm_final_memory_vcs.sh`：`ORDER-SCB-001`～`005` 全部通过；
- `make .SHELLFLAGS=-ec compile`：四个新 test 与完整环境完成远端 VCS 编译和 elaboration；
- `make .SHELLFLAGS=-ec smoke`：`TRANS_NUM=0` 空 design 路径通过，最终为
  `UVM_ERROR: 0`、`UVM_FATAL: 0`。

以上结果不构成 `ORDER-M-001`～`003` 或 `ORDER-V-001` 的 RTL 功能证据。下一步应在正式
design 上运行独立 `shm_ordered_access.lst`；四项全部通过后再运行原 `shm.lst`，并据实
更新上方完成状态。
