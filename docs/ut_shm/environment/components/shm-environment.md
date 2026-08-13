# shm_environment

本文说明当前双 gid 架构中 `shm_environment` 如何创建两个 agent、reference 和
scoreboard，并把 tb top
发布的 virtual interface 与各组件连接起来。整体层次和跨组件数据流分别见
[环境总体架构](../architecture.md)与[数据流和数据模型](../data-flow-and-models.md)。

## 1. 职责边界

`shm_environment` 是 ut_shm 的组合层，负责：

- 获取并校验 environment config、shmins/VLM business interface 和共享 cycle interface；
- 创建 shmins 和统一 VLM 两个 agent；
- 在完整 active 模式下创建 `shm_reference` 和 `shm_scoreboard`；
- 下发 agent config、business vif 和共享 `clk_vif`；
- 建立 creq、期望写、实际写和 MEM read service 的 TLM 连接。

它不生成 creq、不实现地址映射、不维护 memory 内容，也不执行 reservation 或数据
检查。这些行为分别属于 sequence/agent、reference、scoreboard 和 reservation agent。

## 2. 主要源文件

|文件|作用|
|---|---|
|`ut_shm/env/shm_environment.svh`|environment build/connect 实现|
|`ut_shm/env/shm_environment_config.svh`|顶层环境和两个 agent 的配置对象|
|`ut_shm/env/shm_env_package.sv`|按依赖顺序 include agent、reference、scoreboard 和 environment|
|`ut_shm/tb/shm_ut_connect.svh`|从 tb top 向 Config DB 发布 virtual interface|
|`ut_shm/tests/shm_base_test.svh`|创建 config 和实例名为 `shm_env` 的 environment|

## 3. 配置对象

`shm_environment_config.init()` 创建：

- `shmins_mst_agent_config`；
- `vlm_agent_config`。

当前支持边界是完整 active 环境。`env_is_active` 会传给 shmins 和统一 VLM agent，
`shm_is_active` 控制 reference/scoreboard 是否创建，但这些 knob 不能组成完整 passive
模式。开发时不得把某个字段存在解释成该组合已经受支持。

VLM config 的统一 `vlm_vif` 和 `clk_vif` 由 environment 在 build 阶段写入，所有
VLM 子组件使用同一份 handle。

## 4. `build_phase`

Environment 按以下顺序建立依赖：

1. 获取字段名为 `shm_environment_config` 的 config；
2. 确认 `init()` 已创建两个 agent config；
3. 获取 `shmins_vif`、统一 `vlm_vif` 和 `clk_vif`；
4. 把统一 VLM vif 和 cycle source 写入 VLM config；
5. 分别向两个 agent 设置 `cfg` 和需要的 vif；
6. 创建两个 agent；
7. 当 `shm_is_active==UVM_ACTIVE` 时创建 reference 和 scoreboard，并向二者下发
   environment config。

缺少 config、子 config 或 virtual interface 都使用带有明确 ID 的 `UVM_FATAL`，避免
环境在半连接状态继续运行。主要 ID 包括 `SHM_ENV_NO_CFG`、
`SHM_ENV_CFG_NOT_INITIALIZED`、`SHM_ENV_NO_SHMINS_VIF`、`SHM_ENV_NO_VLM_VIF` 和
`SHM_ENV_NO_CLK_VIF`。迁移代码时应同步替换旧 memory/reservation vif error ID。

## 5. `connect_phase`

|源|目标|条件|
|---|---|---|
|shmins monitor analysis port|reference analysis imp|两端实例都存在|
|统一 VLM monitor write analysis port|scoreboard RTL analysis export|两端实例都存在且 transaction 已完成 reservation match|
|统一 VLM memory driver blocking transport port|scoreboard `mem_imp`|两端实例都存在且 read gid 有效|
|reference expected-write analysis port|scoreboard reference analysis export|两端实例都存在|

Reservation agent 不通过 environment TLM 与 scoreboard 相连。它直接读取 reservation
和 MEM interface，在 agent 内完成周期同步检查。

双 gid 架构已将 memory/reservation interface 和 monitor 合并为统一 VLM agent。
Environment 只配置一个 `vlm_vif`；实际 write 和 read service transaction 都先由唯一
到期 reservation record 补全 gid，再连接 scoreboard。

## 6. Phase 与 reset

`shm_environment` 自身只实现 `build_phase` 和 `connect_phase`。运行期行为由其子组件
负责。共享 `clk_if.cycle_count` 不随 reset 清零；业务组件必须依据各自 business
interface 的 `rst_n` 处理 reset。

当前只有初始 reset 启动门控，运行中 reset 的统一清理尚未实现，见 `ENV-001`。

## 7. 调试观察点

环境连接问题应先查看：

- UVM topology 中 shmins/统一 VLM 两个 agent、`shm_ref`、`shm_scb` 是否存在；
- fatal ID 指向的 Config DB 字段是否设置；
- `shm_environment_config.init()` 是否在 environment 子组件 build 前调用；
- memory driver 的 `mem_port` 是否连接到 scoreboard；
- reservation agent 是否同时取得 reservation 和 memory vif。

## 8. 相关测试

`ut_shm/tests/shm_unit_test.svh` 是当前完整 environment 的集成 smoke：启动
`shmins_mst_unit_sequence`，并依赖两个 agent、reference 和 scoreboard 共同工作。当前没有
针对 Config DB 缺失、unsupported passive 组合或运行中 reset 清理的 environment 定向
测试；这些场景分别由 `ENV-002` 和 `ENV-001` 的验收项追踪。

## 9. 开发 contract

- Config DB 字段名和实例路径属于环境连接 contract，改名必须同步设置者与获取者。
- Reference/scoreboard 必须成对创建，memory read service 不能留下未连接的 required
  blocking port。
- 新增跨组件 transaction 时，应先在环境数据流文档定义所有权，再添加 TLM 连接。
- Environment 不复制 DUT 协议规则，也不承担组件内部 checker 功能。
- 现阶段对 passive 配置应明确拒绝，不允许静默构造部分 active 的层次。

## 10. 当前实现状态

- 统一 VLM environment 和 shmins/reference/scoreboard 主路径已于 2026-08-13 在真实 RTL
  集成 testcase 中跑通。
- `ENV-001`：运行中 reset 尚未统一清理。
- `ENV-002`：公开配置仍能表达当前不支持的 passive 组合。

问题详情和验收方法见[验证实现状态](../../verification-status.md)。
