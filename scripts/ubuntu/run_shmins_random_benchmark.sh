#!/usr/bin/env bash
#
# 在 Ubuntu VCS 环境中编译和运行 shmins_sequence_item randomize 性能基准。

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  scripts/ubuntu/run_shmins_random_benchmark.sh <目标> [simv 参数...]

目标：
  compile  编译最小 UVM benchmark
  run      必要时先编译，再运行一次；后续参数原样传给 simv
  sweep    依次运行 README 中的七个 profile；后续参数原样传给每次 simv
  clean    删除本 example 的 build 目录

环境变量：
  VCS             VCS 可执行文件，默认 vcs
  UVM_VERSION     VCS -ntb_opts 使用的 UVM 版本，默认 uvm-1.2
  VCS_USER_OPTS   追加到 VCS 编译命令的空白分隔参数
  BENCH_ITERATIONS  sweep 每个 profile 的次数，默认 10
  BENCH_WARMUP      sweep 每个 profile 的预热次数，默认 2

所有生成文件写入 examples/shmins_random_benchmark/build/。
EOF
}

if (($# == 0)); then
    usage >&2
    exit 2
fi

target="$1"
shift

case "$target" in
    -h | --help)
        usage
        exit 0
        ;;
    compile | run | sweep | clean)
        ;;
    *)
        printf '错误：未知目标：%s\n' "$target" >&2
        usage >&2
        exit 2
        ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "$script_dir/../.." rev-parse --show-toplevel)"
example_dir="$repo_root/examples/shmins_random_benchmark"
build_dir="$example_dir/build"
utility_dir="$repo_root/ut_shm/util"
sequence_dir="$repo_root/ver_common/uvc/shmins_agent/sequences"

vcs_bin="${VCS:-vcs}"
uvm_version="${UVM_VERSION:-uvm-1.2}"
simv="$build_dir/simv"
time_bin="/usr/bin/time"
vcs_user_opts=()
benchmark_sources=(
    "$utility_dir/shm_util_package.sv"
    "$utility_dir/bit_rt_range.svh"
    "$sequence_dir/shmins_sequence_item.svh"
    "$sequence_dir/shmins_seq_item_constraints.svh"
    "$example_dir/shmins_random_benchmark_pkg.sv"
    "$example_dir/tb.sv"
    "$example_dir/benchmark_clock.c"
)

if [[ -n "${VCS_USER_OPTS:-}" ]]; then
    read -r -a vcs_user_opts <<<"$VCS_USER_OPTS"
fi

require_file() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        printf '错误：缺少编译输入：%s\n' "$path" >&2
        exit 2
    fi
}

compile_benchmark() {
    if ! command -v -- "$vcs_bin" >/dev/null 2>&1; then
        printf '错误：找不到 VCS 可执行文件：%s\n' "$vcs_bin" >&2
        exit 2
    fi

    for source_file in "${benchmark_sources[@]}"; do
        require_file "$source_file"
    done
    mkdir -p -- "$build_dir"

    printf 'Ubuntu VCS：编译 shmins randomize benchmark\n'
    (
        cd -- "$build_dir"
        "$vcs_bin" \
            -full64 \
            -sverilog \
            -ntb_opts "$uvm_version" \
            -timescale=1ns/1ps \
            "+incdir+$utility_dir" \
            "+incdir+$sequence_dir" \
            "$utility_dir/shm_util_package.sv" \
            "$example_dir/shmins_random_benchmark_pkg.sv" \
            "$example_dir/tb.sv" \
            "$example_dir/benchmark_clock.c" \
            "${vcs_user_opts[@]}" \
            -top shmins_random_benchmark_tb \
            -o "$simv" \
            -l compile.log
    )
}

ensure_compiled() {
    local source_file

    if [[ ! -x "$simv" ]]; then
        compile_benchmark
        return
    fi

    for source_file in "${benchmark_sources[@]}"; do
        require_file "$source_file"
        if [[ "$source_file" -nt "$simv" ]]; then
            printf '检测到 benchmark 源码更新，重新编译\n'
            compile_benchmark
            return
        fi
    done
}

run_benchmark() {
    local log_name="$1"
    shift

    ensure_compiled
    if [[ ! -x "$time_bin" ]]; then
        printf '错误：缺少计时工具：%s\n' "$time_bin" >&2
        exit 2
    fi

    printf 'Ubuntu VCS：运行 shmins randomize benchmark\n'
    (
        cd -- "$build_dir"
        "$time_bin" -p "$simv" \
            +UVM_TESTNAME=shmins_random_benchmark_test \
            "$@"
    ) 2>&1 | tee "$build_dir/$log_name"
}

run_sweep() {
    local iterations="${BENCH_ITERATIONS:-10}"
    local warmup="${BENCH_WARMUP:-2}"
    local profiles=(
        RANDOM
        LDST_V_LOC
        LDST_V_WRP
        LDST_V_BLK
        LDSTE_V_LOC
        LDSTE_V_WRP
        LDSTE_V_BLK
    )

    for profile in "${profiles[@]}"; do
        run_benchmark "${profile,,}.log" \
            "+BENCH_PROFILE=$profile" \
            "+BENCH_ITERATIONS=$iterations" \
            "+BENCH_WARMUP=$warmup" \
            "$@"
    done
}

clean_build() {
    rm -rf -- "$build_dir"
    printf '已删除：%s\n' "$build_dir"
}

case "$target" in
    compile)
        compile_benchmark
        ;;
    run)
        run_benchmark "run.log" "$@"
        ;;
    sweep)
        run_sweep "$@"
        ;;
    clean)
        clean_build
        ;;
esac
