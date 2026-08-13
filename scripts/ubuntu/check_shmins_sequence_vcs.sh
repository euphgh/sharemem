#!/usr/bin/env bash
#
# 在 Ubuntu VCS 环境中编译或测试 SHMINS sequence 空 design example。

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  scripts/ubuntu/check_shmins_sequence_vcs.sh <目标> [VCS 额外参数...]

目标：
  compile  编译 split sequence item 和 shmins_mst_unit_sequence，不包含 DUT
  copy     编译并运行 sequence-item copy/compare 组件测试
  all      依次执行 compile 和 copy
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
    compile | copy | all | clean)
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

check_uvm_test_log() {
    local log_file="$1"
    local pass_marker="$2"

    if ! grep -Eq 'UVM_ERROR[[:space:]]*:[[:space:]]*0' "$log_file" ||
       ! grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*0' "$log_file" ||
       ! grep -Fq -- "$pass_marker" "$log_file"; then
        printf '错误：UVM 组件测试未通过：%s\n' "$log_file" >&2
        tail -n 80 -- "$log_file" >&2
        return 1
    fi
}

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

run_copy_test() {
    local simv="$build_dir/copy_simv"
    local copy_tb="$example_dir/copy_tb.sv"

    if ! command -v -- "$vcs_bin" >/dev/null 2>&1; then
        printf '错误：找不到 VCS 可执行文件：%s\n' "$vcs_bin" >&2
        exit 2
    fi
    if [[ ! -f "$utility_package" || ! -f "$copy_tb" ]]; then
        printf '错误：缺少 SHMINS transaction copy 测试输入\n' >&2
        exit 2
    fi

    mkdir -p -- "$build_dir"
    printf 'Ubuntu VCS：编译并运行 SHMINS transaction copy/compare 组件测试\n'
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
            "$copy_tb" \
            "$@" \
            -top shmins_transaction_copy_tb \
            -o "$simv" \
            -l copy_compile.log
        "$simv" -l copy_test.log
        check_uvm_test_log copy_test.log \
            '[SHMINS_COPY_TEST] transaction copy and compare component test: PASS'
    )
}

case "$target" in
    compile)
        compile_empty_design "$@"
        ;;
    copy)
        run_copy_test "$@"
        ;;
    all)
        compile_empty_design "$@"
        run_copy_test "$@"
        ;;
    clean)
        rm -rf -- "$build_dir"
        printf '已删除：%s\n' "$build_dir"
        ;;
esac
