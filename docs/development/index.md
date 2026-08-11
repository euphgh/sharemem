# ShareMemory 开发规范

本目录收录仓库级开发约定。DUT 协议、验证环境架构和具体组件 contract
仍由 [ut_shm 验证文档](../ut_shm/index.md) 和源码注释定义，这里不重复设计行为。

## 当前规范

- [SystemVerilog/UVM 开发规范](systemverilog-code-style.md)：文件、package、class、API、
  注释、UVM 报告和修改后检查要求。
- [shmins sequence item 拆分开发计划](shmins-sequence-item-refactor-plan.md)：按地址生成
  形态拆分 transaction、构造合法 offset，并在 hx16 上通过独立 benchmark 验收的阶段方案。

规范对新增代码和本次实际修改的代码生效。现有 legacy 代码不要因为无关的
功能修改而整文件重排；后续 refactor 时再逐步收敛。
