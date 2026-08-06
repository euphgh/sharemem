# ut_shm 文档迁移基线

本文记录文档迁移阶段 0 的盘点结果，包括旧章节的去向、当前代码清单、失效链接、
历史命名和需要延后确认的状态。后续迁移不直接复制旧文档，而是以本基线标记的
来源优先级和处理方式逐项校正。阶段 0 初次盘点对应仓库提交 `aa5a2e3`，检查日期为
2026-08-05；TC 与 regression 格式基线于 2026-08-06 根据当前文件和用户说明补充。

## 1. 信息来源与判定顺序

后续编写新文档时，按以下顺序判断内容是否仍然有效：

1. 用户已经确认的设计或实现状态；
2. 当前源码、package、filelist、tb top、Makefile 和现有定向测试；
3. `docs-old/mem-vlm-interface-spec.md` 与
   `docs-old/vlm-reservation-verification-architecture.md` 中的 VLM 专项定义，且仍需
   与当前源码核对；
4. `docs-old/index.md` 中比旧测试方案更新的命名和 reservation 内容；
5. `docs-old/ut_shm_test_plan.md` 中仍有价值的 DUT、地址模型和测试点描述；
6. 无法由上述来源确认的内容标记为待确认，不根据旧文档自行补全。

本阶段已确认两项特殊基线：

- `shm_scoreboard` 已采用 outstanding 新算法。旧测试方案中“当前仍使用原始算法”
  的状态描述失效；算法正文迁移时必须以当前 `shm_scoreboard.svh` 为准。
- VLM memory 端口、interface、transaction 和 agent 的名称以 VLM 专项文档和当前
  `ver_common/uvc/vlm_memory_agent/` 源码为准，不以
  `docs-old/ut_shm_test_plan.md` 中的历史 `vlm_*` 名称为准。

`docs-old/` 在迁移完成前保留为历史输入。除迁移计划和本基线外，不再在旧正文中
维护新的设计说明或实现状态。

## 2. 旧文档章节迁移清单

### 2.1 `ut_shm_test_plan.md`

|旧章节|有效内容|目标位置|处理方式|
|---|---|---|---|
|1.0 验证环境架构图|DUT、interface 与 UVM 组件的整体关系|`environment/architecture.md`|按当前 tb top 和环境重画|
|1.1 DUT 功能简介|DUT 边界、接口分组和地址术语概览|`spec/dut-overview.md`|校正后迁移|
|1.2 验证目标与方法学|验证目标、参考模型和 checker 思路|`plan/testpoints.md`|删除泛化描述，保留可追踪目标|
|1.3 验证环境组件|组件列表和职责概览|`environment/architecture.md`|按当前 hierarchy 校正|
|2.1 术语表|VADDR、MADDR、BADDR、BANK 等术语|`spec/dut-overview.md`、`spec/address-model.md`|详细定义只放一处|
|2.2 关键参数|参数含义和默认值|`spec/dut-overview.md`、`guide/configuration-reference.md`|以 `shm_util_package.sv` 为准|
|2.3 三级地址体系|VADDR、MADDR、BADDR 的范围与关系|`spec/address-model.md`|校正后迁移|
|2.4 地址映射关系|空间关系、映射流程和策略|`spec/address-model.md`|校正后迁移|
|3.1 映射控制信号|地址空间和映射相关 creq 字段|`spec/address-model.md`、`spec/creq-ack-interface.md`|字段定义与映射规则分开维护|
|3.2 `maddr2bank()`|BANK 与 BADDR 计算|`spec/address-model.md`|与当前 reference/RTL 核对|
|3.3 SPACE_LOC|线程私有映射规则|`spec/address-model.md`|与当前 reference/RTL 核对|
|3.4 SPACE_WRP|warp 共享映射和交织规则|`spec/address-model.md`|与当前 reference/RTL 核对|
|3.5 SPACE_BLK|block 共享映射和约束|`spec/address-model.md`|与当前 reference/RTL 核对|
|3.6 模式对比|三种地址空间的差异|`spec/address-model.md`|由前述单一规则汇总|
|4.1 输入事务|`shmins_interface` 与 `shmins_sequence_item`|`environment/data-flow-and-models.md`、`components/shmins-mst-agent.md`|接口规则链接到 creq/ack spec|
|4.2 输出事务|实际 MEM 访问 interface 与 transaction|`environment/data-flow-and-models.md`、`components/vlm-memory-agent.md`|使用当前 `vlm_memory_*` 命名|
|4.3 比对事务|`shm_wtrans_item` 的作用|`environment/data-flow-and-models.md`、`components/shm-scoreboard.md`|按当前字段和所有权校正|
|5.1.1 shmins mst agent|激励和采集职责|`components/shmins-mst-agent.md`|按当前 driver/monitor/sequencer 校正|
|5.1.2 shm reference|写请求期望数据生成|`components/shm-reference.md`|按当前源码校正|
|5.1.3 VLM slave agent|MEM 采集和读返回|`components/vlm-memory-agent.md`|历史名称全部替换|
|5.1.4 scoreboard|reference 与 MEM 写比对|`components/shm-scoreboard.md`|以新算法为准|
|5.2 读请求处理计划|reference/implementation memory 的设想|`verification-status.md`，确认后再进入组件文档|不得作为已实现架构直接迁移|
|5.3 Outstanding 场景|覆盖写、合并写、过期值和匹配算法|`components/shm-scoreboard.md`|新算法已实现，逐段与源码核对|
|5.3.3 collection 工具库|集合与关联数组工具的用途|`components/shm-scoreboard.md`、`guide/ubuntu-vcs-check.md`|package 名为 `collection`|
|6.1 ver_common|通用 UVC 的来源和路径|`environment/architecture.md`|只保留当前目录|
|6.2 ut_shm|专用环境的目录组织|`environment/architecture.md`、`guide/execution-environments.md`|旧目录树废弃|
|6.3 参数管理|共享参数 package|`guide/configuration-reference.md`|使用 `shm_util_package`|
|7.1 测试策略|单元测试、回归和覆盖目标|`plan/index.md`、`plan/testpoints.md`|状态与策略分离|
|7.2 用例定义|case 维度、限制和不支持组合|`plan/testpoints.md`、`plan/testcases-and-regression.md`、`verification-status.md`|当前 case 不足以确认的内容列为待确认|
|7.3 测试脚本组织|tc、lst、plusarg 和历史 `rpu_sim` 流程|`plan/testcases-and-regression.md`、`guide/workspace-transfer.md`、`guide/configuration-reference.md`|以当前 `ut_shm/tc/`、`ut_shm/regression/` 和 5.7 节格式基线重写；运行命令另行验证|
|7.4 当前测试状态|已完成和待完成清单|`verification-status.md`|全部重新从代码和近期运行结果建立|

### 2.2 `index.md`

旧 `index.md` 是 `ut_shm_test_plan.md` 的扩展副本，不作为新顶层索引迁移。其
1～7 章沿用上表的去向，只额外保留下列增量：

|增量内容|目标位置|处理方式|
|---|---|---|
|验证组件命名迁移表|对应 spec、architecture 和 component 文档|使用当前名称，不保留“目标代码名”措辞|
|VLM reservation 验证架构概览|`components/vlm-reservation-agent.md`|以专项架构文档和源码为准|
|VLM 专项文档链接|新的 spec 和 component 索引|更新为新路径|
|比旧测试方案更新的状态项|`verification-status.md`|仍需逐项核实，不直接继承|

### 2.3 `mem-vlm-interface-spec.md`

|旧章节|目标位置|处理方式|
|---|---|---|
|1 文档目的|`spec/mem-vlm-interface.md` 首段|改为自然的内容介绍，不保留固定元数据格式|
|2 参数和基本约定|`spec/dut-overview.md`、`spec/address-model.md`、`spec/mem-vlm-interface.md`|公共参数只定义一次，接口局部约定保留|
|3 MEM 接口|`spec/mem-vlm-interface.md`|按当前 DUT 端口和 `vlm_memory_interface` 核对|
|4 VLM 预约接口|`spec/mem-vlm-interface.md`|按当前 DUT 端口和 `vlm_reservation_interface` 核对|
|5 VLM 与 MEM 匹配|`spec/mem-vlm-interface.md`|保留完整地址匹配和双向完备性规则|
|6 复位和 X 传播|`spec/mem-vlm-interface.md`|区分 DUT 契约和验证实现|
|7 验证实现基准|对应 memory/reservation component 文档|spec 仅链接实现，不重复算法|
|8 当前未定义行为|`spec/mem-vlm-interface.md`、`verification-status.md`|稳定边界留在 spec，待确认项进入 status|

### 2.4 `vlm-reservation-verification-architecture.md`

|旧章节|目标位置|处理方式|
|---|---|---|
|1 文档目的|`components/vlm-reservation-agent.md` 首段|改为自然介绍|
|2 已确认架构约束|`spec/mem-vlm-interface.md` 或 component 文档链接|DUT 规则移入 spec，实现顺序留在 component|
|3 总体架构|`components/vlm-reservation-agent.md`|按当前 hierarchy 校正|
|4 组件职责|`components/vlm-reservation-agent.md`|按当前 active-only 实现校正|
|5 Transaction 与 scheduler 状态|`components/vlm-reservation-agent.md`|与 types/scheduler 源码核对|
|6 检查契约|DUT 规则放 spec，checker 实现放 component|避免双重定义|
|7 单周期处理顺序|`components/vlm-reservation-agent.md`|按当前 agent `main_phase` 核对|
|8 组件连接关系|`components/vlm-reservation-agent.md`|按当前 direct-call 关系校正|
|9 Transaction、sequence 与运行模式|`components/vlm-reservation-agent.md`|passive 模式描述失效|
|10 实现验收条件|`components/vlm-reservation-agent.md`、`verification-status.md`|contract 与实现状态分开|

### 2.5 `systemverilog-code-style.md`

全部章节迁移到 `development/systemverilog-code-style.md`。API 形状阶段的临时限制
已经失效，需要删除；class、成员、function/task、布局、contract 和检查要求在与
当前代码习惯核对后迁移。

## 3. 已知失效或矛盾信息

|旧信息|当前判定|迁移处理|
|---|---|---|
|scoreboard 新算法“尚未调试通过，当前使用原始算法”|失效；用户确认当前已经采用新算法，源码存在 `wmap_final`、`wmap_expired`、每笔 reference 的 `matched/expired` 和 timeout `unmatched` 记录|scoreboard 文档只描述当前算法，旧状态不迁移|
|`vlm_interface`、`vlm_sequence_item`、`vlm_slv_agent` 及其 driver/sequencer/config|历史名称|统一使用 `vlm_memory_interface`、`vlm_memory_sequence_item`、`vlm_memory_slv_*`|
|MEM UVC 位于 `ver_common/uvc/vlm_slv_agent/`|路径失效|使用 `ver_common/uvc/vlm_memory_agent/`|
|shmins sequence 位于 `ver_common/shmins_agent/sequence/`|路径失效|使用 `ver_common/uvc/shmins_agent/sequences/`|
|`vlm2aa.svh` 位于 `ut_shm/env/util/` 并由 `shm_util_package` include|路径和所属 package 失效|当前文件为 `ut_shm/env/vlm2aa.svh`，由 `shm_seq_item_package` include|
|参数 package 为 `shm_config_pkg`|名称和路径失效|当前为 `ut_shm/util/shm_util_package.sv` 中的 `shm_util_package`|
|集合库位于 `ut_shm/env/collection`，package 为 `collection_pkg`|目录和 package 名失效|文件为 `ut_shm/util/sv-collection/libs/collection_pkg.sv`，声明的 package 为 `collection`|
|环境 class/file 为 `shm_env`/`shm_env.sv`|历史简称|当前 class/file 为 `shm_environment`/`shm_environment.svh`；test 中实例名仍是 `shm_env`|
|`vlm_memory_model` 是 memory agent 子组件|失效|当前 agent 只有 monitor、driver、sequencer；`svt_mem rtl_banks` 由 scoreboard 持有|
|reservation agent、scheduler、checker、coverage 尚待实现|失效|四个组件均已进入 `shm_env_package` 并由 `shm_environment` 实例化|
|reservation agent 支持 active/passive 两种模式|与当前代码矛盾|当前配置和 agent 明确为 active-only，passive 只能列为未来扩展|
|reservation agent “不实现 reset 状态处理”|表述过时且不完整|当前 monitor 在 reset 释放前不采样/XZ 检查，agent 在首个有效周期前驱动已知 busy；运行中再次 reset 时 scheduler 状态如何清理仍需单独确认|
|reservation 核心路径“不使用 `main_phase`”|文字自相矛盾|当前唯一周期循环位于 agent `main_phase`；核心路径不依赖异步 TLM 回调顺序|
|`ref_svt_mem`/`imp_svt_mem` 是计划中的两个 memory component|名称和所有权与当前实现不同|当前 reference 持有 `ref_banks`，scoreboard 持有 `rtl_banks`；读路径完成度在组件迁移阶段重新核实|
|`ut_shm/tc/`、`ut_shm/regression/` 和 `ut_shm/test/` 是当前目录|部分恢复|当前已有 `ut_shm/tc/` 和 `ut_shm/regression/`；UVM test 源码目录仍为复数形式 `ut_shm/tests/`|
|使用 `ver_common/script/rpu_sim` 编译和回归|当前仓库无该入口|当前可重复构建入口是根 `Makefile`；历史脚本差异不迁移|
|旧文档“已完成”的 case、回归和覆盖状态|缺少当前文件或近期结果佐证|迁移到 status 前逐项重新验证，不沿用完成标记|
|Python 约束脚本处于本地未提交状态|当前仓库未发现对应脚本|作为历史未完成项；除非重新提供，不进入主要使用指南|

旧文档中的 SPACE_LOC/WRP/BLK 公式、creq 字段语义、支持组合、读路径完成度和
trans 指令计划暂未在阶段 0 判定真伪。这些内容分别在阶段 2、4、5 与 RTL、
reference、sequence 约束和测试结果核对。

## 4. 失效链接清单

迁移范围内，当前仓库中指向原 `docs/` 路径的有效引用只出现在根
`AGENTS.md`，共四组：

|当前链接|状态|阶段 1 目标|
|---|---|---|
|`docs/index.md`|文件尚未创建|保留名称，创建新顶层索引后恢复|
|`docs/mem-vlm-interface-spec.md`|旧路径已删除|改为 `docs/ut_shm/spec/mem-vlm-interface.md`|
|`docs/vlm-reservation-verification-architecture.md`|旧路径已删除|改为 `docs/ut_shm/environment/components/vlm-reservation-agent.md`|
|`docs/systemverilog-code-style.md`|旧路径已删除|改为 `docs/development/systemverilog-code-style.md`|

`docs-old/` 内的相对链接目前仍能在旧目录内部解析，迁移时再改成新路径。嵌入的
`ut_shm/util/sv-collection` 自带文档属于该工具库自己的文档树，不属于本次顶层
`docs/` 重构范围。

## 5. 当前实现清单

### 5.1 构建入口与 filelist

|项目|当前文件|实际作用|
|---|---|---|
|主构建入口|`Makefile`|使用 VCS 执行 preflight、compile 和 smoke，产物进入 `build/ut_shm`|
|RTL filelist|`ut_shm/filelist/shm_dut.f`|引用 DesignWare、公共 RTL、`RpuShm.f` 和 `RpuShmTop.sv`|
|环境 filelist|`ut_shm/filelist/shm_environment.f`|按依赖顺序加入 VIP、collection、utility、interface、环境 package 和 test package|
|tb top filelist|`ut_shm/filelist/shm_tbtop.f`|加入 `shm_tb_top.sv`|
|独立 UVM filelist|`ut_shm/filelist/shm_common.f`|显式加入 `$UVM_HOME/src/uvm.sv`；根 Makefile 当前通过 VCS `-ntb_opts` 使用 UVM，不引用该 filelist|
|历史配置参考|`ut_shm/cfg/ut_shm.cfg`|根 Makefile 参考其中选项，但明确不解析该文件|

根 Makefile 当前使用 `RPU_DIR`、`TB_DIR`、`VER_CMN`、`AXI_VIP_DIR` 和
`SNPS_DC_HOME`。默认 test 为 `shm_unit_test`；具体命令和变量将在阶段 6 实际验证
后写入 guide。

### 5.2 Package 及编译顺序

|顺序|Package|定义文件|主要内容|
|---|---|---|---|
|1|`collection`|`ut_shm/util/sv-collection/libs/collection_pkg.sv`|集合、关联数组和队列工具|
|2|`shm_util_package`|`ut_shm/util/shm_util_package.sv`|公共参数、`bit_rt_range`、`str_toupper`|
|3|`shm_seq_item_package`|`ut_shm/env/shm_seq_item_package.sv`|shmins/VLM memory transaction、enum field 和 `vlm2aa`|
|4|`shm_seq_package`|`ut_shm/env/shm_seq_package.sv`|shmins master/unit sequence|
|5|`shm_env_package`|`ut_shm/env/shm_env_package.sv`|三类 agent、environment config、reference、scoreboard、environment|
|6|`shm_test_package`|`ut_shm/tests/shm_test_package.sv`|`shm_base_test` 与 `shm_unit_test`|

第三方 package `svt_uvm_pkg` 和 `svt_mem_uvm_pkg` 在 `shm_env_package` 前由
`shm_environment.f` 加入。

### 5.3 Interface 与 tb top

|Interface|定义文件|tb top 实例|DUT 端口组|
|---|---|---|---|
|`clk_if`|`ver_common/uvc/clock/clk_if.sv`|`clock_intf`|提供共享 cycle 计数，不直接连接 DUT 业务端口|
|`shmins_interface`|`ver_common/uvc/shmins_agent/shmins_interface.sv`|`shmins_intf`|`creq_*`、`vack_*`、`mack_*`|
|`vlm_memory_interface`|`ver_common/uvc/vlm_memory_agent/vlm_memory_interface.sv`|`vlm_memory_intf`|DUT `mem_r*`、`mem_w*` 映射到 interface 内部 `r*`、`w*` 字段|
|`vlm_reservation_interface`|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_interface.sv`|`vlm_reservation_intf`|`vlm_rbusy/wbusy`、`vlm_rreq/wreq`、地址和 delay|

`ut_shm/tb/shm_tb_top.sv` 实例化 `RpuShmTop` 和上述四个 interface，通过
`shm_ut_connect.svh` 向 Config DB 发布 virtual interface。顶层在 10 个上升沿后
释放 `rst_n`。

### 5.4 UVM hierarchy 与数据连接

`shm_base_test` 创建实例名为 `shm_env` 的 `shm_environment`。环境当前创建：

```text
shm_environment
├── shmins_mst_agt : shmins_mst_agent
│   ├── monitor
│   ├── driver
│   └── sequencer
├── vlm_memory_slv_agt : vlm_memory_slv_agent
│   ├── monitor
│   ├── driver
│   └── sequencer
├── vlm_reservation_agt : vlm_reservation_agent
│   ├── monitor
│   ├── reservation_checker
│   ├── coverage
│   └── scheduler
├── shm_ref : shm_reference
└── shm_scb : shm_scoreboard
```

`shm_ref` 和 `shm_scb` 仅在 `shm_environment_config.shm_is_active == UVM_ACTIVE`
时创建。当前环境连接为：

|源|目标|内容|
|---|---|---|
|shmins monitor|shm reference|`shmins_sequence_item`|
|shm reference|scoreboard reference FIFO|`shm_wtrans_item` 期望写数据|
|VLM memory monitor write port|scoreboard RTL FIFO|`vlm_memory_sequence_item` 实际写事务|
|VLM memory driver `mem_port`|scoreboard `mem_imp`|阻塞读取 `rtl_banks` 以返回 MEM read data|

Reservation agent 同步采样 reservation 与 MEM interface，在内部按 checker、coverage、
scheduler 的顺序直接调用，不通过 scoreboard TLM 连接。

### 5.5 组件与主要源文件

|组件|主要源文件|
|---|---|
|shmins master agent|`ver_common/uvc/shmins_agent/shmins_mst_agent.svh`、`shmins_monitor.svh`、`shmins_mst_driver.svh`、`shmins_mst_sequencer.svh`|
|VLM memory slave agent|`ver_common/uvc/vlm_memory_agent/vlm_memory_slv_agent.svh`、`vlm_memory_monitor.svh`、`vlm_memory_slv_driver.svh`、`vlm_memory_slv_sequencer.svh`|
|VLM reservation agent|`ver_common/uvc/vlm_reservation_agent/vlm_reservation_agent.svh`、`vlm_reservation_monitor.svh`、`vlm_reservation_scheduler.svh`、`vlm_reservation_checker.svh`、`vlm_reservation_coverage.svh`|
|reference|`ut_shm/env/shm_reference.svh`|
|scoreboard|`ut_shm/env/shm_scoreboard.svh`|
|environment|`ut_shm/env/shm_environment.svh`、`shm_environment_config.svh`|

### 5.6 当前 test 与定向示例

|类型|当前文件或入口|阶段 0 能确认的范围|
|---|---|---|
|主 UVM test|`ut_shm/tests/shm_base_test.svh`、`shm_unit_test.svh`|仓库当前只注册这两个 test class|
|主 smoke 默认值|根 `Makefile` 的 `SIM_ARGS`|默认运行 `shm_unit_test`，`TRANS_NUM=0`|
|TC 根入口|`ut_shm/tc/ut_shm.tc`|定义公共 base testcase、方向派生 testcase、VTRANS testcase，并 include V2M/M2V 子 TC|
|TC 子文件|`ut_shm/tc/v2m/*.tc`、`ut_shm/tc/m2v/*.tc`|按方向、指令类型和地址空间组织普通 case；每个文件展开 DTYPE 与 ATYPE 组合|
|Regression 入口|`ut_shm/regression/ut_shm.lst`|include `v2m.lst` 和 `m2v.lst`；两个子列表给出当前完整目标回归集合|
|reservation compile 示例|`examples/vlm_reservation_compile/tb.sv`|联合 elaboration reservation 与 memory agent|
|地址对齐定向测试|`examples/vlm_reservation_compile/alignment_tb.sv`|write port 0 非对齐、port 1 对齐、MEM 完整地址匹配|
|external busy 定向测试|`examples/vlm_reservation_compile/external_busy_tb.sv`|`EXTERNAL_BUSY_PERCENT` plusarg 覆盖和 busy 驱动|
|sv-collection 自测|`ut_shm/util/sv-collection/tests/`|工具库独立测试，不等同于 ut_shm DUT case|

当前 regression 共选择 43 个 V2M case（42 个普通组合和 1 个 VTRANS）与 42 个
M2V case。Regression 条目表示目标运行集合，不等同于对应 case 已经在真实 design
环境中运行或通过；通过状态仍需以服务器上的实际结果为准。

### 5.7 TC 与 regression 格式基线

`.tc` 文件定义可供仿真或 regression 选择的 testcase：

1. Base testcase 名称对应 `+UVM_TESTNAME`，其后的仿真参数持续到 `endargs`。
2. `derived_case: base_case` 表示继承 base testcase。派生 case 可以追加或覆盖仿真
   参数，但 `+UVM_TESTNAME` 仍使用 base testcase 对应的 UVM test class。
3. `INCLUDE: path/to/file.tc` 将子 TC 文件中的定义并入当前 TC；include 路径相对
   `ut_shm/tc/` 组织。

当前根 TC 先定义 `shm_unit_test`，再派生 V2M、M2V 和 VTRANS 配置。普通子 TC 的名称
遵循：

```text
<direction>_<instruction>_<space>_dtyp<width>_atyp<width>
```

其中 `direction` 为 `v2m` 或 `m2v`，`instruction` 为 `vec`、`es` 或 `ev`，`space`
为 `loc`、`warp` 或 `blk`。每个普通子文件定义
`DTYP_{32,16,8} x ATYP_{32,16}` 六个组合。

`.lst` 文件选择已经在 TC 中定义的 case，并遵循以下规则：

1. 每个列出的 case 必须存在于 TC 定义中。
2. `RUN=n` 表示使用不同随机 seed 运行该 case `n` 次。
3. `SEED=num` 固定该 case 的随机 seed；指定 `SEED` 时，`RUN` 必须为 1。
4. `INCLUDE: child.lst` 将子 regression 列表并入当前列表。

这些规则是 Phase 5 编写 `plan/testcases-and-regression.md` 和检查 case/regression
一致性的格式依据。本地只做文本结构与引用完整性检查；权威解析和执行仍在具有
design 与回归工具的服务器上完成。

## 6. 后续阶段的待确认项

以下内容已有迁移位置，但阶段 0 不做结论：

- 地址公式及 SPACE_LOC、SPACE_WRP、SPACE_BLK 的所有边界值；
- creq/ack 的精确时序、credit/release 契约和 ack 完成条件；
- read request、reference memory 和 implementation memory 的实际完成度；
- 旧文档列出的指令类型、数据类型、地址类型和不支持组合是否仍适用；
- trans 指令需求是否仍属于当前 DUT 和验证范围；
- reservation agent 在仿真中途再次进入 reset 时是否必须清空 scheduler state；
- TC 中存在但未进入 regression 的组合是否需要单独维护或删除；
- 当前 regression case、coverage 和通过结果在远端 design 环境中的最新状态；
- 远端完整 RTL 环境中的最近 compile/smoke 基线。

这些项目分别在迁移阶段 2、4、5、6 和 7 处理。需要设计或用户决定的内容保持
“待确认”，不会在新文档中写成既定行为。

## 7. 阶段 0 验收结论

阶段 0 的五项工作均已完成：旧正文已冻结为历史输入；所有旧文档章节已有目标
位置；原 `docs/` 链接已定位；已知历史名称、路径、方案和矛盾状态已经登记；当前
组件、package、filelist、interface 与 test 已按源码建立清单。阶段 1 可以据此创建
新目录和索引骨架，但在对应正文完成前不应发布指向空白文档的有效链接。
