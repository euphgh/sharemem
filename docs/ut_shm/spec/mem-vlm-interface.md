# RpuShmTop MEM/VLM 接口规范

本文定义 `RpuShmTop` 的 MEM 数据接口、VLM reservation 接口以及两者的一一匹配
关系。creq 如何生成 BANK 和 BADDR 见[地址模型](address-model.md)。本文中的方向
均以 DUT 为参考，所有信号均在 `clk` 上升沿采样。

## 1. 参数和基本约定

|参数|当前值|接口含义|
|---|---:|---|
|`BANK_N`|16|物理 BANK 数量|
|`BADDR_W`|17|BANK 内字节地址宽度|
|`RPORT_DLY`|4|MEM 读请求到读数据返回的固定周期数|
|`VTAB_D`|12|reservation busy 窗口深度|
|`VLM_SUB_BANK_N`|4|每个 BANK 的 sub bank 数量|
|`WRITE_PORT_N`|2|每个 BANK 的写 reservation 端口数|

MEM 和 VLM 地址都是 BANK 内字节地址 BADDR。BANK 由 packed array 下标确定；地址
`address[6:5]` 选择该 BANK 内的 sub bank：

```text
bank_id = packed array index
sub_bank_id = address[6:5]
```

一个 MEM beat 为 256 bit，即 32 Byte。byte lane `k` 对应：

```text
byte_address = address + k
byte_data = data[k*8 +: 8]
```

读地址、读 reservation 地址和写 reservation port 1 地址必须 32 Byte 对齐：

```text
address[4:0] == 0
```

写 reservation port 0 允许非对齐地址。其到期后，`mem_waddr` 必须逐位等于预告的
完整地址，因此 MEM 写地址也可能非对齐。匹配时禁止清除低 5 bit 或只比较 beat
编号。

## 2. MEM 接口

### 2.1 端口

|端口|方向|含义|
|---|---|---|
|`mem_rvld[BANK_N]`|输出|每个 BANK 的读请求有效信号|
|`mem_raddr[BANK_N]`|输出|每个 BANK 的 32-Byte 读地址|
|`mem_rdata[BANK_N][255:0]`|输入|固定延迟读返回数据|
|`mem_wvld[BANK_N]`|输出|每个 BANK 的写请求有效信号|
|`mem_waddr[BANK_N]`|输出|每个 BANK 的写地址|
|`mem_wstrb[BANK_N][31:0]`|输出|32 个 byte lane 的写使能|
|`mem_wdata[BANK_N][255:0]`|输出|写数据|

MEM 没有 ready。`mem_rvld[bank]` 或 `mem_wvld[bank]` 在采样沿为 1，就表示该 BANK
的一笔请求在该周期被接受。

### 2.2 写事务

当 `mem_wvld[bank]==1` 时，`mem_waddr[bank]`、`mem_wstrb[bank]` 和
`mem_wdata[bank]` 形成一笔写事务。对于 lane `k`：

- strobe 为 1 时，将对应 data byte 写入 `mem_waddr[bank]+k`；
- strobe 为 0 时，原地址内容保持不变，对应 data lane 是 don't-care。

有效写请求必须至少包含一个 strobe。不同 BANK 可以在同一周期并行写入。

### 2.3 读事务

当周期 `T` 采样到 `mem_rvld[bank]==1` 时，外部 memory model 必须在
`T+RPORT_DLY` 提供从 `mem_raddr[bank]` 开始的连续 32 Byte：

```text
T             : DUT 发出 mem_rvld 和 mem_raddr
T+RPORT_DLY   : DUT 采样对应 mem_rdata
```

读返回没有 valid。接口允许同一 BANK 每周期接受一笔读请求，因此 memory model
必须支持流水返回，并保持同一 BANK 的请求顺序。没有历史读请求与当前周期对应时，
`mem_rdata` 是 don't-care。

### 2.4 同周期读写

读写通道相互独立，同一周期可以对同一或不同 BANK 各发一笔读写请求。同一 BANK
的读写 byte 范围重叠时，读到旧值还是新值未定义；测试不得依赖其中一种结果。

## 3. VLM reservation 接口

VLM 接口不传输实际数据。它预告未来在哪个周期使用某个 BANK/sub bank 的 MEM
端口，并由外部调度模块通过 busy 表报告已经占用的时隙。

### 3.1 busy 输入

|端口|方向|含义|
|---|---|---|
|`vlm_rbusy[VTAB_D][4]`|输入|未来各 delay、sub bank 的读占用表|
|`vlm_wbusy[VTAB_D][4]`|输入|未来各 delay、sub bank 的写占用表|

在周期 `T`：

```text
vlm_rbusy[d][s] == 1  // sub bank s 在 T+d 已有读占用
vlm_wbusy[d][s] == 1  // sub bank s 在 T+d 已有写占用
```

读 busy 和写 busy 是独立资源。busy 不包含 BANK 维度，一个 bit 可以同时代表多个
不同 BANK 在相同方向、到期周期和 sub bank 上的 reservation。busy 也可能包含其他
模块产生的占用，DUT 不能假设所有 busy 都来自自身请求。

### 3.2 读 reservation

|端口|方向|含义|
|---|---|---|
|`vlm_rreq[BANK_N]`|输出|每个 BANK 的读 reservation 有效信号|
|`vlm_raddr[BANK_N]`|输出|预约的 BANK 内读地址|
|`vlm_rdly[BANK_N]`|输出|距离实际 MEM 读请求的周期数|

当周期 `T` 的 `vlm_rreq[bank]==1` 时：

```text
1 <= vlm_rdly[bank] < VTAB_D
vlm_raddr[bank][4:0] == 0
sub_bank = vlm_raddr[bank][6:5]
vlm_rbusy[vlm_rdly[bank]][sub_bank] == 0
```

DUT 必须在 `T+vlm_rdly[bank]` 发出一笔同 BANK、同完整地址的 MEM 读请求。

### 3.3 写 reservation

|端口|方向|含义|
|---|---|---|
|`vlm_wreq[BANK_N][2]`|输出|每个 BANK 的两条写 reservation 有效信号|
|`vlm_waddr[BANK_N][2]`|输出|预约的 BANK 内写地址|
|`vlm_wdly[BANK_N][2]`|输出|距离实际 MEM 写请求的周期数|

当周期 `T` 的 `vlm_wreq[bank][port]==1` 时：

```text
1 <= vlm_wdly[bank][port] < VTAB_D
sub_bank = vlm_waddr[bank][port][6:5]
vlm_wbusy[vlm_wdly[bank][port]][sub_bank] == 0
```

`port==1` 时地址必须 32 Byte 对齐，`port==0` 时允许非对齐。DUT 必须在到期周期
发出一笔同 BANK、同完整地址的 MEM 写请求。reservation 不预告 `mem_wstrb` 或
`mem_wdata`。

### 3.4 delay 和 busy 前移

当前协议不支持 `dly==0`。一笔 reservation 的到期周期为：

```text
due_cycle = issue_cycle + issue_delay
```

周期 `T` 接受一笔 delay 为 `d` 的 reservation 后，调度环境从下一个周期开始把
该占用反映到 busy 表：

```text
T+1     : busy[d-1][sub_bank] == 1
T+n     : busy[d-n][sub_bank] == 1，1 <= n <= d
T+d     : busy[0][sub_bank] == 1，同时出现匹配的 MEM 请求
```

reservation 只在 issue 周期发布一次。DUT 不得在后续周期用递减 delay 重复发布同一
笔预约。

### 3.5 并行与冲突

不同 BANK 可以在同一周期、相同方向预约相同 `<dly, sub_bank>`，这是合法行为，
因为 busy bit 不区分 BANK。读、写方向也彼此独立，同一 BANK 可以在同一到期周期
各有一笔读和一笔写。

每个 BANK 在每个方向只有一条实际 MEM 端口，因此同一 BANK、同一方向不能有两笔
不同 reservation 在同一周期到期，即使它们访问不同 sub bank。两条写 reservation
端口可以在同一 issue 周期有效，但不同写事务的 due cycle 必须不同。

DUT 发布 reservation 时，目标 `busy[dly][sub_bank]` 必须严格为 0；X/Z 不视为
空闲。不同 delay 或不同 sub bank 的占用不阻塞该请求。

## 4. Reservation 与 MEM 的匹配

每笔 reservation 由以下信息描述：

```text
direction
bank_id
address
issue_cycle
issue_delay
due_cycle = issue_cycle + issue_delay
```

到期 MEM 请求使用完整键匹配：

```text
<direction, bank_id, address, due_cycle>
```

`address` 必须逐位相等。特别是 write port 0 的非对齐预约必须由同样非对齐的
`mem_waddr` 原样兑现。`mem_wstrb` 和 `mem_wdata` 不属于 reservation 匹配键，由
MEM 数据检查单独处理。

匹配关系必须双向完备：

1. 每笔 reservation 在到期周期必须产生且只产生一笔匹配 MEM 请求；
2. 每笔 MEM 请求必须找到一笔当前周期到期的 reservation。

因此，缺少一侧、方向/BANK/地址不等、提前、延后、重复兑现或多对一匹配都属于
协议错误。

## 5. 复位和 X/Z

`rst_n==0` 时，DUT 必须保持 `mem_rvld`、`mem_wvld`、`vlm_rreq` 和 `vlm_wreq`
为 0。验证环境驱动的 busy 和 `mem_rdata` 应为已知值，monitor 不采集复位期间的
事务。

运行中复位会取消所有尚未到期的 reservation 和 MEM read pipeline 事务。调度环境
必须清空 pending record 和 busy 所有权；复位释放后从空状态重新开始，复位前的
预约不得继续兑现。

复位释放后：

- `mem_*vld`、`vlm_*req` 和 busy 禁止包含 X/Z；
- valid/req 有效时，对应地址和 delay 禁止包含 X/Z；
- MEM 写有效时，strobe 和所有 strobe 有效的数据 byte 禁止包含 X/Z；
- 存在到期读返回时，对应 `mem_rdata` 禁止包含 X/Z。

valid/req 为 0 时，相应地址、delay、strobe 和 data 是 don't-care。

## 6. 检查规则

|ID|规则|
|---|---|
|`MEM-001`|复位期间 `mem_rvld` 和 `mem_wvld` 必须为 0。|
|`MEM-002`|`mem_rvld` 有效时，地址必须已知且 32 Byte 对齐。|
|`MEM-003`|`mem_wvld` 有效时，地址、strobe 和有效 data lane 必须已知，且 strobe 不得全 0。|
|`MEM-004`|读请求后的 `RPORT_DLY` 周期必须提供对应 BANK、对应顺序的 32-Byte 读数据。|
|`MEM-005`|每笔 MEM 请求必须匹配一笔当前周期到期的 reservation。|
|`VLM-001`|复位期间 `vlm_rreq` 和 `vlm_wreq` 必须为 0。|
|`VLM-002`|req 有效时，addr 和 dly 必须已知，且 `1 <= dly < VTAB_D`。|
|`VLM-003`|读 reservation 和写 port 1 必须 32 Byte 对齐；写 port 0 允许非对齐。|
|`VLM-004`|发布 reservation 时，对应方向的 `busy[dly][address[6:5]]` 必须严格为 0。|
|`VLM-005`|同一 BANK、同一方向不得有两笔不同 reservation 在同一周期到期。|
|`VLM-006`|每笔 reservation 必须在到期周期产生且只产生一笔同方向、同 BANK、同完整地址的 MEM 请求。|
|`VLM-007`|write port 0 的非对齐 reservation 与 `mem_waddr` 必须完整相等，禁止按 32 Byte 对齐后比较。|
|`VLM-008`|不同 BANK 可以共享相同方向、delay 和 sub bank 的 busy 时隙，checker 不得因此报错。|
|`VLM-009`|复位会取消全部 pending reservation，复位后不得兑现旧事务。|

## 7. 未定义行为

当前接口不规定以下行为：

- 同一周期同一 BANK 重叠地址 read-during-write 返回旧值还是新值；
- valid/req 无效时 payload 的数值和稳定性；
- 外部环境违反 busy、读返回或输入已知值要求后的 DUT 结果；
- creq 本身违反地址范围或地址空洞约束后的 DUT 结果。

测试和 checker 不得依赖这些未定义场景推导功能结果。
