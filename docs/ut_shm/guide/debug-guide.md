# ut_shm 调试指南

本页按“代码未到目标环境、工具无法启动、编译失败、仿真启动后失败”组织定位顺序。
开始前先确认问题出现在哪个执行环境，并按[执行环境](execution-environments.md)判断该
环境本来能够提供哪一级证据。

## 1. 先记录最小上下文

定位任何问题时先保留：

- 本地 commit 或工作区 diff；
- 执行环境和工作目录；
- 完整命令及覆盖的环境变量；
- 首个 error/fatal，而不是只截取最后的汇总；
- 编译阶段、elaboration 阶段或仿真时间；
- case、seed 和最终生效的 plusargs。

多个后续错误可能只是第一个 package、include 或 type 错误的级联结果，应从日志中的
第一处失败开始。

## 2. macOS 到 Ubuntu 同步失败

### 看起来长时间卡住

先确认运行的是 `scripts/local/sync_remote_repo.sh`。脚本已设置 batch SSH、10 秒连接
超时、keepalive 和 60 秒 rsync I/O 超时；超过这些边界仍不退出时，分别检查 SSH 建连
和 rsync 文件扫描阶段。

**执行环境：macOS；工作目录：仓库根目录。**

```bash
scripts/local/sync_remote_repo.sh --dry-run
```

如果在验证远端 `.git` 前失败，优先检查 SSH 别名、认证和
`SHAREMEM_REMOTE_HOST/DIR`。如果已经打印文件列表再失败，远端可能只收到部分文件，
应重新同步后再运行 VCS。

### Ubuntu 文件与本地不一致

默认同步使用删除语义。先用 `--dry-run` 检查 exclude 和删除列表；临时使用
`--no-delete` 只能保留远端额外文件，不能解决同路径内容冲突。

## 3. macOS 到 CentOS 上传问题

### 大量文件被意外重新上传

检查 `build/remote-cache/.target.json` 对应的 host、port、user 和 remote directory。
目标变化会使缓存失效并触发完整同步。缓存被删除或内容与源文件不同也会重新上传。

### 缓存命中但担心服务器内容被改动

缓存比较只发生在 macOS 的源文件和本地快照之间，不读取 CentOS 文件。如果 CentOS
内容可能被其他流程修改，需要使用新的可信目标或重新初始化同步；操作前必须核对远端
绝对路径，因为完整同步会清空该目标目录。

### 认证或主机密钥失败

密码文件权限必须是 `0600`，主机公钥必须已经存在于本机 known_hosts。脚本拒绝未知
主机密钥，不会自动接受。

## 4. Slang 失败

先区分 UVM 源码 warning、wrapper 缺少 include/package，以及改动文件自身的错误。
`check_vlm_memory_slang.sh` 是聚焦检查，未包含的 class 报 undefined 不代表完整环境一定
失败，也不能把扩大 wrapper 后出现的真实依赖错误忽略为工具差异。

常见检查顺序：

1. 确认 `SLANG` 可执行，`UVM_HOME/src/uvm_pkg.sv` 和 `uvm_macros.svh` 存在；
2. 检查 package import、include guard 和 `+incdir`；
3. 检查声明是否出现在语句之后，以及 VCS 兼容模式仍不接受的语法；
4. 用最小 wrapper 覆盖改动文件，再进入 Ubuntu VCS。

## 5. Ubuntu Makefile preflight 失败

`make print-config` 可以显示最终路径。`make preflight` 的常见失败项包括：

- `AXI_VIP_DIR` 未设置，或缺少 `svt_axi.uvm.pkg`/`svt_mem.uvm.pkg`；
- `RPU_DIR` 没有伪 design filelist 或 `RpuShmTop.sv`；
- `TB_DIR`、`VER_CMN` 与同步后的工作区不一致；
- 非登录 Shell 没有加载 VCS 环境；
- 自定义 `SNPS_DC_HOME` 不含 `dw/sim_ver`。

不要在 macOS 运行该 preflight；它要求 VCS 和 Synopsys VIP。

## 6. Ubuntu VCS 编译失败

按以下顺序定位首个错误：

1. source file cannot be opened：检查 filelist 环境变量、相对路径和 include directory；
2. package/type undefined：检查 package 编译顺序和 `.svh` 是否由唯一 package include；
3. interface undefined：确认 interface `.sv` 在依赖它的 class package 之前单独编译；
4. port mismatch：比较 tb top、伪 `RpuShmTop` 和 interface 的当前端口；
5. elaboration hierarchy 错误：确认 UVM test/package 和 `-top` 是否进入命令；
6. Synopsys VIP 错误：先确认 VIP 环境变量和 VCS/UVM 版本，而不是修改验证源码绕过。

根 Makefile失败说明完整测试环境尚未达到 L2。组件脚本通过只能作为 L1 证据，不能覆盖
该失败。

## 7. 仿真启动后的问题

### 0 时间或 reset 前出现 X/Z

先确认错误来自 monitor、checker 还是 DUT assertion。Reservation monitor 已在 reset
释放后才执行 X/Z 检查；其他组件的 reset 和运行中 reset 缺口见
[验证实现状态](../verification-status.md)。

### UVM 环境启动但没有事务

检查最终 `UVM_TESTNAME`、`TRANS_NUM`、`VTRANS_EN` 和 sequence 启动日志。根 Makefile
的默认 smoke 明确设置 `TRANS_NUM=0`，没有事务是预期行为。

### Ubuntu smoke 在 reset 后连续报 request/valid X/Z

先确认 `RPU_DIR` 是否仍指向仓库内的空壳 `design/`。当前 stub 只提供端口并不驱动
DUT 输出，因此 reservation 和 MEM monitor 在 reset 释放后报 X/Z 是已知结果。
`make compile` 通过仍然是有效的 VCS 编译证据，但这个 smoke 失败不能用来评估
真实 DUT 行为。

### 随机配置看起来没有生效

先在 sequence 日志中确认 plusarg 已解析，再查看 monitor transaction。当前
`CREQ_ATYPE_S/G` 被解析但没有约束到 item，属于 `SHMINS-004`；external busy 是概率
行为，除 100% 定向配置外，短时间波形没有 busy 不一定是错误。

### Scoreboard expired 或 reservation mismatch

保留 transaction ID、方向、BANK、完整地址、issue/due cycle、当前 cycle、matched 与
expired 日志。Address alignment、timeout、FFD_CYC 和运行中 reset 都有已登记缺口，
先按错误 ID 进入[验证实现状态](../verification-status.md)，再判断是否为新问题。

## 8. CentOS 结果反馈

CentOS 命令由服务器自有 Makefile/`rpu_sim` 维护，本指南不复制。用户运行最终验证后，
建议至少反馈以下内容：

- 上传所依据的本地 commit 或明确 diff；
- compile、smoke、单 case 或 regression 的阶段；
- case 名、seed 和关键 plusargs；
- 第一条编译 error 或 UVM error/fatal 及前后上下文；
- 对应仿真时间和关键地址；
- 最终 pass/fail 汇总。

没有这些上下文时，只能把结果记录为待分析，不能据此关闭 testpoint 或实现问题。
