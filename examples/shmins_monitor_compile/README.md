# SHMINS monitor component test

本目录在不实例化真实 DUT 的情况下，验证 SHMINS monitor 的 thread-mask 和局部四态
contract。测试覆盖合法 single/sparse/full mask、全零丢弃、tmsk X、inactive payload
X/Z、masked V2M data、masked indexed offset、M2V data、length 外 payload，以及
active mask/shared offset/indexed offset/V2M data X/Z 负例和 `creq_vld==0` 不采样。

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

全零 tmsk 的 `SHMINS_TMSK_ZERO`、tmsk X 的 `SHMINS_TMSK_XZ` 和 5 类 interpreted
payload X 的 `SHMINS_ACTIVE_PAYLOAD_XZ` 是预期负例，必须精确出现并由 report
catcher 降级。全零 sample 不会由 monitor 发布；测试直接调用 coverage subscriber，
仅用于命中非法 mask bin。

`driver_monitor_tb.sv` 还通过 `dontcare-driver` target 验证三笔 transaction 经过生产
sequencer、driver、interface 和 monitor 后仍保留精确四态值，并检查
`delay_cycle=0/1` 的 accept cycle。

`ordered_batch_tb.sv` 通过 `ordered-batch` target 验证跨 transaction physical-byte
hazard 和 directed queue transport。它覆盖双向 V-write/M-access 冲突、M/M 与 V/V
合法 overlap、不同 gid 隔离、DTYP16 partial-byte overlap、零/一周期 item 间隔，以及
非法 batch 在发布任何请求前被拒绝。通过标志为：

```text
[SHMINS_ORDERED_BATCH_TEST] ORDER-HAZ-001..010 and ORDER-SEQ-001..004: PASS
```
