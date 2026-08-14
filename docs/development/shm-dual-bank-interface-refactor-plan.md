# SHM 双 gid BANK 接口重构开发计划

本文定义 `RpuShmTop` 下游存储改为“每个 logical bank 对应两个物理 gid”的验证环境
迁移顺序。DUT 行为以 [地址模型](../ut_shm/spec/address-model.md)、
[creq/ack 接口](../ut_shm/spec/creq-ack-interface.md)和
[MEM/VLM 接口](../ut_shm/spec/mem-vlm-interface.md)为准；本文只规定实现边界、依赖关系
和阶段验收。

## 1. 固定契约

当前迁移基线如下：

```text
BANK_N          = 16 logical bank/MEM ports
GID_N           = 2
WARP_N          = 8 absolute warps
WARP_PER_GID    = 4
WARP_STEP       = 12 KiB
BADDR_W         = MADDR_W - log2(BANK_N) - 1 = 16
creq_vaddr width= BADDR_W
```

物理 byte key 为：

```text
<bank_id, gid, BADDR>
```

三种 address space 先输出逻辑：

```text
<bank_id, absolute_warp_id, warp_laddr>
```

再统一转换：

```text
gid   = absolute_warp_id / 4
BADDR = (absolute_warp_id % 4) * WARP_STEP + warp_laddr
```

SPACE_BLK 的 MADDR 只编码当前 `creq_wpid` 所属 group 内的相对地址；
`creq_wpid/creq_wpnum` 提供绝对 group base。M2V read/write hazard 按有效 byte判断，要求
两个物理 byte 集合不相交。MEM 接口不携带 gid，gid 只能由唯一到期 reservation record
恢复。

## 2. 目标环境架构

目标环境只保留一个 VLM business interface 和一个统一 VLM agent：

```text
vlm_interface
  ├── reservation req/addr/dly/gid
  ├── busy[delay][gid][sub_bank]
  └── MEM valid/addr/data/strb

vlm_agent
  ├── vlm_monitor
  ├── vlm_memory_driver
  ├── vlm_reservation_checker
  ├── vlm_mem_resolver
  ├── vlm_reservation_coverage
  └── vlm_reservation_scheduler
```

统一 monitor 原子采样全部接口信号，但不直接读取 scheduler 私有数组。Agent 使用
checker/resolver 在 pre-update scheduler 状态中完成匹配，再发布带 gid 的 memory
transaction。Reservation cycle transaction 与 memory transaction 保持独立。

## 3. 公共地址类型

公共 package 应新增值类型：

```systemverilog
typedef struct packed {
  bank_id_t    bank_id;
  warp_id_t    warp_id;
  warp_laddr_t laddr;
} shm_logical_addr_t;

typedef struct packed {
  bank_id_t bank_id;
  gid_t     gid;
  baddr_t   baddr;
} shm_physical_addr_t;
```

建议提供以下纯函数：

```systemverilog
map_loc_maddr_to_logical()
map_wrp_maddr_to_logical()
map_blk_maddr_to_logical()
logical_to_physical_addr()
physical_byte_key()
```

所有宽整数运算先在不会截断的类型中完成，通过范围检查后再转换到字段宽度。三种
space helper 不得出现 gid 或 `warp_id%4`；物理 helper 不得重新解释 space/interleave。

## 4. 必须遵守的实现顺序

以下阶段按顺序执行。前一阶段未完成相应验收时，不进入下一阶段；尤其不能先修改
scoreboard 而让它猜测尚未建立的 gid。

### 阶段 1：共享参数、类型和地址 helper

修改范围：

- `shm_util_package`：删除验证侧 `VADDR_W`，把 `BADDR_W` 改为 16，并增加 `GID_N`、
  `WARP_PER_GID` 和必要 typedef；
- shmins 公共 sequence item：`creq_vaddr` 改为 `BADDR_W`；
- 新增逻辑/物理地址 struct 和纯映射 helper；
- 不修改现有 driver/monitor 数据流。

验收：

- 公式级测试覆盖 LOC/WRP/BLK；
- 覆盖绝对 warp 0、3、4、7 和 laddr `0/WARP_STEP-1`；
- warp 0/4 得到相同 BADDR、不同 gid；
- SPACE_BLK 使用非零 `creq_wpid/creq_wpnum` group 得到绝对 warp 4～7；
- syntax/elaboration check 覆盖公共 package 和 sequence item。

### 阶段 2：shmins 生成和 transaction validation

修改范围：

- contiguous、strided、indexed 继续只生成 MADDR；
- 公共基类回填逻辑和物理 element 地址；
- uniqueness/collision key 增加 gid；
- M2V `creq_vaddr` 由逻辑 writeback laddr 编码成 gid 内 BADDR；
- M2V 建立完整 m-read/v-write byte set 并排除 byte overlap；
- `do_copy()`、field automation、打印和最终 validation 同步新字段。

验收：

- 三类 item 的固定 field 和大随机 benchmark 均能生成；
- M2V 候选允许同一 32-Byte beat 中不重叠 byte，拒绝真正 byte overlap；
- `creq_vaddr` 在 warp 3/4 边界不截断、不重复增加 WARP 基址；
- transaction copy 后逻辑/物理地址与原对象一致。

### 阶段 3：reference 和期望 byte map

修改范围：

- `shm_wtrans_item` 保存 gid 和可诊断的逻辑地址；
- `wmap` key 扩展为 `<bank_id,gid,BADDR>`；
- `ref_banks` 扩展为 `[BANK_N][GID_N]`；
- V2M/VTRANS 使用公共物理映射；
- M2V read 按映射 gid 查询，write 使用 `creq_wpid/4` 和原始 `creq_vaddr`，不再添加
  `creq_wpid*WARP_STEP`。

验收：

- 纯 reference 测试证明低、高 gid 相同 BADDR 数据隔离；
- V2M、VTRANS、M2V 分别覆盖 wpid 3/4；
- M2V reference 的 v-write BADDR 逐位等于 `creq_vaddr + byte offset`。

### 阶段 4：统一 interface、transaction 和静态连接

修改范围：

- 合并 memory/reservation interface，增加 `rgid/wgid` 和三维 busy；
- `shm_tb_top`、Config DB、environment config 和 agent 层次改用统一 vif；
- reservation request/record 增加 gid；
- memory transaction 增加 `gid`、`gid_valid`、`reservation_matched`；
- 删除或停止实例化独立 memory monitor，避免重复发布。

这一阶段只要求编译连接完整，不允许暂时用常量 gid 维持旧 scoreboard。

验收：

- 空 DUT/example elaboration 通过；
- active reservation 的 gid X/Z 能被定位到 bank/port；
- 所有 top 端口宽度与 `RpuShmTop` 一致；
- 仿真层次中只有一个 MEM transaction 发布者。

### 阶段 5：scheduler、checker 和 MEM resolver

Scheduler 必须分开维护：

```text
busy ownership : [direction][delay][gid][sub_bank]
MEM port record: [direction][delay][bank_id]
```

修改范围：

- external/SHM/final busy 增加 gid；
- `shm_records` 保持无 gid 数组维度，但 record 本身保存 gid；
- target busy 检查使用 `[dly][gid][addr[6:5]]`；
- pending/current conflict 按 `<direction,bank_id,due>` 检查，忽略 gid/subbank；
- resolver 按到期 record 恢复 MEM gid，并返回逐 bank match result；
- checker、coverage、scheduler 仍在同一 pre-update cycle view 下工作。

验收：

- target gid external busy 阻塞；
- other-gid external busy 允许；
- other-gid same-bank DUT pending record 阻塞；
- 两个 write port 相同 dly、任意 gid/subbank 组合均被拒绝；
- 不同 bank_id 共享 slot 合法；
- unexpected/missing/address mismatch 不产生可用于数据模型的有效 gid。

### 阶段 6：memory driver 和 scoreboard

修改范围：

- `rtl_banks` 扩展为 `[BANK_N][GID_N]`；
- `vlm2aa`、wmap 集合运算和 outstanding key 增加 gid；
- 只有 `gid_valid && reservation_matched` 的 MEM write 才更新可信 memory；
- read driver 复用 agent 的 match result，从正确 gid 获取数据；
- read request metadata 在 T0 固定，`RPORT_DLY` 后返回时不得重新解析 reservation；
- 保留 `FFD_CYC` snapshot 和 reset 清理的既有职责。

验收：

- 同一 bank/BADDR、不同 gid 的 read/write 数据互不污染；
- MEM address mismatch 只产生协议错误，不引发错误 memory 更新；
- M2V 从 gid 1 读取并写回 gid 1/0 的数据均正确；
- scoreboard 最终/expired 算法在增加 gid 后保持原顺序语义。

### 阶段 7：集成 testcase、coverage 和回归

新增或更新：

- address helper 单元测试；
- shmins 三类 item benchmark；
- reservation gid/busy/port-conflict 定向测试；
- MEM/reservation gid 关联和失败路径测试；
- V2M/M2V/VTRANS 的 wpid 3/4 边界数据测试；
- SPACE_BLK group-relative MADDR、WPID 派生 absolute warp 0～7 和 wpnum 1/2/4；
- M2V byte-overlap generator 测试；
- functional coverage：direction × gid × subbank × delay × busy source × match outcome。

最终验收依次为：

1. 本地非 EDA 文档/静态检查；
2. 远端空 DUT/interface compile；
3. 地址和 reservation example；
4. shmins benchmark；
5. ut_shm benchmark regression；
6. 功能覆盖和 checker error count 收敛。

## 5. 禁止的临时兼容方案

- 不得把 gid 拼进 16-bit MEM address；MEM 接口没有该字段；
- 不得根据 MEM address、wpid 或 scoreboard 期望猜测 MEM gid；
- 不得把 `shm_records` 改成 `[...][bank][gid]` 后允许同一 bank/due 两笔请求；
- 不得在 LOC/WRP/BLK 中分别复制 `warp_id → gid/BADDR` 公式；
- 不得为保持旧接口而把 gid 固定为 0；
- 不得让独立 monitor 和 read driver 各自消费一次到期 record；
- 不得让未匹配 MEM transaction 更新 `rtl_banks`；
- 不得把 M2V hazard 粒度扩大为整个 32-Byte beat。

## 6. 文档与状态维护

2026-08-13 集成里程碑：统一 VLM 环境、双 gid 主数据路径和 topology-based shmins
sequence item 已在真实 design 上通过当时 `shm.lst` 的全部 85 个 case。该结果关闭统一接口和
静态连接项 `DBANK-003`；阶段 7 要求的 gid 边界、数据隔离、busy ownership、reservation
冲突/失败路径和 coverage 未由随机正向列表覆盖，因此其他 `DBANK` 项保持当前状态。

2026-08-13 SPACE_BLK contract 后续改为 group-relative MADDR。Spec、正式地址 helper 和
benchmark 已同步更新；空 design 全环境 VCS 编译通过，432 组合与三 topology 无 inline
constraint benchmark 通过，两轮各 1248 个独立公式检查覆盖全部 13 个 interleave size。
当前 Ubuntu EDA 工作区只有空 `RpuShmTop`，因此 RTL 功能回归由实际集成环境执行；
用户已确认新版 SPACE_BLK RTL regression 通过，`SHMINS-003` 与 `REF-001` 于同日关闭。

2026-08-14 接口带宽进一步收窄为每个 thread 256-bit `creq_offs/creq_vdat` 和
32-bit `creq_vmsk`；验证环境使用 `VEC_W=256`、`VEC_BYTE_N=32` 同步适配。用户
确认真实 design 的 109-case `shm.lst` 全部通过。该结果更新双 gid 正向主路径
证据，但不替代本计划阶段 7 的边界、失败路径和 functional coverage。

每完成一个阶段：

1. 更新 [verification-status](../ut_shm/verification-status.md) 对应项的状态和证据；
2. 更新受影响组件文档中的“当前实现状态”；
3. 记录实际运行的 compile/test 命令、seed 和结果位置；
4. 若实现发现 spec 歧义，先修订 spec，再继续代码修改；
5. 不以旧代码行为覆盖本计划第 1 节的固定契约。
