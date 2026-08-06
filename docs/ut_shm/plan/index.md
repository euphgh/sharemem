# ut_shm 验证计划

本目录回答三个问题：需要验证哪些行为，哪些 case 负责产生这些场景，覆盖率达到
什么条件才算收敛。接口规则来自 [DUT 规范](../spec/index.md)，编译和运行命令放在
[使用指南](../guide/index.md)。

## 文档状态

|文档|内容|状态|
|---|---|---|
|`testpoints.md`|功能点、激励、观察点、checker、coverage、case 和状态的对应关系|待迁移|
|`testcases-and-regression.md`|case 分类、命名、约束、seed 和 regression 组织|待迁移|
|`coverage-and-closure.md`|功能覆盖、代码覆盖、断言覆盖、waiver 和完成条件|待迁移|

## 阅读顺序

先从 `testpoints.md` 找到待验证行为及其检查方法，再到
`testcases-and-regression.md` 选择或新增 case。准备关闭功能点时，使用
`coverage-and-closure.md` 检查覆盖缺口和 waiver。运行参数不在这些文档中重复列出。
