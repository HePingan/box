#!/usr/bin/env python3
"""发一条公告，把卡在 183/184/185 的用户捞出来。

为什么需要这个脚本：183/184/185 三个包漏注入更新验签密钥，客户端在读服务端
清单之前就短路失败（"HMAC 更新验签缺少 secret"），因此这些包收不到任何新
版本 —— 修复在 186 里，但坏包拿不到 186，属于自锁死局。

公告接口 /api/announcements 不经过更新验签、匿名可读，是唯一还能触达这批
用户的通道。

用法（在 background.hpa888.top 上跑，需要读 /etc/box-image-platform.env）：
    sudo python3 post_recovery_announcement.py --dry-run
    sudo python3 post_recovery_announcement.py
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8799"
ENV_PATH = "/etc/box-image-platform.env"

TITLE = "更新检查失败？请手动装一次 1.8.6"

# 正文里重复给出下载地址：客户端把 linkUrl 渲染成 SelectableText，不可点击，
# 只能长按复制，所以不能只依赖 linkUrl 字段。
BODY = """如果你在检查更新时看到「更新清单签名校验未通过（HMAC 更新验签缺少 secret）」，这是我们打包时的失误，不是你的设备问题。

受影响版本：1.8.3(183)、1.8.4(184)、1.8.5(185)。

这三个版本打包时漏装了更新校验用的密钥，导致它们无法通过更新校验，也就收不到任何新版本 —— 包括修好这个问题的新版本。所以需要手动装一次，之后自动更新就恢复正常了。

下载地址（长按复制到浏览器打开）：
https://box.hpa888.top/updates/box/android/release/box-1.8.6-186.apk

直接覆盖安装即可，签名和原来一致，数据不会丢，不用先卸载。

装好后版本号会显示 1.8.6(186)，再点检查更新就不会报错了。给你带来的麻烦很抱歉。"""

LINK_URL = "https://box.hpa888.top/updates/box/android/release/box-1.8.6-186.apk"


def load_admin_credentials(path: str) -> tuple[str, str]:
    user = password = ""
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line.startswith("BOX_ADMIN_USERNAME="):
                user = line.split("=", 1)[1].strip().strip('"').strip("'")
            elif line.startswith("BOX_ADMIN_PASSWORD="):
                password = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not user or not password:
        sys.exit(f"未能从 {path} 读到管理员账号")
    return user, password


def post_json(path: str, payload: dict, token: str = "") -> dict:
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        sys.exit(f"{path} -> HTTP {exc.code}: {body[:400]}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="只打印将要发布的内容")
    args = ap.parse_args()

    print("=== 将要发布的公告 ===")
    print(f"level  : warning")
    print(f"pinned : True")
    print(f"title  : {TITLE}")
    print(f"linkUrl: {LINK_URL}")
    print("--- body ---")
    print(BODY)
    print("------------")

    if args.dry_run:
        print("\n[dry-run] 未发布。")
        return

    user, password = load_admin_credentials(ENV_PATH)
    auth = post_json("/api/auth/login", {"username": user, "password": password})
    token = auth.get("token") or (auth.get("data") or {}).get("token") or ""
    if not token:
        sys.exit("登录未返回 token")
    print(f"\n登录成功，token 长度 {len(token)}")

    created = post_json(
        "/admin/announcements",
        {
            "title": TITLE,
            "body": BODY,
            "level": "warning",
            "pinned": True,
            "linkUrl": LINK_URL,
            "published": True,
        },
        token=token,
    )
    ann = created.get("announcement") or created
    print("已创建公告：")
    print(f"  id        = {ann.get('id')}")
    print(f"  level     = {ann.get('level')}")
    print(f"  pinned    = {ann.get('pinned')}")
    print(f"  published = {ann.get('published')}")


if __name__ == "__main__":
    main()
