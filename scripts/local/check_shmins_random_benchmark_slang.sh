#!/usr/bin/env bash
#
# 在本地检查正式 shmins_sequence_item benchmark 的 SystemVerilog 语法。

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  scripts/local/check_shmins_random_benchmark_slang.sh [slang 额外参数...]

环境变量：
  SLANG     slang 可执行文件，默认 slang
  UVM_HOME  UVM 源码根目录，默认 <repo>/resources/uvm-1.2

检查公共基类以及 contiguous、strided、indexed 和 VTRANS 子类。
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
collection_dir="$utility_dir/sv-collection/libs"
environment_dir="$repo_root/ut_shm/env"
sequence_dir="$repo_root/ver_common/uvc/shmins_agent/sequences"
vlm_memory_dir="$repo_root/ver_common/uvc/vlm_memory_agent"
example_dir="$repo_root/examples/shmins_random_benchmark"

required_files=(
    "$uvm_src/uvm_pkg.sv"
    "$uvm_src/uvm_macros.svh"
    "$collection_dir/collection_pkg.sv"
    "$utility_dir/shm_util_package.sv"
    "$environment_dir/shm_wtrans_item.svh"
    "$environment_dir/vlm2aa.svh"
    "$vlm_memory_dir/vlm_memory_sequence_item.svh"
    "$sequence_dir/shmins_sequence_item.svh"
    "$sequence_dir/shmins_contiguous_sequence_item.svh"
    "$sequence_dir/shmins_strided_sequence_item.svh"
    "$sequence_dir/shmins_indexed_sequence_item.svh"
    "$sequence_dir/shmins_vtrans_sequence_item.svh"
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

printf '使用 UVM：%s\n' "$uvm_home"
printf '使用 slang 检查正式 sequence item：%s\n' "$slang_bin"
"$slang_bin" \
    --single-unit \
    --compat vcs \
    --std 1800-2017 \
    --top shmins_random_benchmark_tb \
    -D UVM_NO_DPI \
    -I "$uvm_src" \
    -I "$collection_dir" \
    -I "$utility_dir" \
    -I "$environment_dir" \
    -I "$sequence_dir" \
    -I "$vlm_memory_dir" \
    "$uvm_src/uvm_pkg.sv" \
    "$collection_dir/collection_pkg.sv" \
    "$utility_dir/shm_util_package.sv" \
    "$example_dir/shmins_random_benchmark_pkg.sv" \
    "$example_dir/tb.sv" \
    "$@"

cc -std=c99 -Wall -Wextra -Werror -fsyntax-only "$example_dir/benchmark_clock.c"
