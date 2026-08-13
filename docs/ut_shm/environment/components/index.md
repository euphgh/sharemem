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
|[VLM memory agent](vlm-memory-agent.md)|统一 VLM agent 内的 MEM monitor/driver 与可信数据边界|正向主路径已通过 85-case 真实 RTL 回归，定向验证待补|
|[Reference](shm-reference.md)|期望事务和 reference memory 的生成|已发布|
|[Scoreboard](shm-scoreboard.md)|outstanding 新算法、实际 memory 和 timeout 调试|已发布|
|[统一 VLM agent 的 reservation 路径](vlm-reservation-agent.md)|统一 monitor、resolver、checker、coverage、scheduler、busy 和 read driver|正向主路径已通过 85-case 真实 RTL 回归|

## 阅读顺序

修改环境连接时先读 [Environment](shm-environment.md)。其余组件按数据路径选择：
creq 入口从 [SHMINS master agent](shmins-mst-agent.md)开始，数据比对继续读
[Reference](shm-reference.md)和 [Scoreboard](shm-scoreboard.md)；MEM 端口问题读
[VLM memory agent](vlm-memory-agent.md)，reservation 时序问题读
[VLM reservation agent](vlm-reservation-agent.md)。

组件文档描述当前结构和开发 contract。实现缺口、优先级和验收方法统一维护在
[验证实现状态](../../verification-status.md)，不在各组件正文中分别维护修复进度。
