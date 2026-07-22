# RpuShmTop MEM/VLM 接口规范

|项目|内容|
|---|---|
|文档状态|接口级验证基准|
|版本|0.1|
|日期|2026-07-22|
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

### 2.1 BANK 和 super bank

`bank_id` 由 MEM/VLM 端口 packed array 的 BANK 维下标确定：

```systemverilog
bank_id = bank;
super_bank_id = bank_id[1:0];
```

默认 16 BANK 配置形成 4 个 super bank：

|`super_bank_id`|BANK 成员|
|---:|---|
|0|0、4、8、12|
|1|1、5、9、13|
|2|2、6、10、14|
|3|3、7、11、15|

`vlm_rbusy` 和 `vlm_wbusy` 的低维 4 bit 按 super bank 编号索引。旧文档中的 “sub-bank” 在本文中统一改称 **super bank**。

### 2.2 地址和数据 lane

`mem_*addr` 和 `vlm_*addr` 均为 BANK 内字节地址 BADDR。一个 MEM beat 为 256 bit，即 32 Byte。MEM beat 地址必须按 32 Byte 对齐：

```systemverilog
addr[4:0] == 5'b0;
```

对于 byte lane `k`，其中 `0 <= k < 32`：

```systemverilog
byte_address = addr + k;
byte_data    = data[k*8 +: 8];
```

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

当 `mem_wvld[bank] == 1` 时，形成一笔对 `bank` 的写事务：

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

### 3.3 MEM 读行为

当 `mem_rvld[bank] == 1` 时，形成一笔对 `bank` 的读事务，读取从 `mem_raddr[bank]` 开始的连续 32 Byte。

MEM 读接口没有返回 valid。验证环境必须在请求被采样后的固定 `RPORT_DLY` 周期提供读数据：

```text
T              : mem_rvld[bank] == 1，采样 mem_raddr[bank]
T + RPORT_DLY  : DUT 采样 mem_rdata[bank]
```

`mem_rdata[bank][k*8 +: 8]` 对应请求地址 `mem_raddr[bank] + k`。读通路允许每周期接受一笔请求，因此 memory model 必须支持流水返回；同一 BANK 连续周期的请求在返回端保持请求顺序。

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
|`MEM-007`|每笔 MEM 请求必须存在一笔匹配的 VLM 预约，匹配规则见第 5 章。|
|`MEM-008`|memory model 必须在 `T+RPORT_DLY` 提供读返回，禁止提前、延后或改变同一 BANK 的返回顺序。|
|`MEM-009`|存在到期读返回时，对应的 256-bit `mem_rdata[bank]` 禁止包含 X/Z。|

当相应 valid 为 0 时，地址、strobe 和数据均为 don't-care，验证器不得检查其数值或稳定性。

## 4. VLM 预约接口

### 4.1 接口作用

VLM 接口不执行存储访问，也不传输实际写数据或读返回数据。它向调度模块预告未来的 MEM 访问，并依据调度模块提供的 busy 时间表选择合法的 super bank 时隙。

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
|`vlm_rbusy`|输入|`logic [VTAB_D-1:0][3:0]`|未来各周期、各 super bank 的读端口占用表|
|`vlm_wbusy`|输入|`logic [VTAB_D-1:0][3:0]`|未来各周期、各 super bank 的写端口占用表|

定义如下：

```systemverilog
vlm_rbusy[d][s] == 1; // super bank s 在 T+d 已有读预约
vlm_wbusy[d][s] == 1; // super bank s 在 T+d 已有写预约
```

读 busy 和写 busy 是相互独立的资源。同一 `d`、同一 super bank 允许同时存在一个读预约和一个写预约。

busy 表由 VLM 调度模块或 testbench 调度模型驱动。对于在周期 `T` 新接受且 `d > 0` 的预约，在复位未再次生效的前提下，其占用必须逐周期前移：

```text
T       : 接受 delay=d 的预约
T + n   : busy[d-n][super_bank_id] == 1，1 <= n <= d
T + d   : busy[0][super_bank_id] == 1，同时兑现为 MEM 请求
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
3. `vlm_rbusy[vlm_rdly[bank]][bank[1:0]]` 必须为 0。
4. 必须在 `T + vlm_rdly[bank]` 产生匹配的 `mem_rvld[bank]`。
5. 匹配的 `mem_raddr[bank]` 必须等于预约的 `vlm_raddr[bank]`。

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
2. `vlm_waddr[bank][port]` 必须是合法且 32 Byte 对齐的 BADDR。
3. `vlm_wbusy[vlm_wdly[bank][port]][bank[1:0]]` 必须为 0。
4. 必须在 `T + vlm_wdly[bank][port]` 产生匹配的 `mem_wvld[bank]`。
5. 匹配的 `mem_waddr[bank]` 必须等于预约的 `vlm_waddr[bank][port]`。

特别地，`vlm_wdly[bank][port] == 0` 表示同周期预约并执行：

```text
cycle T:
    vlm_wreq[bank][port] == 1
    mem_wvld[bank] == 1
    vlm_waddr[bank][port] == mem_waddr[bank]
```

VLM 写预约只预告 BANK 和 beat 地址，不预告 `mem_wstrb` 或 `mem_wdata`。

### 4.5 同周期新预约的冲突规则

busy 输入只表示当前周期开始前已经存在的预约，不包含 DUT 在当前周期新输出的其他预约。因此 DUT 必须同时避免新预约彼此冲突。

对每个方向、每个 delay `d` 和每个 super bank `s`：

```text
当前周期新产生且 dly=d、bank_id[1:0]=s 的预约数量 <= 1
```

该规则作用于同一方向的所有 BANK 和所有写预约通道。例如，以下写预约组合是禁止的：

```text
vlm_wreq[0][0]  = 1, vlm_wdly[0][0]  = 3
vlm_wreq[4][1]  = 1, vlm_wdly[4][1]  = 3
```

因为 BANK0 和 BANK4 都属于 super bank 0，并预约了相同的写时隙 `T+3`。

以下组合是允许的：

- 相同 super bank、不同 delay；
- 相同 delay、不同 super bank；
- 相同 delay 和 super bank，但一个是读预约、另一个是写预约。

两条 `vlm_wreq[bank][0:1]` 可以同时有效，但其 delay 必须不同；否则两笔预约会占用相同 BANK、相同 super bank、相同写时隙。

### 4.6 VLM 禁止行为和检查规则

|ID|规则|
|---|---|
|`VLM-001`|复位期间 `vlm_rreq` 和 `vlm_wreq` 必须为 0。|
|`VLM-002`|所有 `vlm_*req` 禁止包含 X/Z。|
|`VLM-003`|req 有效时，对应 addr 和 dly 禁止包含 X/Z。|
|`VLM-004`|req 有效时，dly 禁止大于或等于 `VTAB_D`，即禁止使用编码空间中的无效值。|
|`VLM-005`|req 有效时，对应地址必须 32 Byte 对齐。|
|`VLM-006`|禁止在对应的 `busy[dly][bank_id[1:0]] == 1` 时发出预约。|
|`VLM-007`|禁止同方向的新预约占用相同的 `<dly, super_bank_id>`。|
|`VLM-008`|每笔预约必须在到期周期产生且只产生一笔同 BANK、同地址、同方向的 MEM 请求。|
|`VLM-009`|禁止提前或延后兑现预约。|
|`VLM-010`|禁止重复发布同一笔预约。|
|`VLM-011`|`dly == 0` 时必须同周期产生匹配的 `mem_*vld` 和 `mem_*addr`。|
|`VLM-012`|`dly > 0` 的新预约必须由调度环境在下一周期反映为 `busy[dly-1][super_bank_id] == 1`。该项检查的是调度模型，不是 DUT。|
|`VLM-013`|复位释放后，验证环境驱动的 `vlm_rbusy` 和 `vlm_wbusy` 禁止包含 X/Z。|

当 req 为 0 时，对应 addr 和 dly 为 don't-care，验证器不得检查其数值或稳定性。

## 5. VLM 与 MEM 的端到端匹配

### 5.1 匹配键

checker 必须为每笔有效 VLM 预约创建 pending record：

```text
direction
bank_id
address
issue_cycle
dly
due_cycle = issue_cycle + dly
```

MEM 请求使用以下键与 pending record 匹配：

```text
<direction, bank_id, address, due_cycle>
```

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

建议把检查划分为四个相互独立的组件：

|组件|职责|
|---|---|
|MEM monitor|采集每个 BANK 的读写事务，展开写 byte lane|
|MEM memory model|执行 byte-strobe 写，并在固定 `RPORT_DLY` 后返回 32 Byte 读数据|
|VLM reservation monitor|采集预约，检查 dly、地址、busy 和同周期冲突|
|VLM-MEM checker|维护 pending record，检查预约与实际 MEM 请求一一对应|

最低功能覆盖率应包含：

- 读/写方向；
- `dly == 0`、`dly == 1`、`dly == VTAB_D-1`；
- 4 个 super bank；
- 16 个 BANK；
- 两条 VLM 写预约通道；
- 同周期跨 super bank 并行预约；
- 同一 super bank 的不同 delay 预约；
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
