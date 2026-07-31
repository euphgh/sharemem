#!/usr/bin/env bash
#
# 在远端 ShareMemory 仓库目录中执行命令。
#
# 示例：
#   scripts/run_remote_command.sh pwd
#   scripts/run_remote_command.sh make -C examples/vlm_reservation_compile compile
#   scripts/run_remote_command.sh bash -lc 'make compile 2>&1 | tee /tmp/compile.log'

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  scripts/run_remote_command.sh <命令> [参数...]

环境变量：
  SHAREMEM_REMOTE_HOST  SSH 主机或别名，默认 chatgpt
  SHAREMEM_REMOTE_DIR   远端 HOME 下的仓库路径，默认 sharemem

命令及其参数会被安全地逐项转义，然后在远端仓库目录中执行。需要管道、重定向
或其他 shell 语法时，请显式使用：

  scripts/run_remote_command.sh bash -lc '命令 2>&1 | tee /tmp/output.log'
EOF
}

if (($# == 0)); then
    usage >&2
    exit 2
fi

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac

remote_host="${SHAREMEM_REMOTE_HOST:-chatgpt}"
remote_dir="${SHAREMEM_REMOTE_DIR:-sharemem}"
remote_dir="${remote_dir%/}"

if [[ -z "$remote_host" ]]; then
    printf '错误：SHAREMEM_REMOTE_HOST 不能为空\n' >&2
    exit 2
fi

case "$remote_dir" in
    "" | "." | ".." | "/" | "~")
        printf '错误：拒绝使用危险的远端目录：%q\n' "$remote_dir" >&2
        exit 2
        ;;
esac

printf -v remote_dir_quoted '%q' "$remote_dir"

remote_command=
for argument in "$@"; do
    printf -v argument_quoted '%q' "$argument"
    remote_command+=" ${argument_quoted}"
done

printf '远端执行：%s:%s$' "$remote_host" "$remote_dir"
printf ' %q' "$@"
printf '\n'

ssh -- "$remote_host" \
    "cd -- ${remote_dir_quoted} && exec${remote_command}"
