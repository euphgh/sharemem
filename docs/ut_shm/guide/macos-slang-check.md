# macOS Slang 检查

macOS 是主要代码和文档开发环境，只提供 Slang 与仓库内 UVM 源码。本页记录本地能够
重复执行的语法检查；VCS 兼容性、完整 elaboration 和真实 DUT 行为必须进入后续环境
验证。

## 1. VLM memory agent 检查

[`check_vlm_memory_slang.sh`](../../../scripts/local/check_vlm_memory_slang.sh) 为
`vlm_memory_agent` 生成临时 wrapper，覆盖 interface、transaction、config、monitor、
driver、sequencer 和 agent。临时文件放入系统临时目录，退出时删除。

**执行环境：macOS；工作目录：仓库根目录。**

```bash
scripts/local/check_vlm_memory_slang.sh
```

需要降低输出或传递其他 Slang 参数时，可直接追加：

```bash
scripts/local/check_vlm_memory_slang.sh --quiet
```

脚本默认使用 `slang` 和 `resources/uvm-1.2`，可以通过 `SLANG`、`UVM_HOME` 覆盖。

## 2. 检查范围

该脚本只证明选定的 VLM memory agent 文件能够在当前 Slang wrapper 中通过检查。它不
覆盖 shmins、reservation agent、完整 `shm_env_package`、tb top、Synopsys VIP 或
design filelist，也不会运行 UVM phase。

修改脚本覆盖范围之外的 SystemVerilog 后，应建立能包含改动文件的最小 Slang wrapper，
并把生成物放在 `build/` 或系统临时目录。随后仍要在 Ubuntu 使用 VCS 检查。

## 3. 结果记录

交付代码时至少记录：执行命令、Slang 版本、错误数和未覆盖范围。UVM 1.2 自身的 warning
可以单独说明，但不能隐藏来自仓库源码的 warning 或 error。
