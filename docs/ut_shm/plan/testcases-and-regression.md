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

109-case 普通矩阵最终使用 `shm_unit_test`。`v2m_unit_test`、`m2v_unit_test` 等名称是 TC
中的派生 case，不是 `uvm_test` class。它们通过继承公共参数并追加方向参数，减少每个
叶子 case 的重复配置。P0 双 gid和 mask/VTRANS 定向组直接使用独立 UVM test class，
不继承 `shm_unit_test` 的随机 transaction 配置。

测试源码按是否依赖真实 design 分目录：只有必须实例化并检查真实 DUT 行为的 UVM test
放在 `ut_shm/tests/`；sequence item、agent、checker 或 memory model 等不依赖真实 design
的组件测试放在 `examples/`。组件测试不进入 TC/LST，也不能作为 DUT 功能通过证据。

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
并可追加或覆盖参数；最终 `UVM_TESTNAME` 仍是 base case 对应的 test class。需要注意的是，继承额base_case必须在tc中被如2.1定义过，不可以直接使用一个未定义的UVM_TESTNAME：

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
├── v2m_vtrans_test
├── shm_dbank_wpid_boundary_test
├── shm_dbank_gid_isolation_test
├── shm_m2v_vaddr_boundary_test
├── shm_reservation_gid_ownership_test
├── shm_tmsk_directed_test
├── shm_vtrans_full_mask_test
├── shm_payload_dontcare_x_test
├── shm_m_read_then_write_order_test
├── shm_m_write_then_read_order_test
├── shm_m_write_then_write_order_test
└── shm_v_write_then_write_order_test
```

公共参数当前为：

|Plusarg|值|作用|
|---|---:|---|
|`TRANS_DELAY_MIN`|64|相邻 creq 的最小间隔|
|`TRANS_DELAY_MAX`|128|相邻 creq 的最大间隔|
|`TRANS_NUM`|16|每个 run 生成的 creq 数量|
|`EXTERNAL_BUSY_PERCENT`|10|reservation scheduler 注入 external busy 的概率|

`v2m_unit_test` 追加 `CREQ_RW=SHM_V2M`，`m2v_unit_test` 追加
`CREQ_RW=SHM_M2V`。`v2m_vtrans_test` 追加 `VTRANS_EN=100`；VTRANS sequence 自身再约束
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
- `ATYP_S` 与 `GAUTO_DW` 的定向组合；
- interleave size、WARP ID、WARP group、thread mask、ack 和 priority 的定向取值。

这些都是当前 case 维度的缺口，不是 spec 排除项。

## 5. 当前激励能力和限制

### 5.1 TC 可配置字段

`shmins_mst_unit_sequence` 可以解析：

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

出现的 `CREQ_*` 把 normal allowed-value domain 缩小到 singleton；未出现字段保持完整
合法 domain 并在每笔 transaction 中随机。`VTRANS_EN` 配置全局 VTRANS 百分比，VTRANS
使用独立配置域，不继承 normal 的 `CREQ_*`。

### 5.2 普通请求

普通 sequence 先从 normal ITYPE domain 选择本笔 topology，再显式创建 contiguous、
strided 或 indexed 子类。所有 normal domain 均通过 `inside` inline constraint 应用，
包括 ATYPE_S 和 ATYPE_G。`creq_tmsk` 在普通请求中随机为非全零值，仍没有 plusarg 或
定向 case 控制其具体 pattern，见 `SHMINS-001`。

`creq_inv_size`、`creq_ack_en`、priority、length、element mask、base、offset、vaddr 和
wpnum 等字段主要依赖随机化。没有 functional coverage 时，单个 seed 不能证明这些
随机维度已经命中目标边界。

### 5.3 VTRANS

`v2m_vtrans_test` 把 VTRANS 全局概率设为 100 后，VTRANS 子类固定：

- `SHM_V2M`、`SPACE_LOC`；
- `DTYP_8` 或 `DTYP_16`；
- `LDST_S` 或 `LDST_V`；
- 每个 thread 16 个 element；
- 所有 element mask 为 1；
- `creq_wpid inside {[0:WARP_N-1]}`；VTRANS 仍按所选 warp 映射到对应 gid。

VTRANS sequence 已按 spec 约束 `creq_tmsk=='1`。VTRANS 仍只有一个 case，DTYPE 和
ITYPE 由 seed 随机选择；没有 coverage 时，不能确认四个合法组合都出现。

### 5.4 `LDSTE_S + SPACE_WRP/SPACE_BLK`

该组合在 M2V 中受支持。M2V 子 TC 已定义并由根 TC include，12 个对应叶子 case 已加入
`m2v.lst`，并已包含在扩容后的真实 RTL regression 中。

V2M 中不同 thread 的 element 0 会按 `base + 0*offset` 访问相同 MADDR；多个写对同一
地址的结果未定义。因此 V2M 激励必须令所有 active thread 的 `creq_vmsk[*][0]==0`，并
保持其他有效 element 的写地址无冲突。当前 strided item 已实现该约束；根 TC 已恢复
`es_warp.tc` 和 `es_blk.tc` include，12 个对应叶子 case 已加入 `v2m.lst` 并通过真实 RTL
regression；`SHMINS-007` 已关闭。

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
4. 当前根列表使用 `INCLUDE : child.lst` 把子 regression 列表加入当前列表。

固定 seed 适合复现失败，不应长期代替 functional coverage。增加 `RUN` 只能提高随机
命中概率，也不能证明目标 bin 已经覆盖。

## 7. 当前 regression

|文件|内容|Case 数|
|---|---|---:|
|[`v2m.lst`](../../../ut_shm/regression/v2m.lst)|普通 V2M 矩阵，加 VTRANS|55|
|[`m2v.lst`](../../../ut_shm/regression/m2v.lst)|普通 M2V 矩阵|54|
|[`shm.lst`](../../../ut_shm/regression/shm.lst)|include 前两份普通列表|109|
|[`p0_directed.lst`](../../../ut_shm/regression/p0_directed.lst)|P0-3/P0-4 双 gid 定向组|4|
|[`shmins_mask_directed.lst`](../../../ut_shm/regression/shmins_mask_directed.lst)|普通 mask 24-cell 与 VTRANS 4-cell 定向组|2 tests / 28 cells|
|[`shmins_dontcare_x.lst`](../../../ut_shm/regression/shmins_dontcare_x.lst)|inactive-thread与masked-element合法X定向组|1 test / 30 cells|
|[`shm_ordered_access.lst`](../../../ut_shm/regression/shm_ordered_access.lst)|同 thread 四种基础顺序和 dtype/gid/space/topology 扩展矩阵|13 tests / 13 cells|

普通 V2M 和 M2V regression 都包含：

- `vec` 的 LOC、WRP、BLK；
- `ev` 的 LOC、WRP、BLK；
- `es` 的 LOC、WRP、BLK。

所有条目当前都是 `RUN=1`，没有固定 `SEED`。用户确认当前 109 个 case 已在
`VEC_W=256`、`VEC_BYTE_N=32` 的真实 design 上全部通过，包括新增的 24 个
`LDSTE_S + WRP/BLK` case。没有固定 seed 和 functional coverage 仍不能证明随机字段
命中特定边界或 coverage bin。

`shm_ordered_access.lst` 已登记到根 TC，但暂不被 `shm.lst` include。四个基础 test 固定使用
thread 0、DTYP8、单 element、SPACE_LOC 和零 external busy，并通过 directed queue
背靠背发布目标 pair；setup 与目标 batch 之间、目标 batch 与最终检查之间才 drain。
2026-08-21 用户确认四个基础 test、独立列表和原 `shm.lst` 均已通过正式 design。

列表使用一个参数化 `shm_ordered_access_matrix_test` class 和九个 TC alias，每次仿真只执行
一个可独立诊断的 cell。矩阵覆盖四种顺序关系的 exact/partial、DTYP16/32、thread 15、
gid 0/1、wpid 3/4、WRP/BLK、strided/indexed 和 VTRANS M-write。九个 alias 已登记，公共
class 已通过远端组件门禁、空 design 编译与零事务 smoke；尚待正式 RTL 运行和 coverage
merge 结果，因此不能作为 DUT 功能通过 evidence。

## 8. 双 gid 迁移新增 case 组

当前 109 个 case 已通过真实 RTL 回归，证明新的物理 BANK 组织和缩减后的 creq 向量
带宽可以承载完整正向矩阵。以下第一批双 gid 定向组已经实现并加入根 TC 与独立
`p0_directed.lst`，但尚未加入 `shm.lst`。最新真实 RTL 整组已通过，coverage 证据尚未闭环：

|Case 组|主要 testpoint|
|---|---|
|逻辑/物理地址 helper，warp 0/3/4/7|`TP-ADDR-009`|
|LOC/WRP/BLK 的 wpid 3/4 数据边界|`TP-ADDR-004`～`006`|
|SPACE_BLK group-relative MADDR、wpid-derived absolute warp 0～7、wpnum 1/2/4|`TP-ADDR-006`|
|M2V `creq_vaddr` 不重复加 WARP 基址|`TP-DATA-002`|
|M2V byte overlap 允许/拒绝边界|`TP-DATA-002`|
|target/other gid external busy|`TP-RSV-002`、`TP-RSV-007`|
|跨 gid 的同 bank/due DUT conflict|`TP-RSV-003`、`TP-RSV-007`|
|MEM 从唯一到期 record 恢复 gid|`TP-MEM-005`、`TP-RSV-008`|
|相同 bank/BADDR、不同 gid 的数据隔离|`TP-MEM-005`|

其中 P0-3 由 `shm_dbank_wpid_boundary_test`、`shm_dbank_gid_isolation_test` 和
`shm_m2v_vaddr_boundary_test` 承担；P0-4 由 `shm_reservation_gid_ownership_test` 承担。
2026-08-15 首轮正式 design 中三个 P0-3 case 通过，P0-4 暴露了 other-gid global
blocking；2026-08-18 用户确认 `p0_directed.lst` 已在最新 design 上四项全部通过。原
109-case `shm.lst` 通过结论继续有效。取得并归档目标 coverage 证据后，再决定是否由
`shm.lst` include。

同日用户确认 `shmins_mask_directed.lst` 也在最新 design 上全部通过，即
`shm_tmsk_directed_test` 的 24 个 normal cell 和 `shm_vtrans_full_mask_test` 的4个 VTRANS
cell 均通过。随后正式 design coverage 中 `normal_mask_cg`、`active_thread_cg` 和
`vtrans_cg` 均达到100%，对应 `TP-CREQ-003` 已闭环；该列表仍独立于主列表。

合法 don’t-care X 的 `shm_payload_dontcare_x_test`、根 TC 和独立
`shmins_dontcare_x.lst` 已实现。该 test 内部执行 18 笔 inactive-thread X 和12笔
masked-element X transaction；组件测试、空 design编译和正式 design运行均已通过。
`dontcare_xz_cg=58.33%`，test内counter确认本批要求的各个X类别均已命中；未命中的Z/XZ
bin和完整非法字段矩阵属于后续 `SHMINS-006` 工作。具体矩阵和判定标准见
[SHMINS don’t-care X 定向验证开发计划](../../development/shm-directed-verification-development-plan.md)。

## 9. 维护规则

- 新 case 必须先关联至少一个 testpoint，不能只扩充名称矩阵。
- 真实 design UVM test 放在 `ut_shm/tests/`；不依赖真实 design 的组件测试放在
  `examples/`，并由独立脚本运行。
- TC 继承或公共 plusarg 改动后，应检查所有叶子 case 的 effective configuration。
- LST 不得引用根 TC 无法解析的 case；定义、include 和 regression 选择是三个不同状态。
- Case 改名时同步更新 LST 和 testpoint 映射。
- Sequence 新增可配置字段时，必须确认 plusarg 实际约束 request，并在 testcase 文档中
  说明固定值与随机值。
- `RUN`/`SEED` 只属于执行组织。运行命令、日志目录和服务器流程统一放在 guide。
