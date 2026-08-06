# ut_shm Testcase 与 regression

本文定义 ut_shm 的 case、TC 和 LST 组织方式，并记录当前 case 矩阵能够控制或无法控制
的激励字段。需要了解某个 case 验证什么行为时，先查
[Testpoints](testpoints.md)；编译和运行命令放在[使用指南](../guide/index.md)。

## 1. Case、test 和 run

一个 case 由最终 UVM test class 和一组最终生效的 plusargs 构成：

```text
case = UVM_TESTNAME + effective plusargs
run  = case + seed
```

当前全部 case 最终使用 `shm_unit_test`。`v2m_unit_test`、`m2v_unit_test` 等名称是 TC
中的派生 case，不是 `uvm_test` class。它们通过继承公共参数并追加方向参数，减少每个
叶子 case 的重复配置。

同一个 case 用不同 seed 执行仍是同一个 case。Seed 只改变未被 plusarg 或 sequence
constraint 固定的随机字段；因此 case 被列入 regression 不表示某个概率场景必然发生，
必须用 functional coverage 证明实际命中。

## 2. TC 文件格式

### 2.1 Base testcase

没有冒号的 testcase header 设置 base testcase，并对应 `+UVM_TESTNAME`。后续 plusargs
持续到 `endargs`：

```text
shm_unit_test
+TRANS_NUM=16
+TRANS_DELAY_MIN=64
+TRANS_DELAY_MAX=128
endargs
```

### 2.2 继承

派生 case 使用 `derived_case: base_case`。它继承 base case 的 UVM test 和 plusargs，
并可追加或覆盖参数；最终 `UVM_TESTNAME` 仍是 base case 对应的 test class：

```text
v2m_unit_test: shm_unit_test
+CREQ_RW=SHM_V2M
endargs
```

叶子 case 可以继续继承派生配置：

```text
v2m_vec_loc_dtyp32_atyp16: v2m_unit_test
+CREQ_DTYPE=DTYP_32
+CREQ_ATYPE_W=ATYP_16
+CREQ_ITYPE=LDST_V
+CREQ_SPACE=SPACE_LOC
endargs
```

这笔 case 的有效配置是 `shm_unit_test` 的公共参数、`v2m_unit_test` 的方向参数和叶子
case 的四个字段之和。维护文档时不把三层参数误写成三个独立 UVM test。

### 2.3 Include

```text
INCLUDE: v2m/vec_loc.tc
```

`INCLUDE` 把子 TC 中的定义加入根 TC。当前 include 路径按 `ut_shm/tc/` 组织。注释掉的
include 不向根 TC 暴露其中 case；直接存在的子文件也不等于它已经进入主 regression。

## 3. 当前 case 层次

根文件 [`ut_shm.tc`](../../../ut_shm/tc/ut_shm.tc) 定义：

```text
shm_unit_test
├── v2m_unit_test
│   └── v2m_<instruction>_<space>_dtyp<width>_atyp<width>
├── m2v_unit_test
│   └── m2v_<instruction>_<space>_dtyp<width>_atyp<width>
└── v2m_vtrans_test
```

公共参数当前为：

|Plusarg|值|作用|
|---|---:|---|
|`TRANS_DELAY_MIN`|64|相邻 creq 的最小间隔|
|`TRANS_DELAY_MAX`|128|相邻 creq 的最大间隔|
|`TRANS_NUM`|16|每个 run 生成的 creq 数量|
|`EXTERNAL_BUSY_PERCENT`|40|reservation scheduler 注入 external busy 的概率|

`v2m_unit_test` 追加 `CREQ_RW=SHM_V2M`，`m2v_unit_test` 追加
`CREQ_RW=SHM_M2V`。`v2m_vtrans_test` 只追加 `VTRANS_EN=1`；VTRANS sequence 自身再约束
方向、space、dtype、itype、length 和 mask。

## 4. 普通 case 命名与矩阵

普通叶子 case 使用：

```text
<direction>_<instruction>_<space>_dtyp<width>_atyp<width>
```

|维度|名称|实际 plusarg|
|---|---|---|
|方向|`v2m`、`m2v`|`CREQ_RW=SHM_V2M/SHM_M2V`|
|Instruction|`vec`、`es`、`ev`|`LDST_V`、`LDSTE_S`、`LDSTE_V`|
|Address space|`loc`、`warp`、`blk`|`SPACE_LOC`、`SPACE_WRP`、`SPACE_BLK`|
|Data type|`dtyp32/16/8`|`DTYP_32/16/8`|
|Address width|`atyp32/16`|`ATYP_32/16`|

每个 `<direction, instruction, space>` 子文件定义
`3 DTYPE × 2 ATYPE_W = 6` 个叶子 case。当前 TC 源文件共包含 108 个普通叶子定义：
V2M 和 M2V 各 54 个。

当前普通矩阵没有覆盖：

- `LDST_S`；`vec` 当前只表示 `LDST_V`；
- `ATYP_8`；
- `ATYP_S` 与 `GAUTO_DW` 的定向组合；
- interleave size、WARP ID、WARP group、thread mask、ack 和 priority 的定向取值。

这些都是当前 case 维度的缺口，不是 spec 排除项。

## 5. 当前激励能力和限制

### 5.1 TC 可配置字段

`shmins_unit_sequence` 可以解析：

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

当前叶子 case 只固定其中的方向、DTYPE、ATYPE_W、ITYPE 和 SPACE。未固定字段继续使用
sequence 默认值或 transaction 随机值。

### 5.2 普通请求

普通 sequence inline constraint 当前固定：

- `creq_info=='0`；
- `creq_wpid==0`；
- direction、DTYPE、ATYPE_W、ITYPE 和 SPACE 等于 case 配置。

`CREQ_ATYPE_S` 和 `CREQ_ATYPE_G` 虽能被解析到 sequence，但没有约束到 request，见
`SHMINS-004`。`creq_tmsk` 在普通请求中随机为非全零值，已贯通 driver、monitor 和
reference，但没有 plusarg 或定向 case 控制其具体 pattern，见 `SHMINS-001`。地址约束
仍使用部分 2 的幂边界，不能保证排除 12 KiB 编码空洞，见 `SHMINS-003`。

`creq_inv_size`、`creq_ack_en`、priority、length、element mask、base、offset、vaddr 和
wpnum 等字段主要依赖随机化。没有 functional coverage 时，单个 seed 不能证明这些
随机维度已经命中目标边界。

### 5.3 VTRANS

`v2m_vtrans_test` 使能 VTRANS 后，sequence 固定：

- `SHM_V2M`、`SPACE_LOC`；
- `DTYP_8` 或 `DTYP_16`；
- `LDST_S` 或 `LDST_V`；
- 每个 thread 16 个 element；
- 所有 element mask 为 1；
- `creq_wpid==0`。

VTRANS sequence 已按 spec 约束 `creq_tmsk=='1`。VTRANS 仍只有一个 case，DTYPE 和
ITYPE 由 seed 随机选择；没有 coverage 时，不能确认四个合法组合都出现。

### 5.4 `LDSTE_S + SPACE_WRP/SPACE_BLK`

该组合在 M2V 中受支持。当前 M2V 子 TC 已定义并由根 TC include，但 12 个对应叶子
case 尚未列入 `m2v.lst`。

V2M 中不同 thread 的 element 0 会按 `base + 0*offset` 访问相同 MADDR；多个写对同一
地址的结果未定义。因此根 TC 注释了 V2M 的 `es_warp.tc` 和 `es_blk.tc` include，
`v2m.lst` 也没有这些 case。若要定向验证其余 element，激励至少必须令所有 thread 的
`creq_vmsk[*][0]==0`，并保持其他有效 element 的写地址无冲突。当前 sequence/case 尚
不支持该约束，见 `SHMINS-007`。

## 6. LST 文件格式

Regression 文件的普通条目为：

```text
case_name : RUN=n
case_name : RUN=1 SEED=num
```

规则如下：

1. 所列 case 必须存在于根 TC 能解析到的定义中。
2. `RUN=n` 表示用不同随机 seed 执行同一个 case `n` 次。
3. `SEED=num` 固定 seed；指定固定 seed 时 `RUN` 必须为 1。
4. `INCLUDE: child.lst` 把子 regression 列表加入当前列表。

固定 seed 适合复现失败，不应长期代替 functional coverage。增加 `RUN` 只能提高随机
命中概率，也不能证明目标 bin 已经覆盖。

## 7. 当前 regression

|文件|内容|Case 数|
|---|---|---:|
|[`v2m.lst`](../../../ut_shm/regression/v2m.lst)|普通 V2M 矩阵，加 VTRANS|43|
|[`m2v.lst`](../../../ut_shm/regression/m2v.lst)|普通 M2V 矩阵|42|
|[`ut_shm.lst`](../../../ut_shm/regression/ut_shm.lst)|include 前两份列表|85|

普通 V2M 和 M2V regression 都包含：

- `vec` 的 LOC、WRP、BLK；
- `ev` 的 LOC、WRP、BLK；
- `es` 的 LOC。

两份列表都没有 `es + WRP/BLK`。对 V2M，这是前述未定义重叠写限制；对 M2V，spec
支持且 TC 已存在，因此当前 regression 仍未覆盖这 12 个 case。

所有条目当前都是 `RUN=1`，没有固定 `SEED`。这些文件描述目标运行集合，不记录近期
服务器运行结果，也不能作为 case 已通过或功能已覆盖的证据。

## 8. 维护规则

- 新 case 必须先关联至少一个 testpoint，不能只扩充名称矩阵。
- TC 继承或公共 plusarg 改动后，应检查所有叶子 case 的 effective configuration。
- LST 不得引用根 TC 无法解析的 case；定义、include 和 regression 选择是三个不同状态。
- Case 改名时同步更新 LST 和 testpoint 映射。
- Sequence 新增可配置字段时，必须确认 plusarg 实际约束 request，并在 testcase 文档中
  说明固定值与随机值。
- `RUN`/`SEED` 只属于执行组织。运行命令、日志目录和服务器流程统一放在 guide。
