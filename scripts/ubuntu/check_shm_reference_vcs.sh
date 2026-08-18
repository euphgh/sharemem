#!/usr/bin/env bash
#
# 在 Ubuntu VCS 环境中编译并运行 standalone SHM reference 组件测试。

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
build_dir="$repo_root/examples/shm_reference_compile/build"
testbench="$repo_root/examples/shm_reference_compile/gid_isolation_tb.sv"
vcs_bin="${VCS:-vcs}"
uvm_version="${UVM_VERSION:-uvm-1.2}"

export TB_DIR="${TB_DIR:-$repo_root/ut_shm}"
export VER_CMN="${VER_CMN:-$repo_root/ver_common}"

if ! command -v -- "$vcs_bin" >/dev/null 2>&1; then
    printf '错误：找不到 VCS 可执行文件：%s\n' "$vcs_bin" >&2
    exit 2
fi

mkdir -p -- "$build_dir"
(
    cd -- "$build_dir"
    "$vcs_bin" -full64 -sverilog -ntb_opts "$uvm_version" -timescale=1ns/1ps \
        +incdir+"$TB_DIR/util/sv-collection/libs" \
        +incdir+"$TB_DIR/util" \
        +incdir+"$TB_DIR/env" \
        +incdir+"$VER_CMN/uvc/shmins_agent/sequences" \
        +incdir+"$VER_CMN/uvc/vlm_memory_agent" \
        "$TB_DIR/util/sv-collection/libs/collection_pkg.sv" \
        "$TB_DIR/util/shm_util_package.sv" \
        "$TB_DIR/env/shm_seq_item_package.sv" \
        "$testbench" \
        -top shm_reference_gid_tb -o "$build_dir/simv" -l compile.log
    "$build_dir/simv" -l test.log
    if ! grep -Eq 'UVM_ERROR[[:space:]]*:[[:space:]]*0' test.log ||
       ! grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*0' test.log ||
       ! grep -Fq '[SHM_REFERENCE_GID_TEST] reference gid-isolation component test: PASS' test.log; then
        printf '错误：SHM reference gid-isolation 组件测试未通过\n' >&2
        tail -n 100 test.log >&2
        exit 1
    fi
)
