# ut_shm 使用指南

本目录收集可以直接执行的构建、运行和调试方法。指南会以当前根 `Makefile`、本地
Slang 脚本和远端 VCS 环境为准，不再沿用旧文档中的 `rpu_sim` 流程。

## 文档状态

|文档|内容|状态|
|---|---|---|
|`build-and-run.md`|环境检查、本地 Slang、远端 VCS、Makefile、case 和 regression|待迁移|
|`configuration-reference.md`|环境变量、Makefile 变量和 plusarg 的集中定义|待迁移|
|`debug-guide.md`|按报错现象整理的日志、波形和定位方法|待迁移|

## 阅读顺序

第一次运行先读 `build-and-run.md`。需要修改环境变量或仿真参数时查
`configuration-reference.md`；命令能够启动但编译或仿真报错时，再按现象进入
`debug-guide.md`。在正文发布前，直接以根 `Makefile` 和 `scripts/` 中的当前脚本为准。
