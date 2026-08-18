# SHMINS don’t-care X 定向验证开发计划

本文根据 [creq/ack 接口规范](../ut_shm/spec/creq-ack-interface.md)、
[Testpoints](../ut_shm/plan/testpoints.md)和
[验证实现状态](../ut_shm/verification-status.md)，规定 SHMINS 合法 don’t-care payload
注入 X 的实现顺序、组件测试、真实 RTL 矩阵和判定标准。

此前双 gid `p0_directed.lst` 和 thread-mask/VTRANS `shmins_mask_directed.lst` 已全部在最新
真实 design 上通过；对应实现过程不再保留在本文。Coverage bin/cross 是否闭环仍由状态和
testpoint 文档独立跟踪，不能仅凭 LST 通过推断全部 coverage 已命中。

## 1. 目标与范围

本批验证 DUT、driver、monitor 和 reference 只解释协议选中的 payload：

1. `creq_tmsk[t]==0` 时，thread `t` 的全部 per-thread payload 可以为 X；
2. active thread 中被已知 `creq_vmsk[t][k]==0` 屏蔽的 element data 可以为 X；
3. `LDSTE_V` 被屏蔽 element 的独立 offset slice 可以为 X；
4. contiguous/strided 未使用的 packed offset slice 可以为 X，但共享 offset/stride 必须已知；
5. length 范围外的 mask、data 和未使用 offset slice 可以为 X；
6. M2V 不解释 `creq_vdat`，因此 active thread 的输入 data 可以为 X；
7. X 不得污染 reference、reservation、MEM、M2V writeback 或 scoreboard 最终结果。

本批主要推进 `SHMINS-006`、`TP-CREQ-002` 和 `TP-CREQ-004`，并为已有
`SHMINS-001/TP-CREQ-003` 补充真实 DUT 的 inactive-payload X 证据。

以下内容不属于本批：

- 向 DUT 发送全零或含 X/Z 的 `creq_tmsk`；
- 向 DUT 发送公共控制字段、active priority/length、有效 mask、有效 offset 或有效 V2M data
  含 X/Z 的非法请求；
- 用 X 表示 length 范围内 element 是否有效；该范围的 `creq_vmsk` bit 必须已知；
- 运行中 reset、ack/credit 负例、MEM/VLM 接口四态矩阵；
- 全项目 coverage merge 或总百分比阈值。

非法输入只在 `examples/` 组件 harness 中用于 checker 边界验证，不作为 DUT 功能 case。

## 2. 合法 X contract

### 2.1 Inactive thread

当 `creq_tmsk[t]===1'b0` 时，以下字段全部是 don’t-care，可以整体置 X：

```text
creq_prio[t]
creq_len[t]
creq_vmsk[t]
creq_offs[t]
creq_vdat[t]
```

该 thread 不得形成 MADDR、logical/physical address、reservation、MEM 访问或 M2V 写回。
`elem_num`、`elem_maddr` 和地址回填数组是 verification object 内部生成态，不在 RTL 接口上，
不注入 X。

### 2.2 Active thread 的 element 选择

`creq_len[t]` 和 dtype 决定 length-bounded element 范围；范围内的 `creq_vmsk[t][k]` 必须
已知。只有 mask bit 为 1 的 element 形成访问。

|地址拓扑|mask=0 element data|mask=0 element offset|必须保持已知的 offset|
|---|---|---|---|
|`LDST_S/LDST_V` contiguous|允许 X|没有 per-element offset；未使用 packed slice 允许 X|`offset[0]`|
|`LDSTE_S` strided|允许 X|没有 per-element offset；未使用 packed slice 允许 X|`stride=offset[0]`|
|`LDSTE_V` indexed|允许 X|对应独立 offset slice 允许 X|所有 mask=1 element 的 slice|

只要一个 active thread 仍有至少一个有效 element，contiguous 的起始 offset 和 strided 的
stride 就参与全部有效地址计算，不能因为某个 element 被 mask 而将共享 slice 置 X。

### 2.3 Direction 和 length 外 payload

- V2M 只解释有效 element 对应的 `D` 个 data byte；masked element data 允许 X；
- M2V 不解释 `creq_vdat`，active 和 inactive thread 的 data 都允许 X；
- length 范围外的 mask bit、data byte 和不被当前 topology 选择的 packed offset slice允许 X；
- `creq_vld==0` 时整个 payload 都是 don’t-care，但该规则继续由 monitor 组件测试覆盖，不发送
  成真实 DUT transaction。

## 3. 激励构造规则

### 3.1 两阶段构造

每笔真实 RTL X transaction 必须按以下顺序构造：

```text
1. randomize/generate 全部已知且合法的 topology item
2. pack_offsets()
3. validate_transaction()
4. 只对本计划定义的 don’t-care pin slice 注入 X
5. 不再 pack、randomize 或重新生成地址，直接通过 directed sequence 发送
```

注入发生在最终合法性验证之后，因为 validator 的职责是验证语义请求，X utility 的职责是
把语义上未被消费的 RTL pin slice 替换为四态值。注入后调用 `pack_offsets()` 会覆盖目标 X，
必须禁止。

### 3.2 可复用 utility

在 `ver_common/uvc/shmins_agent/sequences/` 增加无时间消耗的四态激励 utility，至少提供：

```text
poison_inactive_threads()
poison_masked_element_data()
poison_indexed_masked_offsets()
poison_unused_offset_slices()
poison_out_of_length_payload()
poison_m2v_vdata()
```

Utility 接受 `1'bx` 或 `1'bz`，但首批真实 RTL case 固定使用 X。每个 API 必须检查 thread、
element、length、itype 和 offset width，拒绝修改任何被解释的 slice。Utility 不修改内部
`offs_elem/elem_maddr/elem_physical_addr`，也不调用 generator 或 validator。

## 4. 验证环境消费边界修改

### 4.1 Driver 和 monitor

Driver 必须按四态赋值把 transaction payload 原样驱动到 interface。Monitor 应继续：

- 跳过 inactive thread 的全部 payload 检查；
- 只检查 length 范围内的 mask bit；
- 只检查 topology 实际选择的 offset slice；
- 只检查 V2M 有效 element 的有效 data byte；
- M2V 不检查 `creq_vdat`。

不得为了让 X case 通过而关闭或降级 `SHMINS_ACTIVE_PAYLOAD_XZ`。

### 4.2 Reference

Reference 必须在读取 don’t-care 值之前完成过滤：

1. inactive thread 在分配/计算 element 地址前跳过；
2. indexed masked element 在 `decode_packed_offset()` 前跳过；
3. masked V2M element 在读取 `creq_vdat` 前跳过；
4. contiguous/strided 只在存在有效 element 时解码共享 offset/stride；
5. length 外 element 不分配有效 address/strobe，也不读取 data/offset。

不能依赖把 X 赋给 two-state 临时变量后变为 0 来“通过”测试。组件测试必须证明过滤发生在
decode/data read 之前，且派生数组和 `wmap` 只包含有效 byte。

### 4.3 Coverage 分类

现有 active/inactive thread 粗粒度 X/Z 分类不足以区分合法 don’t-care X 和非法 interpreted
X。Coverage 至少拆分为：

```text
interpreted_payload_xz
inactive_thread_payload_xz
masked_element_data_xz
masked_indexed_offset_xz
out_of_length_payload_xz
m2v_unused_vdata_xz
```

真实 RTL 正例要求 `interpreted_payload_xz==KNOWN`，并命中对应 ignored/don’t-care X bin。
Coverage 只观察，不改变 checker、reference 或 DUT 输出。

## 5. 组件测试矩阵

组件测试不实例化真实 DUT，全部位于 `examples/`。

### 5.1 Utility 和 driver/monitor

|场景 ID|场景|预期|
|---|---|---|
|`X-UTIL-001`|inactive thread 五类 payload 全 X|只修改目标 thread；active payload不变|
|`X-UTIL-002`|contiguous/strided masked data 与未使用 offset slice X|共享 `offset[0]` 保持已知|
|`X-UTIL-003`|indexed masked data/offset X|mask=1 element data/offset 保持已知|
|`X-UTIL-004`|length 外 mask/data/offset X|length-bounded payload保持已知|
|`X-UTIL-005`|M2V active `creq_vdat` 全 X|地址、mask 和控制字段不变|
|`X-DRV-001`|连续发送 inactive-thread X 和 indexed masked-element X|monitor 收到两笔且四态值原样保留|
|`X-DRV-002`|上述两笔使用 `delay_cycle=0/1`|accept cycle 分别背靠背/包含一个空闲周期|

`X-DRV-001/002` 同时作为 cycle-based SHMINS driver 的首个有 transaction 组件证据。

### 5.2 Monitor 正负边界

每个非法场景单独驱动，使用 expected-report catcher 检查一次且仅一次
`SHMINS_ACTIVE_PAYLOAD_XZ`：

|场景 ID|注入位置|合法性|
|---|---|---|
|`X-MON-001`|inactive thread 全 X/Z|合法，无 report|
|`X-MON-002`|active masked V2M data X/Z|合法，无 report|
|`X-MON-003`|active indexed masked offset X/Z|合法，无 report|
|`X-MON-004`|active length-bounded mask bit X/Z|非法，精确一个 report|
|`X-MON-005`|active contiguous/strided shared offset X/Z|非法，精确一个 report|
|`X-MON-006`|active indexed mask=1 offset X/Z|非法，精确一个 report|
|`X-MON-007`|active V2M mask=1 data byte X/Z|非法，精确一个 report|
|`X-MON-008`|M2V active data 全 X/Z|合法，无 report|

### 5.3 Reference

|场景 ID|输入|判定|
|---|---|---|
|`X-REF-001`|inactive thread payload 全 X/Z|inactive 派生数组为空|
|`X-REF-002`|V2M masked data X/Z|`wmap` 只含 mask=1 byte，reference memory不被污染|
|`X-REF-003`|indexed masked offset X/Z|不解码、不映射 masked element|
|`X-REF-004`|contiguous/strided unused offset X/Z|共享已知 offset 正常产生有效地址|
|`X-REF-005`|M2V data 全 X/Z|read 和 writeback expected 与已知 data 基线一致|

## 6. 真实 RTL 测试矩阵

新增独立 `shm_payload_dontcare_x_test`，每个 cell 逐笔发送并在下一笔前调用
`shm_env.wait_for_idle()`。首轮不修改已经通过的 `shm_tmsk_directed_test`，以保留全已知
payload 基线。

### 6.1 Inactive-thread X：18 笔

|维度|取值|
|---|---|
|direction|V2M、M2V|
|space|LOC、WRP、BLK|
|tmsk|`16'h0001`、`16'h8000`、`16'h8421`|
|inactive payload|所有 inactive thread 的 prio/len/vmsk/offs/vdat 全 X|

总数为 `2 × 3 × 3 = 18`。全 mask 没有 inactive thread，不进入该矩阵。

### 6.2 Active masked-element X：12 笔

|维度|取值|
|---|---|
|direction|V2M、M2V|
|topology|contiguous、strided、indexed|
|atype width|16、32|
|space|LOC|
|dtype|DTYP_8|
|active thread|thread 0 和 thread 15|
|length/mask|8 element；element 0/7 active，1～6 masked|

总数为 `2 × 3 × 2 = 12`。每笔 transaction：

- V2M element 1～6 data 为 X；M2V 全部 `creq_vdat` 为 X；
- indexed element 1～6 offset slice 为 X；
- contiguous/strided 保留 offset 0，其余未使用 packed offset slice 为 X；
- length 外 mask/data/offset 为 X；
- element 0/7 的 mask、offset 和 V2M data保持已知。

第一批共 30 笔真实 RTL transaction。DTYP_16/32 的多 byte masked data 作为后续扩展，不
阻塞第一批验收。

## 7. 每笔真实 RTL transaction 的判定标准

每个 cell 必须同时满足：

1. driver/monitor 只发布一笔 transaction，目标 don’t-care slice仍为 X；
2. 不出现 `SHMINS_ACTIVE_PAYLOAD_XZ` 或其他未预期 UVM report；
3. interpreted-payload coverage 保持 known，目标 don’t-care X bin 精确增加；
4. reference active thread、element 和 byte 数与 tmsk/length/vmsk 一致；
5. inactive/masked element 不产生额外 reservation 或 MEM transaction；
6. V2M 只写入已知有效 byte，数据与 reference 一致；
7. M2V read 和 writeback 不依赖 X `creq_vdat`；
8. scoreboard 不出现 unexpected/missing/unresolved byte；
9. lifecycle 正常退休，测试 drain 后没有 pending transaction；
10. 最终 `UVM_ERROR: 0`、`UVM_FATAL: 0`，输出稳定 cell 和 test PASS marker。

## 8. 逐文件实施顺序

|顺序|文件或目录|修改|
|---:|---|---|
|1|`ver_common/uvc/shmins_agent/sequences/`|新增四态 don’t-care stimulus utility及 package include|
|2|`examples/shmins_sequence_compile/`|增加 utility 精确 slice 组件测试|
|3|`examples/shmins_driver_compile/` 或现有 SHMINS component harness|建立 sequencer→driver→interface→monitor 四态保真测试|
|4|`ut_shm/env/shm_wtrans_item.svh`、`ut_shm/env/shm_reference.svh`|在 decode/data read 前过滤 inactive/masked payload|
|5|`examples/shm_reference_compile/`|增加 masked offset/data、unused offset 和 M2V data X/Z 测试|
|6|`ver_common/uvc/shmins_agent/shmins_request_coverage.svh`|区分 interpreted 与各类 ignored X/Z|
|7|`examples/shmins_monitor_compile/`|补齐合法/非法四态边界矩阵|
|8|`ut_shm/tests/shm_payload_dontcare_x_test.svh`|实现 18+12 真实 RTL矩阵|
|9|test package、TC、独立 LST|登记新 test，暂不直接加入 `shm.lst`|
|10|status、testpoint、component 和 regression 文档|记录组件、RTL 和 coverage 实际证据|

必须按上述顺序先证明验证环境不会错误读取 don’t-care X，再把 X 发送到真实 DUT。否则 RTL
失败无法区分是 DUT 消费错误还是 reference/monitor 自身 X 处理错误。

## 9. EDA 验证顺序

### 阶段 A：组件门禁

1. utility slice 测试；
2. driver/monitor 四态保真和 `delay_cycle=0/1` 测试；
3. monitor 正负 report 矩阵；
4. reference masked/inactive/M2V data X/Z 测试；
5. 原 SHMINS copy、monitor、reference 组件测试无回归。

### 阶段 B：环境编译

1. 远端 VCS 空 design `make compile`；
2. `TRANS_NUM=0` smoke；
3. 检查新增 test、utility、coverage 和 package include 完整。

空 design 结果只能证明编译、elaboration 和 0-transaction 环境路径，不能作为 X 的 DUT
功能证据。

### 阶段 C：真实 RTL

1. 单独运行 inactive-thread X 的 18 个 cell；
2. 单独运行 masked-element X 的 12 个 cell；
3. 运行新独立 LST；
4. 保存目标 coverage bin/cross；
5. 重跑 `shmins_mask_directed.lst`、`p0_directed.lst` 和 `shm.lst`；
6. 全部通过并完成 coverage 复核后，再决定是否把新 test 纳入主列表。

## 10. 完成条件

本批完成需要：

1. `X-UTIL/DRV/MON/REF` 全部组件场景通过；
2. 合法 X 无误报，非法 interpreted X/Z 精确报告；
3. reference 在读取 data/offset 前完成 inactive/masked 过滤；
4. 30 笔真实 RTL transaction 全部通过；
5. required don’t-care X bin 命中并保存可回溯结果；
6. 三份已有 LST 无新增回归；
7. 文档更新实际命令、版本、seed、日志和剩余缺口。

完成本批可以补齐 inactive/masked payload 的四态边界，但不自动关闭整个 `SHMINS-006`：
公共控制字段和所有非法 active 字段的完整 X/Z 负例仍需按 `TP-CREQ-002` 单独复核。

## 11. 2026-08-18 实现与验证状态

阶段 A 和阶段 B 的静态入口已完成：

- 新增 `shmins_dontcare_x_util`，六个 API 只修改已验证 transaction 中的 don’t-care pin slice；
- reference 在 masked indexed offset decode、V2M data read 和 shared offset decode 前先过滤无效
  element；
- request coverage 已区分 interpreted、inactive、masked data、masked indexed offset、
  out-of-length 和 M2V-unused data 的 X/Z 类别；
- `X-UTIL-001`～`005`、`X-DRV-001/002`、`X-MON-001`～`008` 和
  `X-REF-001`～`005` 已在 hx16、VCS `T-2022.06-SP2-5_Full64` 编译并运行通过，
  各项最终均为 `UVM_ERROR: 0`、`UVM_FATAL: 0`；
- standalone reference harness 使用仅存在于 test package 的 byte-memory stand-in，
  生产 `shm_reference` 源码不变，组件运行不再依赖 VIP SLI server；
- 空 `RpuShmTop` 的完整 27-module parse、elaboration 和 simv link 通过，新 test、
  utility、coverage 和 package include 均进入编译。hx16 的 GNU Make 3.82 需用
  `make .SHELLFLAGS=-ec compile` 避免其对当前多段 `.SHELLFLAGS` 的兼容问题。

真实 RTL 用的 `shm_payload_dontcare_x_test`、根 TC 定义和独立
`shmins_dontcare_x.lst` 已实现，但 18+12 笔矩阵、目标 coverage bin 和三份既有 LST
无回归仍需在正式 design 环境执行。因此本批当前状态是“待验证”，不按空 design
编译结果宣称 DUT 功能通过。
