# SystemVerilog/UVM 开发规范

本文规定 ShareMemory 仓库自有 SystemVerilog/UVM 代码的文件组织、class 布局、
API contract 和修改后检查要求。与 DUT 行为有关的规则以
[ut_shm DUT 规范](../ut_shm/spec/index.md)为准，组件边界以
[验证环境文档](../ut_shm/environment/index.md)为准。

## 1. 适用范围和渐进式采用

本规范适用于仓库自有的新增代码，以及一次变更中实际修改的 class、API 或局部
代码块。现有 legacy 文件可以保留原有缩进和布局；修复局部功能时，不应附带
大范围无关格式化。后续专门 refactor 可以逐文件收敛到本规范。

`ut_shm/util/sv-collection/`、`resources/` 和其他外部导入的第三方源码不在本规范
范围内。不得仅为满足本规范而修改第三方文件。

## 2. 文件、package 和 include

- 独立编译的 package、interface 和 module 使用 `.sv`。
- 由 package 或 module include 的 class、helper 和宏定义使用 `.svh`。
- package 名称必须与定义它的 `.sv` 文件名一致。
- 仓库自有 `.svh` 使用 `INC_<FILE_NAME>_SVH` include guard。文件名转换为大写，
  非字母数字字符转换为下划线。
- include guard 放在可选的文件说明之后、任何声明之前，结尾注释写回宏名。
- class `.svh` 由一个明确的所属 package include，不再作为独立 compilation unit
  加入 filelist。
- interface 在依赖它的 class package 之前单独编译。package 间依赖通过明确的
  编译顺序和 `import` 表达。

自动生成的 `.svh` 也必须保持正确的 guard、package 归属和语法。需要调整生成内容
时，应修改生成器或模板，不在下次生成会覆盖的输出上手工维护。

## 3. 命名和格式

- class、typedef、interface、package 和公共配置字段使用完整、稳定的名称。
- 作用域清晰且含义稳定的局部变量和 API 参数可使用 `txn`、`req`、`rsv`、
  `rec` 和 `cfg` 等常见缩写。不得为不常见概念创造需要猜测的缩写。
- 新增代码遵循所属文件的现有缩进，并保持文件内部一致。现阶段不强制全仓库
  统一为两空格或四空格。
- 代码行以 120 字符为上限目标。超出时优先在参数、逻辑运算符或结构层次
  边界换行，不为较短的传统行宽制造过度碎片化。

## 4. Class 注释

新增 class 和本次进行实质修改的 class 必须在定义前使用 Doxygen 风格行注释，
至少说明：

- class 的主要职责；
- 观察、接收或产生的信息；
- 不负责的相邻职责。

```systemverilog
//------------------------------------------------------------------------------
// @brief Samples reservation and MEM requests into one cycle transaction.
//
// Checks four-state interface values and produces normalized two-state events.
// It does not drive reservation busy or check MEM data.
//------------------------------------------------------------------------------
class vlm_reservation_monitor extends uvm_component;
```

## 5. 成员变量注释

新增成员或本次改变语义的成员必须有紧邻声明的注释。注释应说明用途，并在
适用时说明：

- 所有权和读写者；
- 单位或周期含义；
- 数组各维的索引含义；
- reset 后的状态；
- 它属于配置、interface、子组件、调度状态还是统计信息。

不要使用只重复变量名的注释，例如 `// Cycle ID`。

## 6. Function 和 task contract

新增 API 和本次改变 contract 的 function/task 必须在声明前使用紧邻的
Doxygen 风格行注释：

- `@brief`：职责和可观察效果；
- `@param`：每一个参数的含义和必要范围；
- `@return`：非 `void` function 的返回值和特殊取值；
- `@pre`：适用时说明调用前条件；
- `@post`：适用时说明调用后的状态保证。

Constructor、task 和 `void` function 不添加虚假的 `@return`。简短局部 helper 可在
class 内定义；UVM phase、公共 API 和非平凡方法优先在 class 内使用
`extern function/task` 声明，并在 class 外定义。

```systemverilog
//------------------------------------------------------------------------------
// @brief Returns whether a scheduler slot is occupied by an external source.
//
// @param direction Reservation direction selecting the read or write table.
// @param delay     Relative cycle index in the current busy window.
// @param sub_bank  Sub-bank index in the range 0 through 3.
// @return 1 when the selected slot is externally occupied; otherwise 0.
//------------------------------------------------------------------------------
extern function bit is_external_busy(
    vlm_direction_e direction,
    int unsigned    delay,
    int unsigned    sub_bank);
```

## 7. Class 布局

Class 内部按下列顺序组织，没有内容的分组直接省略：

1. local typedef、enum 和 struct；
2. 配置与 virtual interface；
3. 子组件与 TLM 端口；
4. 调度或检查状态；
5. 统计信息；
6. constraints；
7. constructor 和 UVM phase API；
8. public API；
9. protected/local helper API；
10. UVM factory 注册。

布局是新增 class 的目标。修改 legacy class 的一个局部 API 时，不要为了排序而移动
整个 class。

## 8. UVM 和公开 API

- 需要 factory override 或自动字段操作的 object/component 使用与类型相匹配的
  UVM factory 宏。
- 可能影响 regression 分类和自动化的 UVM report ID 必须稳定。新增诊断优先使用
  `uvm_info/warning/error/fatal` 宏，而不是无上下文的 `$display`。
- `do_copy()`、`do_compare()` 或自定义 copy/compare API 必须覆盖所有影响行为的字段，
  并且返回值必须反映真实结果。
- 不保留只打印 debug、恒定成功、默默不做任何事情或无条件报
  `please implement` 的伪 API。无调用者时删除；有明确 contract 时实现；暂时不能处理时
  登记到 [验证实现状态](../ut_shm/verification-status.md)。
- 不支持的运行模式应在 config/build 阶段明确拒绝，不得构造看似成功但只连接
  了一部分组件的层次。

## 9. Contract 写作

- 注释描述可验证的行为 contract，不解释显而易见的语法。
- 使用 spec 和组件文档中的稳定术语，例如 `BANK`、`sub bank`、`external busy`
  和 `SHM busy`。
- 需要时明确方向、周期、索引、所有权和 reset 语义。
- 不使用“处理相关情况”等无法验证的模糊描述。
- 不确定的 DUT 语义必须先确认，不得从当前验证代码反向推导为稳定 spec。
- 架构和组件文档描述组件边界；详细 API contract 保留在源码注释中。

## 10. 修改后检查

修改 SystemVerilog 源文件后，至少执行能覆盖改动文件的语法 lint 或编译检查。
优先使用仓库已有 filelist 和脚本；完整检查被无关问题阻塞时，运行可覆盖本次
改动的最小检查，并准确记录未验证范围。

具体执行环境和命令见 [ut_shm 使用指南](../ut_shm/guide/index.md)。生成产物必须写入
`build/`、example 自有 build 目录或其他已忽略目录，不得写入源码和文档目录。
