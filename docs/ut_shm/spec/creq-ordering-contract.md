# SHM creq 读写顺序契约

本文面向产生 creq 的上游调度模块，定义哪些访问顺序由 `RpuShmTop` 保证，哪些地址依赖
必须由请求源避免或串行化。本文只规定架构可见结果，不规定 DUT 内部 reservation、MEM request 的实际发出顺序或完成延迟。

## 1. 判定基准

### 1.1 creq 顺序

当 `creq_vld==1` 时，该上升沿接收一笔新 creq。若请求 `A` 的接收沿早于请求 `B`，记为：

```text
A before B
```

本文中的先后顺序只以 creq 接收沿为准，不以 priority、reservation、MEM request、
`creq_rls` 或 ack 的出现顺序为准。`creq_prio` 可以改变内部调度次序，但不能改变本文明确
保证的架构结果。

### 1.2 三类访问

一笔 creq 按 active thread、length、element mask 和 dtype 展开后，形成以下物理 byte 集合：

|集合|产生它的请求|含义|
|---|---|---|
|M-read|普通 M2V|从 MADDR 映射出的地址读取数据|
|M-write|普通 V2M、VTRANS|把输入数据写入 MADDR 映射出的地址|
|V-write|普通 M2V|把读取结果写回 `creq_vaddr` 指定的地址|

每个 byte 的物理地址 key 为：

```text
<bank_id, gid, BADDR>
```

重叠必须按 byte 判定。DTYP16/DTYP32 元素要展开为 2/4 个 byte；两个元素起始地址不同，
仍可能部分重叠。相同 BADDR 但 bank 或 gid 不同不是同一个物理 byte。inactive thread、
mask 为 0 或超出有效 length 的元素不产生访问，也不形成顺序依赖。

## 2. RTL 保证的顺序

以下保证仅适用于两个访问属于相同 thread，并且 `A before B`。允许相关物理 byte 重叠，
RTL 必须使架构结果等价于表中的顺序：

|A 中的访问|B 中的访问|RTL 保证|架构可见结果|
|---|---|---|---|
|M-read|M-write|M-read 在 M-write 前生效|A 读到旧值，M 最终保存 B 的新值|
|M-write|M-read|M-write 在 M-read 前生效|B 读到 A 写入的新值|
|M-write|M-write|两次写按 creq 顺序生效|M 最终保存 B 的写入值|
|V-write|V-write|两次写回按 creq 顺序生效|V 目的地址最终保存 B 的写回值|

这些是结果顺序，不要求 RTL 以固定周期或固定 MEM beat 次序执行。上游不能依据观察到的
内部调度次序推导额外保证。

同一笔 M2V 内，RTL 只保证一个 thread 的一个 element 先完成自己的 M-read，再进行该
element 的 V-write；RTL 不保证所有 element 的 M-read 全部结束后才开始任一 V-write。
因此这个局部保证不能替代第 3 节的地址不重叠要求。

## 3. 上游必须保证的关系

### 3.1 V-write 与 M-access 不得并发重叠

RTL 不保证 V-write 与 M-read 或 M-write 的相对顺序，即使它们属于相同 thread。对任意
两笔可能同时在途的请求 `A` 和 `B`，上游必须保证：

```text
A.V-write intersect (B.M-read union B.M-write) == empty
(A.M-read union A.M-write) intersect B.V-write == empty
```

这个约束是双向的，至少包括以下四种情况：

1. 先发请求的 V-write 与后发请求的 M-read 不重叠；
2. 先发请求的 M-read 与后发请求的 V-write 不重叠；
3. 先发请求的 V-write 与后发请求的 M-write 不重叠；
4. 先发请求的 M-write 与后发请求的 V-write 不重叠。

两次 V-write 可以重叠，但只有同一 thread 的两次 V-write 才有第 2 节规定的先后结果。
M-read/M-write 和 M-write/M-write 也可以重叠，但同样只有同一 thread 才能依赖第 2 节的
顺序保证。

### 3.2 单笔 M2V 的输入限制

同一笔 M2V 中，所有有效 M-read byte 与所有有效 V-write byte 也必须不重叠：

```text
transaction.M-read intersect transaction.V-write == empty
```

该规则必须在整笔请求范围内检查，而不是只比较同一个 thread 或同一个 element。违反该
条件时，DUT 行为未定义。

### 3.3 单笔 V2M/VTRANS 不得重复写同一 byte

一笔 V2M 或 VTRANS 中的所有有效 M-write byte 必须互不重叠。这个检查覆盖所有 active
thread 和 element；不能依赖 RTL 决定同一笔 creq 内哪个 element 的写入最后生效。

### 3.4 不同 thread 之间不得假设顺序

第 2 节的顺序保证按 thread 独立成立。对于一笔包含多个 active thread 的 creq，也要分别
判断每个 thread 产生的访问。来自不同 thread 的两个访问即使落到同一个物理 byte，上游也
不得假设它们按 creq 顺序生效。

若不同 thread 可能访问同一物理 byte，且结果依赖先后顺序，上游必须避免它们同时在途，
或重新安排地址使其不重叠。纯 M-read/M-read 不修改状态，本身不需要为两个 read 建立写入
顺序；一旦还存在相关 write，仍按上述规则处理。

## 4. 无法证明不重叠时的安全调度

如果上游不能证明两笔请求满足第 3 节的 byte-disjoint 条件，必须把它们串行化：只有确认
前一笔请求完成后，才能发布后一笔冲突请求。

从 creq 接口可见，安全的完成事件是请求 ID 对应的 ack：

|前一笔请求|完成事件|
|---|---|
|V2M，包括 VTRANS|`mack_done && mack_id == creq_id`|
|M2V|`vack_done && vack_id == creq_id`|

因此需要用 ack 建立依赖的请求必须设置 `creq_ack_en==1`，并在收到对应 ack 前保持 ID
唯一。`creq_rls` 只归还接收 credit，不表示数据访问已经完成，不能作为解除地址依赖或发布
后一笔冲突请求的条件。

若前一笔请求关闭了 ack，creq/ack 接口本身不提供可供上游判断完成的事件。此时上游必须
使用系统定义的其他完成或 barrier 机制；如果系统没有这类机制，就必须从源头保证相关请求
地址不重叠，不能仅等待固定周期或等待 `creq_rls`。

## 5. 调度示例

### 5.1 RTL 保证：读后写

同一 thread 先发 M2V 从地址 `X` 读取，再发 V2M 向 `X` 写入 `NEW`。只要 M2V 的
V-write 目的地址不与两笔请求的 M-access 重叠，允许两笔同时在途。RTL 必须使 M2V 读到
`X` 的旧值，并使 `X` 最终为 `NEW`。

### 5.2 RTL 保证：写后读

同一 thread 先发 V2M 向 `X` 写入 `NEW`，再发 M2V 从 `X` 读取。RTL 必须使 M2V 读到
`NEW`。M2V 的 V-write 目的地址仍必须与两笔请求的 M-access 不重叠。

### 5.3 上游保证：V-write 与 M-read

请求 A 的 M2V 要把数据写回物理 byte `Y`，请求 B 要从 `Y` 做 M-read。RTL 不保证这两次
访问的顺序。上游必须改用不重叠的写回地址，或者为 A 打开 ack 并等到 A 的 `vack` 后再
发布 B。

### 5.4 上游保证：跨 thread 重叠写

thread 0 和 thread 1 产生的两个 M-write 映射到同一个物理 byte。即使两笔 creq 有明确的
接收先后，上游也不能依赖后发请求覆盖先发请求；必须修改地址或等待前一笔真正完成后再
发布后一笔。