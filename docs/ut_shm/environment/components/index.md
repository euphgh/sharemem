# ut_shm 组件文档

本目录记录各 UVM 组件的实现和开发约束。每篇文档会说明输入输出、配置、phase、
内部状态、检查行为和调试观察点；进入单个组件前，可以先通过
[总体架构](../architecture.md)确认连接，再从[数据流与数据模型](../data-flow-and-models.md)
确认共享对象的所有权。DUT 端口时序不在这里重复定义，应查看
[DUT 规范](../../spec/index.md)。

## 文档状态

|文档|组件|状态|
|---|---|---|
|[Environment](shm-environment.md)|`shm_environment` 及其配置、创建和连接|已发布|
|[SHMINS master agent](shmins-mst-agent.md)|creq 激励、ack 观察和 shmins transaction|已发布|
|[VLM memory agent](vlm-memory-agent.md)|MEM monitor、slave driver、sequencer 和读数据返回|已发布|
|[Reference](shm-reference.md)|期望事务和 reference memory 的生成|已发布|
|[Scoreboard](shm-scoreboard.md)|outstanding 新算法、实际 memory 和 timeout 调试|已发布|
|[VLM reservation agent](vlm-reservation-agent.md)|monitor、checker、coverage、scheduler 和 busy 驱动|已发布|

## 阅读顺序

修改环境连接时先读 [Environment](shm-environment.md)。其余组件按数据路径选择：
creq 入口从 [SHMINS master agent](shmins-mst-agent.md)开始，数据比对继续读
[Reference](shm-reference.md)和 [Scoreboard](shm-scoreboard.md)；MEM 端口问题读
[VLM memory agent](vlm-memory-agent.md)，reservation 时序问题读
[VLM reservation agent](vlm-reservation-agent.md)。

组件文档描述当前结构和开发 contract。实现缺口、优先级和验收方法统一维护在
[验证实现状态](../../verification-status.md)，不在各组件正文中分别维护修复进度。
