# SHM 定向验证开发计划

本文根据 [验证实现状态](../ut_shm/verification-status.md)和
[Testpoints](../ut_shm/plan/testpoints.md)，规定 109-case 正向主列表通过后的定向验证
实施顺序。本计划不再扩充已有 `direction × itype × space × dtype × atype_w`
普通矩阵，而是优先建立可重复的边界激励、独立 checker、功能覆盖和真实 RTL case。

DUT 行为仍以 [DUT spec](../ut_shm/spec/index.md) 为准。本文只规定验证基础设施、
组件测试、真实 RTL case 和验收证据，不从当前验证代码反向定义 DUT 规则。

## 1. 目标与优先级

| 批次 | 问题 ID | 主要目标 | 进入条件 |
|---:|---|---|---|
| 1 | `DBANK-001/002/004` | 双 gid 地址边界、数据隔离、busy ownership、MEM resolver | 当前实现和 109-case 基线 |
| 2 | `VMEM-001` | `FFD_CYC` read snapshot 和同 BANK read/write 时序 | 第 1 批的 gid-aware memory 路径可信 |
| 3 | `SHMINS-001` | thread mask 边界、inactive payload 和 X/Z | 定向 request 发送基础设施可用 |
| 4 | `ENV-001` | 运行中 reset 取消全部 pending state | 主数据路径定向 case 稳定 |

`COV-001` 虽然是 P1，但覆盖采样接口必须与每批 P0 测试一起实现。不先实现
一个覆盖大全，而是只增加本批 testpoint 要求的 bin/cross，并保证每个 bin 能回溯到
稳定 testpoint ID。

## 2. 全批次共同规则

### 2.1 测试存放位置

- 纯函数、sequence item、reference、checker、scheduler、resolver 和 coverage 测试放在
  `examples/`，不使用真实 DUT 行为作为组件验收依据。
- 只有需要观察真实 RTL 地址、reservation、MEM 和数据行为的 UVM test 放在
  `ut_shm/tests/`。
- 组件测试不进入 TC/LST。真实 RTL case 先进入独立 directed LST，稳定后再由
  `shm.lst` include。

### 2.2 定向不等于固定 seed

定向场景必须在激励中显式固定关键字段或构造明确的周期事件。不允许依赖
随机 seed 恰好命中 wpid 3/4、相同 BADDR、other-gid busy 或 address mismatch。固定 seed
只用于失败复现。

### 2.3 独立期望值

- 地址测试的期望值用 testbench 内的明确整数公式计算，不得调用被测 helper
  生成 expected 后再与自身比较。
- Reference 测试使用两组可区分的数据 pattern，并分别读回 gid 0/1 的实际存储值。
- Reservation 测试直接检查结构化 outcome、gid metadata 和 scheduler state，不以日志字符串
  作为唯一判定。

### 2.4 正例与预期负例

新增 `examples/common/shm_expected_report_catcher.svh`，只允许测试声明的 report ID 和次数
被降级并计数。未声明的 `UVM_ERROR/UVM_FATAL`、缺失的预期 report 或额外次数都使
测试失败。不使用全局 severity override 吞掉所有错误。

每个组件脚本同时检查：

- 场景级 PASS marker；
- 预期 report ID 和准确次数；
- `UVM_ERROR: 0`、`UVM_FATAL: 0`；
- 进程返回值非零时必须失败。

## 3. 第一批范围：双 gid 定向验证

第一批要完成的 testpoint 映射如下。

| 问题 ID | Testpoint | 本批证据 |
|---|---|---|
| `DBANK-001` | `TP-ADDR-004/005/006/009`、`TP-DATA-002` | 逻辑/物理地址边界、M2V vaddr 和 byte hazard |
| `DBANK-002` | `TP-DATA-001/002/003`、`TP-MEM-005` | 相同 bank/BADDR 不同 gid 的 expected memory 隔离 |
| `DBANK-004` | `TP-MEM-005`、`TP-RSV-002/003/004/006/007/008` | busy ownership、port conflict、gid resolver 和失败路径 |
| `DBANK-005` | 上述 testpoint 的 coverage | 本批需要的 bin/cross 与 directed case 组织 |

### 3.1 先解决的 contract 记录不一致

[creq/ack spec](../ut_shm/spec/creq-ack-interface.md#6-vtrans) 允许 VTRANS
`creq_wpid inside {[0:WARP_N-1]}`，正式 `shmins_vtrans_sequence_item` 也没有把 wpid 固定为 0。
[Testcase 文档](../ut_shm/plan/testcases-and-regression.md) 目前把 VTRANS 写成 `creq_wpid==0`。

本批实现前先按 spec 修正 testcase 文档，并把 VTRANS wpid 3/4 纳入地址和 reference
组件测试。如果设计后续要求 VTRANS 只允许 wpid 0，必须先修改 spec，不能只改激励。

## 4. 第一批基础设施修改

### 4.1 可复用的 M2V byte-hazard 判定

当前 M2V read/write byte-overlap 判定只嵌在 `generate_m2v_writeback_address()` 中。
`validate_transaction()` 不复查 `creq_vaddr`，因此测试修改或 monitor 重建后的 item
无法使用同一 contract 验证 M2V hazard。

计划修改 `ver_common/uvc/shmins_agent/sequences/shmins_sequence_item.svh`：

1. 新增无副作用的 `m2v_writeback_byte_overlap(candidate_vaddr)` 或等价谓词；
2. 谓词按完整 `<bank,gid,BADDR>` byte key 建立 read/write 集合；
3. `generate_m2v_writeback_address()` 只负责枚举 candidate，并调用该谓词；
4. `validate_transaction()` 对最终 `creq_vaddr` 再次调用该谓词；
5. 检查粒度仍为 byte，同一 32-Byte beat 内不重叠的 byte 必须允许。

新增 API 必须按 SystemVerilog 规范补齐 `@brief/@param/@return`，并不得改变已有
随机生成分布以外的 transaction 字段。

### 4.2 定向 request 发送层

在 `ut_shm/tests/` 新增 test-only `shm_directed_item_sequence.svh`，并由
`shm_test_package.sv` include。该 sequence：

- 接收已经通过正式 topology item `randomize()` 和 `validate_transaction()` 的 request；
- 只执行 `start_item/finish_item`，不再修改 request 字段；
- 拒绝 null handle、非 topology 子类或 `validation_error_count!=0` 的 request；
- 不修改 `shmins_mst_unit_sequence` 对外 API，不把所有定向字段扩展成全局 plusarg。

后续真实 RTL test 使用 test-local builder 创建 request，显式固定 wpid、wpnum、
inv_size、tmsk、length 和 mask。对需要两笔共享 MADDR 但分属 gid 0/1 的场景，
允许 clone 已验证 item 后只改 wpid，但必须重新回填地址并执行最终 validator。

### 4.3 Reservation 结构化 outcome

当前 `vlm_reservation_check_result_t` 只有汇总 error count 和 MEM gid/match metadata。
它不能让组件测试和 coverage 稳定区分：

- target-gid busy；
- other-gid historical pending conflict；
- 同周期双 write-port conflict；
- unexpected、missing、address mismatch 和正常 match。

计划修改：

| 文件 | 修改 |
|---|---|
| `vlm_reservation_types.svh` | 增加 reservation admission outcome 和 MEM match outcome enum，并在 check result 中增加逐 direction/BANK/port 结果 |
| `vlm_reservation_checker.svh` | 在保留现有 report ID 和计数的同时，填写每个结构化 outcome |
| `vlm_reservation_coverage.svh` | 只采样 transaction、check result 和 pre-update scheduler view，不重新实现 checker 规则 |
| `vlm_reservation_agent.svh` | 继续把同一 immutable result 传给 coverage 和 MEM publisher，不新增第二次 resolver |

Outcome 是只读诊断和 coverage metadata，不得参与 scheduler 是否接受 request 的决策。

### 4.4 第一批 functional coverage

#### Address/reference coverage

新增 `ut_shm/env/shm_address_coverage.svh`，通过 analysis export 只读消费
`shm_wtrans_item`。`shm_reference.wdata_ass_arr_port` 同时连接 scoreboard 和 coverage，
不改变 reference 生成和 scoreboard 比对顺序。

本批只实现：

- direction；
- SPACE；
- absolute warp bins `0/3/4/7`；
- gid `0/1`；
- laddr `0/interior/WARP_STEP-1`；
- wpid-derived group，以及 BLK wpnum `1/2/4`；
- `space × absolute warp boundary × gid × laddr boundary`；
- M2V read gid × write gid。

#### Reservation coverage

在已有 `vlm_reservation_coverage` 中实现：

- direction、BANK、gid、subbank 和 delay；
- busy source `none/external/SHM`；
- admission outcome；
- MEM match outcome 和 resolved gid；
- `candidate gid × other-gid owner × same/different bank × outcome`；
- `direction × gid × match outcome`。

不在本批创建所有 SHM coverage。Mask、ack、FFD_CYC 和 reset 覆盖分别留给后续批次。

## 5. 第一批组件测试

### 5.1 地址和 M2V hazard 测试

在 `examples/shmins_sequence_compile/` 新增 `dual_gid_address_tb.sv`，并为
`scripts/ubuntu/check_shmins_sequence_vcs.sh` 增加 `dual-gid-address` target。

#### 物理 helper 场景

- BANK 0/15；
- absolute warp 0/3/4/7；
- laddr 0 和 `WARP_STEP-1`；
- 检查 `gid=warp/4` 和 `BADDR=(warp%4)*WARP_STEP+laddr`；
- warp 0/4 得到相同 BADDR、不同 gid；
- `warp==WARP_N`、`laddr==WARP_STEP` 和越界 BANK 必须被拒绝。

#### SPACE 映射场景

- LOC：thread 0/15，wpid 3/4，MADDR 0 和最后一个 dtype-aligned 地址；
- WRP：最小/最大 interleave，BANK 首尾，12 KiB 空洞两侧；
- BLK：wpnum 1/2/4，wpid 0/3/4/7，group 内编码 0/上界前一个 aligned 值/上界非法值；
- VTRANS：wpid 3/4 继续使用 LOC 地址映射并分别落到 gid 0/1。

#### M2V byte hazard 场景

- read/write 完全相同 byte：拒绝；
- 只重叠 1 byte：拒绝；
- 两个 byte range 恰好相邻：允许；
- 同一 32-Byte beat 内不重叠：允许；
- 相同 BANK/BADDR 但 gid 不同：不构成 overlap；
- wpid 3/4 的 writeback WARP 首尾均不能越出 12 KiB。

PASS 条件是所有固定场景与独立 expected 公式一致，预期非法项只产生指定
report，并输出 `[SHMINS_DUAL_GID_ADDRESS_TEST] ... PASS`。

### 5.2 Reference gid 隔离测试

新增 `examples/shm_reference_compile/`：

```text
examples/shm_reference_compile/
├── README.md
├── gid_isolation_tb.sv
└── build/                 # ignored generated output
```

新增 `scripts/ubuntu/check_shm_reference_vcs.sh`，使用已有 UVM/SVT memory 编译环境，
但不实例化或不依赖真实 DUT 行为。

测试场景：

1. 创建两笔物理 BANK 和 BADDR 相同、wpid 分别为 0/4 的 V2M transaction；
2. 两笔 transaction 使用不同 byte pattern，依次送入 `shm_reference`；
3. 直接读回 `ref_banks[bank][0/1]`，证明两个 gid 互不覆盖；
4. 检查两笔 `shm_wtrans_item.wmap` 的 flattened storage index 不同；
5. 分别从 gid 0/1 的相同 BADDR 执行 M2V read，确认返回各自 pattern；
6. 覆盖 M2V wpid 3/4，检查 v-write gid 和 `creq_vaddr + byte_offset`；
7. 覆盖 VTRANS wpid 3/4，检查转置数据与物理 gid 都正确。

PASS 条件是两个 reference memory 的目标 byte 均为独立 expected pattern，wmap 无 key
合并，并输出 `[SHM_REFERENCE_GID_TEST] ... PASS`。

### 5.3 Reservation ownership 和 resolver 测试

在 `examples/vlm_reservation_compile/` 新增 `gid_contract_tb.sv`，并为
`scripts/ubuntu/check_vlm_reservation_vcs.sh` 增加 `gid-contract` target。一次编译可以包含多个
受控 scenario，但每个 scenario 必须有独立名称、期望 outcome 和计数。

#### Busy/admission 场景

- target gid external busy 且 DUT 仍发 request：`TARGET_BUSY`；
- other gid external busy：当前 request 可接受；
- other gid、same bank/due 存在 DUT pending record：`PENDING_BANK_DUE_CONFLICT`；
- 同周期两个 write port 对同 bank/due 发 request：`CURRENT_BANK_DUE_CONFLICT`；
- 上一场景交叉 same/different gid 和 same/different subbank；
- 不同 BANK 使用相同 direction/delay/gid/subbank slot：合法；
- 同 BANK 同 due 的 read 和 write：方向独立，合法。

#### MEM resolver 场景

- 到期 record 与 MEM 完整地址相同：`MATCHED`，gid valid 且等于 record gid；
- MEM 到来但无 record：`UNEXPECTED`，gid invalid；
- record 到期但无 MEM：`MISSING`；
- BANK/direction 对应但完整地址不同：`ADDRESS_MISMATCH`，gid invalid；
- gid 0/1 在相同 BADDR 上分别正常 match；resolver 必须返回对应 record gid；
- Agent 发布的 unmatched memory transaction 必须保持
  `gid_valid==0 && reservation_matched==0`，不能伪造可信 metadata。

PASS 条件是每个 scenario 的结构化 outcome、scheduler 前/后状态、report ID 和 MEM
metadata 全部匹配，并输出 `[VLM_GID_CONTRACT_TEST] ... PASS`。

## 6. 第一批逐文件修改清单

| 顺序 | 文件 | 操作 |
|---:|---|---|
| 1 | `docs/ut_shm/plan/testcases-and-regression.md` | 修正 VTRANS wpid 记录 |
| 2 | `ver_common/uvc/shmins_agent/sequences/shmins_sequence_item.svh` | 抽取 M2V byte-overlap 谓词，生成器和 validator 共用 |
| 3 | `ver_common/uvc/vlm_reservation_agent/vlm_reservation_types.svh` | 增加逐端口 admission/match outcome |
| 4 | `ver_common/uvc/vlm_reservation_agent/vlm_reservation_checker.svh` | 填写 outcome，保留已有 report ID |
| 5 | `ver_common/uvc/vlm_reservation_agent/vlm_reservation_coverage.svh` | 实现本批 reservation bin/cross |
| 6 | `ut_shm/env/shm_address_coverage.svh` 及 package/environment | 新增 address/reference coverage 订阅者 |
| 7 | `examples/common/shm_expected_report_catcher.svh` | 新增严格预期错误工具 |
| 8 | `examples/shmins_sequence_compile/dual_gid_address_tb.sv` | 新增地址和 M2V hazard 组件测试 |
| 9 | `examples/shm_reference_compile/` | 新增 reference gid 隔离组件测试 |
| 10 | `examples/vlm_reservation_compile/gid_contract_tb.sv` | 新增 ownership/resolver 组件测试 |
| 11 | `scripts/ubuntu/check_*_vcs.sh` | 增加新 target、PASS marker 和 `all` 集成 |
| 12 | `ut_shm/tests/shm_directed_item_sequence.svh` 及 test package | 为真实 RTL 定向 case 提供发送层 |
| 13 | `docs/ut_shm/verification-status.md` 及 testpoint/component 文档 | 记录实际证据和剩余缺口 |

上表是依赖顺序，不是建议并行修改的文件集。尤其是 coverage 和组件测试必须消费
checker 已经固定的结构化 outcome，不得先根据日志文本复制一套判定。

## 7. 第一批实施和验收顺序

### 阶段 A：纯函数与 transaction contract

1. 修正 VTRANS wpid 文档。
2. 实现 M2V overlap 公共谓词和 validator 复查。
3. 运行已有 shmins compile、copy 和 random benchmark，确认无回归。
4. 实现并运行 `dual-gid-address` 组件测试。

阶段 A 未通过时，不进入 reference 或 RTL directed case。

### 阶段 B：Reference 隔离

1. 实现 reference component harness。
2. 先验证 V2M 相同 BADDR/不同 gid 写入隔离。
3. 再验证 M2V 从 gid 0/1 读取和 wpid 3/4 写回。
4. 最后验证 VTRANS wpid 3/4。

阶段 B 未通过时，scoreboard 的真实 RTL 数据结果不作为 `DBANK-002` 关闭证据。

### 阶段 C：Reservation outcome、coverage 和 resolver

1. 先扩展 check-result type，再修改 checker。
2. 用纯 checker scenario 验证 admission 和 match outcome。
3. 用 agent-level subscriber 验证发布的 gid/match metadata。
4. 实现 coverage 并确认每个 directed scenario 命中目标 bin。
5. 运行已有 alignment、external-busy 和新 `gid-contract` 组件测试。

### 阶段 D：空 design 编译门禁

完成上述源码修改后，在 EDA 服务器上执行：

1. SHMINS sequence 组件 `all`；
2. Reference gid-isolation 组件测试；
3. VLM reservation 组件 `all`；
4. ut_shm 空 design compile/elaboration；
5. 0-transaction smoke。

空 design 结果只证明编译、连接和验证组件行为，不作为 DUT 功能证据。

### 阶段 E：真实 RTL directed case

组件门禁全部通过后，再新增：

- `shm_dbank_wpid_boundary_test`；
- `shm_dbank_gid_isolation_test`；
- `shm_m2v_vaddr_boundary_test`；
- `shm_reservation_gid_ownership_test`。

每个 test 先单独运行和固定失败 seed，然后加入 `p0_directed.lst`。待所有目标 coverage
bin 命中、无未解释 UVM error/fatal、原 109-case 主列表无回归后，再由 `shm.lst`
include 该列表。

## 8. 第一批完成条件

第一批只在同时满足以下条件时完成：

1. M2V generator 和 validator 使用同一 byte-overlap contract；
2. 地址 helper、reference 和 reservation/resolver 三类组件测试通过；
3. 预期负例的 report ID 和次数精确，无额外 UVM error/fatal；
4. coverage 报告能回溯到本批相关 testpoint；
5. 四个真实 RTL directed test 通过；
6. 原 109-case `shm.lst` 在当前 256-bit creq 接口上无回归；
7. `verification-status.md`、testpoint、component 文档和 regression 列表同步实际证据。

第一批完成后，`DBANK-001/002/004` 可按各自验收证据关闭。`DBANK-005` 只有在
本批 directed case 和必需 coverage 均完成时才能关闭；否则只更新为已实现或待验证。

## 9. 后续批次摘要

### 第二批：`VMEM-001`

实现 `FFD_CYC` snapshot，先在 `examples/` 覆盖 cutoff 前/当拍/后、部分 byte 重叠和
`FFD_CYC=0/1/>1`，再增加真实 RTL 连续 read、同 BANK read/write 和流水 read case。

### 第三批：`SHMINS-001`

定向覆盖单 thread 0/15、稀疏 mask、全 mask、全零非法输入、inactive payload X/Z 和
VTRANS 全 mask。Monitor 负例放在 `examples/`，合法 mask 的 DUT 访问抑制放在
`ut_shm/tests/`。

### 第四批：`ENV-001`

建立统一 reset epoch/事件，取消 credit、lifecycle、reservation、MEM read、reference 和
scoreboard pending state；同时实现 `SHMINS-010` 和 `RSV-005` 的 reset 静默检查，最后在
各类 pending 阶段执行真实 RTL runtime-reset case。
