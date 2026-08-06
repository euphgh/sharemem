# ut_shm 验证文档迁移计划

本文规划如何将 `docs-old/` 中现有的 ut_shm 验证资料迁移为新的 `docs/`
文档体系。迁移工作以现有旧文档为内容来源，以当前仓库代码、filelist、构建脚本
和已经确认的接口行为为校正依据；执行时应先建立索引和目录骨架，再逐层迁移
DUT 规范、环境架构、组件实现、验证计划和使用指南。

阶段 0 的盘点结果记录在
[`documentation-migration-baseline.md`](documentation-migration-baseline.md)。

## 1. 迁移目标

迁移后的文档需要满足以下要求：

1. 每篇文档只有一个主要目的，不在多篇文档中维护同一份规则或配置定义。
2. `docs/index.md` 和各级 `index.md` 形成自顶向下的索引，读者可以按顺序或按任务进入详细文档。
3. DUT 行为、验证环境架构、组件实现、功能点、case、运行方法和当前状态分别维护。
4. 稳定的设计说明与经常变化的实现状态分离。
5. 旧文档内容迁移前必须与当前代码核对，不能原样复制已经失效的类名、路径、package 或运行方式。
6. 文档第一段自然介绍本文主要内容；只有确实存在前置关系时，才在第一段说明建议先阅读的文档。
7. 不使用固定的“目的、适用读者、前置阅读、权威范围”信息块。
8. 不在文档结尾添加上一篇、下一篇或返回索引导航。

## 2. 目标目录

```text
docs/
├── index.md
│
├── ut_shm/
│   ├── index.md
│   │
│   ├── spec/
│   │   ├── index.md
│   │   ├── dut-overview.md
│   │   ├── address-model.md
│   │   ├── creq-ack-interface.md
│   │   └── mem-vlm-interface.md
│   │
│   ├── environment/
│   │   ├── index.md
│   │   ├── architecture.md
│   │   ├── data-flow-and-models.md
│   │   │
│   │   └── components/
│   │       ├── index.md
│   │       ├── shm-environment.md
│   │       ├── shmins-mst-agent.md
│   │       ├── vlm-memory-agent.md
│   │       ├── vlm-reservation-agent.md
│   │       ├── shm-reference.md
│   │       └── shm-scoreboard.md
│   │
│   ├── plan/
│   │   ├── index.md
│   │   ├── testpoints.md
│   │   ├── testcases-and-regression.md
│   │   └── coverage-and-closure.md
│   │
│   ├── guide/
│   │   ├── index.md
│   │   ├── build-and-run.md
│   │   ├── configuration-reference.md
│   │   └── debug-guide.md
│   │
│   └── verification-status.md
│
└── development/
    └── systemverilog-code-style.md
```

迁移过程中可以先创建上述完整骨架，但未完成的正文不得伪装成有效说明。索引中
应把尚未完成的文档标记为“待迁移”，或暂时不提供链接。

## 3. 文档职责

|文档|主要内容|禁止重复维护的内容|
|---|---|---|
|`docs/index.md`|仓库文档分区和顶层入口|ut_shm 设计正文、组件算法|
|`ut_shm/index.md`|ut_shm 文档地图、顺序阅读路径和按任务阅读路径|详细接口规则、运行命令全集|
|`spec/dut-overview.md`|DUT 职责、边界、参数和接口分组概览|地址公式、UVM 实现|
|`spec/address-model.md`|VADDR/MADDR/BADDR、BANK、sub bank 和地址映射|scoreboard 实现|
|`spec/creq-ack-interface.md`|creq、credit/release 和 ack 行为|agent/driver 代码结构|
|`spec/mem-vlm-interface.md`|MEM 与 VLM reservation 的精确接口契约|reservation agent 内部算法|
|`environment/architecture.md`|testbench 层次、interface、Config DB、TLM 和 phase 关系|各组件内部状态机|
|`environment/data-flow-and-models.md`|共享 transaction、memory model、数据所有权和跨组件数据流|单个组件的开发细节|
|`environment/components/*.md`|每个组件的内部实现、配置、状态、检查和扩展方法|重复定义 DUT 协议|
|`plan/testpoints.md`|需要验证的功能点和检查/覆盖映射|case 运行命令|
|`plan/testcases-and-regression.md`|case 组织、命名、约束、seed 和 regression|plusarg 完整字典|
|`plan/coverage-and-closure.md`|覆盖模型、目标、waiver 和完成条件|组件算法|
|`guide/build-and-run.md`|Slang、VCS、Makefile、case 和 regression 的运行方法|功能点定义|
|`guide/configuration-reference.md`|环境变量、Makefile 变量和 plusarg 的完整定义|重复的运行教程|
|`guide/debug-guide.md`|常见错误、日志、波形和定位方法|当前开发进度|
|`verification-status.md`|已实现、部分实现、未实现、已知限制和最近验证结果|稳定的 DUT 规则|
|`development/systemverilog-code-style.md`|SystemVerilog/UVM 编码和检查规范|ut_shm 功能说明|

当一篇文档需要使用其他文档定义的信息时，应通过链接和规则编号引用，不复制整段
定义。短小的上下文摘要可以保留，但摘要必须明确指向详细文档。

## 4. 索引设计

### 4.1 顶层索引

`docs/index.md` 只列出主要文档分区，并将 ut_shm 的入口指向
`docs/ut_shm/index.md`。开发规范、其他模块文档或未来新增文档也从这里进入。

### 4.2 ut_shm 索引

`docs/ut_shm/index.md` 至少提供两类路径。

顺序阅读路径：

```text
DUT overview
  -> 地址与接口规范
  -> 验证环境架构
  -> 数据流和模型
  -> 功能点与 case
  -> 构建运行
  -> 当前状态
```

按任务阅读路径：

|任务|建议阅读路径|
|---|---|
|理解 DUT|DUT overview -> address model -> 对应接口规范|
|修改地址映射或 reference|address model -> data flow -> shm-reference|
|修改 scoreboard|data flow -> shm-scoreboard -> testpoints -> debug guide|
|修改 VLM memory agent|MEM/VLM interface -> architecture -> vlm-memory-agent|
|修改 reservation agent|MEM/VLM interface -> vlm-reservation-agent -> reservation testpoints|
|新增 testcase|testpoints -> testcases and regression -> configuration reference|
|运行编译或回归|build and run -> configuration reference -> debug guide|
|了解未完成功能|verification status -> 对应 spec/component 文档|

### 4.3 子目录索引

`spec/index.md`、`environment/index.md`、`components/index.md`、`plan/index.md`
和 `guide/index.md` 只承担以下职责：

- 说明该目录覆盖的主题；
- 列出子文档及其一句话内容；
- 给出本目录内部的推荐阅读顺序；
- 必要时给出进入其他目录的交叉链接。

## 5. 旧文档内容映射

### 5.1 `docs-old/ut_shm_test_plan.md`

|旧内容|目标文档|
|---|---|
|概述和 DUT 功能简介|`spec/dut-overview.md`|
|术语、参数和三级地址体系|`spec/address-model.md`，公共参数摘要保留在 DUT overview|
|地址映射机制|`spec/address-model.md`|
|creq 和 ack 相关事务字段|`spec/creq-ack-interface.md`|
|MEM/VLM 端口和行为|`spec/mem-vlm-interface.md`|
|事务建模|`environment/data-flow-and-models.md`|
|验证组件概览和连接|`environment/architecture.md`|
|各组件实现|`environment/components/` 下对应文档|
|Outstanding 和 scoreboard 算法|`environment/components/shm-scoreboard.md`|
|代码仓库、package 和 filelist|`environment/architecture.md` 与 `guide/build-and-run.md`|
|功能维度和测试限制|`plan/testpoints.md`|
|case、tc 和 regression|`plan/testcases-and-regression.md`|
|plusarg|`guide/configuration-reference.md`|
|当前完成和待办状态|`verification-status.md`|

### 5.2 `docs-old/index.md`

该文件是旧验证方案的扩展副本，不能整体迁入新的 `docs/index.md`。只提取其中比
`ut_shm_test_plan.md` 更新的命名、reservation agent 说明和链接，再分别合入新的
spec、environment、component 和 status 文档。

### 5.3 `docs-old/mem-vlm-interface-spec.md`

迁移为 `docs/ut_shm/spec/mem-vlm-interface.md`。迁移时需要保留接口规则、禁止行为、
匹配键、reset 和 X/Z 契约，同时结合当前源码核对参数、端口宽度、write port 0
非对齐地址和 `EXTERNAL_BUSY_PERCENT` 等最近修改。

### 5.4 `docs-old/vlm-reservation-verification-architecture.md`

迁移为 `docs/ut_shm/environment/components/vlm-reservation-agent.md`。DUT 接口规则
移到或链接到 `spec/mem-vlm-interface.md`，本文只保留 agent 层次、transaction、
scheduler、checker、coverage、单周期顺序、配置和开发说明。

### 5.5 `docs-old/systemverilog-code-style.md`

迁移为 `docs/development/systemverilog-code-style.md`。只更新已经失效的路径和阶段
描述，不加入 ut_shm 专用设计内容。

## 6. 执行阶段

### 阶段 0：建立迁移基线

- [x] 保存 `docs-old/` 作为迁移期间的历史输入，不在旧正文中继续开发新内容。
- [x] 记录旧文档的章节清单，确保每个有效章节都有目标位置。
- [x] 搜索仓库中所有指向原 `docs/` 路径的链接，包括根 `AGENTS.md`。
- [x] 列出旧文档中的历史名称、失效路径、未完成方案和相互矛盾的状态说明。
- [x] 根据当前代码建立组件、package、filelist、interface 和 test 的实际清单。

验收条件：旧内容有完整迁移映射，所有已知失效信息都有记录，不开始盲目复制正文。

状态：已于 2026-08-05 基于提交 `aa5a2e3` 完成，详见阶段 0 迁移基线。

### 阶段 1：创建目录和索引骨架

- [x] 创建目标目录。
- [x] 创建 `docs/index.md`。
- [x] 创建 `docs/ut_shm/index.md`。
- [x] 创建 spec、environment、components、plan 和 guide 的目录索引。
- [x] 在索引中只链接已经存在且至少有有效首段说明的文档。
- [x] 在新路径稳定后更新根 `AGENTS.md` 的必读文档链接。

验收条件：从 `docs/index.md` 可以进入 ut_shm，每个目录的职责和阅读路径清晰，
不存在指向空文件的有效链接。

状态：已于 2026-08-06 完成。详细正文仍按后续阶段迁移，索引中的待迁移文件不
提供链接。

### 阶段 2：迁移 DUT 规范

按以下顺序迁移：

1. [x] `dut-overview.md`；
2. [x] `address-model.md`；
3. [x] `creq-ack-interface.md`；
4. [x] `mem-vlm-interface.md`。

每篇文档都需要与当前 RTL 端口、`shm_util_package`、interface 和已确认设计行为
核对。不同文档之间使用链接，地址公式、接口规则和参数定义只保留一个详细版本。

验收条件：读者不阅读 UVM 代码也能理解验证视角下的 DUT 行为；规范之间没有冲突，
所有当前未定义行为均被明确列出。

状态：已于 2026-08-06 完成。地址模型已按 12 KiB WARP 空间重新定义，VTRANS、
credit/ack、运行中复位和 MEM/VLM reservation 的当前规则均已纳入新 spec。

### 阶段 3：迁移环境总体架构和数据模型

- [x] 编写 `environment/architecture.md`，覆盖 tb top、UVM hierarchy、interface、Config DB、TLM 和 phase。
- [x] 编写 `environment/data-flow-and-models.md`，覆盖 transaction、reference/implementation memory 和数据所有权。
- [x] 用当前 `shm_env_package.sv`、`shm_environment.svh`、filelist 和 tb top 校正旧文档。
- [x] 删除旧架构描述中的历史类名和已经废弃的数据通路。

验收条件：读者可以从顶层连接追踪一笔 creq 到 reference、scoreboard、MEM 和
reservation 检查路径，但正文尚不依赖任何组件内部算法。

状态：已于 2026-08-06 完成。正文以当前 source hierarchy 和连接为准，分别追踪
V2M、M2V 与 reservation 数据流；阶段 2 已定义但尚未进入验证代码的行为只登记为
实现边界，没有反向改写 DUT 协议。

### 阶段 4：逐个迁移组件文档

阶段 4 先建立集中问题台账，再按依赖关系迁移组件文档：

1. 提前创建 `verification-status.md`，定义稳定问题 ID、状态流转和验收记录格式；
2. 登记阶段 0～3 已确认的实现差异，不在组件正文中重复维护修复进度；
3. 迁移 `shm-environment.md`；
4. 迁移 `shmins-mst-agent.md`；
5. 迁移 `vlm-memory-agent.md`；
6. 迁移 `shm-reference.md`；
7. 迁移 `shm-scoreboard.md`；
8. 迁移 `vlm-reservation-agent.md`；
9. 每完成一篇组件文档，核对源码、spec 和测试，把新发现的差异加入问题台账；
10. 统一检查组件间链接、问题 ID、历史名称和重复职责。

组件文档、问题台账和 DUT spec 的分工如下：

- DUT spec 定义最终必须满足的端口、地址和时序行为；
- 组件文档说明组件职责、当前结构、数据流、核心算法和开发时必须保持的 contract；
- `verification-status.md` 记录实现与目标之间的差异、优先级、处理状态和验收证据；
- 组件文档只引用问题 ID，不复制问题的处理过程。无法从 spec 和源码确认的内容在
  台账中标记为“待确认”，并在继续形成结论前向用户或设计人员确认。

已知实现差异：当前 `shm_wtrans_item.svh` 的 SPACE_BLK 映射没有正确处理非零
`warp_group`，已有 case 因 MADDR 高位恒为 0 未暴露该问题。迁移 `shm-reference.md`
时需要按新地址模型登记，后续再修改代码；不能把现有 reference 写法反向解释成
DUT 规则。

阶段 2 后新增的已知实现缺口需要在对应组件迁移时处理：

- `creq_tmsk[THD_N]` 已进入接口规范；当前工作树已在 tb top、`shmins_interface` 和
  transaction 中开始添加字段，但声明位宽和 driver、monitor、copy、reference 等数据
  通路仍未贯通；
- 从当前设计代码推测，write reservation port 1 承载 V2M m-write（包括 VTRANS），
  port 0 承载 M2V v-write。该路由不是稳定 DUT 协议，不能用于接口级对齐判定；
- 当前 reservation checker 仍按 write port 0/1 判断对齐。后续应只保留 read
  reservation 的固定对齐检查，write alignment 由持有原始 creq 类型的 scoreboard
  按普通 V2M、M2V v-write 和 VTRANS 分别检查；
- 当前 VLM memory driver 在 `mem_rvld` 到达时立即读取 scoreboard memory，再延迟
  `RPORT_DLY` 输出，尚未实现 `FFD_CYC` 的写可见窗口。memory model 必须按
  `T0+FFD_CYC-1` 建立逐 byte read snapshot，避免依赖 UVM 进程调度顺序。

每篇组件文档至少覆盖：

- 组件负责和不负责的功能；
- 输入、输出和依赖；
- 配置和 phase；
- 内部状态与核心算法；
- error/checker 行为；
- reset、X/Z 和边界场景；
- 调试观察点；
- 主要源文件和相关定向测试；
- 修改或扩展时需要保持的 contract。

验收条件：组件文档能够指导开发修改，但不重新定义 DUT 端口协议；组件间共享的
transaction 和连接关系通过环境文档引用。所有已知实现差异都有唯一问题 ID、影响、
目标依据和验收方法，组件正文中不存在难以追踪的散落 todo。

状态：已于 2026-08-06 完成。六篇组件正文均已按当前源码迁移；同时提前建立
`verification-status.md`，集中登记实现缺口。当前支持边界明确为完整 active 环境；
DUT 可乱序调度重叠 creq，但 scoreboard 最终状态必须等价于 creq 顺序执行。

### 阶段 5：整理功能点、case 和覆盖闭环

- [x] 从旧测试方案、当前 testcase 和已实现 checker 中整理 `plan/testpoints.md`。
- [x] 为每个 testpoint 记录 spec、激励、观察点、checker、coverage、case 和状态。
- [x] 编写 `plan/testcases-and-regression.md`，说明 case 分类、命名、tc/lst、约束、seed 和 regression。
- [x] 编写 `plan/coverage-and-closure.md`，区分功能覆盖、代码覆盖、断言覆盖、waiver 和完成条件。
- [x] 不把运行命令复制到 plan 文档；相关内容链接到 guide。

验收条件：每个主要功能点都能追踪到检查方法和 testcase，未覆盖项有明确状态，
case 文档与当前测试目录一致。

状态：已于 2026-08-06 完成。`plan/index.md` 定义 spec、testpoint、case、run、checker
和 coverage 的关系；`testpoints.md` 按 spec-first 原则建立 30 个 testpoint，并分别
记录目标激励、观察、检查、coverage、case 和当前缺口；case/regression 文档按当前
19 个 TC 文件和 3 个 LST 文件整理，确认目标 regression 为 85 个 case。当前没有
functional coverage，因此本文只建立目标 bin/cross 和关闭条件，不声明任何功能点
已经闭环。新增实现缺口统一登记到 `verification-status.md`。

### 阶段 6：编写使用和调试指南

- [ ] 编写 `guide/build-and-run.md`，覆盖本地 Slang、远端 VCS、Makefile、case 和 regression。
- [ ] 编写 `guide/configuration-reference.md`，集中维护环境变量、Makefile 变量和 plusarg。
- [ ] 编写 `guide/debug-guide.md`，按问题现象组织常见错误、日志字段和波形观察点。
- [ ] 用实际命令验证指南，不复制旧 `rpu_sim` 或历史目录说明。

验收条件：新 checkout 的开发者或 Agent 能按照指南完成环境检查、编译和 smoke；
所有配置字段只有一个完整定义位置。

### 阶段 7：迁移开发规范和当前状态

- [ ] 迁移 SystemVerilog/UVM 开发规范。
- [ ] 整理并补全阶段 4 已创建的 `verification-status.md`。
- [ ] 将“已实现、部分实现、未实现、设计待确认、已知问题”分开记录。
- [ ] 为容易变化的状态记录检查日期或对应版本。
- [ ] 稳定的接口和算法规则回写到 spec/component 文档，不只保留在 status 中。

验收条件：状态文档可以独立更新而不扰动设计文档，开发规范不包含过期阶段说明。

### 阶段 8：一致性检查和阅读验证

- [ ] 检查全部 Markdown 相对链接。
- [ ] 检查根 `AGENTS.md` 和源码注释中的文档链接。
- [ ] 搜索旧类名、旧 package、旧目录和失效命令。
- [ ] 核对文档中的参数、端口、plusarg、UVM error ID 和源码路径。
- [ ] 检查同一规则是否在多篇文档中存在两个完整定义。
- [ ] 检查旧文档每个有效章节是否已经迁移或明确废弃。
- [ ] 使用无上下文阅读方式回答典型开发问题，确认索引能够引导到正确文档。
- [ ] 检查文档首段是否自然说明主要内容和必要前置关系。
- [ ] 检查文档中没有统一元数据块和上一篇/下一篇导航。

验收条件：所有链接有效，典型任务都有明确阅读入口，没有已知的重复职责或历史
命名残留。

## 7. 迁移中的内容处理规则

旧文档内容迁移时按以下方式处理：

- **直接迁移**：当前代码和 spec 仍然支持，且目标职责明确。
- **校正后迁移**：内容仍有价值，但名称、路径、参数或实现状态已经变化。
- **转为状态项**：属于当前限制、未实现功能或临时问题。
- **转为调试说明**：属于常见故障、日志分析或运行环境问题。
- **删除**：已经失效、与当前设计冲突或只是历史修改过程的内容。
- **暂缓**：无法从代码或现有说明确认，需要用户或设计人员决定。

任何暂缓项都应记录在迁移清单中，不能通过猜测补全文档。

## 8. 完成标准

满足以下条件后，新的文档体系才算迁移完成：

1. `docs/index.md` 是有效的仓库文档入口，不再包含整份 ut_shm 验证方案。
2. 从 `docs/ut_shm/index.md` 可以按顺序和按任务找到所有 ut_shm 文档。
3. DUT spec、环境架构、组件实现、testpoint、case、运行指南和状态分别维护。
4. 新文档中的名称、路径、package、filelist 和运行命令与当前仓库一致。
5. 旧文档中的有效内容均已迁移、明确废弃或列为待确认项。
6. 仓库内不存在指向已删除 `docs/*.md` 路径的链接。
7. 同一配置、接口规则或算法没有在多篇文档中维护多个完整副本。
8. 文档首段和各级索引形成清晰阅读路径，不依赖固定元数据块或文末导航。
9. 构建和 smoke 指令经过实际验证，verification status 记录最近结果。
10. `docs-old/` 的最终保留或删除策略由用户在迁移验收后决定。
