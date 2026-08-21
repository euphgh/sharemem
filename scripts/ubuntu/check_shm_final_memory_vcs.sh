#!/usr/bin/env bash
#
# 在 Ubuntu VCS 环境中编译并运行最终 reference/actual memory 比较组件测试。

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
build_dir="$repo_root/examples/shm_reference_compile/build/final_memory"
testbench="$repo_root/examples/shm_reference_compile/final_memory_compare_tb.sv"
vcs_bin="${VCS:-vcs}"
uvm_version="${UVM_VERSION:-uvm-1.2}"

export TB_DIR="${TB_DIR:-$repo_root/ut_shm}"
export VER_CMN="${VER_CMN:-$repo_root/ver_common}"

if ! command -v -- "$vcs_bin" >/dev/null 2>&1; then
    printf '错误：找不到 VCS 可执行文件：%s\n' "$vcs_bin" >&2
    exit 2
fi
if [[ -z "${AXI_VIP_DIR:-}" || ! -d "$AXI_VIP_DIR" ]]; then
    printf '错误：AXI_VIP_DIR 未设置或目录不存在\n' >&2
    exit 2
fi

mkdir -p -- "$build_dir"
(
    cd -- "$build_dir"
    "$vcs_bin" -full64 -sverilog -ntb_opts "$uvm_version" -timescale=1ns/1ps \
        +define+SVT_UVM_TECHNOLOGY +define+SYNOPSYS_SV \
        -f "$TB_DIR/filelist/shm_environment.f" \
        "$testbench" \
        -top shm_final_memory_compare_tb -o "$build_dir/simv" -l compile.log
    "$build_dir/simv" -l test.log
    if ! grep -Eq 'UVM_ERROR[[:space:]]*:[[:space:]]*0' test.log ||
       ! grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*0' test.log ||
       ! grep -Fq '[SHM_FINAL_MEMORY_COMPARE_TEST] ORDER-SCB-001..005 and ORDER-COV exact/partial matrix: PASS' \
           test.log; then
        printf '错误：最终 memory compare 组件测试未通过\n' >&2
        tail -n 100 -- test.log >&2
        exit 1
    fi
)
