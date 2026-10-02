# AI HOT 资讯：点开内容不对的修复 + 数据源迁到 v1（353）

> 面向用户的一句话结论：**首页「资讯」卡的 AI 页签，点任何一条热点都会跳到「视界日报」门户页 —— 已修好；
> 同时把 AI HOT 数据源迁到 v1，否则 2026-10-31 之后这个区块会整个空掉。**

## 一、事实基线（全部实测，不是文档里的状态标签）

| 项 | 实测值 | 依据 |
|---|---|---|
| 线上最新包 | `352` / `1.20.95` | `GET https://box.hpa888.top/api/v1/app-updates/check?...version_code=1` → `latestVersionCode: 352` |
| 线上包对应的发布提交 | `f50d321` | `git log --oneline -1`（工作区 HEAD 就是它） |
| 该提交里的白名单 | 只有 `aihot.virxact.com` | `git show f50d321:lib/daily_news_url_policy.dart` 第 26–35 行 |
| 上游今天的条目链接主机 | **`aihot.news`** | `curl 'https://aihot.news/api/v1/items?mode=selected&window=7d&limit=4'` → `links.aihot = https://aihot.news/items/<id>` |
| 接口主机 | 旧 `aihot.virxact.com` / 新 `aihot.news` | 同上；`https://aihot.virxact.com/items/<id>` 返回 **301** |
| 上游停用公告 | 旧接口 `/api/public/*` 与旧域名 **2026-10-31 一起停用**，之后旧域名只做跳转 | `https://aihot.news/agent?tab=api` 的「旧接口和旧域名」一节（同时它是**必须尽快迁**的理由） |

### 根因

`DailyNewsPage` 只允许在内嵌 WebView 打开白名单里的主机，不在名单里的地址它会**静默回落**到门户页
（`actcpc.heytapimage.com` 那个「视界日报」H5）。而白名单里写的是**接口**主机 `aihot.virxact.com`，
上游给我们点开的却是 `aihot.news/items/…`（**条目页主机**）。两者不是一回事 —— 于是每条热点点开都是门户页，
一个字的提示都没有。

这个 bug 骗过了上一版用例：那份用例自己手写了一个 `https://aihot.virxact.com/items/…` 当「真实 permalink 形态」，
而真实响应里从来没有这个地址。**用例锁的是我们的假设，不是上游的事实**，所以上游换域时它照样绿灯。

### v1 字段对照（迁移的全部内容）

| 旧（`/api/public/*`） | 新（`/api/v1/*`） |
|---|---|
| `take` | `limit` |
| （无） | `window`（只认 `24h`/`7d` 这类枚举；实测 `1h`/`6h`/`30d` 直接 **400**） |
| 条目 `url` | `links.original` |
| 条目 `permalink` | `links.aihot` |
| 条目 `source`（字符串） | `source.name` |
| 条目 `title_en` | `originalTitle` |
| `attribution{source,canonical}` | `attribution{name,url}` |
| 顶层 `count`/`hasNext`/`nextCursor` | `page.count`/`page.hasMore`/`page.nextCursor` |
| —— | 只接受 OpenAPI 里声明过的参数：**多带一个 `take` 就是 400** |

## 二、改了什么

| # | 文件（行号） | 改动 | 判据 |
|---|---|---|---|
| 1 | `lib/daily_news_url_policy.dart:52-61` | 白名单加 `aihot.news`（保留旧域名给用户手上的旧链接） | `resolve(实现里的 links.aihot)` 原样通过 |
| 2 | `lib/daily_news_url_policy.dart:23-36,84-95` | 新增 `DailyNewsTarget` / `decide()`：站外地址标 `blocked` 并**原样带回原地址**，不再静默换门户页 | 站外 x.com/arxiv → `isBlocked`；`resolve()` 旧行为不变（插件入口仍能看门户） |
| 3 | `lib/daily_news_page.dart:38-40,85-92,136-138,144-206` | 站外地址改成一页如实说明 + 「复制链接」（App 无 `url_launcher`，沿用本仓库「复制而不是跳浏览器」的既有做法）；标题按**真正加载的主机**取名；页面里点到站外链接给一句提示 + 复制，不再「点了没反应」 | 真机上「内容不对」不再表现为「另一个站」 |
| 4 | `lib/features/home/data/ai_hot_service.dart:42-53,84-86` | 迁 v1：主机 `aihot.news`、路径 `/api/v1/items`、`take`→`limit`、显式 `window=7d`（与旧接口默认窗口对齐，迁移后条数/新鲜度不变） | 单测断言 host/path/参数名，且**断言不带 `take`** |
| 5 | `lib/features/home/data/ai_hot_models.dart:141-151,235-236` | 同时吃 v1 与旧形状（老版本写进本机缓存的快照还能显示）；删掉 `attributionCanonical`（它是**单条**条目页，不是站点 canonical，正是 #6 那个 bug 的来源） | 两份真实响应夹具都要过 |
| 6 | `lib/features/home/presentation/home_page.dart:388,747`；`daily_news_service.dart:105` | AI 页签「更多」→ `https://aihot.news/`（站点列表）；热闻「更多」→ `https://daily.zhihu.com/`（列表是知乎日报的内容，此前跳的是视界日报门户） | 两个落点都在白名单内，单测覆盖 |
| 7 | `test/daily_news_page_host_allowlist_test.dart`（重写） | 主机/字段**全部从真实响应快照里取**（v1，2026-10-02），断言「每条 hot 的链接原样通过白名单」+ 仿冒后缀/非 http scheme 仍被拒 | 这条断言就是这个 bug 的回归锁 |
| 8 | `test/features/home/ai_hot_feed_test.dart`、`ai_hot_live_e2e_test.dart` | 加 v1 夹具与解析用例；live 用例新增「真实上游今天给的主机必须在白名单里」这道端到端闸门；真连上游的超时从 30 秒放宽到 2 分钟（有负载时同一条链路实测 5s→65s，会把「机器忙」误报成「上游坏了」） | —— |
| 9 | `lib/features/home/presentation/widgets/ai_hot_section.dart`（`AiHotRow`） | AI 行标题下加**摘要**（上游每条都给 `summary`，此前解析了却没人显示 —— 想知道这条讲什么只能点开，而原文常在 x.com）；最多 2 行 + 省略号，`summaryMaxLines` 是公开常量、用例锁住它 | `home_feed_tabs_test.dart`：有摘要要渲染且 `maxLines == 2`；没有摘要不许留空行（行高控制组） |

## 三、验证（都跑过，输出可复算）

| 验证 | 命令 | 结果 |
|---|---|---|
| 静态检查（CI 口径） | `flutter analyze --no-fatal-infos` | **28 issues = 本轮开始时的基线 28**（`git stash` 前后各跑一次），0 error / 0 warning |
| 定向用例 | `flutter test test/daily_news_page_host_allowlist_test.dart test/features/home/ai_hot_feed_test.dart test/features/home/home_feed_tabs_test.dart test/features/home/home_news_empty_state_test.dart` | **49 passed**（含新增的摘要两条用例） |
| 全量（CI 口径） | `flutter test --exclude-tags live` | **All tests passed!**（4197 passed / 0 failed / 3 skipped） |
| 真连上游（e2e） | `flutter test --tags live test/features/home/ai_hot_live_e2e_test.dart` | All tests passed（真实 v1 响应 + 解析 + 白名单一致性） |
| 产物核对（发布前） | `verify_release_apk.py <新包> <352的包> f50d321 1.20.96 353 --require-literal '这条内容要在浏览器里打开' --control-literal '资讯'` | 全部通过：版本/ABI/证书正确、包内无口令（0/0）、注入项 0→1、控制组 6→6、AOT 新增字面量 4 条（站外说明页 3 条 + 「知乎日报」）。**摘要那一项没有新增字面量**（纯渲染改动），它的证据是同一次构建 + 49 条定向用例 |
| 发布（2026-10-02） | hpa888 `box-publish-apk.py`（演练后正式） | release **id=194** `1.20.96(353)` published，352 归档；公网包逐字节一致、HMAC 复核通过、352 客户端 `hasNewVersion=true` 且 `effectiveForceUpdate=false`（建议升级、不强制）、353 客户端不再提示；服务端临时包已清理 |
| 未验证 | 真机 | 验收见下（升级到 1.20.96 后两步） |

### 真机验收（用户侧两步就能做完）

1. 升级后打开首页 → 「资讯」卡切到 **AI** 页签 → 点任意一条：应看到 **AI HOT 的条目页**（标题是那条热点本身，不是「视界日报」）。
2. 再点右上角「更多」：应进 **aihot.news 的列表页**（标题「AI 热点」），而不是某一条热点、也不是视界日报。

> 没拿到「发」之前，本轮的改动只到「代码 + 用例 + 本地提交」。

## 四、没做 / 可选项（等拍板）

| 项 | 现状 | 建议 | 代价 |
|---|---|---|---|
| ~~条目摘要没露出来~~ | **本轮已做**（见改动 #9）：AI 行标题下加摘要，最多 2 行 | —— | 每行高约 +30dp（两行摘要 + 间距）；AI 页签不是首屏页签，热闻页签（默认）不受影响 |
| 「为什么入选」的 `reason`（v1 新字段） | 未解析、未显示。2026-10-02 实测 50/50 条都有 `summary`，`reason`（入选理由）和它说的是两件事 | **建议不做**：没有「缺摘要」的条目，回落逻辑永远走不到；两个都显示则每行更长 | —— |
| 站外原文想真正在浏览器里打开 | 现在只能「复制链接」（项目没有 `url_launcher`，4 处注释为证）。实测 50/50 条都有站内条目页，说明页是罕见兜底 | **建议不做**：要加依赖或写原生通道，换来的是一条一年也碰不到几次的兜底路径 | 中 |
| 时间窗 `7d` vs `24h` | 现在 `7d`，与迁移前条数/新鲜度一致（实测 7d→50 条上限、24h→24 条） | 想更「新」可以把首页预览改成 `24h` | 极端时段（早上）可能只剩几条甚至空态；空态有重试与缓存兜底，但不划算，建议维持 `7d` |
| ETag / `If-None-Match` | 未做 | 上游建议带上（变化时返回 304 省流量） | 5 分钟客户端缓存已把请求压到 12 次/小时（限流约 60 次/分钟），收益低，且要多一份需要持久化的状态 |
| 分页 `page.nextCursor` | 未读（首页只看前几条） | 等真的做「AI 热点列表页」时再接 | —— |

## 五、连带提醒（上游要求转告）

上游公告里明确请接入方把这条转告用户：**旧接口 `/api/public/*` 与旧域名 `aihot.virxact.com` 于 2026-10-31 停用**。
本版已迁到 `https://aihot.news/api/v1`，所以只要这一版发出去就不受影响；若这一版一直不发，10-31 之后首页 AI 页签会退化成
「拿不到内容 → 显示上次缓存（标注缓存）→ 最终空态」。

## 六、下一轮（354）：把「假设 vs 事实」的对照做成工具

353 真正暴露的问题不是那一个白名单写错，而是**客户端的手写假设和上游的事实之间
没有任何自动对照**：夹具手写 → 用例锁的是假设 → 白名单写错也一路绿，直到真机点开。
这一轮把它做成闭环（三项，都在 354 里）。

| # | 改动 | 落点 | 判据 |
|---|---|---|---|
| A1 | 分类标签补三档：`ai-products`→产品、`industry`→行业、`tip`→教程 | `lib/features/home/data/ai_hot_models.dart` 的 `categoryLabel` | 2026-10-02 拉 50 条精选实测分布 `ai-products 13 / tip 11 / ai-models 11 / industry 10 / paper 5`；修复前这三档全部落到 `default`，首页 AI 行的标签位直接显示英文 slug。中文名照抄上游 `/api/v1/agent` 的官方说法，不自己另起名字 |
| B1 | `tool/refresh_ai_hot_fixture.py`：从上游抓真实响应写进夹具（**每个分类留一条，字段字节未改**），并报告主机 / 分类 / 字段相对客户端假设的差异；`--check` 可当闸门（夹具过期退 1） | 新文件 + `test/fixtures/ai_hot_selected_v1.json` | 跑一次输出 `条目页主机: aihot.news / 白名单: ✅ / 分类: ✅`；两个用例文件改为读这份夹具（不再手写） |
| B2 | `tool/check_ai_hot_live.dart`：拿**客户端自己的**模型和白名单打一次当天真实接口 —— 解析条数对不上、条目页主机不在白名单、分类没中文标签 → 退 1；上游不可达 → 打印「跳过」并退 0（离线不阻断发版） | 新文件 + 接进 `tool/build_release_with_update_sign.sh`（入口守卫之后、Gradle 之前） | 反证：临时摘掉 `tip` 一档 → `dart run` 退 1 并指名「分类 tip 没有中文标签」；恢复后通过。**正证**：`上游 50 条 · 条目页主机 aihot.news · 分类 industry→行业, tip→教程, ai-models→模型, ai-products→产品, paper→论文` |

为什么闸门要「不可达就跳过」：发版机离线或上游限流都不该阻断发布，
但**上游可达而假设漂了**必须当场断 —— 那正是 353 那个 bug 的形状。

### 验证（都跑过）

| 验证 | 命令 | 结果 |
|---|---|---|
| 静态检查 | `flutter analyze --no-fatal-infos` | **28 issues**（与基线一致，0 error / 0 warning；新增的两个 `tool/` 脚本自身 0 issue） |
| 定向用例 | `flutter test test/daily_news_page_host_allowlist_test.dart test/features/home/ai_hot_feed_test.dart test/features/home/home_feed_tabs_test.dart` | **47 passed**（含新增「每个分类都有中文标签」） |
| 全量 | `flutter test --exclude-tags live` | **All tests passed!**（4198 passed / 0 failed / 3 skipped） |
| 真连上游 | `flutter test --tags live test/features/home/ai_hot_live_e2e_test.dart` | All tests passed |
| 活体闸门（正证） | `dart run tool/check_ai_hot_live.dart` | 退 0：`上游 50 条 · 条目页主机 aihot.news · 分类 industry→行业, tip→教程, ai-models→模型, ai-products→产品, paper→论文` |
| 活体闸门（反证） | 临时摘掉 `case 'tip'` 后重跑 | 退 1，指名 `✗ 分类 tip 没有中文标签（界面上会直接显示英文 slug）`；恢复后回 0 |
| 夹具刷新 | `python3 tool/refresh_ai_hot_fixture.py` → 再 `--check` | 首次「需要更新」并写盘；复跑报「与上游一致」（退 0） |
| 悬挂 API | `python3 tool/scan_dangling_apis.py` | 悬挂 0 个 |
| 静默失败 | `python3 tool/scan_silent_failures.py --baseline 48` | 候选 **48 = 基线**（未新增） |

> 没拿到「发」之前，这一轮同样只到「代码 + 工具 + 用例 + 本地提交」。
