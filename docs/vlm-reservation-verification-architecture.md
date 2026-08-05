# VLM Reservation 调度与协同验证架构

|项目|内容|
|---|---|
|文档状态|验证代码实现基准|
|版本|0.5|
|日期|2026-08-05|
|适用模块|`RpuShmTop`|

## 1. 文档目的

本文定义 `RpuShmTop` 的 VLM reservation 调度与协同验证架构，作为
`vlm_reservation_agent`、reservation monitor、scheduler、checker 和 coverage
组件的实现依据。

本文规定：

- 验证组件及其职责边界；
- `vlm_reservation_interface` 与 `vlm_memory_interface` 的访问关系；
- `clk_if` 提供的统一 cycle number；
- 四态接口采样到二态 cycle transaction 的转换边界；
- external busy、SHM busy 和 reservation record 的状态模型；
- reservation、busy 与实际 MEM 请求之间的检查边界；
- `main_phase` 中的单周期处理顺序；
- 组件之间的直接调用关系。

MEM/VLM 端口的协议语义、时序和禁止行为见
[RpuShmTop MEM/VLM 接口规范](mem-vlm-interface-spec.md)。本文不重复定义
MEM 数据通路，也不规定 `mem_rdata`、`mem_wdata` 或 `mem_wstrb` 的数据检查方法。

## 2. 已确认的架构约束

### 2.1 BANK 与 sub bank

`bank_id` 是接口数组的 BANK 维下标。每个 BANK 内包含 4 个 sub bank：

```systemverilog
sub_bank_id = bank_addr[6:5];
```

busy 资源按 `<direction, due_cycle, sub_bank_id>` 区分，读方向与写方向相互独立。

### 2.2 多 BANK 共享同一 SHM slot

不同 BANK 可以在相同周期、相同方向预约相同 sub bank，不构成冲突。多笔 DUT
reservation 可以具有相同的：

```text
<direction, dly, sub_bank_id>
```

同一个 SHM busy bit 可以对应多笔不同 BANK 的 reservation record。checker
不得仅因这种组合报告错误。

同一 BANK、同一方向仍然不能有两笔不同 reservation 在同一周期到期，因为每个
BANK 在每个方向只有一条实际 MEM 请求端口。该 BANK 冲突与两笔 reservation
访问的 sub bank 是否相同无关。

读写方向相互独立。同一 BANK 在同一周期允许分别到期一笔读 reservation 和一笔
写 reservation；checker 不得仅因这种跨方向组合报告 BANK 冲突。

### 2.3 external 与 SHM 的冲突

只有 DUT reservation 与其他外部模块占用相同资源时才构成冲突。冲突键为：

```text
<direction, due_cycle, sub_bank_id>
```

同一位置的 external busy 与 SHM busy 不得同时为 1。DUT 发出 reservation 时，
目标位置的最终 busy 必须严格等于 0。

### 2.4 当前验证配置不支持 `dly == 0`

MEM/VLM 接口规范定义了 `dly == 0` 的协议语义，但当前 `RpuShmTop` 设计配置保证
不会产生 `dly == 0` 的 reservation。本验证架构将其作为设计配置违例处理：

- monitor 保留该已知请求供 checker 诊断；
- checker 立即报告 `UVM_ERROR`；
- scheduler 不接受该 reservation；
- 该 reservation 不写入 `shm_records`，也不设置 `shm_busy`；
- 该 reservation 不进入正常的 reservation/MEM 匹配流程。

正常调度与匹配仅处理：

```text
1 <= dly < VTAB_D
```

### 2.5 Cycle number

验证环境实例化一个全局 `clk_if`。`clk_if` 只提供时钟周期服务，不替代
`vlm_reservation_interface`、`vlm_memory_interface` 或 `shmins_interface`
原有的普通 `clk`、`rst_n` 连接。

`clk_if` 至少提供：

```systemverilog
longint unsigned cycle_count;
task wait_cycles(int unsigned count);
```

`cycle_count` 从 0 开始，在每个 `clk` 上升沿单调递增，reset 不清零该计数。
需要读取 cycle number 的 UVM component 各自声明：

```systemverilog
virtual clk_if clk_vif;
```

并通过 UVM Config DB 的统一字段名 `clk_vif` 获取同一个 interface 实例。业务
virtual interface 继续由 agent config 提供，`clk_vif` 不放入
`vlm_reservation_agent_config`。

任何 reservation component 都不得维护第二份独立递增的 cycle counter。Cycle
transaction 中的 cycle 字段只是对 `clk_vif.cycle_count` 的当周期快照。

### 2.6 UVM phase 与 reset 范围

`vlm_reservation_agent` 的周期循环只运行在 `main_phase`。本架构不使用
`main_phase` 启动 reservation monitor、scheduler、checker、coverage 或 busy
驱动逻辑。

Monitor 使用 reservation interface clocking block 中采样的 `rst_n` 作为采集门控：

- 当 `rst_n !== 1'b1` 时，`collect_cycle()` 继续等待，不构造 cycle transaction，
  也不执行 busy、reservation 或 MEM request 的 X/Z 检查；
- reset 释放后的请求从第一个完整采样到 `rst_n == 1'b1` 的时钟沿开始生效；
- reservation agent 在等待期间不调用 checker、coverage 或 scheduler；
- scheduler、checker 和 coverage 暂不声明 reset API，运行中再次进入 reset 时保留内部状态。

当前 reset 支持仅用于屏蔽 reset 期间的接口采样与检查，不等同于完整的动态 reset
状态清理。后续若需要在运行中 reset 并清空 scheduler 状态，必须单独扩展对应 API。

## 3. 总体架构

```text
shm_env
├── vlm_reservation_agent
│   ├── vlm_reservation_monitor
│   ├── vlm_reservation_scheduler
│   ├── vlm_reservation_checker
│   └── vlm_reservation_coverage
│
├── vlm_memory_slv_agent
│   ├── vlm_memory_monitor
│   ├── vlm_memory_slv_driver
│   └── vlm_memory_model
│
└── shm_scoreboard
```

`vlm_reservation_agent` 是一个周期精确的 reactive agent。它在 `main_phase`
中主动驱动 reservation busy，同时只读观察 reservation 请求和实际 MEM 请求。

`vlm_memory_slv_agent` 保持独立，继续负责 memory model 和 `mem_rdata`。
`vlm_reservation_agent` 不替代或复用其 read-data driver。

## 4. 组件职责

### 4.1 `vlm_reservation_agent`

`vlm_reservation_agent` 是 reservation 验证子系统的容器、周期编排者和 busy
驱动者，负责：

- 获取并保存 reservation 与 memory 两个 virtual interface；
- 创建并连接 monitor、scheduler、checker 和 coverage；
- 管理 active/passive 配置和 scheduler 配置；
- 在唯一的 `main_phase` 循环中向 monitor 请求当周期 transaction；
- 按固定顺序同步调用 checker、coverage 和 scheduler；
- 在 active 模式下把 scheduler 的最终 busy 驱动到 reservation interface；
- 对外提供 reservation、busy、monitor 输入错误和 checker 错误统计接口。

该 agent 持有：

```systemverilog
virtual vlm_reservation_interface reservation_vif;
virtual vlm_memory_interface      memory_vif;
```

两个 virtual interface 的权限如下：

|Interface|读取|驱动|
|---|---|---|
|`reservation_vif`|`vlm_*req`、`vlm_*addr`、`vlm_*dly`、实际 `vlm_*busy`|`vlm_rbusy`、`vlm_wbusy`|
|`memory_vif`|`mem_rvld`、`mem_raddr`、`mem_wvld`、`mem_waddr`|无|

`vlm_reservation_agent` 禁止驱动 `mem_rdata`，也不负责 MEM 数据内容检查。

### 4.2 `vlm_reservation_monitor`

`vlm_reservation_monitor` 是两个业务 interface 与二态 transaction 之间的唯一
采样边界，负责：

- 通过 Config DB 获取 `clk_vif`；
- 使用 reservation interface 的 monitor clocking block 等待采样沿；
- 在同一采样沿读取 reservation、busy 和 MEM request；
- 从 `clk_vif` 取得当前 `cycle_count`；
- 按每个 valid/request 及其有效 payload 检查 X/Z；
- 把已知信号转换成二态 cycle transaction；
- 把接口输入错误记录在 transaction 状态和 monitor 统计中；
- 通过 `collect_cycle()` 把 transaction 同步返回给 agent。

Monitor 不负责：

- 驱动 reservation busy；
- 调用 scheduler、checker 或 coverage；
- 接受或拒绝语义上非法的 reservation；
- 维护 external busy、SHM busy 或 reservation record；
- 检查 MEM 数据。

Monitor 不启动独立的 `main_phase` 或 `main_phase`。Agent 的 `main_phase` 调用
`collect_cycle()`；该 task 每次只采集一个周期。

### 4.3 `vlm_reservation_scheduler`

`vlm_reservation_scheduler` 负责维护未来 `VTAB_D` 周期内读写方向的全部
sub-bank busy 状态，并区分 busy 的来源。

Scheduler 接收：

- monitor 产生的二态 cycle transaction；
- transaction 中从 `clk_if` 快照得到的 cycle number；
- 测试配置提供的 external busy 生成策略。

External busy 概率通过 `vlm_reservation_agent_config.EXTERNAL_BUSY_PERCENT`
配置，取值范围为 0～100，默认值为 0。仿真命令行可以使用以下大写 plusarg
覆盖 test 写入 config object 的值：

```text
+EXTERNAL_BUSY_PERCENT=<0..100>
```

Plusarg 在 agent 的 build 阶段解析，并在 scheduler 开始处理第一个周期前完成传递；
超出范围的值属于 testbench 配置错误，必须立即报告 `UVM_FATAL`。配置值表示对
每个当前空闲的 `<direction, delay, sub_bank_id>` slot 独立执行一次百分比随机判定。

Scheduler 提供：

- `external_busy`；
- `shm_busy`；
- 最终 `vlm_rbusy` 和 `vlm_wbusy`；
- 按 `<direction, relative_delay, bank_id>` 索引的 `shm_records` 只读状态视图；
- 供 checker 和 coverage 使用的 busy 来源信息。

Scheduler 只接受满足当前架构约束的 reservation。已知但语义非法的请求仍由
checker 报错，但 scheduler 不得把它写入调度状态。

Scheduler 不接收 `mem_rdata`，不检查 MEM 数据，也不得根据 MEM 请求是否按时出现
来延长、缩短或修正 reservation 的到期时间。Scheduler 不维护自行递增的 cycle
counter。若保存 `last_processed_cycle`，它只能是最近一次 transaction 的 cycle
快照，不能作为 scheduler 数组当前相对 delay 的第二份独立计数器。

### 4.4 `vlm_reservation_checker`

`vlm_reservation_checker` 负责检查：

- busy 状态及来源的一致性；
- reservation 请求的 dly、端口相关地址对齐和 sub-bank 选择；
- reservation 是否避开 external/SHM 已占用 slot；
- 同一 BANK、同一方向的到期冲突；
- 到期 `shm_records` 与实际 MEM 请求的一一对应；
- MEM 请求是否来自到期的 SHM reservation。

Checker 接收：

- monitor 产生的当周期二态 transaction；
- scheduler 提供的当周期只读状态视图。

四态 X/Z 检查完全属于 monitor。Checker 只处理 monitor 已规范化的二态数据，
不重复报告或统计四态错误。`input_error` 只用于阻止 checker 把 X/Z 归一化产生的
占位值解释为可靠接口值。

Checker 不检查：

- `mem_rdata` 的数值或返回延迟；
- `mem_wdata` 和 `mem_wstrb`；
- memory model 的存储内容；
- creq 到 MEM 的功能映射。

这些职责分别属于 `vlm_memory_slv_agent`、MEM 数据 checker 和
`shm_scoreboard`。

### 4.5 `vlm_reservation_coverage`

`vlm_reservation_coverage` 负责采集：

- 读/写方向；
- BANK、sub bank 和 dly；
- external busy 与 SHM busy；
- busy 阻塞；
- 多 BANK 共享同一 SHM slot；
- 同一个 SHM slot 中的 reservation record 数量；
- 两条 VLM 写 reservation port；
- 到期 reservation 与 MEM request 的匹配结果；
- `dly == 0` 配置违例；
- monitor 检测到的接口输入错误。

多 BANK 共享同一 `<direction, dly, sub_bank_id>` 是合法功能场景，必须作为
正常 coverage，而不是错误或开放问题处理。

Coverage 只通过同步 function API 采样，不启动 `main_phase` 或 `main_phase`，
也不影响 scheduler、checker 或 busy 驱动状态。Agent 必须在 scheduler 更新前
调用 coverage，使 transaction、checker 结果和 scheduler 只读视图都属于同一
采样周期。

### 4.6 `vlm_memory_slv_agent`

`vlm_memory_slv_agent` 保持现有独立职责：

- monitor 采集 MEM 读写请求；
- memory model 维护实际存储内容；
- slave driver 在固定延迟后提供 `mem_rdata`；
- MEM 数据路径相关 checker/scoreboard 检查数据、strobe 和返回时序。

它与 `vlm_reservation_agent` 可以同时读取 `vlm_memory_interface`，但只有
`vlm_memory_slv_driver` 可以驱动 `mem_rdata`。

## 5. Transaction 与 Scheduler 状态模型

### 5.1 Monitor 四态采样边界

Monitor 在 `collect_cycle()` 中先等待 reservation interface clocking block 采样到
`rst_n == 1'b1`，再读取两个业务 interface 的同周期采样值，完成四态检查并构造
二态 transaction。本架构不定义或传递独立的 `vlm_reservation_raw_sample_t`。

对于 req/vld 为 0 的端口，对应 addr、dly 和数据为 don't-care，monitor 不检查
这些 payload，对应的 transaction class handle 保持 `null`。req/vld 或其有效
payload 包含 X/Z 时，monitor 报告错误、设置 `input_error`，并同样保持对应
handle 为 `null`。

### 5.2 二态 cycle transaction

核心路径使用包含二态值和只读 class handle 的普通 struct，而不是
`uvm_sequence_item`。Cycle transaction 至少包含：

- `cycle`：`clk_vif.cycle_count` 的采样快照；
- `rsv_rreq_array[BANK_N]`：每个 BANK 的读 reservation request handle；
- `rsv_wreq_array[BANK_N][WRITE_PORT_N]`：每个 BANK、每个写端口的 reservation
  request handle；
- `mem_rreq_array[BANK_N]`：每个 BANK 的实际 MEM 读 request handle；
- `mem_wreq_array[BANK_N]`：每个 BANK 的实际 MEM 写 request handle；
- 当周期观察到的 read/write busy；
- `input_error`：monitor 是否在该周期发现接口 X/Z。

非 `null` request handle 表示对应物理端口存在一笔完整已知的请求；`null` 表示
该端口没有可供 checker 和 scheduler 处理的请求。完整已知但语义非法的
reservation 仍创建 request instance，供 checker 报错和 scheduler 拒绝。包含
未知 valid 或未知有效 payload 的端口不创建 instance。

Request instance 由 monitor 创建，之后只读。Scheduler 不得保存或修改 monitor
创建的 request instance；被接受的 reservation 必须转换成独立的
`vlm_shm_record_t`。Busy 中的 X/Z 由 monitor 报错，并在 `observed_busy` 中
归一化为 0；该 0 只是保证后续仿真确定性的占位值，不表示对应 slot 已确认空闲。

该 transaction 由 agent 以 `const ref` 直接传给 checker、scheduler 和 coverage。
核心路径不依赖 analysis port、TLM FIFO、subscriber 回调顺序或 sequence item
握手。

### 5.3 Busy 状态

Scheduler 按 direction、delay 和 sub-bank 维护两类二态 busy：

```systemverilog
bit external_busy[2][VTAB_D][4];
bit shm_busy     [2][VTAB_D][4];
```

direction 的两个取值分别对应 read 和 write。最终接口激励满足：

```text
vlm_rbusy = external_busy[READ]  OR shm_busy[READ]
vlm_wbusy = external_busy[WRITE] OR shm_busy[WRITE]
```

必须始终满足以下状态不变量：

```text
external_busy[direction][delay][sub_bank_id]
AND
shm_busy[direction][delay][sub_bank_id]
== 0
```

`external_busy` 表示其他外部模块的预约；`shm_busy` 表示已经被 scheduler
接受的 DUT reservation。

### 5.4 SHM reservation record

每笔被 scheduler 接受的 DUT reservation 使用以下只读 record：

```systemverilog
class vlm_shm_record_t;
    bit [BADDR_W-1:0] address;
    int unsigned      write_port;
    longint unsigned  issue_cycle;
    int unsigned      issue_delay;
endclass
```

Scheduler 按以下结构保存 nullable record handle：

```text
shm_records[direction][relative_delay][bank_id]
```

其中 direction、当前相对 delay 和 BANK 已由数组索引表达。`sub_bank_id` 从
record 的 `address[6:5]` 派生。固定 `<direction, relative_delay, bank_id>` 只有
一个 handle，因此从结构上保证同一 BANK、同一方向、同一到期周期最多保存一笔
DUT reservation。不同 BANK 的 record 可以通过相同地址 sub-bank 位共享一个
SHM busy bit。

Record 中的 `write_port` 保存写预约的来源端口；读预约统一保存为 0。该字段不属于
MEM 匹配键，因为每个 BANK 只有一条实际 MEM 写端口，但 checker 使用它保留
write port 0 与 write port 1 不同的地址对齐契约。

Record 中的 `issue_delay` 是 reservation 发出时的原始 delay，record 移动时
保持不变。Checker 在 scheduler 更新前必须检查：

```text
record.issue_cycle + record.issue_delay
==
transaction.cycle + relative_delay
```

`shm_busy` 与 `shm_records` 必须满足：

```text
shm_busy[direction][delay][sub_bank_id] == 1
当且仅当存在某个 bank_id，满足
shm_records[direction][delay][bank_id] != null
且 shm_records[direction][delay][bank_id].address[6:5] == sub_bank_id
```

## 6. 检查契约

### 6.1 Monitor 四态检查

Monitor 必须检查：

- reservation req、MEM valid 和 busy 禁止包含 X/Z；
- req 为 1 的 reservation addr 和 dly 禁止包含 X/Z；
- MEM valid 为 1 的 MEM address 禁止包含 X/Z；
- req/valid 为 0 时，不检查对应 payload；
- busy 中的 X/Z 必须在 monitor 报错后归一化为 0，并设置 transaction 的
  `input_error`。

每个 X/Z 违例由 monitor 报告 `UVM_ERROR`，并增加 monitor input error 统计。
Checker 不再保存 per-bit known mask，也不重复增加四态错误计数。

### 6.2 Reservation 合法性

对于 transaction 中每笔完整已知的 reservation，checker 必须检查：

- `1 <= dly < VTAB_D`；
- read reservation 和 write port 1 地址按 32 Byte 对齐；
- write port 0 允许非 32 Byte 对齐，scheduler 必须原样保存完整地址；
- `sub_bank_id = address[6:5]`；
- 当 `input_error == 0` 时，对应方向的二态 `observed_busy[dly][sub_bank_id]`
  必须为 0；
- active 模式下，scheduler 内部 external/SHM busy 的目标位置必须为空闲；
- 同一 BANK、同一方向不存在另一笔相同到期周期的 reservation，无论两笔请求的
  sub bank 是否相同；
- 同一 BANK 同周期各一笔读写 reservation 是合法的跨方向组合。

当 `input_error == 1` 时，checker 跳过依赖 `observed_busy` 真实性的比较，但仍
检查 scheduler 内部不变量以及所有完整已知的 reservation/MEM event。Scheduler
不得把归一化后的 `observed_busy` 作为预约接收依据。

不同 BANK 的 reservation 可以共享相同 `<direction, dly, sub_bank_id>`。

### 6.3 Busy 来源一致性

Checker 必须检查：

- external busy 与 SHM busy 不重叠；
- 实际驱动到接口的已知 busy 等于两类 busy 的 OR；
- `shm_busy` 与所有 BANK record 按 `address[6:5]` 归约后的占用状态一致；
- DUT reservation 不得占用 external busy 已占用的 slot。

### 6.4 MEM 请求匹配

合法 reservation 均满足 `dly > 0`，因此每笔实际 MEM 请求都必须满足：

```text
shm_busy[direction][0][sub_bank_id] == 1
external_busy[direction][0][sub_bank_id] == 0
```

并且必须在以下位置找到匹配 record：

```text
shm_records[direction][0][bank_id]
```

匹配键为：

```text
<direction, bank_id, address, due_cycle=transaction.cycle>
```

`address` 比较必须覆盖完整 BADDR。Checker 禁止对 reservation 或 MEM 地址进行
32 Byte 向下对齐、清除低 5 bit 或仅比较 beat 编号。读 MEM 地址仍必须
32 Byte 对齐；写 MEM 地址不单独要求对齐，其合法性由它是否逐位等于到期写预约
决定。write port 0 的非对齐预约因此只能由完全相同的非对齐 `mem_waddr` 兑现。

Checker 必须同时保证：

1. 每笔 MEM 请求匹配且只匹配一笔到期 record；
2. 每笔到期 record 产生且只产生一笔 MEM 请求；
3. MEM 请求不得使用 external busy 占用的 slot；
4. 多笔不同 BANK 的到期 record 可以共享同一个 SHM busy bit，但必须分别匹配各自
   BANK 的 MEM 请求。

## 7. `main_phase` 单周期处理顺序

在周期 `N` 的上升沿之前，agent 已经把 scheduler 为周期 `N` 准备的最终 busy
驱动到 reservation interface。

周期 `N` 上升沿后的 `main_phase` 处理顺序固定为：

1. agent 调用 `monitor.collect_cycle()`；
2. monitor 等待 reset 释放后的有效采样沿，并原子采样两个业务 interface，生成
   transaction；reset 有效期间不会返回 transaction；
3. agent 调用 checker，checker 使用 scheduler 更新前状态检查当前到期记录；
4. agent 调用 coverage，传入相同 transaction、checker 结果和 scheduler
   更新前状态；
5. agent 调用 scheduler，scheduler 消费到期记录、移动 busy 窗口、接收合法新
   reservation，并生成下一周期 busy；
6. active agent 把 scheduler 的最终 busy 驱动到 reservation interface，供周期
   `N+1` 采样。

除 `monitor.collect_cycle()` 的时钟等待外，checker、scheduler、coverage 和 busy
驱动 API 不得消耗仿真时间。整个闭环由 agent 的一个 `main_phase` 进程顺序执行。

## 8. 组件连接关系

```text
                UVM Config DB
                     |
                  clk_vif
                     |
                     v
          +----------------------------------+
          |      vlm_reservation_agent       |
          |                                  |
reservation_vif --> monitor                  |
memory_vif -------> monitor                  |
          |             | cycle transaction  |
          |             v                    |
          |      agent main_phase            |
          |        |       |       |         |
          |        v       v       v         |
          |     checker coverage scheduler   |
          |        ^       ^       |         |
          |        +-------+-------+         |
          |          scheduler view          |
          |                | final busy       |
reservation_vif <----------+                 |
          +----------------------------------+
```

核心连接如下：

|源组件|目标组件|内容|
|---|---|---|
|Config DB|需要周期信息的 component|同一个 `virtual clk_if`|
|monitor|agent|当周期二态 cycle transaction|
|agent|checker|当周期 transaction|
|scheduler|checker|更新前 external busy、SHM busy、SHM records 只读视图|
|agent|coverage|当周期 transaction 和 checker 结果，在 scheduler 更新前采样|
|scheduler|coverage|更新前 busy 来源和 SHM record 只读视图|
|agent|scheduler|当周期 transaction|
|scheduler|agent|下一周期最终 read/write busy|

`vlm_reservation_checker` 位于 `vlm_reservation_agent` 内，不再作为
`shm_env` 中独立连接两个 monitor 的 checker。

## 9. Transaction、sequence 与运行模式

busy 是连续的周期状态，核心调度路径不使用 sequence item 逐周期产生 busy，也不
依赖 sequencer/driver 的 item 握手。

核心 cycle transaction 是 monitor 与 agent 之间同步返回的普通 struct。可选的
analysis port 只允许在核心处理之外用于：

- transaction recording、日志和离线调试；
- 向外部 subscriber 发布已规范化事件；
- 功能覆盖率扩展。

Checker、scheduler 和 busy 驱动的正确性不得依赖 analysis port 或 subscriber
回调顺序。

Agent 至少支持：

|模式|行为|
|---|---|
|Active|在 `main_phase` 驱动 reservation busy，并运行 monitor、scheduler、checker 和 coverage|
|Passive|不驱动 busy；运行 monitor 以及适用于 passive 状态的 checker 和 coverage|

external busy 生成策略至少允许全空闲、定向和随机三种配置。具体随机算法不属于
本文范围。

## 10. 实现验收条件

实现满足以下条件时，视为符合本架构：

- `vlm_reservation_agent` 同时持有 reservation vif 和只读 memory vif；
- 原 cycle controller 已替换为只负责采样和规范化的 reservation monitor；
- agent 只在 `main_phase` 运行核心周期循环，不实现 reservation `main_phase`；
- monitor、scheduler 和 checker 从 Config DB 获取统一的 `clk_vif`；
- 没有 component 维护独立递增的 cycle counter；
- monitor 原子采集两个业务 interface，并生成二态 cycle transaction；
- monitor 直接从 clocking-block 采样值构造 transaction，不保存独立 raw sample；
- monitor 报告所有 X/Z，把 busy 的 X/Z 归一化为 0，并设置 `input_error`；
- transaction 不保存 per-bit busy known mask；
- transaction 使用固定 BANK/port 数组和 nullable request handle，不使用 event
  queue；
- checker 只处理二态语义，不重复报告 monitor 的四态错误；
- 核心 checker、scheduler、coverage 和 busy 驱动使用同步直接调用；
- coverage 在 scheduler 更新前采集当前 transaction 和 scheduler 状态；
- scheduler 能区分 external busy 与 SHM busy；
- external busy 与 SHM busy 永不重叠；
- `shm_records[direction][delay][bank]` 每个位置最多保存一个 record；
- 多个不同 BANK 的 record 可以通过相同 `address[6:5]` 共享一个 SHM busy bit；
- 同一 BANK、同一方向、同一到期周期最多接受一笔 reservation，跨读写方向不
  构成该 BANK 冲突；
- `dly == 0` 报告 `UVM_ERROR` 且不进入正常调度模型；
- 每笔合法 MEM 请求能够匹配唯一的到期 SHM record；
- 每笔到期 SHM record 能够匹配唯一的 MEM 请求；
- reservation agent 不驱动或检查 `mem_rdata`；
- 当前代码框架不声明或实现 reset 处理 API；
- 核心 busy 激励不依赖逐周期 sequence item。
