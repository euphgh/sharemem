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
```

`original.f` 和 `post_randomize.f` 分别选择原始 solver 实现和独立的
post-randomize 实现。两个文件都定义名为 `shmins_sequence_item` 的 class，因此不能
出现在同一次编译中；编译结果分别写入 `build/original/` 和
`build/post_randomize/`。

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
|`BENCH_PROFILE`|`LDSTE_V_BLK`|随机分支或固定 instruction/space profile|
|`BENCH_RW`|`V2M`|固定 profile 的方向，可选 `V2M` 或 `M2V`|
|`M2V_UNIQUE`|0|post-randomize item 的 M2V active 地址唯一开关；V2M 始终检查，original 保持 legacy constraint|
|`BENCH_CONSTRAINT_SET`|`ALL`|启用全部约束，或关闭一组约束用于瓶颈隔离|
|`BENCH_REUSE_ITEM`|1|1 表示重复随机化同一对象；0 会在每次尝试前重新创建对象|
|`BENCH_SUPPRESS_ITEM_WARNINGS`|1|屏蔽 item 的 post-randomize 地址 warning，避免日志开销污染结果|

固定 profile 都使用 `DTYP_8 + ATYP_16 + ATYP_U + GAUTO_1B`，避免 dtype/atype 分支
变化干扰对比。可选值为：

- `RANDOM`；
- `LDST_S_LOC`、`LDST_S_WRP`、`LDST_S_BLK`；
- `LDST_V_LOC`、`LDST_V_WRP`、`LDST_V_BLK`；
- `LDSTE_S_LOC`、`LDSTE_S_WRP`、`LDSTE_S_BLK`；
- `LDSTE_V_LOC`、`LDSTE_V_WRP`、`LDSTE_V_BLK`。

`LDSTE_V_BLK` 还固定 `creq_wpid=0`，并在 WARP group 0 内随机 base、保留末尾
4 KiB 安全余量。该限制避免现有 `c_addr_bound` 产生无法通过 unsigned offset 回到目标
WARP group 的组合，并同时应用于两种 item 实现。对于
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

比较 constraint 优化前后时，应使用同一 VCS 版本、同一 profile、constraint set、次数、
reuse 设置和 seed，并至少重复三次。先用较小次数确认不会长时间卡住，再增加
`BENCH_ITERATIONS` 降低计时噪声。
