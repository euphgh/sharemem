# SHMINS monitor component test

本目录在不实例化真实 DUT 的情况下，验证 SHMINS monitor 的 thread-mask 和局部四态
contract。测试覆盖合法 single/sparse/full mask、全零丢弃、tmsk X、inactive payload
X/Z、active payload X，以及 `creq_vld==0` 不采样。

在配置好 VCS 的 Ubuntu EDA 环境执行：

```bash
scripts/ubuntu/check_shmins_sequence_vcs.sh mask-monitor
```

通过条件是日志包含：

```text
[SHMINS_MASK_MONITOR_TEST] thread-mask monitor component matrix: PASS
UVM_ERROR :    0
UVM_FATAL :    0
```

全零 tmsk 的 `SHMINS_TMSK_ZERO`、tmsk X 的 `SHMINS_TMSK_XZ` 和 active payload X 的
`SHMINS_ACTIVE_PAYLOAD_XZ` 是预期负例，必须各出现一次并由 report catcher 降级。全零
sample 不会由 monitor 发布；测试直接调用 coverage subscriber，仅用于命中非法 mask bin。
