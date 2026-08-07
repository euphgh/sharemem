# ut_shm Testpoints

本文把 [DUT spec](../spec/index.md) 转换为可追踪的验证目标。每个 testpoint 先定义
spec 要求的激励、观察和 coverage，再记录当前 sequence、checker 和 case 能否支撑；
当前代码行为不会反向缩小 testpoint 范围。Case 的继承和 regression 组织见
[Testcase 与 regression](testcases-and-regression.md)。

## 1. Testpoint 状态

每个 testpoint 分别记录四项实现状态：

|维度|完整|部分|缺失|
|---|---|---|---|
|激励|能稳定产生全部目标场景|只能随机命中或缺少部分字段/边界|没有合法激励入口|
|检查|能独立判定全部目标行为|只检查部分结果，或 checker 自身有已知缺口|没有检查路径|
|Coverage|所需 functional bin/cross 已实现|只实现部分 bin/cross|没有 functional coverage|
|Case|定向 case 已定义并进入目标 regression|只有宽泛 case、TC 定义或未进入 regression|没有 case|

总体状态使用：

|状态|含义|
|---|---|
|待实现|只有 spec 目标，主要验证入口尚未建立|
|部分实现|激励、检查或 case 至少一项不完整，当前结果不能代表完整目标|
|可运行未闭环|已有可信激励与检查，但 coverage 或关闭证据缺失|
|已闭环|满足 [Testpoint 关闭条件](coverage-and-closure.md#6-testpoint-关闭条件)|
|待确认|Spec 本身仍需设计确认|
|受限支持|只有满足额外合法性条件的子场景有定义，其余行为未定义|

当前没有 functional coverage，因此本文没有 testpoint 可标记为“已闭环”。表格中的
“目标 coverage”是后续实现要求，不表示已有 covergroup。

## 2. Testpoint 总览

|领域|Testpoint|当前结论|
|---|---|---|
|Creq/ack|`TP-CREQ-001`～`005`、`TP-ACK-001`|credit、tmsk、四态、priority 和完整 ack 检查均不完整|
|数据路径|`TP-DATA-001`～`004`|已有 reference/scoreboard 主路径，但受 copy、FFD、reset 和定向并发缺口影响|
|地址模型|`TP-ADDR-001`～`008`|当前矩阵只覆盖部分 ATYPE/ITYPE/space，12 KiB 空洞和非零 warp group 有已知问题|
|MEM|`TP-MEM-001`～`004`|写比对和固定延迟 read service 已接入，来源对齐、四态和 FFD_CYC 不完整|
|Reservation|`TP-RSV-001`～`006`|checker 已覆盖大部分时序/匹配规则，但 write alignment、reset 和 coverage 有缺口|
|Reset|`TP-RST-001`～`002`|初始 reset 可避开未知采样，运行中 reset 没有统一取消状态|

## 3. Creq 与 ack

|ID|Spec 与验证目标|所需激励|观察点与 checker|目标 coverage|当前 case|状态与缺口|
|---|---|---|---|---|---|---|
|`TP-CREQ-001`|[`CREQ-001`](../spec/creq-ack-interface.md#8-复位与检查规则)、`CREQ-005`：只在持有 credit 时接收请求，每笔有效 creq 消耗一个 credit，每拍 release 最多归还一个且总数不超过 `OTF_N`；release 与 ack 独立|连续发送至少 `OTF_N+1` 笔请求，覆盖 credit 用尽、release 早于/晚于 ack、连续 release 和无在途 release|观察 `creq_vld/creq_rls`、driver semaphore 和 outstanding 请求；需要独立 credit checker。当前 driver 只用 semaphore 限制自身发送，没有系统检查 DUT 过量 release，见 `SHMINS-009`|credit occupancy `0..OTF_N`、stall、release/ack 相对顺序及交叉|所有普通 case 都经过 credit driver，但公共 64～128 周期间隔不形成定向压力|激励部分、检查部分、coverage 缺失、case 仅宽泛映射；总体部分实现|
|`TP-CREQ-002`|[`CREQ-002`](../spec/creq-ack-interface.md#8-复位与检查规则)：valid 时公共字段和 active-thread payload 已知，inactive-thread payload 可为 X/Z；valid 为 0 时 payload 不检查|分别向公共字段、active thread 和 inactive thread 注入 X/Z，并覆盖 valid 0/1|shmins interface 和 monitor；monitor 应按 active mask 局部检查。当前只判断 `creq_vld`，见 `SHMINS-006`|字段类别 × active/inactive × known/XZ × valid|无负向 case|激励缺失、检查缺失、coverage 缺失、case 缺失；总体待实现|
|`TP-CREQ-003`|[`CREQ-007`](../spec/creq-ack-interface.md#8-复位与检查规则)及 thread-mask 语义：普通请求 `creq_tmsk!=0`，inactive thread 不产生地址、MEM/reservation 或写回；VTRANS 必须全 1|定向生成单 thread、多 thread、稀疏 mask、全 1、全 0 非法输入和 inactive payload X/Z|monitor 检查 X/Z/全零；reference 为 inactive thread 建立空派生数组，实际额外 MEM/VLM 输出由后级 checker 比对；见 `SHMINS-001`|tmsk population、thread index、direction、space、VTRANS 和全零非法 bin|普通 case 随机非全零 mask，VTRANS 全 1；没有 tmsk 定向 case|激励部分、检查已接入但待远端验证、coverage 缺失、case 缺失；总体部分实现|
|`TP-CREQ-004`|[`CREQ-004`](../spec/creq-ack-interface.md#8-复位与检查规则)及 mask/尾部 byte：length 以 Byte 计、与 DTYPE 对齐，只有 tmsk/vmsk/length 共同选择的 byte 形成访问|覆盖 DTYPE 8/16/32、length 0/最小/最大/非整元素非法值、稀疏 vmsk 和 element 尾部 byte|monitor transaction、reference 的 byte `wmap`、MEM strobe 和 scoreboard；reference 已支持 tmsk/length/vmsk，copy 仍见 `SHMINS-002`|DTYPE × length class × vmsk pattern × beat crossing × direction|V2M/M2V 矩阵固定 DTYPE，length/vmsk 由 seed 随机；没有边界 case|激励部分、检查部分、coverage 缺失、case 部分；总体部分实现|
|`TP-CREQ-005`|[Payload 语义](../spec/creq-ack-interface.md#4-payload-语义与合法性)：priority 只影响 MEM 调度顺序，不改变地址、数据和最终结果|相同 creq 数据使用不同 priority，覆盖多笔并发、地址重叠和调度次序变化|观察 creq priority、MEM 兑现次序和 scoreboard 最终状态；reference 不能按 priority 改期望|priority class × overlap × observed order × final result|priority 随机但无 plusarg、定向 case或 coverage；公共间隔也弱化并发|激励部分、检查部分、coverage 缺失、case 缺失；总体部分实现|
|`TP-ACK-001`|[`ACK-001`](../spec/creq-ack-interface.md#8-复位与检查规则)、`ACK-002`：ack disable 不得 ack；enable 时按方向、正确 ID exactly-once，done/有效 ID 已知；无协议最大延迟|V2M、M2V、VTRANS 分别覆盖 ack on/off、多个 outstanding ID、重复/错误方向/错误 ID/XZ 负例，以及 ack 与 release 的所有顺序|观察 `vack/mack` 与 creq outstanding 表。Monitor 只为 ack-enabled 请求等待匹配 ID，并用固定 200 周期 `UVM_ERROR` timeout；不能完整检查 unexpected、duplicate 或协议无最大延迟，见 `SHMINS-008`、`SHMINS-009`|direction × ack_en × outcome × ack/release order × latency class|普通 case 中 `creq_ack_en` 随机；无 ack 定向 case|激励部分、检查部分、coverage 缺失、case 缺失；总体部分实现|

## 4. 数据路径和架构顺序

|ID|Spec 与验证目标|所需激励|观察点与 checker|目标 coverage|当前 case|状态与缺口|
|---|---|---|---|---|---|---|
|`TP-DATA-001`|[普通 V2M](../spec/creq-ack-interface.md#5-普通-v2m-与-m2v)：所有有效输入 byte 按映射地址写入 MEM，无效 byte 不改变存储|覆盖 ITYPE、space、DTYPE、ATYPE、mask、length、跨 beat 和多 BANK 写|shmins monitor → reference byte map → memory monitor write → scoreboard final/expired 匹配|direction=V2M × ITYPE × SPACE × DTYPE × ATYPE；strobe pattern 和 BANK count|42 个普通 V2M regression case|主路径可运行，但 copy、地址约束、来源 alignment 和 tmsk 定向验证有缺口；coverage 缺失；总体部分实现|
|`TP-DATA-002`|[普通 M2V](../spec/creq-ack-interface.md#5-普通-v2m-与-m2v)：从 m-read 地址取得数据，再按 `creq_vaddr` 写回对应 thread/WARP|覆盖初始 memory、已有 V2M 写、不同 read/write bank、vaddr 对齐/非对齐、read pipeline 和所有地址模式|reference `ref_banks` 预测写回；memory driver 从 `rtl_banks` 返回 read data；memory monitor/scoreboard 检查最终 v-write|M2V × ITYPE × SPACE × source BANK × writeback BANK × vaddr alignment|42 个 M2V regression case；M2V `es+WRP/BLK` 的 12 个 TC 未入 LST|主路径存在，但 `FFD_CYC`、copy、地址约束和 tmsk 定向验证有缺口；coverage 缺失；总体部分实现|
|`TP-DATA-003`|[`CREQ-006`](../spec/creq-ack-interface.md#8-复位与检查规则)和 [VTRANS](../spec/creq-ack-interface.md#6-vtrans)：合法输入为 16×16，数据转置但地址与控制不变，使用允许非对齐的 V2M write|DTYPE 8/16 × ITYPE LDST_S/LDST_V，非零 offset、不同数据模式、全 tmsk/vmsk，并覆盖不合法方向/space/length/mask 负例|reference 的 source `[element][thread]` 与 target `[thread][element]`、reservation/MEM 完整地址、scoreboard byte 数据|DTYPE × ITYPE × source/destination index；data pattern；aligned/nonaligned write|仅 `v2m_vtrans_test`，合法组合由 seed 随机|激励部分：tmsk 已全 1，copy 仍可能丢 `creq_info`；检查部分；coverage 缺失；总体部分实现|
|`TP-DATA-004`|[架构顺序](../environment/components/shm-scoreboard.md#4-实际-write-比对)：DUT 可乱序兑现重叠 creq，但最终 memory 必须等价于 creq 顺序执行|定向构造完全重叠、部分重叠、链式覆盖和非重叠 creq，并控制 DUT 先兑现旧值或最终值|scoreboard `wmap_final/wmap_expired`、record matched/expired/unmatched 和 `check_phase` 最终收敛|overlap class × observed order × final/expired match × final convergence|公共 case 的 64～128 周期间隔不能稳定形成 outstanding/重叠；无定向 case|激励缺失、checker 已有但缺独立定向验证，coverage 缺失、case 缺失；总体部分实现|

## 5. 地址模型

|ID|Spec 与验证目标|所需激励|观察点与 checker|目标 coverage|当前 case|状态与缺口|
|---|---|---|---|---|---|---|
|`TP-ADDR-001`|[Offset 解码](../spec/address-model.md#32-offset-解码)：ATYPE_W 32/16、signed/unsigned、1B/DW granularity 与 DTYPE 共同得到 `E[t][k]`，禁止截断回绕|覆盖正/负/零/边界 raw offset，所有 width/sign/granularity/DTYPE 组合|monitor 解码字段、reference MADDR 和最终 BANK/BADDR/数据；需要独立公式级 reference 测试|ATYPE_W × sign × granularity × DTYPE × offset sign/boundary|叶子 case 已覆盖两个支持的 ATYPE_W；S/G 无有效约束，见 `SHMINS-004`|激励部分、检查部分、coverage 缺失、case 部分；总体部分实现|
|`TP-ADDR-002`|[ITYPE 地址公式](../spec/address-model.md#32-offset-解码)：LDST_S/LDST_V、LDSTE_V、LDSTE_S 分别使用连续、逐元素和 stride 公式|四种 ITYPE、不同 element index、正负 offset、DTYPE 和 length|reference 派生 MADDR/BANK/BADDR 与 scoreboard 最终值|ITYPE × element index class × offset sign × DTYPE × SPACE|`vec` 只覆盖 LDST_V；`es/ev` 覆盖 LDSTE_S/V；没有普通 LDST_S case|激励部分、检查部分、coverage 缺失、case 部分；总体部分实现|
|`TP-ADDR-003`|[`CREQ-003`](../spec/creq-ack-interface.md#8-复位与检查规则)及 [Interleave](../spec/address-model.md#4-interleave-概念与参数)：每个有效 MADDR 合法；`G=4 Byte..16 KiB`，跨块依次选择 BANK，并在 WRP/BLK 中形成正确 `inv_offs/inv_index`|每个合法 `creq_inv_size`，地址位于 block 首尾和跨界两侧，覆盖 4 KiB、8 KiB、16 KiB 编码差异|reference MADDR 字段分解、BANK/BADDR 和实际 MEM 请求|SPACE × G × block-boundary × BANK × local index|`creq_inv_size` 随机，无 TC knob 或 coverage 保证全部取值|激励部分、检查部分、coverage 缺失、case 缺失；总体部分实现|
|`TP-ADDR-004`|[SPACE_LOC](../spec/address-model.md#5-space_loc)：bank=thread，BADDR=`wpid*12KiB+MADDR`，合法 MADDR 严格小于 12 KiB|thread 0/15、wpid 0/末值、MADDR 0、12 KiB-1 及 12 KiB 空洞负例|reference 的 thread/MADDR/BANK/BADDR 与实际 write/read；输入约束应拒绝空洞|thread × wpid × MADDR boundary × direction × DTYPE|LOC 矩阵存在，但 wpid 固定 0，约束按 16 KiB，见 `SHMINS-003`|激励部分、检查部分、coverage 缺失、case 部分；总体部分实现|
|`TP-ADDR-005`|[SPACE_WRP](../spec/address-model.md#6-space_wrp)：BANK 来自 MADDR，BADDR 使用 wpid 和 local offset；8/16 KiB interleave 的 12～16 KiB local 空洞禁止访问|wpid 0/非零、所有 G、每个 BANK、MADDR 范围首尾、空洞前后和非法空洞|reference 算术/拼接结果与实际 MEM；输入 constraint 合法性|direction × G × BANK × wpid × local boundary/hole|WRP 的 vec/ev 矩阵存在；M2V es TC 存在但未入 regression；wpid 固定 0，空洞约束缺失|激励/检查部分、coverage 缺失、case 部分；总体部分实现|
|`TP-ADDR-006`|[SPACE_BLK](../spec/address-model.md#7-space_blk)：MADDR 决定 warp_group/warp_offs，`warp_index=warp_group*wpnum+warp_offs`；wpid 只做同组检查，并排除 12 KiB 空洞|wpnum 1/2/4、非零 warp_group、组边界、wpid 同组/异组负例、所有 G 和 MADDR/空洞边界|reference 的 group 分解、BANK/warp/BADDR 与实际 MEM；当前 reference 遗漏非零 warp_group，见 `REF-001`|wpnum × warp_group × warp_offs × G × BANK × hole class|BLK vec/ev 矩阵存在；M2V es TC 未入 regression；没有非零 warp_group 定向 case|激励部分、检查不可信、coverage 缺失、case 部分；总体部分实现|
|`TP-ADDR-007`|[M2V 写回和 beat 对齐](../spec/address-model.md#8-访问来源与-mem-beat-对齐)：m-read 和普通 V2M beat 对齐；M2V v-write、VTRANS write 可非对齐；M2V 写回位于所选 WARP 12 KiB|各来源 aligned/nonaligned 正反例，vaddr 0/最大值，写回跨 beat，普通 V2M element 位于 beat 边界|reservation read alignment、scoreboard 关联原始 creq 与实际 write、完整地址和 byte strobe；来源检查缺失见 `SCB-001/RSV-001`|source × direction × aligned class × vaddr boundary × beat crossing|V2M/M2V/VTRANS case 都可能随机命中，但没有定向来源分类 case|激励部分、检查部分、coverage 缺失、case 部分；总体部分实现|
|`TP-ADDR-008`|V2M `LDSTE_S + SPACE_WRP/BLK` 仅在排除 element 0 跨 thread 重叠写后可定义；M2V 同组合受支持|V2M 必须令每个 thread `creq_vmsk[*][0]==0` 并保证其余写地址无冲突；M2V 覆盖正常 element 0 读取|reference 单笔 overlap 检查、scoreboard 数据结果和 M2V read/writeback|direction × SPACE_WRP/BLK × element0 mask × overlap outcome|V2M 子 TC 存在但根 include 注释；M2V TC 已 include 但未入 LST|受限支持；V2M 激励缺失见 `SHMINS-007`，M2V case 未进 regression，coverage 缺失|

## 6. MEM 接口

|ID|Spec 与验证目标|所需激励|观察点与 checker|目标 coverage|当前 case|状态与缺口|
|---|---|---|---|---|---|---|
|`TP-MEM-001`|[`MEM-002`](../spec/mem-vlm-interface.md#6-检查规则)、`MEM-003`：有效 read/write 的地址已知，read 对齐；write 地址、strobe 和有效 data lane 已知且 strobe 非零|read/write 分别注入 valid/address/strobe/data X/Z、零 strobe、read 非对齐；valid 0 时 payload 任意|memory monitor 和 reservation monitor；当前只覆盖部分 valid/address，完整四态缺口见 `VMEM-002`|direction × field × known/XZ × valid × alignment|普通 V2M/M2V case 产生合法流量；无负向 case|激励缺失、检查部分、coverage 缺失、case 缺失；总体部分实现|
|`TP-MEM-002`|[`MEM-003`](../spec/mem-vlm-interface.md#6-检查规则)和 [写事务](../spec/mem-vlm-interface.md#22-写事务)：strobe 为 1 的 lane 写入对应 byte，0 lane保持；地址按访问来源满足对齐规则|full/sparse/single-lane strobe、跨 beat、同 bank 多周期写，以及三类来源 alignment|memory monitor transaction、`rtl_banks` 更新、reference byte map 和 scoreboard；来源 alignment 见 `SCB-001`|source × strobe pattern × DTYPE × beat crossing × aligned class|V2M/M2V/VTRANS 提供宽泛数据流，无 strobe/alignment 定向 case|激励部分、检查部分、coverage 缺失、case 部分；总体部分实现|
|`TP-MEM-003`|[`MEM-004`](../spec/mem-vlm-interface.md#6-检查规则)：T0 read 在 `T0+RPORT_DLY` 返回，只包含 `T0+FFD_CYC-1` 及之前的重叠写|`FFD_CYC=0/1/>1`，截止前/同周期/截止后写，byte 部分重叠和多次覆盖|T0 read transaction、写事件时间、memory snapshot 和返回 data；固定延迟路径存在，FFD snapshot 缺口见 `VMEM-001`|FFD_CYC × write relative cycle × overlap class × strobe × return correctness|M2V case 使用 read service，但没有 FFD 定向 case，当前参数只有 1|激励缺失、检查/模型部分、coverage 缺失、case 缺失；总体部分实现|
|`TP-MEM-004`|[同周期读写](../spec/mem-vlm-interface.md#25-同周期读写)及流水：不同 BANK 并行，同 BANK 可同时 read/write，每 BANK read 每拍可流水且保持顺序|连续 read、同拍多 BANK、同 BANK read/write、不同地址及重叠地址|memory monitor read/write transaction、每 BANK pending read queue、RPORT_DLY 后 data 和 M2V 最终写回|bank concurrency × pipeline depth × same-bank RW × overlap × order|公共 64～128 周期间隔不能稳定形成流水或同拍 read/write；无定向 case|激励缺失、检查部分、coverage 缺失、case 缺失；总体部分实现|

## 7. VLM reservation

|ID|Spec 与验证目标|所需激励|观察点与 checker|目标 coverage|当前 case|状态与缺口|
|---|---|---|---|---|---|---|
|`TP-RSV-001`|[`VLM-002`](../spec/mem-vlm-interface.md#6-检查规则)：req 有效时 addr/dly 已知，`1<=dly<VTAB_D`|read/write、两个 write port、delay 1/中间/`VTAB_D-1`，以及 0/越界/XZ 负例|reservation monitor X/Z 和 checker `DLY_ZERO/DLY_RANGE`|direction × port × delay bins × known/XZ|所有数据 case 间接产生 reservation；无 delay 定向 case|激励部分、检查已有、coverage 缺失、case 部分；可运行未闭环|
|`TP-RSV-002`|[`VLM-004`](../spec/mem-vlm-interface.md#6-检查规则)及 [busy 前移](../spec/mem-vlm-interface.md#34-delay-和-busy-前移)：issue 时目标 busy 严格为 0，后续占用逐拍前移且 reservation 不重复发布|external busy 0/1、SHM busy、不同 delay/sub bank，命中和不命中目标 slot|checker `TARGET_BUSY`、observed/final/SHM busy、record due-cycle 和 window 一致性|direction × delay × sub bank × busy source × accepted/rejected|公共 `EXTERNAL_BUSY_PERCENT=10` 概率注入；无确定 slot case|激励部分、检查已有、coverage 缺失、case 部分；可运行未闭环|
|`TP-RSV-003`|[`VLM-005`](../spec/mem-vlm-interface.md#6-检查规则)：同 BANK、同方向不得有两笔不同 reservation 同周期到期；read/write 方向独立|历史 pending 与新请求冲突、同周期两个 write port 同 delay、不同 delay合法、同 BANK read/write 同 due 合法|checker `PENDING_BANK_DUE_CONFLICT/CURRENT_BANK_DUE_CONFLICT`|direction × conflict source × same/different delay × legal/illegal|无冲突定向 case；普通随机流量可能命中|激励部分、检查已有、coverage 缺失、case 缺失；总体部分实现|
|`TP-RSV-004`|[`MEM-005`](../spec/mem-vlm-interface.md#6-检查规则)、`VLM-006`：reservation 与到期 MEM 双向一一对应，direction/BANK/完整地址/due cycle 全相等|正常兑现、missing、unexpected、提前、延后、重复、方向/BANK/地址错误|checker `UNEXPECTED_MEM/MISSING_MEM/MEM_ADDRESS/MEM_DUE_CYCLE` 和 matched counter；全局 `input_error` 抑制缺口见 `RSV-004`|match outcome × direction × bank × timing error × address relation|所有普通 case 经过匹配 checker；无负向定向 case|激励部分、检查部分、coverage 缺失、case 部分；总体部分实现|
|`TP-RSV-005`|[`VLM-003`](../spec/mem-vlm-interface.md#6-检查规则)、`VLM-007`：read 对齐；write 对齐按来源；合法非对齐 write 必须由完全相同的 `mem_waddr` 兑现|普通 V2M、M2V v-write、VTRANS 的 aligned/nonaligned 正反例，并改变低 5 bit|reservation checker 完整地址比较；write source alignment 应由 scoreboard 检查。当前见 `RSV-001`、`SCB-001`|source × aligned class × address-low-bits × match result|三类 case 存在但无定向地址 case|激励部分、检查部分、coverage 缺失、case 部分；总体部分实现|
|`TP-RSV-006`|[`VLM-008`](../spec/mem-vlm-interface.md#6-检查规则)和并行规则：不同 BANK 可共享同方向/delay/sub-bank slot；read/write 方向相互独立|至少两个 BANK 共享 slot，同 BANK read/write 同 due，以及单 BANK ownership 对照|checker 对 record 跨 BANK OR reduction，禁止共享本身报错；busy source 一致性仍需检查|bank multiplicity × direction × delay × sub bank × shared/not-shared|无共享 slot 定向 case；随机命中不可证明|激励缺失、检查已有、coverage 缺失、case 缺失；总体部分实现|

## 8. Reset

|ID|Spec 与验证目标|所需激励|观察点与 checker|目标 coverage|当前 case|状态与缺口|
|---|---|---|---|---|---|---|
|`TP-RST-001`|[`MEM-001`](../spec/mem-vlm-interface.md#6-检查规则)、`VLM-001` 和 [creq reset](../spec/creq-ack-interface.md#8-复位与检查规则)：reset 期间 creq_vld、release、ack、MEM valid、VLM req 全为 0；环境输出已知|初始 reset 和运行中 reset 分别在每类输出上注入违例，reset X/Z 边界单独处理|独立 reset assertion/monitor。当前 reservation monitor 跳过 reset 周期，无法检查 MEM/VLM 静默，见 `RSV-005`；creq release/ack 静默缺口见 `SHMINS-010`|initial/runtime reset × signal group × quiet/violation|根 case 只有固定初始 reset，无 reset 中负向或运行中 reset case|激励缺失、检查缺失、coverage 缺失、case 缺失；总体待实现|
|`TP-RST-002`|[`ACK-003`](../spec/creq-ack-interface.md#8-复位与检查规则)、[`VLM-009`](../spec/mem-vlm-interface.md#6-检查规则)：运行中 reset 取消 outstanding creq、credit、ack、pending reservation、MEM read pipeline 和验证侧期望，释放后不得兑现旧事务|分别在 credit 等待、ack 等待、reservation pending、MEM read pending、scoreboard outstanding 时拉 reset|跨组件 pending state、reset 后接口、reference/rtl memory、旧 timeout 和旧 due event；统一清理缺口见 `ENV-001`|reset stage × pending type × direction × post-reset stale event|无运行中 reset case|激励/检查/coverage/case 均缺失；总体待实现|

## 9. 当前缺口汇总

### 9.1 有 case，但覆盖证据不足

- V2M/M2V 矩阵能固定 direction、ITYPE、SPACE、DTYPE 和 ATYPE_W，但没有 functional
  coverage，无法证明随机的 length、mask、inv_size、wpnum、ack、priority、地址边界和
  reservation 场景已经出现。
- VTRANS 只有一个 case，虽然 `creq_tmsk` 已约束全 1，DTYPE 与 ITYPE 组合仍由 seed 决定。
- M2V `LDSTE_S + SPACE_WRP/BLK` 的 TC 已存在，但未进入当前 regression。

### 9.2 Spec 有要求，但当前没有定向 case

- credit 压力、ack 错误、四态输入、thread mask、priority、地址空洞、非零 WARP group；
- FFD_CYC、流水 read、同拍 read/write；
- reservation 冲突、跨 BANK 共享 slot、负向匹配；
- 运行中 reset 和所有 pending-state 取消。

### 9.3 Checker 或模型缺口

现有实现问题统一由[验证实现状态](../verification-status.md)跟踪。任何影响 testpoint
可信度的 P0/P1 问题关闭前，对应 testpoint 都不能标为已闭环。
