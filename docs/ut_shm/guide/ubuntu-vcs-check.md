# Ubuntu VCS 检查

Ubuntu `chatgpt` 提供 VCS、UVM 和 Synopsys VIP，但没有真实 design RTL。仓库内的
`design/` 是接口 stub，用于尽早发现测试环境的 filelist、package、include、端口和
VCS 兼容问题；完整 DUT 功能仍由 CentOS 验证。

## 1. 前置检查

先按[工作区流转](workspace-transfer.md#2-同步到-ubuntu)从 macOS 同步代码。直接登录
Ubuntu 后，确认位于 `~/sharemem` 或 `SHAREMEM_REMOTE_DIR` 指定的仓库根目录，并确认
EDA 环境已在非登录 Shell 中生效。

## 2. 根 Makefile 全环境检查

根 Makefile读取 `ut_shm/filelist/shm_dut.f`、`shm_environment.f` 和 `shm_tbtop.f`。
它参考 `ut_shm/cfg/ut_shm.cfg` 中的 VCS 选项，但不会解析该 CFG。

**执行环境：Ubuntu `chatgpt`；工作目录：仓库根目录。**

检查工具、目录、VIP 和主要输入：

```bash
make preflight
```

查看最终路径和变量：

```bash
make print-config
```

执行分析和 elaboration：

```bash
make compile
```

执行零事务 smoke：

```bash
make smoke
```

默认产物位于 `build/ut_shm/`，主要日志为 `compile.log` 和 `smoke.log`。`make smoke`
默认运行 `shm_unit_test` 并设置 `TRANS_NUM=0`。它只尝试启动 UVM 环境，不验证
数据路径；当前仓库 stub 没有驱动 DUT 输出，因此 smoke 启动后会被 monitor 的
X/Z 检查判定失败。这个结果不会否定已通过的 VCS 分析和 elaboration。

**执行环境：Ubuntu `chatgpt`；工作目录：仓库根目录。**

```bash
make clean
```

清理目标只允许位于当前仓库的 `build/*` 下。

## 3. Reservation 组件测试

[`check_vlm_reservation_vcs.sh`](../../../scripts/ubuntu/check_vlm_reservation_vcs.sh)
替代原 example Makefile，构建产物仍写入 `examples/vlm_reservation_compile/build/`。

**执行环境：Ubuntu `chatgpt`；工作目录：仓库根目录。**

```bash
scripts/ubuntu/check_vlm_reservation_vcs.sh compile
scripts/ubuntu/check_vlm_reservation_vcs.sh alignment
scripts/ubuntu/check_vlm_reservation_vcs.sh external-busy
```

`compile` 联合编译 reservation agent、memory agent 和 `RpuShmTop` stub；`alignment`
验证 reservation 不执行 alignment policy 且完整地址必须一致，`external-busy` 运行
对应 plusarg 定向 testbench。一次运行所有目标：

```bash
scripts/ubuntu/check_vlm_reservation_vcs.sh all
```

`external-busy` testbench 的 config 和 scheduler 字段已对齐，且当前版本已在远端通过；
`alignment` 目标已不再编码旧的 port-based alignment 规则。两个 UVM 组件运行脚本都会
检查 PASS marker、`UVM_ERROR: 0` 和 `UVM_FATAL: 0`，避免只依赖 simv 退出码。

## 4. 从 macOS 发起相同检查

下面的脚本在 macOS 启动，但 `make` 和 VCS 实际运行在 Ubuntu。

**启动环境：macOS；实际执行环境：Ubuntu `chatgpt`；工作目录：Ubuntu 仓库根目录。**

```bash
scripts/local/run_remote_command.sh make compile
scripts/local/run_remote_command.sh scripts/ubuntu/check_vlm_reservation_vcs.sh compile
```

远程执行不会自动同步；必须先运行 `scripts/local/sync_remote_repo.sh`。

## 5. Ubuntu 结果边界

Ubuntu 可以证明测试环境与 VCS/UVM/VIP 以及伪 design 接口能够共同编译，组件 testbench
也可以在不依赖真实 DUT 行为时运行。它没有 CentOS 的真实 design 和 TC/LST/CFG
解析框架，因此不能作为完整 case、regression 或 DUT 功能通过证据。

## 6. 2026-08-06 实测快照

本次在 Ubuntu `chatgpt` 的同步工作区中得到：

- `make preflight` 通过；
- `make compile` 通过，生成 `build/ut_shm/simv`；
- `make smoke` 完成编译并启动 UVM，但因空壳 `RpuShmTop` 输出未驱动，在
  cycle 11 至 200 触发 `VLM_RESERVATION_RREQ_XZ`、`VLM_RESERVATION_WREQ_XZ`、
  `MEM_RVLD_XZ` 和 `MEM_WVLD_XZ`，最终为 `UVM_CASE_FAIL`；
- 组件脚本的 `compile` 目标通过；
- `alignment` 目标运行通过，但它仍编码旧 port-based alignment 规则，不是最新
  spec 的验收证据；
- 当时的 `external-busy` 目标因字段名不一致而编译失败；当前源码已修复，并在
  2026-08-13 使用 VCS `W-2024.09-SP1_Full64` 复跑通过，`RSV-003` 已关闭。

这份快照只记录当时的伪 design 环境，后续代码变更后应重新执行，不能替代
CentOS 真实 RTL 的最终结果。

## 7. 2026-08-09 RSV-001 实测快照

在远端 Ubuntu `chatgpt` 工作区使用 VCS `W-2024.09-SP1_Full64` 得到：

- `scripts/ubuntu/check_vlm_reservation_vcs.sh alignment` 编译并运行通过，日志包含
  `vlm reservation alignment-ownership regression: PASS`；
- read、write port 0/1 的非对齐 reservation 均保留完整地址，同地址 MEM request 匹配，
  仅低 5 bit 不同的 MEM request 被完整地址检查拒绝；
- `scripts/ubuntu/check_vlm_reservation_vcs.sh compile` 完成 reservation agent、memory
  agent 和空 design 的 parse、elaboration 与 simv link；
- Linux 6.17 unsupported-kernel warning 是工具环境提示，没有阻止编译或定向仿真。

该证据验证 reservation 接受非对齐地址并执行完整地址匹配。2026-08-11 已进一步确认
下游 SRAM 对所有 32-Byte read/write 都支持非对齐地址，因此不存在待补的 scoreboard
来源相关 alignment checker。该组件证据仍不替代真实 RTL 完整 regression。

## 8. 2026-08-18 SHMINS don’t-care X 组件门禁

在 hx16 使用 VCS `T-2022.06-SP2-5_Full64` 执行：

```bash
scripts/ubuntu/check_shmins_sequence_vcs.sh all
scripts/ubuntu/check_shm_reference_vcs.sh
make .SHELLFLAGS=-ec compile
```

结果如下：

- SHMINS compile、copy、lifecycle、dual-gid-address、mask-monitor、don’t-care utility 和
  driver/monitor 四态保真目标全部通过；
- monitor 负例精确捕获5个预期 interpreted-payload X/Z report，最终
  `UVM_ERROR: 0`、`UVM_FATAL: 0`；
- standalone reference 的 gid isolation、masked/inactive/M2V don’t-care X 过滤通过，
  最终 `UVM_ERROR: 0`、`UVM_FATAL: 0`；
- 空 `RpuShmTop` 环境共27个 module完成 parse、elaboration 和 simv link。

GNU Make 3.82 对仓库当前多段 `.SHELLFLAGS` 的解释不兼容，因此本次空 design 编译显式
覆盖为 `.SHELLFLAGS=-ec`。本批没有执行空 design smoke，也没有执行正式 RTL；后者仍需用
`shmins_dontcare_x.lst` 验证30笔合法 X transaction 和目标 coverage。
