#!/usr/bin/env python3
"""把被抹掉的 htpasswd 那一行按**原哈希**补回（只补它，别的一律不动）。

2026-09-30 22:31 的事故就是这么修的：边缘机 `all` 文件被整体重写成了 `rw` 文件的内容，
而 `rw` 的定义是"不含 `ro-` 用户"——于是 `ro-probe-hpa888` / `ro-probe-175` 两行静默消失，
两个入口的只读凭据一律 401（还容易被误读成"密钥路径收口被放开"）。

为什么要用脚本而不是手改：
  * **别重签**（`revoke` + `issue`）—— 重签改的是那一格的口令，正在用它的设备当场失效；
    这里只要从事故前的 `.bak-*` 里把**原来那一行**按原样搬回来；
  * 手改容易顺手重写整份文件 —— 那正是这次事故的成因。

用法（在边缘机上跑）：
  restore_dropped_cred_row.py --user ro-probe-175
  restore_dropped_cred_row.py --user ro-probe-175 --from-bak /www/server/nginx/conf/box-ops175.htpasswd.bak-20260930-223117
  restore_dropped_cred_row.py --user ro-probe-175 --dry-run

护栏：备份与现文件**共有**的行里若有一行哈希变了（说明期间重签过凭据），就停下不动手 ——
那种情况要人判断。写完立刻回读断言：那一行回来了、其它行逐字节没动、`rw ⊆ all`。
不打印任何口令/哈希全文。
"""
from __future__ import annotations

import argparse
import os
import shutil
import stat
import sys
import time
from pathlib import Path

CONF_DIR = Path("/www/server/nginx/conf")
BAK_GLOB = "*.htpasswd.bak-*"


def read_rows(path: Path) -> list[str]:
    return [ln for ln in path.read_text().splitlines() if ln.strip()]


def as_map(rows: list[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for ln in rows:
        u, h = ln.split(":", 1)
        out[u] = h
    return out


def find_bak(user: str) -> Path | None:
    """最近的、含这一行的备份。"""
    cands = [p for p in CONF_DIR.glob(BAK_GLOB) if f"{user}:" in p.read_text()]
    return max(cands, key=lambda p: p.stat().st_mtime) if cands else None


def rw_of(target: Path) -> Path:
    return target.with_name(target.name.replace(".htpasswd", "-rw.htpasswd"))


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="按原哈希补回被抹掉的 htpasswd 行")
    ap.add_argument("--user", required=True, help="要补回的用户名，例如 ro-probe-175")
    ap.add_argument("--from-bak", help="从哪份备份取那一行（默认：最近的、含这一行的备份）")
    ap.add_argument("--dry-run", action="store_true", help="只看要做什么，不写文件")
    a = ap.parse_args(argv)

    bak = Path(a.from_bak) if a.from_bak else find_bak(a.user)
    if not bak or not bak.exists():
        print(f"✗ 找不到含 {a.user} 的备份（{CONF_DIR}/{BAK_GLOB}）—— 不动手")
        return 3
    target = CONF_DIR / bak.name.split(".bak-")[0]
    if not target.exists():
        print(f"✗ 目标文件不在：{target} —— 你大概不是在边缘机上跑")
        return 3

    cur, old = read_rows(target), read_rows(bak)
    cmap, omap = as_map(cur), as_map(old)
    print(f"目标文件：{target}")
    print(f"备份    ：{bak}")
    print(f"现在   ：{sorted(cmap)}")
    print(f"备份里 ：{sorted(omap)}")

    shared = [u for u in cmap if u in omap]
    unchanged = all(cmap[u] == omap[u] for u in shared)
    print(f"共有行逐字节未变：{unchanged}（{len(shared)} 行）")
    if not unchanged:
        print("✗ 有共有行被改过（期间可能重签过凭据）—— 不动手，交人判断")
        return 3
    if a.user in cmap:
        print(f"= {a.user} 本来就在，什么都不用做")
        return 0
    if a.user not in omap:
        print(f"✗ 备份里也没有 {a.user} 这一行 —— 不动手")
        return 3
    if a.dry_run:
        print(f"（dry-run）会把 `{a.user}:<备份里那一行的原哈希>` 补到最前面，其它行原样不动")
        return 0

    st = target.stat()
    bpath = f"{target}.bak-{time.strftime('%Y%m%d-%H%M%S')}-before-restore"
    shutil.copy2(target, bpath)
    tmp = target.with_name(target.name + ".tmp-restore")
    with open(tmp, "w") as f:
        f.write(f"{a.user}:{omap[a.user]}\n")
        f.write("".join(ln + "\n" for ln in cur))
    os.chmod(tmp, stat.S_IMODE(st.st_mode))
    os.chown(tmp, st.st_uid, st.st_gid)
    os.replace(tmp, target)

    after = as_map(read_rows(target))
    rw = rw_of(target)
    ok_row = after.get(a.user) == omap[a.user]
    ok_rest = all(after.get(u) == cmap[u] for u in cmap)
    ok_sub = set(as_map(read_rows(rw))) <= set(after) if rw.exists() else True
    print(f"备份：{bpath}")
    print(f"✓ 那一行按原哈希补回：{ok_row}")
    print(f"✓ 其它行逐字节未动：{ok_rest}")
    print(f"✓ rw ⊆ all：{ok_sub}")
    print(f"现在：{sorted(after)}")
    if not (ok_row and ok_rest and ok_sub):
        return 4
    print("下一步：跑 box_channel_cred.py check，再用 box-ops-gate-probe.py --check 看巡检是否转绿")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))