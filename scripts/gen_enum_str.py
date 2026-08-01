#!/usr/bin/env python3
"""
SystemVerilog Enum String Converter Generator

解析 SV 文件中的 typedef enum 定义，生成对应的字符串转换函数。

用法:
    python gen_enum_str.py input.sv [-o output.sv] [--pkg PKG_NAME]
    python gen_enum_str.py src/*.sv -o generated/enum_str_funcs.sv

支持的 enum 格式:
    typedef enum { A, B, C } my_enum_t;
    typedef enum bit [2:0] { A=0, B=1, C=2 } my_enum_t;
    typedef enum logic [7:0] { A = 8'h00, B = 8'h01 } my_enum_t;
"""

import argparse
import re
import sys
from pathlib import Path


class EnumMember:
    def __init__(self, name, value=None):
        self.name = name
        self.value = value

    def to_string(self):
        """生成字符串表示（默认去掉前缀）"""
        return self.name


class EnumDef:
    def __init__(
        self, name, base_name, base_type=None, members=None, invalid_member=None
    ):
        self.name = name  # 类型名，如 cmd_t
        self.base_name = base_name  # 去掉 _t 后缀，如 cmd
        self.base_type = base_type  # 如 bit [2:0]
        self.members = members or []  # list of EnumMember
        self.invalid_member = invalid_member  # 用于 from_str 的默认返回值

    def find_invalid_member(self):
        """查找可能的 INVALID 成员"""
        for m in self.members:
            name_upper = m.name.upper()
            if (
                "INVALID" in name_upper
                or "UNKNOWN" in name_upper
                or "NONE" in name_upper
            ):
                return m.name
        return None


def parse_enum(text):
    """解析 SV 文本中的所有 typedef enum 定义"""

    # 匹配 typedef enum [base_type] { members } name;
    # 支持多行，支持注释
    pattern = r"""
        typedef\s+enum\s*
        (?P<base_type>(?:bit|logic|reg|int|integer)\s*(?:\[[^\]]+\])?\s*)?
        \{\s*
        (?P<members>[^}]+)
        \}\s*
        (?P<name>\w+)\s*;
    """

    enums = []

    for match in re.finditer(pattern, text, re.VERBOSE | re.MULTILINE | re.DOTALL):
        base_type = match.group("base_type")
        if base_type:
            base_type = base_type.strip()

        name = match.group("name")
        members_text = match.group("members")

        # 移除注释
        members_text = re.sub(r"//[^\n]*", "", members_text)
        members_text = re.sub(r"/\*.*?\*/", "", members_text, flags=re.DOTALL)

        # 解析成员
        members = []
        for item in members_text.split(","):
            item = item.strip()
            if not item:
                continue

            # 匹配 NAME 或 NAME = VALUE
            m = re.match(r"(\w+)\s*(?:=\s*(.+))?", item)
            if m:
                member_name = m.group(1)
                member_value = m.group(2).strip() if m.group(2) else None
                members.append(EnumMember(name=member_name, value=member_value))

        if members:
            # 计算 base_name（去掉 _t 后缀）
            base_name = name[:-2] if name.endswith("_t") else name

            enum_def = EnumDef(
                name=name, base_name=base_name, base_type=base_type, members=members
            )
            enum_def.invalid_member = enum_def.find_invalid_member()
            enums.append(enum_def)

    return enums


def get_string_value(member_name, strip_prefix=False):
    """获取成员的字符串表示"""
    if not strip_prefix:
        return member_name
    # 去掉前缀：CMD_READ -> READ, MODE_SINGLE -> SINGLE
    parts = member_name.split("_", 1)
    return parts[1] if len(parts) > 1 else member_name


def generate_to_str(enum, strip_prefix=False):
    """生成 xxx_to_str 函数"""
    lines = [
        "    function automatic string %s_to_str(%s e);" % (enum.base_name, enum.name),
        "        case (e)",
    ]

    for m in enum.members:
        str_val = get_string_value(m.name, strip_prefix)
        lines.append('            %s: return "%s";' % (m.name, str_val))

    lines.extend(
        [
            '            default: return "UNKNOWN";',
            "        endcase",
            "    endfunction",
        ]
    )

    return "\n".join(lines)


def generate_from_str(enum, case_insensitive=True, strip_prefix=False):
    """生成 str_to_xxx 函数"""
    invalid = enum.invalid_member or enum.members[-1].name

    lines = [
        "    function automatic %s str_to_%s(string s);" % (enum.name, enum.base_name),
    ]

    if case_insensitive:
        lines.append("        string s_upper;")
        lines.append("        s_upper = str_toupper(s);")
        var = "s_upper"
    else:
        var = "s"

    # 生成 if-else 链
    first = True
    for m in enum.members:
        if m.name == invalid:
            continue

        keyword = "if" if first else "else if"
        first = False
        str_val = get_string_value(m.name, strip_prefix)
        lines.append(
            '        %s (%s == "%s") return %s;' % (keyword, var, str_val, m.name)
        )

    lines.extend(
        [
            "        else return %s;" % invalid,
            "    endfunction",
        ]
    )

    return "\n".join(lines)


def generate_value_plusargs(enum):
    """生成 value_xxx_plusargs 函数，语义与 $value$plusargs 相同"""
    return """    function automatic bit value_%s_plusargs(string name, ref %s var_ref);
        string s;
        if ($value$plusargs({name, "=%%s"}, s)) begin
            var_ref = str_to_%s(s);
            return 1;
        end
        return 0;
    endfunction""" % (enum.base_name, enum.name, enum.base_name)


def generate_package(
    enums,
    pkg_name,
    case_insensitive=True,
    include_utils=True,
    import_pkgs=None,
    strip_prefix=False,
):
    """生成完整的 package"""

    lines = [
        "//===================================================================",
        "// Auto-generated enum string conversion functions",
        "// Generated by gen_enum_str.py",
        "//===================================================================",
        "",
    ]

    lines.append("package %s;" % pkg_name)

    # 添加 import 语句
    if import_pkgs:
        lines.append("")
        for pkg in import_pkgs:
            lines.append("    import %s::*;" % pkg)

    lines.append("")

    # 字符串工具函数
    if include_utils and case_insensitive:
        lines.extend(
            [
                "    // String utility functions",
                "    function automatic string str_toupper(string s);",
                "        string result;",
                "        result = s;",
                "        for (int i = 0; i < result.len(); i++) begin",
                '            if (result[i] >= "a" && result[i] <= "z")',
                '                result[i] = result[i] - "a" + "A";',
                "        end",
                "        return result;",
                "    endfunction",
                "",
            ]
        )

    # 为每个 enum 生成函数
    for enum in enums:
        lines.extend(
            [
                "    //---------------------------------------------------------------",
                "    // %s" % enum.name,
                "    //---------------------------------------------------------------",
                "",
                generate_to_str(enum, strip_prefix),
                "",
                generate_from_str(enum, case_insensitive, strip_prefix),
                "",
                generate_value_plusargs(enum),
                "",
            ]
        )

    lines.append("endpackage")

    return "\n".join(lines)


def generate_functions_only(enums, case_insensitive=True, strip_prefix=False):
    """只生成函数，不包含 package 包装"""

    lines = [
        "//===================================================================",
        "// Auto-generated enum string conversion functions",
        "// Generated by gen_enum_str.py",
        "//===================================================================",
        "",
    ]

    for enum in enums:
        lines.extend(
            [
                "//---------------------------------------------------------------",
                "// %s" % enum.name,
                "//---------------------------------------------------------------",
                "",
                generate_to_str(enum, strip_prefix),
                "",
                generate_from_str(enum, case_insensitive, strip_prefix),
                "",
                generate_value_plusargs(enum),
                "",
            ]
        )

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Generate string conversion functions for SystemVerilog enums",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("input", nargs="+", help="Input SV file(s)")
    parser.add_argument("-o", "--output", help="Output file (default: stdout)")
    parser.add_argument(
        "--pkg", default="enum_str_pkg", help="Package name (default: enum_str_pkg)"
    )
    parser.add_argument(
        "--import",
        dest="imports",
        action="append",
        default=[],
        help="Package(s) to import (can be used multiple times)",
    )
    parser.add_argument(
        "--no-pkg",
        action="store_true",
        help="Generate functions only, without package wrapper",
    )
    parser.add_argument(
        "--case-sensitive",
        action="store_true",
        help="Generate case-sensitive from_str functions",
    )
    parser.add_argument(
        "--strip-prefix",
        action="store_true",
        help="Strip enum prefix from string values (CMD_READ -> READ)",
    )
    parser.add_argument(
        "--list", action="store_true", help="List found enums without generating code"
    )

    args = parser.parse_args()

    # 读取所有输入文件
    all_text = ""
    for input_path in args.input:
        path = Path(input_path)
        if not path.exists():
            print("Error: File not found: %s" % input_path, file=sys.stderr)
            sys.exit(1)
        all_text += path.read_text() + "\n"

    # 解析 enum
    enums = parse_enum(all_text)

    if not enums:
        print("No typedef enum definitions found.", file=sys.stderr)
        sys.exit(0)

    # 列出模式
    if args.list:
        print("Found %d enum(s):" % len(enums))
        for e in enums:
            invalid_str = (
                " [invalid: %s]" % e.invalid_member if e.invalid_member else ""
            )
            print("  %s: %d members%s" % (e.name, len(e.members), invalid_str))
            for m in e.members:
                val_str = " = %s" % m.value if m.value else ""
                print("    - %s%s" % (m.name, val_str))
        sys.exit(0)

    # 生成代码
    case_insensitive = not args.case_sensitive
    import_pkgs = args.imports if args.imports else None
    strip_prefix = args.strip_prefix

    if args.no_pkg:
        output = generate_functions_only(enums, case_insensitive, strip_prefix)
    else:
        output = generate_package(
            enums,
            args.pkg,
            case_insensitive,
            import_pkgs=import_pkgs,
            strip_prefix=strip_prefix,
        )

    # 输出
    if args.output:
        Path(args.output).write_text(output)
        print(
            "Generated %s with %d enum(s)" % (args.output, len(enums)), file=sys.stderr
        )
    else:
        print(output)


if __name__ == "__main__":
    main()
