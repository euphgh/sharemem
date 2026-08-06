# ShareMemory 文档

这里是 ShareMemory 仓库的文档入口。当前主要内容是 RpuShmTop 的 ut_shm 验证
环境；DUT 规范、验证环境、验证计划、使用指南和开发规范均已迁移到当前
`docs/` 结构。

## 验证环境

- [ut_shm 验证文档](ut_shm/index.md)：DUT 规范、验证环境、组件实现、验证计划和
  使用指南的总入口。

## 开发规范

- [开发规范](development/index.md)：新增或被修改的 SystemVerilog/UVM 代码所需遵循的
  文件、API、注释和检查要求。

## 文档迁移

旧文档仍保存在 `docs-old/`，只作为已完成迁移的一致性验收输入，不在其中继续维护
设计正文。迁移阶段和最终核对结果见
[迁移计划](../docs-old/documentation-migration-plan.md)，已经确认的旧名称、失效路径
和代码基线见[阶段 0 基线](../docs-old/documentation-migration-baseline.md)。是否继续
保留 `docs-old/` 由迁移验收后另行决定。
