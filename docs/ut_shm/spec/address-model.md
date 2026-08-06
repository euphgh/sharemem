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
请求。无效 mask 对应的元素不形成访问，其地址不参与这项检查。

## 2. 从 creq 生成统一地址

### 2.1 数据元素宽度

`creq_dtype` 决定每个数据元素占用的字节数 `D`：

|编码|`D`|
|---|---:|
|`DTYP_32`|4|
|`DTYP_16`|2|
|`DTYP_8`|1|

`creq_len[t]` 是线程 `t` 的有效数据字节数。有效元素数为
`creq_len[t]/D`，并受 512-bit 数据向量和 offset 向量容量限制。

### 2.2 Offset 解码

`creq_atype_w` 选择 offset 元素宽度 32、16 或 8 bit。每个 raw offset 先按
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

### 2.3 Mask 和尾部 byte

`creq_vmsk[t][k]==0` 时，元素 `k` 不产生有效 byte。mask 有效时，元素内 byte lane
`lane` 的有效条件为：

```text
byte_valid(t,k,lane) =
    creq_vmsk[t][k] && (k*D + lane < creq_len[t])
```

V2M 使用这些有效 byte 形成写数据和 byte strobe；M2V 使用相同范围确定读数据写回
的有效 byte。

## 3. Interleave 参数

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

## 4. SPACE_LOC

SPACE_LOC 表示每个线程访问同编号 BANK 中自己的 WARP 区域：

```text
0 <= MADDR < W
bank_id = thread_index
BADDR = creq_wpid * W + MADDR
```

因此，线程索引选择 BANK，`creq_wpid` 选择 BANK 内的 WARP 区域。尽管
`VADDR_W=14` 可以编码 16 KiB，SPACE_LOC 的合法 MADDR 上限仍是 12 KiB；
`[12 KiB, 16 KiB)` 不得由合法 creq 产生。

当前配置要求 `THD_N==BANK_N==16`。若要支持两者不相等，必须先重新定义线程到
BANK 的映射。

## 5. SPACE_WRP

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

## 6. SPACE_BLK

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

## 7. M2V 写回地址

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

## 8. VTRANS 与地址计算

VTRANS 只转置 V2M 的输入数据矩阵，不改变 `creq_base`、`creq_offs`、地址类型、
address space 或其他控制字段。转置后的每个目标元素继续按普通 V2M 规则计算
MADDR、BANK 和 BADDR。VTRANS 的识别方式和输入限制见
[creq/ack 接口](creq-ack-interface.md#6-vtrans)。

## 9. 三种模式对比

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
