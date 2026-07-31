#!/usr/bin/env python3
"""清空远程目录并通过 SFTP 上传本地目录。"""

from __future__ import annotations

import argparse
import errno
import getpass
import os
import posixpath
import stat
import sys
from pathlib import Path

import paramiko


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


def upload_tree(
    sftp: paramiko.SFTPClient,
    local_dir: Path,
    remote_dir: str,
) -> None:
    """像 ``cp -r`` 一样，将本地目录本身递归上传到远程目录。"""
    destination_dir = posixpath.join(
        remote_dir,
        local_dir.name,
    )
    upload_tree_contents(
        sftp,
        local_dir,
        destination_dir,
    )


def upload_tree_contents(
    sftp: paramiko.SFTPClient,
    local_dir: Path,
    remote_dir: str,
) -> None:
    """递归上传本地目录内容到已经确定的远程目录。"""
    make_remote_dirs(sftp, remote_dir)

    for local_path in sorted(local_dir.iterdir()):
        remote_path = posixpath.join(
            remote_dir,
            local_path.name,
        )

        if local_path.is_symlink():
            raise RuntimeError(f"默认不上传本地符号链接：{local_path}")

        if local_path.is_dir():
            upload_tree_contents(
                sftp,
                local_path,
                remote_path,
            )
        elif local_path.is_file():
            upload_file(
                sftp,
                local_path,
                remote_path,
            )
        else:
            raise RuntimeError(f"不支持的本地文件类型：{local_path}")


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
    """连接服务器、清空目录并上传文件。"""
    # local_dir = Path(args.local_dir).expanduser().resolve()
    remote_dir = validate_remote_path(args.remote_dir)

    # if not local_dir.is_dir():
    #     raise ValueError(f"本地路径不是目录：{local_dir}")

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
            print(f"清空远程目录：{remote_dir}")

            # 删除整个目录；不存在时不会报错。
            remove_remote_tree(sftp, remote_dir)

            # 重新创建目标目录。
            make_remote_dirs(sftp, remote_dir)

            # 像 cp -r 一样上传本地目录本身。
            upload_tree(sftp, Path("ut_shm"), remote_dir)
            upload_tree(sftp, Path("ver_common"), remote_dir)

            print("上传完成")
        finally:
            sftp.close()
    finally:
        client.close()


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(
        description=("使用密码登录 SFTP，清空远程目录，然后递归上传本地目录内容")
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
        help="需要清空并上传到的远程绝对路径",
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
