# ut_shm 验证文档

本页整理 ut_shm 的文档分区和阅读路线。DUT 规范、环境架构、数据模型、组件实现、
验证计划、使用指南和当前状态已经完成迁移；后续开发仍应先查看状态文档中的已知
实现差异。

## 文档分区

|分区|内容|状态|
|---|---|---|
|[DUT 规范](spec/index.md)|RpuShmTop 的双 gid BANK、地址模型、creq/ack、MEM 和 VLM reservation 接口|双 gid contract 已发布|
|[验证环境](environment/index.md)|tb top、统一 VLM 架构、数据流和各组件实现|双 gid 主路径已接入并通过 85-case 真实 RTL 回归|
|[验证计划](plan/index.md)|testpoint、testcase、regression 和覆盖闭环|Phase 5 三篇正文已发布|
|[使用指南](guide/index.md)|三环境边界、代码流转、Slang/VCS 检查、配置和调试|Phase 6 正文已发布|
|[当前状态](verification-status.md)|实现差异、优先级、处理状态和验收方法|持续维护；已记录 85-case 真实 RTL 回归里程碑|

## 顺序阅读

第一次接触环境时，建议按下面的顺序阅读：

1. 从 [DUT 概览](spec/dut-overview.md)了解模块边界，再阅读
   [地址模型](spec/address-model.md)和对应接口规范；
2. 阅读 [验证环境](environment/index.md)，弄清 interface、UVM 组件和数据连接；
3. 进入 [验证计划](plan/index.md)，查看功能点如何映射到 checker、coverage 和 case；
4. 需要编译、运行或定位问题时，再看 [使用指南](guide/index.md)；
5. 用[当前状态](verification-status.md)确认实现差异、优先级和验收方法。

## 按任务查找

|任务|阅读入口|后续目标文档|
|---|---|---|
|理解 DUT|[DUT 概览](spec/dut-overview.md)|[地址模型](spec/address-model.md) → [creq/ack](spec/creq-ack-interface.md)或 [MEM/VLM](spec/mem-vlm-interface.md)|
|修改地址映射或 reference|[地址模型](spec/address-model.md) → [数据流与数据模型](environment/data-flow-and-models.md)|[Reference](environment/components/shm-reference.md)|
|修改 scoreboard|[总体架构](environment/architecture.md) → [数据流与数据模型](environment/data-flow-and-models.md)|[Scoreboard](environment/components/shm-scoreboard.md) → [Testpoint](plan/testpoints.md)|
|修改 VLM memory agent|[MEM/VLM 接口](spec/mem-vlm-interface.md) → [总体架构](environment/architecture.md)|[VLM memory agent](environment/components/vlm-memory-agent.md)|
|修改 reservation agent|[MEM/VLM 接口](spec/mem-vlm-interface.md) → [总体架构](environment/architecture.md)|[VLM reservation agent](environment/components/vlm-reservation-agent.md)|
|新增 testcase|[Testpoint](plan/testpoints.md) → [Testcase 与 regression](plan/testcases-and-regression.md)|[使用指南](guide/index.md) → `configuration-reference.md`|
|编译或运行|[使用指南](guide/index.md)|执行环境 → 对应检查手册 → 配置参考 → 调试指南|
|查看未完成功能|[当前状态](verification-status.md)|问题 ID → 对应 spec 或组件文档|

使用指南中的 macOS 和 Ubuntu 命令以仓库脚本为准；CentOS 的最终运行命令由服务器
自有框架维护，不在本仓库复制。
