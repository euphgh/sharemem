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
  lifecycle 编译并运行 ordered ack-grace lifecycle 组件测试
  dual-gid-address 编译并运行双 gid 地址与 M2V byte-hazard 组件测试
  mask-monitor 编译并运行 thread-mask monitor/XZ 组件测试
  dontcare-x 编译并运行 don’t-care X utility 精确 slice 组件测试
  dontcare-driver 编译并运行 don’t-care X driver/monitor 四态保真测试
  all      依次执行全部 SHMINS 组件目标
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
    compile | copy | lifecycle | dual-gid-address | mask-monitor | dontcare-x | dontcare-driver | all | clean)
        ;;
    *)
        printf '错误：未知目标：%s\n' "$target" >&2
        usage >&2
        exit 2
        ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
example_dir="$repo_root/examples/shmins_sequence_compile"
build_dir="$example_dir/build"
sequence_dir="$repo_root/ver_common/uvc/shmins_agent/sequences"
shmins_agent_dir="$repo_root/ver_common/uvc/shmins_agent"
memory_agent_dir="$repo_root/ver_common/uvc/vlm_memory_agent"
environment_dir="$repo_root/ut_shm/env"
common_example_dir="$repo_root/examples/common"
mask_monitor_dir="$repo_root/examples/shmins_monitor_compile"
collection_dir="$repo_root/ut_shm/util/sv-collection/libs"
utility_package="$repo_root/ut_shm/util/shm_util_package.sv"
collection_package="$collection_dir/collection_pkg.sv"
clock_interface="$repo_root/ver_common/uvc/clock/clk_if.sv"
shmins_interface="$shmins_agent_dir/shmins_interface.sv"
sequence_item_package="$environment_dir/shm_seq_item_package.sv"
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

check_directed_test_log() {
    local log_file="$1"
    local pass_marker="$2"

    if grep -Eq 'UVM_(ERROR|FATAL)' "$log_file" || ! grep -Fq -- "$pass_marker" "$log_file"; then
        printf '错误：SHMINS lifecycle 组件测试未通过：%s\n' "$log_file" >&2
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

run_lifecycle_test() {
    local simv="$build_dir/lifecycle_simv"
    local lifecycle_tb="$example_dir/lifecycle_tb.sv"

    if ! command -v -- "$vcs_bin" >/dev/null 2>&1; then
        printf '错误：找不到 VCS 可执行文件：%s\n' "$vcs_bin" >&2
        exit 2
    fi
    if [[ ! -f "$collection_package" || ! -f "$utility_package" ||
          ! -f "$clock_interface" || ! -f "$shmins_interface" ||
          ! -f "$sequence_item_package" || ! -f "$lifecycle_tb" ]]; then
        printf '错误：缺少 SHMINS lifecycle 测试输入\n' >&2
        exit 2
    fi

    mkdir -p -- "$build_dir"
    printf 'Ubuntu VCS：编译并运行 ordered ack-grace lifecycle 组件测试\n'
    (
        cd -- "$build_dir"
        "$vcs_bin" \
            -full64 \
            -sverilog \
            -ntb_opts "$uvm_version" \
            -timescale=1ns/1ps \
            "+incdir+$collection_dir" \
            "+incdir+$repo_root/ut_shm/util" \
            "+incdir+$sequence_dir" \
            "+incdir+$shmins_agent_dir" \
            "+incdir+$memory_agent_dir" \
            "+incdir+$environment_dir" \
            "$collection_package" \
            "$utility_package" \
            "$clock_interface" \
            "$shmins_interface" \
            "$sequence_item_package" \
            "$lifecycle_tb" \
            "$@" \
            -top shmins_lifecycle_order_tb \
            -o "$simv" \
            -l lifecycle_compile.log
        "$simv" -l lifecycle_test.log
        check_directed_test_log lifecycle_test.log \
            '[SHMINS_LIFECYCLE_TEST] ordered ack grace regression: PASS'
    )
}

run_dual_gid_address_test() {
    local simv="$build_dir/dual_gid_address_simv"
    local address_tb="$example_dir/dual_gid_address_tb.sv"

    if ! command -v -- "$vcs_bin" >/dev/null 2>&1; then
        printf '错误：找不到 VCS 可执行文件：%s\n' "$vcs_bin" >&2
        exit 2
    fi
    if [[ ! -f "$utility_package" || ! -f "$address_tb" ]]; then
        printf '错误：缺少 SHMINS dual-gid address 测试输入\n' >&2
        exit 2
    fi

    mkdir -p -- "$build_dir"
    printf 'Ubuntu VCS：编译并运行 SHMINS dual-gid address 组件测试\n'
    (
        cd -- "$build_dir"
        "$vcs_bin" -full64 -sverilog -ntb_opts "$uvm_version" -timescale=1ns/1ps \
            "+incdir+$repo_root/ut_shm/util" "+incdir+$sequence_dir" \
            "$utility_package" "$address_tb" "$@" \
            -top shmins_dual_gid_address_tb -o "$simv" -l dual_gid_address_compile.log
        "$simv" -l dual_gid_address_test.log
        check_uvm_test_log dual_gid_address_test.log \
            '[SHMINS_DUAL_GID_ADDRESS_TEST] dual-gid address and M2V byte-hazard component test: PASS'
    )
}

run_mask_monitor_test() {
    local simv="$mask_monitor_dir/build/simv"
    local monitor_tb="$mask_monitor_dir/mask_monitor_tb.sv"

    if ! command -v -- "$vcs_bin" >/dev/null 2>&1; then
        printf '错误：找不到 VCS 可执行文件：%s\n' "$vcs_bin" >&2
        exit 2
    fi
    if [[ ! -f "$collection_package" || ! -f "$utility_package" ||
          ! -f "$clock_interface" || ! -f "$shmins_interface" ||
          ! -f "$sequence_item_package" || ! -f "$monitor_tb" ]]; then
        printf '错误：缺少 SHMINS mask-monitor 测试输入\n' >&2
        exit 2
    fi

    mkdir -p -- "$mask_monitor_dir/build"
    printf 'Ubuntu VCS：编译并运行 SHMINS thread-mask monitor 组件测试\n'
    (
        cd -- "$mask_monitor_dir/build"
        "$vcs_bin" -full64 -sverilog -ntb_opts "$uvm_version" -timescale=1ns/1ps \
            "+incdir+$collection_dir" "+incdir+$repo_root/ut_shm/util" \
            "+incdir+$sequence_dir" "+incdir+$shmins_agent_dir" \
            "+incdir+$memory_agent_dir" "+incdir+$environment_dir" \
            "+incdir+$common_example_dir" \
            "$collection_package" "$utility_package" "$clock_interface" \
            "$shmins_interface" "$sequence_item_package" "$monitor_tb" "$@" \
            -top shmins_mask_monitor_tb -o "$simv" -l compile.log
        "$simv" -l test.log
        check_uvm_test_log test.log \
            '[SHMINS_MASK_MONITOR_TEST] thread-mask monitor component matrix: PASS'
    )
}

run_dontcare_x_test() {
    local simv="$build_dir/dontcare_x_simv"
    local dontcare_tb="$example_dir/dontcare_x_tb.sv"

    if ! command -v -- "$vcs_bin" >/dev/null 2>&1; then
        printf '错误：找不到 VCS 可执行文件：%s\n' "$vcs_bin" >&2
        exit 2
    fi
    if [[ ! -f "$utility_package" || ! -f "$dontcare_tb" ]]; then
        printf '错误：缺少 SHMINS don’t-care X utility 测试输入\n' >&2
        exit 2
    fi

    mkdir -p -- "$build_dir"
    printf 'Ubuntu VCS：编译并运行 SHMINS don’t-care X utility 组件测试\n'
    (
        cd -- "$build_dir"
        "$vcs_bin" -full64 -sverilog -ntb_opts "$uvm_version" -timescale=1ns/1ps \
            "+incdir+$repo_root/ut_shm/util" "+incdir+$sequence_dir" \
            "$utility_package" "$dontcare_tb" "$@" \
            -top shmins_dontcare_x_tb -o "$simv" -l dontcare_x_compile.log
        "$simv" -l dontcare_x_test.log
        check_uvm_test_log dontcare_x_test.log \
            '[SHMINS_DONTCARE_X_TEST] don’t-care X utility component matrix: PASS'
    )
}

run_dontcare_driver_test() {
    local simv="$mask_monitor_dir/build/driver_monitor_simv"
    local driver_tb="$mask_monitor_dir/driver_monitor_tb.sv"

    if ! command -v -- "$vcs_bin" >/dev/null 2>&1; then
        printf '错误：找不到 VCS 可执行文件：%s\n' "$vcs_bin" >&2
        exit 2
    fi
    if [[ ! -f "$collection_package" || ! -f "$utility_package" ||
          ! -f "$clock_interface" || ! -f "$shmins_interface" ||
          ! -f "$sequence_item_package" || ! -f "$driver_tb" ]]; then
        printf '错误：缺少 SHMINS don’t-care driver/monitor 测试输入\n' >&2
        exit 2
    fi

    mkdir -p -- "$mask_monitor_dir/build"
    printf 'Ubuntu VCS：编译并运行 SHMINS don’t-care driver/monitor 组件测试\n'
    (
        cd -- "$mask_monitor_dir/build"
        "$vcs_bin" -full64 -sverilog -ntb_opts "$uvm_version" -timescale=1ns/1ps \
            "+incdir+$collection_dir" "+incdir+$repo_root/ut_shm/util" \
            "+incdir+$sequence_dir" "+incdir+$shmins_agent_dir" \
            "+incdir+$memory_agent_dir" "+incdir+$environment_dir" \
            "$collection_package" "$utility_package" "$clock_interface" \
            "$shmins_interface" "$sequence_item_package" "$driver_tb" "$@" \
            -top shmins_driver_monitor_tb -o "$simv" -l driver_monitor_compile.log
        "$simv" -l driver_monitor_test.log
        check_uvm_test_log driver_monitor_test.log \
            '[SHMINS_DRIVER_MONITOR_TEST] don’t-care driver/monitor component matrix: PASS'
    )
}

case "$target" in
    compile)
        compile_empty_design "$@"
        ;;
    copy)
        run_copy_test "$@"
        ;;
    lifecycle)
        run_lifecycle_test "$@"
        ;;
    dual-gid-address)
        run_dual_gid_address_test "$@"
        ;;
    mask-monitor)
        run_mask_monitor_test "$@"
        ;;
    dontcare-x)
        run_dontcare_x_test "$@"
        ;;
    dontcare-driver)
        run_dontcare_driver_test "$@"
        ;;
    all)
        compile_empty_design "$@"
        run_copy_test "$@"
        run_lifecycle_test "$@"
        run_dual_gid_address_test "$@"
        run_mask_monitor_test "$@"
        run_dontcare_x_test "$@"
        run_dontcare_driver_test "$@"
        ;;
    clean)
        rm -rf -- "$build_dir"
        rm -rf -- "$mask_monitor_dir/build"
        printf '已删除：%s\n' "$build_dir"
        ;;
esac
