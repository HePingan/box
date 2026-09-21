#!/usr/bin/env python3
"""在更新服务端插入「公开历史更新日志」端点。

为什么需要这个补丁：客户端「关于 → 更新内容 → 历史更新」要列出每个版本改了
什么，但服务端只有两个公开端点（check / latest），都只回**最新一版**。能列全部
版本的 `/api/v1/admin/releases` 挂着 `Depends(get_current_admin)` —— 把管理员
凭据打进 APK 等于把发布后台的钥匙分发给每个用户，不可行。

安全取舍（这是本补丁最重要的部分）：
只回放 changelog 元数据，**刻意不回放 downloadUrl / backupDownloadUrl / sha256 /
publicApkPath**。历史版本里存在 HMAC 验签坏掉的包（v1.9.9+199）和被 rollback 的
记录，把下载地址公开出去等于给用户一条装到坏版本的路。用户要的是「哪个版本改了
什么」，给这个就够。

只列 status == 'published'：draft / rolled_back 的记录不该出现在用户面前。

幂等：重复执行不会插入第二份（先查标记）。
"""

import re
import sys

TARGET = "/home/update-server/app/main.py"

MARKER = "/api/v1/app-updates/history"

# 插在公开 latest 端点之后、admin 段之前；用 latest 端点的装饰器作锚点。
ANCHOR = '@app.get("/api/v1/app-updates/latest")'

NEW_ENDPOINT = '''
# =========================
# 公共：客户端查看历史更新日志
# =========================
@app.get("/api/v1/app-updates/history")
def update_history(
    app_id: str = Query(..., description="应用ID"),
    platform: str = Query(..., description="平台，例如 android"),
    channel: str = Query("release", description="渠道，例如 release/beta"),
    package_name: str | None = Query(None, description="包名，可选"),
    limit: int = Query(30, ge=1, le=100, description="最多返回多少条"),
    db: Session = Depends(get_db),
):
    """公开的历史版本更新日志。

    刻意**只回元数据**，不含 downloadUrl / backupDownloadUrl / sha256 /
    publicApkPath。历史版本里有验签坏掉的包和被回滚的记录，公开下载地址
    等于给用户一条装到坏版本的路。想装新版走 /check 那条正规链路。

    只列 status == 'published'：draft 和 rolled_back 不该出现在用户面前。
    """
    q = db.query(Release).filter(
        Release.app_id == app_id,
        Release.platform == platform,
        Release.channel == channel,
        Release.status == "published",
    )

    if package_name:
        q = q.filter(Release.package_name == package_name)

    releases = (
        q.order_by(Release.version_code.desc())
        .limit(limit)
        .all()
    )

    items = [
        {
            "versionName": r.version_name,
            "versionCode": r.version_code,
            "publishedAt": utc_iso(r.published_at),
            "title": r.title,
            "changelog": json_list(r.changelog_json),
            "forceUpdate": r.force_update,
        }
        for r in releases
    ]

    return ok({"items": items, "total": len(items)})


'''


def ensure_utc_iso_import(source: str) -> str:
    """`utc_iso` 在 main.py 的 services 导入清单里没有，用了会 NameError。

    补在 `set_json_list,` 之后（清单是字母序）。已存在则原样返回。
    """
    if re.search(r"^\s+utc_iso,\s*$", source, flags=re.M):
        return source

    needle = "    set_json_list,\n"
    if needle not in source:
        raise SystemExit("FAIL: 找不到 services 导入清单锚点 set_json_list")

    # signature_state 之后、validate_apk_file 之前，保持字母序
    return source.replace(
        "    validate_apk_file,\n",
        "    utc_iso,\n    validate_apk_file,\n",
        1,
    )


def main() -> int:
    with open(TARGET, "r", encoding="utf-8") as fh:
        source = fh.read()

    if MARKER in source:
        print("SKIP: 端点已存在，未重复插入")
        return 0

    source = ensure_utc_iso_import(source)

    if ANCHOR not in source:
        print(f"FAIL: 找不到锚点 {ANCHOR!r}", file=sys.stderr)
        return 1

    # 找到 latest 端点函数体的结束位置：下一个顶层 '@app.' 或 '# ====' 段落
    anchor_at = source.index(ANCHOR)
    tail = source[anchor_at + len(ANCHOR):]

    # 下一个顶层装饰器即为边界
    nxt = re.search(r"\n@app\.(get|post|put|delete)\(", tail)
    if not nxt:
        print("FAIL: 找不到 latest 端点之后的下一个路由，无法确定插入点", file=sys.stderr)
        return 1

    insert_at = anchor_at + len(ANCHOR) + nxt.start() + 1

    # 若边界前带有 '# ====' 注释块，插到注释块之前
    before = source[:insert_at]
    comment_block = re.search(r"(# =+\n(?:#.*\n)*# =+\n)\Z", before)
    if comment_block:
        insert_at = comment_block.start()

    patched = source[:insert_at] + NEW_ENDPOINT.lstrip("\n") + source[insert_at:]

    with open(TARGET, "w", encoding="utf-8") as fh:
        fh.write(patched)

    print(f"OK: 已插入 {MARKER}，插入位置偏移 {insert_at}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
