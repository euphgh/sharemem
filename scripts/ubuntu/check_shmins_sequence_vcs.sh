#!/usr/bin/env bash
#
# 在 Ubuntu VCS 环境中编译 SHMINS sequence 空 design example。

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  scripts/ubuntu/check_shmins_sequence_vcs.sh <目标> [VCS 额外参数...]

目标：
  compile  编译 split sequence item 和 shmins_mst_unit_sequence，不包含 DUT
  clean    删除本 example 的 build 目录

环境变量：
  VCS          VCS 可执行文件，默认 vcs
  UVM_VERSION  VCS -ntb_opts 使用的 UVM 版本，默认 uvm-1.2
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
    compile | clean)
        ;;
    *)
        printf '错误：未知目标：%s\n' "$target" >&2
        usage >&2
        exit 2
        ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "$script_dir/../.." rev-parse --show-toplevel)"
example_dir="$repo_root/examples/shmins_sequence_compile"
build_dir="$example_dir/build"
sequence_dir="$repo_root/ver_common/uvc/shmins_agent/sequences"
utility_package="$repo_root/ut_shm/util/shm_util_package.sv"
vcs_bin="${VCS:-vcs}"
uvm_version="${UVM_VERSION:-uvm-1.2}"

compile_empty_design() {
    local simv="$build_dir/simv"

    if ! command -v -- "$vcs_bin" >/dev/null 2>&1; then
        printf '错误：找不到 VCS 可执行文件：%s\n' "$vcs_bin" >&2
        exit 2
    fi
    if [[ ! -f "$utility_package" || ! -f "$example_dir/tb.sv" ]]; then
        printf '错误：缺少 SHMINS sequence compile 输入\n' >&2
        exit 2
    fi

    mkdir -p -- "$build_dir"
    printf 'Ubuntu VCS：编译 SHMINS sequence 空 design\n'
    (
        cd -- "$build_dir"
        "$vcs_bin" \
            -full64 \
            -sverilog \
            -ntb_opts "$uvm_version" \
            -timescale=1ns/1ps \
            "+incdir+$repo_root/ut_shm/util" \
            "+incdir+$sequence_dir" \
            "$utility_package" \
            "$example_dir/tb.sv" \
            "$@" \
            -top shmins_sequence_compile_tb \
            -o "$simv" \
            -l compile.log
    )
}

case "$target" in
    compile)
        compile_empty_design "$@"
        ;;
    clean)
        rm -rf -- "$build_dir"
        printf '已删除：%s\n' "$build_dir"
        ;;
esac

