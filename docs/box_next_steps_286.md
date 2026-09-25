# 286 优化方案（box 应用；含宿主监控一条线）

> 命名说明：前几轮叫 `remote_storage_plugin_next_steps_28N.md`，因为范围就是远端存储插件。
> 这一轮范围扩到"整个 app 的插件 + 刚上线的监控链路"，所以改成 `box_next_steps_286.md`。

## 1. 事实基线（2026-09-25 核对，全部实机验证）

| 项 | 现状 |
|---|---|
| 线上版本 | **1.20.28+285（release id=127, published）**，284 已归档 |
| 内置插件 | 目录里 **16 条**（原 15 + 本轮「服务监控」），路由码登记在 `builtin_plugin_pages.dart` |
| 本轮新增插件 | `plugins/monitor/`：models 161 行 + page 466 行 + service 169 行 = **796 行** |
| 测试口径 | CI 口径 **3159 通过 / 3 跳过 / 0 失败**（排除 live）；插件目录 31 条 |
| analyze | 220 条（长期基线，门禁只卡 error/warning） |
| 悬挂 API 闸门 | 113 个公开方法 / 0 悬挂（已把 monitor 插件纳入） |
| 监控链路 | Kuma 10 项，cron `*/2` 采样 → 快照 893B → `https://box.hpa888.top/monitors.json` |
| **证书剩余（实测可采）** | myb **57 天** / kimi **43 天** / qwen 89 天 / zocr 76 天 —— 数字来自 `/metrics`，**目前没上界面** |
| remote_storage 未做项 | 限速/暂停：全仓 0 处；系统分享接收：`AndroidManifest.xml` 无 SEND 过滤 |
| 宿主侧 | GoAccess **两台都没装**；无任何安全巡检 cron |

## 2. 候选清单

### P 档（建议本轮四件）

| # | 项 | 落点（文件:行号） | 做法 | 收益 | 成本 | 验收标准 |
|---|---|---|---|---|---|---|
| **P1** | 监控插件收口：证书天数 + 采样链告警 + 端点收口 | `tool/gen_monitors_json.py:41`（LINE_RE 加 `monitor_cert_days_remaining`）、`:106 build()`、`:147 push_to_edge`；`monitor_models.dart:30/38/52`；`monitor_page.dart:411 _MonitorTile`；边缘机 `box.hpa888.top.conf` 的 `location = /monitors.json`；`monitor_service.dart:122` | ① 快照加 `certDays`（缺就省略，界面 `—`），行内显示「证书 43 天」，**<30 天标黄**；② 采样或推送失败时发飞书（复用已有告警链路），不再只写日志；③ 端点加共享 token（`$arg_token` 校验，不对返回 404） | 证书只剩 43 天这类信息从"哪天打不开才知道"变成提前可见；采样链断了能收到告警；端点不再裸奔 | 约 1 天（含用例） | 快照含 certDays 且界面显示；手动停 cron → 10 分钟内收到飞书；不带 token 请求 404，带上正常 |
| **P2** | 传输限速 / 暂停（285 D3） | `domain/webdav_client.dart:370 downloadTo` / `:442 uploadFrom`（按字节+时间片节流）、`application/remote_storage_service.dart:764/:998`（透传参数）、`application/transfer_queue.dart`（暂停=取消当前任务并留 `.part`） | 限速：每传 N 字节 sleep 到目标速率；暂停：取消在跑的任务、保留 `.part`，恢复时复用 C2 的 `resumeFrom`（206 追加 / 200 截断 / 416 清断点） | 弱网与流量敏感场景能限速；暂停/继续不必重下 | 约 1 天 + 用例 | 限速生效（单位时间字节数有界，用例断言）；暂停后 `.part` 在、恢复从中断处继续；不续传的服务端回落为重新下载 |
| **P3** | 接收系统分享上传（285 D4） | `android/app/src/main/AndroidManifest.xml:66`（新增 `SEND`/`SEND_MULTIPLE` 过滤）、`MainActivity.kt:17`（取 `EXTRA_STREAM`）、`remote_storage_service.dart:962 uploadFile`（复用入队） | 注册 `image/*` + `video/*`（**不用 `*/*`**，避免出现在所有分享面板），冷启动与 `onNewIntent` 两条路径都取 URI → 入传输队列，目标=当前目录 | 相册/文件管理器里分享文件直接进云盘 | 约 1 天（安卓侧 + 生命周期） | 从相册分享到 box → 任务出现在队列并上传成功；多选按数量入队；解析 URI 的纯函数有用例 |
| **P4** | 搜索复用目录快照（285 D1） | `application/remote_storage_service.dart:477 searchSubtree`、`:599 cachedListing`、`domain/remote_storage_models.dart:701 DirSnapshot` | 先用 D7 的快照秒出"上次见过的命中"并**显式标注可能过期**，同时后台精确扫，扫完替换 | 大目录搜索体感（不必每次等全树遍历） | 半天 + 5 用例 | 有快照时首屏立即可见且带"可能过期"提示；后台结果回来后替换；无快照时行为与现在一致 |

### D 档（体验，可挑）

| # | 项 | 落点 | 收益 | 成本 |
|---|---|---|---|---|
| D1 | 监控插件历史趋势（极简 sparkline） | 生成脚本维护最近 60 次采样的环形缓冲；页面自绘（约 20 行，无新依赖） | 从"挂了才知道"到"变慢了看得出" | 半天 |
| D2 | remote_storage 筛选增强（类型/大小/时间） | 本目录筛选（C3）+ D10 的匹配纯函数 | 目录里几百个文件时能用 | 低 |
| D3 | 监控项详情页（最近心跳/证书/检查目标） | `monitor_page.dart` 行点击 → 新页；需要快照补字段 | 面板外也能看单点细节 | 半天 |
| D4 | 清一批 analyze info（挑喜欢的几类） | 全仓 | 门禁只卡 error/warning，纯卫生 | 低（可选） |

### E 档（不建议本轮）

- **E1 上传续传**：WebDAV 没有标准部分 PUT（`Content-Range` 是扩展，多数服务端直接拒）→
  只做「能力探测 + 明确报错」，不做分片拼接（285 已拍板）。
- **E2/E3 视频首帧扩展到中继/摘要账户、非 Android 平台**：收益小、代价大（要为一帧开中继会话）。
- **E4 监控快照改实时 API**：要让 app 直连就得给它一个带鉴权的服务端，收益不抵成本
  （现在静态快照 + `generatedAt` 已经够用）。

## 3. 宿主侧（另一条线，不动 box 代码）

| # | 项 | 现状 | 做法 |
|---|---|---|---|
| H1 | Kuma 告警入口换成 Hermes 原生 webhook | 现在是 nginx 随机路径即密钥 + `hermes send` 裸转发 | 用 Hermes 的 webhook 路由接 Kuma：路径/令牌即密钥，触发的是一次 agent run —— 告警能带上下文（先查该项状态、看日志）再发飞书 |
| H2 | 安全巡检 | 无任何巡检 cron | 每日一次：sshd 失败登录、开放端口变化、证书到期（快照里已有数字）、磁盘/内存、Docker 镜像是否有更新、nginx 配置哈希变化 → 结果进飞书 |
| H3 | GoAccess 流量分析 | 两台都没装（实测） | 边缘机装 goaccess + 解析 nginx 日志 + 出一份内部报表（每日/每周） |
| H4 | 文件投放页 | 未开工 | 临时文件上传/取件页（带过期与口令） |

## 4. 规模粗估（非承诺）

| 档 | 项数 | 估时 | 说明 |
|---|---|---|---|
| P1–P4 | 4 | 约 3.5 天 | P1 收益最快见效 |
| D1–D4 | 4 | 约 1.5 天 | 都可拆开单独做 |
| H1–H4 | 4 | 另算 | 属于宿主运维，与 box 发布节奏无关 |

## 5. 待拍板（3 条，各带建议）

1. **范围**：建议本轮做 **P1–P4 四件**（P1 先把监控这条新链路收口，P2/P3/P4 清掉远端存储的
   三个真实缺口）；D 档下轮。
2. **快照端点的"收口"到哪一步**：建议只加**共享 token**（`$arg_token`，不对就 404）——
   它挡得住随手扫到的爬虫，但**不是真鉴权**（app 里的常量可被反编译看到）。要真鉴权得给每台设备
   发凭据，成本和收益不成比例。能接受这个定位就按建议做，要更严就说（比如换独立子域 + IP 白名单）。
3. **宿主侧 H1–H4**：建议**先不动**，等 box 这条线停下再单独排；如果你更想先做 H2（安全巡检），
   说一声我把它提到本轮前面。

## 6. 执行记录（2026-09-25，P1–P4 全部完成）

提交链（旧→新）：`c758025`(P1) → `81ae6ad`(P2) → `8e1d24b`(P3) → `e097e90`(P4) → `8119734`(提版 1.20.29+286)。

### P1 监控插件收口 ✅

| 项 | 结果 |
|---|---|
| 快照加证书天数 | `tool/gen_monitors_json.py` 解析 `monitor_cert_days_remaining`，快照每项写 `certDays`；实测 57 / 89 …（缺就不写字段） |
| 界面上界面 | `monitor_models.dart`：`certDays` / `certValid` / ~~`certificateLabel`~~ → 文案与告警判定（**<30 天标黄、已失效标红**）为纯函数；`monitor_page.dart` 行内显示 |
| 采样链故障告警 | 状态机（只在翻转时报）：`🔴 采样异常` / `🟢 已恢复`，走 `hermes send -t feishu`；**不重复报单项宕机**（那是 Kuma 的活）。实测两条告警都收到 |
| 端点收口 | 边缘机 nginx `location = /monitors.json` 加 `$arg_token` 校验；令牌 `/root/.secrets/box-monitor-snapshot-token`（600，不进仓库、不打印）。构建脚本经 `--dart-define=MONITOR_SNAPSHOT_TOKEN` 注入（缺文件直接构建失败） |
| 实测 | 不带 token → **404**；带 token → 200 + `application/json` |

**过程中纠正的一次误判**：加完 nginx 后第一次测"不带 token"仍是 200，一度以为闸门没生效。实际是 `nginx -s reload` 的优雅切换窗口——旧 worker 还在处理已有连接。第二次测（新 worker 生效后）就是 404。**教训：reload 后立刻的探测结果不代表新配置生效**。

### P2 传输限速 / 暂停 ✅

| 项 | 结果 |
|---|---|
| 限速 | 新增 `domain/transfer_throttle.dart`：按「已传字节 vs 已用时间」补等（不是每块睡固定时长）→ 服务器快一阵不会被额外惩罚；档位 不限/1M/512K/256K，偏好落盘（`remoteStorage.transferRateLimit`），**对之后开始的传输生效**；`downloadTo` / `uploadFrom` 每块之后过一遍限速器（上传体改成 `asyncMap`，因为 `map` 回调是同步的、没法 await） |
| 暂停/继续 | `TransferStatus.paused`：在跑的取消当前传输（`.part` 保留），排队中的直接转暂停；`pause/pauseAll/resume/resumeAll/pausedCount`；**暂停态单独落盘**（`paused` 标记）→ 重启后恢复成暂停态而不是自动开跑；清空已完成不动暂停的任务 |
| 界面 | 行内「暂停 / 取消 / 继续」、顶部「全部暂停 / 全部继续」与限速菜单；暂停的条目**仍显示进度条**（压暗）+「已暂停」 |
| 用例 | 限速原语 5 条 + 接线 3 条（记录型限速器，不起真等待）+ 队列暂停 8 条 + 界面 5 条 = **21 条** |

**两个测试期发现的坑（已写进代码注释）**：① `pause()` 会立刻改状态，但在跑的那次要自己抛取消才算收尾——想断言"暂停已生效"必须看 `debugRunningCount`，不是看状态；② 假传输层**必须读完 PUT 的请求体**，否则流式上传的 `asyncMap` 不推进（限速器一次都不被调用）。

### P3 接收系统分享上传 ✅

| 项 | 结果 |
|---|---|
| 声明 | `AndroidManifest.xml`：`SEND` + `SEND_MULTIPLE` 各两个 `image/*` / `video/*` 过滤（**不用 `*/*`**） |
| 原生 | 新增 `ShareInboxReceiver.kt`：把 `content://` 内容**复制进缓存**（Dart 拿不到 ContentResolver），文件名清洗（去路径分隔符与 `../` 写法）、单文件 512MB / 每次 20 个上限、过期中转文件 24h 兜底清理；`MainActivity` 冷启动 + `onNewIntent` 两条路径都收 |
| Dart | `share_inbox_models.dart`（纯解析，坏条目跳过不整份作废）、`share_inbox_channel.dart`（`ready` / `takePending` / `onSharedFiles`）、`share_inbox_sheet.dart`（选账户 + 目标目录，默认第一个账户与根目录）、`share_inbox_gate.dart`（挂在 `home` 之下、Navigator 之上） |
| 上传 | 全部走已有传输队列（并发/重试/落盘/前台保活），**只删 `shared_inbox` 目录里的中转副本**（绝不删用户原图） |
| 用例 | 模型 8 条 + 通道 5 条 + 面板 5 条 + 闸门 4 条 = **22 条** |

**与方案的两处差异（都是实施中改的，写清楚）**：① 方案写的是"取 URI → 入队列，目标=当前目录"，实际必须**先复制进缓存**再上传（Dart 侧拿不到 `content://` 的真实路径与大小，也没有流式上传通路）——代价是多一次本地复制，收益是复用已有上传链路；② 方案没提"传到哪里"的交互，实施时加了账户/目录选择面板（多账户场景下必须有这一步）。

**诚实说明**：P3 只在单测与构建层面验证过（原生代码、清单、AOT 标记）。**真机分享动作没有验证**——本机没有 Android 设备/模拟器，需要你在手机上从相册选一张图/一段视频「分享 → box」实测一次。

### P4 搜索复用目录快照 ✅

| 项 | 结果 |
|---|---|
| 做法 | `searchSubtree(useSnapshot: true)` 默认先读 D7 目录快照：**上限 1 小时**，超龄不采信（宁可慢也不给用户看过时目录）；现场列过的目录顺手存快照 → 下次搜索几乎瞬时 |
| 诚实标注 | `SubtreeSearchResult` 增 `snapshotDirs` / `oldestSnapshotAt` / `snapshotNote(now)`：面板写「其中 N 个目录用了本地缓存（最旧 X 分钟前），刚新增的文件可能还没出现。」 |
| 重新搜索 | 用了缓存时面板多一个「重新搜索」→ `useSnapshot: false` 现场重列（面板返回值放宽成 `Object`，用哨兵对象区分"点了条目"与"点了重搜"） |
| 用例 | 服务 5 条 + 文案 3 条（合计 8 条）+ 面板 1 条 |

**与方案的差异**：方案写的是"先用快照秒出 + 后台精确扫、扫完替换"。实际做成**快照优先 + 显式「重新搜索」**——原因是"后台扫完替换"要在面板还开着时改内容，交互上更容易让人误以为结果自己变了；给一个明确按钮更简单也更诚实。**收益同为"不必每次等全树遍历"**。

### 验证（真实输出，2026-09-25）

| 项 | 结果 |
|---|---|
| 全量测试（CI 口径，排除 live） | **3217 通过 / 3 跳过 / 0 失败**（285 基线 3159；本轮 +58 条用例） |
| analyze | **220 条**（长期基线；本轮新增 lint 已清零） |
| 悬挂 API 闸门 | **126 个公开方法 / 0 悬挂**（285 为 113） |
| release 构建 | `BUILD_EXIT=0`，`app-release.apk` **27,099,696 字节**，sha256 `b314a8d53e624c5524d404816125bfdada7b3cc4250ce12cb141524cd41b31e9`；符号表归档 `/root/.box-symbols/286`（**285 的没被覆盖**）；验签密钥指纹 `fc9d22015158` 已注入 |
| 包内核对（独立脚本 `verify286.py`，非脚本自述） | ① dex 字符串池含 `top.hpa888.box/share_inbox`、`takePending`、`onSharedFiles`（P3 原生代码进包）；② APK 清单 `.MainActivity` 子树含 **2×SEND + 2×SEND_MULTIPLE、image/video 各 2 个、无 `*/*`**；③ `libapp.so` 286 新增标记 11/11 出现、控制项 6/6 不变；④ 快照令牌已注入（只校验存在性，不打印） |
| 监控端到端 | 不带 token → **404**、带 token → 200；快照 10 项含 `certDays`（myb 57 / kimi 43 / qwen 89 / zocr 76 …）；生成脚本仓库版与 175 部署版 sha256 一致 `533f4368…`；cron `*/2` 在跑 |

### 构建验证逮到的三个坑（都已修/已记）

1. **Kotlin 块注释可嵌套**：KDoc 里写 `image/*` 等于又开一层注释，KDoc 的 `*/` 只关掉内层 → `Unclosed comment` → `assembleRelease` 失败。**只看 analyze / 单测永远发现不了原生编译问题**。
2. **release 会 R8 混淆**：非清单引用的类（如 `ShareInboxReceiver`）会被改名 → "dex 里搜类名" 不能作为"没进包"的判据（285 的 `VideoTransferKeepAliveService` 找得到，是因为 Service 在清单里声明、名字被保留）。正确判据是查该类自己的字符串常量。
3. **`aapt2 dump xmltree` 每条属性打印两次**（`A: ...="x" (Raw: "x")`）→ 计数是声明数的 2 倍，断言写错会误报"清单不对"。

### 未做 / 待你确认

- **未发版**：已提版 `1.20.29+286` 并构建验证，等你一声「发布」再走发布流程。
- **真机确认项**：① 相册选图 → 分享到 box → 选账户/目录 → 应出现在传输队列并上传成功；② 传输面板能「暂停/继续」，暂停后进度条还在；③ 传输面板右上角限速菜单选 512KB/s 后，新任务应明显变慢；④ 大目录里搜子目录应秒回并标注"其中 N 个目录用了本地缓存"；⑤ 首页「服务监控」里应能看到「证书 43 天」这类信息。
- **D 档（趋势 sparkline、筛选增强、监控项详情、analyze 卫生）与宿主侧 H1–H4** 仍未开工。

