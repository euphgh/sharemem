# ut_shm 工作区流转

本页说明如何从 macOS 主工作区把改动送到 Ubuntu 或 CentOS。两条路径互相独立：
Ubuntu 接收近似完整的 Git 工作区，CentOS 只接收 `ut_shm/` 和 `ver_common/`，且没有从
CentOS 下载文件的反向通道。

## 1. 流转关系

```text
macOS -- rsync/SSH --> Ubuntu chatgpt
macOS -- SFTP -----> CentOS
CentOS -- 无下载通道 --> macOS
```

Ubuntu 不能作为 CentOS 上传源。需要送入 CentOS 的修改必须先回到 macOS 主工作区，
再运行本地上传脚本。

## 2. 同步到 Ubuntu

[`sync_remote_repo.sh`](../../../scripts/local/sync_remote_repo.sh) 从 macOS 启动，默认把
当前工作区同步到 SSH 别名 `chatgpt` 的 `~/sharemem`。它保留远端 `.git`，跳过
`resources/`、构建产物、日志和密码文件；默认还会删除 Ubuntu 上本地已不存在的源码。

**执行环境：macOS；工作目录：仓库根目录。**

先预览差异：

```bash
scripts/local/sync_remote_repo.sh --dry-run
```

确认后同步：

```bash
scripts/local/sync_remote_repo.sh
```

如果需要暂时保留 Ubuntu 独有文件：

```bash
scripts/local/sync_remote_repo.sh --no-delete
```

默认模式使用 batch SSH、连接超时和 keepalive，认证失败或连接停滞时会退出，而不是
等待交互式密码输入。目标目录必须已经是 Git clone。

## 3. 从 macOS 触发 Ubuntu 命令

[`run_remote_command.sh`](../../../scripts/local/run_remote_command.sh) 在 macOS 组装并
转义参数，再进入 Ubuntu 仓库根目录执行命令。

**启动环境：macOS；实际执行环境：Ubuntu `chatgpt`；工作目录：Ubuntu 仓库根目录。**

```bash
scripts/local/run_remote_command.sh pwd
```

需要管道或重定向时，Shell 语法必须显式放进远端 `bash -lc`：

```bash
scripts/local/run_remote_command.sh bash -lc 'make compile 2>&1 | tee /tmp/ut_shm_compile.log'
```

脚本只执行命令，不会自动同步工作区。运行 VCS 前应先执行上一节的同步步骤。

## 4. 上传到 CentOS

[`upload_centos.py`](../../../scripts/local/upload_centos.py) 从 macOS 通过 SFTP 上传
`ut_shm/` 和 `ver_common/`。CentOS 自有 design、Makefile 和 `rpu_sim` 不由本脚本
覆盖。

脚本使用 Python 3 和 `paramiko`。执行前需要在 macOS 的 Python 环境中安装
`paramiko`；依赖缺失时脚本会在建立 SFTP 连接前退出。

**执行环境：macOS；工作目录：仓库根目录。**

```bash
scripts/local/upload_centos.py
```

脚本使用 `build/remote-cache/` 保存上次成功上传的内容快照。源文件与缓存内容完全相同
时跳过 SFTP；源文件被修改、删除或由文件变成目录时，会同步更新 CentOS 和缓存。

缓存通过 `.target.json` 绑定 host、port、user 和远端目录。目标变化或缓存无效时，脚本
会清空指定的远端目录并做一次完整同步，因此修改连接参数前必须先核对远端绝对路径。
缓存只代表“上次成功上传的内容”，不会读取 CentOS 文件来确认服务器是否被其他流程
改动。

密码默认从 `scripts/sftp.password` 读取，也可以用 `--password-file` 指向其他权限为
`0600` 的文件；具体参数见[配置参考](configuration-reference.md)。

## 5. CentOS 反馈边界

当前无法从 CentOS 下载日志、波形或生成文件。用户完成最终验证后，需要把 commit 或
上传批次、case/seed、首个错误及其上下文、最终 pass/fail 摘要反馈到开发工作区。
仓库文档不复制 CentOS 自有运行命令。
