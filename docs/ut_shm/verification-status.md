# ut_shm 验证实现状态

本文集中记录 ut_shm 验证环境与当前 DUT spec 之间的实现差异，以及组件开发中已经
确认的问题。组件文档只引用这里的稳定问题 ID，不重复维护修复过程。原有清单于
2026-08-06 按源码提交 `304c232` 复核；2026-08-08 基于提交 `77626b4` 新增
`SHMINS-012` 的 benchmark-only 拆分计划；同日已完成公共基类和
contiguous 子类的第一版 hx16 验证。Phase 6 的 macOS/Ubuntu 构建结果见
[实测快照](guide/ubuntu-vcs-check.md#6-2026-08-06-实测快照)，不作为闭环以下功能问题的证据。
2026-08-11 已将双 gid BANK 接口写入当前 spec；RTL top 和验证环境主数据路径已开始
同步迁移，实施顺序由
[双 gid 开发计划](../development/shm-dual-bank-interface-refactor-plan.md)统一规定。
2026-08-13 已确认修改后的验证环境和正式 topology-based shmins sequence item 在真实
RTL 集成 testcase 中跑通，`SHMINS-012` 因此完成系统验证并关闭；双 gid 和其他 SHMINS
细分定向项仍按各自验收条件继续跟踪。同日 SPACE_BLK contract 改为 group-relative
MADDR；空 DUT 编译、独立公式 benchmark 和真实 RTL BLK regression 均已通过，
`SHMINS-003` 与 `REF-001` 已关闭。
随后用户确认当前验证环境已在真实 design 上通过 `ut_shm/regression/shm.lst` 的全部
85 个 case。该结果关闭统一接口静态接入项 `DBANK-003`，并作为其余地址、数据和
reservation 正向主路径的系统回归证据；随机 `RUN=1` 列表未覆盖的定向边界、负例、
运行中 reset 和 functional coverage 仍独立跟踪。
随后主列表加入 V2M/M2V `LDSTE_S + WRP/BLK` 共 24 个 case，当前规模为 109；新增项
最初不改变此前 85-case 基线的通过结论。
同日远端 VCS `W-2024.09-SP1_Full64` 组件测试通过四 topology transaction copy/compare
以及 reservation external-busy plusarg/drive 检查，`SHMINS-002`、`SHMINS-011` 和
`RSV-003` 已关闭。
2026-08-14 已把 scoreboard 时间戳统一为共享 `clk_if.cycle_count`，移除 monitor 的固定
200-cycle ack process，新增 accepted creq/data completion/raw ack lifecycle checker，
并将 scoreboard timeout、post-completion ack grace 和 test drain 改为 case plusarg。
随后根据真实 RTL 的同方向顺序 ack 行为，把 grace 起点进一步改为本事务成为 V2M/M2V
独立 ordered lifecycle 队头的周期；年轻事务提前完成或提前 ack 不报告乱序。远端 VCS
组件测试已覆盖慢前序/快后序、无需 ack 的前序、方向独立及年轻事务提前 ack，并完成空
design 全量编译和 0-transaction smoke；clocked grace timeout 触发边界仍待定向验证。
同日 RTL 将每个 thread 的 `creq_offs`、`creq_vdat` 缩为 256 bit，并将 `creq_vmsk` 缩为
32 bit；验证环境同步改为 `VEC_W=256`、`VEC_BYTE_N=32`。用户确认适配后真实 design 的
`shm.lst` 全部 109 个 case 再次通过。该证据关闭 `SHMINS-007`，并把其余正向主路径证据
更新为 109-case 基线；它仍不替代双 gid 边界、负例、运行中 reset 或 functional coverage。
同日第一批双 gid 定向验证基础设施完成：地址/M2V hazard、reference gid 隔离和 reservation
ownership/resolver 组件测试通过，address/reservation 第一批 functional coverage 已接入，
空 design compile/elaboration 和 0-transaction smoke 通过。Reservation outcome 只作为
checker/assertion、诊断和 coverage 证据，不参与 scheduler 接纳或 RTL 输出控制。真实 RTL
directed case 和本批 coverage bin 命中证据尚未完成；本批不要求全项目 coverage merge 或
总百分比阈值。
2026-08-15 完成 P0-1/P0-2 组件补强：地址/reference 测试补齐 wpid 3/4、VTRANS、M2V
byte hazard 和 writeback 边界；reservation 测试补齐 historical pending、跨 BANK 共享、
read/write 独立、missing MEM、gid 0/1 resolver 和 unmatched agent metadata。新增 optional
external busy policy，可按 drive cycle、direction、delay、gid 和 sub-bank 定向占用；未配置
policy 时保留原百分比随机模式。该证据仍不替代真实 RTL directed case。
同日完成 P0-3/P0-4 的四个真实 RTL test、根 TC 定义和独立 `p0_directed.lst`。远端
VCS `make compile` 已完成所有新增 class 的 parse、elaboration 和 link；真实 design 运行、
目标 coverage bin 命中和主列表无回归仍待验证，因此双 gid 问题尚不关闭。
随后用户在正式 design 上完成首轮执行：三个 P0-3 case 和原 `shm.lst` 109-case 全部
通过；P0-4 `shm_reservation_gid_ownership_test` 报告
`SHM_RESERVATION_OTHER_GID_NOT_COVERED`。波形确认 DUT 在 gid 0 external write busy 时也
阻塞目标 gid 1 的 reservation，即把 other-gid busy 当成 BANK 全局 busy。该问题等待与
设计确认；当前 spec、checker 和 directed test 的 other-gid-allow contract 保持不变。
同日完成 `SHMINS-001` thread-mask 定向验证的组件与激励基础设施：monitor 对全零 tmsk
报告后直接丢弃，不向 production analysis port 发布；active-thread payload 局部 X/Z
检查和 request mask/VTRANS coverage 已接入。Monitor、sequence copy/VTRANS 和 reference
组件测试在远端 VCS 通过，两个真实 RTL directed test、TC 和独立 LST 已编写，并通过
空 design `make compile`。真实 RTL 的 24-cell normal mask、4-cell VTRANS、coverage 命中和
109-case 无回归证据尚未执行。

## 1. 状态和优先级

问题状态按以下顺序流转：

```text
待确认 → 待实现 → 实现中 → 待验证 → 已完成
                         ↘ 暂缓
```

|状态|含义|
|---|---|
|待确认|DUT contract 或验证目标尚未确定；当前没有这类开放项|
|待实现|contract 已确定，代码尚未满足|
|实现中|已开始修改，但代码或必要测试尚未完整|
|待验证|代码路径已实现，缺少验收条件中要求的可重复证据|
|已完成|代码和验收证据均齐备，转入已解决记录|
|暂缓|目标已知，但经明确决定暂不实现|

|优先级|含义|
|---|---|
|P0|违反当前 spec、破坏核心数据正确性，或阻止主要功能验证|
|P1|检查、配置或定向测试明显不完整，可能漏报或误报|
|P2|参数化、冗余结构或辅助 API 问题，不影响默认配置的主要路径|

“已完成”必须同时具备代码修改和可重复的验收证据。只有文档更新不能关闭实现问题。
问题关闭时必须记录修改文件、commit、验证命令、结果和日期；不追溯没有完整
证据的历史修改。

本文维护“具体实现问题”的生命周期。功能点的激励、checker、coverage 和 case 是已实现、
部分实现还是未实现，统一由 [Testpoints](plan/testpoints.md) 维护；稳定的当前结构和
算法由对应组件文档维护。这里不再建立重复的功能完成度矩阵。

## 2. 当前支持边界

- 当前只支持完整 active 环境，passive 模式明确不支持。相关配置应当明确拒绝，或在
  后续清理中移除，不能让环境进入半连接状态。
- DUT 可以乱序调度多笔 creq，但最终 memory 结果必须与 creq 顺序执行的结果一致。
  Reference 按 creq 采样顺序建立架构期望，scoreboard 可以接受合法中间写入，但测试
  结束时必须收敛到顺序执行的最终状态。
- 当前双 gid spec 是目标协议。下表中的缺口不能被迁移前源码行为反向解释为协议例外。
- `BANK_N=16` 表示 logical bank/MEM port 数量，物理 storage key 是
  `<bank_id,gid,BADDR>`；MEM gid 由唯一到期 reservation record 恢复。

## 3. 开放问题总表

|ID|优先级|状态|组件|主题|
|---|---:|---|---|---|
|`ENV-001`|P0|待实现|跨组件|运行中 reset 未统一取消 pending 状态|
|`ENV-002`|P2|待实现|environment config|仍暴露不能组成完整环境的 passive 配置组合|
|`COV-001`|P1|实现中|跨组件|address/reservation 和 request mask/VTRANS coverage 已接入；其余 coverage 与 bin 证据仍缺|
|`DBANK-001`|P0|待验证|共享地址/shmins|wpid/gid 地址和 M2V vaddr 定向 case 已通过真实 RTL；待保存 coverage/关闭证据|
|`DBANK-002`|P0|待验证|reference/expected model|相同 BADDR 跨 gid 数据隔离 case 已通过真实 RTL；待保存 coverage/关闭证据|
|`DBANK-004`|P0|待实现|RTL/VLM reservation|真实 RTL 把 other-gid external busy 当成全局阻塞；等待设计确认和修复|
|`DBANK-005`|P1|待验证|test/coverage|P0-3 三项及109-case通过；P0-4发现DUT ownership问题，目标bin和整组通过仍缺|
|`SHMINS-001`|P0|待验证|shmins agent|组件矩阵及 directed tests 已完成，待真实 RTL 28-cell、coverage 和主列表回归|
|`SHMINS-004`|P1|待验证|unit sequence|RW/DTYPE/ATYPE_W/ITYPE/SPACE 固定配置已通过 109-case RTL 回归，待 ATYPE_S/G 端到端定向验证|
|`SHMINS-005`|P2|待实现|shmins agent|256-bit 向量参数适配已通过；16-thread/4-bit 等硬编码仍在|
|`SHMINS-006`|P1|实现中|shmins monitor|active-thread payload 局部 X/Z 检查已实现；公共字段和完整字段矩阵仍缺|
|`SHMINS-008`|P1|待验证|shmins monitor/lifecycle|有序 grace 组件测试已通过，待 clocked timeout 触发边界验证|
|`SHMINS-009`|P1|待验证|shmins/lifecycle|ack 完备 checker 和 credit/release 上溢检查已实现，待定向正负例|
|`SHMINS-010`|P1|待实现|shmins monitor|复位期间 release 和 ack 静默缺少检查|
|`VMEM-001`|P0|待实现|memory model|MEM read 未实现 `FFD_CYC` 写可见窗口|
|`VMEM-002`|P1|待实现|memory monitor|MEM valid、地址、strobe 和有效数据缺少完整 X/Z 检查|
|`VMEM-003`|P2|待实现|memory agent|sequencer 和部分 compare API 没有有效行为|
|`SCB-002`|P1|待验证|scoreboard|固定 timeout 已改为可关闭的 cycle plusarg，待定向验证|
|`RSV-002`|P1|实现中|reservation coverage|第一批 ownership/resolver coverpoint 和 cross 已实现；完整 testpoint coverage 仍缺|
|`RSV-004`|P1|待实现|reservation checker|全局 `input_error` 会屏蔽无关 slot 的检查|
|`RSV-005`|P1|待实现|reservation monitor|复位期间没有检查 DUT request/valid 必须为 0|

## 4. 问题详情

### 双 gid 迁移门控顺序

双 gid 开放项必须按以下顺序推进：

```text
DBANK-001 公共类型/地址/shmins
    → DBANK-002 reference 期望模型
    → DBANK-003 统一 interface/静态连接（已完成）
    → DBANK-004 scheduler/resolver/driver/scoreboard 数据接入
    → DBANK-005 testcase/coverage/regression
```

Reference 期望模型在统一接口之前完成；scoreboard 的 actual gid memory 与 read driver
在 `DBANK-004` 提供可信 resolver 后一起接入。完整逐文件和阶段验收见
[开发计划](../development/shm-dual-bank-interface-refactor-plan.md#4-必须遵守的实现顺序)。

2026-08-11 当前验证记录：

- `make preflight` 在新远端服务器通过，完整 filelist、VIP 和空 `RpuShmTop` 输入齐全；
- VCS license 恢复后，`scripts/ubuntu/check_vlm_reservation_vcs.sh compile` 完成统一
  VLM interface/agent 空设计示例的 parse、elaboration 和 simv link；
- 随后执行 `make compile`，27 个模块全部完成编译，`shm_tb_top` 使用空
  `RpuShmTop` 完成 elaboration 和 simv link。日志保留在远端
  `build/ut_shm/compile.log`，末尾记录 `51.332 seconds to compile + .300 seconds to
  elab + 1.183 seconds to link`；
- 以上证据解除静态编译门禁，因此 `DBANK-001`～`DBANK-004` 转为“待验证”；它不等同于
  双 gid 定向功能测试或真实 RTL regression 通过。
- 2026-08-13 用户确认修改后的统一验证环境和 shmins sequence item 已在真实 RTL 集成
  testcase 中跑通。这证明主数据路径能够工作，但不替代 `DBANK-001`～`DBANK-005`
  验收项要求的 gid 边界、数据隔离、busy ownership、冲突和失败路径定向测试。
- 2026-08-13 SPACE_BLK group-relative MADDR 修改后，在 Ubuntu EDA 服务器执行
  `make compile`，空 `RpuShmTop` 的 parse、elaboration 和 link 通过，耗时为
  `32.363 seconds to compile + .338 seconds to elab + .966 seconds to link`。
- 同一版本执行
  `BENCH_ITERATIONS=100 BENCH_WARMUP=5 scripts/ubuntu/run_shmins_random_cross_benchmark.sh all`：
  432 个 topology/space/RW/dtype/atype 组合全部通过，三个无 inline constraint topology
  各 100 次全部通过，UVM error/fatal 均为 0；matrix 和 unconstrained 启动时分别完成
  1248 个独立 SPACE_BLK 公式检查，覆盖全部 13 个 interleave size，error 均为 0。
  日志位于远端
  `examples/shmins_random_benchmark/build/split/cross_matrix.log` 和
  `unconstrained.log`。
- 当前 Ubuntu EDA 工作区中的 `RpuShmTop.sv` 是 66 行无行为 stub，仓库也没有真实 RTL
  regression 命令，因此上述仓库内命令本身不包含 RTL 功能回归。随后用户在实际 BLK
  regression 环境中完成新版 SPACE_BLK 回归并确认通过；该系统证据与独立公式 benchmark
  共同关闭 `SHMINS-003` 和 `REF-001`。
- 用户随后确认当前代码在真实 design 上完成 `ut_shm/regression/shm.lst` 全量回归；当前
  `v2m.lst` 有 55 个 case（54 个普通 V2M 和 1 个 VTRANS），`m2v.lst` 有 54 个 case，
  共 109 个且全部通过。每个条目当前为 `RUN=1`；
  该结果证明列表所含 V2M/M2V/VTRANS、LOC/WRP/BLK、DTYPE 8/16/32、ATYPE_W 16/32
  正向组合的系统主路径无新增错误，但不证明随机字段命中特定 bin，也不覆盖未列入
  LST 的定向或负向场景。

### `DBANK-001` 两层地址模型与合法激励

- 现状：共享参数已删除 `VADDR_W` 并定义双 gid 物理地址；正式 topology item 已回填
  逻辑/物理 element 地址、使用 gid-aware byte key，并为 M2V 生成 byte-disjoint writeback
  BADDR；生成器和 validator 复用同一 byte-hazard 谓词。LOC/WRP/BLK、V2M/M2V 的正向
  主路径已通过 109-case 真实 RTL 回归；独立公式组件测试覆盖 BANK 0/15、warp 0/3/4/7、
  laddr 首尾和三种 space 的 wpid 3/4。VTRANS wpid 3/4 物理映射已通过；M2V 组件测试已
  覆盖 exact/one-byte overlap 拒绝、adjacent/same-beat-disjoint/cross-gid 允许和 gid 内
  WARP 首尾合法候选。用户确认三种 space 的 wpid/gid 边界和 M2V vaddr 首尾 directed
  case 已在真实 RTL 上通过；原 109-case 主列表同时无回归。
- 目标：三种 space 输出 `<bank,absolute warp,laddr>`，公共 helper 统一生成 gid/BADDR；
  `creq_vaddr` 改为 16 bit 并携带 gid 内 WARP 基址；M2V 排除有效 read/write byte overlap。
- 验收：地址公式测试覆盖 warp 0/3/4/7、SPACE_BLK 非零 group 和 WARP 首尾；三类
  sequence item 通过 copy/validation 和随机 benchmark。

### `DBANK-002` gid-aware reference 与 expected memory key

- 现状：`wmap` 已用 flattened `<bank,gid>` storage index，`ref_banks` 已扩展为
  `[BANK_N][GID_N]`；reference M2V 直接使用 `creq_vaddr` 并从 wpid 取得 write gid；
  V2M/M2V/VTRANS 正向数据检查已通过 109-case 真实 RTL 回归；standalone reference 组件
  测试已证明相同 bank/BADDR、不同 gid 的 V2M 写入和 M2V 读取互不覆盖，并验证 VTRANS
  wpid 3/4 的 16×16 转置及 M2V wpid 3/4 的 writeback gid/BADDR。用户确认相同
  BANK/BADDR、不同 gid 的可区分数据 pattern directed case 已在真实 RTL 上通过；原
  109-case 主列表同时无回归。
- 目标：全部 expected physical byte key 改为 `<bank,gid,BADDR>`；reference M2V 直接使用
  `creq_vaddr`，只从 wpid 得到 write gid。
- 验收：相同 bank/BADDR、不同 gid 的数据隔离；V2M/VTRANS/M2V 的 wpid 3/4 定向
  reference 测试通过。

### `DBANK-004` Reservation resolver 与数据路径

- 现状：scheduler busy 和 record 已携带 gid；checker 从唯一到期 record 生成 per-BANK
  match metadata，统一 agent 固定 metadata 后驱动 read response/发布 write，scoreboard
  只对 matched transaction 访问对应 gid memory；正常 reservation/MEM 兑现路径已通过
  109-case 真实 RTL 回归。Checker 现在额外返回逐请求 admission outcome 和逐 BANK MEM
  match outcome；组件测试已覆盖 target-gid external busy、other-gid external allow、
  other-gid historical pending、同周期 write-port conflict、different-bank shared slot、
  read/write direction independence、gid 0/1 正常 match、unexpected、missing 和 address
  mismatch。Agent-level subscriber 已证明 unmatched MEM 发布时 gid/match metadata 仍无效。
  Outcome 只供
  assertion/checker、诊断和 coverage 使用，不控制 scheduler 或 RTL 输出。P0-4 在真实
  RTL 上报告 `SHM_RESERVATION_OTHER_GID_NOT_COVERED`；波形确认 gid 0 external busy 会
  同时阻塞目标 gid 1 reservation。验证侧 policy 已生效，问题等待设计确认和 RTL 修复。
- 目标：busy ownership 使用 `[direction][delay][gid][subbank]`，MEM port record 保持
  `[direction][delay][bank]`；resolver 从唯一到期 record 恢复 gid，read driver复用同一
  match result，scoreboard actual memory增加gid，未匹配 MEM 不更新可信模型。
- 验收：other-gid external busy允许，other-gid same-bank/due DUT record阻塞；两个 write
  port相同dly的所有gid/subbank组合被拒绝；read/write正确访问对应gid memory。

### `DBANK-005` 双 gid testcase 与覆盖

- 现状：现有 109 个 case 已在真实 design 上全部通过，证明统一双 gid 环境可以承载当前
  正向矩阵。第一批 address/reservation coverage collector、定向 topology item 发送层和
  三类组件测试已经实现。P0-3/P0-4 的四个真实 RTL test 由根 TC 和独立
  `p0_directed.lst` 组织；P0-3 三项和原 109-case 主列表已通过，P0-4 ownership case
  稳定暴露 DUT other-gid global blocking。目标 bin 命中证据和整组 PASS 仍未完成。
- 目标：实现 `TP-ADDR-009`、`TP-MEM-005`、`TP-RSV-007/008` 以及更新后的 M2V、LOC、
  WRP、BLK testpoint；coverage 至少交叉 direction、gid、subbank、busy source和match结果。
- 验收：开发计划阶段 7 的定向 case 全部通过，主 regression 无新增 error，并保存可重复
  命令、seed、日志和 coverage 结果。

### `ENV-001` 运行中 reset 状态清理

- 现状：driver、monitor 多数只等待初始 reset 释放；reference memory、scoreboard
  outstanding、MEM read fork 和 reservation scheduler 没有统一取消或重建。
- 影响：运行中 reset 后可能继续兑现 reset 前事务，违反 DUT reset 契约。
- 目标依据：[DUT 概览的 reset 行为](spec/dut-overview.md#6-复位边界)。
- 验收：在 creq、reservation 和 MEM read 均有在途状态时拉低 reset；释放后不得出现
  旧 ack、旧 MEM response、旧 reservation 到期或旧 scoreboard timeout。

### `ENV-002` Unsupported passive 配置

- 现状：config 中仍有多组 active/passive knob，但 reservation agent 固定 active；
  关闭 scoreboard 时，active memory driver 的 blocking transport 也会失去目标。
- 影响：非默认组合可能在 elaboration 或运行时形成半连接环境。
- 目标：现阶段只支持完整 active；不支持的组合应尽早 fatal，或删除无效 knob。
- 验收：所有公开配置组合要么形成完整连接，要么在 build 阶段给出明确错误。

### `COV-001` ut_shm functional coverage

- 现状：`shm_address_coverage` 已只读采样 reference transaction 的 direction、space、
  absolute warp、gid、laddr、wpnum 和 M2V read/write gid；`vlm_reservation_coverage` 已采样
  direction、bank、gid、subbank、delay、ownership、admission 和 MEM match outcome；
  `shmins_request_coverage` 已采样 normal/VTRANS、direction、space、tmsk class/population、
  active thread、payload X/Z 和 VTRANS dtype/itype。Ack、FFD_CYC、reset 等其他 testpoint
  尚无对应 functional coverage，新增 request coverage 也尚缺真实 RTL bin 命中证据。
- 影响：case 运行和 checker 通过不能证明 spec 场景实际发生，所有 testpoint 都缺少
  功能覆盖关闭证据。
- 目标依据：[Testpoints](plan/testpoints.md)和
  [Coverage 与关闭条件](plan/coverage-and-closure.md)。
- 验收：每个 required testpoint 都能映射到已实现的 functional bin/cross，报告可按
  testpoint ID 回溯，未命中项有定向激励或有效 waiver。第一批双 gid 验收暂不要求全项目
  coverage merge 或总百分比阈值，但必须保存其目标 bin/cross 的命中证据。

### `SHMINS-001` `creq_tmsk` 数据通路

- 现状：tb top、interface、transaction、copy、factory field、driver 和 monitor 已贯通
  `THD_N` bit `creq_tmsk`。普通请求约束非全零，VTRANS 约束全 1；monitor 报告 X/Z 和
  全零值，并在全零报告后丢弃事务，不分配 UID、不发布到 production analysis port。
  Reference 为非 active thread 创建空的地址/BANK/strobe 数组，不解释 inactive payload，
  也不生成对应读写期望。`MON-MASK-001`～`010`、四个 VTRANS sequence cell 和 reference
  inactive X/Z 组件测试已通过；24-cell normal 与 4-cell VTRANS 真实 RTL tests 已编写并
  通过空 design 编译。正向主路径此前已通过 109-case 真实 RTL 回归，但新 directed tests
  尚未在真实 RTL 上执行。
- 影响：代码路径已具备 mask 行为，但在稀疏 mask、inactive payload X/Z 和 DUT 意外
  输出场景验证完成前，不能确认功能关闭。
- 目标依据：[creq/ack 接口](spec/creq-ack-interface.md)。
- 验收：覆盖非全零普通 mask、inactive thread X/Z、全零非法请求和 VTRANS 全 1；保存
  24-cell normal、4-cell VTRANS、目标 coverage 和 109-case 无回归证据。

### `SHMINS-004` Unit sequence 配置丢失

- 现状：`shmins_mst_unit_sequence` 已用 allowed-value domain 统一约束 ATYPE_W/S/G、
  dtype、RW、itype 和 space，并支持 `set_fixed_*()` 把对应 domain 缩为单值。109-case
  真实 RTL 回归已验证 RW、DTYPE、ATYPE_W、ITYPE 和 SPACE 的 TC/plusarg 正向路径；
  ATYPE_S/G 尚缺从 testcase 配置入口到 monitor transaction 的端到端定向证据。
- 影响：item 生成侧配置已经贯通，但 testcase/plusarg 集成路径仍可能发生配置遗漏。
- 目标：所有公开 sequence 配置必须确定对应 item 字段。
- 验收：分别设置 signedness 和 granularity plusarg，monitor transaction 与配置一致。

### `SHMINS-005` 参数硬编码

- 现状：driver/monitor 使用固定 16-thread 循环，interface priority 宽度固定为 4 bit，
  部分辅助函数也使用固定 BANK 数。`VEC_W` 从 512 改为 256 后，interface、transaction、
  driver、monitor 和 reference 已通过参数同步适配并完成 109-case RTL 回归；该证据只覆盖
  向量宽度，不覆盖本 ID 的 `THD_N/PRIO_W` 参数化目标。
- 影响：修改 `THD_N` 或 `PRIO_W` 时环境不能可靠复用。
- 目标：循环和位宽来自 `shm_util_package` 参数。
- 验收：至少使用一个非默认 `THD_N/PRIO_W` 配置完成语法和 elaboration 检查。

### `SHMINS-006` creq 四态检查

- 现状：monitor 已先检查 tmsk，再按 active thread 检查 priority、length、有效 vmsk、
  topology 实际使用的 offset slice，以及 V2M 有效 data byte；inactive payload X/Z 和
  `creq_vld!=1` 时 payload 不检查。组件测试已覆盖 inactive X/Z、active length X、tmsk X
  和 valid 0。公共控制字段及各 active payload 字段的完整 X/Z 矩阵仍未覆盖。
- 影响：非法输入可能进入 reference，错误被延迟或转化成难以定位的数据差异。
- 目标依据：`CREQ-002`。
- 验收：为公共字段、active thread payload 和 inactive thread payload 分别注入 X/Z，
  只报告协议禁止的组合。

### `SHMINS-008` Ack timeout 不是协议时限

- 现状：2026-08-14 已删除 monitor 的逐事务固定 200-cycle process。Monitor 只发布 raw
  ack；lifecycle checker 只在 scoreboard 把全部期望 byte 实际匹配为 `OBSERVED`，且
  同方向所有前序事务都已退休后，可选使用 `ACK_POST_COMPLETE_GRACE_CYCLES` 报告缺失
  ack。0 可关闭中途诊断，最终 required ack 仍在 drain/check phase 检查。独立 V2M/M2V
  队列按 accepted 顺序退休：无需 ack 的事务在数据 resolved 后退休，需要 ack 的事务在
  数据 resolved 且收到 ack 后退休；年轻事务提前收到 ack 只记录状态，不报告乱序。
- 影响：实现不再限制 creq accepted 到数据完成的时延。有序队头切换已有组件证据，尚缺
  运行 checker `main_phase` 的 clocked grace timeout 触发和关闭边界证据。
- 目标：保持 timeout 可配置或关闭，并明确属于 hang 诊断；默认策略不得被解释成 DUT
  protocol checker。
- 验收：关闭 timeout 时长延迟 ack 不报错；配置诊断阈值时日志能区分协议错误与
  hang 诊断；最终正确 ack 仍按方向和 ID 完成匹配。
- 当前证据：远端 VCS `W-2024.09-SP1_Full64` 执行
  `scripts/ubuntu/check_shmins_sequence_vcs.sh lifecycle`，覆盖慢前序/快后序完成、无需 ack
  的前序、V2M/M2V 独立推进及年轻事务提前 ack，输出
  `ordered ack grace regression: PASS`，且 `UVM_ERROR: 0`、`UVM_FATAL: 0`。随后执行
  `make compile` 和 `make smoke`，空 design 编译通过，0-transaction smoke 输出
  `UVM_CASE_PASS`、`UVM_ERROR: 0`、`UVM_FATAL: 0`。当前 109-case 真实 RTL 回归也通过
  lifecycle 正向路径，但不包含 clocked grace timeout 触发/关闭边界。

### `SHMINS-009` Credit 与 ack 完备性检查

- 现状：driver 使用显式 `credit_cnt` 限制环境自身发送，在每个 `creq_rls` 上归还 credit，
  并以 `SHMINS_CREDIT_OVERFLOW` 检查计数不得超过 `OTF_N`。2026-08-14 lifecycle checker
  已实现 ack-disabled、unexpected、duplicate、wrong-direction、wrong-ID/reset-epoch 关联和
  exactly-once 状态，尚未完成独立正负例验收。109-case 真实 RTL 回归已通过合法
  ack/release 正向路径，但不会主动制造 credit 上溢或错误 ack。
- 影响：实现路径已经具备，但缺少负例证据时仍不能确认每种 credit/ack 违例都能被唯一、
  准确地分类和定位。
- 目标依据：`CREQ-005`、`ACK-001` 和 `ACK-002`。
- 验收：定向覆盖 credit 下溢/上溢、unexpected/duplicate/wrong-direction/wrong-ID ack，
  每类违例均得到唯一且可定位的错误；合法 release/ack 独立顺序不误报。

### `SHMINS-010` 复位期间 release/ack 静默

- 现状：driver 和 monitor 等待初始 reset 释放后才进入正常业务循环，没有独立检查
  `rst_n==0` 时 DUT 的 `creq_rls/vack_done/mack_done` 必须为 0。
- 影响：DUT 在初始或运行中 reset 期间错误归还 credit 或发送 ack 时可能不被报告。
- 目标依据：[creq/ack 接口的复位规则](spec/creq-ack-interface.md#8-复位与检查规则)。
- 验收：reset 已知为 0 时分别拉高 release、vack 和 mack，均得到明确错误；reset X/Z
  不启动正常 payload 检查，done 为 0 时不检查 ID。

### `VMEM-001` `FFD_CYC` read snapshot

- 现状：memory driver 在采样 `mem_rvld/mem_raddr` 后立即调用 scoreboard
  `b_transport()` 读取 `rtl_banks`，再延迟输出。
- 影响：不能表示 read 在未来截止周期之前可见的 write。
- 目标依据：[MEM/VLM 接口的写可见窗口](spec/mem-vlm-interface.md#24-ffd_cyc-写可见窗口)。
- 验收：覆盖 `FFD_CYC=0`、1 和大于 1，确认截止周期之后的 write 不进入返回值。

### `VMEM-002` MEM 四态检查

- 现状：memory monitor 采集 valid/address/strobe/data，但没有系统性的 `$isunknown`
  检查；reservation monitor 只覆盖 MEM valid 和地址。
- 影响：strobe 或有效 data lane 的 X/Z 可能污染 `rtl_banks` 或形成误导性比对。
- 目标依据：`MEM-002`、`MEM-003`。
- 验收：分别向 read valid/address 和 write valid/address/strobe/有效 data lane 注入 X/Z。

### `VMEM-003` 无效辅助结构

- 现状：active memory agent 创建 sequencer，但 driver 不消费 sequence item；
  `vlm_memory_sequence_item.compare_item()` 也不会累计错误，且循环硬编码为 16。
- 影响：组件 API 暗示了并不存在的控制和比较能力。
- 目标：删除无意义结构，或补齐可验证的用途，避免保留会静默返回错误结果的 API。
- 验收：组件公开结构与实际数据流一致，所有保留 compare API 有定向单元测试。

### `SCB-002` 可配置 timeout

- 现状：2026-08-14 scoreboard 已统一使用 `clk_if.cycle_count`，固定 128-cycle 路径已替换
  为 `SCB_NO_PROGRESS_TIMEOUT_CYCLES` 和 `SCB_RECORD_AGE_TIMEOUT_CYCLES`。两者默认 0
  关闭；触发只报告一次并保留 record，扫描周期单独配置。109-case 真实
  RTL 回归已通过正常 scoreboard 生命周期，但没有定向覆盖两类 timeout 的边界。
- 影响：协议时延不再被默认阈值限制，但尚缺关闭、触发后继续匹配和无进展恢复的定向证据。
- 目标依据：[DUT 概览的协议边界](spec/dut-overview.md#7-协议边界)。
- 验收：timeout 可配置或关闭；超过默认诊断阈值但最终正确的事务不会被强制判错。

### `RSV-002` Reservation coverage

- 现状：coverage 已在 scheduler 更新前采样同一 transaction/check result/pre-update state，
  实现 direction、bank、gid、subbank、delay、other-gid ownership、admission outcome、MEM
  match outcome 和 resolved gid 的第一批 coverpoint/cross，并维护可供组件测试检查的计数器。
- 影响：第一批双 gid ownership/resolver 已有采样基础；reservation 的完整 delay、并发共享、
  X/Z 和 reset 场景仍未覆盖闭环。
- 目标：继续按 testpoint 补齐缺失的 coverpoint/cross，且不得改变 scheduler 状态或参与
  request admission。
- 验收：覆盖报告能追踪主要合法场景和错误注入场景；第一批不设置全项目 merge 或总
  百分比阈值，但目标 bin 必须有可回溯命中证据。

P0-2 另外为 external busy 增加 optional policy object。定向 policy 以 inclusive
drive-cycle range 和完整 `<direction,delay,gid,sub_bank>` 指定占用，并优先于
`EXTERNAL_BUSY_PERCENT`；policy 为空时保留原百分比随机模式。Scheduler 和 agent-level
组件测试已经验证单 cycle/range、窗口前移、已有 SHM slot 不被覆盖、优先级和 config
handle 传播。该 policy 是可重复激励基础设施，不参与 checker 判定或 DUT 输出控制。

### `RSV-004` `input_error` 抑制粒度

- 现状：cycle transaction 只有一个全局 `input_error`。任意 busy、reservation 或 MEM
  端口出现 X/Z 后，checker 会跳过本周期全部 observed-busy 比较，并抑制所有到期
  record 的 `MISSING_MEM`。
- 影响：一个 BANK 或方向上的四态错误可能掩盖其他 BANK、方向和 slot 上彼此独立的
  busy mismatch 或 missing MEM，降低 checker 的并发诊断能力。
- 目标：保留 monitor 的原始 X/Z 报错，同时把“该观察值是否可靠”记录到实际受影响的
  busy bit 和 request port，或采用等价的局部抑制机制。
- 验收：向一个无关端口注入 X/Z 时，该端口不产生归一化后的级联误报；同周期其他
  BANK/direction 上的 busy mismatch 和 missing MEM 仍能被 checker 报告。

### `RSV-005` 复位期间 request quiescence

- 现状：`collect_cycle()` 在 `rst_n!==1` 时只等待，不采样 reservation 或 MEM
  request，因此没有检查复位期间 `vlm_rreq/vlm_wreq` 和 `mem_rvld/mem_wvld` 必须为 0。
- 影响：DUT 在初始或运行中复位期间错误发出 reservation/MEM request 时，验证环境
  不会报告 `MEM-001` 或 `VLM-001` 违例。
- 目标依据：[MEM/VLM 接口的复位和 X/Z](spec/mem-vlm-interface.md#5-复位和-xz)。正常
  cycle transaction 仍只在 reset 释放后创建；复位静默检查应使用独立的 assertion、
  reset-only monitor 路径或等价机制。
- 验收：在已知 `rst_n==0` 的周期分别拉高四类 request/valid，均能得到明确错误；reset
  为 X/Z 时不启动业务 X/Z 检查，也不产生正常 transaction。

## 5. 已解决记录

### `SHMINS-007` V2M `LDSTE_S + SPACE_WRP/SPACE_BLK`

- 关闭日期：2026-08-14。
- 修改：strided item 在 V2M，或开启 uniqueness 的 M2V，且 space 为 WRP/BLK 时，将每个
  active thread 的 element 0 mask 为 0，并继续对其余有效 element 执行 byte-overlap
  检查；V2M/M2V 对应的 WRP/BLK 叶子 case 共 24 个已加入主列表。
- 生成验证：交叉 benchmark 已覆盖 V2M/M2V、WRP/BLK 和 strided 组合，transaction
  validator 保证 V2M 不产生未定义的有效写 byte overlap。
- 系统验证：用户确认真实 design 上扩容后的 `ut_shm/regression/shm.lst` 全部 109 个
  case 通过，其中 `v2m.lst` 55 个、`m2v.lst` 54 个；新增 24 个 strided case 已纳入该次
  回归。随后 `VEC_W` 缩为 256、`VEC_BYTE_N` 缩为 32 后，同一主列表再次全部通过。
- 结论：element-0 激励限制、reference/scoreboard 消费和真实 RTL 系统路径已完成验收。
  Functional coverage 仍由 `TP-ADDR-008` 和 `COV-001` 跟踪，不再作为本实现问题的阻塞。

### `SHMINS-002` / `SHMINS-011` Transaction copy 与 compare

- 关闭日期：2026-08-13。
- 修改：公共 transaction `do_copy()` 保留 creq、生成统计、decoded offset、element MADDR
  和两层映射结果；contiguous override 额外复制 `start_maddr`。`compare_item()` 使用 UVM
  注册字段比较，不再无条件 fatal。
- 验证：远端 VCS `W-2024.09-SP1_Full64` 执行
  `scripts/ubuntu/check_shmins_sequence_vcs.sh all` 和带结果门禁的 `copy` 复跑；contiguous、
  strided、indexed、VTRANS 均完成非默认字段 copy、未注册生成态逐字段检查、相等正例、
  `creq_id` 差异负例及恢复正例，报告为 `UVM_ERROR: 0`、`UVM_FATAL: 0`。
- 结论：影响行为的 copy 状态完整，保留的 compare API 已有稳定正反例组件测试。

### `RSV-003` Reservation external-busy example

- 关闭日期：2026-08-13。
- 修改：external-busy testbench 连接 agent 必需的 read-data transport endpoint；Ubuntu
  组件脚本增加 PASS marker、`UVM_ERROR: 0` 和 `UVM_FATAL: 0` 结果门禁，避免 UVM fatal
  仍被 shell 当作成功。
- 验证：远端 VCS `W-2024.09-SP1_Full64` 执行
  `scripts/ubuntu/check_vlm_reservation_vcs.sh external-busy`；config 默认值为 7，plusarg
  覆盖 scheduler 为 100，所有 external read/write busy slot 实际拉高，最终 0 error、
  0 fatal 并输出 `EXTERNAL_BUSY_TEST ... PASS`。
- 结论：当前 example 可独立验证 external-busy 配置优先级和基本 drive 行为。

### `DBANK-003` 统一 VLM interface 与静态连接

- 关闭日期：2026-08-13。
- 修改：主要实现提交 `8c399f8` 将 tb/environment 切换为一个统一 `vlm_interface` 和
  `vlm_agent`，原子承载 busy、reservation、gid 和 MEM 信号；monitor 对 busy、request、
  address、delay 和 gid 执行四态检查，agent 是唯一 MEM transaction 发布者，后续修订
  已包含在本次真实 design 回归版本中。
- 编译证据：空 design 与集成 top 均已完成 compile/elaboration；接口 gid 维度和端口宽度
  已由真实 design 集成编译固定。
- 系统证据：用户确认真实 design 上 `ut_shm/regression/shm.lst` 的 85 个 case 全部通过，
  覆盖 V2M/M2V/VTRANS 与 LOC/WRP/BLK 正向主路径。
- 结论：统一接口、单 monitor/发布者和静态连接已完成。Reservation ownership、错误匹配
  和数据隔离定向验证继续由 `DBANK-002/004/005` 跟踪。

### `SHMINS-003` / `REF-001` SPACE_BLK group-relative 地址生成与映射

- 关闭日期：2026-08-13。
- 修改：SPACE_BLK MADDR 合法范围改为 `[0,C*BANK_N*creq_wpnum)`；MADDR 只编码当前
  group 内的 `bank_id/warp_offs/inv_index/inv_offs`，absolute `warp_group` 由
  `creq_wpid/creq_wpnum` 派生。Sequence generator、validator、公共两层地址 helper 和
  reference consumer 使用同一稳定 contract。
- 公式验证：执行
  `BENCH_ITERATIONS=100 BENCH_WARMUP=5 scripts/ubuntu/run_shmins_random_cross_benchmark.sh all`，
  432 个交叉组合和三个无 inline constraint topology 全部通过；matrix 与 unconstrained
  各完成 1248 个独立 BLK 公式检查，覆盖 WPNUM 1/2/4、WPID 0/3/4/7、全部 13 个
  interleave size、编码上界和地址空洞，error 均为 0。
- 系统验证：用户确认新版代码在实际 RTL BLK regression 中通过。问题分析期间明确了
  `creq_inv_size=9`、`creq_wpnum=2`、`creq_wpid=3` 时 MADDR 必须小于 `0x60000`，
  旧 group base 不再属于 MADDR 编码。
- 结论：激励、公共 helper、reference 和实际 RTL 已对齐到 group-relative BLK contract。
  功能覆盖率统计仍由 `TP-ADDR-006` 和 `COV-001` 独立跟踪。

### `SHMINS-012` Sequence item 随机化性能与结构拆分

- 关闭日期：2026-08-13。
- 修改：正式 `shmins_sequence_item.svh` 现为公共 transaction 和地址 helper 基类；
  contiguous、strided、indexed 与 VTRANS 子类按 MADDR 拓扑生成地址，master unit sequence
  通过 normal/VTRANS allowed-value domain 和全局 VTRANS 概率显式创建对应子类。旧 solver、
  monolithic post-randomize item、生成 constraint 和历史 benchmark filelist 已删除。
- 消费边界：`shm_wtrans_item` 只为 `tmsk && length && vmsk` 选中的 active element 重建、
  映射地址；超出 length、masked 或 inactive payload 不再触发 `map_maddr()`。M2V reference
  同样跳过 zero-strobe element。
- Benchmark：2026-08-09 的 432 组交叉矩阵每组 100 次，共 43,200 次随机化，全部
  `failures=0`、`validation_errors=0`；三种 topology 无 inline override 各 1000 次通过。
  2026-08-12 增强矩阵对 432 组各运行 20 次，并通过真实
  `shm_wtrans_item.init_from()` 检查 BANK/gid/BADDR 和 zero-length active-thread 场景；另有
  `LDST_S × LOC/WRP/BLK × V2M/M2V` 共 600 次全部通过。
- 编译与集成：远端 VCS `W-2024.09-SP1_Full64` 已完成正式 sequence 最小 top 和空
  `RpuShmTop` 的 parse、elaboration、link；2026-08-13 用户确认修改后的验证环境和 sequence
  item 已在真实 design 上通过当时 `shm.lst` 的全部 85 个 case，不再出现 inactive element
  MADDR mapping error。
- 结论：随机化性能重构、正式 API 迁移和系统消费边界均已完成。`SHMINS-003` 已单独
  关闭；`SHMINS-002/011` 已由独立 copy/compare 组件测试关闭，`SHMINS-004` 仍按配置
  端到端验收条件独立跟踪；`SHMINS-007` 已由扩容后的 109-case RTL 回归关闭。

### `RSV-001` Reservation alignment policy

- 关闭日期：2026-08-11。
- 修改：提交 `acb05a2` 删除 types alignment helper、checker 的 request/record/MEM
  alignment 判断和 scheduler alignment 拒绝路径；reservation 与到期 MEM 继续逐位
  比较完整地址。
- 验证：远端 VCS `W-2024.09-SP1_Full64` 执行
  `scripts/ubuntu/check_vlm_reservation_vcs.sh alignment`，read、write port 0/1 非对齐地址
  保留、同地址兑现和低位 mismatch 定向场景 PASS；`compile` 完成 reservation agent、
  memory agent 与空 design 的 parse、elaboration 和 link。2026-08-11 已确认完整验证通过。
- 结论：reservation agent 不执行 alignment policy；完整地址兑现仍是稳定协议检查。

### `SCB-001` 来源相关 MEM alignment

- 关闭日期：2026-08-11。
- 关闭类型：DUT contract 更新后不再适用，不需要实现或验证来源归属算法。
- 依据：下游 SRAM 支持从任意 byte address 开始的 32-Byte read/write；普通 V2M 只要求
  有效写 byte 的 BANK、BADDR、strobe 和 data 正确，不要求 MEM beat base 对齐。
- 文档：已更新 DUT overview、地址模型、MEM/VLM 接口、scoreboard、reference、memory
  agent 和 testpoint，并删除失效的 SCB-001 开发计划。
