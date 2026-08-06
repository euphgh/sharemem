# ut_shm 使用指南

本目录按执行环境组织 ut_shm 的代码交付、语法检查、VCS 编译和调试方法。macOS、
Ubuntu 与 CentOS 拥有不同的工具和文件可见性；任何命令都必须先确认执行环境，不能
把低一级检查结果当成完整 DUT 或 regression 结论。

## 文档地图

|文档|内容|
|---|---|
|[执行环境](execution-environments.md)|三个环境的工具、文件可见性、权限和验证证据等级|
|[工作区流转](workspace-transfer.md)|macOS 到 Ubuntu/CentOS 的同步、上传和远程执行边界|
|[macOS Slang 检查](macos-slang-check.md)|本地可执行的语法检查及其局限|
|[Ubuntu VCS 检查](ubuntu-vcs-check.md)|伪 design 全环境编译、smoke 和 reservation 组件测试|
|[配置参考](configuration-reference.md)|脚本环境变量、Makefile 变量和仿真 plusarg|
|[调试指南](debug-guide.md)|按同步、编译和运行现象组织的定位方法|

## 按任务进入

|任务|阅读路径|
|---|---|
|判断一项检查应在哪运行|执行环境 → 对应平台检查手册|
|把本地改动送到 Ubuntu|工作区流转 → Ubuntu VCS 检查|
|把测试环境送到 CentOS|工作区流转；实际编译和 regression 使用 CentOS 自有框架|
|修改环境变量或 plusarg|配置参考 → 对应平台检查手册|
|定位失败|对应平台检查手册 → 调试指南 → 验证实现状态|

macOS 与 Ubuntu 的命令由仓库脚本维护。CentOS 只接收 `ut_shm/` 和 `ver_common/`，
完整编译、case 与 regression 命令不在本仓库记录。
