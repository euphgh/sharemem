# RpuShmTop creq/ack 接口规范

本文定义 creq 的接收、credit/release、字段编码以及 vack/mack 完成应答。地址生成和
三种 address space 的映射公式见[地址模型](address-model.md)；MEM 与 reservation
行为见 [MEM/VLM 接口](mem-vlm-interface.md)。所有信号均在 `clk` 上升沿采样，端口
方向以 `RpuShmTop` 为参考。

## 1. 端口

|端口|方向|含义|
|---|---|---|
|`creq_vld`|输入|本周期 creq payload 有效|
|`creq_rls`|输出|归还一个 creq credit|
|`creq_id`|输入|请求 ID，宽度为 `ID_W`|
|`creq_wpid`|输入|发起请求的 WARP ID|
|`creq_wpnum`|输入|SPACE_BLK 的 WARP 组大小，合法值为 1、2、4|
|`creq_prio[thread]`|输入|每个线程的调度优先级|
|`creq_len[thread]`|输入|每个线程的有效数据 byte 数|
|`creq_typ`|输入|方向、数据类型、地址类型和控制位的 20-bit packed 字段|
|`creq_vaddr`|输入|M2V 写回的线程本地基址|
|`creq_vmsk[thread]`|输入|每个线程的 element mask|
|`creq_base`|输入|48-bit byte address 基址，普通 MADDR 使用低 `MADDR_W` bit|
|`creq_offs[thread]`|输入|每个线程的 packed offset 向量|
|`creq_vdat[thread]`|输入|V2M 写数据|
|`vack_done/vack_id`|输出|M2V 完成应答及请求 ID|
|`mack_done/mack_id`|输出|V2M 完成应答及请求 ID|

## 2. 接收与 credit

creq 没有 ready 信号。复位释放后可用 credit 数恢复为 `OTF_N`。每个满足
`creq_vld==1` 的采样沿接收一笔新请求并消耗一个 credit；payload 的所有字段在该
采样沿作为一个整体被接收。

请求源只能在持有 credit 时拉高 `creq_vld`。`creq_vld` 连续多个周期为 1 表示每个
周期各接收一笔请求，不表示同一请求等待握手。

每个 `creq_rls==1` 的采样沿归还一个 credit。`creq_rls` 只表示 DUT 不再占用该
creq 的接收资源，与请求是否已经产生 `vack/mack` 无关；release 可以早于或晚于
ack。协议不规定 credit 的最晚归还周期。

复位会取消所有在途请求并把 credit 状态恢复到初始值。复位前尚未出现的 release
或 ack 不得在复位释放后补发。

## 3. `creq_typ` 编码

`creq_typ[19:0]` 按下表解释：

|bit|字段|含义|
|---:|---|---|
|`[19:16]`|`creq_info`|`4'h0` 为普通请求，`4'hf` 为 VTRANS；其他值保留|
|`[15:14]`|`creq_space`|SPACE_LOC、SPACE_WRP 或 SPACE_BLK|
|`[13:10]`|`creq_inv_size`|interleave size 的 log2 编码，`G=2^(creq_inv_size+2)` Byte|
|`[9]`|`creq_ack_en`|是否要求完成应答|
|`[8:7]`|`creq_itype`|offset/元素地址生成方式|
|`[6]`|`creq_atype_g`|offset 是否按数据宽度缩放|
|`[5]`|`creq_atype_s`|offset 做符号扩展或零扩展|
|`[4:3]`|`creq_atype_w`|raw offset 元素宽度|
|`[2:1]`|`creq_dtype`|数据元素宽度|
|`[0]`|`creq_rw`|V2M 写或 M2V 读|

当前编码如下：

|字段|编码|
|---|---|
|`creq_rw`|`SHM_V2M=0`，`SHM_M2V=1`|
|`creq_dtype`|`DTYP_32=0`，`DTYP_16=1`，`DTYP_8=2`|
|`creq_atype_w`|`ATYP_32=0`，`ATYP_16=1`，`ATYP_8=2`|
|`creq_atype_s`|`ATYP_U=0`，`ATYP_S=1`|
|`creq_atype_g`|`GAUTO_1B=0`，`GAUTO_DW=1`|
|`creq_itype`|`LDST_S=0`，`LDST_V=1`，`LDSTE_S=2`，`LDSTE_V=3`|
|`creq_space`|`SPACE_LOC=0`，`SPACE_WRP=1`，`SPACE_BLK=2`|

未列出的 enum 编码和保留的 `creq_info` 值不得由合法 creq 产生。

## 4. Payload 语义与合法性

`creq_len[t]` 的单位是 Byte，不是 element。元素宽度为 `D` Byte 时，线程 `t` 的
有效元素数为 `creq_len[t]/D`；合法请求必须使 byte length 与数据类型对齐。
`creq_vmsk[t][k]` 决定元素 `k` 是否形成访问。

`creq_base`、`creq_offs`、data type 和 address type 共同生成每个有效元素的 MADDR。
请求源必须对最终 MADDR 做合法性检查，包括 SPACE_LOC 的 12 KiB 上限以及
SPACE_WRP/SPACE_BLK 在 8 KiB、16 KiB interleave size 下的地址空洞。不能只检查
`creq_base`。完整公式见[地址模型](address-model.md)。

`creq_wpid` 的合法范围是 `0 .. WARP_N-1`。`creq_wpnum` 当前只能取 1、2、4；在
SPACE_BLK 中，最终 `warp_index` 必须与 `creq_wpid` 位于同一个 `creq_wpnum` 对齐
分组中。

`creq_prio` 会影响 DUT 生成 MEM 请求的先后顺序，但不改变任何请求的地址、数据或
最终结果。验证模型不应根据 priority 改变期望值。

对于要求 ack 的 outstanding 请求，环境必须保证 `creq_id` 足以区分尚未完成的
请求，避免在收到对应 ack 前复用同一个 ID。

## 5. 普通 V2M 与 M2V

`creq_rw==SHM_V2M` 时，DUT 按地址模型把 `creq_vdat` 中由 length 和 mask 选中的
byte 写入 MEM。`creq_rw==SHM_M2V` 时，DUT 从映射后的 MEM 地址读取数据，再写回
`creq_vaddr` 指定的线程本地区域。

普通请求使用 `creq_info==4'h0`。V2M 和 M2V 共享 MADDR 生成与 BANK 映射规则，
区别在数据流向以及完成时使用的 ack 通道。

## 6. VTRANS

VTRANS 由 `creq_info==4'hf` 识别，是一种受限的 V2M。合法 VTRANS 必须满足：

```text
creq_rw    == SHM_V2M
creq_space == SPACE_LOC
creq_dtype inside {DTYP_8, DTYP_16}
creq_itype inside {LDST_S, LDST_V}
creq_wpid  inside {[0:WARP_N-1]}
```

16 个线程均参与操作，每个线程恰好包含 16 个有效元素，所有 element mask 均为 1：

```text
DTYP_8 : creq_len[t] == 16 Byte
DTYP_16: creq_len[t] == 32 Byte
creq_vmsk[t] == '1
```

输入数据形成 16×16 的 element 矩阵。DUT 只转置数据：

```text
transposed_data[dst_thread][dst_element]
    = original_data[dst_element][dst_thread]
```

若元素包含多个 byte，各 byte lane 保持在元素内部的原顺序。转置不改变
`creq_base`、`creq_offs`、address type、space、length、mask 或其他控制字段。
转置完成后，以目标 `thread/element` 的普通 V2M 地址计算结果执行写入，因此 VTRANS
支持与普通 V2M 相同的 toff 和 MADDR 生成规则。

## 7. ack

当 `creq_ack_en==0` 时，该请求不产生完成 ack。当 `creq_ack_en==1` 时，DUT 在请求
完成后必须产生且只产生一次对应 ack：

|请求方向|完成通道|
|---|---|
|`SHM_V2M`，包括 VTRANS|`mack_done`、`mack_id`|
|`SHM_M2V`|`vack_done`、`vack_id`|

`*_done==1` 的采样沿表示一笔完成事件，`*_id` 必须等于原 `creq_id`。done 为 0 时
对应 ID 是 don't-care。ack 与 `creq_rls` 相互独立，协议不规定 ack 的最大延迟；
验证环境中的 timeout 只用于发现疑似挂死，不构成 DUT 时序要求。

## 8. 复位与检查规则

复位期间，请求源必须保持 `creq_vld==0`，DUT 必须保持
`creq_rls==0`、`vack_done==0` 和 `mack_done==0`。复位会取消所有 outstanding creq，
复位释放后从 `OTF_N` 个 credit 的初始状态重新开始。

|ID|规则|
|---|---|
|`CREQ-001`|请求源只能在持有 credit 时拉高 `creq_vld`；每个有效采样沿消耗一个 credit。|
|`CREQ-002`|`creq_vld==1` 时，所有参与解释的控制字段、地址、length、mask、offset 和有效数据禁止包含 X/Z。|
|`CREQ-003`|每个有效元素生成的 MADDR 必须满足对应 address space 的范围、空洞和 WARP 分组约束。|
|`CREQ-004`|`creq_len` 必须以 Byte 表示，并与 `creq_dtype` 对齐。|
|`CREQ-005`|`creq_rls` 每个有效周期只归还一个 credit，并且不得使可用 credit 超过 `OTF_N`。|
|`CREQ-006`|VTRANS 必须满足第 6 节的方向、space、dtype、itype、length 和 mask 限制。|
|`ACK-001`|ack 关闭的请求不得产生完成 ack；ack 打开的请求必须产生且只产生一次正确方向、正确 ID 的 ack。|
|`ACK-002`|`vack_done`、`mack_done` 和 done 有效时的 ID 禁止包含 X/Z。|
|`ACK-003`|复位前尚未完成的请求被取消，复位后不得补发对应 release 或 ack。|

当 valid 或 done 为 0 时，对应 payload 为 don't-care，验证器不得检查其数值或稳定性。
