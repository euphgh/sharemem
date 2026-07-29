# SystemVerilog/UVM Class 与 API 注释规范

## 1. 适用范围

本文规定本仓库 SystemVerilog/UVM class 的代码布局和注释要求。接口行为和验证
架构分别以对应的 spec 和架构文档为准。

## 2. API 形状阶段

当用户要求先定义代码形状时，只添加：

- class、enum、struct 和 typedef 定义；
- 成员变量；
- function/task API 声明；
- 必要的 UVM factory、virtual interface、子组件和 TLM 端口声明；
- 描述上述内容的注释。

在用户明确要求实现之前，不添加调度、检查、随机化、信号驱动或其他行为逻辑。
API 优先使用 `extern function` 和 `extern task` 声明。

## 3. Class 注释

每个 class 定义前必须有 Doxygen 风格的行注释块。至少说明：

- class 的主要职责；
- class 观察、接收或产生的信息；
- 它不负责的相邻职责。

```systemverilog
//------------------------------------------------------------------------------
// @brief Samples reservation and MEM requests into one cycle transaction.
//
// Checks four-state interface values and produces normalized two-state events.
// It does not drive reservation busy or check MEM data.
//------------------------------------------------------------------------------
class vlm_reservation_monitor extends uvm_component;
```

## 4. 成员变量注释

每个成员变量必须有紧邻声明的注释，说明该变量的用途。适用时还应说明：

- 所有权和读写者；
- 单位或周期含义；
- 数组各维的索引含义；
- reset 后的状态；
- 它属于配置、接口、子组件、调度状态还是统计信息。

```systemverilog
// Shared clock service obtained through UVM Config DB for cycle-number access.
virtual clk_if clk_vif;

// Read-only MEM interface used to observe request valid and address signals.
virtual vlm_memory_interface memory_vif;
```

不要使用只重复变量名的注释，例如 `// Cycle ID`。

## 5. Function 和 task API 注释

每个 function/task 声明前必须有紧邻声明的 Doxygen 风格行注释块。

必须使用：

- `@brief`：说明 API 职责和可观察效果；
- `@param`：说明每一个参数；
- `@return`：说明所有非 `void` function 的返回值和特殊取值。

根据 contract 需要，可以使用：

- `@pre`：调用前必须满足的条件；
- `@post`：调用后的状态保证。

constructor、task 和 `void` function 没有返回值，不添加虚假的 `@return`；
需要描述状态变化时使用 `@post`。

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

```systemverilog
//------------------------------------------------------------------------------
// @brief Runs the reservation sample, check, schedule, and busy-drive loop.
//
// @param phase UVM main phase controlling the reactive agent lifetime.
// @post The next busy state is prepared without modifying MEM read data.
//------------------------------------------------------------------------------
extern virtual task main_phase(uvm_phase phase);
```

## 6. Class 布局

class 内部按以下顺序组织，省略没有内容的分组：

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

API 声明放在 class 内。进入行为实现阶段后，再使用
`class_name::method_name` 在 class 外定义 method。

代码行允许使用最多 120 个字符。在不超过该限制且不降低可读性的情况下，应把短
函数调用、数组索引、循环头和布尔表达式保留在同一行，避免为了较短的传统行宽产生
过多换行。超过 120 个字符时，应优先在参数、逻辑运算符或结构层次边界换行。

## 7. Contract 与写作要求

- 注释描述行为 contract，不解释显而易见的语法。
- 使用 spec 和架构文档中的稳定术语，例如 `BANK`、`sub bank`、
  `external busy` 和 `SHM busy`。
- 明确方向、周期、索引、所有权和 reset 语义。
- 不使用“处理相关情况”等无法验证的模糊描述。
- 不确定的语义必须先与用户确认，不能在 API 中自行假设。
- 架构文档描述组件边界；详细 API contract 保留在源代码注释中。

## 8. 验证要求

修改 SystemVerilog 源文件后，至少运行覆盖改动文件的语法 lint 或编译检查。
优先使用仓库已有的 filelist 和脚本；如果完整检查被无关问题阻塞，应运行能够覆盖
改动文件的最小检查，并准确记录未验证范围。
