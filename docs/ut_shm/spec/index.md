# ut_shm DUT 规范

本目录描述验证人员需要遵守的 RpuShmTop 行为，包括地址模型和接口契约。这里不写
UVM 组件的内部实现；需要了解 monitor、driver 或 checker 时，从
[验证环境索引](../environment/index.md)继续阅读。

## 文档状态

|文档|内容|状态|
|---|---|---|
|[dut-overview.md](dut-overview.md)|DUT 职责、双 gid BANK 拓扑、参数和接口分组|双 gid contract 已发布|
|[address-model.md](address-model.md)|MADDR、逻辑 bank/warp/laddr、物理 gid/BADDR 和两层映射|双 gid contract 已发布|
|[creq-ack-interface.md](creq-ack-interface.md)|creq、M2V vaddr/hazard、credit/release、vack 和 mack|双 gid contract 已发布|
|[mem-vlm-interface.md](mem-vlm-interface.md)|MEM、带 gid reservation/busy、端口冲突和 gid恢复|双 gid contract 已发布|

## 阅读顺序

先读 [DUT 概览](dut-overview.md)，再用[地址模型](address-model.md)建立地址概念。
输入请求相关工作继续读 [creq/ack 接口](creq-ack-interface.md)；MEM 数据端口或
reservation 工作读 [MEM/VLM 接口](mem-vlm-interface.md)。两份接口文档都引用地址
模型，不各自维护一套地址公式。
