# VLM Reservation 调度与协同验证架构

|项目|内容|
|---|---|
|文档状态|验证代码实现基准|
|版本|0.1|
|日期|2026-07-23|
|适用模块|`RpuShmTop`|

## 1. 文档目的

本文定义 `RpuShmTop` 的 VLM reservation 调度与协同验证架构，作为
`vlm_reservation_agent`、reservation scheduler、checker 和 coverage
组件的实现依据。

本文规定：

- 验证组件及其职责边界；
- `vlm_reservation_interface` 与 `vlm_memory_interface` 的访问关系；
- external busy、SHM busy 和 reservation record 的状态模型；
- reservation、busy 与实际 MEM 请求之间的检查边界；
- 组件之间的连接关系。

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

不同 BANK 可以在相同周期、相同方向预约相同 sub bank，不构成冲突。也就是说，
多笔 DUT reservation 可以具有相同的：

```text
<direction, dly, sub_bank_id>
```

同一个 SHM busy bit 可以对应多笔不同 BANK 的 reservation record。checker
不得仅因这种组合报告错误。

同一 BANK、同一方向仍然不能有两笔不同 reservation 在同一周期到期，因为每个
BANK 在每个方向只有一条实际 MEM 请求端口。

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

- checker 立即报告 `UVM_ERROR`；
- scheduler 不接受该 reservation；
- 该 reservation 不写入 `shm_records`，也不设置 `shm_busy`；
- 该 reservation 不进入正常的 reservation/MEM 匹配流程。

正常调度与匹配仅处理：

```text
1 <= dly < VTAB_D
```

## 3. 总体架构

```text
shm_env
├── vlm_reservation_agent
│   ├── vlm_reservation_cycle_controller
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

`vlm_reservation_agent` 是一个周期精确的 reactive agent。它主动驱动
reservation busy，同时只读观察 reservation 请求和实际 MEM 请求。

`vlm_memory_slv_agent` 保持独立，继续负责 memory model 和 `mem_rdata`。
`vlm_reservation_agent` 不替代或复用其 read-data driver。

## 4. 组件职责

### 4.1 `vlm_reservation_agent`

`vlm_reservation_agent` 是 reservation 验证子系统的容器，负责：

- 获取并保存 reservation 与 memory 两个 virtual interface；
- 创建并连接 cycle controller、scheduler、checker 和 coverage；
- 管理 active/passive 配置和 scheduler 配置；
- 对外提供可选的 reservation、busy 和错误统计接口。

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

### 4.2 `vlm_reservation_cycle_controller`

`vlm_reservation_cycle_controller` 是 agent 内唯一拥有周期推进职责的组件，负责：

- 在统一的 `clk` 和 `rst_n` 下同步两个 interface；
- 每周期原子采集 reservation、busy 和 MEM request；
- 为采样结果分配统一的 `cycle_id`；
- 按固定顺序调用 scheduler、checker 和 coverage；
- 把 scheduler 生成的最终 busy 驱动到 `reservation_vif`；
- 在 reset 时协调各组件清空状态。

agent 内其他组件不得独立推进全局周期或修改 cycle controller 的周期计数。
核心调度路径不依赖不同 monitor 的 TLM transaction 到达顺序。

### 4.3 `vlm_reservation_scheduler`

`vlm_reservation_scheduler` 负责维护未来 `VTAB_D` 周期内读写方向的全部
sub-bank busy 状态，并区分 busy 的来源。

Scheduler 接收：

- cycle controller 采集到的有效 reservation；
- 当前 `cycle_id` 和 reset 状态；
- 测试配置提供的 external busy 生成策略。

Scheduler 提供：

- `external_busy`；
- `shm_busy`；
- 最终 `vlm_rbusy` 和 `vlm_wbusy`；
- `shm_records` 的只读状态视图；
- 供 checker 和 coverage 使用的 busy 来源信息。

Scheduler 不接收 `mem_rdata`，不检查 MEM 数据，也不得根据 MEM 请求是否按时出现
来延长、缩短或修正 reservation 的到期时间。

### 4.4 `vlm_reservation_checker`

`vlm_reservation_checker` 负责检查：

- busy 状态及来源的一致性；
- reservation 请求的 dly、地址对齐和 sub-bank 选择；
- reservation 是否避开 external/SHM 已占用 slot；
- 同一 BANK、同一方向的到期冲突；
- 到期 `shm_records` 与实际 MEM 请求的一一对应；
- MEM 请求是否来自到期的 SHM reservation；
- reset 后是否存在未清除的 scheduler/checker 状态。

Checker 接收：

- cycle controller 的当周期 reservation、busy 和 MEM request 采样；
- scheduler 提供的当周期只读状态视图。

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
- `dly == 0` 配置违例。

多 BANK 共享同一 `<direction, dly, sub_bank_id>` 是合法功能场景，必须作为
正常 coverage，而不是错误或开放问题处理。

### 4.6 `vlm_memory_slv_agent`

`vlm_memory_slv_agent` 保持现有独立职责：

- monitor 采集 MEM 读写请求；
- memory model 维护实际存储内容；
- slave driver 在固定延迟后提供 `mem_rdata`；
- MEM 数据路径相关 checker/scoreboard 检查数据、strobe 和返回时序。

它与 `vlm_reservation_agent` 可以同时读取 `vlm_memory_interface`，但只有
`vlm_memory_slv_driver` 可以驱动 `mem_rdata`。

## 5. Scheduler 状态模型

### 5.1 Busy 状态

Scheduler 按 direction、delay 和 sub-bank 维护两类 busy：

```systemverilog
logic external_busy[2][VTAB_D][4];
logic shm_busy     [2][VTAB_D][4];
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

### 5.2 SHM reservation record

每笔 DUT reservation 使用以下 record：

```systemverilog
typedef struct {
    int unsigned            bank_id;
    int unsigned            write_port;
    logic [BADDR_W-1:0]     address;
    longint unsigned        issue_cycle;
    longint unsigned        due_cycle;
} vlm_shm_record_t;
```

Scheduler 按以下结构保存 record：

```text
shm_records[direction][delay][sub_bank_id][$]
```

其中每个数组元素是一个 record queue。queue 用于表示多个不同 BANK 合法共享
同一个 SHM slot；不得把一个 slot 限制为只能保存一笔 DUT reservation。

读 reservation 的 `write_port` 固定为 0 或标记为不使用。`sub_bank_id`、direction
和当前相对 delay 已由数组索引表达，因此不重复存入 record。

`shm_busy` 与 `shm_records` 必须满足：

```text
shm_busy[direction][delay][sub_bank_id] == 1
当且仅当
shm_records[direction][delay][sub_bank_id] 非空
```

## 6. 检查契约

### 6.1 Reservation 合法性

对于每笔有效 reservation，checker 必须检查：

- req、addr 和 dly 不含 X/Z；
- `1 <= dly < VTAB_D`；
- 地址按 32 Byte 对齐；
- `sub_bank_id = address[6:5]`；
- 对应方向的最终 `busy[dly][sub_bank_id]` 严格等于 0；
- 同一 BANK、同一方向不存在另一笔相同到期周期的 reservation。

不同 BANK 的 reservation 可以共享相同 `<direction, dly, sub_bank_id>`。

### 6.2 Busy 来源一致性

Checker 必须检查：

- external busy 与 SHM busy 不重叠；
- 实际驱动到接口的 busy 等于两类 busy 的 OR；
- busy 不含 X/Z；
- `shm_busy` 与 `shm_records` 的空/非空状态一致；
- DUT reservation 不得占用 external busy 已占用的 slot。

### 6.3 MEM 请求匹配

合法 reservation 均满足 `dly > 0`，因此每笔实际 MEM 请求都必须满足：

```text
shm_busy[direction][0][sub_bank_id] == 1
external_busy[direction][0][sub_bank_id] == 0
```

并且必须在以下 queue 中找到唯一匹配 record：

```text
shm_records[direction][0][sub_bank_id]
```

匹配键为：

```text
<direction, bank_id, address, due_cycle=current_cycle>
```

Checker 必须同时保证：

1. 每笔 MEM 请求匹配且只匹配一笔到期 record；
2. 每笔到期 record 产生且只产生一笔 MEM 请求；
3. MEM 请求不得使用 external busy 占用的 slot；
4. 多笔不同 BANK 的到期 record 可以共享同一个 SHM busy bit，但必须分别匹配各自
   BANK 的 MEM 请求。

## 7. 组件连接关系

```text
                         +-----------------------------+
                         |   vlm_reservation_agent     |
                         |                             |
reservation_vif ------->| cycle_controller            |
  req/addr/dly/busy      |    |                        |
                         |    +----> checker            |
                         |    +----> coverage           |
                         |    +----> scheduler          |
                         |                  |           |
reservation_vif <-------|<----- final busy-+           |
                         +-----------------------------+
                                      ^
                                      |
                                      | read-only MEM request
                                      |
                              vlm_memory_interface
                                      |
                         +------------+---------------+
                         |    vlm_memory_slv_agent     |
                         | monitor/model/rdata driver  |
                         +----------------------------+
```

核心连接如下：

|源组件|目标组件|内容|
|---|---|---|
|cycle controller|scheduler|当周期 reservation、cycle/reset 状态|
|scheduler|cycle controller|最终 read/write busy|
|cycle controller|checker|当周期 reservation、busy、MEM request|
|scheduler|checker|external busy、SHM busy、SHM records 只读视图|
|cycle controller|coverage|当周期采样和匹配结果|
|scheduler|coverage|busy 来源和 slot 占用信息|

`vlm_reservation_checker` 位于 `vlm_reservation_agent` 内，不再作为
`shm_env` 中独立连接两个 monitor 的 checker。

## 8. Transaction 与 sequence 使用原则

busy 是连续的周期状态，核心调度路径不使用 sequence item 逐周期产生 busy，也不
依赖 sequencer/driver 的 item 握手。

transaction 仅用于非核心路径：

- 在发生有效 reservation 时向外部 subscriber 发布事件；
- 在发生实际 MEM 请求时复用现有 memory transaction；
- transaction recording、日志和离线调试；
- 测试向 scheduler 下发稀疏的配置或定向 external reservation 命令。

checker 的正确性不得依赖 reservation transaction 与 memory transaction 的 TLM
回调先后顺序。

## 9. Reset 与运行模式

reset 时：

- cycle controller 停止接受 reservation；
- scheduler 清空 external busy、SHM busy 和所有 records；
- checker 清空未完成匹配状态；
- reservation busy 驱动为已知值，默认全 0；
- coverage 不把 reset 周期计入正常功能采样。

agent 至少支持：

|模式|行为|
|---|---|
|Active|驱动 reservation busy，运行 scheduler、checker 和 coverage|
|Passive|不驱动 busy，只观察接口并运行适用的协议检查与 coverage|

external busy 生成策略至少应允许全空闲、定向和随机三种配置。具体随机算法不属于
本文范围。

## 10. 实现验收条件

实现满足以下条件时，视为符合本架构：

- `vlm_reservation_agent` 同时持有 reservation vif 和只读 memory vif；
- 只有一个组件负责全局 cycle ID 和两个 interface 的周期同步；
- scheduler 能区分 external busy 与 SHM busy；
- external busy 与 SHM busy 永不重叠；
- 一个 SHM slot 可以保存多笔不同 BANK 的 record；
- `dly == 0` 报告 `UVM_ERROR` 且不进入正常调度模型；
- 每笔合法 MEM 请求能够匹配唯一的到期 SHM record；
- 每笔到期 SHM record 能够匹配唯一的 MEM 请求；
- reservation agent 不驱动或检查 `mem_rdata`；
- 核心 busy 激励不依赖逐周期 sequence item。
