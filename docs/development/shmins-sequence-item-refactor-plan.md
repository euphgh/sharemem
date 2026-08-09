# shmins sequence item 拆分开发计划

本文规定 `shmins_sequence_item` 随机化性能重构的设计边界、目标结构、开发阶段和验收
证据。Benchmark 阶段已经完成 contiguous、strided 和 indexed 原型及交叉性能测试；当前
阶段把 SPLIT 实现接入 `ut_shm` 正式 sequence item package 和 master unit sequence。
Driver、monitor、reference 和 scoreboard 继续通过公共 `shmins_sequence_item` handle
工作，不按地址拓扑派生新的组件类型。

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
2. 只让低成本公共字段进入 solver，MADDR、base 和 offset 由子类与基类 helper
   过程式构造；
3. 由独立 validator 复查 packed offset 和最终 transaction，不信任生成算法自身；
4. 保留 original 和 monolithic post-randomize 实现作为性能基线；
5. 保持 driver、monitor、sequencer 和 reference 使用的公共 transaction API；
6. 在远端 EDA 服务器上完成无 DUT 的 package/sequence 编译，再进入真实 DUT testcase。

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

`offs_elem` 和 `elem_maddr` 保留为公开的过程式生成与调试结果，不声明为
`rand`。`elem_maddr[t][k]` 保存每个 active element 的完整 MADDR；inactive entry
每次生成前清零，不参加合法性判定。`creq_base` 也不再声明为 `rand`，由子类在
MADDR 确定后通过基类 helper 生成。

基类只保留低成本 solver 约束：合法 enum、interleave、WARP、thread mask、
length/element capacity 和 M2V vaddr。`creq_wpid` 和 `creq_wpnum` 仍为低成本随机
控制字段，并在 SPACE_BLK 中决定 MADDR 候选 group。base 范围与对齐不再由
solver constraint 表达。

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
fast_legal_space_range(space_lower, space_upper);
legal_space_maddr_check(thread_idx, maddr);
map_maddr(thread_idx, maddr, result);
physical_byte_key(bank_id, baddr);
uniqueness_required();
check_active_maddr_byte_uniqueness();
decoded_offset_range(decode_lower, decode_upper);
intersect_creq_base_range(target, base_lower, base_upper);
validate_transaction();
```

其中 `fast_legal_space_range()` 返回左闭右开的快速编码域：

```text
SPACE_LOC: [0, WARP_STEP)
SPACE_WRP: [0, coded_warp_bytes * BANK_N)
SPACE_BLK: [selected_group * group_span, (selected_group + 1) * group_span)
```

该范围不排除 8/16 KiB interleave 下的地址空洞。候选 MADDR 随机后必须通过
`legal_space_maddr_check()` 复查数值范围、dtype 自然对齐、空洞、BANK 和
SPACE_BLK WARP group。

地址映射结果至少包含 `valid`、`bank_id`、完整 `baddr`、`local_offset` 和 `warp_index`。
`check_active_maddr_byte_uniqueness()` 对 V2M 和显式开启 uniqueness 的 M2V 使用最终
物理 byte key，逐 byte 检查 1/2/4-byte element，不能只比较 element 起始 MADDR。
SPACE_LOC 中不同 thread 自然按 BANK 分域；SPACE_WRP/BLK 对全部 active element
使用同一物理 byte key 集合。

`decoded_offset_range()` 按 ATYPE_W/S/G 和 dtype 计算 decoded offset 闭区间
`[decode_lower, decode_upper]`。若某个 topology 目标值满足
`target=creq_base+decoded_offset`，则该 target 对 base 的约束为：

```text
target - decode_upper <= creq_base <= target - decode_lower
```

所有 target 取交集后：

```text
max(target) - decode_upper <= creq_base <= min(target) - decode_lower
```

`intersect_creq_base_range()` 增量完成该交集，并把 base 范围限制到
`[0, 2**MADDR_W-1]`。GAUTO_DW 下 decoded offset 是 dtype byte width 的倍数，已对齐
MADDR 会自然推出 base 对齐。GAUTO_1B 第一版仍从交集中选择 dtype 对齐
base，作为激励限制而非协议要求。

基类 `post_randomize()` 只负责编排：

```systemverilog
function void shmins_sequence_item::post_randomize();
  reset_generation_state();
  generate_address_fields();
  check_generated_maddrs();
  pack_offsets();
  validate_transaction();
endfunction
```

`generate_address_fields()` 由子类覆盖，填充 `elem_maddr`、`creq_base` 和 `offs_elem`。
基类仍需能被 monitor 类似的非随机化消费者构造，因此
不声明为 virtual class；直接随机化基类必须用稳定 report ID 明确拒绝。Validator 必须
从 `creq_offs_packed` 重新解码并计算 MADDR，与 `elem_maddr` 比较后再独立检查
space 和 collision，不能只检查过程式中间结果。

## 5. 子类随机算法

### 5.1 Contiguous

每个 active thread 从 `fast_legal_space_range()` 返回的编码域中生成一个 dtype 对齐
`start_maddr[t]`，再按以下公式回填完整 active MADDR 数组：

```text
elem_maddr[t][k] = start_maddr[t] + k*D
```

快速 start 范围根据最大 active index 从 space 上界向下收缩。因为该范围不能排除
地址空洞，候选后必须对全部 active element 调用 `legal_space_maddr_check()`。

Contiguous 的 decoded offset 只有 `offs_elem[t][0]`，因此 base 交集使用
`start_maddr[t]`，不直接使用每个 `elem_maddr[t][k]`。若从完整数组推导，需先归一化为
`elem_maddr[t][k]-k*D`，其结果应全部等于 `start_maddr[t]`。所有 thread 完成后从
base 交集中生成 `creq_base`，再计算 `offs_elem[t][0]=start_maddr[t]-creq_base`。

最后对完整 `elem_maddr` 执行逐 byte uniqueness 检查；冲突或 base 交集为空时重新
生成候选。候选必须从 space 编码域产生，不能从完整 ATYP32 空间盲抽。该
路径优先解决已观察到的 `V2M + LDST_V + SPACE_LOC + DTYP_32 + ATYP_32`
慢随机问题。

### 5.2 Strided

每个 active thread 生成一个 stride，按公式回填 `elem_maddr`，并对全部 active index 验证
`MADDR[k]=base+k*stride`。算法必须覆盖 signed stride、向低地址增长、零 stride 重叠和
非连续 active mask。V2M WRP/BLK 的 element 0 在 solver 基础约束中直接 mask；M2V 不
应用该限制。由于 encoded offset 表示 stride，不表示 `elem_maddr-base`，strided 不能
直接对所有 MADDR 套用 contiguous/indexed 的 base 交集公式。

### 5.3 Indexed

每个 active element 先从 space 的快速 MADDR 编码域生成目标地址，通过
`legal_space_maddr_check()` 后写入 `elem_maddr[t][k]`。Indexed 的每个 MADDR 都是
`base+decoded_offset` 的 target，因此逐 element 更新 base 交集，最后计算
`offset[t][k]=elem_maddr[t][k]-base`。V2M 和显式 unique M2V 使用基类逐 byte
uniqueness 检查；M2V 默认允许重复地址。

### 5.4 VTRANS

VTRANS 继承 contiguous，只增加方向、`creq_info==4'hf`、SPACE_LOC、dtype/itype、全
thread mask、16-element length 和全 element mask 限制。它不复制 contiguous 地址算法。

## 6. Sequence 配置与正式环境接入

### 6.1 Sequence 层级和对象创建

不再维护旧的 `shmins_mst_sequence`。`shmins_unit_sequence` 重命名为
`shmins_mst_unit_sequence`，并直接继承：

```systemverilog
uvm_sequence #(shmins_sequence_item)
```

Sequence 每笔 transaction 显式创建拓扑子类。禁止使用全局 factory override 把公共
基类替换为某一个子类，因为同一 sequence 可以产生多种 ITYPE，monitor 也仍需创建不参与
随机化的公共基类对象。

Normal transaction 必须先从允许的 ITYPE 集合选择本笔 `selected_itype`，再创建：

```text
LDST_S、LDST_V -> shmins_contiguous_sequence_item
LDSTE_S        -> shmins_strided_sequence_item
LDSTE_V        -> shmins_indexed_sequence_item
```

VTRANS 直接创建 `shmins_vtrans_sequence_item`。该类继承 contiguous，只覆盖普通请求
类型约束并增加 VTRANS 的协议限制，不重写地址生成算法。

### 6.2 Normal allowed-value domain

`shmins_mst_unit_sequence` 不使用 value 加 `is_fixed` 的双变量配置，也不保留位置参数较多
的 `config_item()`。每个基本控制字段使用一个无重复元素的 queue 表示当前允许集合：

```systemverilog
creq_dtype_e   normal_dtype_domain[$];
creq_atype_w_e normal_atype_w_domain[$];
creq_atype_s_e normal_atype_s_domain[$];
creq_atype_g_e normal_atype_g_domain[$];
creq_rw_e      normal_rw_domain[$];
creq_itype_e   normal_itype_domain[$];
creq_space_e   normal_space_domain[$];
```

初始集合包含对应字段的全部协议合法枚举值。空配置因而表示 normal 大随机；singleton
表示固定值；多元素子集表示受限随机。公开 setter 包括：

```text
set_fix_dtype()    set_fix_atype_w()  set_fix_atype_s()
set_fix_atype_g()  set_fix_rw()       set_fix_itype()
set_fix_space()
```

Setter 只允许把当前集合缩小为其中一个值。参数不在当前集合时立即报告配置错误；重复设置
相同值是幂等操作，不额外维护 configured flag。所有 domain 在 sequence 启动前必须非空。

Item randomize 使用 `inside {local::domain}` 约束 allowed-value queue，不能把 enum 字段与
queue 用 `==` 比较。ITYPE 是唯一必须在创建 item 前选出具体值的字段；它在每笔
transaction 重新选择，因此不属于 sequence 级 fixed 配置。

### 6.3 独立 VTRANS allowed-value domain

VTRANS 与 normal 使用互不修改的配置集合：

```text
dtype   = {DTYP_16, DTYP_8}
atype_w = {ATYP_32, ATYP_16}
atype_s = {ATYP_U, ATYP_S}
atype_g = {GAUTO_1B, GAUTO_DW}
itype   = {LDST_S, LDST_V}
```

公开 setter 为 `set_fix_vtrans_dtype()`、`set_fix_vtrans_atype_w()`、
`set_fix_vtrans_atype_s()`、`set_fix_vtrans_atype_g()` 和
`set_fix_vtrans_itype()`。VTRANS 的 `rw==SHM_V2M`、`space==SPACE_LOC` 和
`creq_info==4'hf` 是协议常量，由 VTRANS item 约束，不提供 sequence 配置 API。

`atype_g` 虽然不影响数据转置，仍参与普通 offset 解码和 MADDR 计算，因此必须保留在
VTRANS domain 中。

### 6.4 全局 VTRANS 概率

`set_vtrans_en(int unsigned percentage=100)` 配置每笔 transaction 为 VTRANS 的全局
概率，参数范围为 0～100。未调用时内部概率为 0：

```text
0   -> 只生成 normal transaction
1～99 -> 按全局比例混合 normal 和 VTRANS
100 -> 只生成 VTRANS transaction
```

选择 VTRANS 后只使用 VTRANS domain；选择 normal 后只使用 normal domain。两套配置
互不求交，因此 `normal rw={SHM_M2V}` 与非零 VTRANS 概率可以合法共存。100% VTRANS
也不缩小或覆盖 normal domain。

### 6.5 时间和命令行配置

`config_time(trans_num, delay_max, delay_min)` 保留，启动前检查 transaction 数量非负且
delay 区间非空。已有 `TRANS_NUM`、`TRANS_DELAY_MIN/MAX`、`CREQ_*` 和 `VTRANS_EN`
plusarg 保留；出现的 `CREQ_*` 通过 normal setter 缩小对应 domain，`VTRANS_EN` 解析为
0～100 的全局概率。VTRANS 专用 domain 第一版只通过公开 API 配置，不复用 normal
`CREQ_*` plusarg。

### 6.6 Package 和兼容边界

正式 `shm_seq_item_package` include 公共基类、contiguous、strided、indexed、VTRANS 和
enum helper；`shm_seq_package` 只 include `shmins_mst_unit_sequence`。公共基类保留
driver、monitor、reference 和 `shm_wtrans_item` 已使用的字段、copy、RTL pack/unpack 和
地址 helper API。旧 solver item 只作为 benchmark ORIGINAL 基线，不再进入正式 package。

## 7. Benchmark 基线

Benchmark 保留三种实现选择：

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

## 8. 开发阶段

1. **公共 checker**：先实现 offset 编解码、active-element、三种 space 映射、自然对齐、
   hole、WARP group 和物理 byte collision 的独立 validator。
2. **基类**：迁移公共字段/API，移除 `rand offs_elem` 和大型 solver 地址/collision 约束。
3. **Contiguous**：实现合法区间构造，首先复现并修复已知慢 profile。
4. **Indexed**：实现逐 active element 的合法 MADDR 采样和提交。
5. **Strided**：实现 stride 可达区间、element 0 和 signed stride 规则。
6. **VTRANS**：复用 contiguous 并增加输入限制。
7. **Benchmark**：增加 SPLIT build、字段 knobs、profile matrix 和统计。
8. **Benchmark 验证**：完成三种拓扑的交叉性能和无 inline override 测量。
9. **正式集成**：增加 VTRANS 子类、domain-based master unit sequence 和 package include。
10. **空 design 编译**：不依赖真实 DUT，编译正式 item/sequence 源码和最小 UVM top。
11. **系统验证**：空 design 编译通过后，由独立阶段运行真实 DUT testcase/regression。

截至 2026-08-09，contiguous、strided 和 indexed 及 432 组交叉配置已经完成远端编译和
随机化测试；阶段 9 的正式 package/sequence 接入和阶段 10 的空 design VCS 编译已经完成。
Driver、monitor、reference、scoreboard 和真实 DUT regression 不在本次修改范围；发现
contract 冲突时记录到 verification status，不顺带改变 DUT 检查语义。

## 9. 远端验证矩阵和证据

本地工作区没有 EDA 工具，不运行 VCS。先加载本地 `.env`，再使用
`scripts/local/sync_remote_repo.sh` 同步必要输入，并通过
`scripts/local/run_remote_command.sh` 在 `.env` 指定的 hx16 工作区执行。
生成的 simv、日志和计时结果留在远端
`examples/shmins_random_benchmark/build/` 目录；`.env` 本身不同步。

正式集成的第一道门槛是空 design compile：最小 UVM top include 与正式 package 相同的
公共基类、四种子类、enum helper 和 `shmins_mst_unit_sequence`，但不实例化真实 DUT，
也不运行功能 testcase。该测试只证明 SystemVerilog/UVM 语法、继承、constraint、factory
注册和 queue-based inline constraint 可以由目标 VCS 接受。

2026-08-09 使用远端 VCS `W-2024.09-SP1_Full64` 执行：

```text
scripts/ubuntu/check_shmins_sequence_vcs.sh compile
```

公共基类、contiguous、strided、indexed、VTRANS、enum helper 和
`shmins_mst_unit_sequence` 均完成 parse、elaboration 和 simv link，无编译 error。VCS 报告
Linux 6.17 kernel 不在支持列表，该环境 warning 未阻止编译。

后续功能最低矩阵包括：

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

## 10. 当前集成阶段验收条件

- 正式 item package include 公共基类和四种 topology/request 子类；
- `shmins_mst_unit_sequence` 不依赖已删除的 `shmins_mst_sequence`；
- 空 normal domain 语义不存在，完整初始 domain 表示大随机；setter 只能保持或缩小集合；
- normal 和 VTRANS domain 互不修改，全局 VTRANS 概率的 0、部分、100 语义明确；
- sequence 显式创建正确子类，所有 queue 通过 `inside` 参与 inline constraint；
- 远端空 design VCS compile 无 error；
- 本阶段编译通过只作为正式激励源的语法/结构证据，不作为 DUT 功能或系统 regression
  通过证据。

## 11. 暂缓项

以下工作不属于本阶段：

- 修改 driver、monitor、reference、scoreboard；
- 修复 `REF-001` 或以现有 reference 验证非零 SPACE_BLK group；
- 运行真实 DUT case、TC/LST regression 或 functional coverage；
- 提取 address-space policy class；
- 放宽 base 和 decoded offset 分别自然对齐的临时激励限制；
- 删除 original 或 monolithic benchmark 基线。

空 design 编译通过后仍需另立系统验证阶段，重新检查 `SHMINS-002`～`SHMINS-007`、真实
DUT testcase、完整 ut_shm elaboration 和 regression 证据。
