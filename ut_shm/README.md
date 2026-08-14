# ut_shm tests 使用说明

本文汇总 `ut_shm/tests/` 当前测试入口及其实际读取的全部项目自定义 plusarg，方便在
命令行或 `ut_shm/tc/*.tc` 中配置 testcase。详细 contract 仍以
[配置参考](../docs/ut_shm/guide/configuration-reference.md)、
[SHMINS master agent](../docs/ut_shm/environment/components/shmins-mst-agent.md)和
[Scoreboard](../docs/ut_shm/environment/components/shm-scoreboard.md)为准。

## 1. 测试入口

当前完整环境测试类是 `shm_unit_test`。它执行以下流程：

1. 创建 `shmins_mst_unit_sequence`；
2. 读取本页列出的 sequence plusarg；
3. 生成并发送配置数量的 SHM transaction；
4. 等待 scoreboard、transaction lifecycle 和 reservation scheduler 连续两个周期
   都进入 idle；
5. 执行 UVM check/report phase。

仓库根目录的 `make smoke` 使用空 design，默认参数为：

```text
+UVM_TESTNAME=shm_unit_test +TRANS_NUM=0 +UVM_VERBOSITY=UVM_LOW +UVM_TOPOLOGY
```

它只用于 testbench 编译、连接和零事务 smoke，不是 DUT 功能正确性的证据。真实 design
case 使用 `ut_shm/tc/` 和 `ut_shm/regression/` 中的配置。

## 2. Transaction 数量、间隔和 VTRANS

|Plusarg|合法值|代码默认值|作用|
|---|---|---:|---|
|`+TRANS_NUM=<n>`|非负整数|8|本次 sequence 生成的 transaction 数量|
|`+TRANS_DELAY_MIN=<n>`|非负整数|0|相邻 transaction driver delay 的随机下界，单位为 cycle|
|`+TRANS_DELAY_MAX=<n>`|不小于 MIN 的整数|16|相邻 transaction driver delay 的随机上界，单位为 cycle|
|`+VTRANS_EN=<n>`|0～100|0|每笔 transaction 独立选择为 VTRANS 的百分比|

`ut_shm/tc/ut_shm.tc` 当前把 transaction 数量设置为 16、delay 设置为 64～128 cycles，
这与 sequence 类自身的默认值不同。`VTRANS_EN=100` 表示全部生成 VTRANS；
`VTRANS_EN=0` 表示全部生成 normal transaction。

## 3. Normal transaction domain

以下 plusarg 只缩小 normal transaction 的 allowed-value domain。没有提供的字段在其完整
合法集合内随机；每个字段目前只接受一个固定值，不支持在命令行中传入多个值。

|Plusarg|可选字符串|不配置时的行为|
|---|---|---|
|`+CREQ_RW=<value>`|`SHM_V2M`、`SHM_M2V`|两个方向随机|
|`+CREQ_DTYPE=<value>`|`DTYP_32`、`DTYP_16`、`DTYP_8`|三种 dtype 随机|
|`+CREQ_ATYPE_W=<value>`|`ATYP_32`、`ATYP_16`|两种 offset 编码位宽随机|
|`+CREQ_ATYPE_S=<value>`|`ATYP_U`、`ATYP_S`|unsigned/signed 随机|
|`+CREQ_ATYPE_G=<value>`|`GAUTO_1B`、`GAUTO_DW`|1-byte/dtype granularity 随机|
|`+CREQ_ITYPE=<value>`|`LDST_S`、`LDST_V`、`LDSTE_S`、`LDSTE_V`|四种 ITYPE 随机|
|`+CREQ_SPACE=<value>`|`SPACE_LOC`、`SPACE_WRP`、`SPACE_BLK`|三种 space 随机|

枚举字符串不区分大小写，但应只使用表中列出的名称。ITYPE 对应的 sequence item 为：

|ITYPE|地址形态|Sequence item|
|---|---|---|
|`LDST_S`、`LDST_V`|contiguous|`shmins_contiguous_sequence_item`|
|`LDSTE_S`|strided|`shmins_strided_sequence_item`|
|`LDSTE_V`|indexed|`shmins_indexed_sequence_item`|

Normal `CREQ_*` plusarg 不约束 VTRANS。VTRANS 使用独立 domain，并固定为 V2M、
`SPACE_LOC`；其 dtype 只在 `DTYP_16/DTYP_8` 中选择，ITYPE 只在
`LDST_S/LDST_V` 中选择。因此，例如下面的配置会生成 50% 固定为 M2V/BLK 的 normal
transaction，以及约 50% 独立合法的 VTRANS：

```text
+VTRANS_EN=50 +CREQ_RW=SHM_M2V +CREQ_SPACE=SPACE_BLK
```

## 4. Scoreboard、ack 和 test drain

所有值都以共享 `clk_if.cycle_count` 的 cycle 为单位，不使用绝对 simulation time。

|Plusarg|合法值|默认值|作用|
|---|---|---:|---|
|`+SCB_NO_PROGRESS_TIMEOUT_CYCLES=<n>`|非负整数|0|存在 pending record 但 scoreboard 没有任何进展的诊断阈值；0 关闭|
|`+SCB_RECORD_AGE_TIMEOUT_CYCLES=<n>`|非负整数|0|单笔 reference record 总年龄诊断阈值；0 关闭|
|`+SCB_TIMEOUT_SCAN_INTERVAL_CYCLES=<n>`|正整数|10|scoreboard completion/timeout 扫描间隔；0 会 fatal|
|`+ACK_POST_COMPLETE_GRACE_CYCLES=<n>`|非负整数|20|全部期望 byte 实际匹配且事务成为同方向有序队头后等待 required ack 的 grace；0 关闭中途诊断|
|`+TEST_DRAIN_TIMEOUT_CYCLES=<n>`|正整数|10000|sequence 结束后等待整个环境 idle 的 watchdog；0 会 fatal|

两个 scoreboard timeout 和 ack grace 都是 hang 诊断，不是 DUT protocol 最大延迟：

- Scoreboard timeout 触发后只报告一次，不删除 pending record，后续正确数据仍可匹配；
- V2M/mack 和 M2V/vack 分别维护接收顺序，两个方向互不阻塞；
- `ACK_POST_COMPLETE_GRACE_CYCLES` 只有在 scoreboard 报告 `OBSERVED`，并且同方向所有
  前序事务都已退休后才开始，不从 creq accepted cycle 或本事务提前完成的 cycle 开始；
- 前序 ack-disabled 事务在 data resolved 后退休；前序 ack-enabled 事务在 data resolved
  且 ack received 后退休；
- 关闭 ack grace 不会关闭 end-of-test required-ack 完整性检查；
- `TEST_DRAIN_TIMEOUT_CYCLES` 是 testcase 结束保护，不是单笔 transaction timeout。

对于流量集中在少数 BANK、external busy 较高或冲突较多的 case，通常保持两个
scoreboard timeout 为 0，只按预期最大总运行时间调整 `TEST_DRAIN_TIMEOUT_CYCLES`。
需要定位疑似无进展时，再单独启用 no-progress timeout。

## 5. Reservation external busy

|Plusarg|合法值|代码默认值|作用|
|---|---|---:|---|
|`+EXTERNAL_BUSY_PERCENT=<n>`|0～100|0|每个当前可用 reservation slot 被外部 busy 占用的独立百分比|

`ut_shm/tc/ut_shm.tc` 当前覆盖为 10。值越大，DUT 可用的 reservation slot 越少，事务
完成时间通常越长。超过 100 会在 build phase fatal。

## 6. 调试开关

|Plusarg|格式|作用|
|---|---|---|
|`+file_debug`|无值开关|让 `shm_reference` 创建 `vlm.ref` 调试文件|

`file_debug` 名称区分大小写。生成文件属于仿真产物，不应提交到源码或文档目录。

## 7. 常用 UVM/VCS plusarg

下列参数由 UVM 或 VCS 读取，不是项目自定义字段，但运行 `ut_shm` tests 时经常一起使用：

|Plusarg|示例|作用|
|---|---|---|
|`+UVM_TESTNAME=<class>`|`+UVM_TESTNAME=shm_unit_test`|选择 UVM test class|
|`+UVM_VERBOSITY=<level>`|`+UVM_VERBOSITY=UVM_LOW`|设置 UVM 全局日志级别|
|`+UVM_TOPOLOGY`|无值开关|在 end-of-elaboration 打印 UVM topology|
|`+ntb_random_seed=<n>`|`+ntb_random_seed=12345`|设置 VCS 随机种子，便于复现|

## 8. 使用示例

### 8.1 完全大随机 normal traffic

不配置任何 `CREQ_*`，所有 normal domain 都保持开放：

```text
+UVM_TESTNAME=shm_unit_test
+TRANS_NUM=100
+TRANS_DELAY_MIN=0
+TRANS_DELAY_MAX=16
+VTRANS_EN=0
+ntb_random_seed=12345
```

### 8.2 定向 indexed V2M/BLK

```text
+UVM_TESTNAME=shm_unit_test
+TRANS_NUM=16
+CREQ_RW=SHM_V2M
+CREQ_ITYPE=LDSTE_V
+CREQ_SPACE=SPACE_BLK
+CREQ_DTYPE=DTYP_16
+CREQ_ATYPE_W=ATYP_32
+CREQ_ATYPE_S=ATYP_S
+CREQ_ATYPE_G=GAUTO_DW
```

### 8.3 高 external busy 和较长 drain

```text
+UVM_TESTNAME=shm_unit_test
+TRANS_NUM=32
+EXTERNAL_BUSY_PERCENT=50
+SCB_NO_PROGRESS_TIMEOUT_CYCLES=0
+SCB_RECORD_AGE_TIMEOUT_CYCLES=0
+TEST_DRAIN_TIMEOUT_CYCLES=50000
```

### 8.4 根 Makefile smoke

在支持 VCS 的远端仓库根目录执行：

```bash
make smoke SIM_ARGS='+UVM_TESTNAME=shm_unit_test +TRANS_NUM=0 +UVM_VERBOSITY=UVM_LOW +UVM_TOPOLOGY'
```

若把 `TRANS_NUM` 改为非零，仍然只有接入真实 design 的运行结果才能作为 DUT 行为证据。

### 8.5 TC 文件片段

```text
my_indexed_blk_case: shm_unit_test
+TRANS_NUM=16
+CREQ_RW=SHM_V2M
+CREQ_ITYPE=LDSTE_V
+CREQ_SPACE=SPACE_BLK
+TEST_DRAIN_TIMEOUT_CYCLES=30000
endargs
```

同一 testcase 中不要重复配置同名 plusarg。已有 testcase 和 regression 列表分别位于
`ut_shm/tc/` 与 `ut_shm/regression/`。
