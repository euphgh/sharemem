# ut_shm 验证计划

本目录把 DUT spec 转换为可追踪的 testpoint，并说明当前 testcase、regression、checker
和 coverage 能否形成验证闭环。接口和地址规则由 [DUT 规范](../spec/index.md)定义；
plan 文档只描述验证目标与证据，不重新定义协议。

## 1. 验证对象之间的关系

```text
Spec ──> Testpoint ──> Case ──> Run
             │           │       └── seed 和一次执行结果
             │           └── UVM test + 最终生效的 plusargs
             ├── Checker
             └── Functional coverage
```

- Spec 是 testpoint 的唯一功能依据。当前 sequence、checker 或 case 的限制不能反向
  缩小 DUT 应验证的范围。
- Testpoint 描述一条可检查、可覆盖的 DUT 行为。一个 testpoint 可以由多个 case
  共同激励，一个 case 也可以同时覆盖多个 testpoint。
- Case 是一个 UVM test 和一组继承、覆盖后最终生效的 plusargs。当前 TC 中的派生名称
  是 case 配置层，不代表新的 UVM test class。
- Run 是 case 使用一个 seed 的一次执行。`RUN` 或固定 `SEED` 改变执行次数或随机输入，
  不产生新的 case。
- Checker 证明观察结果是否正确；functional coverage 证明目标场景是否真正发生。
  仅有 case 或 checker 不能证明 testpoint 已关闭。

## 2. 文档职责

|文档|内容|不包含|
|---|---|---|
|[Testpoints](testpoints.md)|spec、目标激励、观察点、checker、目标 coverage、case 映射和状态|TC/LST 语法、checker 内部算法|
|[Testcase 与 regression](testcases-and-regression.md)|case 定义、TC/LST 格式、当前配置矩阵、激励限制和 regression 组织|DUT 协议、运行命令|
|[Coverage 与关闭](coverage-and-closure.md)|功能、代码、断言 coverage 的职责，waiver 和关闭条件|逐 testpoint 的详细规则|
|[验证实现状态](../verification-status.md)|验证代码与目标方案之间的实现缺口|稳定 DUT 行为|
|[使用指南](../guide/index.md)|编译、单 case、seed 和 regression 的实际运行方法|验证目标和关闭判断|

Checker 的完整检查条件和错误 ID 由[组件文档](../environment/components/index.md)维护。
Testpoint 只引用其中能为目标行为提供证据的检查，不复制实现细节。

## 3. 当前基线

双 gid BANK 接口已经成为当前 spec 基线，验证环境的统一 interface/agent、reference、
scoreboard 和 topology-based sequence item 已完成主路径迁移。新增 testpoint 必须使用
`<bank_id,gid,BADDR>` 物理 key，并遵守
[双 gid 接口重构开发计划](../../development/shm-dual-bank-interface-refactor-plan.md)的
稳定 contract。

- 109-case普通矩阵最终运行 `shm_unit_test`，通过 plusargs 选择 V2M、M2V、VTRANS、
  instruction、space、DTYPE 和 ATYPE；双 gid 和 mask/VTRANS directed 组使用独立 UVM test。
- `ut_shm/regression/shm.lst` 当前选择 109 个 case：54 个普通 V2M、54 个普通 M2V
  和 1 个 VTRANS。当前 109 个 case 已在 `VEC_W=256` 的真实 design 上全部通过；其中
  新增的 24 个 `LDSTE_S + WRP/BLK` case 已完成系统验证。
- `p0_directed.lst` 的四个双 gid test 和 `shmins_mask_directed.lst` 的28个 mask/VTRANS
  cell 也已在最新真实 design 上全部通过；目标 functional coverage 结果尚未归档。
- 当前已接入 address、reservation 和 request mask/VTRANS 的第一批 functional
  covergroup；其余 testpoint coverage 和目标 bin/cross 闭环仍不完整，case 或 checker
  不能替代 coverage。
- 当前 sequence 已使用 topology-based 过程式地址生成，并完成地址空洞和 BLK
  group-relative MADDR 约束；`creq_tmsk` 和 wpid/gid 第一批边界已有定向 case，合法
  don’t-care X、其他随机字段和完整 coverage仍待补。
  完整限制见
  [Testcase 与 regression](testcases-and-regression.md#5-当前激励能力和限制)。

## 4. 阅读路径

- 修改 DUT 功能检查：先读 spec，再从 [Testpoints](testpoints.md) 找目标观察点和
  checker，最后进入对应组件文档。
- 新增 testcase：先确认它补充哪个 testpoint，再按
  [Testcase 与 regression](testcases-and-regression.md)增加 TC 和 LST。
- 实现 functional coverage：从 testpoint 的目标 bin/cross 出发，再按
  [Coverage 与关闭](coverage-and-closure.md)选择采样位置和关闭标准。
- 判断功能是否完成：检查 testpoint 的激励、checker、coverage、case 和 regression
  证据；任何一项缺失都不能标记为已闭环。
