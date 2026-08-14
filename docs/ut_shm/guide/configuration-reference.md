# ut_shm 配置参考

本页集中列出仓库脚本、根 Makefile 和 UVM 环境实际读取的配置项。运行步骤放在对应平台
指南，TC/LST 的继承和 regression 格式放在
[Testcase 与 regression](../plan/testcases-and-regression.md)，这里不重复维护。

## 1. macOS 脚本环境变量

|变量|读取者|默认值|作用|
|---|---|---|---|
|`SLANG`|`scripts/local/check_vlm_memory_slang.sh`|`slang`|Slang 可执行文件|
|`UVM_HOME`|同上|`resources/uvm-1.2`|本地 UVM 源码根目录|
|`SHAREMEM_REMOTE_HOST`|Ubuntu 同步和远程执行脚本|`chatgpt`|Ubuntu SSH 主机或别名|
|`SHAREMEM_REMOTE_DIR`|Ubuntu 同步和远程执行脚本|`sharemem`|Ubuntu HOME 下的仓库路径|
|`SFTP_PASSWORD`|`upload_centos.py` 的底层密码读取函数|无|只有调用方未指定 password file 时才作为后备；当前 CLI 默认优先读取密码文件|

`upload_centos.py` 的连接参数通过命令行设置：

运行时依赖 Python 3 和第三方包 `paramiko`。这是 macOS 上传环境的前置条件，
不是 CentOS 依赖。

|参数|作用|
|---|---|
|`--host`、`--port`、`--user`|CentOS SFTP 连接目标|
|`--remote-dir`|CentOS 上接收 `ut_shm/` 和 `ver_common/` 的绝对目录|
|`--password-file`|密码文件，权限不得向 group/other 开放；默认 `scripts/sftp.password`|
|`--timeout`|连接、banner 和认证超时，单位为秒|

`--local-dir` 目前保留在参数接口中，但上传集合固定为 `ut_shm/` 和 `ver_common/`，该
参数不会改变实际上传目录。

## 2. Ubuntu 根 Makefile变量

|变量|默认值|作用|
|---|---|---|
|`VCS`|`vcs`|VCS 可执行文件|
|`UVM_VERSION`|`uvm-1.2`|传给 `-ntb_opts` 的 UVM 版本|
|`BUILD_DIR`|`build/ut_shm`|simv、编译日志和 smoke 日志目录|
|`RPU_DIR`|`design`|伪 design 根目录|
|`TB_DIR`|`ut_shm`|ut_shm 根目录|
|`VER_CMN`|`ver_common`|公共验证组件根目录|
|`AXI_VIP_DIR`|无，必填|Synopsys AXI/VIP 根目录|
|`SNPS_DC_HOME`|未设置时使用 build 内空 stub|DesignWare 根目录|
|`ENABLE_COVERAGE`|`0`|设为 `1` 时加入 line/cond/fsm/branch/tgl 编译选项|
|`VCS_USER_OPTS`|空|附加 VCS 编译参数|
|`SIM_ARGS`|零事务 `shm_unit_test` 参数|覆盖 `make smoke` 的仿真参数|
|`SIM_TIMEOUT_SECONDS`|`120`|GNU `timeout` 对 smoke 的外部时间限制|

Makefile会导出 `RPU_DIR`、`TB_DIR`、`VER_CMN`、`AXI_VIP_DIR` 和 `SNPS_DC_HOME`，供
filelist 中的 `$变量` 展开。`ut_shm/cfg/ut_shm.cfg` 只是选项来源参考，不会被 Makefile
解析。

## 3. Ubuntu reservation 组件脚本

|变量|默认值|作用|
|---|---|---|
|`VCS`|`vcs`|组件测试使用的 VCS 可执行文件|
|`UVM_VERSION`|`uvm-1.2`|组件测试使用的 UVM 版本|
|`RPU_DIR`|`design`|`compile` 目标使用的 `RpuShmTop` stub 根目录|

目标后的其余参数原样追加到 VCS 编译命令。例如需要临时增加 define 时，在 Ubuntu
仓库根目录执行：

**执行环境：Ubuntu `chatgpt`；工作目录：仓库根目录。**

```bash
scripts/ubuntu/check_vlm_reservation_vcs.sh compile +define+MY_DEBUG
```

## 4. ut_shm 仿真 plusarg

下表记录当前代码实际读取的名称。名称区分大小写。

|Plusarg|格式或取值|读取位置|当前效果|
|---|---|---|---|
|`UVM_TESTNAME`|UVM test class 名|UVM|当前正常 case 使用 `shm_unit_test`|
|`TRANS_NUM`|非负整数|`shmins_mst_unit_sequence`|生成的 creq 数量；主 TC 当前设为 16|
|`TRANS_DELAY_MIN`|整数|`shmins_mst_unit_sequence`|transaction 间隔随机范围下界|
|`TRANS_DELAY_MAX`|整数|`shmins_mst_unit_sequence`|transaction 间隔随机范围上界|
|`VTRANS_EN`|`0..100`|`shmins_mst_unit_sequence`|每笔 transaction 为 VTRANS 的全局百分比|
|`CREQ_RW`|`SHM_V2M`、`SHM_M2V`|`shmins_mst_unit_sequence`|把 normal 请求方向 domain 缩小到该值|
|`CREQ_DTYPE`|`DTYP_32`、`DTYP_16`、`DTYP_8`|`shmins_mst_unit_sequence`|把 normal dtype domain 缩小到该值|
|`CREQ_ATYPE_W`|`ATYP_32`、`ATYP_16`|`shmins_mst_unit_sequence`|把 normal offset 宽度 domain 缩小到该值|
|`CREQ_ATYPE_S`|`ATYP_U`、`ATYP_S`|`shmins_mst_unit_sequence`|把 normal offset signedness domain 缩小到该值|
|`CREQ_ATYPE_G`|`GAUTO_1B`、`GAUTO_DW`|`shmins_mst_unit_sequence`|把 normal offset granularity domain 缩小到该值|
|`CREQ_ITYPE`|`LDST_S`、`LDST_V`、`LDSTE_S`、`LDSTE_V`|`shmins_mst_unit_sequence`|把 normal 地址拓扑 domain 缩小到该值|
|`CREQ_SPACE`|`SPACE_LOC`、`SPACE_WRP`、`SPACE_BLK`|`shmins_mst_unit_sequence`|把 normal address-space domain 缩小到该值|
|`EXTERNAL_BUSY_PERCENT`|`0..100`|reservation agent|覆盖 config 中的 external busy 概率；越界会 fatal|
|`SCB_NO_PROGRESS_TIMEOUT_CYCLES`|非负整数|scoreboard|pending record 全局无进展诊断；0（默认）关闭|
|`SCB_RECORD_AGE_TIMEOUT_CYCLES`|非负整数|scoreboard|单笔 record 总年龄诊断；0（默认）关闭|
|`SCB_TIMEOUT_SCAN_INTERVAL_CYCLES`|正整数|scoreboard|timeout/completion 扫描周期；默认 10，0 会 fatal|
|`ACK_POST_COMPLETE_GRACE_CYCLES`|非负整数|lifecycle checker|数据全部实际匹配且成为同方向有序队头后等待 required ack 的诊断 grace；默认 20，0 关闭中途诊断|
|`TEST_DRAIN_TIMEOUT_CYCLES`|正整数|`shm_environment.wait_for_idle()`|sequence 结束后环境 drain watchdog；默认 10000，0 会 fatal|
|`file_debug`|无值开关|reference、旧独立 VLM memory monitor|主环境创建 `vlm.ref`；旧 monitor 单独使用时创建 `vlm_memory.rtl`，统一 VLM monitor 当前不创建独立 debug 文件|
|`UVM_VERBOSITY`|UVM verbosity 名称|UVM|控制 UVM report 输出级别|
|`UVM_TOPOLOGY`|无值开关|UVM|打印 UVM topology|

`shm_base_test` 不再自动启动旧 master sequence。`shmins_mst_unit_sequence` 启动时检查
`TRANS_NUM` 和 delay 区间；非法配置在生成 item 前 fatal。

`CREQ_*` 只配置 normal domain，不配置 VTRANS。VTRANS 使用独立 domain 和子类协议
约束，因此 normal 的 `CREQ_RW=SHM_M2V` 可以与非零 `VTRANS_EN` 合法共存。

三个 timeout 名称都以 cycle 为单位。Scoreboard timeout 和 ack grace 是可关闭的 hang
诊断，不是 DUT protocol latency；`TEST_DRAIN_TIMEOUT_CYCLES` 是 testcase 结束保护，触发
时会打印仍 pending 的 scoreboard、lifecycle 和 reservation 状态。

## 5. TC、LST 与 CFG

`.tc`、`.lst` 和 `ut_shm/cfg/ut_shm.cfg` 可以在 macOS 和 Ubuntu 被当作文本审阅，但
只有 CentOS 自有框架负责真实解析。TC inheritance、`INCLUDE`、`RUN` 和 `SEED` 的格式
见[Testcase 与 regression](../plan/testcases-and-regression.md)。本仓库不提供模拟该
解析过程的本地脚本，也不记录 CentOS 的运行命令。
