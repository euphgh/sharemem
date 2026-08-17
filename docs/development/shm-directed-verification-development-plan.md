# SHMINS thread-mask 定向验证开发计划

本文根据 [验证实现状态](../ut_shm/verification-status.md)、
[Testpoints](../ut_shm/plan/testpoints.md)和
[creq/ack 接口规范](../ut_shm/spec/creq-ack-interface.md)，规定第三批
`SHMINS-001` thread-mask 定向验证的实现顺序、测试矩阵和判定标准。

此前双 gid P0 的实现结果和未决 DUT ownership 问题由
[验证实现状态](../ut_shm/verification-status.md)继续跟踪，不在本文重复保留。本文只描述
当前 `SHMINS-001` 开发，不改变 DUT contract，也不把非法输入的 DUT 行为定义成新规范。

## 1. 目标与范围

本批需要为以下行为提供可重复证据：

1. 普通请求支持单 thread 0、单 thread 15、稀疏 mask 和全 mask；
2. inactive thread 不生成 MADDR、reservation、MEM 或 M2V 写回；
3. inactive thread 的 `creq_prio/len/vmsk/offs/vdat` 可以包含 X/Z；
4. `creq_tmsk=='0` 被 monitor 准确报告为非法输入；
5. VTRANS 必须使用全 thread mask、全 element mask 和固定 element 数；
6. coverage 能区分 mask 类型、thread 边界、方向、space 和 VTRANS 组合。

本批主要关闭 `SHMINS-001` 和 `TP-CREQ-003`。为证明 inactive payload 的 X/Z 是被
选择性忽略，而不是 monitor 完全不检查 payload，本批同时实现 `SHMINS-006` 所需的
active/inactive thread 局部检查基础，但不因此自动关闭完整 `SHMINS-006` 或 `COV-001`。

以下内容不属于本批：

- `FFD_CYC` read snapshot；
- 运行中 reset；
- ack、credit 和 priority 压力；
- length/vmsk 所有边界组合；
- 向真实 DUT 注入全零 tmsk 或 X/Z payload；
- 全项目 coverage merge 或总百分比阈值。

## 2. 验证分层与共同规则

### 2.1 组件测试与真实 RTL 测试的边界

- monitor report、全零非法输入、tmsk X/Z、active payload X/Z 和 inactive payload X/Z
  放在 `examples/`；
- reference 对 inactive thread 派生数组的抑制也在 `examples/` 独立验证；
- 只有合法 mask 的 DUT 访问抑制和 VTRANS 数据转置放在 `ut_shm/tests/`；
- 空 design 只能作为编译、连接和 elaboration 证据，不能作为 DUT 行为证据；
- 新真实 RTL case 先进入独立 directed LST，不直接加入 `shm.lst`。

### 2.2 定向激励规则

定向场景必须显式固定 tmsk、方向、space、dtype、itype、length 和 element mask。随机器只
生成满足这些固定条件的合法地址，不允许依赖 seed 恰好命中目标 mask。

普通 mask 的真实 RTL 测试先以全 thread active 生成合法 payload、offset 和 MADDR，再把
最终 `creq_tmsk` 缩小到目标 mask。这样 inactive thread 仍保留合法且可区分的 sentinel
payload；如果 DUT 错误执行 inactive thread，checker 可以观察到额外访问。修改 mask 后
必须重新执行最终 validator，但不能重新生成或清除 inactive payload。

### 2.3 预期负例规则

组件负例复用 `examples/common/shm_expected_report_catcher.svh`。每个负例必须同时满足：

- 指定 report ID 出现准确次数；
- 没有未声明的 `UVM_ERROR/UVM_FATAL`；
- 缺失 report 或 report 次数过多都使测试失败；
- 测试输出独立场景 PASS marker；
- 脚本检查进程返回值和最终 PASS marker。

全零 tmsk 是 monitor 协议检查，不作为真实 DUT case。Monitor 报告一次
`SHMINS_TMSK_ZERO` 后必须立即丢弃该 sample，不分配 transaction UID、不递增已发布事务
计数，也不写入 production analysis port。因此 reference、scoreboard、lifecycle checker 和
production coverage 都不能收到全零事务。全零 coverage bin 只能由组件 harness 直接调用
coverage subscriber 采样，不得依赖生产数据流发布非法事务。

## 3. 行为 contract 与判定边界

### 3.1 普通请求

当 `creq_vld==1` 时，普通请求必须满足：

```text
creq_tmsk 已知且 creq_tmsk != '0
```

只有 `creq_tmsk[t]===1'b1` 的 thread 才能形成有效地址和数据访问。inactive thread 的
payload 是 don't-care，允许包含 X/Z，monitor 和 reference 都不能解释这些值。

### 3.2 Active payload 四态检查

monitor 先检查 `creq_tmsk`。tmsk 未知时只报告 tmsk 错误，不继续按未知 mask 分类
thread。tmsk 已知后，检查 active thread 实际参与解释的字段：

- `creq_prio[t]` 和 `creq_len[t]`；
- 有效 element 范围内的 `creq_vmsk[t]`；
- 对当前 itype 和 active element 实际使用的 offset slice；
- V2M 中由 length 和 vmsk 选中的有效 `creq_vdat[t]` byte。

M2V 不解释 `creq_vdat`，inactive thread 不检查任何上述 per-thread payload。active
payload X/Z 使用稳定 report ID `SHMINS_ACTIVE_PAYLOAD_XZ`，消息必须包含 thread、字段和
有效 slice。公共控制字段的完整四态矩阵仍由 `SHMINS-006` 后续工作跟踪。

### 3.3 VTRANS

VTRANS 正例必须同时满足：

```text
creq_tmsk == '1
foreach thread: elem_num == 16
foreach thread: creq_vmsk == '1
DTYP_8 : creq_len == 16 Byte
DTYP_16: creq_len == 32 Byte
```

本批不向 DUT 发送违反上述规则的 VTRANS。sequence item 约束和 monitor 组件检查负责
证明输入限制，真实 RTL case 负责证明全 mask 下的转置数据正确。

## 4. 组件测试矩阵

组件测试建议新增到：

```text
examples/shmins_monitor_compile/
```

Harness 直接驱动 `shmins_interface`，连接 production monitor、一个 transaction
subscriber 和必要的 coverage/reference 组件，不实例化真实 DUT。

### 4.1 Monitor 与四态矩阵

除表中明确注入的字段外，公共字段和 active payload 均使用合法已知值。

|场景 ID|`creq_vld`|请求类型|`creq_tmsk`|注入内容|预期 report|transaction/reference 判定|
|---|---:|---|---:|---|---|---|
|`MON-MASK-001`|1|普通|`16'h0001`|无|无|发布一次；只有 thread 0 active|
|`MON-MASK-002`|1|普通|`16'h8000`|无|无|发布一次；只有 thread 15 active|
|`MON-MASK-003`|1|普通|`16'h8421`|无|无|发布一次；active thread 为 0、5、10、15|
|`MON-MASK-004`|1|普通|`16'hffff`|无|无|发布一次；16 个 thread active|
|`MON-MASK-005`|1|普通|`16'h0000`|无|一次 `SHMINS_TMSK_ZERO`|monitor 丢弃；不分配 UID、不发布；无额外 error|
|`MON-MASK-006`|1|普通|含 X/Z|只修改 tmsk|一次 `SHMINS_TMSK_XZ`|不继续报告 per-thread payload 错误|
|`MON-MASK-007`|1|普通|`16'h0001`|thread 1～15 payload 全 X|无|sample 保留四态值；inactive 派生数组为空|
|`MON-MASK-008`|1|普通|`16'h0001`|thread 1～15 payload 全 Z|无|sample 保留四态值；inactive 派生数组为空|
|`MON-MASK-009`|1|普通|`16'h0001`|active thread 0 的 `creq_len` 含 X|一次 `SHMINS_ACTIVE_PAYLOAD_XZ`|证明 active/inactive 检查边界有效|
|`MON-MASK-010`|0|任意|X/Z|全部 payload X/Z|无|monitor 不采样、不发布、不检查 payload|

`MON-MASK-007/008` 送入 `shm_wtrans_item::init_from()` 后还必须检查：

- thread 0 按 length/vmsk 生成期望地址；
- thread 1～15 的 BADDR、BANK、gid、logical address 和 strobe 动态数组长度均为 0；
- reference 不读取 inactive thread 的 offset、length、mask 或 data；
- 整个组件测试没有 UVM error/fatal。

### 4.2 VTRANS sequence-item 矩阵

|场景 ID|dtype|itype|预期 tmsk|预期 length/thread|预期 vmsk/thread|判定|
|---|---|---|---:|---:|---:|---|
|`SEQ-VTRANS-001`|`DTYP_8`|`LDST_S`|`16'hffff`|16 Byte|全 1|randomize、validate、copy 通过|
|`SEQ-VTRANS-002`|`DTYP_8`|`LDST_V`|`16'hffff`|16 Byte|全 1|randomize、validate、copy 通过|
|`SEQ-VTRANS-003`|`DTYP_16`|`LDST_S`|`16'hffff`|32 Byte|全 1|randomize、validate、copy 通过|
|`SEQ-VTRANS-004`|`DTYP_16`|`LDST_V`|`16'hffff`|32 Byte|全 1|randomize、validate、copy 通过|

这些场景可以加入现有 `examples/shmins_sequence_compile/`，不需要复制完整 sequence-item
编译环境。

## 5. Functional coverage

新增可复用的 `shmins_request_coverage` subscriber，放在
`ver_common/uvc/shmins_agent/`，由 `shmins_mst_agent` 在 monitor 存在时创建并连接。
Coverage 只读消费 monitor transaction，不重新计算地址或决定 transaction 合法性。

### 5.1 Coverpoint

- request kind：normal、VTRANS；
- direction：V2M、M2V；
- space：LOC、WRP、BLK；
- tmsk class：unknown、zero、single、sparse、full；
- tmsk population：0、1、2～15、16；
- active thread index：0、15、middle；
- inactive payload X/Z：none、X、Z；
- active payload X/Z：none、present；
- VTRANS dtype：DTYP_8、DTYP_16；
- VTRANS itype：LDST_S、LDST_V。

### 5.2 Required cross

```text
normal direction × space × legal tmsk class
single-thread index × direction
VTRANS dtype × VTRANS itype × full tmsk
tmsk class × inactive payload X/Z category
```

Illegal/unknown tmsk 由组件测试命中；真实 RTL case 只负责 normal legal cross 和 VTRANS
cross。本批要求保存这些目标 bin/cross 的命中证据，但不要求全项目 coverage merge。

## 6. 真实 RTL 普通 mask 测试矩阵

新增 `shm_tmsk_directed_test`。所有 transaction 固定：

```text
creq_info    = normal
creq_itype   = LDST_S
creq_dtype   = DTYP_8
creq_atype_w = ATYP_32
creq_atype_s = ATYP_U
creq_atype_g = GAUTO_1B
elem_num[t]  = 1
creq_len[t]  = 1 Byte
creq_vmsk[t] = bit 0 only
```

每笔 transaction 先以 `creq_tmsk=='1` 生成 16 个 thread 的合法地址和互异数据
signature，再把 mask 改为下表目标值并执行最终 validator。M2V 生成阶段开启 byte-level
uniqueness，确保 sentinel read 地址和 writeback 地址满足既有 hazard contract。

### 6.1 Mask 定义

|Mask ID|值|active thread|用途|
|---|---:|---|---|
|`M0`|`16'h0001`|0|最低 thread 边界|
|`M15`|`16'h8000`|15|最高 thread 边界|
|`MS`|`16'h8421`|0、5、10、15|跨低、中、高 index 的稀疏模式|
|`MF`|`16'hffff`|0～15|普通请求全 mask|

### 6.2 24 笔 transaction 矩阵

下表每个 cell 分别执行 `M0/M15/MS/MF` 四笔 transaction，不允许按 seed 抽样。

|方向|SPACE_LOC|SPACE_WRP|SPACE_BLK|小计|
|---|---|---|---|---:|
|V2M|`M0/M15/MS/MF`|`M0/M15/MS/MF`|`M0/M15/MS/MF`|12|
|M2V|`M0/M15/MS/MF`|`M0/M15/MS/MF`|`M0/M15/MS/MF`|12|
|总计|8|8|8|24|

每笔 transaction 名称必须包含方向、space 和 mask ID，例如
`v2m_loc_m0`、`m2v_blk_ms`，使 timeout、scoreboard 和波形日志可以直接定位矩阵 cell。

Test 必须逐笔发送并在每笔之后调用 `shm_env.wait_for_idle()`，不能把 24 笔全部并发发出后
只检查最终汇总。发送前后分别保存 request coverage 和
`shm_address_coverage.sampled_active_byte_count`，用计数增量判定当前 cell；这样一旦失败，
日志、coverage counter 和 scoreboard pending state 都只对应一笔 transaction。

### 6.3 每笔 transaction 的判定标准

每笔普通 mask transaction 必须同时满足：

1. monitor 采样到的 tmsk 等于目标值；
2. reference active-thread 数等于 `$countones(creq_tmsk)`；
3. reference active-byte 数等于 `$countones(creq_tmsk)`，因为每个 active thread 只有一个 byte；
4. inactive thread 的派生数组为空；
5. DUT 不产生 expected wmap 之外的 reservation、MEM 或 M2V 写回；
6. V2M 的每个 active signature byte 写入正确物理地址；
7. M2V 的每个 active read byte 和 writeback byte与 reference 一致；
8. transaction 能被 scoreboard 和 lifecycle checker 完整退休；
9. 没有未预期 UVM error/fatal；
10. 对应 direction × space × mask-class coverage bin 命中。

第 5 项是 inactive 抑制的主要 DUT 判据。生成阶段保留的 inactive sentinel payload 必须与
active expected 地址可区分；如果 DUT 忽略 tmsk，额外访问必须表现为 unexpected
reservation/MEM、额外 writeback 或 scoreboard 数据差异，不能被 active expected byte
吸收。

## 7. 真实 RTL VTRANS 矩阵

新增 `shm_vtrans_full_mask_test`，发送以下四笔 transaction：

|场景 ID|dtype|itype|tmsk|每 thread element 数|每 thread vmsk|
|---|---|---|---:|---:|---:|
|`RTL-VTRANS-001`|`DTYP_8`|`LDST_S`|`16'hffff`|16|全 1|
|`RTL-VTRANS-002`|`DTYP_8`|`LDST_V`|`16'hffff`|16|全 1|
|`RTL-VTRANS-003`|`DTYP_16`|`LDST_S`|`16'hffff`|16|全 1|
|`RTL-VTRANS-004`|`DTYP_16`|`LDST_V`|`16'hffff`|16|全 1|

每笔 VTRANS 必须同时满足：

1. 发送前显式检查 tmsk、所有 length 和所有 vmsk；
2. monitor transaction 保持相同限制；
3. reference 生成 16×16 element 的转置 expected data；
4. scoreboard 检查全部有效 byte 写入正确；
5. 没有 inactive thread、缺失 byte 或额外 byte；
6. transaction 和 ack/lifecycle 正常退休；
7. 对应 dtype × itype × full-mask coverage bin 命中；
8. 没有未预期 UVM error/fatal。

## 8. 逐文件实施计划

|顺序|文件或目录|修改|
|---:|---|---|
|1|`ver_common/uvc/shmins_agent/shmins_monitor.svh`|抽取 tmsk 和 active/inactive payload 四态检查，保留已有 tmsk report ID|
|2|`ver_common/uvc/shmins_agent/shmins_request_coverage.svh`|新增本批 mask/VTRANS coverpoint、cross 和可查询计数|
|3|`ver_common/uvc/shmins_agent/shmins_mst_agent.svh`、`ut_shm/env/shm_env_package.sv`|创建、include 并连接 request coverage subscriber|
|4|`examples/shmins_monitor_compile/`|新增 monitor、全零和 inactive/active X/Z 组件测试与脚本|
|5|`examples/shmins_sequence_compile/`|补四个 VTRANS constraint/copy 场景|
|6|`ut_shm/tests/shm_directed_base_test.svh`|增加从全 mask 合法 transaction 缩小为目标 mask 的复用 builder|
|7|`ut_shm/tests/shm_tmsk_directed_test.svh`|实现 24 笔 normal mask 矩阵|
|8|`ut_shm/tests/shm_vtrans_full_mask_test.svh`|实现四笔 VTRANS 全 mask 矩阵|
|9|`ut_shm/tests/shm_test_package.sv`|include 两个新 test|
|10|`ut_shm/tc/shmins_mask_directed.tc`|登记两个真实 RTL test 及必要 timeout 配置|
|11|`ut_shm/regression/shmins_mask_directed.lst`|建立独立 directed list|
|12|状态、testpoint、component 和 regression 文档|记录实际命中证据与剩余缺口|

新 class、成员和 function/task 必须遵循
[SystemVerilog/UVM 开发规范](systemverilog-code-style.md)，特别是 120 字符目标、class
职责注释、成员语义和完整 `@brief/@param/@return` contract。

## 9. 实施与验证顺序

### 阶段 A：Monitor contract

1. 实现 tmsk 和 active/inactive payload helper；
2. 保证 tmsk 未知时不继续产生级联 payload 错误；
3. 运行 `MON-MASK-001`～`010`；
4. 确认预期 report ID 和次数精确。

阶段 A 未通过时，不修改 production environment 的 coverage 连接。

### 阶段 B：Reference 与 coverage

1. 验证 inactive X/Z transaction 的派生数组为空；
2. 实现 request coverage subscriber；
3. 用组件矩阵命中 zero、unknown、single、sparse、full 和 inactive X/Z bin；
4. 运行已有 SHMINS copy/random benchmark，确认 monitor/coverage 修改无回归。

### 阶段 C：真实 RTL stimulus

1. 实现 masked transaction builder；
2. 在 test 内先检查 builder 保留了 inactive sentinel payload；
3. 实现并编译 `shm_tmsk_directed_test`；
4. 实现并编译 `shm_vtrans_full_mask_test`；
5. 建立独立 TC 和 LST。

### 阶段 D：EDA 编译门禁

同步所需源码到 EDA 服务器后执行：

1. SHMINS monitor component tests；
2. SHMINS sequence compile/copy/VTRANS component tests；
3. reference component tests；
4. ut_shm 空 design compile/elaboration；
5. 0-transaction smoke。

这些结果只证明验证代码可编译、组件 contract 正确和环境连接完整。

### 阶段 E：真实 RTL 验收

1. 单独运行 `shm_tmsk_directed_test`；
2. 单独运行 `shm_vtrans_full_mask_test`；
3. 检查所有矩阵 cell 的事务级日志和 coverage bin；
4. 运行独立 `shmins_mask_directed.lst`；
5. 重新运行原 109-case `shm.lst`；
6. 保存命令、seed、日志、UVM 汇总和目标 coverage 结果；
7. 更新 verification status 和 testpoint。

## 10. 完成条件

只有同时满足以下条件，才能关闭 `SHMINS-001`：

1. `MON-MASK-001`～`010` 和 `SEQ-VTRANS-001`～`004` 全部通过；
2. 全零 tmsk 和 active payload X/Z 只产生指定 report，次数准确；
3. inactive payload X/Z 不产生误报，reference 不访问 inactive payload；
4. 普通请求 24 个真实 RTL matrix cell 全部通过；
5. 四个 VTRANS 真实 RTL matrix cell 全部通过；
6. checker 没有观察到 inactive thread 对应的额外 reservation、MEM 或 writeback；
7. 本批 required coverage bin/cross 命中并保存可回溯证据；
8. 原 109-case `shm.lst` 无新增 error/fatal；
9. 文档同步实际结果和仍未覆盖的 `SHMINS-006/COV-001` 范围。

完成本批不自动关闭完整 `SHMINS-006`，因为公共字段、valid 为 0 的所有字段类别和其他
active payload slice 仍需按其独立验收范围复查；也不自动关闭全项目 `COV-001`。

## 11. 2026-08-15 实施快照

阶段 A～D 的代码和静态门禁已完成：

- production monitor 已实现全零 tmsk 报告后丢弃、tmsk X/Z 检查以及 active-thread
  payload 局部四态检查；
- `shmins_request_coverage` 已接入 master agent，提供 mask、active thread、方向、space 和
  VTRANS 的 coverpoint、cross 与事务级可查询计数；
- `examples/shmins_monitor_compile/` 的 `MON-MASK-001`～`010` 在远端 VCS
  `W-2024.09-SP1_Full64` 运行通过，三个预期 error 均被准确捕获并降级，最终
  `UVM_ERROR: 0`、`UVM_FATAL: 0`；
- `examples/shmins_sequence_compile/` 的四个 VTRANS dtype/itype 组合、copy 和 lifecycle
  组件测试通过；reference gid-isolation 组件测试加入 inactive payload X/Z 场景后通过；
- `shm_tmsk_directed_test`、`shm_vtrans_full_mask_test`、TC 和独立 LST 已实现；远端
  `make compile` 使用空 design 完成 parse、elaboration 和 simv link。

阶段 E 尚未执行，因此当前证据不能关闭 `SHMINS-001`：仍需在真实 RTL 上运行 24 个
normal mask cell、四个 VTRANS cell、保存目标 coverage 命中，并确认原 109-case
`shm.lst` 无回归。
