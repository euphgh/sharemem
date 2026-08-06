#!/usr/bin/env bash
#
# 在 Ubuntu VCS 环境中编译或运行 VLM reservation 组件测试。

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  scripts/ubuntu/check_vlm_reservation_vcs.sh <目标> [VCS 额外参数...]

目标：
  compile        联合编译 reservation agent、memory agent 和 RpuShmTop stub
  alignment      编译并运行 reservation 地址定向测试
  external-busy  编译并运行 external busy plusarg 定向测试
  all            依次执行以上三个目标
  clean          删除本脚本生成的 build 目录

环境变量：
  VCS          VCS 可执行文件，默认 vcs
  UVM_VERSION  VCS -ntb_opts 使用的 UVM 版本，默认 uvm-1.2
  RPU_DIR      design 根目录，默认 <repo>/design

本脚本必须在配置了 VCS/UVM 环境的 Ubuntu 主机上执行。所有构建产物写入
examples/vlm_reservation_compile/build/。
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
    compile | alignment | external-busy | all | clean)
        ;;
    *)
        printf '错误：未知目标：%s\n' "$target" >&2
        usage >&2
        exit 2
        ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "$script_dir/../.." rev-parse --show-toplevel)"
example_dir="$repo_root/examples/vlm_reservation_compile"
build_dir="$example_dir/build"
design_root="${RPU_DIR:-$repo_root/design}"
vcs_bin="${VCS:-vcs}"
uvm_version="${UVM_VERSION:-uvm-1.2}"

utility_package="$repo_root/ut_shm/util/shm_util_package.sv"
clock_interface="$repo_root/ver_common/uvc/clock/clk_if.sv"
memory_agent_dir="$repo_root/ver_common/uvc/vlm_memory_agent"
reservation_agent_dir="$repo_root/ver_common/uvc/vlm_reservation_agent"
memory_interface="$memory_agent_dir/vlm_memory_interface.sv"
reservation_interface="$reservation_agent_dir/vlm_reservation_interface.sv"
dut_source="$design_root/RpuTop/src/RpuShm/RpuShmTop.sv"

vcs_common=(
    "$vcs_bin"
    -full64
    -sverilog
    -ntb_opts "$uvm_version"
    -timescale=1ns/1ps
    "+incdir+$repo_root/ut_shm/util"
    "+incdir+$memory_agent_dir"
    "+incdir+$reservation_agent_dir"
)
vcs_extra=("$@")

require_file() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        printf '错误：缺少编译输入：%s\n' "$path" >&2
        exit 2
    fi
}

prepare_build() {
    if ! command -v -- "$vcs_bin" >/dev/null 2>&1; then
        printf '错误：找不到 VCS 可执行文件：%s\n' "$vcs_bin" >&2
        exit 2
    fi

    require_file "$utility_package"
    require_file "$clock_interface"
    mkdir -p -- "$build_dir"
}

compile_integration() {
    local simv="$build_dir/simv"

    prepare_build
    require_file "$memory_interface"
    require_file "$reservation_interface"
    require_file "$dut_source"
    require_file "$example_dir/tb.sv"

    printf 'Ubuntu VCS：编译 VLM reservation/memory agent 联合环境\n'
    (
        cd -- "$build_dir"
        "${vcs_common[@]}" \
            "$utility_package" \
            "$clock_interface" \
            "$memory_interface" \
            "$reservation_interface" \
            "$dut_source" \
            "$example_dir/tb.sv" \
            "${vcs_extra[@]}" \
            -top tb \
            -o "$simv" \
            -l compile.log
    )
}

run_alignment() {
    local simv="$build_dir/alignment_simv"

    prepare_build
    require_file "$example_dir/alignment_tb.sv"

    printf 'Ubuntu VCS：编译并运行 reservation alignment 定向测试\n'
    (
        cd -- "$build_dir"
        "${vcs_common[@]}" \
            "$utility_package" \
            "$clock_interface" \
            "$example_dir/alignment_tb.sv" \
            "${vcs_extra[@]}" \
            -top alignment_tb \
            -o "$simv" \
            -l alignment_compile.log
        "$simv" -l alignment_test.log
    )
}

run_external_busy() {
    local simv="$build_dir/external_busy_simv"

    prepare_build
    require_file "$memory_interface"
    require_file "$reservation_interface"
    require_file "$example_dir/external_busy_tb.sv"

    printf 'Ubuntu VCS：编译并运行 reservation external busy 定向测试\n'
    (
        cd -- "$build_dir"
        "${vcs_common[@]}" \
            "$utility_package" \
            "$clock_interface" \
            "$memory_interface" \
            "$reservation_interface" \
            "$example_dir/external_busy_tb.sv" \
            "${vcs_extra[@]}" \
            -top external_busy_tb \
            -o "$simv" \
            -l external_busy_compile.log
        "$simv" +EXTERNAL_BUSY_PERCENT=100 -l external_busy_test.log
    )
}

clean_build() {
    rm -rf -- "$build_dir"
    printf '已删除：%s\n' "$build_dir"
}

case "$target" in
    compile)
        compile_integration
        ;;
    alignment)
        run_alignment
        ;;
    external-busy)
        run_external_busy
        ;;
    all)
        compile_integration
        run_alignment
        run_external_busy
        ;;
    clean)
        clean_build
        ;;
esac
