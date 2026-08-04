#!/usr/bin/env python3
"""通过带本地内容缓存的 SFTP 增量同步目录。"""

from __future__ import annotations

import argparse
import errno
import filecmp
import getpass
import json
import os
import posixpath
import shutil
import stat
import sys
import tempfile
from pathlib import Path

import paramiko


CACHE_ROOT = Path("build/remote-cache")
CACHE_TARGET_FILE = ".target.json"
IGNORED_DIRECTORY_NAMES = frozenset((".git", ".svn"))


def is_not_found(exc: OSError) -> bool:
    """判断远程 SFTP 错误是否表示路径不存在。"""
    return getattr(exc, "errno", None) == errno.ENOENT


def validate_remote_path(remote_path: str) -> str:
    """检查并规范化远程目录，避免误删危险路径。"""
    normalized = posixpath.normpath(remote_path)

    if not normalized.startswith("/"):
        raise ValueError(f"远程路径必须是绝对路径：{remote_path!r}")

    if normalized in ("", ".", "..", "/"):
        raise ValueError(f"拒绝操作危险远程路径：{remote_path!r}")

    return normalized


def remove_remote_tree(
    sftp: paramiko.SFTPClient,
    remote_path: str,
) -> None:
    """递归删除远程文件、符号链接或目录。

    符号链接只删除链接自身，不跟随链接进入目标目录。
    远程路径不存在时直接返回。
    """
    try:
        root_attr = sftp.lstat(remote_path)
    except OSError as exc:
        if is_not_found(exc):
            return
        raise

    # 普通文件或符号链接：直接删除。
    if not stat.S_ISDIR(root_attr.st_mode):
        print(f"删除远程文件：{remote_path}")
        sftp.remove(remote_path)
        return

    # 目录：先递归删除内容。
    for entry in sftp.listdir_attr(remote_path):
        child_path = posixpath.join(
            remote_path,
            entry.filename,
        )

        # 使用 lstat，避免跟随远程符号链接。
        child_attr = sftp.lstat(child_path)

        if stat.S_ISDIR(child_attr.st_mode):
            remove_remote_tree(sftp, child_path)
        else:
            print(f"删除远程文件：{child_path}")
            sftp.remove(child_path)

    print(f"删除远程目录：{remote_path}")
    sftp.rmdir(remote_path)


def make_remote_dirs(
    sftp: paramiko.SFTPClient,
    remote_path: str,
) -> None:
    """实现远程 mkdir -p。"""
    normalized = posixpath.normpath(remote_path)

    if normalized == "/":
        return

    current = "/"

    for component in normalized.strip("/").split("/"):
        current = posixpath.join(current, component)

        try:
            attr = sftp.stat(current)
        except OSError as exc:
            if not is_not_found(exc):
                raise

            print(f"创建远程目录：{current}")
            sftp.mkdir(current)
            continue

        if not stat.S_ISDIR(attr.st_mode):
            raise RuntimeError(f"远程路径已存在但不是目录：{current}")


def upload_file(
    sftp: paramiko.SFTPClient,
    local_path: Path,
    remote_path: str,
) -> None:
    """上传单个文件。"""
    print(f"上传：{local_path} -> {remote_path}")

    sftp.put(
        str(local_path),
        remote_path,
        confirm=True,
    )


def cached_file_matches(
    local_path: Path,
    cache_path: Path,
) -> bool:
    """按文件内容判断本地源文件是否与上次成功上传的缓存相同。"""
    return cache_path.is_file() and filecmp.cmp(
        local_path,
        cache_path,
        shallow=False,
    )


def remove_cache_path(cache_path: Path) -> None:
    """删除缓存中的文件、符号链接或目录。"""
    if cache_path.is_symlink() or cache_path.is_file():
        cache_path.unlink()
    elif cache_path.is_dir():
        shutil.rmtree(cache_path)


def upload_file_and_update_cache(
    sftp: paramiko.SFTPClient,
    local_path: Path,
    remote_path: str,
    cache_path: Path,
) -> None:
    """上传文件，并仅在上传成功后原子更新对应的本地缓存。"""
    cache_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    file_descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{cache_path.name}.",
        suffix=".tmp",
        dir=cache_path.parent,
    )
    os.close(file_descriptor)
    temporary_path = Path(temporary_name)

    try:
        # 先生成稳定快照，确保远端内容与成功后写入的缓存完全一致。
        shutil.copy2(
            local_path,
            temporary_path,
        )
        print(f"上传：{local_path} -> {remote_path}")
        sftp.put(
            str(temporary_path),
            remote_path,
            confirm=True,
        )
        os.replace(
            temporary_path,
            cache_path,
        )
    finally:
        temporary_path.unlink(missing_ok=True)


def upload_tree(
    sftp: paramiko.SFTPClient,
    local_dir: Path,
    remote_dir: str,
    cache_root: Path | None = None,
) -> None:
    """像 ``cp -r`` 一样，将本地目录本身增量同步到远程目录。"""
    destination_dir = posixpath.join(
        remote_dir,
        local_dir.name,
    )
    cache_dir = None

    if cache_root is not None:
        cache_dir = cache_root / local_dir.name

    upload_tree_contents(
        sftp,
        local_dir,
        destination_dir,
        cache_dir,
    )


def upload_tree_contents(
    sftp: paramiko.SFTPClient,
    local_dir: Path,
    remote_dir: str,
    cache_dir: Path | None = None,
) -> None:
    """递归同步目录内容，并用缓存跳过与上次上传内容相同的文件。"""
    if cache_dir is not None and cache_dir.is_symlink():
        raise RuntimeError(f"拒绝使用符号链接缓存目录：{cache_dir}")

    if cache_dir is not None and cache_dir.exists() and not cache_dir.is_dir():
        remove_remote_tree(sftp, remote_dir)
        remove_cache_path(cache_dir)

    make_remote_dirs(sftp, remote_dir)

    if cache_dir is not None:
        cache_dir.mkdir(
            parents=True,
            exist_ok=True,
        )

    local_names: set[str] = set()

    for local_path in sorted(local_dir.iterdir()):
        if local_path.name in IGNORED_DIRECTORY_NAMES:
            continue

        local_names.add(local_path.name)
        remote_path = posixpath.join(
            remote_dir,
            local_path.name,
        )
        cache_path = None if cache_dir is None else cache_dir / local_path.name

        if local_path.is_symlink():
            raise RuntimeError(f"默认不上传本地符号链接：{local_path}")

        if cache_path is not None and cache_path.is_symlink():
            raise RuntimeError(f"拒绝使用符号链接缓存路径：{cache_path}")

        if local_path.is_dir():
            if cache_path is not None and cache_path.exists() and not cache_path.is_dir():
                remove_remote_tree(sftp, remote_path)
                remove_cache_path(cache_path)

            upload_tree_contents(
                sftp,
                local_path,
                remote_path,
                cache_path,
            )
        elif local_path.is_file():
            if cache_path is not None and cache_path.exists() and not cache_path.is_file():
                remove_remote_tree(sftp, remote_path)
                remove_cache_path(cache_path)

            if cache_path is not None and cached_file_matches(local_path, cache_path):
                print(f"跳过（缓存命中）：{local_path}")
            elif cache_path is not None:
                upload_file_and_update_cache(
                    sftp,
                    local_path,
                    remote_path,
                    cache_path,
                )
            else:
                upload_file(
                    sftp,
                    local_path,
                    remote_path,
                )
        else:
            raise RuntimeError(f"不支持的本地文件类型：{local_path}")

    if cache_dir is None:
        return

    # 缓存中存在而源目录已删除的条目，代表上次同步后被移除的内容。
    for cache_path in sorted(cache_dir.iterdir()):
        if cache_path.name in local_names:
            continue

        remote_path = posixpath.join(
            remote_dir,
            cache_path.name,
        )
        print(f"删除远端旧路径：{remote_path}")
        remove_remote_tree(
            sftp,
            remote_path,
        )
        remove_cache_path(cache_path)


def cache_target_matches(
    cache_root: Path,
    target: dict[str, object],
) -> bool:
    """判断现有缓存是否属于本次 SFTP 目标。"""
    target_file = cache_root / CACHE_TARGET_FILE

    try:
        cached_target = json.loads(target_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False

    return cached_target == target


def write_cache_target(
    cache_root: Path,
    target: dict[str, object],
) -> None:
    """原子记录缓存对应的 SFTP 目标。"""
    cache_root.mkdir(
        parents=True,
        exist_ok=True,
    )
    target_file = cache_root / CACHE_TARGET_FILE
    file_descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{CACHE_TARGET_FILE}.",
        suffix=".tmp",
        dir=cache_root,
        text=True,
    )

    try:
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as temporary_file:
            json.dump(
                target,
                temporary_file,
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
            temporary_file.write("\n")

        os.replace(
            temporary_name,
            target_file,
        )
    finally:
        Path(temporary_name).unlink(missing_ok=True)


def reset_cache(cache_root: Path) -> None:
    """清空可信度不足的旧缓存，为一次完整同步做准备。"""
    if cache_root.is_symlink():
        raise RuntimeError(f"拒绝清空符号链接缓存目录：{cache_root}")

    if cache_root.exists():
        shutil.rmtree(cache_root)

    cache_root.mkdir(
        parents=True,
        exist_ok=True,
    )


def read_password(password_file: str | None) -> str:
    """从密码文件、环境变量或终端读取密码。"""
    if password_file is not None:
        path = Path(password_file).expanduser()

        file_mode = stat.S_IMODE(path.stat().st_mode)
        if file_mode & 0o077:
            raise PermissionError(f"密码文件权限过宽：{path}，请执行 chmod 600")

        lines = path.read_text(encoding="utf-8").splitlines()
        if not lines:
            raise ValueError(f"密码文件为空：{path}")

        return lines[0]

    env_password = os.environ.get("SFTP_PASSWORD")
    if env_password is not None:
        return env_password

    return getpass.getpass("SFTP password: ")


def run(args: argparse.Namespace) -> None:
    """连接服务器，并使用本地缓存增量同步文件。"""
    # local_dir = Path(args.local_dir).expanduser().resolve()
    remote_dir = validate_remote_path(args.remote_dir)

    # if not local_dir.is_dir():
    #     raise ValueError(f"本地路径不是目录：{local_dir}")

    local_dirs = (
        Path("ut_shm"),
        Path("ver_common"),
    )

    for local_dir in local_dirs:
        if not local_dir.is_dir():
            raise ValueError(f"本地路径不是目录：{local_dir}")

    cache_root = CACHE_ROOT

    if cache_root.is_symlink():
        raise RuntimeError(f"拒绝使用符号链接缓存目录：{cache_root}")

    cache_target = {
        "host": args.host,
        "port": args.port,
        "remote_dir": remote_dir,
        "user": args.user,
    }
    incremental_sync = cache_target_matches(
        cache_root,
        cache_target,
    )

    password = read_password(args.password_file)

    client = paramiko.SSHClient()

    # 从 ~/.ssh/known_hosts 等文件加载服务器主机密钥。
    client.load_system_host_keys()

    # 未知主机密钥时拒绝连接，防止中间人攻击。
    client.set_missing_host_key_policy(paramiko.RejectPolicy())

    try:
        client.connect(
            hostname=args.host,
            port=args.port,
            username=args.user,
            password=password,
            look_for_keys=False,
            allow_agent=False,
            timeout=args.timeout,
            banner_timeout=args.timeout,
            auth_timeout=args.timeout,
        )

        sftp = client.open_sftp()

        try:
            if incremental_sync:
                print(f"使用缓存增量同步：{cache_root}")
            else:
                print(f"初始化缓存并完整同步：{cache_root}")
                print(f"清空远程目录：{remote_dir}")
                remove_remote_tree(sftp, remote_dir)
                reset_cache(cache_root)

            make_remote_dirs(sftp, remote_dir)

            for local_dir in local_dirs:
                upload_tree(
                    sftp,
                    local_dir,
                    remote_dir,
                    cache_root,
                )

            write_cache_target(
                cache_root,
                cache_target,
            )

            print("同步完成")
        finally:
            sftp.close()
    finally:
        client.close()


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(
        description=("使用密码登录 SFTP，通过 build/remote-cache 增量同步目录")
    )

    parser.add_argument(
        "--host",
        default="10.10.88.208",
        help="SFTP 服务器地址",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=22,
        help="SSH/SFTP 端口，默认 22",
    )
    parser.add_argument(
        "--user",
        default="sftpuser",
        help="登录用户名",
    )
    parser.add_argument(
        "--local-dir",
        help="需要上传的本地目录",
    )
    parser.add_argument(
        "--remote-dir",
        default="/sftpuser/guanghui.hu/remote",
        help="需要同步到的远程绝对路径",
    )
    parser.add_argument(
        "--password-file",
        default="scripts/sftp.password",
        help="密码文件；必须设置为 chmod 600",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=10.0,
        help="连接和认证超时时间，默认 10 秒",
    )

    return parser.parse_args()


def main() -> int:
    """程序入口。"""
    try:
        run(parse_args())
    except (
        paramiko.AuthenticationException,
        paramiko.SSHException,
        OSError,
        ValueError,
        RuntimeError,
    ) as exc:
        print(f"错误：{exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
