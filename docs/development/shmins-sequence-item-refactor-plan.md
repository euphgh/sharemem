# shmins sequence item 拆分开发计划

本文规定 `shmins_sequence_item` 随机化性能重构的设计边界、目标结构、开发阶段和验收
证据。本阶段只开发并验证 `examples/shmins_random_benchmark/` 使用的新实现，不把它接入
`ut_shm` 正式 package、driver、monitor、reference、scoreboard、testcase 或 regression。

DUT 地址与 creq 合法性仍以 [地址模型](../ut_shm/spec/address-model.md)和
[creq/ack 接口](../ut_shm/spec/creq-ack-interface.md)为准。本文描述如何产生合法激励，
不重新定义 DUT 行为。实现问题由
[`SHMINS-012`](../ut_shm/verification-status.md#shmins-012-sequence-item-随机化性能与结构拆分)
跟踪；正式环境尚未满足完整地址规则的问题仍由 `SHMINS-003` 跟踪。

## 1. 背景和目标

当前 solver-based `shmins_sequence_item` 让大型 `offs_elem` 数组同时参与地址范围、
solve-order、全局 uniqueness 和 thread range non-overlap 求解。许多 inactive thread、
超出实际 length 或被 mask 的 element 也进入 solver，部分组合的随机化时间过长。

现有 `shmins_post_randomize_sequence_item` 把 collision 检查移到 `post_randomize()`，但仍把
不同地址生成形态、space、方向和 retry 算法集中在一个 class 中。它还保留旧的
`c_addr_bound`，并从完整 ATYPE 编码域抽取候选，仍可能求解缓慢或耗尽 retry。

本阶段目标是：

1. 按 MADDR 生成形态拆分随机算法，避免 `itype × space × direction` 的组合类爆炸；
2. 只让低成本公共字段进入 solver，offset 由子类从合法地址域过程式构造；
3. 由独立 validator 复查 packed offset 和最终 transaction，不信任生成算法自身；
4. 保留 original 和 monolithic post-randomize 实现作为性能基线；
5. 仅在 hx16 上编译、运行和比较 `examples/shmins_random_benchmark/`。

## 2. 已确认的约束边界

### 2.1 协议硬约束

只有会形成访问的 element 参加地址合法性检查：

```text
active(t, k) = creq_tmsk[t]
             && k < creq_len[t] / data_byte_width
             && creq_vmsk[t][k]
```

每个 active element 必须满足：

- raw offset 按 ATYPE_W 做 16/32-bit 解码，并按 ATYPE_S 符号扩展或零扩展；
- GAUTO_DW 把解码值乘以 dtype byte width，GAUTO_1B 不缩放；
- 按 ITYPE 公式计算的最终 MADDR 禁止截断回绕；
- 最终 MADDR 按 dtype byte width 自然对齐；
- MADDR 满足 LOC、WRP 或 BLK 的编码范围、12 KiB 实际容量和地址空洞规则；
- SPACE_BLK 的 `warp_index` 合法，并与 `creq_wpid` 位于同一个 `creq_wpnum` 对齐组。

协议只要求最终 MADDR 自然对齐，不要求 `creq_base` 和 decoded offset 各自自然对齐。
本阶段为了简化候选构造，允许使用更强的激励限制：分别约束 base 和 decoded offset 按
dtype 自然对齐。独立 validator 仍必须直接检查最终 MADDR；以后放宽激励限制时不得依赖
base/offset 分别对齐代替协议检查。

### 2.2 当前环境的可判定激励限制

当前 reference 对单笔 V2M 中重复写同一物理 byte 报 overlap。为使 benchmark 生成的
transaction 能继续用于后续集成准备，新实现采用以下激励策略：

- V2M 的 active write byte 不得映射到相同 `<BANK, BADDR>`；
- SPACE_LOC 中不同 thread 固定进入不同 BANK，uniqueness key 可以按 thread 分域；
- SPACE_WRP/SPACE_BLK 对所有 active thread 使用全局物理 byte key；
- `V2M + LDSTE_S + SPACE_WRP/SPACE_BLK` 必须 mask active thread 的 element 0；
- M2V 重复读取合法，默认不要求 unique；可选 M2V uniqueness 只能作为 benchmark
  压力或诊断配置，不能解释为 DUT 协议。

LDST 的 thread range non-overlap 和 `unique {offs_elem}` 只是实现上述目标的保守旧方法。
新实现检查 active 物理 byte，不再约束完整二维 offset 数组。

### 2.3 实现保护，不是协议

Retry 上限、候选采样窗口、benchmark constraint-set、对象复用和统计计数均属于实现或
测量策略。它们不得被写成 DUT 合法性规则，也不得在没有诊断的情况下排除合法地址。

## 3. 目标继承结构

```text
shmins_sequence_item
├── shmins_contiguous_sequence_item   // LDST_S、LDST_V
│   └── shmins_vtrans_sequence_item   // 特殊 V2M LDST
├── shmins_strided_sequence_item      // LDSTE_S
└── shmins_indexed_sequence_item      // LDSTE_V
```

继承按地址生成拓扑划分：

|Class|支持的 ITYPE|每个 thread 的随机参数|MADDR 公式|
|---|---|---|---|
|`shmins_contiguous_sequence_item`|`LDST_S`、`LDST_V`|一个起始 offset|`base+offset[t]+k*D`|
|`shmins_strided_sequence_item`|`LDSTE_S`|一个 stride|`base+k*stride[t]`|
|`shmins_indexed_sequence_item`|`LDSTE_V`|每个 active element 一个 offset|`base+offset[t][k]`|
|`shmins_vtrans_sequence_item`|受限 LDST|继承 contiguous|地址不变，只增加 VTRANS 输入限制|

SPACE_LOC/WRP/BLK 在第一版作为基类公共 helper 中的策略分支，不建立 policy class。
只有在三个子类出现重复的 space 候选枚举逻辑后，才考虑提取
`shmins_address_space_policy` 对象。V2M/M2V 只改变 collision 策略，不形成方向子类。

## 4. 基类职责和 API

`shmins_sequence_item` 继续作为公共 transaction 类型。为将来接入正式环境保留现有
公共字段、factory 注册和以下 API：

- `creq_offs()`、`set_creq_offs()`；
- `item_to_rtl()`、`rtl_to_item()`；
- 完整的 `do_copy()` 和明确的 compare contract；
- dtype、atype、length、mask、delay 和 creq payload 字段。

`offs_elem` 可以保留为公开的调试结果，但不再声明为 `rand`。基类只保留低成本 solver
约束：合法 enum、interleave、WARP、thread mask、length/element capacity、M2V vaddr
以及本阶段采用的 base 自然对齐限制。

基类提供下列公共或 protected helper；具体命名可在实现 review 中调整，但职责不能重新
混回子类：

```systemverilog
data_byte_w();
offs_bit_w();
offs_elem_max();
gran_shift();
thread_elem_cnt(thread_idx);
is_active_element(thread_idx, elem_idx);
check_offset_encodable(offset);
pack_offsets();
decode_packed_offset(thread_idx, elem_idx);
map_maddr(thread_idx, maddr, result);
check_maddr(thread_idx, maddr);
physical_byte_key(bank_id, baddr);
uniqueness_required();
validate_transaction();
```

地址映射结果至少包含 `valid`、`bank_id`、完整 `baddr`、`local_offset` 和 `warp_index`。
collision 使用最终物理 byte key，不能只比较 element 起始 MADDR。

基类 `post_randomize()` 只负责编排：

```systemverilog
function void shmins_sequence_item::post_randomize();
  reset_generation_stats();
  generate_offsets();
  pack_offsets();
  validate_transaction();
endfunction
```

`generate_offsets()` 由子类覆盖。基类仍需能被 monitor 类似的非随机化消费者构造，因此
不声明为 virtual class；直接随机化基类必须用稳定 report ID 明确拒绝。Validator 必须
从 `creq_offs_packed` 重新解码并计算 MADDR，不能只检查 `offs_elem` 中间结果。

## 5. 子类随机算法

### 5.1 Contiguous

每个 active thread 先找 active element 的最小和最大 index，再从当前 space 的合法 MADDR
窗口反推可编码的起始 offset。选中候选后检查所有 active element 的自然对齐、hole、
WARP group 和物理 byte。V2M 接受一个 thread 后提交其 byte key，后续 thread 避开重叠。

候选必须从合法地址域或其反推区间产生，不能从完整 ATYP32 空间盲抽。该路径优先解决
已观察到的 `V2M + LDST_V + SPACE_LOC + DTYP_32 + ATYP_32` 慢随机问题。

### 5.2 Strided

每个 active thread 生成一个 stride，并对全部 active index 验证
`MADDR[k]=base+k*stride`。算法必须覆盖 signed stride、向低地址增长、零 stride 重叠和
非连续 active mask。V2M WRP/BLK 的 element 0 在 solver 基础约束中直接 mask；M2V 不
应用该限制。

### 5.3 Indexed

每个 active element 先从 space 的合法 MADDR 集合选择目标地址，再计算
`offset=target_maddr-base` 并检查 ATYPE/S/G 可编码。V2M 在接受候选后提交物理 byte key；
M2V 默认允许选择已有地址。

### 5.4 VTRANS

VTRANS 继承 contiguous，只增加方向、`creq_info==4'hf`、SPACE_LOC、dtype/itype、全
thread mask、16-element length 和全 element mask 限制。它不复制 contiguous 地址算法。

## 6. Benchmark 接入

本阶段不修改 `ut_shm/env/shm_seq_item_package.sv`。Benchmark 增加第三种实现选择：

```text
ORIGINAL          当前 solver-based item
POST_RANDOMIZE    当前 monolithic post-randomize item
SPLIT             本计划的新基类和子类
```

三种实现必须在互相隔离的 compilation 中定义各自的 `shmins_sequence_item`，不能同时
include。为避免在原型阶段覆盖正式文件，新基类可以暂用独立文件名；未来决定集成时再
替换正式 `shmins_sequence_item.svh`。

Split benchmark 根据固定 profile 显式创建子类。`RANDOM` profile 若允许每次改变 ITYPE，
必须在每次 attempt 前选择拓扑并创建相应子类；它不能在复用同一个对象时改变 class。

Benchmark 还需增加或确认以下可控字段，不能继续只固定 DTYP_8/ATYP_16：

- dtype；
- ATYPE_W、ATYPE_S、ATYPE_G；
- direction；
- ITYPE/space profile；
- M2V optional uniqueness；
- iteration、warmup、seed 和 object reuse。

统计至少包括 randomize 成败、validator error、retry exhaustion、每种 reject 原因、
`elapsed_ms`、`ms_per_attempt`、attempts per second 和 checksum。

## 7. 开发阶段

1. **公共 checker**：先实现 offset 编解码、active-element、三种 space 映射、自然对齐、
   hole、WARP group 和物理 byte collision 的独立 validator。
2. **基类**：迁移公共字段/API，移除 `rand offs_elem` 和大型 solver 地址/collision 约束。
3. **Contiguous**：实现合法区间构造，首先复现并修复已知慢 profile。
4. **Indexed**：实现逐 active element 的合法 MADDR 采样和提交。
5. **Strided**：实现 stride 可达区间、element 0 和 signed stride 规则。
6. **VTRANS**：复用 contiguous 并增加输入限制。
7. **Benchmark**：增加 SPLIT build、字段 knobs、profile matrix 和统计。
8. **hx16 验证**：同步 benchmark 所需最小输入，在映射工作区运行 VCS benchmark。
9. **结果复核**：记录命令、VCS 版本、seed、三次重复结果和未覆盖范围，再决定是否进入
   正式环境集成阶段。

截至 2026-08-08，阶段 1～3 已完成第一版，阶段 7 已完成 SPLIT
contiguous profile 与定向地址字段控制，阶段 8 已完成 compile 和三个
100-attempt 代表配置。阶段 4～6、完整矩阵和三次基线对比仍待完成，
因此 `SHMINS-012` 保持“实现中”。

本阶段不得顺带修改 driver、monitor、reference、scoreboard、TC/LST 或正式 package。
若开发中发现这些组件 contract 与新 validator 冲突，只记录到 verification status，
不扩大本阶段实现范围。

## 8. hx16 验证矩阵和证据

本地工作区没有 EDA 工具，不运行 VCS。先加载本地 `.env`，再使用
`scripts/local/sync_remote_repo.sh` 同步必要输入，并通过
`scripts/local/run_remote_command.sh` 在 `.env` 指定的 hx16 工作区执行。
生成的 simv、日志和计时结果留在远端
`examples/shmins_random_benchmark/build/` 目录；`.env` 本身不同步。

最低矩阵包括：

- contiguous、strided、indexed 的 LOC/WRP/BLK 固定 profile；
- V2M 和 M2V；
- DTYP_8/16/32；
- ATYP_16/32、signed/unsigned、GAUTO_1B/GAUTO_DW；
- `creq_inv_size` 的 4 KiB、8 KiB、16 KiB 分界及代表性小粒度；
- WARP group 0 和非零 group，`creq_wpnum` 为 1/2/4；
- 稀疏 tmsk/vmsk、最小/最大 length；
- VTRANS 支持的 dtype/itype 组合。

每个用于性能结论的配置采用相同 VCS 版本、profile、字段配置、iteration、warmup、reuse
和 seed，对三种实现各运行至少三次。先用小 iteration 排除长时间卡住，再使用不少于
100 次 measured attempt 形成正式结果。

## 9. 本阶段验收条件

- SPLIT benchmark 在 hx16 上完成 VCS compile 和所有 required profile；
- required run 的 `failures==0`、validator error 为 0、retry exhaustion 为 0；
- 每笔成功 transaction 的所有 active MADDR 自然对齐且满足 range、hole 和 group；
- V2M 没有 active 物理 byte collision，M2V 合法重复地址不误报；
- `V2M + LDSTE_S + WRP/BLK` 的 active element 0 全部被 mask；
- 已知慢 profile 能稳定完成不少于 100 次 attempt；
- 同配置三次运行的 median `ms_per_attempt` 低于 ORIGINAL 和 monolithic
  POST_RANDOMIZE；其他 required profile 若出现明显性能回退，必须记录原因后才能验收；
- 日志保存实现名、命令、VCS 版本、seed、配置、次数、checksum 和 reject 统计；
- 不修改或编译正式 `ut_shm` 集成路径，benchmark 通过不作为 DUT 功能或系统 regression
  通过证据。

## 10. 暂缓项

以下工作不属于本阶段：

- 把新实现接入 `shm_seq_item_package` 或 unit sequence；
- 修改 driver、monitor、reference、scoreboard；
- 修复 `REF-001` 或以现有 reference 验证非零 SPACE_BLK group；
- 运行真实 DUT case、TC/LST regression 或 functional coverage；
- 提取 address-space policy class；
- 放宽 base 和 decoded offset 分别自然对齐的临时激励限制；
- 删除 original 或 monolithic benchmark 基线。

进入正式集成前必须另立阶段，重新检查 `SHMINS-002`～`SHMINS-007`、API 兼容性和完整
ut_shm 语法/elaboration 证据。
