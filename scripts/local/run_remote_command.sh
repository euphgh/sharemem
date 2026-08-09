#!/usr/bin/env bash
#
# 在远端 ShareMemory 仓库目录中执行命令。
#
# 示例：
#   scripts/local/run_remote_command.sh pwd
#   scripts/local/run_remote_command.sh scripts/ubuntu/check_vlm_reservation_vcs.sh compile
#   scripts/local/run_remote_command.sh bash -lc 'make compile 2>&1 | tee /tmp/compile.log'

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  scripts/local/run_remote_command.sh <命令> [参数...]

环境变量：
  SHAREMEM_REMOTE_HOST  SSH 主机或别名，默认 chatgpt
  SHAREMEM_REMOTE_DIR   远端 HOME 下的仓库路径，默认 sharemem
  SHAREMEM_SSH_OPTION   追加到 ssh 的 SSH 选项，以空白分隔，默认为空

命令及其参数会被安全地逐项转义，然后在远端仓库目录中执行。需要管道、重定向
或其他 shell 语法时，请显式使用：

  scripts/local/run_remote_command.sh bash -lc '命令 2>&1 | tee /tmp/output.log'
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

# Bound connection setup and prevent an authentication prompt from looking like a hung command.
ssh_args=(
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o ServerAliveInterval=10
    -o ServerAliveCountMax=3
)

# 将用户配置的 SSH 选项作为独立参数追加，避免整段字符串被 ssh 当作一个参数。
# 此变量用于命令行选项，不支持选项值中包含空白字符。
if [[ -n "${SHAREMEM_SSH_OPTION:-}" ]]; then
    read -r -a ssh_extra_args <<<"$SHAREMEM_SSH_OPTION"
    ssh_args+=("${ssh_extra_args[@]}")
fi

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

ssh "${ssh_args[@]}" -- "$remote_host" \
    "cd -- ${remote_dir_quoted} && exec${remote_command}"
