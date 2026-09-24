#!/usr/bin/env python3
"""扫描"写了没人调"的公开方法（284 拍板 3）。

为什么要有它：283 之前 `clearThumbnailCache()` 全仓零调用——一个看起来有功能、
单测也覆盖了的 API，UI 里从来没有入口，等于不存在。这类问题编译器不管、测试也不会
失败（不会红的测试不会提醒任何人），只有把调用点扫一遍才发现。

判定规则：
  1. 在某个 .dart 文件里**定义**了公开方法（缩进 2 空格、方法名不以 `_` 开头）；
  2. 在**该文件之外**（默认扫 lib/ 与 test/ 全仓）没有任何 `名字(` 形式的调用；
  3. 两条都成立 → 报为"悬挂 API"。

已知的边界（不假装它能判所有情况）：
  - 私有方法（`_foo`）不参与：它们本来就只在本文件用；
  - 基类/接口方法的 override（例如测试里的假服务实现真服务的方法）**不算调用点**，
    所以"只被 override、从不被直接调用"的方法会被报出来。遇到这种：
      a) 如果它真的没接上 → 接上（这正是本脚本要抓的）；
      b) 如果它是给外部用的（平台侧、其他包、反射式调用）→ 加进 ALLOW 并写原因；
  - 只做"名字 + 左括号"的文本匹配，不做语义分析（宁可漏报也不误报）。

用法：
  python3 tool/scan_dangling_apis.py                    # 扫默认范围（见下方 SCOPE）
  python3 tool/scan_dangling_apis.py --warn-only        # 只打印，不改退出码
  python3 tool/scan_dangling_apis.py --dir lib/foo      # 只扫某个目录
退出码：发现悬挂 API 为 1（CI 会红），否则 0。
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# 扫描范围：只扫"插件/功能自成一体的目录"最有效——全仓扫会把框架回调、
# 路由注册这类"由外部按名字调用"的方法全部报出来，噪音大到没人看。
SCOPE = ["lib/features/extensions/plugins/remote_storage"]

# 搜索调用点的范围（定义文件本身除外都算）。
SEARCH = ["lib", "test"]

# 白名单：确认为"给外部调用"的方法，格式 (方法名, 原因)。
ALLOW: list[tuple[str, str]] = []

# 方法声明：缩进 2 空格，返回类型 + 名字 + 左括号；名字不以 _ 开头。
DECL = re.compile(
    r"^  (?:@\w+\s+)*"
    r"(?:static\s+|const\s+)?"
    r"(?:Future<[^>]*>|Future|void|bool|int|double|num|String|"
    r"Stream<[^>]*>|List<[^>]*>|Map<[^>]*>|Set<[^>]*>|Iterable<[^>]*>|"
    r"[A-Z]\w*(?:<[^>]*>)?\??)\s+"
    r"([a-z]\w*)\s*\("
)


def collect_declarations(directories: list[Path]) -> dict[str, list[str]]:
    """方法名 → 定义位置（`相对路径:行号`）。"""
    found: dict[str, list[str]] = {}
    for directory in directories:
        if not directory.exists():
            continue
        for path in sorted(directory.rglob("*.dart")):
            rel = path.relative_to(REPO)
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("//"):
                    continue
                match = DECL.match(line)
                if match:
                    found.setdefault(match.group(1), []).append(f"{rel}:{number}")
    return found


def reference_counts(
    names: set[str],
    declarations: dict[str, list[str]],
    search_roots: list[str],
) -> dict[str, int]:
    """每个名字在（全仓搜索范围内）`名字(` 形式的**调用**次数。

    必须把定义行本身排除掉：定义行也长成 `名字(`，算进去的话任何方法都至少
    有 1 次"调用"，闸门永远不会红——一个静默失效的闸门比没有闸门更糟。
    """
    counts = {name: 0 for name in names}
    pattern = re.compile(r"\b(" + "|".join(re.escape(n) for n in sorted(names)) + r")\s*\(")
    for root_name in search_roots:
        root = REPO / root_name
        if not root.exists():
            continue
        for path in root.rglob("*.dart"):
            rel = str(path.relative_to(REPO))
            text = path.read_text(encoding="utf-8", errors="replace")
            for match in pattern.finditer(text):
                name = match.group(1)
                line = text.count("\n", 0, match.start()) + 1
                if f"{rel}:{line}" in declarations.get(name, []):
                    continue  # 这是定义行，不是调用
                counts[name] += 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description="扫描写了没人调的公开方法")
    parser.add_argument("--dir", action="append", default=None, help="只扫该目录（可多次）")
    parser.add_argument("--warn-only", action="store_true", help="只打印，不改退出码")
    args = parser.parse_args()

    directories = [REPO / d for d in (args.dir or SCOPE)]
    declarations = collect_declarations(directories)

    # 调用点既在全仓的 lib/test 里找，也在被扫描的目录里找——否则用 --dir 指向
    # 仓库外的目录时"明明有调用"也判成悬挂（自检时踩过）。
    search_roots: list[str] = []
    for root in [*SEARCH, *(str(d.relative_to(REPO)) for d in directories)]:
        if root not in search_roots:
            search_roots.append(root)

    allowed = {name for name, _ in ALLOW}
    candidates = {
        name: locs for name, locs in declarations.items() if name not in allowed
    }
    counts = reference_counts(set(candidates), declarations, search_roots)

    dangling: list[tuple[str, list[str]]] = []
    for name, locations in candidates.items():
        # 出现在定义行上的那一次不算调用；定义文件之外零调用才叫悬挂。
        if counts[name] > 0:
            continue
        dangling.append((name, locations))

    print(f"扫描目录: {', '.join(str(d.relative_to(REPO)) for d in directories)}")
    print(f"公开方法: {len(declarations)} 个（白名单 {len(allowed)} 个不计）")
    if not dangling:
        print("悬挂 API: 0 个 ✅（每个公开方法至少有一个调用点）")
        return 0

    print(f"悬挂 API: {len(dangling)} 个 ❌\n")
    for name, locations in sorted(dangling):
        print(f"  {name}")
        for location in locations:
            print(f"    定义于 {location}")
    print(
        "\n处理方式：① 真的没接上就接上（这正是本闸门要抓的）；"
        "② 确认给外部调用就在 tool/scan_dangling_apis.py 的 ALLOW 里登记并写原因。"
    )
    return 0 if args.warn_only else 1


if __name__ == "__main__":
    sys.exit(main())
