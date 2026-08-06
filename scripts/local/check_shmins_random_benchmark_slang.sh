#!/usr/bin/env bash
#
# 在 macOS 上检查 shmins_sequence_item randomize 基准环境的 SystemVerilog 语法。

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  scripts/local/check_shmins_random_benchmark_slang.sh [slang 额外参数...]

环境变量：
  SLANG     slang 可执行文件，默认 slang
  UVM_HOME  UVM 源码根目录，默认 <repo>/resources/uvm-1.2

本脚本只做语法/语义检查，不运行 constraint solver，也不产生性能结果。
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "$script_dir/../.." rev-parse --show-toplevel)"

slang_bin="${SLANG:-slang}"
uvm_home="${UVM_HOME:-$repo_root/resources/uvm-1.2}"
uvm_src="$uvm_home/src"
utility_dir="$repo_root/ut_shm/util"
sequence_dir="$repo_root/ver_common/uvc/shmins_agent/sequences"
example_dir="$repo_root/examples/shmins_random_benchmark"

required_files=(
    "$uvm_src/uvm_pkg.sv"
    "$uvm_src/uvm_macros.svh"
    "$utility_dir/shm_util_package.sv"
    "$sequence_dir/shmins_sequence_item.svh"
    "$sequence_dir/shmins_seq_item_constraints.svh"
    "$example_dir/shmins_random_benchmark_pkg.sv"
    "$example_dir/tb.sv"
    "$example_dir/benchmark_clock.c"
)

if ! command -v -- "$slang_bin" >/dev/null 2>&1; then
    printf '错误：找不到 slang：%s\n' "$slang_bin" >&2
    exit 1
fi

for required_file in "${required_files[@]}"; do
    if [[ ! -f "$required_file" ]]; then
        printf '错误：缺少检查输入：%s\n' "$required_file" >&2
        exit 1
    fi
done

printf '使用 slang：%s\n' "$slang_bin"
printf '使用 UVM：%s\n' "$uvm_home"

"$slang_bin" \
    --single-unit \
    --compat vcs \
    --std 1800-2017 \
    --top shmins_random_benchmark_tb \
    -D UVM_NO_DPI \
    -I "$uvm_src" \
    -I "$utility_dir" \
    -I "$sequence_dir" \
    "$uvm_src/uvm_pkg.sv" \
    "$utility_dir/shm_util_package.sv" \
    "$example_dir/shmins_random_benchmark_pkg.sv" \
    "$example_dir/tb.sv" \
    "$@"

cc -std=c99 -Wall -Wextra -Werror -fsyntax-only "$example_dir/benchmark_clock.c"
