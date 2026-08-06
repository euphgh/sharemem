# ut_shm 验证环境

本目录解释 testbench 如何实例化和连接，以及 transaction 和 memory model 在组件
之间如何流动。总体架构、数据模型和组件文档已经完成迁移；组件内部状态机和算法放在
[组件文档](components/index.md)，DUT 的协议规则由 [DUT 规范](../spec/index.md)维护。

## 文档状态

|文档|内容|状态|
|---|---|---|
|[总体架构](architecture.md)|tb top、UVM hierarchy、interface、Config DB、TLM 和 phase|已发布|
|[数据流与数据模型](data-flow-and-models.md)|共享 transaction、memory model、数据所有权和跨组件数据流|已发布|
|[组件文档](components/index.md)|environment、agent、reference 和 scoreboard 的实现说明|六篇正文已发布|

## 阅读顺序

先用[总体架构](architecture.md)看清层次和连接，再读
[数据流与数据模型](data-flow-and-models.md)追踪一笔事务。确认共享数据由谁创建、
修改和消费之后，再进入对应的组件文档。这样能把环境连接问题和组件算法问题分开
排查。
