# ut\_shm 验证方案

## 1\. 概述

### 1\.0 验证环境架构图

下图展示了 ut\_shm 验证环境的整体结构，包含 DUT（RpuShmTop）、DUT 各接口、UVM 验证组件及其连接关系。虚线框标注的组件（ref\_svt\_mem / imp\_svt\_mem）尚未实现。

> *图 1\-0：ut\_shm 验证环境架构图*

### 1\.1 DUT 功能简介

RpuShmTop 模块是 RPU 中 Share Memory 的地址映射单元，负责将访存指令转换为对 16 个 BANK 物理存储的读写请求。

#### 接口说明

|接口|方向|功能描述|
|---|---|---|
|creq<br>|输入|接收访存指令。请求通道基于 credit 流控，无握手信号。<br>写请求携带写地址与写数据；<br>读请求仅携带读地址，不返回读数据|
|mem|双向|向 16 个 BANK 发起物理读写请求。<br>写请求流程：DUT 发送目标写地址和写数据，完成写入<br>读请求流程：DUT 发送读地址 → 等待物理存储返回数据 → 将数据写回由 creq\_vaddr 指定的目标地址（详见第 3 章地址空间映射）|
|ack|输出|返回指令完成状态。creq 中包含 ack 使能位，未使能时不返回 ack|
|vlm|双向|向调度模块预告未来 X 个时钟周期内的 DUT 的读写请求。调度模块返回 vlm\_rbusy/vlm\_wbusy 指示存储器忙闲状态。当前验证环境假设物理存储始终空闲|

#### 地址术语定义

|术语|定义|参考点|
|---|---|---|
|指令地址|写请求的写地址、读请求的读地址|相对 DUT|
|写回地址|读请求数据写回的目标地址，由 creq\_vaddr 指定|相对 DUT|
|访存地址|指令地址与写回地址在 BANK 侧的统一表述|相对物理 BANK|

### 1\.2 验证目标与方法学

ut\_shm 验证环境基于 UVM 方法学构建，参考模型（Reference Model）采用 SystemVerilog 实现。验证目标包括：

- 验证 RpuShmTop 在三种地址空间模式下的地址映射正确性（详见第 3 章）

- 验证读写数据通路的完整性

- 未来计划支持 CDV（Coverage Driven Verification）方法学

### 1\.3 验证环境组件

验证环境包含以下核心组件：

|组件|类型|功能描述|
|---|---|---|
|shmins\_mst\_agent|UVM Agent|驱动 creq 输入事务，包含 driver 与 monitor|
|vlm\_slv\_agent|UVM Agent|采集 mem 接口读写事务，送入 scoreboard 比对|
|shm\_reference|Reference Model|根据 creq 指令计算期望的读写地址与数据|
|shm\_scoreboard|Scoreboard|比对 reference 与 DUT 的**写数据**，提供 DUT 读数据预期值|
|shm\_env|UVM Environment|实例化各子组件，管理配置与 TLM 连接|
|shm\_unit\_sequence|Sequence|生成随机合法的 creq 请求，支持定向配置与 virtual sequence 集成|

## 2\. 术语与地址概念

### 2\.1 术语表

|术语|全称|定义|
|---|---|---|
|THD|Thread（线程）|硬件最小执行单元|
|VLM|Vector Local Memory|线程私有存储空间，容量 8KB|
|WARP|Warp（线程束）|线程集合，包含 16 个 THD|
|Block|Block|硬件侧的WARP 集合，包含 8 个 WARP|
|BANK|Bank|物理 SRAM 模块。多个 WARP 的同一编号线程共享同一 BANK，通过地址高位区分|
|vlm\_\*|vlm\_monitor / vlm\_slv\_agent 等|访问物理 BANK 的验证接口，与 VLM（逻辑概念）不同|

### 2\.2 关键参数

参数统一定义于 `shm_config_pkg.sv`，供 ver\_common、ut\_shm 及设计仓库共享。使用时需通过 `import shm_config_pkg::*` 导入。

|参数|值|说明|
|---|---|---|
|THD\_N|16|单 WARP 线程数|
|WARP\_N|8|单 Block 包含的 WARP 数|
|BANK\_N|16|物理 BANK 数量|
|WARP\_STEP|8192|单 BANK 中每个 VLM 的存储容量（Byte），即单线程 VLM 大小|
|VADDR\_W|13|VADDR 位宽，$clog2(8KB) = 13$|
|MADDR\_W|20|MADDR 位宽，Block 总 VLM 容量 = 8 WARP × 16 THD × 8KB = $2^{20}$ Byte|
|BADDR\_W|16|BADDR 位宽，单 BANK 容量 = 8 WARP × 8KB = $2^{16}$ Byte|

### 2\.3 三级地址体系

Share Memory 的 16 个 BANK 可从三种视角理解，对应三级地址：

> *图 2\-1：VADDR、MADDR、BADDR 三级地址关系示意图*

#### VADDR（VLM Address）

- **定义**：线程内部地址，用于索引该线程 8KB VLM 空间

- **位宽**：13bit

- **寻址范围**：\[0, 8KB\]

- **特性**：独立于 MADDR 与 BADDR，仅描述单线程 VLM 内部偏移

#### MADDR（Memory Address）

- **定义**：Block 级统一地址，可寻址整个 Block 所有线程的 VLM 空间

- **位宽**：20bit

- **寻址范围**：\[0, $2^{20}$ Byte\]

- **特性**：20 位地址空间可覆盖 Block 全部 VLM，但地址映射不保证连续性（例如 0\~8KB 不一定对应 WARP0\.THD0 的 VLM）

#### BADDR（Bank Address）

- **定义**：物理 BANK 级地址，用于 BANK 读写操作

- **位宽**：16bit

- **寻址范围**：\[0, $2^{16}$ Byte\]

- **特性**：地址连续。以 BANK0 为例，0\~8KB 对应 WARP0\.TH0 的 VLM，8KB\~16KB 对应 WARP1\.TH0 的 VLM

> **说明**：指令地址、写回地址、访存地址在与 BANK 交互时均以 BADDR 形式表示。

### 2\.4 地址映射关系

#### 地址空间关系

|地址|描述对象|独立性|
|---|---|---|
|VADDR|单线程 VLM 内部地址空间|独立，与 MADDR/BADDR 无直接映射关系|
|MADDR|所有 VLM 构成的 Block 级统一地址空间|作为地址映射的输入|
|BADDR|物理 BANK 地址空间|作为地址映射的输出|

#### 映射流程

访存指令的地址映射流程如下：

```Plain Text
creq指令
  │
  ├─ 输入：creq_base与creq_offs
  ├─ 控制：creq_atype、creq_dtype等信号（计算统一地址的方式）
  │
MADDR（Block 级统一地址，20bit）
  │
  ├─ 输入：maddr2bank() 函数
  ├─ 控制：creq_space 信号（选择映射策略）
  │
<BANK_ID, BADDR>（物理 BANK 地址）
```

#### 映射策略

根据 creq\_space 信号取值，映射策略分为三种：

|模式|全称|访问范围|
|---|---|---|
|SPACE\_LOC|Local|线程私有 VLM 访问|
|SPACE\_WRP|Warp|WARP 内线程间共享访问|
|SPACE\_BLK|Block|Block 级跨 WARP 共享访问|

各模式的具体映射规则详见第 3 章。

## 3\. 地址映射机制

### 3\.1 映射控制信号

creq 访存指令中包含多个控制信号，用于决定地址映射策略。在深入映射规则前，先介绍这些信号的含义：

|信号|位宽|功能描述|
|---|---|---|
|creq\_space|2bit|地址空间选择：SPACE\_LOC、SPACE\_WRP、SPACE\_BLK|
|creq\_wpid|$clog2\(WARP\_N\)|当前执行访存指令的线程组的WARP ID，用于指定访问哪一行 WARP 的 VLM 空间（取值范围 0\~7）|
|creq\_wpnum|$clog2\(WARP\_N\)<br>|Block 中实际使用的 WARP 数量，取值为 1、2、4（对应 $2^0$、$2^1$、$2^2$）|
|creq\_inv\_size|2bit|交织粒度控制信号，与 \+2 后表示交织粒度的 2 的幂次|

**交织粒度说明**：

交织粒度 = $2^{(creq\_inv\_size + 2)}$，取值范围为 4Byte \~ 8KB（$2^2$ \~ $2^{13}$）。交织粒度决定了统一地址空间如何划分到不同的 VLM 中：

- 整个统一地址空间按交织粒度划分为多个**交织块**

- 每个交织块属于不同的 VLM

- 当统一地址跨越交织块边界时，需要访问相邻 BANK 的不同交织块

### 3\.2 映射函数 maddr2bank\(\)

当一笔访存指令进入 DUT 时，DUT 首先为每个线程的每个元素计算 MADDR（统一地址）。一笔指令最多产生 16 线程 × 64 元素 = 1024 个统一地址。随后通过 `maddr2bank()` 函数将统一地址映射为 `<BANK_ID, BADDR>` 的物理地址形式。

```Verilog
function void maddr2bank(
    input  logic [MADDR_W-1:0]        maddr,      // 输入：统一地址
    output logic [$clog2(BANK_N)-1:0] bank_id,    // 输出：目标 BANK 编号
    output logic [BADDR_W-1:0]        baddr       // 输出：目标 BANK 内的字节地址
);
endfunction
```

映射过程除 maddr 外，还依赖 creq\_space、creq\_wpid、creq\_wpnum、creq\_inv\_size 等信号。下面分别介绍三种地址空间模式下的映射规则。

### 3\.3 SPACE\_LOC（线程私有访问）

#### 适用场景

线程访问自身 VLM 中的私有数据，不可跨线程访问。

#### 地址范围

- MADDR 有效位：低 13bit（\[12:0\]），取值范围 \[0, 8KB\]

- MADDR 高 7bit 必须为 0

#### 映射规则

此模式下，MADDR 与 VADDR 含义相同。creq\_wpid 指定访问哪一行 WARP 的 VLM，每个线程仅能访问自身 VLM。

> *图 3\-1：SPACE\_LOC 地址映射示意图（creq\_wpid = 1）*

```Verilog
assign bank_id = creq_wpid;
assign baddr   = maddr[VADDR_W-1:0];  // 取 MADDR 低 13bit
```

**映射特点**：

- bank\_id 直接由 creq\_wpid 决定

- baddr 等于 MADDR 的低 13bit

- 映射关系简单，无交织

### 3\.4 SPACE\_WRP（Warp 内共享访问）

#### 适用场景

同一 WARP 内的线程共享数据，每个线程可访问该 WARP 中任意线程的 VLM。

#### 地址范围

- MADDR 有效位：低 17bit（\[16:0\]），取值范围 \[0, 128KB\]（8KB × 16 线程）

- MADDR 高 3bit 必须为 0

#### 交织机制

与 SPACE\_LOC 不同，SPACE\_WRP 支持交织访问。MADDR 的 17bit 有效地址被划分为三个字段：

|字段|位宽|说明|
|---|---|---|
|interleave\_index（交织块索引）|13 \- inv\_size\_offs\_width bit|索引 VLM 内的不同交织块|
|bank\_id（BANK 编号）|4bit|指定访问哪一个 BANK|
|interleave\_offset（交织块偏移）|inv\_size\_offs\_width bit|索引交织块内的字节偏移|

其中 `inv_size_offs_width = creq_inv_size + 2`，由 ISA 规定。

**交织块数量计算**：

- 单个 VLM 包含交织块数 = $8KB / 2^{inv\_size\_offs\_width} = 2^{13 - inv\_size\_offs\_width}$

- 例：creq\_inv\_size = 0 时，交织粒度 = 4Byte，单个 VLM 包含 $2^{13} = 8192$ 个交织块

> *图 3\-2：SPACE\_WRP 交织地址映射示意图（交织粒度 = 4Byte）*

```Verilog
int inv_size_offs_width = creq_inv_size + 2;
int inv_size_index_width = 13 - inv_size_offs_width;

logic [inv_size_offs_width-1:0]   inv_offs;   // 交织块偏移
logic [inv_size_index_width-1:0]  inv_index;  // 交织块索引

// 核心映射：从 MADDR 中提取三个字段
assign {inv_index, bank_id, inv_offs} = maddr[16:0];

// 计算实际物理地址：交织索引 + 偏移 + WARP 基地址
assign baddr = {inv_index, inv_offs} + creq_wpid * WARP_STEP;
```

**映射特点**：

- bank\_id 由 MADDR 的中间 4bit 直接决定，与 creq\_wpid 无关

- baddr 需要加上 creq\_wpid × WARP\_STEP 作为基地址偏移

- 支持交织访问，提高 BANK 级并行度

- 交织大小默认是2的n次幂，如果VLM大小不足次幂，则交织大小可以超过

### 3\.5 SPACE\_BLK（Block 级共享访问）

#### 适用场景

Block 内跨 WARP 共享数据，线程可访问多个 WARP 的 VLM 空间。

#### 地址范围

- MADDR 有效位：全部 20bit，取值范围 \[0, $2^{20}$ Byte\]

- 实际可访问的 VLM 范围受 creq\_wpnum 与 creq\_wpid 联合约束

#### WARP 约束规则

creq\_wpnum 指定 Block 中参与访存的 WARP 数量（取值 1、2、4）。creq\_wpid 与最终访问的 WARP 编号（warp\_index）需满足以下约束：

```Verilog
assert((creq_wpid / creq_wpnum) == (warp_index / creq_wpnum));
```

即 warp\_index 与 creq\_wpid 必须位于同一个 creq\_wpnum 大小的整除区间内。

**示例**：creq\_wpnum = 2，creq\_wpid ∈ \{0, 1\} 时，warp\_index 只能访问 WARP0 或 WARP1。

#### 地址划分

MADDR 的 20bit 被划分为五个字段：

|字段|位宽|说明|
|---|---|---|
|warp\_base|MADDR\_W \- warp\_offs\_width \- 4 \- 13 bit|WARP 基地址部分|
|interleave\_index|13 \- inv\_size\_offs\_width bit|交织块索引|
|warp\_offs|warp\_offs\_width bit|WARP 偏移部分|
|bank\_id|4bit|BANK 编号|
|interleave\_offset|inv\_size\_offs\_width bit|交织块偏移|

其中 `warp_offs_width = $clog2(creq_wpnum)`，取值为 0、1、2。

> *图 3\-3：SPACE\_BLK 地址映射示意图（creq\_wpnum = 2，交织粒度 = 4Byte）*

```Verilog
int inv_size_offs_width = creq_inv_size + 2;
int inv_size_index_width = 13 - inv_size_offs_width;
int warp_offs_width = $clog2(creq_wpnum);
int warp_base_width = MADDR_W - warp_offs_width - $clog2(BANK_N) - 13;

logic [inv_size_offs_width-1:0]    inv_offs;
logic [inv_size_index_width-1:0]   inv_index;
logic [warp_offs_width-1:0]        warp_offs;
logic [warp_base_width-1:0]        warp_base;

// 核心映射：从 MADDR 中提取五个字段
{warp_base, inv_index, warp_offs, bank_id, inv_offs} = maddr;

// 计算最终访问的 WARP 编号
int warp_index = warp_base + warp_offs;

// 约束检查：warp_index 与 creq_wpid 位于同一整除区间
assert ((creq_wpid / creq_wpnum) == (warp_index / creq_wpnum));

// 计算实际物理地址
baddr = {inv_index, inv_offs} + warp_index * WARP_STEP;

```

**映射特点**：

- creq\_wpnum 参与 baddr 计算（通过 warp\_index）

- creq\_wpid **不直接参与** baddr 和 bank\_id 的计算，但通过约束条件间接限制可访问范围

- 支持跨 WARP 访问，灵活性最高

### 3\.6 三种模式对比

|对比项|SPACE\_LOC|SPACE\_WRP|SPACE\_BLK|
|---|---|---|---|
|访问范围|单线程 VLM|单 WARP 内所有 VLM|Block 内跨 WARP VLM|
|MADDR 有效位|低 13bit|低 17bit|全部 20bit|
|控制信号|creq\_wpid|creq\_wpid, creq\_inv\_size|creq\_wpid, creq\_wpnum, creq\_inv\_size|
|bank\_id 来源|creq\_wpid|MADDR 中间 4bit|MADDR 中间 4bit|
|creq\_wpid 作用|直接决定 bank\_id|计算 baddr 基地址|约束可访问 WARP 范围|
|交织支持|否|是|是|
|地址连续性|连续|取决于交织粒度|取决于交织粒度与 warp 约束|

## 4\. 事务建模

### 4\.1 输入事务：shmins\_sequence\_item

#### 4\.1\.1 shmins\_interface

`shmins_interface` 对 RTL 的 creq 接口所有位域进行建模，包含指令请求信号与 ack 信号。文件位于 `ver_common/uvc/shmins_agent/shmins_interface.sv`。

该 interface 在 `tb_top` 中实例化后与 DUT 连接，并通过 `uvm_config_db` 传递给 `shmins_mst_driver` 与 `shmins_monitor`。

|信号|位宽|方向|说明|
|---|---|---|---|
|clk|1bit|输入|时钟信号|
|rst\_n|1bit|输入|复位，低有效|
|creq\_vld|1bit|输入|访存指令有效信号|
|creq\_rls|1bit|输入|credit 释放信号|
|creq\_id|ID\_W|输入|访存指令 ID|
|creq\_wpid|$clog2\(WARP\_N\)|输入|执行指令的线程所属的 WARP 编号|
|creq\_wpnum|$clog2\(WARP\_N\+1\)|输入|Block 的 WARP 数量（取值 1、2、4）|
|creq\_prio|4×THD\_N|输入|每线程优先级|
|creq\_len|8×THD\_N|输入|每线程元素个数（0\~32）|
|creq\_typ|16bit|输入|复合类型字段，编码：\[15:14\]space \+ \[13:10\]ilv\_size \+ \[9\]ack\_en \+ \[8:7\]ityp \+ \[6:3\]atyp \+ \[2:1\]dwidth \+ \[0\]rw|
|creq\_vaddr|VADDR\_W|输入|写回地址，所有线程相同|
|creq\_vmsk|64×THD\_N|输入|每线程元素的 mask|
|creq\_base|48bit|输入|指令地址基地址|
|creq\_offs|512×THD\_N|输入|指令地址偏移量，每线程每元素一个|
|creq\_vdat|64×8×THD\_N|输入|写数据，每线程 64 Byte|
|vack\_done|1bit|输出|M2V 类型指令的 Ack|
|vack\_id|ID\_W|输出|Ack 的指令 ID|
|mack\_done|1bit|输出|V2M 类型指令的 Ack|
|mack\_id|ID\_W|输出|Ack 的指令 ID|

#### 4\.1\.2 shmins\_sequence\_item

`shmins_sequence_item` 基于 `shmins_interface` 的信号定义，包含 creq 指令的所有位域（不含 ack 信号）。文件位于 `ver_common/uvc/shmins_agent/sequence/shmins_sequence_item.sv`。

**位域定义**

|类型|变量名|位宽|说明|
|---|---|---|---|
|creq\_rw\_e|creq\_rw|1bit|读写标志：SHM\_V2M \(0\), SHM\_M2V \(1\)|
|creq\_dtype\_e|creq\_dtype<br>|2bit|数据宽度：DTYP\_32 \(0\), DTYP\_16 \(1\), DTYP\_8 \(2\)|
|creq\_atype\_w\_e|creq\_atype\_w|2bit|地址宽度：ATYP\_32 \(0\), ATYP\_16 \(1\), ATYP\_8 \(2\)|
|creq\_atype\_s\_e|creq\_atype\_s|1bit|符号位：ATYP\_U \(0, 无符号\), ATYP\_S \(1, 有符号\)|
|creq\_atype\_g\_e|creq\_atype\_g|1bit|颗粒度标志：GAUTO\_1B \(0\), GAUTO\_DW \(1\)|
|creq\_itype\_e|creq\_itype|2bit<br>|指令类型：LDST\_S \(0\), LDST\_V \(1\), LDSTE\_S \(2\), LDSTE\_V \(3\)|
|creq\_space\_e|creq\_space|2bit|地址空间：SPACE\_LOC \(0\), SPACE\_WRP \(1\), SPACE\_BLK \(2\)|
|logic \[0:0\]|creq\_ack\_en|1bit|应答使能：0 \(禁用\), 1 \(启用\)|
|logic \[3:0\]|creq\_inv\_size|4bit|交织粒度控制，实际交织粒度 = $2^{(creq\_inv\_size + 2)}$|
|logic \[ID\_W\-1:0\]|creq\_id|ID\_W|访存指令 ID|
|logic \[$clog2\(WARP\_N\)\-1:0\]|creq\_wpid<br>|3bit|执行指令的 16 个线程所属的 WARP 编号|
|logic \[$clog2\(WARP\_N\+1\)\-1:0\]|creq\_wpnum|3bit|Block 的 WARP 数量，取值 1、2、4|
|logic \[VADDR\_W\-1:0\]|creq\_vaddr|13bit|写回地址，所有线程相同|
|logic \[47:0\]|creq\_base|48bit|指令地址基地址|
|logic \[511:0\]\[THD\_N\]|creq\_offs|512×16 bit|指令地址偏移量，每线程每元素一个|
|logic \[3:0\]\[THD\_N\]|creq\_prior|4×16 bit|每线程优先级|
|logic \[7:0\]\[THD\_N\]|creq\_len<br>|8×16 bit|每线程元素个数 × 元素宽度（总字节数）|
|logic \[63:0\]\[THD\_N\]|creq\_vmsk|64×16 bit|每线程元素的 mask|
|logic \[63:0\]\[7:0\]\[THD\_N\]|creq\_vdat|64×8×16 bit|写数据，每线程 64 Byte|
|int|delay\_cycle|32bit|随机化延迟周期|

**约束生成**

`shmins_sequence_item` include 了 `shmins_seq_item_constraints.svh`，其中包含由 Python 脚本生成的约束代码。使用 Python 生成的原因：

- 约束需考虑数据宽度（creq\_dtype）、地址宽度（creq\_atype）、地址空间（creq\_space）等信号的交叉组合

- 每种组合需要独立的约束规则，手工维护成本高

- Python 脚本根据参数配置自动生成合法约束

> **说明**：Python 约束生成脚本目前处于本地测试阶段，尚未提交至仓库。该脚本的介绍与使用方法将单独编写文档说明。

**地址计算**

一笔 `shmins_sequence_item` 可直接计算出对 16 个物理 BANK 的访存地址与写回地址：

1. **统一地址计算**：将 creq\_base 与 creq\_offs 按 creq\_dtype、creq\_atype、creq\_itype 规定的规则计算，得到 16 线程 × 32 元素的统一地址（MADDR）

2. **物理地址映射**：按 creq\_space 的三种模式，结合 creq\_wpid、creq\_wpnum、creq\_inv\_size，将 MADDR 映射为 `<BANK_ID, BADDR>`

3. **写回地址计算**：由 creq\_vaddr 直接计算得到

### 4\.2 输出事务：vlm\_sequence\_item

#### 4\.2\.1 vlm\_interface

`vlm_interface` 建模对 16 个 BANK 的读写操作。master 侧仅发送读写 valid 信号，写数据与 valid 同一周期送入，读数据在指定延迟后返回。文件位于 `ver_common/uvc/vlm_slv_agent/vlm_interface.sv`。

|信号|位宽|方向|说明|
|---|---|---|---|
|clk|1bit|输入|时钟信号|
|rst\_n|1bit|输入|复位，低有效|
|vlm\_rvld|BANK\_N \(16bit\)|输入|读请求有效信号，每 bit 对应一个 BANK|
|vlm\_raddr|BADDR\_W × BANK\_N|输入|每 BANK 的读地址|
|vlm\_rdata|256 × BANK\_N|输出|每 BANK 的读返回数据（256bit = 32 Byte），数据在延迟后返回|
|vlm\_wvld|BANK\_N \(16bit\)|输入|写请求有效信号，每 bit 对应一个 BANK|
|vlm\_waddr|BADDR\_W × BANK\_N|输入|每 BANK 的写地址|
|vlm\_wstrb|32 × BANK\_N|输入|每 BANK 的写字节选通信号（32bit 对应 32 Byte）|
|vlm\_wdata|256 × BANK\_N|输入|每 BANK 的写数据（256bit = 32 Byte）|

#### 4\.2\.2 vlm\_sequence\_item

`vlm_sequence_item` 基于 `vlm_interface` 构建，将 DUT 输出端口的读写信号封装为事务格式，供 scoreboard 使用。事务字段与 interface 信号一一对应，包含读写两个方向的完整信息。

### 4\.3 比对事务：shm\_wtrans\_item

`shm_wtrans_item` 继承自 `shmins_sequence_item`（详见 4\.1\.2 节），新增以下字段用于 scoreboard 比对。文件位于 `ut_shm/env/scoreboard/shm_wtrans_item.svh`。

|字段|类型|说明|
|---|---|---|
|issue\_time|time|`shm_reference` 创建该实例的时刻，用于 scoreboard 超时检测|
|wmap|Array of Associative Array|reference 计算的期望写地址与写数据。外层 Array 含 16 个元素对应 16 个 BANK，内层 Associative Array 的 key 为字节级写地址（BADDR），value 为 1 Byte 写数据|

## 5\. 验证组件详解

### 5\.1 已实现组件

本节按数据流顺序介绍已实现的验证组件。各组件交互的事务格式定义见第 4 章。

#### 5\.1\.1 shmins\_mst\_agent

`shmins_mst_agent` 负责驱动 creq 输入事务并采集接口信号，包含 driver 与 monitor 两个子组件。

**shmins\_mst\_driver**

将 `shmins_sequence_item` 驱动到 `shmins_interface` 上。驱动过程中需模拟上层模块的流量控制与延迟行为：

- **Credit 流控**：driver 内部维护 credit\_cnt 信号量。每次拉起 valid 时 credit\_cnt 自增，检测到 release 信号时自减。若 credit\_cnt 已达上限则暂停发送，等待 DUT 释放 credit

- **延迟模拟**：driver 读取 `shmins_sequence_item` 中的 `delay_cycle` 字段，在完成一笔事务驱动后插入相应时钟周期的延迟

**shmins\_monitor**

从 `shmins_interface` 上采集 creq 事务，并通过 TLM FIFO 发送给 `shm_reference`。此外，monitor 包含 ack 超时检查逻辑：

- 若采集到需要 ack 的 creq 事务，但在指定时钟周期内未检测到 ack 返回，则生成 `UVM_ERROR`

#### 5\.1\.2 shm\_reference（写请求路径）

`shm_reference` 接收 `shmins_monitor` 采集的 creq 事务，计算期望的读写地址与数据，生成比对事务后发送给 `shm_scoreboard`。

**工作流程**

4. 从 TLM FIFO 中接收 `shmins_sequence_item`

5. 根据 creq 指令中的位域（creq\_base、creq\_offs、creq\_dtype、creq\_atype、creq\_itype 等）计算每个线程每个元素的统一地址（MADDR）

6. 根据 creq\_space 选择映射策略，将 MADDR 映射为 `<BANK_ID, BADDR>` 物理地址

7. 对于写请求：计算每个 BANK 的写地址与写数据，封装为 `shm_wtrans_item`（详见 4\.3 节）发送给 scoreboard

> **说明**：当前仅实现写请求处理。读请求处理计划见 5\.2 节。

#### 5\.1\.3 vlm\_slv\_agent

`vlm_slv_agent` 采集 mem 接口上的读写事务，送入 scoreboard 与 reference 数据进行比对。

**vlm\_sequence\_item 采集**

基于 `vlm_interface`（详见 4\.2\.1 节）构建的 monitor 将 DUT 的数据输出端口信号转化为 `vlm_sequence_item` 事务格式。

**vlm2aa 转换工具**

`vlm2aa` 工具类将 `vlm_sequence_item` 的写数据转换为 Array of Associative Array 格式。文件位于 `ut_shm/env/util/vlm2aa.svh`，被 `ut_shm/env/shm_util_package.sv` include。使用者通过 `import shm_util_package::*` 导入。

转换规则：

- 外层 Array 含 16 个元素，对应 16 个物理 BANK

- 内层 Associative Array 的 key 为字节级写地址（BADDR），value 为 1 Byte 写数据

- 支持将多笔 `vlm_sequence_item` 的写数据合并到同一个 Array of Associative Array 中

#### 5\.1\.4 shm\_scoreboard

`shm_scoreboard` 负责比对 reference 计算的期望写数据与 DUT 实际输出的写数据。

**原始比对算法**

DUT 会将一笔 `shmins_sequence_item` 拆分为多笔 `vlm_sequence_item` 写入物理存储，且两者之间无直接对应信号。因此比对策略为 **reference 等待 DUT**：

- `shm_wtrans_item`（ref item）包含一笔 creq 指令的所有期望写地址与写数据

- 若一笔 `vlm_sequence_item` 转换后的 Array of Associative Array（rtl item）能够被某个 ref item **完全包含**，则该 rtl item 通过比对

- 比对通过后，从 ref item 中移除已匹配的写地址与写数据；若 ref item 为空，则从队列中移除

```Verilog
task shm_scoreboard::run_phase(uvm_phase phase);
    super.run_phase(phase);
    fork
        collect_ref();           // 从 reference 接收 ref item，放入队列
        scan_timeout_creq();     // 轮询队列，检测超时 ref item
        compare_dut_with_ref();  // 接收 rtl item，与 ref item 逐项比对
    join_none
endtask
```

**scan\_timeout\_creq**：轮询 ref item 队列，若当前时间与 ref item 的 `issue_time` 差值超过阈值，且该 ref item 仍有未匹配的写地址，则生成 `UVM_ERROR` 并删除该 item。

**compare\_dut\_with\_ref**：每接收到一个 rtl item，从队头到队尾逐项匹配。若 rtl item 完全属于某个 ref item，则标记为正确并移除匹配数据。

> **说明**：outstanding 场景下的改进算法见 5\.3 节。

### 5\.2 读请求处理计划

#### 5\.2\.1 ref\_svt\_mem 与 imp\_svt\_mem

`ref_svt_mem` 与 `imp_svt_mem` 均用于建模 RpuShmTop 模块下游的物理 BANK，但实例化位置与服务对象不同：

|对比项|ref\_svt\_mem|imp\_svt\_mem|
|---|---|---|
|实例化位置|`shm_reference`|`shm_scoreboard`|
|服务对象|Reference Model|Scoreboard / DUT|
|触发操作|收到 creq 指令时，对 `ref_svt_mem` 执行对应的读写操作|收到 `vlm_sequence_item` 时，对 `imp_svt_mem` 执行对应的读写操作|
|读请求处理|从 `ref_svt_mem` 读取期望数据，用于后续写回计算|从 `imp_svt_mem` 读取数据，通过 TLM FIFO 返回给 `vlm_slv_monitor`，最终回传给 DUT|
|写请求处理|更新 `ref_svt_mem` 状态，记录期望的写数据|更新 `imp_svt_mem` 状态，维护 DUT 侧物理存储的实际状态|

两者区分的原因：在 outstanding 和乱序场景下，reference 与 DUT 的物理存储数据在中间态不相等是正常现象。保持两份独立的存储模型可避免状态混淆。

#### 5\.2\.2 读请求处理流程

**shm\_reference 端**

8. 计算指令地址，从 `ref_svt_mem` 中读取期望数据

9. 根据 `creq_vaddr` 将数据写回 `ref_svt_mem`

10. 将写回地址与数据封装到 `shm_wtrans_item` 的 `wmap` 中，由 `shm_scoreboard` 比对写回数据是否正确

从 mem 接口的角度，`shm_reference` 仅将写地址和写数据发送给 scoreboard 进行比对，不比对读取数据的正确性。

**imp\_svt\_mem 端**

收到 `vlm_sequence_item` 后对 `imp_svt_mem` 执行读写操作。写请求时更新 `imp_svt_mem` 状态；读请求时从 `imp_svt_mem` 读取数据，通过 TLM FIFO 返回给 `vlm_slv_monitor`，最终回传给 DUT。

> **说明**：`imp_svt_mem` 读请求回传数据的具体实现方式尚未确定，该部分功能尚未开发。

### 5\.3 Outstanding 场景处理

#### 5\.3\.1 问题描述

在 outstanding（多笔指令并行处理）场景下，原始比对算法存在以下问题：

11. **合并写**：DUT 将多笔 outstanding 的 `shmins_sequence_item` 合并为一笔 `vlm_sequence_item` 输出（已确认行为）

12. **覆盖写**：多笔 outstanding 的 creq 指令对同一地址进行写操作时，DUT 可能仅输出最新的写数据（潜在问题，需与设计确认）

原始算法假设一笔 ref item 与 rtl item 之间存在明确的包含关系，但在合并写和覆盖写场景下，该假设不再成立。

#### 5\.3\.2 改进算法

为解决 outstanding 场景问题，改进算法引入以下数据结构：

```Verilog
// 从shm_reference中接受到的golden的事务
shm_wtrans_item ref_items[$];

// 合并所有 ref item 后的最新写数据映射
typedef bit [BADDR_W-1:0] baddr_t;
typedef byte wmap_t [baddr_t][16];
wmap_t wmap_final;

// 被覆盖的旧写数据，按地址记录历史值
typedef byte val_sets_t [$];
typedef val_sets_t wmmap_t [baddr_t][16];
wmmap_t wmap_expired;

// 记录每个地址的写操作来自哪个时刻的事务
typedef time tmap_t [baddr_t][16];
tmap_t trans_matched[$];   // 与 rtl item 匹配上的地址
tmap_t trans_expired[$];   // 被更新 ref item 覆盖的地址
```

算法流程分为三步：

**步骤 1：collect\_ref（接收 reference 事务）**

当从 TLM FIFO 中接收到新的 `shm_wtrans_item`（ref item）时：

1. 遍历 ref item 的 `wmap` 中每个 `<bank_id, baddr, data>` 三元组

2. 若该 `<bank_id, baddr>` 在 `wmap_final` 中已有旧值，将旧值 push 到 `wmap_expired[bank_id][baddr]` 队列中

3. 将新值写入 `wmap_final[bank_id][baddr]`

4. 遍历队列中已有的 ref item，若其 `wmap` 与新 ref item 的地址有交集，将交集地址记录到该 ref item 的 `trans_expired` 中

5. 将新 ref item 加入 `ref_items` 队列

**步骤 2：compare\_dut\_with\_ref（比对 DUT 输出）**

当从 `vlm_slv_monitor` 接收到一笔 `vlm_sequence_item`（rtl item）时：

6. 将 rtl item 通过 `vlm2aa` 转换为 Array of Associative Array

7. 验证 rtl item 中的每个 `<bank_id, baddr, data>` 是否满足以下条件之一：

    - `wmap_final[bank_id][baddr]` 存在且值匹配

    - `wmap_expired[bank_id][baddr]` 有定义且队列中存在该值

8. 若不满足，说明 DUT 写入了 reference 未预期的地址，生成 `UVM_ERROR`

9. 遍历 `ref_items` 队列，对每个 ref item：

    - 若 rtl item 的某个 `<bank_id, baddr, data>` 与该 ref item 的 `wmap` 匹配，将该地址记录到该 ref item 的 `trans_matched` 中

**步骤 3：scan\_timeout\_creq（超时检测）**

周期性地轮询 `ref_items` 队列：

10. 对每个 ref item，检查其 `trans_matched` 与 `trans_expired` 中地址的并集

11. 若并集覆盖该 ref item 的所有写地址，说明所有期望数据要么已匹配，要么被新的 ref item 覆盖，安全删除该 ref item

12. 若当前时间与 ref item 的 `issue_time` 差值超过阈值，且不满足上述条件，说明期望数据未在 DUT 输出中出现，生成 `UVM_ERROR` 并删除该 ref item

> **说明**：改进算法已开发完成但尚未调试通过，当前验证环境（ut\_shm main 分支）使用原始比对算法。

#### 5\.3\.3 collection\_pkg 工具库

改进算法涉及集合运算（交集、并集）与关联数组合并操作。为此开发了 `collection_pkg` 工具库，位于 `ut_shm/env/collection`，提供对 SystemVerilog 原生容器的遍历、合并与集合操作。使用时需 `import collection::*`。

## 6\. 代码仓库与组织

### 6\.1 ver\_common 仓库

ver\_common 仓库包含验证环境的通用组件，供多个 ut\_\* 项目共享使用。

**实现内容**

|模块类型|内容|文件路径|
|---|---|---|
|interface|`shmins_interface`、`vlm_interface` 等|`ver_common/uvc/*/`|
|sequence|sequence\_item、sequence、sequencer|`ver_common/uvc/*/sequence/`|
|agent|driver 与 monitor|`ver_common/uvc/*/`|

**shm 分支**

为防止对 ver\_common 的修改影响其他项目，ut\_shm 相关的修改均位于 `shm` 分支。开发时应基于该分支进行，合并前需评估对其他项目的影响。

**通用脚本**

仓库包含 `ver_common/script/rpu_sim` 仿真运行脚本，负责编译、仿真、结果收集等流程。详见 ver\_common 仓库文档。在实践中发现环境变量中还存在`/proj/common/npu/npudv/rpu_sim`，但是使用存在bug，目前使用ver\_common下的rpu\_sim。此外，shm分支中rpu\_sim脚本也有少量修改，用于支持tc文件中的带文件夹路径的INCLUDE关键字，7\.3\.2节中会详细介绍。

### 6\.2 ut\_shm 仓库

ut\_shm 仓库实现 RpuShmTop 模块的专属验证组件与测试管理。

**实现内容**

|模块|说明|
|---|---|
|reference|`shm_reference`，计算期望读写数据|
|scoreboard|`shm_scoreboard`，比对 reference 与 DUT 输出|
|env|`shm_env`，实例化子组件、管理配置与 TLM 连接|
|test|各 test case 的 UVM test 类|
|事务定义|`shm_wtrans_item` 等比对事务|

**目录结构**

```Plain Text
ut_shm/
├── env/                    # 验证环境组件
│   ├── shm_env.sv          # 顶层环境
│   ├── scoreboard/         # 参考模型与比对引擎
│   │   ├── shm_reference.sv    # 参考模型
│   │   ├── shm_scoreboard.sv   # 比对引擎
│   │   └── shm_wtrans_item.svh # 比对事务定义
│   ├── collection/         # 集合运算工具库
│   ├── util/               # 工具类（vlm2aa 等）
│   └── shm_config_pkg.sv   # 参数定义
├── tc/                     # 测试用例定义（详见 7.3 节）
│   ├── ut_shm.tc
│   └── v2m/
├── regression/             # 回归测试列表（详见 7.3 节）
│   ├── shm_v2m.lst
│   └── pass.lst
└── test/                    # UVM顶层test
```

ut\_shm 的目录结构与其他 ut\_\* 仓库保持一致，便于团队统一管理。

### 6\.3 参数管理

参数统一定义于 `ut_shm/env/shm_config_pkg.sv`，作为一个 SystemVerilog package 供跨仓库共享。

**共享范围**

|仓库|用途|
|---|---|
|ver\_common|interface 位宽定义、sequence 约束参数|
|ut\_shm|reference 计算、scoreboard 比对、事务定义|
|设计仓库|RTL 模块参数化|

**使用规范**

需要使用参数的文件通过 `import shm_config_pkg::*` 导入所有参数。建议与设计团队协商该 package 的维护归属，理想情况下由设计维护、验证引用，确保参数一致性。

## 7\. 测试方案

### 7\.1 测试策略

测试采用**单元测试 → 回归测试**的递进策略：

13. **单元测试**：针对读写功能的各个场景单独验证，确保每种地址空间、指令类型、数据类型的组合均能正确工作

14. **回归测试**：将所有通过的单元测试组合为回归列表，每次代码变更后自动运行，确保无功能回退

当前测试覆盖范围仅限于 v2m（写请求）场景，读请求测试待 ref\_svt\_mem 实现后补充。

### 7\.2 测试用例定义（DUT 相关）

#### 7\.2\.1 用例命名规则

Test Case Name 采用五维度命名法：

```Plain Text
<请求类型>_<指令类型>_<地址空间>_<数据类型>_<地址类型>
```

#### 7\.2\.2 维度取值表

|维度|说明|取值|
|---|---|---|
|请求类型|写请求 / 读请求|v2m（写）, m2v（读）|
|指令类型|ISA 指令类别<br>|vec（LDST\_V/LDST\_S）, ev（LDSTE\_V）, es（LDSTE\_S）|
|地址空间|统一地址解析方式|loc（SPACE\_LOC）, warp（SPACE\_WRP）, block（SPACE\_BLK）|
|数据类型|creq\_vdat 中每个元素的宽度|dtyp32, dtyp16, dtyp8|
|地址类型|creq\_offs 中每个元素的地址宽度|atyp32, atyp16|

**示例**：`v2m_vec_loc_dtyp32_atyp32` 表示写请求、vec 指令类型、SPACE\_LOC 地址空间、32bit 数据宽度、32bit 地址宽度。

**注意：**shm硬件设计可以支持atyp宽度为8bit，但是指令集目前对只有对atyp32和atyp16的定义，而且atyp8会难以生成合法的激励，因此不再测试。

#### 7\.2\.3 测试限制

当前单元测试存在以下限制：

|限制项|说明|配置方式|
|---|---|---|
|延迟放宽|相邻指令间隔 32\~64 个时钟周期，无 outstanding 与流水测试|`+TRANS_DELAY_MIN=32` / `+TRANS_DELAY_MAX=64`|
|warpid 固定|仅测试 warpid = 0 的场景|Randomize with override为0|
|读写类型|仅支持写请求（v2m）|`+CREQ_RW=SHM_V2M`|

#### 7\.2\.4 不支持场景

**LDSTE\_S \+ SPACE\_WRP / SPACE\_BLK**

在 LDSTE\_S（es）指令类型下，不支持 SPACE\_WRP 和 SPACE\_BLK 地址空间。原因：当前设计在该组合下必然导致不同线程写入相同的物理地址，产生不可解决的地址冲突。相关测试用例在 tc 文件中处于注释状态。

### 7\.3 测试脚本组织（结构相关）

#### 7\.3\.1 文件夹结构

```Plain Text
tc/
├── ut_shm.tc           # 根 tc 文件，定义基本配置并 include 子 tc
└── v2m/                # 写请求测试用例
    ├── es_blk.tc       # LDSTE_S + SPACE_BLK（注释状态）
    ├── es_loc.tc       # LDSTE_S + SPACE_LOC
    ├── es_warp.tc      # LDSTE_S + SPACE_WRP（注释状态）
    ├── ev_blk.tc       # LDSTE_V + SPACE_BLK
    ├── ev_loc.tc       # LDSTE_V + SPACE_LOC
    ├── ev_warp.tc      # LDSTE_V + SPACE_WRP
    ├── vec_blk.tc      # LDST_V/LDST_S + SPACE_BLK
    ├── vec_loc.tc      # LDST_V/LDST_S + SPACE_LOC
    └── vec_warp.tc     # LDST_V/LDST_S + SPACE_WRP

regression/
├── pass.lst            # 当前已通过的所有 test case
└── shm_v2m.lst         # 所有定义的写请求 test case

```

#### 7\.3\.2 tc 文件与 INCLUDE 机制

tc 文件定义可用的 test case，每个 test case 本质是一个 UVM\_TESTNAME 与对应 plusargs 的集合。test case name 可传递给 `rpu_sim` 命令的 `-case` 参数单独运行。

**根 tc 文件（ut\_shm\.tc）**

```Plain Text
shm_unit_test
+TRANS_DELAY_MIN=32
+TRANS_DELAY_MAX=64
+CREQ_RW=SHM_V2M
endargs

INCLUDE: v2m/vec_loc.tc
INCLUDE: v2m/es_loc.tc
INCLUDE: v2m/ev_loc.tc
INCLUDE: v2m/vec_warp.tc
# not support for must addr conflict INCLUDE: v2m/es_warp.tc
INCLUDE: v2m/ev_warp.tc
INCLUDE: v2m/vec_blk.tc
# not support for must addr conflict INCLUDE: v2m/es_blk.tc
INCLUDE: v2m/ev_blk.tc

```

- `shm_unit_test`：基本 UVM test 名称

- plusargs：配置相邻指令延迟范围与读写类型

- `endargs`：plusargs 结束标记

- `INCLUDE`：包含子 tc 文件，将子文件中定义的 test case 合并到当前列表

需要注意的是，目前main分支的ver\_common仓库中的rpu\_sim虽然支持INCLUDE关键字，但是不支持带路径的关INCLUDE，要求被INCLUDE的文件与使用INCLUDE的文件均直接位于tc文件夹下。为了结构化的管理tc文件，我对rpu\_sim的相关逻辑进行了一些修改，包括

1. find\_tests函数关于INCLUDE关键字的表达式

2. 在regr模式下，使用$VER\_CMN环境变量调用仓库下的rpu\_sim而非环境变量中的rpu\_sim

```Diff
@@ -427,7 +427,7 @@ sub find_tests { # parse module.tc file
($valid_arg, $discard)=split/#/,$valid_arg;

#for included tc file
- if($valid_arg =~ /^\s*INCLUDE\s*:\s*(\w+)\.tc\s*$/) {
+ if($valid_arg =~ /^\s*INCLUDE\s*:\s*([\w\/.-]+)\.tc\s*$/) {
    my $sub_fname = $tb_dir."/tc/".$1.".tc";
    find_tests($sub_fname);
    if ($debug) {print "sub_tcfile=$sub_fname\n";}
```

```Diff
@@ -14,7 +14,7 @@ my $bjob_param    
my $prj_dir            = $ENV{PRJ_DIR};
- my $ver_dir            = $ENV{VER_DIR};
+ my $ver_cmn            = $ENV{VER_CMN};
my $tb_dir             = $ENV{TB_DIR};
my $blockname          = $ENV{BLOCK_NAME};

@@ -1206,7 +1206,7 @@ sub pre_regress {

    if ($sim_args ne "") {$regr_sim_arg = "-sim_args='$sim_args'";}

-       $run_string = "rpu_sim -lsf=0 -cfg $cfgfile_nopath -tc $tcfile_nopath \\
+       $run_string = "$ver_cmn/script/rpu_sim -lsf=0 -cfg $cfgfile_nopath -tc $tcfile_nopath \\
            -block $blockname -case $tc -def $cfgdef \\
            -sim_dir=$sim_dir \\
```

#### 7\.3\.3 plusargs 配置

|plusarg|说明|当前值|
|---|---|---|
|TRANS\_DELAY\_MIN|相邻指令最小延迟（时钟周期）|32|
|TRANS\_DELAY\_MAX|相邻指令最大延迟（时钟周期）|64|
|CREQ\_RW|指令读写类型|SHM\_V2M（写请求）|

#### 7\.3\.4 回归测试管理

regression/ 目录下每个 lst 文件定义一个回归测试列表，每行一个 Test Case Name，可配置 SEED 数与运行次数。

|文件|用途|
|---|---|
|shm\_v2m\.lst|包含所有定义的写请求 test case，用于完整回归|
|pass\.lst|包含当前已通过的所有 test case，用于日常验证|

### 7\.4 当前测试状态

#### 7\.4\.1 已完成

- v2m 写请求单元测试（vec/ev/es 三种指令类型 × loc/warp/block 三种地址空间）

- 三种地址空间映射逻辑验证

- 基础 scoreboard 比对（原始算法）

- 测试脚本框架（tc/lst 管理、INCLUDE 机制）

- outstanding scoreboard 改进算法调试

#### 7\.4\.2 待完成

- ref\_svt\_mem / imp\_svt\_mem 实现与读请求（m2v）测试支持

- CDV（Coverage Driven Verification）方法学集成

- Python 约束生成脚本文档化

- warpid 覆盖

- LDSTE\_S \+ SPACE\_WRP/SPACE\_BLK 地址冲突问题的设计修复与测试补充

- isz不限制最大范围，以指令集最大为准。允许超过VLM的地址空间大小，但是不允许使用不合法的地址空间进行访问

- shm增加trans功能（矩阵转置）

    - creq\_type高位增加4bit，=15时指示本次请求是trans指令，其他数值无意义

    - trans的抽象等同于vsti，即rw/指令类型等信息同vsti

    - 每个线程16个elem进行一次转置，这样线程0的16个元素就是THD\[0\]\.Elem\[0\], THD\[1\]\. Elem\[0\]\.\.\.然后才是普通的store

    - 支持toff，数据跟随指令一起进来

    - 各线程element len\(非byte len\)只能是16\(BANK\_N\)

    - dtype仅支持8bit/16bit，仅支持space = local模式

    - tmask/emask需要全为1

- Vlm interface

    - vlm\_rreq: 表示未来第vlm\_rdly个周期是会发起一个mem\_rreq

        - vlm\_rreq拉起的**同周期**vlm\_rbusy\[vlm\_rdly\]对应的sub bank必须为0

        - **下一周期**vlm\_rbusy\[vlm\_rdly \- 1\]对应sub bank为1

    - Sub bank分组：地址第两位分组，interleave

    - 

