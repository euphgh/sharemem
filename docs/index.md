# ShareMemory 文档

这里是 ShareMemory 仓库的文档入口。当前主要内容是 RpuShmTop 的 ut_shm 验证
环境；详细文档正在从 `docs-old/` 迁移，已经发布的入口可以直接阅读，尚未迁移的
正文会在索引中标明状态。

## 验证环境

- [ut_shm 验证文档](ut_shm/index.md)：DUT 规范、验证环境、组件实现、验证计划和
  使用指南的总入口。

## 开发规范

SystemVerilog/UVM 编码规范将在迁移阶段 7 发布到
`development/systemverilog-code-style.md`。在此之前，根 `AGENTS.md` 保留一条
指向旧规范的过渡链接。

## 文档迁移

旧文档仍保存在 `docs-old/`，只作为迁移输入，不在其中继续维护设计正文。迁移的
目录设计和执行顺序见[迁移计划](../docs-old/documentation-migration-plan.md)，已经
确认的旧名称、失效路径和当前代码清单见
[阶段 0 基线](../docs-old/documentation-migration-baseline.md)。
