#!/usr/bin/env bash
#
# 在一次 VCS 进程中运行 split sequence item 的参数交叉测试或无 inline constraint 基准。

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  scripts/ubuntu/run_shmins_random_cross_benchmark.sh <matrix|unconstrained|all> [simv 参数...]

环境变量：
  BENCH_ITERATIONS  每个参数组合或 topology 的正式随机次数，默认 100
  BENCH_WARMUP      每个参数组合或 topology 的预热次数，默认 5

输出保存在 examples/shmins_random_benchmark/build/split/：
  cross_matrix.log / cross_matrix.csv
  unconstrained.log / unconstrained.csv
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
    matrix | unconstrained | all)
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
build_dir="$example_dir/build/split"
simv="$build_dir/simv"
iterations="${BENCH_ITERATIONS:-100}"
warmup="${BENCH_WARMUP:-5}"

if [[ ! "$iterations" =~ ^[1-9][0-9]*$ ]]; then
    printf '错误：BENCH_ITERATIONS 必须是正整数：%s\n' "$iterations" >&2
    exit 2
fi
if [[ ! "$warmup" =~ ^[0-9]+$ ]]; then
    printf '错误：BENCH_WARMUP 必须是非负整数：%s\n' "$warmup" >&2
    exit 2
fi

"$script_dir/run_shmins_random_benchmark.sh" compile

extract_results() {
    local result_id="$1"
    local keys="$2"
    local log_file="$3"
    local csv_file="$4"

    awk -v result_id="$result_id" -v keys="$keys" '
        BEGIN {
            key_count = split(keys, key, ",")
            print keys
        }
        index($0, "[" result_id "]") && index($0, key[1] "=") {
            for (saved_key in value) {
                delete value[saved_key]
            }
            for (field_idx = 1; field_idx <= NF; field_idx++) {
                equals_idx = index($field_idx, "=")
                if (equals_idx > 1) {
                    field_key = substr($field_idx, 1, equals_idx - 1)
                    value[field_key] = substr($field_idx, equals_idx + 1)
                }
            }
            for (key_idx = 1; key_idx <= key_count; key_idx++) {
                printf "%s%s", value[key[key_idx]], (key_idx == key_count) ? ORS : OFS
            }
        }
    ' OFS=, "$log_file" >"$csv_file"
}

check_uvm_result() {
    local log_file="$1"

    if grep -Eq 'UVM_(ERROR|FATAL) :[[:space:]]+[1-9][0-9]*' "$log_file"; then
        printf '错误：测试报告 UVM_ERROR/UVM_FATAL：%s\n' "$log_file" >&2
        return 1
    fi
}

run_matrix() {
    local log_file="$build_dir/cross_matrix.log"
    local csv_file="$build_dir/cross_matrix.csv"
    local keys="topology,space,rw,dtype,atype_w,atype_s,atype_g,iterations,successes,failures,retries,"
    keys+="validation_errors,elapsed_ms,ms_per_attempt,checksum"
    local result_count

    printf '运行 432 组合 split sequence item 交叉测试\n'
    (
        cd -- "$build_dir"
        /usr/bin/time -p "$simv" \
            +UVM_TESTNAME=shmins_random_cross_benchmark_test \
            "+BENCH_ITERATIONS=$iterations" \
            "+BENCH_WARMUP=$warmup" \
            +UVM_NO_RELNOTES \
            "$@"
    ) 2>&1 | tee "$log_file"
    check_uvm_result "$log_file"
    extract_results SHMINS_CROSS_RESULT "$keys" "$log_file" "$csv_file"
    result_count="$(awk 'END { print NR - 1 }' "$csv_file")"
    if [[ "$result_count" != 432 ]]; then
        printf '错误：期望 432 条交叉结果，实际得到 %s 条\n' "$result_count" >&2
        return 1
    fi
    printf '交叉测试 CSV：%s\n' "$csv_file"
    awk -F, '
        NR > 1 {
            count[$1]++
            time_sum[$1] += $14
            retry_sum[$1] += $11
            attempts_sum[$1] += $8
            if ($14 > time_max[$1]) {
                time_max[$1] = $14
                slowest[$1] = $2 "/" $3 "/" $4 "/" $5 "/" $6 "/" $7
            }
        }
        END {
            for (topology in count) {
                printf "SHMINS_CROSS_TOPOLOGY_SUMMARY topology=%s combinations=%d " \
                       "avg_ms_per_attempt=%.6f max_ms_per_attempt=%.6f " \
                       "avg_retries_per_attempt=%.3f slowest=%s\n", \
                       topology, count[topology], time_sum[topology] / count[topology], \
                       time_max[topology], retry_sum[topology] / attempts_sum[topology], slowest[topology]
            }
        }
    ' "$csv_file"
}

run_unconstrained() {
    local log_file="$build_dir/unconstrained.log"
    local csv_file="$build_dir/unconstrained.csv"
    local keys="topology,inline_constraints,iterations,successes,failures,retries,validation_errors,"
    keys+="elapsed_ms,ms_per_attempt,checksum"
    local result_count

    printf '运行三个 topology 的无 inline constraint 基准\n'
    (
        cd -- "$build_dir"
        /usr/bin/time -p "$simv" \
            +UVM_TESTNAME=shmins_random_unconstrained_benchmark_test \
            "+BENCH_ITERATIONS=$iterations" \
            "+BENCH_WARMUP=$warmup" \
            +UVM_NO_RELNOTES \
            "$@"
    ) 2>&1 | tee "$log_file"
    check_uvm_result "$log_file"
    extract_results SHMINS_UNCONSTRAINED_RESULT "$keys" "$log_file" "$csv_file"
    result_count="$(awk 'END { print NR - 1 }' "$csv_file")"
    if [[ "$result_count" != 3 ]]; then
        printf '错误：期望 3 条无 inline constraint 结果，实际得到 %s 条\n' "$result_count" >&2
        return 1
    fi
    printf '无 inline constraint CSV：%s\n' "$csv_file"
}

case "$target" in
    matrix)
        run_matrix "$@"
        ;;
    unconstrained)
        run_unconstrained "$@"
        ;;
    all)
        run_matrix "$@"
        run_unconstrained "$@"
        ;;
esac
