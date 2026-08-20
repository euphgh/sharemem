# shm_environment

本文说明当前双 gid 架构中 `shm_environment` 如何创建两个 agent、reference 和
scoreboard，并把 tb top
发布的 virtual interface 与各组件连接起来。整体层次和跨组件数据流分别见
[环境总体架构](../architecture.md)与[数据流和数据模型](../data-flow-and-models.md)。

## 1. 职责边界

`shm_environment` 是 ut_shm 的组合层，负责：

- 获取并校验 environment config、shmins/VLM business interface 和共享 cycle interface；
- 创建 shmins 和统一 VLM 两个 agent；
- 在完整 active 模式下创建 `shm_reference`、`shm_scoreboard` 和 transaction lifecycle
  checker，以及第一批双 gid `shm_address_coverage`；
- 下发 agent config、business vif 和共享 `clk_vif`；
- 建立 creq、raw ack、scoreboard completion、期望写、实际写和 MEM read service 的
  TLM 连接；
- 为 testcase 提供 clock-based `is_idle()` 和 `wait_for_idle()`。

它不生成 creq、不实现地址映射、不维护 memory 内容，也不执行 reservation 或数据
检查。这些行为分别属于 sequence/agent、reference、scoreboard 和 reservation agent。

## 2. 主要源文件

|文件|作用|
|---|---|
|`ut_shm/env/shm_environment.svh`|environment build/connect 实现|
|`ut_shm/env/shm_environment_config.svh`|顶层环境、agent、timeout 和 drain 配置对象|
|`ut_shm/env/shm_address_coverage.svh`|只读采样 reference 派生逻辑/物理地址和 M2V gid 关系|
|`ut_shm/env/shm_transaction_lifecycle_checker.svh`|accepted creq、ack 与数据完成关联|
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

Scoreboard 和 lifecycle 的中途诊断、以及 testcase drain watchdog 都以共享 clock cycle
配置；具体 plusarg 见[配置参考](../../guide/configuration-reference.md#4-ut_shm-仿真-plusarg)。

## 4. `build_phase`

Environment 按以下顺序建立依赖：

1. 获取字段名为 `shm_environment_config` 的 config；
2. 确认 `init()` 已创建两个 agent config；
3. 获取 `shmins_vif`、统一 `vlm_vif` 和 `clk_vif`；
4. 把统一 VLM vif 和 cycle source 写入 VLM config；
5. 分别向两个 agent 设置 `cfg` 和需要的 vif；
6. 创建两个 agent；
7. 当 `shm_is_active==UVM_ACTIVE` 时创建 reference、scoreboard、lifecycle checker 和
   address coverage，并向需要配置的组件下发 environment config。

缺少 config、子 config 或 virtual interface 都使用带有明确 ID 的 `UVM_FATAL`，避免
环境在半连接状态继续运行。主要 ID 包括 `SHM_ENV_NO_CFG`、
`SHM_ENV_CFG_NOT_INITIALIZED`、`SHM_ENV_NO_SHMINS_VIF`、`SHM_ENV_NO_VLM_VIF` 和
`SHM_ENV_NO_CLK_VIF`。迁移代码时应同步替换旧 memory/reservation vif error ID。

## 5. `connect_phase`

|源|目标|条件|
|---|---|---|
|shmins monitor analysis port|reference analysis imp|两端实例都存在|
|shmins monitor analysis port|lifecycle accept imp|两端实例都存在|
|shmins monitor raw ack port|lifecycle ack imp|两端实例都存在|
|统一 VLM monitor write analysis port|scoreboard RTL analysis export|两端实例都存在且 transaction 已完成 reservation match|
|统一 VLM agent blocking transport port|scoreboard `mem_imp`|两端实例都存在且 MEM gid/match 有效|
|reference expected-write analysis port|scoreboard reference analysis export|两端实例都存在|
|reference expected-write analysis port|address coverage analysis export|两端实例都存在|
|scoreboard completion port|lifecycle completion imp|两端实例都存在|

Reservation agent 不通过 environment TLM 与 scoreboard 相连。它直接读取 reservation
和 MEM interface，在 agent 内完成周期同步检查。

双 gid 架构已将 memory/reservation interface 和 monitor 合并为统一 VLM agent。
Environment 只配置一个 `vlm_vif`；实际 write 和 read service transaction 都先由唯一
到期 reservation record 补全 gid，再连接 scoreboard。

## 6. Phase、drain 与 reset

`shm_environment` 使用共享 `clk_if.cycle_count`；该计数不随 reset 清零。`is_idle()`
联合检查 scoreboard、transaction lifecycle、reservation scheduler 和 pending MEM read
response。`wait_for_idle()`
至少连续两个 clock cycle 观察到 idle 才返回，避免最后一笔 monitor/FIFO delta-cycle
传播尚未完成时提前结束。超过 `TEST_DRAIN_TIMEOUT_CYCLES` 只报告 testbench drain hang，
不定义 DUT 单笔事务的最大完成时延。

`shm_unit_test` 已用 `wait_for_idle()` 替代固定 `#200ns` test tail。

当前只有初始 reset 启动门控，运行中 reset 的统一清理尚未实现，见 `ENV-001`。

## 7. 调试观察点

环境连接问题应先查看：

- UVM topology 中 shmins/统一 VLM 两个 agent、`shm_ref`、`shm_scb` 是否存在；
- fatal ID 指向的 Config DB 字段是否设置；
- `shm_environment_config.init()` 是否在 environment 子组件 build 前调用；
- drain timeout 时 scoreboard、lifecycle 和 reservation scheduler 的 pending state；
- 统一 VLM agent 的 `mem_port` 是否连接到 scoreboard；
- reservation agent 是否同时取得 reservation 和 memory vif。

## 8. 相关测试

`ut_shm/tests/shm_unit_test.svh` 是当前完整 environment 的集成入口：启动
`shmins_mst_unit_sequence`，并依赖两个 agent、reference 和 scoreboard 共同工作。当前没有
针对 Config DB 缺失、unsupported passive 组合或运行中 reset 清理的 environment 定向
测试；这些场景分别由 `ENV-002` 和 `ENV-001` 的验收项追踪。

2026-08-14 在远端执行根目录 `make smoke`，空 design 完成 parse、elaboration、link 和
0-transaction UVM run，结果为 `UVM_CASE_PASS` 且 0 error/fatal。该结果只证明新增 coverage
和定向 sequence 的 package/include/TLM 连接正确，不作为 DUT 行为证据。

## 9. 开发 contract

- Config DB 字段名和实例路径属于环境连接 contract，改名必须同步设置者与获取者。
- Reference/scoreboard 必须成对创建，memory read service 不能留下未连接的 required
  blocking port。
- 新增跨组件 transaction 时，应先在环境数据流文档定义所有权，再添加 TLM 连接。
- Test tail 必须等待 environment drain，不得用固定 simulation time 推断所有事务完成。
- Environment 不复制 DUT 协议规则，也不承担组件内部 checker 功能。
- 现阶段对 passive 配置应明确拒绝，不允许静默构造部分 active 的层次。

## 10. 当前实现状态

- 统一 VLM environment 和 shmins/reference/scoreboard 正向主路径已在真实 design 上通过
  `shm.lst` 全部 109 个 case；当前接口为 `VEC_W=256`、`VEC_BYTE_N=32`，列表包含
  新增的 24 个 strided case。`DBANK-003` 和 `SHMINS-007` 已关闭。
- `ENV-001`：运行中 reset 尚未统一清理。
- `ENV-002`：公开配置仍能表达当前不支持的 passive 组合。
- 第一批 `shm_address_coverage` 已接入 reference fanout；正式 RTL coverage报告得到
  `address_cg=89.88%`、`m2v_gid_cg=91.67%`，仍需分析并补齐未命中bin/cross。

问题详情和验收方法见[验证实现状态](../../verification-status.md)。
