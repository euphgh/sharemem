#!/usr/bin/env bash
#
# 在 Ubuntu VCS 环境中编译和运行正式 shmins_sequence_item randomize 基准。

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  scripts/ubuntu/run_shmins_random_benchmark.sh <目标> [simv 参数...]

目标：
  compile  编译正式 sequence item 的最小 UVM benchmark
  run      必要时先编译，再运行一次
  clean    删除本 example 的 build 目录

环境变量：
  VCS              VCS 可执行文件，默认 vcs
  UVM_VERSION      VCS -ntb_opts 使用的 UVM 版本，默认 uvm-1.2
  VCS_USER_OPTS    追加到 VCS 编译命令的空白分隔参数
  BENCH_ITERATIONS compare、sweep 的迭代次数，默认 10
  BENCH_WARMUP     compare、sweep 的预热次数，默认 2

生成物保存在 build/split，split 是过程式 topology 实现沿用的 benchmark 标签。
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
    compile | run | clean)
        ;;
    *)
        printf '错误：未知目标：%s\n' "$target" >&2
        usage >&2
        exit 2
        ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && git rev-parse --show-toplevel)"
example_dir="$repo_root/examples/shmins_random_benchmark"
build_root="$example_dir/build"
utility_dir="$repo_root/ut_shm/util"
collection_dir="$utility_dir/sv-collection/libs"
environment_dir="$repo_root/ut_shm/env"
sequence_dir="$repo_root/ver_common/uvc/shmins_agent/sequences"
vlm_memory_dir="$repo_root/ver_common/uvc/vlm_memory_agent"

selected_impl="split"
vcs_bin="${VCS:-vcs}"
uvm_version="${UVM_VERSION:-uvm-1.2}"
time_bin="/usr/bin/time"
vcs_user_opts=()

if [[ -n "${VCS_USER_OPTS:-}" ]]; then
    read -r -a vcs_user_opts <<<"$VCS_USER_OPTS"
fi

validate_implementation() {
    local implementation="$1"

    if [[ "$implementation" != "split" ]]; then
        printf '错误：仅支持正式 split topology 实现：%s\n' "$implementation" >&2
        exit 2
    fi
}

require_file() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        printf '错误：缺少编译输入：%s\n' "$path" >&2
        exit 2
    fi
}

collect_sources() {
    local implementation="$1"

    benchmark_sources=(
        "$collection_dir/collection_pkg.sv"
        "$utility_dir/shm_util_package.sv"
        "$utility_dir/bit_rt_range.svh"
        "$environment_dir/shm_wtrans_item.svh"
        "$environment_dir/vlm2aa.svh"
        "$vlm_memory_dir/vlm_memory_sequence_item.svh"
        "$example_dir/shmins_random_benchmark_pkg.sv"
        "$example_dir/shmins_random_cross_benchmark_test.svh"
        "$example_dir/tb.sv"
        "$example_dir/benchmark_clock.c"
        "$example_dir/${implementation}.f"
    )
    benchmark_sources+=(
        "$sequence_dir/shmins_sequence_item.svh"
        "$sequence_dir/shmins_contiguous_sequence_item.svh"
        "$sequence_dir/shmins_strided_sequence_item.svh"
        "$sequence_dir/shmins_indexed_sequence_item.svh"
        "$sequence_dir/shmins_vtrans_sequence_item.svh"
    )
}

compile_benchmark() {
    local implementation="$1"
    local build_dir="$build_root/$implementation"
    local filelist="$example_dir/${implementation}.f"
    local simv="$build_dir/simv"

    validate_implementation "$implementation"
    if ! command -v -- "$vcs_bin" >/dev/null 2>&1; then
        printf '错误：找不到 VCS 可执行文件：%s\n' "$vcs_bin" >&2
        exit 2
    fi

    collect_sources "$implementation"
    for source_file in "${benchmark_sources[@]}"; do
        require_file "$source_file"
    done
    mkdir -p -- "$build_dir"

    printf 'Ubuntu VCS：编译 %s shmins randomize benchmark\n' "$implementation"
    (
        # hx16 的旧 Bash 在 nounset 模式下展开空数组会报 unbound variable。
        set +u
        export RPU_DIR="$repo_root"
        cd -- "$build_dir"
        "$vcs_bin" \
            -full64 \
            -sverilog \
            -ntb_opts "$uvm_version" \
            -timescale=1ns/1ps \
            -f "$filelist" \
            "${vcs_user_opts[@]}" \
            -top shmins_random_benchmark_tb \
            -o "$simv" \
            -l compile.log
    )
}

ensure_compiled() {
    local implementation="$1"
    local simv="$build_root/$implementation/simv"

    collect_sources "$implementation"
    if [[ ! -x "$simv" ]]; then
        compile_benchmark "$implementation"
        return
    fi

    for source_file in "${benchmark_sources[@]}"; do
        require_file "$source_file"
        if [[ "$source_file" -nt "$simv" ]]; then
            printf '检测到 %s benchmark 源码更新，重新编译\n' "$implementation"
            compile_benchmark "$implementation"
            return
        fi
    done
}

run_benchmark() {
    local implementation="$1"
    local log_name="$2"
    local build_dir="$build_root/$implementation"
    local simv="$build_dir/simv"
    shift 2

    validate_implementation "$implementation"
    ensure_compiled "$implementation"
    if [[ ! -x "$time_bin" ]]; then
        printf '错误：缺少计时工具：%s\n' "$time_bin" >&2
        exit 2
    fi

    printf 'Ubuntu VCS：运行 %s shmins randomize benchmark\n' "$implementation"
    (
        cd -- "$build_dir"
        "$time_bin" -p "$simv" \
            +UVM_TESTNAME=shmins_random_benchmark_test \
            "$@"
    ) 2>&1 | tee "$build_dir/$log_name"

    # UVM_FATAL can terminate this VCS build with process status zero. Treat a
    # non-zero UVM error/fatal summary as a failed benchmark invocation.
    if grep -Eq 'UVM_(ERROR|FATAL) :[[:space:]]+[1-9][0-9]*' \
        "$build_dir/$log_name"; then
        printf '错误：%s benchmark 报告 UVM_ERROR/UVM_FATAL\n' "$implementation" >&2
        return 1
    fi
}

clean_build() {
    rm -rf -- "$build_root"
    printf '已删除：%s\n' "$build_root"
}

validate_implementation "$selected_impl"
case "$target" in
    compile)
        compile_benchmark "$selected_impl"
        ;;
    run)
        run_benchmark "$selected_impl" "run.log" "$@"
        ;;
    clean)
        clean_build
        ;;
esac
