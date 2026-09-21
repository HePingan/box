#!/usr/bin/env python3
"""发一条 box 用户公告。

凭据从 image_platform_quota_server 的进程环境读取（BOX_ADMIN_USERNAME /
BOX_ADMIN_PASSWORD），不落盘、不进命令行参数、不回显 —— 命令行参数在 `ps` 里
全机可见，所以密码只能走 stdin/环境。

用法（在服务器上以 root 运行）：
    sudo python3 post_announcement.py <<'JSON'
    {"title": "...", "body": "...", "level": "info", "pinned": false,
     "linkUrl": "..."}
    JSON


服务器是 CentOS 系的 Python 3.6，所以：不用 `from __future__ import annotations`、
不用 `X | None` 联合类型、不用 dict 的 `|` 合并。f-string 可以用。
"""

import json
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8799"
PID_HINT = "image_platform_quota_server"


def read_admin_creds():
    """从服务进程的 environ 里取管理员账密。"""
    import glob
    import os

    for environ_path in glob.glob("/proc/[0-9]*/environ"):
        pid = environ_path.split("/")[2]
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as fh:
                if PID_HINT not in fh.read().decode("utf-8", "replace"):
                    continue
            with open(environ_path, "rb") as fh:
                env = dict(
                    part.split("=", 1)
                    for part in fh.read().decode("utf-8", "replace").split("\0")
                    if "=" in part
                )
        except (OSError, PermissionError):
            continue
        user = env.get("BOX_ADMIN_USERNAME")
        pwd = env.get("BOX_ADMIN_PASSWORD")
        if user and pwd:
            return user, pwd
    raise SystemExit(f"找不到 {PID_HINT} 进程的管理员凭据（需要 root 读 /proc/*/environ）")


def call(method, path, payload, token):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(f"{BASE}{path}", data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")[:400]
        raise SystemExit(f"HTTP {exc.code} {method} {path}\n{body}") from exc


def main():
    spec = json.load(sys.stdin)
    for required in ("title", "body"):
        if not spec.get(required):
            raise SystemExit(f"缺少字段：{required}")

    user, pwd = read_admin_creds()
    # 登录端点是 /api/auth/login（不是 /admin/login，后者不存在）。
    # 密码本身不能当 Bearer token 用 —— 直传会 401「请使用管理员账号登录后操作」。
    login = call("POST", "/api/auth/login", {"username": user, "password": pwd}, None)
    payload = login.get("data") if isinstance(login.get("data"), dict) else login
    token = payload.get("token") or payload.get("accessToken")
    if not token:
        raise SystemExit(f"登录没拿到 token，响应字段：{list(payload)}")
    print(f"[OK] 已登录管理员（user={user}）")

    created = call(
        "POST",
        "/admin/announcements",
        {
            "title": spec["title"],
            "body": spec["body"],
            "level": spec.get("level", "info"),
            "pinned": bool(spec.get("pinned", False)),
            "linkUrl": spec.get("linkUrl", ""),
            "published": True,
        },
        token,
    )
    ann_id = created.get("id") or created.get("data", {}).get("id")
    print(f"[OK] 公告已创建 id={ann_id}")

    # 核验：从公开接口读回，确认用户端真能看到
    public = call("GET", "/api/announcements?limit=5", None, None)
    items = public.get("announcements") or public.get("items") or []
    hit = next((i for i in items if i.get("id") == ann_id), None)
    if hit is None:
        raise SystemExit("[FAIL] 公开接口读不到刚发的公告 —— 可能没 published")
    print(f"[OK] 公开接口已可见：{hit['title']}  level={hit['level']}")
    print(f"[OK] 公告总数={public.get('total')} version={public.get('version')}")


if __name__ == "__main__":
    main()
