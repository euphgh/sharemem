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

当前只实现了第一批双 gid 的 address/reference 和 reservation functional coverage 基础；
其他 testpoint 仍缺少对应 covergroup，已实现项也尚未保存真实 RTL directed case 的目标
bin 命中证据，因此本文仍没有 testpoint 可标记为“已闭环”。本批暂不要求全项目 coverage
merge 或总百分比阈值。

## 2. Testpoint 总览

|领域|Testpoint|当前结论|
|---|---|---|
|Creq/ack|`TP-CREQ-001`～`005`、`TP-ACK-001`|credit、tmsk、四态、priority 和完整 ack 检查均不完整|
|数据路径|`TP-DATA-001`～`004`|双 gid正向主路径和reference隔离组件测试通过；真实RTL边界定向与完整coverage未完成|
|地址模型|`TP-ADDR-001`～`009`|BLK公式/回归和双gid物理公式组件测试通过；真实RTL边界与完整coverage未完成|
|MEM|`TP-MEM-001`～`005`|统一 monitor、gid resolver 和模型正向主路径已通过 109-case 真实 RTL 回归；FFD_CYC 和定向负例未完成|
|Reservation|`TP-RSV-001`～`008`|结构化outcome、第一批coverage和ownership/resolver组件测试已接入；完整矩阵与RTL定向未完成|
|Reset|`TP-RST-001`～`002`|初始 reset 可避开未知采样，运行中 reset 没有统一取消状态|

## 3. Creq 与 ack

|ID|Spec 与验证目标|所需激励|观察点与 checker|目标 coverage|当前 case|状态与缺口|
|---|---|---|---|---|---|---|
|`TP-CREQ-001`|[`CREQ-001`](../spec/creq-ack-interface.md#8-复位与检查规则)、`CREQ-005`：只在持有 credit 时接收请求，每笔有效 creq 消耗一个 credit，每拍 release 最多归还一个且总数不超过 `OTF_N`；release 与 ack 独立|连续发送至少 `OTF_N+1` 笔请求，覆盖 credit 用尽、release 早于/晚于 ack、连续 release 和无在途 release|观察 `creq_vld/creq_rls`、driver semaphore 和 outstanding 请求；需要独立 credit checker。当前 driver 只用 semaphore 限制自身发送，没有系统检查 DUT 过量 release，见 `SHMINS-009`|credit occupancy `0..OTF_N`、stall、release/ack 相对顺序及交叉|所有普通 case 都经过 credit driver，但公共 64～128 周期间隔不形成定向压力|激励部分、检查部分、coverage 缺失、case 仅宽泛映射；总体部分实现|
|`TP-CREQ-002`|[`CREQ-002`](../spec/creq-ack-interface.md#8-复位与检查规则)：valid 时公共字段和 active-thread payload 已知，inactive-thread payload 可为 X/Z；valid 为 0 时 payload 不检查|分别向公共字段、active thread 和 inactive thread 注入 X/Z，并覆盖 valid 0/1|shmins interface 和 monitor；monitor 应按 active mask 局部检查。当前只判断 `creq_vld`，见 `SHMINS-006`|字段类别 × active/inactive × known/XZ × valid|无负向 case|激励缺失、检查缺失、coverage 缺失、case 缺失；总体待实现|
|`TP-CREQ-003`|[`CREQ-007`](../spec/creq-ack-interface.md#8-复位与检查规则)及 thread-mask 语义：普通请求 `creq_tmsk!=0`，inactive thread 不产生地址、MEM/reservation 或写回；VTRANS 必须全 1|定向生成单 thread、多 thread、稀疏 mask、全 1、全 0 非法输入和 inactive payload X/Z|monitor 检查 X/Z/全零；reference 为 inactive thread 建立空派生数组，实际额外 MEM/VLM 输出由后级 checker 比对；见 `SHMINS-001`|tmsk population、thread index、direction、space、VTRANS 和全零非法 bin|109-case RTL 回归中普通请求随机非全零 mask，VTRANS 全 1；没有 tmsk 定向 case|正向主路径已通过全列表；coverage 和 mask/XZ 定向 case 缺失；总体部分实现|
|`TP-CREQ-004`|[`CREQ-004`](../spec/creq-ack-interface.md#8-复位与检查规则)及 mask/尾部 byte：length 以 Byte 计、与 DTYPE 对齐，只有 tmsk/vmsk/length 共同选择的 byte 形成访问；当前每个 thread 的 data、offset 和 mask 容量分别为 256 bit、256 bit 和 32 bit|覆盖 DTYPE 8/16/32、length 0/最小/32 Byte/非整元素非法值、稀疏 vmsk、最高有效 mask bit 和 element 尾部 byte|monitor transaction、reference 的 byte `wmap`、MEM strobe 和 scoreboard；reference 已支持 tmsk/length/vmsk，copy 和 active-element 消费边界已修复|DTYPE × length class × vmsk pattern × highest element × beat crossing × direction|256-bit 接口适配后的 109-case RTL 回归固定覆盖 DTYPE，length/vmsk 由 seed 随机；没有宽度边界定向 case|缩减带宽的正向主路径已通过全列表；coverage 缺失、边界 case 部分；总体部分实现|
|`TP-CREQ-005`|[Payload 语义](../spec/creq-ack-interface.md#4-payload-语义与合法性)：priority 只影响 MEM 调度顺序，不改变地址、数据和最终结果|相同 creq 数据使用不同 priority，覆盖多笔并发、地址重叠和调度次序变化|观察 creq priority、MEM 兑现次序和 scoreboard 最终状态；reference 不能按 priority 改期望|priority class × overlap × observed order × final result|priority 随机但无 plusarg、定向 case或 coverage；公共间隔也弱化并发|激励部分、检查部分、coverage 缺失、case 缺失；总体部分实现|
|`TP-ACK-001`|[`ACK-001`](../spec/creq-ack-interface.md#8-复位与检查规则)、`ACK-002`：ack disable 不得 ack；enable 时按方向、正确 ID exactly-once，done/有效 ID 已知；无协议最大延迟|V2M、M2V、VTRANS 分别覆盖 ack on/off、多个 outstanding ID、重复/错误方向/错误 ID/XZ 负例，以及 ack 与 release 的所有顺序|Monitor 发布带 cycle/reset epoch 的 raw ack；lifecycle checker 关联 accepted creq 和 scoreboard completion，检查 disabled/unexpected/duplicate/wrong-direction/wrong-ID。固定 200-cycle timeout 已移除；V2M/M2V 各自按接收顺序退休，可选 grace 只在实际数据全部 observed 且事务成为本方向队头后起算；年轻事务提前 ack 暂不报告乱序；credit 上溢仍缺，见 `SHMINS-008/009`|direction × ack_en × outcome × ack/release order × latency class|普通 case 中 `creq_ack_en` 随机；组件测试已覆盖慢前序/快后序、ack-disabled 前序、方向独立和年轻事务提前 ack；尚无 ack 协议负例及 clocked grace timeout case|ordered lifecycle 正向组件测试已通过；负例、clocked timeout、激励和 coverage 仍缺；总体部分实现|

## 4. 数据路径和架构顺序

|ID|Spec 与验证目标|所需激励|观察点与 checker|目标 coverage|当前 case|状态与缺口|
|---|---|---|---|---|---|---|
|`TP-DATA-001`|[普通 V2M](../spec/creq-ack-interface.md#5-普通-v2m-与-m2v)：所有有效输入 byte 按物理 `<bank,gid,BADDR>` 写入 MEM，无效 byte 不改变存储|覆盖 ITYPE、space、DTYPE、ATYPE、mask、length、两个gid、跨 beat 和多 bank写|shmins monitor → gid-aware reference byte map → unified VLM write → scoreboard final/expired 匹配|direction=V2M × ITYPE × SPACE × DTYPE × ATYPE × gid；strobe和bank count|109-case真实RTL主路径通过；standalone reference已验证相同bank/BADDR跨gid的V2M隔离；address coverage已接入|模型和组件隔离证据已具备；真实RTL gid边界case、完整coverage和bin命中证据仍缺|
|`TP-DATA-002`|[普通 M2V](../spec/creq-ack-interface.md#5-普通-v2m-与-m2v)：从物理 `<bank,gid,BADDR>` m-read，再按已编码 gid 内 WARP 基址的 `creq_vaddr` 写回；有效 read/write byte 不重叠|覆盖两个 gid、初始 memory、已有 V2M 写、read/write bank、vaddr 边界、byte overlap 接近但不相交及非法相交 generator case|reference `ref_banks[bank][gid]` 预测；统一 VLM resolver 为 MEM 补 gid；driver 从 `rtl_banks[bank][gid]` 返回；scoreboard 检查 v-write|M2V × ITYPE × SPACE × read gid × write gid × wpid 3/4 × byte-overlap class|109-case真实RTL主路径通过；组件测试覆盖跨gid读取、wpid 3/4 writeback、gid内WARP首尾，以及exact/one-byte overlap拒绝、adjacent/same-beat-disjoint/cross-gid允许；M2V gid cross已接入|公共hazard谓词和P0-1组件矩阵已具备；真实RTL vaddr边界和bin命中证据仍缺|
|`TP-DATA-003`|[`CREQ-006`](../spec/creq-ack-interface.md#8-复位与检查规则)和 [VTRANS](../spec/creq-ack-interface.md#6-vtrans)：合法输入为 16×16，数据转置但地址与控制不变，使用通用 V2M write byte 语义|DTYPE 8/16 × ITYPE LDST_S/LDST_V，非零 offset、不同数据模式、全 tmsk/vmsk，并覆盖不合法方向/space/length/mask 负例|reference 的 source `[element][thread]` 与 target `[thread][element]`、reservation/MEM 完整地址、scoreboard byte 数据|DTYPE × ITYPE × source/destination index；data pattern；beat address low bits|`v2m_vtrans_test` 已通过真实 RTL；reference组件已逐byte验证wpid 3/4的16×16转置和物理gid|VTRANS 正向主路径及双gid reference contract已具备；负例、coverage 和更多合法组合定向仍缺失；总体部分实现|
|`TP-DATA-004`|[架构顺序](../environment/components/shm-scoreboard.md#4-实际-write-比对)：DUT 可乱序兑现重叠 creq，但最终 memory 必须等价于 creq 顺序执行|定向构造完全重叠、部分重叠、链式覆盖和非重叠 creq，并控制 DUT 先兑现旧值或最终值|scoreboard `wmap_final/wmap_expired`、record matched/expired/unmatched 和 `check_phase` 最终收敛|overlap class × observed order × final/expired match × final convergence|公共 case 的 64～128 周期间隔不能稳定形成 outstanding/重叠；无定向 case|激励缺失、checker 已有但缺独立定向验证，coverage 缺失、case 缺失；总体部分实现|

## 5. 地址模型

|ID|Spec 与验证目标|所需激励|观察点与 checker|目标 coverage|当前 case|状态与缺口|
|---|---|---|---|---|---|---|
|`TP-ADDR-001`|[Offset 解码](../spec/address-model.md#32-offset-解码)：ATYPE_W 32/16、signed/unsigned、1B/DW granularity 与 DTYPE 共同得到 `E[t][k]`，禁止截断回绕|覆盖正/负/零/边界 raw offset，所有 width/sign/granularity/DTYPE 组合|monitor 解码字段、reference MADDR 和最终 BANK/BADDR/数据；需要独立公式级 reference 测试|ATYPE_W × sign × granularity × DTYPE × offset sign/boundary|正式 benchmark 已交叉覆盖 ATYPE_W/S/G/DTYPE，叶子 testcase 仍缺完整边界定向|生成与系统消费主路径已通过，独立公式测试、coverage 和边界 case 缺失；总体部分实现|
|`TP-ADDR-002`|[ITYPE 地址公式](../spec/address-model.md#32-offset-解码)：LDST_S/LDST_V、LDSTE_V、LDSTE_S 分别使用连续、逐元素和 stride 公式|四种 ITYPE、不同 element index、正负 offset、DTYPE 和 length|reference 派生 MADDR/BANK/BADDR 与 scoreboard 最终值|ITYPE × element index class × offset sign × DTYPE × SPACE|`vec` 只覆盖 LDST_V；`es/ev` 覆盖 LDSTE_S/V；没有普通 LDST_S case|激励部分、检查部分、coverage 缺失、case 部分；总体部分实现|
|`TP-ADDR-003`|[`CREQ-003`](../spec/creq-ack-interface.md#8-复位与检查规则)及 [Interleave](../spec/address-model.md#4-interleave-概念与参数)：每个有效 MADDR 合法；`G=4 Byte..16 KiB`，跨块依次选择 BANK，并在 WRP/BLK 中形成正确 `inv_offs/inv_index`|每个合法 `creq_inv_size`，地址位于 block 首尾和跨界两侧，覆盖 4 KiB、8 KiB、16 KiB 编码差异|reference MADDR 字段分解、BANK/BADDR 和实际 MEM 请求|SPACE × G × block-boundary × BANK × local index|`creq_inv_size` 随机，无 TC knob 或 coverage 保证全部取值|激励部分、检查部分、coverage 缺失、case 缺失；总体部分实现|
|`TP-ADDR-004`|[SPACE_LOC](../spec/address-model.md#5-space_loc)：bank=thread、absolute warp=`wpid`、laddr=MADDR，再统一拆 gid/BADDR；MADDR 严格小于 12 KiB|thread 0/15、wpid 0/3/4/7、MADDR 0、12 KiB-1 及空洞负例|逻辑地址与物理 `<bank,gid,BADDR>`；输入约束拒绝空洞|thread × wpid boundary × gid × MADDR boundary × direction × DTYPE|LOC 正向矩阵已通过109-case RTL回归；contiguous组件已定向检查wpid 3/4映射|双层地址正向主路径和组件gid边界证据已具备；真实RTL边界case和coverage仍缺|
|`TP-ADDR-005`|[SPACE_WRP](../spec/address-model.md#6-space_wrp)：bank/laddr 来自 MADDR，absolute warp=`wpid`，再统一拆 gid/BADDR；12～16 KiB local 空洞禁止访问|wpid 0/3/4/7、所有 G、每个 bank、MADDR 范围和空洞边界|第一层 interleave 结果与第二层物理映射分别检查|direction × G × bank × wpid × gid × local boundary/hole|WRP 正向矩阵已通过109-case RTL回归；contiguous组件已定向检查wpid 3/4映射|双层地址正向主路径和组件gid边界证据已具备；真实RTL空洞/边界case和coverage仍缺|
|`TP-ADDR-006`|[SPACE_BLK](../spec/address-model.md#7-space_blk)：MADDR 编码当前 group 内的 bank/warp_offs/inv_index，`wpid/wpnum` 选择 absolute group，再统一拆 gid/BADDR|wpnum 1/2/4、wpid 0/3/4/7、MADDR 0 与 `C*B*P-1/C*B*P`、absolute warp 0～7、空洞边界|独立公式与公共 helper 比对 group-relative range、逻辑 bank/warp/laddr、物理 gid/BADDR 和实际 MEM|wpnum × wpid-derived group × warp_offs × absolute warp × gid × G × bank × hole|两轮各1248个独立公式边界检查覆盖全部13个interleave size，RTL BLK regression通过；contiguous组件已检查wpid 3/4|激励、helper、reference和RTL回归已完成；functional coverage待实现|
|`TP-ADDR-007`|[MEM beat 地址与 byte lane](../spec/address-model.md#9-mem-beat-地址与-byte-lane)：read/write beat 均允许非对齐，lane `k` 对应 `beat_addr+k`|两个 gid、低 5 bit、跨传统 32-Byte 边界、vaddr WARP首尾和 sparse strobe|memory model 按 `<bank,gid,BADDR>` 返回；scoreboard 展开逐 byte；reservation 完整地址兑现|direction × gid × address-low-bits × boundary crossing × strobe|正向随机地址已通过 109-case RTL 回归；没有 gid/跨界定向|激励和模型正向主路径已通过全列表；coverage、gid 和跨边界定向 case 缺失|
|`TP-ADDR-008`|V2M `LDSTE_S + SPACE_WRP/BLK` 仅在排除 element 0 跨 thread 重叠写后可定义；M2V 同组合受支持|V2M 必须令每个 thread `creq_vmsk[*][0]==0` 并保证其余写地址无冲突；M2V 覆盖正常 element 0 读取|reference 单笔 overlap 检查、scoreboard 数据结果和 M2V read/writeback|direction × SPACE_WRP/BLK × element0 mask × overlap outcome|Strided item 已自动 mask V2M element 0；V2M/M2V 共 24 个叶子 case 已通过扩容后的真实 RTL 主列表|激励、checker 和系统 case 已验证；functional coverage 缺失，总体可运行未闭环；`SHMINS-007` 已关闭|
|`TP-ADDR-009`|[逻辑到物理映射](../spec/address-model.md#8-逻辑地址到物理地址)：三种 space 共用 `gid=warp/4`、`BADDR=(warp%4)*WARP_STEP+laddr`|公式级遍历关键 bank/warp/laddr；故意构造 warp0/4 同 BADDR|独立 helper 单元测试和 reference 诊断字段|space × warp 0/3/4/7 × gid × laddr boundary|独立公式组件测试覆盖BANK 0/15、warp 0/3/4/7、laddr首尾和VTRANS wpid 3/4；address coverage已接入|公式和组件边界证据已具备；三种space的真实RTL定向case及目标cross命中证据仍缺|

## 6. MEM 接口

|ID|Spec 与验证目标|所需激励|观察点与 checker|目标 coverage|当前 case|状态与缺口|
|---|---|---|---|---|---|---|
|`TP-MEM-001`|[`MEM-002`](../spec/mem-vlm-interface.md#6-检查规则)、`MEM-003`：有效 read/write 的完整地址已知；write strobe和有效data已知且非零|read/write分别注入valid/address/strobe/data X/Z和零strobe|统一 VLM monitor；当前旧实现只覆盖部分valid/address，见`VMEM-002`|direction × field × known/XZ × valid|无负向case|统一monitor四态检查待实现|
|`TP-MEM-002`|[`MEM-003`](../spec/mem-vlm-interface.md#6-检查规则)和 [写事务](../spec/mem-vlm-interface.md#22-写事务)：strobe lane写入`mem_waddr+lane`，地址允许非对齐|两个gid、full/sparse/single-lane、低5bit和跨32-Byte边界|matched memory transaction、`rtl_banks[bank][gid]`、reference byte map和scoreboard|source × gid × strobe × DTYPE × lowbits × crossing|正向随机写流量已通过 109-case RTL 回归；无 gid/strobe 定向|gid-aware 模型正向主路径已通过全列表；边界 case 和 coverage 缺失|
|`TP-MEM-003`|[`MEM-004`](../spec/mem-vlm-interface.md#6-检查规则)：T0 read 在 `T0+RPORT_DLY` 返回，只包含 `T0+FFD_CYC-1` 及之前的重叠写|`FFD_CYC=0/1/>1`，截止前/同周期/截止后写，byte 部分重叠和多次覆盖|T0 read transaction、写事件时间、memory snapshot 和返回 data；固定延迟路径存在，FFD snapshot 缺口见 `VMEM-001`|FFD_CYC × write relative cycle × overlap class × strobe × return correctness|M2V case 使用 read service，但没有 FFD 定向 case，当前参数只有 1|激励缺失、检查/模型部分、coverage 缺失、case 缺失；总体部分实现|
|`TP-MEM-004`|[同周期读写](../spec/mem-vlm-interface.md#25-同周期读写)及流水：不同 BANK 并行，同 BANK 可同时 read/write，每 BANK read 每拍可流水且保持顺序|连续 read、同拍多 BANK、同 BANK read/write、不同地址及重叠地址|memory monitor read/write transaction、每 BANK pending read queue、RPORT_DLY 后 data 和 M2V 最终写回|bank concurrency × pipeline depth × same-bank RW × overlap × order|公共 64～128 周期间隔不能稳定形成流水或同拍 read/write；无定向 case|激励缺失、检查部分、coverage 缺失、case 缺失；总体部分实现|
|`TP-MEM-005`|[`VLM-012`](../spec/mem-vlm-interface.md#6-检查规则)：MEM 无 gid，只有唯一到期 reservation match 才能补全 gid并更新数据模型|正常 match、unexpected、missing、地址错误，以及两个 gid相同 BADDR 的隔离访问|resolver 的 gid/gid_valid/matched；read driver和 scoreboard只消费完全匹配事务|direction × gid × match outcome × same-BADDR-different-gid|109-case正常路径通过；组件测试覆盖gid 0/1 matched、unexpected、missing、address mismatch及agent发布unmatched metadata，reference覆盖同BADDR跨gid隔离；match coverage已接入|P0-1 resolver组件矩阵已具备；真实RTL定向及目标bin命中证据仍缺|

## 7. VLM reservation

|ID|Spec 与验证目标|所需激励|观察点与 checker|目标 coverage|当前 case|状态与缺口|
|---|---|---|---|---|---|---|
|`TP-RSV-001`|[`VLM-002`](../spec/mem-vlm-interface.md#6-检查规则)：req 有效时 addr/dly/gid 已知，`1<=dly<VTAB_D`|read/write、两个 write port、gid 0/1、delay边界和 addr/dly/gid XZ负例|统一 monitor X/Z 和 checker `DLY_ZERO/DLY_RANGE`|direction × port × gid × delay bins × known/XZ|正向 reservation 流量已通过 109-case RTL 回归|统一接口和 checker 正向主路径已通过全列表；coverage 和 gid/delay/XZ 定向 case 缺失|
|`TP-RSV-002`|[`VLM-004`](../spec/mem-vlm-interface.md#6-检查规则)及 busy前移：目标 `[dly][gid][subbank]` 必须空闲并逐拍前移|两个 gid的 external/SHM busy、不同 delay/subbank，命中和非目标 slot|checker `TARGET_BUSY`、observed/final/SHM busy、record gid/due和window|direction × delay × gid × subbank × busy source × outcome|109-case正向路径通过；组件测试覆盖target-gid external拒绝、other-gid external允许、SHM pending阻塞和窗口前移；定向policy可精确构造drive-cycle/slot；admission coverage已接入|external/SHM ownership和可重复激励基础已具备；完整delay/subbank矩阵、RTL定向和bin命中仍缺|
|`TP-RSV-003`|[`VLM-005`](../spec/mem-vlm-interface.md#6-检查规则)：同 bank/direction/due仅一笔，即使gid/subbank不同；read/write独立|历史跨gid pending、同周期双write port各种gid/subbank组合、不同delay合法、同bank read/write同due合法|checker `PENDING_BANK_DUE_CONFLICT/CURRENT_BANK_DUE_CONFLICT`|direction × conflict source × same/different gid × same/different subbank × outcome|组件测试已覆盖current conflict、historical other-gid pending、different-bank shared slot和同bank read/write同due合法；结构化outcome和coverage已接入|P0-1冲突/合法对照已具备；完整gid/subbank组合、RTL定向和bin命中仍缺|
|`TP-RSV-004`|[`MEM-005`](../spec/mem-vlm-interface.md#6-检查规则)、`VLM-006/012`：reservation 与到期 MEM 双向一一对应；record额外携带gid供MEM继承|两个gid正常兑现、missing、unexpected、提前、延后、重复和地址错误|checker错误族、matched counter、resolver gid/match status；局部抑制仍见`RSV-004`|match outcome × direction × bank × gid × timing × address relation|109-case正常路径通过；组件测试覆盖gid 0/1 matched、missing、unexpected和address mismatch，结构化outcome和coverage已接入|P0-1正常/主要负例组件证据已具备；提前/延后/重复、RTL定向和bin命中仍缺|
|`TP-RSV-005`|[`VLM-003`](../spec/mem-vlm-interface.md#6-检查规则)、`VLM-007`：read/write reservation 均允许非对齐，并由完全相同的 MEM 完整地址兑现|read/write、两个 write port、低 5 bit 为 0/非零，以及只改变低位的 mismatch|reservation checker 完整地址比较；scheduler 保留所有地址位|direction × port × address-low-bits × match result|reservation 定向例覆盖非对齐地址原样兑现和低位 mismatch|激励和检查已有、coverage 缺失；总体部分实现|
|`TP-RSV-006`|[`VLM-008`](../spec/mem-vlm-interface.md#6-检查规则)：不同bank可共享同direction/delay/gid/subbank slot；read/write独立|至少两个bank共享完整slot，同bank read/write同due及ownership对照|checker按gid/subbank跨bank OR reduction|bank multiplicity × direction × delay × gid × subbank × shared|组件测试已定向覆盖different-bank shared slot和同bank read/write同due合法|跨bank归约及direction独立组件证据已具备；完整组合、RTL定向和coverage仍缺|
|`TP-RSV-007`|[`VLM-010`](../spec/mem-vlm-interface.md#6-检查规则)：other-gid external busy允许，other-gid同bank/due DUT record阻塞|对同一候选交替构造两种busy所有者，并覆盖不同bank对照|scheduler ownership与checker target/pending判定|direction × candidate gid × other-gid source × same/different bank × outcome|组件测试已证明target-gid external拒绝、other-gid external允许、other-gid SHM pending阻塞和different-bank合法；ownership cross及定向busy policy已接入|P0-1所有权组件矩阵已具备；真实RTL定向及bin命中仍缺|
|`TP-RSV-008`|[`VLM-012`](../spec/mem-vlm-interface.md#6-检查规则)：到期record为MEM恢复唯一gid|两个gid相同地址正常兑现，及unexpected/missing/address mismatch|resolver result、memory transaction metadata和可信模型是否更新|direction × gid × match outcome × address relation|组件测试覆盖gid 0/1正常恢复、unexpected、missing、address mismatch，并由agent subscriber检查unmatched发布元数据；reference覆盖相同BADDR跨gid隔离；match cross已接入|P0-1 resolver/metadata组件矩阵已具备；真实RTL定向及bin命中仍缺|

## 8. Reset

|ID|Spec 与验证目标|所需激励|观察点与 checker|目标 coverage|当前 case|状态与缺口|
|---|---|---|---|---|---|---|
|`TP-RST-001`|[`MEM-001`](../spec/mem-vlm-interface.md#6-检查规则)、`VLM-001` 和 [creq reset](../spec/creq-ack-interface.md#8-复位与检查规则)：reset 期间 creq_vld、release、ack、MEM valid、VLM req 全为 0；环境输出已知|初始 reset 和运行中 reset 分别在每类输出上注入违例，reset X/Z 边界单独处理|独立 reset assertion/monitor。当前 reservation monitor 跳过 reset 周期，无法检查 MEM/VLM 静默，见 `RSV-005`；creq release/ack 静默缺口见 `SHMINS-010`|initial/runtime reset × signal group × quiet/violation|根 case 只有固定初始 reset，无 reset 中负向或运行中 reset case|激励缺失、检查缺失、coverage 缺失、case 缺失；总体待实现|
|`TP-RST-002`|[`ACK-003`](../spec/creq-ack-interface.md#8-复位与检查规则)、[`VLM-009`](../spec/mem-vlm-interface.md#6-检查规则)：运行中 reset 取消 outstanding creq、credit、ack、pending reservation、MEM read pipeline 和验证侧期望，释放后不得兑现旧事务|分别在 credit 等待、ack 等待、reservation pending、MEM read pending、scoreboard outstanding 时拉 reset|跨组件 pending state、reset 后接口、reference/rtl memory、旧 timeout 和旧 due event；统一清理缺口见 `ENV-001`|reset stage × pending type × direction × post-reset stale event|无运行中 reset case|激励/检查/coverage/case 均缺失；总体待实现|

## 9. 当前缺口汇总

### 9.1 有 case，但覆盖证据不足

- V2M/M2V 矩阵能固定 direction、ITYPE、SPACE、DTYPE 和 ATYPE_W；第一批 address 和
  reservation coverage 已接入，但尚无真实 RTL directed run 的目标 bin 命中证据，且
  length、mask、ack、priority 等仍无 coverage。
- VTRANS 只有一个 case，虽然 `creq_tmsk` 已约束全 1，DTYPE 与 ITYPE 组合仍由 seed 决定。
- V2M/M2V `LDSTE_S + SPACE_WRP/BLK` 的 24 个 case 已进入 regression，并随
  109-case 主列表通过真实 RTL 运行；本批 address collector 已接入，但对应 target cross
  尚未形成可保存的命中证据。

### 9.2 Spec 有要求，但当前没有定向 case

- credit 压力、ack 错误、四态输入、thread mask、priority、地址空洞、非零 WARP group；
- FFD_CYC、流水 read、同拍 read/write；
- reservation 完整冲突矩阵、跨 BANK 共享 slot 和真实 RTL 负向匹配；纯 checker 组件已
  覆盖部分 ownership/current-conflict/unexpected/address-mismatch 场景；
- 运行中 reset 和所有 pending-state 取消。

### 9.3 Checker 或模型缺口

现有实现问题统一由[验证实现状态](../verification-status.md)跟踪。任何影响 testpoint
可信度的 P0/P1 问题关闭前，对应 testpoint 都不能标为已闭环。
