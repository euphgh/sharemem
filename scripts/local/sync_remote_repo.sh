#!/usr/bin/env bash
#
# 将当前本地工作区同步到远端测试仓库。
#
# 默认目标：
#   SSH 主机：chatgpt
#   远端目录：~/sharemem（相对于远端 HOME 的 sharemem）
#
# 可通过 SHAREMEM_REMOTE_HOST 和 SHAREMEM_REMOTE_DIR 覆盖默认值。

set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  scripts/local/sync_remote_repo.sh [--dry-run] [--no-delete]

选项：
  --dry-run    只显示将要同步的改动，不实际修改远端文件
  --no-delete  不删除远端存在但本地已经不存在的文件
  -h, --help   显示帮助

环境变量：
  SHAREMEM_REMOTE_HOST  SSH 主机或别名，默认 chatgpt
  SHAREMEM_REMOTE_DIR   远端 HOME 下的仓库路径，默认 sharemem

同步会保留远端 .git，跳过本地 UVM resources、构建目录和密码文件。默认删除
远端多余的源码文件，使远端测试工作区与本地一致。
EOF
}

dry_run=0
delete_remote_files=1

while (($# > 0)); do
    case "$1" in
        --dry-run)
            dry_run=1
            ;;
        --no-delete)
            delete_remote_files=0
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf '错误：未知参数：%s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(git -C "$script_dir/.." rev-parse --show-toplevel)"

remote_host="${SHAREMEM_REMOTE_HOST:-chatgpt}"
remote_dir="${SHAREMEM_REMOTE_DIR:-sharemem}"
remote_dir="${remote_dir%/}"

# Bound both SSH connection setup and established-but-stalled transfers. Batch
# mode also prevents an authentication prompt from looking like a hung sync.
ssh_args=(
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o ServerAliveInterval=10
    -o ServerAliveCountMax=3
)
rsync_ssh_command='ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3'

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

# 只允许同步到一个已经存在的 Git clone，防止路径配置错误时写入其他目录。
if ! ssh "${ssh_args[@]}" -- "$remote_host" "test -d ${remote_dir_quoted}/.git"; then
    printf '错误：SSH 连接失败，或远端目录不是 Git clone：%s:%s\n' \
        "$remote_host" "$remote_dir" >&2
    exit 1
fi

rsync_args=(
    -az
    --itemize-changes
    --timeout=60
    --rsh="$rsync_ssh_command"
    --exclude=.git
    --exclude=.env
    --exclude=.venv/
    --exclude=resources/
    --exclude=__pycache__/
    --exclude='*.pyc'
    --exclude=.DS_Store
    --exclude=build/
    --exclude=csrc/
    --exclude=simv
    --exclude=simv.daidir/
    --exclude='*.log'
    --exclude=scripts/sftp.password
)

if ((delete_remote_files)); then
    rsync_args+=(--delete)
fi

if ((dry_run)); then
    rsync_args+=(--dry-run)
fi

printf '同步本地工作区：%s\n' "$repo_root"
printf '远端测试仓库：%s:%s\n' "$remote_host" "$remote_dir"

if ! rsync "${rsync_args[@]}" \
    "$repo_root/" \
    "${remote_host}:${remote_dir}/"; then
    printf '错误：同步失败；请检查 SSH 网络连接后重新运行，远端可能只收到部分文件\n' >&2
    exit 1
fi

if ((dry_run)); then
    printf '预览完成，远端文件未修改\n'
else
    printf '远端测试仓库同步完成\n'
fi
