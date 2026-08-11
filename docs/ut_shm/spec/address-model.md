# RpuShmTop 地址模型

本文定义 creq 地址如何转换成 MADDR，再映射为 `<BANK, BADDR>`。阅读前应先了解
[DUT 概览](dut-overview.md)中的参数和术语；creq 字段编码见
[creq/ack 接口](creq-ack-interface.md)。所有区间均采用左闭右开形式，例如
`0 <= MADDR < 12 KiB`。

## 1. 地址层次

|地址|宽度|当前编码范围|用途|
|---|---:|---:|---|
|VADDR|`VADDR_W=14`|`0 .. 2^14-1`|M2V 写回的线程本地地址|
|MADDR|`MADDR_W=21`|`0 .. 2^21-1`|普通访存的统一字节地址|
|BADDR|`BADDR_W=17`|`0 .. 2^17-1`|BANK 内字节地址|

位宽只说明端口能够编码的范围，不代表其中每个值都是合法地址。每个 WARP 在每个
BANK 内实际占用 `WARP_STEP=12 KiB`；14-bit VADDR 或某些 interleave size 会把该
区域按 16 KiB 编码，超出的 4 KiB 是地址空洞。

地址空洞属于 creq 的输入合法性约束。产生 creq 的模块和验证激励必须保证每个会
形成存储访问的元素 MADDR 均合法，不得依赖 DUT 在收到非法 creq 后丢弃 MEM 或 VLM
请求。inactive thread 或无效 element mask 对应的元素不形成访问，其地址不参与这项
检查。

## 2. 两阶段地址计算流程

一笔 creq 包含 16 个 thread 的访存信息。DUT 先为每个 thread 的每个有效 element
计算统一地址 MADDR，再依据 address space 和 interleave 信息把每个 MADDR 映射为
物理 `<bank_id, BADDR>`：

```text
creq payload
    |
    | creq_base、creq_offs
    | creq_dtype、creq_atype_*、creq_itype
    v
逐 thread、逐有效 element 计算 MADDR
    |
    | MADDR、creq_space、creq_inv_size
    | creq_wpid、creq_wpnum、thread_index
    v
映射为 <bank_id, BADDR>
```

两阶段使用的输入不同：

|阶段|依赖信息|作用|
|---|---|---|
|有效元素选择|`creq_tmsk`、`creq_len`、`creq_vmsk`、`creq_dtype`|确定哪些 thread、element 和 byte 会形成访问|
|Offset 解码|`creq_offs`、`creq_atype_w`、`creq_atype_s`、`creq_atype_g`、`creq_dtype`|确定 raw offset 的宽度、扩展方式和缩放单位|
|MADDR 计算|`creq_base`、解码后的 offset、`creq_itype`|计算每个有效 element 的统一字节地址|
|空间选择|MADDR、`creq_space`|选择 SPACE_LOC、SPACE_WRP 或 SPACE_BLK 映射|
|Interleave|MADDR、`creq_inv_size`、`BANK_N`|得到交织块内偏移、BANK 和交织块索引|
|WARP 定位|`creq_wpid`、`creq_wpnum`、thread index、`WARP_STEP`|选择或检查目标 WARP，并形成最终 BADDR|

`creq_tmsk[t]==0` 的 thread 不进入后续地址计算。`creq_prio` 只影响请求调度顺序，
不参与 MADDR、BANK 或 BADDR 的数值计算。VTRANS 只转置数据，仍使用相同的两阶段
地址计算。

## 3. 从 creq 生成统一地址

### 3.1 数据元素宽度

`creq_dtype` 决定每个数据元素占用的字节数 `D`：

|编码|`D`|
|---|---:|
|`DTYP_32`|4|
|`DTYP_16`|2|
|`DTYP_8`|1|

`creq_len[t]` 是线程 `t` 的有效数据字节数。有效元素数为
`creq_len[t]/D`，并受 512-bit 数据向量和 offset 向量容量限制。

### 3.2 Offset 解码

`creq_atype_w` 选择 offset 元素宽度 32 或 16 bit；8-bit offset 不受支持。每个 raw offset 先按
`creq_atype_s` 做符号扩展或零扩展；当 `creq_atype_g==GAUTO_DW` 时，再乘以数据
元素字节数 `D`。`GAUTO_1B` 不缩放。

记解码后的 offset 为 `E[t][k]`。元素 `k` 的地址偏移为：

|`creq_itype`|地址偏移|
|---|---|
|`LDST_S`、`LDST_V`|`E[t][0] + k*D`|
|`LDSTE_V`|`E[t][k]`|
|`LDSTE_S`|`k*E[t][0]`|

统一地址为：

```text
MADDR[t][k] = creq_base[MADDR_W-1:0] + address_offset[t][k]
```

使用有符号 offset 时可以向低地址移动，但结果仍必须落在所选 address space 的合法
范围内。禁止依靠 `MADDR_W` 截断产生回绕访问。

每个有效元素的最终 MADDR 必须按数据元素字节数 `D` 自然对齐。该规则只约束
`creq_base` 与解码后 address offset 相加得到的结果，不要求 `creq_base` 和 offset
分别自然对齐。验证激励可以暂时采用“base 与 offset 分别对齐”的更强生成限制，但
checker 必须直接检查最终 MADDR，不能把该激励限制解释为 DUT 协议。

### 3.3 Mask 和尾部 byte

`creq_tmsk[t]==0` 时，整个 thread 不产生访问。thread 有效时，
`creq_vmsk[t][k]==0` 的元素也不产生有效 byte。元素内 byte lane `lane` 的有效条件
为：

```text
byte_valid(t,k,lane) =
    creq_tmsk[t] &&
    creq_vmsk[t][k] &&
    (k*D + lane < creq_len[t])
```

V2M 使用这些有效 byte 形成写数据和 byte strobe；M2V 使用相同范围确定读数据写回
的有效 byte。

## 4. Interleave 概念与参数

Interleave 将统一地址空间切成大小为 `G` Byte 的连续交织块。块内 byte offset
保存在 `inv_offs`；跨过一个交织块边界后，映射会切换到下一个 BANK，而不是立刻
增加当前 BANK 内的地址。以 SPACE_WRP 为例：

```text
MADDR [0, G)         -> BANK 0，local block 0
MADDR [G, 2G)        -> BANK 1，local block 0
...
MADDR [15G, 16G)     -> BANK 15，local block 0
MADDR [16G, 17G)     -> BANK 0，local block 1
```

因此，较小的 interleave size 会把相邻地址更快地分散到多个 BANK，较大的
interleave size 则让更多连续 byte 留在同一 BANK。SPACE_BLK 在遍历完全部 BANK
后还会依次遍历 `warp_offs`，随后才增加 `inv_index` 和 `warp_group`：

```text
inv_offs -> bank_id -> warp_offs -> inv_index -> warp_group
```

这里的箭头表示 MADDR 从低位到高位、从变化最快到变化最慢的字段顺序。

令：

```text
I = creq_inv_size + 2
G = 2^I                         // interleave size，单位为 Byte
B = BANK_N
W = WARP_STEP                   // 当前为 12 KiB
N = WARP_N
C = (G <= 4 KiB) ? 12 KiB : 16 KiB
```

当前合法的 `I` 为 2～14，因此 `G` 为 4 Byte～16 KiB。`C` 是 MADDR 为每个
BANK/WARP 编码的空间：当 `G` 能整除 12 KiB 时使用真实容量 12 KiB；`G` 为 8 KiB
或 16 KiB 时按 16 KiB 编码，再通过合法性约束排除尾部地址空洞。

一个 WARP 的真实 BANK 内空间始终是 12 KiB。interleave size 可以大于 12 KiB
能够整除的最大粒度，但合法 creq 仍不得访问 12～16 KiB 的编码空洞。

## 5. SPACE_LOC

SPACE_LOC 表示每个线程访问同编号 BANK 中自己的 WARP 区域：

```text
0 <= MADDR < W
bank_id = thread_index
BADDR = creq_wpid * W + MADDR
```

从硬件位域看，SPACE_LOC 不进行 interleave 拆分：

```systemverilog
local_offs = MADDR[VADDR_W-1:0];
bank_id    = thread_index;
BADDR      = creq_wpid * WARP_STEP + local_offs;
```

合法性约束 `MADDR < WARP_STEP` 保证 `local_offs` 不会进入 12～16 KiB 的编码区域。

因此，线程索引选择 BANK，`creq_wpid` 选择 BANK 内的 WARP 区域。尽管
`VADDR_W=14` 可以编码 16 KiB，SPACE_LOC 的合法 MADDR 上限仍是 12 KiB；
`[12 KiB, 16 KiB)` 不得由合法 creq 产生。

当前配置要求 `THD_N==BANK_N==16`。若要支持两者不相等，必须先重新定义线程到
BANK 的映射。

## 6. SPACE_WRP

SPACE_WRP 允许一个 WARP 内的线程访问任意 BANK。MADDR 的合法编码范围为：

```text
0 <= MADDR < C * B
```

使用整数除法和取模定义映射：

```text
inv_offs   = MADDR % G
bank_id    = (MADDR / G) % B
inv_index  = MADDR / (G * B)
local_offs = inv_index * G + inv_offs

BADDR = creq_wpid * W + local_offs
```

定义 `S=$clog2(B)`、`J=VADDR_W-I`。对当前 request 按 `I` 展开后，上述算术形式等价
于以下位域拼接；当 `J==0` 时省略 `inv_index`：

```systemverilog
{inv_index, bank_id, inv_offs} = MADDR[VADDR_W+S-1:0];
local_offs = {inv_index, inv_offs};
BADDR = creq_wpid * WARP_STEP + local_offs;
```

字段宽度为：

|字段|位宽|
|---|---:|
|`inv_offs`|`I`|
|`bank_id`|`S`|
|`inv_index`|`J`|

合法 SPACE_WRP 的 MADDR 高于 `VADDR_W+S` 的 bit 必须为 0。`G<=4 KiB` 时，MADDR
范围进一步保证 `inv_index < C/G`；`G=8/16 KiB` 时仍需用
`local_offs<WARP_STEP` 排除地址空洞。

每个会形成访问的元素还必须满足：

```text
local_offs < W
```

当 `G <= 4 KiB` 时，`C=W=12 KiB`，整个 MADDR 范围连续有效。当 `G` 为 8 KiB
或 16 KiB 时，MADDR 范围扩展为 `0 .. 16 KiB*BANK_N`，但映射到
`12 KiB <= local_offs < 16 KiB` 的地址是空洞，合法 creq 不得生成这些 MADDR。

例如：

- `G=8 KiB` 时，第二个 interleave block 只有前 4 KiB 有效；
- `G=16 KiB` 时，每个 BANK 编码块的后 4 KiB 无效。

`creq_wpid` 只参与 BADDR 的 WARP 基址计算，不改变 `bank_id`。

## 7. SPACE_BLK

SPACE_BLK 允许 Block 内跨 WARP 访问。令：

```text
P = creq_wpnum                  // 当前合法值为 1、2、4
K = C / G                       // 每个编码空间中的 interleave block 数
```

MADDR 的合法编码范围为：

```text
0 <= MADDR < C * B * N
```

地址字段使用以下算术关系解释：

```text
inv_offs   = MADDR % G
bank_id    = (MADDR / G) % B
warp_offs  = (MADDR / (G * B)) % P
inv_index  = (MADDR / (G * B * P)) % K
warp_group = MADDR / (C * B * P)

warp_base  = warp_group * P
warp_index = warp_base + warp_offs
local_offs = inv_index * G + inv_offs

BADDR = warp_index * W + local_offs
```

硬件位域形式需要先区分 WARP group。定义：

```text
Q = $clog2(P)
J = VADDR_W - I
group_span = C * B * P
```

先把 MADDR 分成 group 编号和 group 内地址，再对 `group_maddr` 做拼接：

```systemverilog
warp_group = MADDR / group_span;
group_maddr = MADDR % group_span;

{inv_index, warp_offs, bank_id, inv_offs} = group_maddr;

warp_base  = warp_group * P;
warp_index = warp_base + warp_offs;
local_offs = {inv_index, inv_offs};
BADDR      = warp_index * WARP_STEP + local_offs;
```

字段宽度为：

|字段|位宽|
|---|---:|
|`inv_offs`|`I`|
|`bank_id`|`$clog2(B)`|
|`warp_offs`|`Q`|
|`inv_index`|`J`|

当 `P==1` 时省略零宽的 `warp_offs`。`group_maddr < group_span` 保证
`inv_index < C/G`，因此这组拼接与前面的除法、取模公式完全等价。

当 `C==16 KiB` 时，`group_span` 是 2 的幂，可以把 group 分解和组内拼接合并为：

```systemverilog
{warp_group, inv_index, warp_offs, bank_id, inv_offs} = MADDR;
```

此时 `warp_group` 的位宽为 `$clog2(N/P)`，五个字段的总宽度正好是当前
`MADDR_W=21`。

当 `C==12 KiB` 时，`group_span` 不是 2 的幂，必须保留
`warp_group/group_maddr` 的预分解；直接把原始 MADDR 固定切成五个字段并不等价。

合法 creq 必须同时满足：

```text
local_offs < W
warp_index < N
creq_wpid / P == warp_index / P
```

`creq_wpid` 只用于最后一条同组 assertion，不参与 `bank_id`、`warp_index` 或 BADDR
计算。真正的 WARP 基地址来自 MADDR：`warp_group` 先乘以 `creq_wpnum` 得到组基址，
再加 `warp_offs` 得到最终 `warp_index`。

当 `G <= 4 KiB` 时，MADDR 范围是 `0 .. 12 KiB*BANK_N*WARP_N`，范围内没有地址
空洞。当 `G` 为 8 KiB 或 16 KiB 时，范围扩展为
`0 .. 16 KiB*BANK_N*WARP_N`，但每个 WARP 中满足
`12 KiB <= local_offs < 16 KiB` 的编码均为地址空洞。

## 8. MEM beat 地址与 byte lane

MADDR、element BADDR 和最终发布到 VLM reservation/MEM 接口的地址都是 byte address。
下游 SRAM 支持从任意 byte address 开始的 32-Byte beat，因此 read/write beat 地址均不
要求 32 Byte 对齐，也不按访问来源区分 alignment policy。

对于任意 read/write beat，lane `k` 对应：

```text
byte_address = beat_addr + k
```

Write strobe 为 1 的 lane 必须携带该 byte address 的正确数据，为 0 的 lane 不得改变
存储内容。普通 V2M、M2V v-write 和 VTRANS 可以采用不同的 beat 划分，只要最终有效
写 byte 的 `<BANK, BADDR, data>` 与 creq 语义一致，且不产生额外有效写。M2V m-read
必须取得所有有效 element 所需的正确 byte。接口中不存在 v-read。

Reservation 和到期 MEM request 必须保留并逐位匹配完整 beat 地址，包括低 5 bit；不能
通过截断低位把两个不同的地址视为相同。逐周期接口契约见
[MEM/VLM 接口](mem-vlm-interface.md)。

## 9. M2V 写回地址

M2V 先按前述映射从外部 MEM 读取数据，再写回线程本地区域。线程 `t`、元素 `k`、
元素内 byte `lane` 的写回位置为：

```text
writeback_bank  = t
writeback_baddr = creq_vaddr
                + creq_wpid * W
                + k * D
                + lane
```

合法 creq 必须保证所有有效写回 byte 均位于所选 WARP 的 12 KiB 区域内。当前一条
向量最多携带 64 Byte，因此完整向量写回时应满足：

```text
0 <= creq_vaddr <= W - 64 Byte
```

## 10. VTRANS 与地址计算

VTRANS 只转置 V2M 的输入数据矩阵，不改变 `creq_base`、`creq_offs`、地址类型、
address space 或其他控制字段。转置后的每个目标元素继续按普通 V2M 规则计算
MADDR、BANK 和 BADDR。VTRANS 的识别方式和输入限制见
[creq/ack 接口](creq-ack-interface.md#6-vtrans)。

VTRANS 使用与普通 V2M 相同的 MADDR 映射和通用非对齐 MEM beat 地址规则。

## 11. 三种模式对比

|项目|SPACE_LOC|SPACE_WRP|SPACE_BLK|
|---|---|---|---|
|BANK 来源|线程索引|MADDR|MADDR|
|WARP 来源|`creq_wpid`|`creq_wpid`|MADDR 中的 `warp_group/warp_offs`|
|`creq_wpid` 作用|BADDR 基址|BADDR 基址|只做同组 assertion|
|`creq_wpnum` 作用|无|无|决定 WARP 组宽度和 `warp_offs`|
|`G <= 4 KiB` MADDR 上界|`12 KiB`|`12 KiB*B`|`12 KiB*B*N`|
|`G=8/16 KiB` MADDR 上界|仍为 `12 KiB`|`16 KiB*B`|`16 KiB*B*N`|
|地址空洞|不允许超出 12 KiB|8/16 KiB interleave 时存在|8/16 KiB interleave 时存在|

所有上界均为 exclusive。验证激励必须对每个有效元素执行范围和空洞检查，不能只
约束 `creq_base` 而忽略 offset 生成的最终 MADDR。
