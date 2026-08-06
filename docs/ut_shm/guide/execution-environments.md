# ut_shm 执行环境

ut_shm 的开发和验证分布在 macOS、Ubuntu 与 CentOS 三个环境中。三者能访问的源码、
EDA 工具和外部框架不同，因此同一份改动需要逐级检查；本页先定义环境边界，具体命令
分别放在平台检查和工作区流转文档中。

## 1. 环境能力

|环境|主要用途|可用工具|design RTL|主要限制|
|---|---|---|---|---|
|macOS 本地工作区|AI 辅助代码与文档开发、快速语法检查|Git、Python、Slang、SSH/SFTP 客户端|只有仓库内的伪造 stub|没有 VCS，不能证明 VCS 编译、elaboration 或 DUT 行为|
|Ubuntu `chatgpt`|VCS 编译器检查、组件定向测试和简单 smoke|VCS、UVM、Synopsys VIP、常规 Linux 工具|与本地同步的伪造 stub，没有真实 RTL|可以检查测试环境与工具兼容性，不能验证真实 DUT 功能|
|CentOS|完整 design 集成、case 和 regression|真实 design、服务器自有 Makefile/`rpu_sim` 和 EDA 环境|有|当前 Agent 不能直接操作或下载文件，最终命令由用户执行|

仓库中的 `design/` 只为 Ubuntu 编译入口提供接口 stub。它不代表真实设计，也不能用来
证明地址映射、时序或数据行为正确。

## 2. 文件可见性

|内容|macOS|Ubuntu|CentOS|
|---|---|---|---|
|完整 Git 工作区|是|通过 rsync 获得，保留 Ubuntu 自己的 `.git`|否|
|`ut_shm/`、`ver_common/`|是|是|通过 SFTP 上传|
|仓库根 Makefile、`scripts/`、`examples/`|是|是|不由上传脚本交付|
|真实 design RTL|否|否|是|
|TC/LST/CFG 的真实解析器|否|否|是|

TC、LST 和 CFG 的格式说明属于仓库文档，但这些文件能否被实际框架接受，必须以
CentOS 上的解析结果为准。

## 3. 验证证据等级

|等级|环境|证据含义|
|---|---|---|
|L0|macOS Slang|选定 SystemVerilog/UVM 文件通过基础语法和部分语义检查|
|L1|Ubuntu VCS 组件测试|不依赖真实 DUT 行为的组件能够被 VCS 编译、elaborate 或运行|
|L2|Ubuntu 根 Makefile|完整测试环境 filelist 能与伪造 design 接口一起编译，并可启动 smoke|
|L3|CentOS|真实 DUT 能完成编译、启动仿真，并由用户执行指定 case 或 regression|

较低等级通过不能替代较高等级。尤其是 L2 只证明测试环境与伪 design 的接口和编译
依赖基本一致，不构成任何 DUT 功能结论。

## 4. 命令标注约定

指南中的每个命令块都必须紧邻注明执行环境和工作目录。对于
`run_remote_command.sh` 这类跨环境脚本，还要分别注明启动环境和命令主体的实际执行
环境。例如：

```text
启动环境：macOS
实际执行环境：Ubuntu chatgpt
工作目录：两端均为仓库根目录
```

CentOS 不提供仓库内运行命令。相关章节只说明交付内容和需要用户反馈的验证证据。
