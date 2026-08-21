# RpuShmTop 验证视角概览

本文从外部接口说明 `RpuShmTop` 做什么，以及 ut_shm 采用哪些参数和术语。地址公式
放在[地址模型](address-model.md)，各端口的逐周期规则分别由
[creq/ack 接口](creq-ack-interface.md)和 [MEM/VLM 接口](mem-vlm-interface.md)定义；上游
请求之间的读写依赖由 [creq 读写顺序契约](creq-ordering-contract.md)定义。

## 1. 模块职责

`RpuShmTop` 接收一条包含 16 个线程访存信息的 creq，将指令地址先转换为逻辑
`<bank_id, warp_id, laddr>`，再映射为物理 `<bank_id, gid, BADDR>`，预约未来的 MEM
访问时隙，随后发出 BANK 读写请求。读请求返回的数据还会写回 `creq_vaddr` 指定的
gid 内 BADDR。若 creq 使能完成应答，模块通过
`vack` 或 `mack` 返回原请求 ID。

```mermaid
flowchart LR
    A["creq 指令"] --> B["逐 thread/element 计算 MADDR"]
    B --> C["映射为 BANK 与 BADDR"]
    C --> D["VLM reservation"]
    D --> E["MEM 读写请求"]
    E --> F["读数据返回或写完成"]
    F --> G["可选 ack"]
```

从接口契约看，物理存储位于模块外部。`RpuShmTop` 负责调度和转换，不规定 SRAM
内部如何实现；MEM 读返回延迟、写 byte lane 和 reservation 合法性仍属于它必须
遵守的外部协议。

## 2. 接口分组

所有方向均以 `RpuShmTop` 为参考。

|接口组|方向|内容|
|---|---|---|
|时钟与复位|输入|`clk`、低有效 `rst_n`|
|creq|输入为主|`creq_vld`、thread mask 和指令 payload；DUT 用 `creq_rls` 归还 credit|
|ack|输出|`vack_done/vack_id`、`mack_done/mack_id`|
|MEM|读写|DUT 输出每个逻辑 bank port 的读写请求，外部存储返回 `mem_rdata`；端口不携带 gid|
|VLM reservation|读写|DUT 输出包含 gid 的 reservation，外部调度模块输入 read/write busy 表|

creq 没有 ready 握手。请求由 credit 控制，每个 `creq_vld==1` 的采样沿形成一笔新
请求。MEM 也没有 ready；每个有效的 `mem_*vld[bank]` 在当拍被下游接受。

## 3. 地址术语

|术语|含义|
|---|---|
|MADDR|由 `creq_base` 和 `creq_offs` 计算出的统一字节地址，宽度为 `MADDR_W`|
|logical bank|MEM/VLM packed array 的 `bank_id` 下标；当前有 16 个，每个对应两个物理 BANK|
|warp ID|绝对 WARP 编号 0～7；逻辑地址模型保留完整编号|
|laddr|单个 WARP 内的 byte 地址，合法范围为 `0 .. WARP_STEP-1`|
|gid|物理 BANK 组选择；0 对应 warp 0～3，1 对应 warp 4～7|
|physical bank|由 `<bank_id, gid>` 唯一标识的存储实例，当前共有 32 个|
|BADDR|一个 gid 内的 byte 地址，宽度为 `BADDR_W`|
|sub bank|物理 BANK 内的预约资源，当前由 BADDR 的 `[6:5]` 选择|
|MEM beat|一次 MEM 端口事务覆盖的 256 bit，即 32 Byte|

MADDR 到逻辑地址的转换受 `creq_space`、`creq_wpid`、`creq_wpnum` 和
`creq_inv_size` 控制。逻辑地址再通过统一规则转换为 gid 和 BADDR。`creq_vaddr` 的
宽度为 `BADDR_W`，已经携带当前 gid 内的 WARP 基址，用于 M2V 读数据写回。
SPACE_BLK 的 MADDR 是当前 `creq_wpid` 所属 aligned WARP group 内的相对编码；
`creq_wpid/creq_wpnum` 决定 group base，MADDR 中的 `warp_offs` 决定 group 内 WARP。

## 4. 当前参数

ut_shm 从 `shm_util_package` 取值，并在 `shm_tb_top` 实例化 DUT 时显式传入。下表是
当前配置，不是对所有参数组合的兼容性承诺。

|参数|当前值|用途|
|---|---:|---|
|`WARP_N`|8|可编码的 WARP 数量|
|`THD_N`|16|一条 creq 的线程数|
|`BANK_N`|16|逻辑 bank/MEM 端口数量|
|`GID_N`|2|每个逻辑 bank 对应的物理 BANK 数量；当前由接口的一位 gid 编码|
|`WARP_PER_GID`|4|每个物理 BANK 承载的 WARP 数量|
|`WARP_STEP`|12 KiB|同一 gid 内相邻 WARP 地址区域的步长|
|`OTF_N`|8|creq 初始 credit 数|
|`PRIO_W`|4|线程优先级宽度；当前 RTL 端口固定写成 4 bit|
|`FFD_CYC`|1|MEM 读可见的前向写窗口；当前值表示读可见同周期写|
|`RPORT_DLY`|5|MEM 读请求到读数据返回的固定周期数|
|`VTAB_D`|13|reservation busy 窗口深度，表达式为 `6+RPORT_DLY-FFD_CYC+1+1+1`|
|`ID_W`|8|creq 和 ack ID 宽度|
|`MADDR_W`|21|统一地址宽度|
|`BADDR_W`|16|gid 内地址以及 `creq_vaddr` 的宽度，等于 `MADDR_W-$clog2(BANK_N)-1`|
|`VEC_W`|256 bit|每个 thread 的 `creq_offs` 和 `creq_vdat` 位宽|
|`VEC_BYTE_N`|32 Byte|一条线程向量包含的 byte 数和语义 element-mask 位数|
|`VLM_DATA_BIT_W`|256 bit|一次 VLM/MEM beat 的数据位宽|
|`VLM_DATA_BYTE_W`|32 Byte|一次 VLM/MEM beat 包含的 byte 数|
|`VLM_SUB_BANK_N`|4|每个 BANK 的 reservation sub-bank 数量|
|`WRITE_PORT_N`|2|每个 logical bank 的 write reservation port 数量|

`GID_N` 和 `WARP_PER_GID` 是当前接口/验证模型使用的派生常量，不要求作为
`RpuShmTop` 独立 parameter 暴露；RTL top 通过一位 `vlm_*gid` 和固定的四-WARP 分组
表达同一契约。

本轮接口缩减后，`creq_offs[thread]` 和 `creq_vdat[thread]` 均为 256 bit，验证环境按
`VEC_BYTE_N=32` 生成和解释 `creq_vmsk[thread][31:0]`。RTL top、interface、transaction、
driver、monitor 和 reference 使用同一组宽度。

当前配置满足 `THD_N == BANK_N`。reference 的 SPACE_LOC 映射依赖这一关系，每个
线程固定落到同编号 BANK。若要支持两者不相等，必须先重新定义映射契约。

当前物理存储 key 为 `<bank_id, gid, BADDR>`。`BANK_N` 不是物理存储实例总数；验证
环境不得只用 `<bank_id, BADDR>` 合并低、高 gid 的数据。合法 creq 还必须保证逻辑
`laddr` 不进入每个 WARP 的 12～16 KiB 编码空洞；完整规则见[地址模型](address-model.md)。

## 5. 三条外部数据路径

### 5.1 V2M 写路径

`creq_rw == SHM_V2M` 时，creq 携带写数据、mask 和地址信息。DUT 将有效 byte 映射
到 BANK，先发出写 reservation，再在预约到期时通过 `mem_wvld`、`mem_waddr`、
`mem_wstrb` 和 `mem_wdata` 写入外部存储。若请求使能 ack，完成事件走 `mack`。

普通 V2M 只有从 MADDR 产生的 m-write。下游 SRAM 支持任意 byte address 开始的
32-Byte write beat，因此最终 VLM/MEM write 地址不要求 32 Byte 对齐；DUT 必须用
完整 beat 地址、byte strobe 和 write data 正确表达所有有效 byte。

VTRANS 是受限的特殊 V2M：16 个线程各提供 16 个元素，DUT 先把这个 16×16 数据
矩阵转置，再沿用普通 V2M 的地址计算和写路径。其他地址、offset 或其他控制字段都不改变。

### 5.2 M2V 读路径

`creq_rw == SHM_M2V` 时，DUT 从映射后的 BANK 地址发起 MEM 读，等待固定延迟的
`mem_rdata`，再把数据写回 `creq_vaddr` 指定的 gid 内 BADDR。若请求使能 ack，完成
事件走 `vack`。

M2V 包含两类访问：从 MADDR 产生的 m-read，以及从 `creq_vaddr` 产生的 v-write。
`creq_vaddr` 已经包含 `(creq_wpid % 4) * WARP_STEP`，DUT 不得再次增加 WARP 基址；
write gid 为 `creq_wpid/4`。合法激励必须保证全部有效 m-read byte 与全部有效 v-write
byte 在 `<bank_id, gid, BADDR>` 上不重叠。两类 32-Byte beat 都允许使用非对齐地址；
接口中不存在 v-read。

### 5.3 Reservation 路径

MEM 请求发出前，DUT 通过 VLM reservation 端口报告方向、bank_id、gid、BADDR 和
到期 delay。外部 busy 表按方向、未来周期、gid 和 sub bank 表示已占用资源。当前
契约要求 `1 <= dly < VTAB_D`，不支持同周期 `dly==0` 预约。

MEM 端口不携带 gid。到期 MEM request 的 gid 由同一 direction、bank_id 和 due cycle
下唯一的 reservation record 确定；因此同一逻辑 bank、同一方向、同一到期周期最多
只能存在一笔 DUT reservation，即使两笔请求的 gid 或 sub bank 不同。

## 6. 复位边界

接口在 `clk` 上升沿采样。`rst_n==0` 时，DUT 不得产生新的 creq 完成、MEM 请求或
VLM reservation；相应 valid/req/done 应为 0。payload 在 valid、req 或 done 为 0
时是 don't-care。

测试环境从第一个采样到 `rst_n==1` 的上升沿开始收集事务。仿真运行中再次复位时，
DUT 必须取消所有 outstanding creq、尚未到期 reservation 和 MEM read pipeline
事务，清空相关状态，并按初始复位后的状态重新启动。

## 7. 协议边界

creq release 和 ack 都没有规定最大延迟；测试环境可以配置超时以发现疑似挂死，
但该超时不是 DUT 协议的一部分。MEM 重叠读写返回值由 `FFD_CYC` 定义：读请求在
`T0` 被接受时，可见截止到 `T0+FFD_CYC-1` 接受的写；详细逐周期规则见
[MEM/VLM 接口](mem-vlm-interface.md)。

对上游而言，RTL 只保证同一 thread 的 M-read/M-write、M-write/M-write 和
V-write/V-write 满足 creq 接收顺序的架构结果。V-write 与 M-read/M-write，以及不同
thread 之间会影响结果的物理 byte overlap，必须由上游避免或等待前一笔 ack 后串行发布；
完整矩阵见 [creq 读写顺序契约](creq-ordering-contract.md)。
