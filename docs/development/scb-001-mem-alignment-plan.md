# SCB-001 MEM beat 对齐检查开发计划

本文记录 `SCB-001` 的候选实现、已知风险和后续确认项。由于近期 RTL 还会进行一次
重构，本问题暂缓实现；本文不改变当前 DUT 对齐规则，也不表示现有 scoreboard 已经
具备来源相关的 MEM beat 对齐检查。

DUT contract 仍以 [地址模型](../ut_shm/spec/address-model.md#8-访问来源与-mem-beat-对齐)
和 [MEM/VLM 接口](../ut_shm/spec/mem-vlm-interface.md)为准：所有 MEM read 必须 32 Byte
对齐，普通 V2M m-write 必须 32 Byte 对齐，M2V v-write 和 VTRANS write 允许非对齐。

## 1. 职责边界

VLM reservation transaction 不携带可靠的原始 creq 来源，write port 编号也不是访问
类型编码。Reservation agent 因而只负责：

- reservation delay、busy 和到期冲突；
- reservation 与实际 MEM request 的 direction、BANK、due cycle 和完整地址匹配；
- 非对齐地址的低位必须原样保留，禁止按 32 Byte 边界截断后比较。

所有 read/write alignment policy 最终应由能观察 MEM transaction 的 checker 承担。
Write alignment 还需要原始 `shm_wtrans_item` 上下文，因此候选检查位置是 scoreboard。

## 2. 当前候选算法

`vlm_memory_sequence_item` 是同一周期所有 BANK 的快照，不保证整个对象来自同一笔
shmins transaction。来源归属和 alignment 判断必须以每个 active BANK 的 MEM beat
为粒度。

Write 路径仅在现有 `value_full_match` 分支中执行来源检查。也就是说，实际 write 的
地址和数据必须先完整通过 `wmap_final/wmap_expired` 检查，之后才允许用该 write 推导
可能的原始 shmins transaction。数据检查失败时不再追加来源相关 alignment 错误。

对每个 BANK `b`，临时采用以下严格策略：

```text
bank_requires_alignment[b] =
    OR over every eligible shmins transaction tr {
        tr is normal V2M
        AND tr.wmap and actual vlm_wmap contain at least one equal <BANK, address, data> byte in b
    }
```

其中 normal V2M 定义为：

```text
tr.creq_rw == SHM_V2M && tr.creq_info != 4'hf
```

如果 `bank_requires_alignment[b]` 为 1，则要求该 BANK 的实际 beat base 满足
`vlm_addr[b][4:0]==0`。同一 BANK 即使归属于多个 shmins transaction，也只汇总一次
alignment 要求并最多报告一次错误。只要任一可能来源是普通 V2M，该 BANK 就按必须
对齐处理；这是当前有意选择的最严格策略。

Read 不需要关联 shmins transaction。Scoreboard 收到每个 active read BANK 后直接检查
`vlm_addr[b][4:0]==0`。具体采用 memory monitor analysis path 还是 read service path，需在
RTL 重构后的环境数据流稳定后确定，禁止在两条路径重复报告同一请求。

## 3. `get_intersect()` 的值语义

`wmap_util::get_intersect(lhs, rhs)` 只按 associative-array key 求交集，结果 value 来自
`lhs`，不会自动比较双方 value。因此来源判断必须显式比较期望值和实际值。

当前 scoreboard 已把调用调整为：

```systemverilog
trans_pair_matched = wmap_util::get_intersect(vlm_wmap, curr_trans.wmap);
```

此时交集 value 来自实际 `vlm_wmap`，后续仍必须使用：

```systemverilog
curr_trans.wmap[bank][addr] == trans_pair_matched[bank][addr]
```

只有地址和数据同时相等的 byte 才能建立来源候选。不能把“地址 key 相交”直接解释为
transaction 归属。

## 4. 实现前必须解决的问题

### 4.1 Expired 来源可能已经离开 record queue

`scan_timeout_creq()` 会在一个 reference record 的全部地址已经 matched 或 expired 后将
它从 `ref_record_q` 删除，但对应旧值仍可能保留在 `wmap_expired` 中并被后续实际 write
合法命中。若 alignment 只遍历当前 `ref_record_q`，这种 write 会通过数据检查，却无法
恢复原始来源，形成漏检。

候选实现需要为 final/expired expectation 保留与其生命周期一致的 provenance。只为
alignment 服务时，可以保存 `<BANK, address, value>` 对应的 `requires_alignment` 聚合
bit；需要详细诊断时，再保存候选 `creq_id` 集合。不能通过永久保留全部历史 record
解决，因为已经消费的古老 transaction 会继续参与归属并增加误报。

### 4.2 一个实际 byte 可能有多个候选来源

不同 creq 可能产生相同 `<BANK, address, data>`。当前严格策略对所有仍合法的候选来源
做 OR：任一候选要求对齐，就要求实际 BANK beat 对齐。这不会漏掉普通 V2M 候选，但在
普通 V2M 与 M2V/VTRANS 完全不可区分时可能误报。

该歧义不能仅靠调整遍历顺序可靠解决。RTL 重构后需要与设计确认：

- DUT 是否保证一个 BANK beat 只合并同一笔 creq 的 byte；
- 是否存在可观察的顺序、tag 或调度信息用于唯一归属；
- 在接口行为不可区分时，checker 应采用“任一候选要求对齐”还是“存在合法来源即可”语义。

在这些问题确认前，`SCB-001` 保持暂缓，不能用严格策略的潜在误报关闭问题。

### 4.3 比对状态必须分成检查和提交两阶段

当前 value loop 可能在确认整笔 write 通过前删除部分 `wmap_final/wmap_expired` 条目。
正式加入 provenance 后应先只读完成整笔 BANK 的数据检查和来源汇总，再统一消费匹配
状态。否则部分错误 transaction 可能提前改变 expectation，或者在 alignment 判断前
丢失来源信息。

`rtl_banks` 表示 DUT 实际已写入的状态，是否在数据错误时仍更新属于独立的 memory-model
语义，不应与 expectation 消费混为一体。

### 4.4 多 BANK 和重复诊断

一个 `vlm_memory_sequence_item` 的不同 active BANK 可以属于不同 shmins transaction。
实现必须先生成 `bank_has_source[BANK_N]` 和 `bank_requires_alignment[BANK_N]`，再逐 BANK
报告；不能因多个候选 transaction 对同一个非对齐 BANK 重复报错。

若数据已经完整匹配但某个 active BANK 没有任何可恢复的来源，应报告 scoreboard
provenance 内部错误，不能静默跳过 alignment。这通常表示 expired provenance 生命周期
不完整或匹配状态已经被过早消费。

## 5. 后续验证要求

RTL 重构完成并确认归属 contract 后，至少增加以下定向场景：

- 普通 V2M aligned 通过、nonaligned 报错；
- M2V v-write 和 VTRANS aligned/nonaligned 均按协议通过；
- MEM read aligned 通过、nonaligned 报错；
- 同一周期多个 BANK 分别来自不同 shmins transaction；
- 同一 BANK 的多个候选来源具有相同和不同 alignment policy；
- final、expired、record 已移除但 expired value 尚可命中的场景；
- 数据错误时只报告数据错误，不追加无法可靠归属的 alignment 错误；
- 一个 BANK 有多个要求对齐的候选时只报告一次 alignment 错误。

关闭 `SCB-001` 前，除定向 scoreboard 测试外，还需要运行包含普通 V2M、M2V 和 VTRANS
的完整环境 regression，确认 checker 没有因来源歧义产生不可接受的误报。
