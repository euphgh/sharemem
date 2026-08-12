# shmins_sequence_item 随机化基准

该最小 UVM 环境创建并随机化正式的 `shmins_sequence_item` topology 子类，不实例化
DUT，也不驱动 creq interface。公共基类使用过程式 `post_randomize()` 组织 MADDR、base
和 offset 生成；contiguous、strided、indexed 子类分别实现对应地址公式。

历史 solver item 和 monolithic post-randomize item 已从正式源码与 benchmark 删除。
`build/split/` 中的 `split` 仅是沿用的生成物目录名，不再表示可选择的实现版本。

## 基本运行

在 Ubuntu VCS 主机的仓库根目录执行：

```sh
scripts/ubuntu/run_shmins_random_benchmark.sh compile
scripts/ubuntu/run_shmins_random_benchmark.sh run \
  +BENCH_PROFILE=LDST_V_LOC \
  +BENCH_DTYPE=DTYP_32 \
  +BENCH_ATYPE_W=ATYP_32
```

本地只进行语法检查：

```sh
scripts/local/check_shmins_random_benchmark_slang.sh
```

## 参数交叉与无 override 测试

`matrix` 在一次仿真中遍历 topology、space、RW、dtype、ATYPE width、signedness 和
granularity，共 432 种组合。Contiguous 固定使用地址算法相同的 `LDST_V`，strided
使用 `LDSTE_S`，indexed 使用 `LDSTE_V`。每个成功 item 还会从公开的 packed offset
重新计算 active element MADDR 并调用公共映射函数，检查生成模型与 reference 消费边界。

`unconstrained` 分别创建三个 topology 子类并直接调用 `randomize()`，不添加 inline
constraint：

```sh
BENCH_ITERATIONS=100 BENCH_WARMUP=5 \
  scripts/ubuntu/run_shmins_random_cross_benchmark.sh matrix

BENCH_ITERATIONS=1000 BENCH_WARMUP=10 \
  scripts/ubuntu/run_shmins_random_cross_benchmark.sh unconstrained

BENCH_ITERATIONS=100 BENCH_WARMUP=5 \
  scripts/ubuntu/run_shmins_random_cross_benchmark.sh all
```

结果写入 `examples/shmins_random_benchmark/build/split/`：

- `cross_matrix.log` 和 `cross_matrix.csv`；
- `unconstrained.log` 和 `unconstrained.csv`；
- VCS 编译日志 `compile.log`。

## 单 profile 配置

`run` 后面的参数原样传给 `simv`：

|Plusarg|默认值|说明|
|---|---|---|
|`BENCH_ITERATIONS`|10|计时区间内的 randomize 次数|
|`BENCH_WARMUP`|2|计时前的预热次数|
|`BENCH_PROFILE`|`LDST_V_LOC`|固定 ITYPE/space profile|
|`BENCH_RW`|`V2M`|`V2M` 或 `M2V`|
|`BENCH_DTYPE`|`DTYP_8`|`DTYP_8/16/32`|
|`BENCH_ATYPE_W`|`ATYP_16`|`ATYP_16/32`|
|`BENCH_ATYPE_S`|`ATYP_U`|`ATYP_U` 或 `ATYP_S`|
|`BENCH_ATYPE_G`|`GAUTO_1B`|`GAUTO_1B` 或 `GAUTO_DW`|
|`BENCH_INV_SIZE`|-1|随机，或 0～12 对应 4 B～16 KiB interleave|
|`BENCH_WPID`|0|固定 absolute WARP ID|
|`BENCH_WPNUM`|-1|随机，或固定为 1/2/4|
|`M2V_UNIQUE`|0|为 1 时额外要求 M2V active byte 唯一|
|`BENCH_REUSE_ITEM`|1|是否重复随机化同一对象|

支持的 profile 为 `LDST_S/LDST_V/LDSTE_S/LDSTE_V` 与 `LOC/WRP/BLK` 的组合，例如
`LDSTE_V_BLK`。正式实现只支持 `BENCH_CONSTRAINT_SET=ALL`。

日志中的 `SHMINS_RANDOM_BENCH_RESULT` 给出成功/失败次数、retry、validator error、
`elapsed_ms`、`ms_per_attempt`、attempts/s 和 checksum。性能结论必须使用相同 VCS
版本、profile、次数、reuse 设置和 seed，并要求 failure 与 validation error 均为 0。
