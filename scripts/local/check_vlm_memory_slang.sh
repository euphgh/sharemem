#!/usr/bin/env bash
#
# 使用本机 slang 和 UVM 1.2 检查 VLM memory slave agent 组件。
#
# 检查 interface、transaction、config、monitor、driver、sequencer 和 agent。

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  scripts/local/check_vlm_memory_slang.sh [slang 额外参数...]

环境变量：
  SLANG     slang 可执行文件，默认 slang
  UVM_HOME  UVM 源码根目录，默认 <repo>/resources/uvm-1.2

示例：
  scripts/local/check_vlm_memory_slang.sh
  scripts/local/check_vlm_memory_slang.sh --quiet
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "$script_dir/.." rev-parse --show-toplevel)"

slang_bin="${SLANG:-slang}"
uvm_home="${UVM_HOME:-$repo_root/resources/uvm-1.2}"
uvm_src="$uvm_home/src"
memory_agent_dir="$repo_root/ver_common/uvc/vlm_memory_agent"

if ! command -v "$slang_bin" >/dev/null 2>&1; then
    printf '错误：找不到 slang：%s\n' "$slang_bin" >&2
    exit 1
fi

if [[ ! -f "$uvm_src/uvm_pkg.sv" || ! -f "$uvm_src/uvm_macros.svh" ]]; then
    printf '错误：UVM_HOME 中缺少 UVM 1.2 源码：%s\n' "$uvm_home" >&2
    exit 1
fi

required_files=(
    "$repo_root/ut_shm/util/shm_util_package.sv"
    "$memory_agent_dir/vlm_memory_interface.sv"
    "$memory_agent_dir/vlm_memory_sequence_item.svh"
    "$memory_agent_dir/vlm_memory_slv_agent_config.svh"
    "$memory_agent_dir/vlm_memory_monitor.svh"
    "$memory_agent_dir/vlm_memory_slv_driver.svh"
    "$memory_agent_dir/vlm_memory_slv_sequencer.svh"
    "$memory_agent_dir/vlm_memory_slv_agent.svh"
)

for required_file in "${required_files[@]}"; do
    if [[ ! -f "$required_file" ]]; then
        printf '错误：缺少待检查文件：%s\n' "$required_file" >&2
        exit 1
    fi
done

build_dir="$(mktemp -d "${TMPDIR:-/tmp}/sharemem-vlm-memory-slang.XXXXXX")"
trap 'rm -rf -- "$build_dir"' EXIT

testbench="$build_dir/vlm_memory_slang_tb.sv"

cat >"$testbench" <<'SYSTEMVERILOG'
package vlm_memory_slang_test_pkg;
  import uvm_pkg::*;
  import shm_util_package::*;

  `include "uvm_macros.svh"
  `include "vlm_memory_sequence_item.svh"
  `include "vlm_memory_slv_agent_config.svh"
  `include "vlm_memory_monitor.svh"
  `include "vlm_memory_slv_driver.svh"
  `include "vlm_memory_slv_sequencer.svh"
  `include "vlm_memory_slv_agent.svh"
endpackage : vlm_memory_slang_test_pkg

module vlm_memory_slang_tb;
  import uvm_pkg::*;
  import vlm_memory_slang_test_pkg::*;

  logic clk;
  logic rst_n;
  vlm_memory_interface memory_if(clk, rst_n);

  initial begin
    vlm_memory_slv_agent agent;
    vlm_memory_slv_agent_config agent_config;

    agent = new("agent", null);
    agent_config = new("agent_config");
  end
endmodule : vlm_memory_slang_tb
SYSTEMVERILOG

printf '使用 slang：%s\n' "$slang_bin"
printf '使用 UVM：%s\n' "$uvm_home"

"$slang_bin" \
    --single-unit \
    --compat vcs \
    --std 1800-2017 \
    --top vlm_memory_slang_tb \
    -D UVM_NO_DPI \
    -I "$uvm_src" \
    -I "$memory_agent_dir" \
    "$uvm_src/uvm_pkg.sv" \
    "$repo_root/ut_shm/util/shm_util_package.sv" \
    "$memory_agent_dir/vlm_memory_interface.sv" \
    "$testbench" \
    "$@"
