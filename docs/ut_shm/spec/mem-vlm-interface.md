# RpuShmTop MEM/VLM 接口规范

本文定义 `RpuShmTop` 的 MEM 数据接口、VLM reservation 接口以及两者的一一匹配
关系。creq 如何生成 BANK 和 BADDR 见[地址模型](address-model.md)。本文中的方向
均以 DUT 为参考，所有信号均在 `clk` 上升沿采样。

## 1. 参数和基本约定

|参数|当前值|接口含义|
|---|---:|---|
|`BANK_N`|16|逻辑 bank/MEM 端口数量|
|`GID_N`|2|每个逻辑 bank 对应的物理 BANK 数量|
|`BADDR_W`|16|一个 gid 内的字节地址宽度|
|`FFD_CYC`|1|读请求可见的前向写周期数|
|`RPORT_DLY`|4|MEM 读请求到读数据返回的固定周期数|
|`VTAB_D`|12|reservation busy 窗口深度|
|`VLM_SUB_BANK_N`|4|每个 gid 的 reservation sub-bank 数量|
|`WRITE_PORT_N`|2|每个逻辑 bank 的写 reservation 端口数|

MEM 和 VLM 地址都是 gid 内字节地址 BADDR。逻辑 bank 由 packed array 下标确定，物理
BANK 由 `<bank_id, gid>` 确定；地址 `address[6:5]` 选择该物理 BANK 内的 sub bank：

```text
bank_id = packed array index
physical_bank = <bank_id, gid>
sub_bank_id = address[6:5]
```

VLM reservation 显式携带 gid，MEM 接口不携带 gid。实际 MEM request 的 gid 继承自
同一 direction、bank_id 和 due cycle 下唯一的到期 reservation record。

一个 MEM beat 为 256 bit，即 32 Byte。byte lane `k` 对应：

```text
byte_address = address + k
byte_data = data[k*8 +: 8]
```

Read/write beat 都允许从任意 byte address 开始，不要求 `address[4:0]==0`，也不按访问
来源或 write reservation port 区分 alignment policy。一个 32-Byte beat 可以自然跨过
传统的 32-Byte 地址边界。

所有 reservation 和 MEM request 都必须保留完整地址。Reservation 到期后，MEM 地址
必须逐位等于预告地址；匹配时禁止清除低 5 bit 或只比较对齐后的 beat 编号。

## 2. MEM 接口

### 2.1 端口

|端口|方向|含义|
|---|---|---|
|`mem_rvld[BANK_N]`|输出|每个逻辑 bank port 的读请求有效信号|
|`mem_raddr[BANK_N]`|输出|每个逻辑 bank port 的 16-bit gid 内读地址|
|`mem_rdata[BANK_N][255:0]`|输入|固定延迟读返回数据|
|`mem_wvld[BANK_N]`|输出|每个逻辑 bank port 的写请求有效信号|
|`mem_waddr[BANK_N]`|输出|每个逻辑 bank port 的 16-bit gid 内写地址|
|`mem_wstrb[BANK_N][31:0]`|输出|32 个 byte lane 的写使能|
|`mem_wdata[BANK_N][255:0]`|输出|写数据|

MEM 没有 ready。`mem_rvld[bank]` 或 `mem_wvld[bank]` 在采样沿为 1，就表示该逻辑
bank port 的一笔请求在该周期被接受。该请求访问的 gid 由到期 reservation 确定，不能
仅凭 MEM address 推导。

### 2.2 写事务

当 `mem_wvld[bank]==1` 时，`mem_waddr[bank]`、`mem_wstrb[bank]` 和
`mem_wdata[bank]` 形成一笔写事务。对于 lane `k`：

- strobe 为 1 时，将对应 data byte 写入 `mem_waddr[bank]+k`；
- strobe 为 0 时，原地址内容保持不变，对应 data lane 是 don't-care。

有效写请求必须至少包含一个 strobe。不同逻辑 bank port 可以在同一周期并行写入。

所有访问来源都使用相同的非对齐地址语义：lane `k` 对应 `mem_waddr+k`。普通 V2M
只要求所有有效写 byte 的地址、strobe 和 data 正确，不要求选择特定的 32-Byte 对齐
beat base。

### 2.3 读事务

当周期 `T` 采样到 `mem_rvld[bank]==1` 时，外部 memory model 必须在
`T+RPORT_DLY` 提供从 `mem_raddr[bank]` 开始的连续 32 Byte：

```text
T             : DUT 发出 mem_rvld 和 mem_raddr
T+RPORT_DLY   : DUT 采样对应 mem_rdata
```

读返回没有 valid。接口允许同一逻辑 bank port 每周期接受一笔读请求，因此 memory
model 必须支持流水返回，并保持同一 bank_id 的请求顺序。没有历史读请求与当前周期对应时，
`mem_rdata` 是 don't-care。

### 2.4 `FFD_CYC` 写可见窗口

参数必须满足：

```text
0 <= FFD_CYC <= RPORT_DLY
```

当 MEM read 在周期 `T0` 通过 `mem_rvld/mem_raddr` 被采样时，返回数据在
`T0+RPORT_DLY` 被 DUT 采样。该读允许看到的最后一个 write 接受周期为：

```text
visible_write_cycle = T0 + FFD_CYC - 1
```

返回数据必须包含 `visible_write_cycle` 及之前由 `mem_wvld` 接受的所有重叠写，
并排除该周期之后、即使早于 read return 发生的写。可见性按 byte 判断：只有有效
strobe 对应的 byte 会更新读结果；同一 byte 在可见窗口内被多次写入时，返回截止
周期及之前最后一次有效写入的值。

|`FFD_CYC`|最后可见写周期|同周期同地址读写|
|---:|---|---|
|0|`T0-1`|返回写入前的旧值|
|1|`T0`|包含 `T0` 接受的写，返回新值|
|2|`T0+1`|还包含下一周期接受的写|

例如，当前 `FFD_CYC=1`、`RPORT_DLY=4` 时，`T0` 的 read 在 `T0+4` 返回，并包含
`T0` 及之前的写；`T0+1`～`T0+3` 的写不能进入这笔返回数据。

### 2.5 同周期读写

读写通道相互独立，同一周期可以对同一或不同逻辑 bank 各发一笔读写请求。同一 bank_id
的读写 byte 范围重叠时，返回旧值还是新值由 `FFD_CYC` 决定，不受 testbench 中
monitor、driver 或 scoreboard 的进程调度顺序影响。

## 3. VLM reservation 接口

VLM 接口不传输实际数据。它预告未来在哪个周期使用某个 logical bank/gid/sub bank 的 MEM
端口，并由外部调度模块通过 busy 表报告已经占用的时隙。

### 3.1 busy 输入

|端口|方向|含义|
|---|---|---|
|`vlm_rbusy[VTAB_D][2][4]`|输入|未来各 delay、gid、sub bank 的读占用表|
|`vlm_wbusy[VTAB_D][2][4]`|输入|未来各 delay、gid、sub bank 的写占用表|

在周期 `T`：

```text
vlm_rbusy[d][g][s] == 1  // gid g、sub bank s 在 T+d 已有读占用
vlm_wbusy[d][g][s] == 1  // gid g、sub bank s 在 T+d 已有写占用
```

读 busy 和写 busy 是独立资源。busy 不包含 logical bank 维度，一个 bit 可以同时代表
多个不同 bank_id 在相同方向、到期周期、gid 和 sub bank 上的 reservation。busy 也
可能包含其他模块产生的占用，DUT 不能假设所有 busy 都来自自身请求。

### 3.2 读 reservation

|端口|方向|含义|
|---|---|---|
|`vlm_rreq[BANK_N]`|输出|每个逻辑 bank 的读 reservation 有效信号|
|`vlm_raddr[BANK_N]`|输出|预约的 gid 内读地址|
|`vlm_rdly[BANK_N]`|输出|距离实际 MEM 读请求的周期数|
|`vlm_rgid[BANK_N]`|输出|预约的低/高物理 BANK；0 对应 warp 0～3，1 对应 warp 4～7|

当周期 `T` 的 `vlm_rreq[bank]==1` 时：

```text
1 <= vlm_rdly[bank] < VTAB_D
sub_bank = vlm_raddr[bank][6:5]
gid = vlm_rgid[bank]
vlm_rbusy[vlm_rdly[bank]][gid][sub_bank] == 0
```

DUT 必须在 `T+vlm_rdly[bank]` 发出一笔同 logical bank、同完整地址的 MEM 读请求；
该 MEM request 的物理 gid 由本 reservation record 继承。

### 3.3 写 reservation

|端口|方向|含义|
|---|---|---|
|`vlm_wreq[BANK_N][2]`|输出|每个逻辑 bank 的两条写 reservation 有效信号|
|`vlm_waddr[BANK_N][2]`|输出|预约的 gid 内写地址|
|`vlm_wdly[BANK_N][2]`|输出|距离实际 MEM 写请求的周期数|
|`vlm_wgid[BANK_N][2]`|输出|预约的低/高物理 BANK；0 对应 warp 0～3，1 对应 warp 4～7|

当周期 `T` 的 `vlm_wreq[bank][port]==1` 时：

```text
1 <= vlm_wdly[bank][port] < VTAB_D
sub_bank = vlm_waddr[bank][port][6:5]
gid = vlm_wgid[bank][port]
vlm_wbusy[vlm_wdly[bank][port]][gid][sub_bank] == 0
```

DUT 必须在到期周期发出一笔同 logical bank、同完整地址的 MEM 写请求；物理 gid 由
本 reservation record 继承。Reservation 不预告
`mem_wstrb`、`mem_wdata` 或原始 creq 类型，也不执行 alignment policy。

### 3.4 delay 和 busy 前移

当前协议不支持 `dly==0`。一笔 reservation 的到期周期为：

```text
due_cycle = issue_cycle + issue_delay
```

周期 `T` 接受一笔 delay 为 `d` 的 reservation 后，调度环境从下一个周期开始把
该占用反映到 busy 表：

```text
T+1     : busy[d-1][gid][sub_bank] == 1
T+n     : busy[d-n][gid][sub_bank] == 1，1 <= n <= d
T+d     : busy[0][gid][sub_bank] == 1，同时出现匹配的 MEM 请求
```

reservation 只在 issue 周期发布一次。DUT 不得在后续周期用递减 delay 重复发布同一
笔预约。

### 3.5 并行与冲突

不同 bank_id 可以在同一周期、相同方向预约相同 `<dly, gid, sub_bank>`，这是合法
行为，因为 busy bit 不区分 bank_id。读、写方向也彼此独立，同一 bank_id 可以在同一
到期周期各有一笔读和一笔写。

每个 bank_id 在每个方向只有一条实际 MEM 端口，因此同一 bank_id、同一方向不能有
两笔 reservation 在同一周期到期，即使它们访问不同 gid 或不同 sub bank。这项端口
冲突检查独立于 busy：

- 另一个 gid 的 busy 若只由外部模块产生，不阻塞当前 gid 的请求；
- 另一个 gid 已存在相同 bank_id、direction 和 due cycle 的 DUT reservation 时，
  当前请求必须被阻止；
- 同一 issue cycle 的两个 write reservation port 若使用相同 bank_id 和 dly，不能同时
  发出，无论它们的 gid/sub bank 是否相同；
- 不同 bank_id 仍可以在相同 due cycle 并行使用各自 MEM 端口。

DUT 发布 reservation 时，目标 `busy[dly][gid][sub_bank]` 必须严格为 0；X/Z 不视为
空闲。不同 delay 或不同 gid/sub bank 的外部占用不阻塞该请求。DUT 必须通过自身
pending reservation 状态识别上述跨 gid 的 MEM 端口冲突，不能只依赖合并 busy bit。

## 4. Reservation 与 MEM 的匹配

每笔 reservation 由以下信息描述：

```text
direction
bank_id
gid
address
issue_cycle
issue_delay
due_cycle = issue_cycle + issue_delay
```

Reservation record 的完整键为：

```text
<direction, bank_id, gid, address, due_cycle>
```

MEM 接口没有 gid，直接可观察的匹配字段为：

```text
<direction, bank_id, address, due_cycle>
```

Checker 先按 `<direction, bank_id, due_cycle>` 取得唯一到期 record，再从该 record 恢复
gid，最后逐位比较 MEM address。不得通过 MEM address 反查 gid，也不得在没有唯一到期
record 时猜测 gid。

`address` 必须逐位相等。任何 read/write reservation 都必须由携带相同低地址位的 MEM
request 原样兑现。`mem_wstrb` 和 `mem_wdata` 不属于 reservation 匹配键，由 MEM 数据
检查单独处理。

匹配关系必须双向完备：

1. 每笔 reservation 在到期周期必须产生且只产生一笔匹配 MEM 请求；
2. 每笔 MEM 请求必须找到一笔当前周期到期的唯一 reservation；
3. 匹配成功的 MEM transaction 继承该 record 的 gid，数据模型使用
   `<bank_id, gid, address>` 访问物理存储。

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
- valid/req 有效时，对应地址、delay 和 reservation gid 禁止包含 X/Z；
- MEM 写有效时，strobe 和所有 strobe 有效的数据 byte 禁止包含 X/Z；
- 存在到期读返回时，对应 `mem_rdata` 禁止包含 X/Z。

valid/req 为 0 时，相应地址、delay、strobe 和 data 是 don't-care。

## 6. 检查规则

|ID|规则|
|---|---|
|`MEM-001`|复位期间 `mem_rvld` 和 `mem_wvld` 必须为 0。|
|`MEM-002`|`mem_rvld` 有效时，完整地址必须已知；地址允许非对齐。|
|`MEM-003`|`mem_wvld` 有效时，完整地址、strobe 和有效 data lane 必须已知，且 strobe 不得全 0；地址允许非对齐。|
|`MEM-004`|读请求后的 `RPORT_DLY` 周期必须提供对应 BANK、对应顺序的 32-Byte 读数据；该数据以读地址原有存储状态为基础，只合入 `T0+FFD_CYC-1` 及之前的写。|
|`MEM-005`|每笔 MEM 请求必须匹配一笔当前周期到期的 reservation。|
|`VLM-001`|复位期间 `vlm_rreq` 和 `vlm_wreq` 必须为 0。|
|`VLM-002`|req 有效时，addr、dly 和 gid 必须已知，且 `1 <= dly < VTAB_D`、gid 属于 0/1。|
|`VLM-003`|read/write reservation 地址均允许非对齐，环境不得根据方向、访问来源或 write port 拒绝低 5 bit 非零的请求。|
|`VLM-004`|发布 reservation 时，对应方向的 `busy[dly][gid][address[6:5]]` 必须严格为 0。|
|`VLM-005`|同一 bank_id、同一方向不得有两笔不同 reservation 在同一周期到期，无论 gid/sub bank 是否相同。|
|`VLM-006`|每笔 reservation 必须在到期周期产生且只产生一笔同方向、同 BANK、同完整地址的 MEM 请求。|
|`VLM-007`|read/write reservation 与到期 MEM 地址必须完整相等，禁止清除低 5 bit 后比较。|
|`VLM-008`|不同 bank_id 可以共享相同方向、delay、gid 和 sub bank 的 busy 时隙，checker 不得因此报错。|
|`VLM-009`|复位会取消全部 pending reservation，复位后不得兑现旧事务。|
|`VLM-010`|其他 gid 的 external busy 不阻塞当前 gid；其他 gid 中相同 bank_id/direction/due 的 DUT pending reservation 必须阻塞当前请求。|
|`VLM-011`|同一 bank_id 的两个 write reservation port 不得在同一 issue cycle 发布相同 dly，即使 gid/sub bank 不同。|
|`VLM-012`|MEM transaction 的 gid 必须来自唯一到期 reservation record；没有唯一 record 的 MEM request 不得更新可信 memory model。|

## 7. 未定义行为

当前接口不规定以下行为：

- valid/req 无效时 payload 的数值和稳定性；
- 外部环境违反 busy、读返回或输入已知值要求后的 DUT 结果；
- creq 本身违反地址范围或地址空洞约束后的 DUT 结果。

测试和 checker 不得依赖这些未定义场景推导功能结果。
