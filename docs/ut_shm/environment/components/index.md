# ut_shm 组件文档

本目录记录各 UVM 组件的实现和开发约束。每篇文档会说明输入输出、配置、phase、
内部状态、检查行为和调试观察点；DUT 端口时序不在这里重复定义，应先查看
[DUT 规范](../../spec/index.md)。

## 文档状态

|文档|组件|状态|
|---|---|---|
|`shm-environment.md`|`shm_environment` 及其配置、创建和连接|待迁移|
|`shmins-mst-agent.md`|creq 激励、ack 观察和 shmins transaction|待迁移|
|`vlm-memory-agent.md`|MEM monitor、slave driver、sequencer 和读数据返回|待迁移|
|`shm-reference.md`|期望事务和 reference memory 的生成|待迁移|
|`shm-scoreboard.md`|outstanding 新算法、实际 memory 和 timeout 调试|待迁移|
|`vlm-reservation-agent.md`|monitor、checker、coverage、scheduler 和 busy 驱动|待迁移|

## 阅读顺序

修改环境连接时先读 `shm-environment.md`。其余组件按数据路径选择：creq 入口从
`shmins-mst-agent.md` 开始，数据比对继续读 `shm-reference.md` 和
`shm-scoreboard.md`；MEM 端口问题读 `vlm-memory-agent.md`，reservation 时序问题读
`vlm-reservation-agent.md`。
