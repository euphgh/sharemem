# RpuShmTop 验证视角概览

本文从外部接口说明 `RpuShmTop` 做什么，以及 ut_shm 采用哪些参数和术语。地址公式
放在[地址模型](address-model.md)，各端口的逐周期规则分别由
[creq/ack 接口](creq-ack-interface.md)和 [MEM/VLM 接口](mem-vlm-interface.md)定义。

## 1. 模块职责

`RpuShmTop` 接收一条包含 16 个线程访存信息的 creq，将指令地址转换为物理
`<BANK, BADDR>`，预约未来的 MEM 访问时隙，随后发出 BANK 读写请求。读请求返回的
数据还会写回 `creq_vaddr` 指定的线程本地地址。若 creq 使能完成应答，模块通过
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
|creq|输入为主|`creq_vld` 和指令 payload；DUT 用 `creq_rls` 归还 credit|
|ack|输出|`vack_done/vack_id`、`mack_done/mack_id`|
|MEM|读写|DUT 输出每 BANK 的读写请求，外部存储返回 `mem_rdata`|
|VLM reservation|读写|DUT 输出 reservation，外部调度模块输入 read/write busy 表|

creq 没有 ready 握手。请求由 credit 控制，每个 `creq_vld==1` 的采样沿形成一笔新
请求。MEM 也没有 ready；每个有效的 `mem_*vld[bank]` 在当拍被下游接受。

## 3. 地址术语

|术语|含义|
|---|---|
|VADDR|线程本地写回地址，宽度为 `VADDR_W`|
|MADDR|由 `creq_base` 和 `creq_offs` 计算出的统一字节地址，宽度为 `MADDR_W`|
|BANK|物理存储实例，端口数组下标就是 `bank_id`|
|BADDR|BANK 内字节地址，宽度为 `BADDR_W`|
|sub bank|BANK 内的预约资源，当前由 BADDR 的 `[6:5]` 选择|
|MEM beat|一次 MEM 端口事务覆盖的 256 bit，即 32 Byte|

MADDR 到 `<BANK, BADDR>` 的转换受 `creq_space`、`creq_wpid`、`creq_wpnum` 和
`creq_inv_size` 控制。VADDR 不参与普通指令地址的映射，它用于 M2V 读数据的写回。

## 4. 当前参数

ut_shm 从 `shm_util_package` 取值，并在 `shm_tb_top` 实例化 DUT 时显式传入。下表是
当前配置，不是对所有参数组合的兼容性承诺。

|参数|当前值|用途|
|---|---:|---|
|`WARP_N`|8|可编码的 WARP 数量|
|`THD_N`|16|一条 creq 的线程数|
|`BANK_N`|16|物理 BANK 数量|
|`WARP_STEP`|12 KiB|同一 BANK 内相邻 WARP 地址区域的步长|
|`OTF_N`|4|creq 初始 credit 数|
|`PRIO_W`|4|线程优先级宽度；当前 RTL 端口固定写成 4 bit|
|`FFD_CYC`|1|DUT 内部 feed-forward 周期参数|
|`RPORT_DLY`|4|MEM 读请求到读数据返回的固定周期数|
|`VTAB_D`|12|reservation busy 窗口深度，表达式为 `6+RPORT_DLY-FFD_CYC+1+1+1`|
|`ID_W`|8|creq 和 ack ID 宽度|
|`VADDR_W`|14|线程本地地址编码宽度|
|`MADDR_W`|21|统一地址宽度|
|`BADDR_W`|17|BANK 内地址宽度，等于 `MADDR_W-$clog2(BANK_N)`|

当前配置满足 `THD_N == BANK_N`。reference 的 SPACE_LOC 映射依赖这一关系，每个
线程固定落到同编号 BANK。若要支持两者不相等，必须先重新定义映射契约。

`WARP_STEP` 是 12 KiB，而 `VADDR_W` 可以编码 16 KiB。合法 creq 必须保证最终 MADDR 不进入12～16 KiB 的编码空洞；完整规则见[地址模型](address-model.md)。

## 5. 三条外部数据路径

### 5.1 V2M 写路径

`creq_rw == SHM_V2M` 时，creq 携带写数据、mask 和地址信息。DUT 将有效 byte 映射
到 BANK，先发出写 reservation，再在预约到期时通过 `mem_wvld`、`mem_waddr`、
`mem_wstrb` 和 `mem_wdata` 写入外部存储。若请求使能 ack，完成事件走 `mack`。

VTRANS 是受限的特殊 V2M：16 个线程各提供 16 个元素，DUT 先把这个 16×16 数据
矩阵转置，再沿用普通 V2M 的地址计算和写路径。其他地址、offset或其他控制字段都不改变。

### 5.2 M2V 读路径

`creq_rw == SHM_M2V` 时，DUT 从映射后的 BANK 地址发起 MEM 读，等待固定延迟的
`mem_rdata`，再把数据写回 `creq_vaddr` 对应的线程本地区域。若请求使能 ack，完成
事件走 `vack`。

### 5.3 Reservation 路径

MEM 请求发出前，DUT 通过 VLM reservation 端口报告方向、BANK、BADDR 和到期
delay。外部 busy 表按方向、未来周期和 sub bank 表示已占用资源。当前契约要求
`1 <= dly < VTAB_D`，不支持同周期 `dly==0` 预约。

## 6. 复位边界

接口在 `clk` 上升沿采样。`rst_n==0` 时，DUT 不得产生新的 creq 完成、MEM 请求或
VLM reservation；相应 valid/req/done 应为 0。payload 在 valid、req 或 done 为 0
时是 don't-care。

测试环境从第一个采样到 `rst_n==1` 的上升沿开始收集事务。仿真运行中再次复位时，
DUT 必须取消所有 outstanding creq、尚未到期 reservation 和 MEM read pipeline
事务，清空相关状态，并按初始复位后的状态重新启动。

## 7. 协议边界

creq release 和 ack 都没有规定最大延迟；测试环境可以配置超时以发现疑似挂死，
但该超时不是 DUT 协议的一部分。同一周期对同一 MEM BANK 的重叠地址读写返回旧值
还是新值也未定义，测试不得依赖其中一种结果。
