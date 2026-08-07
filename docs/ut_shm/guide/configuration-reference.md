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
|`TRANS_NUM`|非负整数|`shmins_unit_sequence`|生成的 creq 数量；主 TC 当前设为 16|
|`TRANS_DELAY_MIN`|整数|`shmins_unit_sequence`|transaction 间隔随机范围下界|
|`TRANS_DELAY_MAX`|整数|`shmins_unit_sequence`|transaction 间隔随机范围上界|
|`VTRANS_EN`|`0`/`1`|`shmins_unit_sequence`|启用 VTRANS 专用 inline constraint|
|`CREQ_RW`|`SHM_V2M`、`SHM_M2V`|`shmins_unit_sequence`|普通请求方向|
|`CREQ_DTYPE`|`DTYP_32`、`DTYP_16`、`DTYP_8`|`shmins_unit_sequence`|普通请求数据元素宽度|
|`CREQ_ATYPE_W`|`ATYP_32`、`ATYP_16`|`shmins_unit_sequence`|普通请求 offset 元素宽度|
|`CREQ_ATYPE_S`|`ATYP_U`、`ATYP_S`|`shmins_unit_sequence`|能被解析，但当前没有约束到 item，见 `SHMINS-004`|
|`CREQ_ATYPE_G`|`GAUTO_1B`、`GAUTO_DW`|`shmins_unit_sequence`|能被解析，但当前没有约束到 item，见 `SHMINS-004`|
|`CREQ_ITYPE`|`LDST_S`、`LDST_V`、`LDSTE_S`、`LDSTE_V`|`shmins_unit_sequence`|普通请求地址生成类型|
|`CREQ_SPACE`|`SPACE_LOC`、`SPACE_WRP`、`SPACE_BLK`|`shmins_unit_sequence`|普通请求地址空间|
|`EXTERNAL_BUSY_PERCENT`|`0..100`|reservation agent|覆盖 config 中的 external busy 概率；越界会 fatal|
|`file_debug`|无值开关|reference、memory monitor|分别创建 `vlm.ref`、`vlm_memory.rtl` 调试文件|
|`UVM_VERBOSITY`|UVM verbosity 名称|UVM|控制 UVM report 输出级别|
|`UVM_TOPOLOGY`|无值开关|UVM|打印 UVM topology|

`shm_base_test` 还读取小写 `trans_num`，但当前 TC 使用的 `shm_unit_test` 覆盖了
`main_phase` 并读取大写 `TRANS_NUM`。新增 case 不应混用这两个名称。

`TRANS_DELAY_MIN/MAX` 没有独立范围检查；下界大于上界时，sequence item randomize 会
失败。VTRANS 会覆盖方向、info、dtype/itype 范围、space、thread mask、element 数和
vector mask，不能把普通请求的全部 plusarg 理解成 VTRANS 的最终约束。

## 5. TC、LST 与 CFG

`.tc`、`.lst` 和 `ut_shm/cfg/ut_shm.cfg` 可以在 macOS 和 Ubuntu 被当作文本审阅，但
只有 CentOS 自有框架负责真实解析。TC inheritance、`INCLUDE`、`RUN` 和 `SEED` 的格式
见[Testcase 与 regression](../plan/testcases-and-regression.md)。本仓库不提供模拟该
解析过程的本地脚本，也不记录 CentOS 的运行命令。
