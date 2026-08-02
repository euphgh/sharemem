# ut_shm 验证环境修复 TODO 与检查清单

## 1. 文档目的

本文用于跟踪当前 `ut_shm` 验证环境从“代码已迁移但无法编译”修复到“VCS
编译成功并能启动 UVM 仿真环境”的工作。本文是实施清单，不定义 DUT 功能正确性。

本阶段的完成标准是：

1. 本地使用 slang 对可覆盖的 SystemVerilog/UVM 源码完成语法检查。
2. 远端服务器使用 VCS、UVM 和 Synopsys VIP 完成编译与 elaboration。
3. 生成的仿真程序能够启动 `shm_tb_top` 和一个零事务 smoke test。
4. UVM topology 中能看到 SHMINS、VLM memory、VLM reservation、reference 和
   scoreboard 组件；启动阶段没有由 package、Config DB、virtual interface 或 TLM
   连接缺失导致的 `UVM_FATAL`。

本阶段不要求：

- DUT 输出或 scoreboard 比对结果正确；
- reservation checker 和 coverage 达到功能验收标准；
- 完成读写、outstanding、地址映射或回归测试；
- 空壳 `RpuShmTop` 产生有效行为。

### 实施阶段门禁

本文只建立后续修复计划，不自动授权源码实现。仓库级 `AGENTS.md` 当前仍记录
`vlm_reservation_agent` 的 API-shape 阶段限制。P0 构建入口已由用户明确授权实施；执行
P1～P5 中任何非文档修改前，仍需用户明确确认进入对应的环境编译修复与集成阶段。

## 2. 信息来源与适用优先级

修复时按以下优先级处理冲突：

1. 用户已确认的迁移决定和当前阶段约束。
2. `docs/mem-vlm-interface-spec.md` 中的接口行为约定。
3. `docs/vlm-reservation-verification-architecture.md` 中的新 reservation agent
   结构与连接约定。
4. `ut_shm/cfg/ut_shm.cfg` 已有选项的构建语义。
5. `docs/systemverilog-code-style.md` 中的代码风格。
6. 当前遗留源码仅用于恢复实现意图，冲突时不得反向覆盖上述决定。
7. `docs/ut_shm_test_plan.md` 仅用于理解旧环境的数据流、reference、scoreboard 和
   test 意图。该文档中的旧名称、旧路径和旧参数不作为当前实现基准。

已确认的迁移决定：

- `ut_shm/util/shm_util_package.sv` 内的 package 名固定为
  `shm_util_package`，文件名与 package 名一致。
- `shm_util_package` 替代旧的 `shm_config_pkg`，统一提供验证参数和
  `bit_rt_range` 等通用工具。
- `sv-collection` 保持独立的 `collection` package，通过编译顺序和显式 import
  提供给使用者，不在 `shm_util_package` 内嵌套 package。
- 带完整声明且由 package include 的头文件使用 `.svh`；include guard 统一为
  `INC_<FILE_NAME>_SVH`。
- DUT 的 `mem_*` 端口接入 `vlm_memory_agent`，DUT 的 `vlm_*` 预约端口接入
  `vlm_reservation_agent`。
- 远端 `AXI_VIP_DIR` 已配置，Synopsys VIP 依赖可以保留。
- 设计目录以 `ut_shm/filelist/shm_dut.f` 为基准。

## 3. 目标 package 与编译依赖

建议的编译顺序如下，filelist 和 Makefile 应明确保持这个顺序：

1. UVM 与 Synopsys VIP package。
2. `collection` package。
3. `shm_util_package`。
4. `RpuCommon` 与 DUT 源码。
5. `clk_if`、`shmins_interface`、`vlm_memory_interface` 和
   `vlm_reservation_interface`。
6. `shm_seq_item_package`。
7. `vlm_reservation_pkg`。
8. `shm_env_package`。
9. `shm_seq_package`。
10. `shm_test_package`。
11. `shm_tb_top`。

目标 package 内容：

| Package | 目标内容 |
|---|---|
| `collection` | `sv-collection` 工具类 |
| `shm_util_package` | 公共参数、`bit_rt_range` 和 SHM 通用工具 |
| `shm_seq_item_package` | SHMINS enum、`shmins_sequence_item`、enum 转换函数和 `vlm_memory_sequence_item` |
| `vlm_reservation_pkg` | reservation types、config、scheduler、checker、coverage、monitor 和 agent |
| `shm_env_package` | SHMINS agent、VLM memory agent、environment config、reference、scoreboard 和 environment |
| `shm_seq_package` | SHMINS base/unit sequence |
| `shm_test_package` | base/unit test |

## 4. 修复 TODO

状态标记：`[ ]` 未开始，`[~]` 进行中，`[x]` 已完成，`[!]` 等待确认。

### P0：建立可重复的构建入口（已完成）

- [x] **BUILD-01：将 `ut_shm.cfg` 作为构建参数参考。**
  - 根 Makefile 不 include、解析或修改 `ut_shm.cfg`。
  - 在 Makefile 中显式维护等价的 filelist、宏、elaboration 和 coverage 选项。
  - filelist 内部继续使用 `$RPU_DIR`、`$TB_DIR`、`$VER_CMN` 等 VCS 环境变量引用。

- [x] **BUILD-02：在仓库根目录新增 `Makefile`。**
  - Makefile 仅面向远端 Linux/GNU Make，不要求兼容 macOS 自带 Make。
  - 提供 `preflight`、`compile`、`smoke` 和 `clean` target。
  - 明确记录 `RTL_FLST`、`TB_FLST`、`RTL_ANA_OPT`、`TB_ANA_OPT`、
    `TB_ELAB_OPT` 和 `TB_CMP_OPT` 分别映射到哪个 VCS 命令，配置项不能被静默忽略。
  - `compile` 必须同时完成 analysis 与 elaboration，并生成本次构建的 `simv`。
  - `smoke` 必须依赖并运行同一构建目录中的 `simv`；`simv` 不存在时先触发
    `compile`，不得复用路径不明的旧程序。
  - 所有输出放到独立的 `build/` 或用户指定目录，不在源码和文档目录生成中间文件。
  - `clean` 只能删除已验证的构建目录。

- [x] **BUILD-03：定义 Makefile 环境变量和默认路径。**
  - 从根 Makefile 位置默认推导 `RPU_DIR`、`TB_DIR` 和 `VER_CMN`，并导出给 VCS。
  - 外部使用 `AXI_VIP_DIR`、可选的 `SNPS_DC_HOME` 和 `VCS`。
  - 命令行显式赋值优先于默认值。
  - 远端没有设置 `SNPS_DC_HOME`；当前空壳 DUT 不使用 DW cell，因此暂时在构建目录
    提供空的 `dw/sim_ver` fallback。后续 RTL 使用 DW cell 时必须传入真实安装路径。

- [x] **BUILD-04：实现远端构建前置检查。**
  - 检查 Make 最终解析出的 `$(VCS)` 可执行，不假设命令固定为 `vcs`。
  - 检查 `AXI_VIP_DIR`、`SNPS_DC_HOME` 和所需 VIP package 文件。
  - 检查三个主 filelist：`shm_dut.f`、`shm_environment.f` 和 `shm_tbtop.f`，以及
    它们引用的文件。
  - `shm_common.f` 不属于当前远端 VCS 构建入口。
  - 缺失依赖时在进入 VCS 前给出具体路径。

- [x] **BUILD-05：确定 UVM 的唯一引入方式。**
  - 远端 VCS 使用 `-ntb_opts uvm-1.2`，不再显式编译 `shm_common.f`。
  - 远端不要求 `UVM_HOME`；本地 slang 后续继续使用仓库 `resources/` 中的 UVM 源码。

P0 编译基线（2026-08-02）：

- 远端 GNU Make 4.3，VCS `W-2024.09-SP1_Full64`。
- `AXI_VIP_DIR` 下的 `svt_axi.uvm.pkg` 与 `svt_mem.uvm.pkg` 均存在。
- `make preflight` 通过。
- `make compile` 已进入 UVM、`RpuCommon.sv` 和 `RpuShmTop.sv` 解析阶段。
- 用户补充空的 `$RPU_DIR/RhCommon/usr_ref.sv` 后，VCS 已继续完成 AXI VIP 和 memory
  VIP package 解析。
- 当前首个失败为旧路径 `ut_shm/env/collection/libs/collection_pkg.sv` 不存在，VCS
  返回 255；日志位于远端 `build/ut_shm/compile.log`。该失败属于 P1 的 `FLIST-01`。
- 本次使用 `--no-delete` 同步，远端仍残留本地已不存在的旧
  `ut_shm/env/shm_config_pkg.sv`。进入 P1 正式编译前，必须先确认远端是可对齐测试副本，
  再执行带删除同步，避免陈旧源码造成假通过或改变首错。

### P1：修复参数、工具 package 和 filelist 主干

- [ ] **UTIL-01：统一 package 名为 `shm_util_package`。**
  - 修改 `ut_shm/util/shm_util_package.sv` 的 package 声明。
  - 将 `shm_config_pkg::*`、`shm_util_pkg::*` 和旧的
    `shm_util_package::*` 使用点统一到最终名称。
  - 确认所有 interface、transaction、agent、environment 和 top 均从同一 package
    获取参数。

- [ ] **UTIL-02：接入 `sv-collection`。**
  - 在 filelist 中先编译 `collection_pkg.sv`。
  - 修复 `collections::*` 为 `collection::*`。
  - 使用 collection 类型的源码显式 import `collection::*` 或所需符号。
  - 不把 `collection_pkg.sv` include 到 `shm_util_package` 内部。

- [ ] **UTIL-03：解决缺失的 generated collection 头文件。**
  - 当前若干 array utility 会 include `generated/*.svh`。
  - 决定是恢复受版本控制的生成文件，还是在构建目录生成并添加 include 路径。
  - 生成动作必须可重复，且 `make clean` 能清理构建产物。

- [ ] **FLIST-01：按当前仓库结构重写 `shm_environment.f`。**
  - 删除 `ver_common/uvc/*`、旧 `vlm_agent`、旧 sequence 目录和旧 collection 目录。
  - 加入 `ver_common/shmins_agent`、`vlm_memory_agent`、
    `vlm_reservation_agent`、`clock` 和 `ut_shm/util/sv-collection`。
  - 加入新的 interface、package 和 test 文件。
  - 文件顺序符合第 3 节依赖关系。

- [ ] **FLIST-02：核对 `shm_dut.f` 引用。**
  - 以 `RhCommon`、`RpuCommon` 和 `RpuTop/src/RpuShm` 的当前混合路径为准。
  - 每个 `-f` 和显式源码路径均应存在。
  - 空 filelist 在本阶段可以保留，但应记录其用途。

- [x] **FLIST-03：处理 `$RPU_DIR/RhCommon/usr_ref.sv`。**
  - 用户已添加空占位文件，旧 environment filelist 可以继续解析。
  - 后续若不再需要该入口，可在整理 filelist 时再决定是否删除。

### P2：规范 `.svh`、include guard 和事务 package

- [ ] **HDR-01：统一声明型 `.svh` 的 include guard。**
  - 格式固定为 `INC_<FILE_NAME>_SVH`。
  - 修复缺少 `INC_`、残留 `_SV`、旧式双下划线和拼写错误的 guard。
  - 文件结束注释与 guard 名一致。

- [ ] **HDR-02：核对仍带 guard 的 `.sv` 文件。**
  - 若文件只应由 package include，则改为 `.svh`。
  - 若文件作为独立 compilation unit 编译，则移除不必要的 include 关系并避免重复定义。
  - 优先核对 `shmins_sequence_item.sv` 和 VLM memory agent 中的 class 文件。

- [ ] **SEQITEM-01：修复 `shm_seq_item_package`。**
  - include 实际存在的 SHMINS sequence item 文件。
  - 在 enum typedef 之后 include `shmins_enum_field.svh`。
  - 用 `vlm_memory_sequence_item` 替换不存在的 `vlm_sequence_item`。
  - 删除 `shmins_enum_fields.sv` 等失效文件名。

- [ ] **SEQITEM-02：修复 enum 字符串转换生成物。**
  - 为 `shmins_enum_field.svh` 增加规范 include guard。
  - 提供 `str_toupper()`，或让生成代码使用标准 string 大写转换方式。
  - 同步修复 `scripts/gen_enum_str.py`，避免下次生成重新引入错误。

- [!] **SEQITEM-03：统一 `creq_itype` 与遗留 `creq_ltype`。**
  - 当前 sequence item 和新文档使用 `creq_itype_e/creq_itype`。
  - 旧 sequence、reference 辅助类仍使用 `creq_ltype_e/creq_ltype`。
  - 推荐以 `creq_itype` 为标准；正式修改前确认不需要兼容旧外部 API。
  - 本项未解决前不得迁移 sequence、reference 和 scoreboard 类型依赖。

### P3：迁移 agent、environment 和 package

- [ ] **AGENT-01：修复 SHMINS agent 的编译级遗留问题。**
  - 统一所有 `shminus_*` 为 `shmins_*`。
  - 统一 monitor analysis port 的声明、构造、写入和连接名称。
  - 为类外定义的方法补齐类内 `extern` 声明。
  - 删除或修正无意义的生成式 debug 方法，但不改变必要的驱动和监测行为。

- [ ] **AGENT-02：将 VLM memory agent 纳入 package。**
  - `shm_seq_item_package` 提供 `vlm_memory_sequence_item`。
  - `shm_env_package` 按依赖顺序 include config、monitor、sequencer、driver 和 agent。
  - Config DB key 使用当前 agent API 的 `cfg` 和 `memory_vif`。

- [ ] **AGENT-03：将 VLM reservation agent 纳入环境。**
  - filelist 编译 `vlm_reservation_interface.sv` 和 `vlm_reservation_pkg.sv`。
  - `shm_env_package` import `vlm_reservation_pkg::*`。
  - environment 创建 `vlm_reservation_agent` 和 config。
  - config 同时持有 `reservation_vif` 与共享的 `memory_vif`。
  - scheduler、checker、coverage 和 monitor 获得正确的 `clk_vif`。

- [ ] **ENV-01：重写 `shm_environment_config`。**
  - 移除 `vlm_slv_agent_config` 和旧 `vlm_slv_*` 字段。
  - 增加 `vlm_memory_slv_agent_config` 与 `vlm_reservation_agent_config`。
  - 保留并规范 SHMINS active/passive 配置。
  - 必要 config 缺失时使用明确的 `UVM_FATAL`，避免报错后继续解引用 null。

- [ ] **ENV-02：重写 `shm_environment` 的 build/connect。**
  - 创建 SHMINS、VLM memory 和 VLM reservation 三个 agent。
  - 创建 reference 与 scoreboard。
  - 通过 config object 和 Config DB 向子组件传递 virtual interface。
  - SHMINS monitor analysis port 连接 reference。
  - VLM memory monitor write analysis port 连接 scoreboard。
  - VLM memory driver `mem_port` 连接 scoreboard `mem_imp`。
  - reference 输出连接 scoreboard 的 reference analysis export。

- [ ] **ENV-03：修复 reference、scoreboard 和转换工具的类型。**
  - 将旧 `vlm_sequence_item` 替换为 `vlm_memory_sequence_item`。
  - 更新 analysis export、FIFO、blocking transport 和局部变量的模板参数。
  - 修复 `shm_util_package` 与 `collection` import。
  - 本阶段只修复编译和连接，不重构 scoreboard 算法。

- [ ] **PKG-01：补全 `shm_env_package`。**
  - 删除所有旧 `.sv`/旧 VLM include。
  - 以基类和被依赖类型优先的顺序 include agent、config、reference、scoreboard 和
    environment。
  - 确保一个 class 只被一个 package 定义一次。

- [ ] **PKG-02：修复 `shm_seq_package` 与 `shm_test_package`。**
  - sequence package 仅 include 当前存在的 `.svh`。
  - 删除不存在且不再需要的 `vlm_slv_sequence`。
  - test package include base/unit test，并保证 UVM factory 注册完整。

### P4：重写 testbench top 和接口连接

- [ ] **TOP-01：替换旧 VLM interface。**
  - 删除 `vlm_interface`。
  - 实例化 `vlm_memory_interface(clk, rst_n)`。
  - 实例化 `vlm_reservation_interface(clk, rst_n)`。
  - 实例化共享 `clk_if`。

- [ ] **TOP-02：拆分 DUT 接线。**
  - DUT `mem_rvld/raddr/rdata` 和 `mem_wvld/waddr/wstrb/wdata` 接入
    `vlm_memory_interface`。
  - DUT `vlm_rreq/raddr/rdly`、`vlm_wreq/waddr/wdly` 和 busy 接入
    `vlm_reservation_interface`。
  - 保持 SHMINS creq/ack 接线。
  - 修复 `clck`、旧 `.sv` include 和宽度不一致等 top 级错误。

- [ ] **TOP-03：统一 Config DB 发布。**
  - 发布 `shmins_interface`。
  - 发布 `vlm_memory_interface`。
  - 发布 `vlm_reservation_interface`。
  - 发布 `clk_if`。
  - key、类型和 environment/agent 的 get 路径完全一致。

- [ ] **TOP-04：使 smoke test 不依赖 DUT 功能。**
  - 使用 `shm_unit_test` 加 `+TRANS_NUM=0`，或增加专用零事务 smoke test。
  - smoke test 只验证 UVM component build/connect 和仿真启动。
  - test 必须打印或以其他可检查方式证明 `TRANS_NUM=0` 已被解析并生效。
  - smoke 命令必须显式传递 `+UVM_TESTNAME`，并启用 topology 输出。
  - 设置有限仿真超时作为挂起保护；触发 timeout 应判定 smoke 失败。

### P5：语法检查、远端编译和仿真启动

- [ ] **CHECK-01：新增完整环境 slang 检查入口。**
  - 与现有 VLM memory slang 脚本分离或扩展为 `check_ut_shm_slang.sh`。
  - 使用 `resources/` 中的 UVM。
  - 对本地缺失的 Synopsys VIP 明确采用“排除 VIP 依赖文件”或最小声明 stub，不能掩盖
    package/include 顺序错误。
  - 每次检查输出实际检查的源文件清单、stub 清单和排除项清单。
  - 构建产物放在临时或专用 build 目录。

- [ ] **CHECK-02：运行分层本地检查。**
  - 第一层：utility、sequence item 和 interface。
  - 第二层：三个 agent package。
  - 第三层：不依赖真实 VIP 实现的 environment/top 语法。
  - 保存并逐项修复 slang 的首个根因错误，避免只处理级联错误。

- [ ] **REMOTE-01：检查远端环境。**
  - 先使用 `scripts/sync_remote_repo.sh --dry-run` 审查同步范围，再同步本地工作区。
  - 确认远端 `sharemem` 是允许被 rsync `--delete` 对齐的测试副本；否则使用
    `--no-delete`。
  - 使用 `scripts/run_remote_command.sh` 检查 Make 最终解析出的 `VCS`、`AXI_VIP_DIR`、
    `SNPS_DC_HOME` 和 UVM。
  - 不在远端修改源文件；所有修复先在本地完成。

- [ ] **REMOTE-02：运行远端 VCS 编译。**
  - 在仓库根目录执行 `make preflight`。
  - 从空的专用构建目录开始，避免陈旧 `simv` 或中间产物造成假通过。
  - 在仓库根目录执行 `make compile`。
  - 编译日志必须保存到 build 目录。
  - 按 package 未找到、include 未找到、类型未定义、接口宽度、Config DB 类型和
    elaboration 顺序分类处理错误。

- [ ] **REMOTE-03：启动 smoke 仿真。**
  - 在仓库根目录执行 `make smoke`。
  - 日志证明 factory 创建了目标 test、实际 top 为 `shm_tb_top`、进入 UVM run phase，
    并且零事务设置已经生效。
  - topology 逐项包含 SHMINS agent、VLM memory agent、VLM reservation agent、
    reference 和 scoreboard。
  - smoke 进程正常结束且返回值为 0；`UVM_FATAL` 和 `UVM_ERROR` 均为 0。
  - `UVM_WARNING` 可以存在，但必须记录；timeout 或非零返回值一律视为失败。

- [ ] **REMOTE-04：整理最终结果。**
  - 记录实际使用的 VCS、UVM 和 VIP 版本及环境路径。
  - 记录完整 compile/smoke 命令和退出码。
  - 保存完整日志，并记录日志路径、生成物路径、剩余 warning 和延期功能问题。
  - 确认源码和 docs 目录中没有 VCS 生成物。

## 5. 实施过程 Checklist

### 修改前

- [ ] `git status --short` 已记录，用户已有修改不会被覆盖。
- [ ] 用户已明确授权开始当前待执行阶段；P0 授权不自动扩展到 P1～P5。
- [ ] 已确认当前 `ut_shm.cfg`、`shm_dut.f`、`shm_environment.f`、
  `shm_tbtop.f` 和目标 package 内容。
- [ ] 已确认 `shm_util_package` 是唯一公共参数 package。
- [ ] 已确认本阶段只要求编译、elaboration 和启动 smoke 仿真。
- [ ] `SEQITEM-03` 等当前阶段的阻断决策已经关闭。

### 每批 package/include 修改后

- [ ] 所有 include 文件实际存在，大小写与扩展名准确。
- [ ] 所有 `.svh` guard 符合 `INC_<FILE_NAME>_SVH`。
- [ ] package 内 include 顺序满足类型依赖。
- [ ] filelist 不会把已被 package include 的 class 文件再次作为 compilation unit 编译。
- [ ] 不存在旧 `vlm_interface`、`vlm_slv_agent`、`vlm_sequence_item` 的有效引用。
- [ ] 不存在旧 `shm_config_pkg` 或错误的 `shm_util_pkg` import。
- [ ] `collection` 的 package 名和 import 名一致。

### agent/environment 集成后

- [ ] SHMINS interface、config、driver、sequencer、monitor 和 agent 类型可见。
- [ ] VLM memory interface、config、driver、sequencer、monitor 和 agent 类型可见。
- [ ] VLM reservation interface、config、scheduler、checker、coverage、monitor 和 agent
  类型可见。
- [ ] memory 和 reservation agent 使用同一个 `vlm_memory_interface` 实例。
- [ ] reservation agent 独占 reservation busy 驱动职责。
- [ ] memory driver 独占 `mem_rdata` 驱动职责。
- [ ] 每个 Config DB `set` 都有类型、key 和层级匹配的 `get`。
- [ ] 所有 TLM port/export/imp 的 transaction 类型一致。

### 本地检查后

- [ ] slang 返回值为 0。
- [ ] 已保存 slang 实际覆盖的文件、stub 和排除项清单。
- [ ] 没有缺失 package、include 或未知类型错误。
- [ ] 本地 VIP 限制已明确记录，没有把 VIP 专有 API 误判为已验证。
- [ ] 检查产物不在源码或 docs 目录。

### 远端编译后

- [ ] `AXI_VIP_DIR` 指向有效 Synopsys VIP 安装目录。
- [ ] `make preflight` 通过。
- [ ] VCS compile/elaboration 返回值为 0。
- [ ] 编译从空构建目录开始，日志能证明 `simv` 是本次生成。
- [ ] `simv` 已生成在专用 build 目录。
- [ ] 编译日志没有 unresolved package/module/class/interface。
- [ ] 所有 warning 已记录，未把 warning 静默过滤。

### smoke 仿真后

- [ ] `make smoke` 和 `simv` 进程返回值均为 0。
- [ ] 仿真程序能够启动并进入 UVM phases。
- [ ] `shm_tb_top` 是实际 elaborated top。
- [ ] `shm_unit_test` 或专用 smoke test 能被 factory 创建。
- [ ] UVM topology 包含目标环境组件。
- [ ] 日志证明 `TRANS_NUM=0` 或等效零事务配置已经生效。
- [ ] `UVM_FATAL` 和 `UVM_ERROR` 计数均为 0。
- [ ] 仿真能在零事务模式下正常退出，且没有触发挂起保护 timeout。

## 6. 已知脱节点与延期项

以下内容已经发现，但除非阻止编译或仿真启动，否则不在本阶段展开：

- `docs/ut_shm_test_plan.md` 仍使用旧 VLM agent 名称、旧目录和
  `shm_config_pkg`。
- 测试计划中的 8KB/13bit/20bit 参数与当前源码中的
  12KB/14bit/21bit 参数不一致；本阶段以当前源码和
  `shm_util_package` 为编译基准，功能参数需要后续单独确认。
- `RpuShmTop` 当前只有端口壳，没有可验证的内部行为。
- reference/scoreboard 的读请求、outstanding 和覆盖写算法不作为本阶段验收内容。
- reservation checker/coverage 的功能结果不作为本阶段验收内容。
- `examples/vlm_reservation_compile` 是局部集成参考，不是正式 `ut_shm` 构建入口。
- scoreboard 中可能存在数组循环边界和旧 transaction API 等功能问题；只有造成编译或
  启动失败的部分在本阶段修复。

## 7. 完成判定

当以下命令在对应环境中稳定通过时，本阶段可以结束：

```text
# 本地
scripts/check_ut_shm_slang.sh

# 远端
scripts/sync_remote_repo.sh --dry-run
# 已确认远端是可被 --delete 对齐的测试副本时
scripts/sync_remote_repo.sh
# 否则改用：scripts/sync_remote_repo.sh --no-delete
scripts/run_remote_command.sh make preflight
scripts/run_remote_command.sh make compile
scripts/run_remote_command.sh make smoke
```

最终交付应包含：修复后的源码和 filelist、仓库根目录 `Makefile`、作为参数参考保留的
`ut_shm.cfg`、本地 slang 检查脚本，以及远端 compile/smoke 日志摘要。
