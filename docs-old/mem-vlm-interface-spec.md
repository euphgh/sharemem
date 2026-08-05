# RpuShmTop MEM/VLM 接口规范

|项目|内容|
|---|---|
|文档状态|接口级验证基准|
|版本|0.5|
|日期|2026-08-05|
|适用模块|`RpuShmTop`|

## 1. 文档目的

本文定义 `RpuShmTop` 的 MEM 数据接口和 VLM 预约接口，是相关 monitor、memory model、scoreboard、assertion 和功能覆盖率的共同验证基准。

本文只规定以下端口：

- MEM 接口：`mem_rvld`、`mem_raddr`、`mem_rdata`、`mem_wvld`、`mem_waddr`、`mem_wstrb`、`mem_wdata`
- VLM 接口：`vlm_rbusy`、`vlm_wbusy`、`vlm_rreq`、`vlm_raddr`、`vlm_rdly`、`vlm_wreq`、`vlm_waddr`、`vlm_wdly`

`creq` 指令解释、地址空间映射、ack 和读数据写回不属于本文范围。本文中的端口方向均以 `RpuShmTop` 为参考。

当本文与 `docs/index.md` 中的概述性描述不一致时，MEM/VLM 接口验证以本文为准；端口宽度始终以 DUT 实际 elaboration 参数为准。

本文使用以下规范用语：

- **必须**：违反该规则属于 DUT 或验证环境错误。
- **禁止**：验证器必须报告错误。
- **允许**：验证器不得仅因该行为报告错误。
- **未定义**：当前接口契约不保证结果，测试不得依赖该结果。

## 2. 参数和基本约定

接口宽度由实际 elaboration 参数决定。当前 `RpuShmTop.sv` 的默认值如下：

|参数|默认值|接口含义|
|---|---:|---|
|`BANK_N`|16|物理 BANK 数量|
|`BADDR_W`|17|BANK 内字节地址位宽|
|`RPORT_DLY`|4|MEM 读请求到 `mem_rdata` 返回的固定周期数|
|`VTAB_D`|12|VLM busy 时间表的深度|
|`$clog2(VTAB_D)`|4|`vlm_rdly`、`vlm_wdly` 的编码位宽|

除非另有说明，所有接口信号在 `clk` 上升沿采样。当 `rst_n == 0` 时处于复位状态；本文用 `T` 表示一次上升沿采样时刻，用 `T+n` 表示之后第 `n` 个上升沿。

### 2.1 BANK 和 sub bank

`bank_id` 由 MEM/VLM 端口 packed array 的 BANK 维下标确定。每个 BANK 内含 4 个 sub bank，`sub_bank_id` 由该 BANK 内的访问地址决定：

```systemverilog
bank_id = bank;
sub_bank_id = bank_addr[6:5];
```

`bank_id` 与 `sub_bank_id` 是两个独立维度。默认配置包含 16 个 BANK，每个 BANK 均包含 sub bank 0～3；不能根据 `bank_id` 推导 `sub_bank_id`。

`vlm_rbusy` 和 `vlm_wbusy` 的低维 4 bit 按 `sub_bank_id` 索引。

### 2.2 地址和数据 lane

`mem_*addr` 和 `vlm_*addr` 均为 BANK 内字节地址 BADDR。一个 MEM beat 为 256 bit，即 32 Byte。

读地址 `mem_raddr`、`vlm_raddr` 以及写预约端口 1 的
`vlm_waddr[bank][1]` 必须按 32 Byte 对齐：

```systemverilog
addr[4:0] == 5'b0;
```

写预约端口 0 的 `vlm_waddr[bank][0]` 允许非 32 Byte 对齐。该预约兑现时，
`mem_waddr[bank]` 必须逐位等于预约中保存的完整地址，因此 `mem_waddr` 也允许
出现非对齐值。验证器禁止先清除地址低 5 bit、向下取整或只比较 beat 编号。

对于 byte lane `k`，其中 `0 <= k < 32`：

```systemverilog
byte_address = addr + k;
byte_data    = data[k*8 +: 8];
```

地址以 256-bit/32-Byte beat 为粒度在 4 个 sub bank 间交织：

|BANK 内 beat 地址|`sub_bank_id`|
|---:|---:|
|`0x00`|0|
|`0x20`|1|
|`0x40`|2|
|`0x60`|3|
|`0x80`|0|

因此，地址低 7 bit 的含义为：`addr[4:0]` 是 beat 内 byte offset，`addr[6:5]` 是 sub-bank 选择位。

## 3. MEM 接口

### 3.1 端口定义

|端口|方向|类型|含义|
|---|---|---|---|
|`mem_rvld`|输出|`logic [BANK_N-1:0]`|每个 BANK 的读请求有效信号|
|`mem_raddr`|输出|`logic [BANK_N-1:0][BADDR_W-1:0]`|每个 BANK 的读 beat 地址|
|`mem_rdata`|输入|`logic [BANK_N-1:0][255:0]`|每个 BANK 的固定延迟读返回数据|
|`mem_wvld`|输出|`logic [BANK_N-1:0]`|每个 BANK 的写请求有效信号|
|`mem_waddr`|输出|`logic [BANK_N-1:0][BADDR_W-1:0]`|每个 BANK 的写 beat 地址|
|`mem_wstrb`|输出|`logic [BANK_N-1:0][31:0]`|每个 BANK 的 32 个 byte lane 写使能|
|`mem_wdata`|输出|`logic [BANK_N-1:0][255:0]`|每个 BANK 的写数据|

MEM 接口没有 `ready`。`mem_rvld[bank]` 或 `mem_wvld[bank]` 在上升沿为 1，即表示该请求在该上升沿被下游接受，DUT 不得等待额外握手。

### 3.2 MEM 写行为

当 `mem_wvld[bank] == 1` 时，形成一笔对 `bank` 的写事务。`mem_waddr` 可以非
32 Byte 对齐，其合法性由第 5 章定义的到期写预约完整地址决定：

```text
bank    = bank
address = mem_waddr[bank]
strobe  = mem_wstrb[bank]
data    = mem_wdata[bank]
```

对于每个 byte lane `k`：

- `mem_wstrb[bank][k] == 1`：必须把 `mem_wdata[bank][k*8 +: 8]` 写入 `mem_waddr[bank] + k`。
- `mem_wstrb[bank][k] == 0`：该地址原有内容必须保持不变；对应的 `mem_wdata` lane 为 don't-care。

有效写事务必须至少写一个 byte：

```systemverilog
mem_wvld[bank] |-> (mem_wstrb[bank] != '0);
```

不同 BANK 的写事务彼此独立，允许在同一周期并行发出。

`mem_waddr[bank][6:5]` 指定该写事务访问 BANK `bank` 内的哪个 sub bank。

### 3.3 MEM 读行为

当 `mem_rvld[bank] == 1` 时，形成一笔对 `bank` 的读事务，读取从 `mem_raddr[bank]` 开始的连续 32 Byte。

MEM 读接口没有返回 valid。验证环境必须在请求被采样后的固定 `RPORT_DLY` 周期提供读数据：

```text
T              : mem_rvld[bank] == 1，采样 mem_raddr[bank]
T + RPORT_DLY  : DUT 采样 mem_rdata[bank]
```

`mem_rdata[bank][k*8 +: 8]` 对应请求地址 `mem_raddr[bank] + k`。读通路允许每周期接受一笔请求，因此 memory model 必须支持流水返回；同一 BANK 连续周期的请求在返回端保持请求顺序。

`mem_raddr[bank][6:5]` 指定该读事务访问 BANK `bank` 内的哪个 sub bank。

当某个返回周期没有对应的历史读请求时，`mem_rdata` 为 don't-care，DUT 不得使用该值产生可观察结果。

### 3.4 同周期读写

MEM 读写通道相互独立，允许同一周期：

- 不同 BANK 同时读写；
- 同一 BANK 同时出现 `mem_rvld` 和 `mem_wvld`。

同一周期读写同一 BANK 且访问字节范围重叠时，读到旧值还是新值属于未定义行为。定向测试和随机激励不得依赖该返回值；若需要验证该场景，必须先补充 read-during-write 策略。

### 3.5 MEM 禁止行为和检查规则

验证器必须实现以下检查：

|ID|规则|
|---|---|
|`MEM-001`|复位期间 `mem_rvld` 和 `mem_wvld` 必须为 0。|
|`MEM-002`|`mem_rvld`、`mem_wvld` 和有效写事务的 `mem_wstrb` 禁止包含 X/Z。|
|`MEM-003`|当 `mem_rvld[bank] == 1` 时，`mem_raddr[bank]` 禁止包含 X/Z，且必须 32 Byte 对齐。|
|`MEM-004`|当 `mem_wvld[bank] == 1` 时，`mem_waddr[bank]`、`mem_wstrb[bank]` 及所有 strobe 有效的 `mem_wdata` byte 禁止包含 X/Z。|
|`MEM-005`|`mem_wvld[bank] == 1` 时，`mem_wstrb[bank]` 禁止全 0。|
|`MEM-006`|一次 `mem_*vld[bank]` 只能表示该 BANK 的一笔 32-Byte beat，禁止在一个端口周期隐式表示两个不同 beat 地址。|
|`MEM-007`|每笔 MEM 请求必须存在一笔匹配的 VLM 预约，且 MEM 地址必须逐位等于预约保存的完整地址，匹配规则见第 5 章。|
|`MEM-008`|memory model 必须在 `T+RPORT_DLY` 提供读返回，禁止提前、延后或改变同一 BANK 的返回顺序。|
|`MEM-009`|存在到期读返回时，对应的 256-bit `mem_rdata[bank]` 禁止包含 X/Z。|

当相应 valid 为 0 时，地址、strobe 和数据均为 don't-care，验证器不得检查其数值或稳定性。

## 4. VLM 预约接口

### 4.1 接口作用

VLM 接口不执行存储访问，也不传输实际写数据或读返回数据。它向调度模块预告未来的 MEM 访问，并依据调度模块提供的 busy 时间表选择合法的 sub-bank 时隙。

每笔 VLM 预约由以下四项唯一描述：

```text
direction, bank_id, address, due_cycle
```

其中：

```text
due_cycle = issue_cycle + dly
```

一笔预约只在 `vlm_*req` 被采样为 1 的周期创建一次。已经创建的预约不得在后续周期以递减 delay 重复发送。

### 4.2 busy 输入端口

|端口|方向|类型|含义|
|---|---|---|---|
|`vlm_rbusy`|输入|`logic [VTAB_D-1:0][3:0]`|未来各周期、各 sub bank 的读端口占用表|
|`vlm_wbusy`|输入|`logic [VTAB_D-1:0][3:0]`|未来各周期、各 sub bank 的写端口占用表|

定义如下：

```systemverilog
vlm_rbusy[d][s] == 1; // sub bank s 在 T+d 已有读预约
vlm_wbusy[d][s] == 1; // sub bank s 在 T+d 已有写预约
```

读 busy 和写 busy 是相互独立的资源。同一 `d`、同一 sub bank 允许同时存在一个读预约和一个写预约。

busy 表由 VLM 调度模块或 testbench 调度模型驱动。对于在周期 `T` 新接受且 `d > 0` 的预约，在复位未再次生效的前提下，其占用必须逐周期前移：

```text
T       : 接受 delay=d 的预约
T + n   : busy[d-n][sub_bank_id] == 1，1 <= n <= d
T + d   : busy[0][sub_bank_id] == 1，同时兑现为 MEM 请求
```

busy 表可能同时包含其他模块产生的预约，因此 DUT 及 checker 均不得假设 busy 中的每个 1 都由当前 `RpuShmTop` 产生。

### 4.3 读预约输出

|端口|方向|类型|含义|
|---|---|---|---|
|`vlm_rreq`|输出|`logic [BANK_N-1:0]`|每个 BANK 的读预约有效信号|
|`vlm_raddr`|输出|`logic [BANK_N-1:0][BADDR_W-1:0]`|读预约对应的 BANK 内 beat 地址|
|`vlm_rdly`|输出|`logic [BANK_N-1:0][$clog2(VTAB_D)-1:0]`|从当前周期到实际 MEM 读请求的周期数|

当 `vlm_rreq[bank] == 1` 时：

1. `vlm_rdly[bank]` 必须位于 `[0, VTAB_D-1]`。
2. `vlm_raddr[bank]` 必须是合法且 32 Byte 对齐的 BADDR。
3. `sub_bank_id = vlm_raddr[bank][6:5]`。
4. `vlm_rbusy[vlm_rdly[bank]][vlm_raddr[bank][6:5]]` 必须严格等于 0；X/Z 不视为空闲。
5. 必须在 `T + vlm_rdly[bank]` 产生匹配的 `mem_rvld[bank]`。
6. 匹配的 `mem_raddr[bank]` 必须等于预约的 `vlm_raddr[bank]`。

特别地，`vlm_rdly[bank] == 0` 表示同周期预约并执行：

```text
cycle T:
    vlm_rreq[bank] == 1
    mem_rvld[bank] == 1
    vlm_raddr[bank] == mem_raddr[bank]
```

### 4.4 写预约输出

|端口|方向|类型|含义|
|---|---|---|---|
|`vlm_wreq`|输出|`logic [BANK_N-1:0][1:0]`|每个 BANK 的两条写预约有效通道|
|`vlm_waddr`|输出|`logic [BANK_N-1:0][1:0][BADDR_W-1:0]`|每条写预约对应的 BANK 内 beat 地址|
|`vlm_wdly`|输出|`logic [BANK_N-1:0][1:0][$clog2(VTAB_D)-1:0]`|从当前周期到实际 MEM 写请求的周期数|

`port` 取值为 0 或 1。当 `vlm_wreq[bank][port] == 1` 时：

1. `vlm_wdly[bank][port]` 必须位于 `[0, VTAB_D-1]`。
2. `port == 1` 时，`vlm_waddr[bank][port]` 必须是合法且 32 Byte 对齐的 BADDR；`port == 0` 时允许非对齐地址。
3. `sub_bank_id = vlm_waddr[bank][port][6:5]`。
4. `vlm_wbusy[vlm_wdly[bank][port]][vlm_waddr[bank][port][6:5]]` 必须严格等于 0；X/Z 不视为空闲。
5. 必须在 `T + vlm_wdly[bank][port]` 产生匹配的 `mem_wvld[bank]`。
6. 匹配的 `mem_waddr[bank]` 必须等于预约的 `vlm_waddr[bank][port]`。

特别地，`vlm_wdly[bank][port] == 0` 表示同周期预约并执行：

```text
cycle T:
    vlm_wreq[bank][port] == 1
    mem_wvld[bank] == 1
    vlm_waddr[bank][port] == mem_waddr[bank]
```

VLM 写预约只预告 BANK 和 beat 地址，不预告 `mem_wstrb` 或 `mem_wdata`。

### 4.5 多 BANK 并行预约与冲突边界

同一周期允许多个 BANK 同时拉起 reservation req。每笔请求必须根据自身的 BANK 地址独立计算 `sub_bank_id` 并检查 busy：

```systemverilog
foreach (vlm_rreq[i]) begin
  if (vlm_rreq[i]) begin
    assert (vlm_rbusy[vlm_rdly[i]][vlm_raddr[i][6:5]] === 1'b0);
  end
end

foreach (vlm_wreq[i, p]) begin
  if (vlm_wreq[i][p]) begin
    assert (vlm_wbusy[vlm_wdly[i][p]][vlm_waddr[i][p][6:5]] === 1'b0);
  end
end
```

busy 输入表示当前周期开始前已经存在的占用，不包含 DUT 在当前周期新输出的其他预约。

不同 BANK 在相同周期、相同方向预约相同 `<dly, sub_bank_id>` 是允许行为，
不构成 DUT 内部预约冲突。一个 busy bit 可以代表多笔不同 BANK、相同方向且
相同到期周期的预约；checker 不得仅因该组合报告错误。

只有 DUT reservation 与其他外部模块占用相同
`<direction, due_cycle, sub_bank_id>` 时才构成 sub-bank 资源冲突。其他 sub bank
的 external busy 不阻塞该 reservation。验证 scheduler 必须区分 external busy
与 DUT SHM busy，二者不得在同一位置同时有效。DUT 仍须对每笔 reservation
独立检查其发出时看到的最终 busy。

DUT 自身还受 BANK MEM 端口数量限制。每个 BANK 在每个方向只有一条实际 MEM
端口，因此同一 BANK、同一方向不能有两笔不同预约在同一周期到期；该 BANK
冲突与两笔预约访问的 sub bank 是否相同无关。两条
`vlm_wreq[bank][0:1]` 可以同时有效，但若它们表示不同写事务，其
`due_cycle` 必须不同。

读方向与写方向相互独立。同一 BANK 在同一周期允许分别产生一笔读请求和一笔写
请求；同样，不能仅因一笔读预约和一笔写预约具有相同
`<dly, sub_bank_id>` 而报告冲突。

### 4.6 VLM 禁止行为和检查规则

|ID|规则|
|---|---|
|`VLM-001`|复位期间 `vlm_rreq` 和 `vlm_wreq` 必须为 0。|
|`VLM-002`|所有 `vlm_*req` 禁止包含 X/Z。|
|`VLM-003`|req 有效时，对应 addr 和 dly 禁止包含 X/Z。|
|`VLM-004`|req 有效时，dly 禁止大于或等于 `VTAB_D`，即禁止使用编码空间中的无效值。|
|`VLM-005`|读 req 有效时以及 `vlm_wreq[bank][1]` 有效时，对应地址必须 32 Byte 对齐；`vlm_wreq[bank][0]` 允许非对齐地址。|
|`VLM-006`|req 有效时，必须使用对应地址的 `[6:5]` 作为 `sub_bank_id`，并且 `busy[dly][sub_bank_id]` 必须严格等于 0。|
|`VLM-007`|同一 BANK、同一方向禁止有两笔不同预约在同一周期到期，无论其 sub bank 是否相同，因为对应方向只有一条实际 MEM 端口。读写方向独立，同一 BANK 同周期各一笔读写预约不违反本规则。|
|`VLM-008`|每笔预约必须在到期周期产生且只产生一笔同 BANK、同地址、同方向的 MEM 请求。|
|`VLM-009`|禁止提前或延后兑现预约。|
|`VLM-010`|禁止重复发布同一笔预约。|
|`VLM-011`|`dly == 0` 时必须同周期产生匹配的 `mem_*vld` 和 `mem_*addr`。|
|`VLM-012`|`dly > 0` 的新预约必须由调度环境在下一周期反映为 `busy[dly-1][sub_bank_id] == 1`。该项检查的是调度模型，不是 DUT。|
|`VLM-013`|复位释放后，验证环境驱动的 `vlm_rbusy` 和 `vlm_wbusy` 禁止包含 X/Z。|
|`VLM-014`|不同 BANK 可以在相同周期、相同方向预约相同 `<dly, sub_bank_id>`；checker 禁止仅因该组合报告冲突。|
|`VLM-015`|验证 scheduler 的 external busy 与 DUT SHM busy 禁止占用相同 `<direction, due_cycle, sub_bank_id>`。|

当 req 为 0 时，对应 addr 和 dly 为 don't-care，验证器不得检查其数值或稳定性。

## 5. VLM 与 MEM 的端到端匹配

### 5.1 匹配键

验证模型必须为每笔被 scheduler 接受的 VLM 预约创建 pending record。逻辑匹配
信息包括：

```text
direction
bank_id
address
sub_bank_id = address[6:5]
issue_cycle
issue_delay
due_cycle = issue_cycle + issue_delay
```

MEM 请求使用以下键与 pending record 匹配：

```text
<direction, bank_id, address, due_cycle>
```

其中 `address` 是接口采样得到的完整 BADDR，必须逐位相等。禁止把 reservation
地址或 MEM 地址向下对齐、清除 `[4:0]`，也禁止仅比较
`address[BADDR_W-1:5]`。因此，write port 0 预约的非对齐地址必须由
`mem_waddr` 原样兑现。

`mem_wstrb` 和 `mem_wdata` 不属于 VLM 写预约匹配键，由 MEM 数据 checker 单独检查。

### 5.2 双向完备性

checker 必须同时检查：

1. **预约必须兑现**：每笔 VLM 预约在到期周期必须找到一笔匹配 MEM 请求。
2. **访问必须预约**：每笔 MEM 请求必须找到一笔当前周期到期的 VLM 预约。

因此，下列行为全部禁止：

- 有 VLM 预约但没有 MEM 请求；
- 有 MEM 请求但没有 VLM 预约；
- BANK 相同但地址不同；
- 地址相同但 BANK 不同；
- 请求方向不同；
- 请求提前或延后；
- 一笔预约匹配多笔 MEM 请求；
- 多笔预约匹配同一笔 MEM 请求。

### 5.3 `dly == 0` 的 checker 顺序

由于 `dly == 0` 的预约与 MEM 请求在同一采样周期出现，checker 必须先采集该周期的 VLM 预约，再进行该周期的 MEM 匹配，或者将两组信号作为同一个 cycle transaction 原子处理。不得因为软件线程或 monitor 调度顺序而误报 “MEM 无预约”。

### 5.4 写预约双通道与单 MEM 端口

每个 BANK 有两条 VLM 写预约通道，但只有一条 MEM 写端口。两条预约允许在不同到期周期兑现；禁止它们在同一周期到期，因为单个 `mem_wvld[bank]` 无法表示两笔不同地址的 MEM 写事务。

## 6. 复位和 X 传播

### 6.1 DUT 复位要求

当 `rst_n == 0` 时，DUT 必须保持以下信号为 0：

```text
mem_rvld
mem_wvld
vlm_rreq
vlm_wreq
```

其他 DUT 输出在 valid/req 为 0 时为 don't-care。

### 6.2 验证环境复位要求

复位期间，验证环境必须：

- 驱动 `vlm_rbusy` 和 `vlm_wbusy` 为已知值，默认全 0；
- 驱动 `mem_rdata` 为已知值，默认全 0；
- 清空 VLM pending record 和 MEM read-response pipeline；
- 不把复位期间的输出采集为事务。

复位释放后的预约和 MEM 请求从第一个 `rst_n == 1` 的采样沿开始生效。

## 7. 验证实现基准

VLM reservation 的组件划分、scheduler 状态模型和连接关系见
[VLM Reservation 调度与协同验证架构](vlm-reservation-verification-architecture.md)。
接口级实现至少覆盖以下职责：

|组件|职责|
|---|---|
|MEM monitor|采集每个 BANK 的读写事务，展开写 byte lane|
|MEM memory model|执行 byte-strobe 写，并在固定 `RPORT_DLY` 后返回 32 Byte 读数据|
|VLM reservation agent|生成并驱动 busy，区分 external/SHM 来源，检查 dly、地址和逐请求 busy 条件|
|VLM reservation checker|维护到期 record，检查 reservation 与实际 MEM 请求一一对应|

最低功能覆盖率应包含：

- 读/写方向；
- `dly == 0`、`dly == 1`、`dly == VTAB_D-1`；
- 每个 BANK 内的 4 个 sub bank；
- 16 个 BANK；
- 两条 VLM 写预约通道；
- write port 0 的对齐与非对齐地址，以及 write port 1 非对齐地址被拒绝；
- write port 0 非对齐预约与 `mem_waddr` 的完整地址相等和低位不相等场景；
- 同周期不同 BANK、不同 sub bank 的并行预约；
- 同一 sub bank 的不同 delay 预约；
- 不同 BANK 在相同周期、相同方向、相同 `<dly, sub_bank_id>` 的合法共享场景；
- external busy 与 SHM busy 的冲突阻塞；
- busy 阻塞；
- 同周期 MEM 读写；
- full/partial/single-byte 写 strobe；
- 同一 BANK 连续周期流水读。

## 8. 当前未定义行为

下列行为不在当前验证基准中作功能判断：

- 同一周期对同一 BANK 重叠地址的 read-during-write 返回新值还是旧值；
- req/valid 无效时 payload 的数值和稳定性；
- MEM/VLM 接口以外的 `creq`、ack 和地址映射行为；
- 复位中途到来时，复位前尚未到期预约是否被取消以外的内部处理细节。对接口而言，这些 pending record 在复位时统一作废。

若后续设计约束与本文冲突，应先修改本文并记录规则变化，再修改 checker；不得仅在 checker 中加入未文档化的例外。
