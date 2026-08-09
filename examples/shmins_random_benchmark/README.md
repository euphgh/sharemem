# shmins_sequence_item randomize 性能基准

这个最小 UVM 环境只创建并随机化 `shmins_sequence_item`，用于比较 constraint 修改前后
的求解速度。它不实例化 DUT，也不驱动 creq interface。DPI 单调时钟只包围正式
randomize 循环，因此结果不包含 VCS/UVM 启动和 warmup；Ubuntu 脚本另外输出整个
仿真进程的 `real/user/sys` 时间。

## 运行环境

在 Ubuntu VCS 主机的仓库根目录执行：

```sh
scripts/ubuntu/run_shmins_random_benchmark.sh compile
scripts/ubuntu/run_shmins_random_benchmark.sh run

BENCH_IMPL=post_randomize \
  scripts/ubuntu/run_shmins_random_benchmark.sh compile
BENCH_IMPL=post_randomize \
  scripts/ubuntu/run_shmins_random_benchmark.sh run

BENCH_IMPL=split \
  scripts/ubuntu/run_shmins_random_benchmark.sh compile
BENCH_IMPL=split \
  scripts/ubuntu/run_shmins_random_benchmark.sh run \
  +BENCH_PROFILE=LDST_V_LOC \
  +BENCH_DTYPE=DTYP_32 \
  +BENCH_ATYPE_W=ATYP_32
```

`original.f`、`post_randomize.f` 和 `split.f` 分别选择原始 solver 实现、独立的
monolithic post-randomize 实现和按地址生成拓扑拆分的新实现。三者都定义名为
`shmins_sequence_item` 的 class，因此不能出现在同一次编译中；编译结果分别写入对应的
`build/<implementation>/`。

SPLIT 当前支持 contiguous `LDST_S/LDST_V`、strided `LDSTE_S` 和 indexed `LDSTE_V`
的 LOC/WRP/BLK 固定 profile。三个 topology 已通过远端 Ubuntu VCS benchmark 编译和参数
交叉测试。SPLIT 不接入正式 `ut_shm` package，不能用于系统仿真或 DUT 功能结论。

## SPLIT 参数交叉与无 inline constraint 基准

下面的脚本只适用于 `split` 实现。`matrix` 在一次仿真进程中遍历 topology、space、RW、
dtype、ATYPE width、signedness 和 granularity 的 432 种组合；contiguous 固定选择地址算法
相同的 `LDST_V`，`INV_SIZE` 固定为 10，LOC/WRP 使用 `WPID=0/WPNUM=1`，BLK 使用最后一个
WPID 和 `WPNUM=4`。M2V optional uniqueness 保持关闭。

`unconstrained` 分别创建 contiguous、strided 和 indexed 子类，并直接调用
`item.randomize()`，不添加 inline `with` constraint。子类自身用于选择地址拓扑的 native
constraint 仍然生效。

```sh
BENCH_ITERATIONS=100 BENCH_WARMUP=5 \
  scripts/ubuntu/run_shmins_random_cross_benchmark.sh matrix

BENCH_ITERATIONS=1000 BENCH_WARMUP=10 \
  scripts/ubuntu/run_shmins_random_cross_benchmark.sh unconstrained

BENCH_ITERATIONS=100 BENCH_WARMUP=5 \
  scripts/ubuntu/run_shmins_random_cross_benchmark.sh all
```

逐组合结果写入 `build/split/cross_matrix.csv`，无 inline constraint 结果写入
`build/split/unconstrained.csv`。对应日志保存在同一目录，不进入源码仓库。

macOS 只能检查语法和 C 计时代码，不能产生 randomize 性能数据：

```sh
scripts/local/check_shmins_random_benchmark_slang.sh
```

## 基准配置

`run` 后面的参数会原样传给 `simv`：

|Plusarg|默认值|说明|
|---|---|---|
|`BENCH_ITERATIONS`|10|进入计时区间的 randomize 次数；必须大于 0|
|`BENCH_WARMUP`|2|计时前的 solver 预热次数|
|`BENCH_PROFILE`|original/post: `LDSTE_V_BLK`; split: `LDST_V_LOC`|随机分支或固定 instruction/space profile|
|`BENCH_RW`|`V2M`|固定 profile 的方向，可选 `V2M` 或 `M2V`|
|`BENCH_DTYPE`|`DTYP_8`|固定 profile 的 dtype，可选 `DTYP_8/16/32`|
|`BENCH_ATYPE_W`|`ATYP_16`|固定 profile 的 offset 编码宽度，可选 `ATYP_16/32`|
|`BENCH_ATYPE_S`|`ATYP_U`|固定 profile 的 offset signedness|
|`BENCH_ATYPE_G`|`GAUTO_1B`|固定 profile 的 offset granularity|
|`BENCH_INV_SIZE`|-1|`creq_inv_size`；-1 表示随机，0～12 分别覆盖 4 B～16 KiB interleave|
|`BENCH_WPID`|0|固定 WARP ID，可用于定向选择非零 SPACE_BLK group|
|`BENCH_WPNUM`|-1|`creq_wpnum`；-1 表示从 1/2/4 中随机|
|`M2V_UNIQUE`|0|post-randomize item 的 M2V active 地址唯一开关；V2M 始终检查，original 保持 legacy constraint|
|`BENCH_CONSTRAINT_SET`|`ALL`|启用全部约束，或关闭一组约束用于瓶颈隔离|
|`BENCH_REUSE_ITEM`|1|1 表示重复随机化同一对象；0 会在每次尝试前重新创建对象|
|`BENCH_SUPPRESS_ITEM_WARNINGS`|1|屏蔽 item 的 post-randomize 地址 warning，避免日志开销污染结果|

固定 profile 默认使用 `DTYP_8 + ATYP_16 + ATYP_U + GAUTO_1B`，可以用上述 plusarg
覆盖。性能对比必须让不同实现使用完全相同的 dtype/atype 配置。可选 profile 为：

- `RANDOM`；
- `LDST_S_LOC`、`LDST_S_WRP`、`LDST_S_BLK`；
- `LDST_V_LOC`、`LDST_V_WRP`、`LDST_V_BLK`；
- `LDSTE_S_LOC`、`LDSTE_S_WRP`、`LDSTE_S_BLK`；
- `LDSTE_V_LOC`、`LDSTE_V_WRP`、`LDSTE_V_BLK`。

固定 profile 默认使用 `BENCH_WPID=0`，并在所选 WARP group 内随机 base；original 和
post-randomize 会额外保留末尾 4 KiB 安全余量。可通过 `BENCH_WPID` 和
`BENCH_WPNUM` 定向选择非零 SPACE_BLK group。对于
`V2M + LDSTE_S + SPACE_WRP/SPACE_BLK`，benchmark 还会强制 mask 每个 active thread
的 element 0；M2V 不受这条限制。

Constraint set 的可选值为：

- `ALL`：启用 transaction 的全部约束；
- `NO_ADDR_BOUND`：只关闭 `c_addr_bound`；
- `NO_SOLVE_ORDER`：只关闭从原约束块拆出的 `c_offs_elem_solve_order`；
- `NO_LDSTE_LOC_UNIQUE`：只关闭 SPACE_LOC 的逐线程 uniqueness；
- `NO_LDSTE_GLOBAL_UNIQUE`：只关闭 SPACE_WRP/BLK 的全局 uniqueness；
- `NO_LDST_RANGE`：只关闭 SPACE_WRP/BLK 的 thread range non-overlap；
- `NO_COLLISION`：关闭三组 uniqueness/non-overlap，保留 solve-order；
- `NO_UNIQUENESS`：关闭 solve-order 和三组 collision 约束，保持与拆分前 benchmark 的含义一致；
- `CORE`：同时关闭 `c_addr_bound` 和原 `c_addr_offs_elem_ne` 拆出的全部约束。

除 `ALL` 外的 constraint set 只用于判断时间消耗来自哪个约束组，产生的 item 不代表
合法 DUT 激励。
如果需要观察关闭约束后产生的越界地址，可以设置 `BENCH_SUPPRESS_ITEM_WARNINGS=0`；
这种运行的耗时不能再和正常基准直接比较。

例如固定 seed 测量本轮实验使用的 `LDSTE_V + SPACE_BLK`：

```sh
scripts/ubuntu/run_shmins_random_benchmark.sh run \
  +BENCH_PROFILE=LDSTE_V_BLK \
  +BENCH_ITERATIONS=100 \
  +BENCH_WARMUP=5 \
  +ntb_random_seed=12345
```

只关闭本 profile 实际使用的全局 uniqueness：

```sh
scripts/ubuntu/run_shmins_random_benchmark.sh run \
  +BENCH_PROFILE=LDSTE_V_BLK \
  +BENCH_CONSTRAINT_SET=NO_LDSTE_GLOBAL_UNIQUE \
  +BENCH_ITERATIONS=100 \
  +ntb_random_seed=12345
```

使用相同 profile、constraint set 和 seed 对比两种 item 实现：

```sh
BENCH_ITERATIONS=100 BENCH_WARMUP=5 \
  scripts/ubuntu/run_shmins_random_benchmark.sh compare \
  +ntb_random_seed=12345
```

独立的 `POST_RANDOMIZE` item 保留 `c_addr_bound`、`c_offs_width` 和
`c_offs_align`，将 solver 中的 collision constraint 替换为空约束。它按不同 itype
修复 active offset：`LDSTE_V` 逐 element 生成，`LDSTE_S` 每个 thread 生成一个
stride，`LDST_S/LDST_V` 每个 thread 生成一个起始 offset。`SPACE_LOC` 的唯一性范围
是单个 thread，`SPACE_WRP/SPACE_BLK` 则跨所有 active thread。M2V 开启可选
uniqueness 时，`LDSTE_S` 的 element 0 不参与冲突检查，因为该地址不受 stride 影响，
多个线程读取该地址是合法行为。

例如测量默认不要求 unique 的 M2V：

```sh
BENCH_IMPL=post_randomize \
  scripts/ubuntu/run_shmins_random_benchmark.sh run \
  +BENCH_PROFILE=LDST_S_WRP \
  +BENCH_RW=M2V \
  +M2V_UNIQUE=0
```

## 结果字段

`sweep` 使用同一个 `LDSTE_V_BLK` profile 依次测量所有 constraint set：

```sh
BENCH_ITERATIONS=100 BENCH_WARMUP=5 \
  scripts/ubuntu/run_shmins_random_benchmark.sh sweep \
  +ntb_random_seed=12345
```

日志中的 `SHMINS_RANDOM_BENCH_RESULT` 包含：

- `elapsed_ms`：正式 randomize 循环的单调时钟耗时，单位为 ms；
- `ms_per_attempt` 和 `attempts_per_second`：主要性能指标；
- `successes`、`failures`：求解结果，性能对比必须要求 failures 为 0；
- `checksum`：由随机结果计算，用于确认循环确实产生了数据；
- `reuse_item`：区分纯重复 randomize 和包含 object allocation 的模式。
- `item_impl`：区分原始 solver-unique 与 post-randomize 实现。
- `inv_size`、`wpid`、`wpnum`：定向配置值；-1 表示该字段由 transaction 随机化。
- `retries`、`validation_errors`：过程式生成的 reject 总数和独立 validator 错误数。

比较 constraint 优化前后时，应使用同一 VCS 版本、同一 profile、constraint set、次数、
reuse 设置和 seed，并至少重复三次。先用较小次数确认不会长时间卡住，再增加
`BENCH_ITERATIONS` 降低计时噪声。
