# 287 优化方案（box 应用 + 宿主监控这条线）

> 事实全部来自本轮实测（2026-09-25，线上 1.20.29+286 已发布之后）。凡"现状"一栏都标了实测命令的口径。

## 1. 事实基线

| 项 | 现状（实测） |
|---|---|
| 线上版本 | **1.20.29+286（release id=128, published）**，285（id=127）已归档 |
| 本仓 HEAD | `c5a6b12`（286 发版收尾 + 两处小修） |
| 内置插件 | 目录 **17 条**；`plugins/` 下代码 **15,567 行** |
| 测试 | CI 口径 **3217 通过 / 3 跳过 / 0 失败**（426 个测试文件）；live 用例另计 |
| analyze | **218 info / 0 warning / 0 error**（`flutter analyze --no-fatal-infos lib test` → 退出码 0，即 `.github/workflows/ci.yml` 用的命令） |
| 悬挂 API 闸门 | **126 个公开方法 / 0 悬挂** |
| 远端存储现有能力 | 浏览/上传/下载/预览/播放/删除/新建/**重命名/复制到…/移动到…**（后三项已有入口，别当缺口）、限速、暂停继续、系统分享接收、跨目录搜索（复用快照）、文件夹上传、递归下载 |
| **网络条件感知** | **全仓 0 处**：`pubspec.yaml` 无 `connectivity_plus`/`network_info`，也没有 wifi/移动网络判断 → "移动网络下是否要传"目前无人回答 |
| 分享接收的边界 | 单次 **上限 20 个**、单文件 **512MB**；超限与读不出来的**静默跳过**（界面只说"收到 N 个"，没说跳过了几个） |
| 传输并发 | 固定 `kMaxConcurrentTransfers = 3`，不可调（不是问题，但值得知道） |
| 监控快照字段 | `generatedAt / panelUrl / summary` + 每项 `{name, up, id, pingMs, certDays, certValid, uptime24h}` —— **无历史序列**（趋势类需求必须先在采样侧攒数据） |
| 175 磁盘 | **86%**（40G 用了 34G，余 5.6G）——大头：`/root/.gradle` 5.0G、`/root/Android` 3.6G、`/root/box` 3.0G、`/root/.npm` 1.0G、`/var/cache` 953M、`/root/.hermes` 883M、`.pub-cache` 767M、`.dartServer` 481M、`.cache` 335M、`.android` 252M、旧备份 `/root/restore` 123M + `ha-main-175.tar.gz` 72M + `ha-shards` 72M |
| hpa888 磁盘 | 65%（59G 用了 37G，余 20G）——不紧张 |
| 宿主监控 | Kuma 10 项、cron `*/2` 采样、快照端点已收口（token 闸门实测 404/200）；告警链路仍是 nginx 随机路径 + `hermes send` 裸转发 |
| 安全巡检 | **没有任何巡检 cron**（`crontab -l` 8 行里没有；Hermes cron 只有"第二只眼睛"盯主机的 5 分钟探活） |
| GoAccess | 两台都没装 |

## 2. 候选清单

### P 档（建议本轮四件）

| # | 项 | 落点 | 做法 | 收益 | 成本 | 验收标准 |
|---|---|---|---|---|---|---|
| **P1** | 移动网络下的传输策略（仅 Wi-Fi / 每次问 / 都允许） | 新 `domain/network_status.dart` + `data/network_status_channel.dart`（原生 `ConnectivityManager`，沿 `ShareInboxReceiver` 的通道形状）；`application/transfer_queue.dart` 的 `_pump` 前加闸门；`presentation/remote_storage_page.dart` 传输面板加档位菜单（与限速菜单并列） | 三档偏好（默认"仅 Wi-Fi"）：非 Wi-Fi 时任务停在队列里标「等待 Wi-Fi」，切回 Wi-Fi 自动开跑；"每次问"档弹一次确认；**不引第三方依赖**（原生通道 + 已有 MethodChannel 模式） | 出门在外不会因为一个 3GB 的下载把流量跑光——这是远端存储目前最贵的一类事故 | 约 1 天（原生 + 状态机 + 用例） | 假通道返回"移动网络"时任务不入 running 且标「等待 Wi-Fi」；切回 Wi-Fi 自动开始；三档偏好落盘且重启生效 |
| **P2** | 分享接收的"诚实计数" | `ShareInboxReceiver.kt`（返回 `received/total` 与跳过原因）、`share_inbox_models.dart`、`presentation/share_inbox_sheet.dart` | 原生把"分享里有几个、收了几个、为什么没收"一起报上来（超 20 个上限 / 单文件超 512MB / 读不出来 / mime 不在 image\|video），界面写清「分享 25 个，收了 20 个（5 个超过单次上限）」并给"再分享一次剩余的"提示 | 现在超限是静默的——用户以为传了 25 个，实际只有 20 个，事后无法察觉 | 半天 | 分享 25 个 → 界面明确写出 20/25 与原因；单文件超限 → 指名道姓列出；纯函数解析用例 + 面板用例 |
| **P3** | 监控插件：历史趋势 + 单项详情 | `tool/gen_monitors_json.py`（环形缓冲最近 N 次采样）、`monitor_models.dart`（`pingSeries` 解析）、`monitor_page.dart`（行内迷你折线 + 点进详情页） | 采样侧维护最近 **60 次**（约 2 小时）每项 `pingMs/up` 序列写进快照（快照会涨到 ~20KB，仍是静态文件）；页面自绘 2px 折线（**无新依赖**），详情页显示最近心跳、证书、24h 可用率与"从什么时候开始不通" | 从"挂了才知道"变成"变慢了看得出"；单项详情能把"是不是刚抖了一下"讲清楚 | 约 1.5 天 | 快照含 `series`；页面折线随采样变化；Kuma 里手动停一项 → 2 分钟内序列末端变红、详情页给出起始时刻；快照体积 < 40KB |
| **P4** | 传输面板的排队规则 + analyze 卫生 | `transfer_queue.dart`（排序/优先级）、`remote_storage_page.dart`（面板内拖动或"优先"按钮）；全仓 info（218 条里的 `avoid_print` 203 条集中在 `test/`） | ① 队列支持"把这条提到最前"（长队里小文件不必等大文件）；② 顺手清一批机械型 info（未用 import / 可 const / `avoid_print` 换 `debugPrint` 或加 ignore），把 218 压到 180 以下并**用 CI 同款命令**验证 | 长队体验 + 把分析噪声降下来（噪声越多，真警告越容易被忽略） | 约 1 天 | 点"优先"后该任务下一个开跑（用例断言顺序）；`flutter analyze --no-fatal-infos` 计数下降且退出码 0 |

### D 档（体验，可挑）

| # | 项 | 落点 | 收益 | 成本 |
|---|---|---|---|---|
| D1 | 远端存储筛选增强（类型/大小/时间段） | C3 的本地筛选 + D10 的匹配纯函数 | 目录里几百个文件时能用 | 低 |
| D2 | 传输并发可调（1–6） | `kMaxConcurrentTransfers` 变偏好 | 弱网下自己压并发 | 低 |
| D3 | 分享接收支持"分享文本/链接"（存成 .txt 或 .url 到远端） | Manifest 再加 `text/plain` + 原生分支 | 少一步"先存文件再传" | 低 |
| D4 | 监控快照 `generatedAt` 超过 N 分钟时页面顶部变黄（采样链已断但不至于静默） | `monitor_page.dart` | 把"静态文件的陈旧"变成看得见 | 极低 |

### E 档（建议不做，理由写清）

- **E1 上传断点续传（分片）**：WebDAV 无标准部分 PUT（285 已拍板只做能力探测 + 明确报错）；继续不做。
- **E2 相册自动备份**：看着诱人，但要做"扫描相册 → 去重 → 增量 → 后台调度 → 通知/失败重试 → 权限与隐私说明"整条链，本轮排不下，且与"分享接收"重叠度高，先看分享用得顺不顺再决定。
- **E3 监控快照改实时 API / 让 app 直连 Kuma**：要多一套带鉴权的服务端，收益不抵成本（静态快照 + 时间戳已够）。

## 3. 宿主侧（另一条线，不动 box 代码）

| # | 项 | 现状 | 做法 | 优先级 |
|---|---|---|---|---|
| **H1** | **175 磁盘清理**（本轮新增，现实风险最高） | 86%，余 5.6G | 保守清单：`/root/.gradle` 5.0G（留当前版本依赖、清旧版本与 build-cache）、`/root/.npm` 1.0G（`npm cache clean --force`）、`/var/cache` 953M（`apt-get clean`）、`.dartServer` 481M、`.hermes/cache/scratch` 483M（保留最近两轮）、旧符号表只留 283–286、确认 `/root/restore`、`ha-main-175.tar.gz`、`ha-shards` 是否还需要的备份件。目标 <70% 并**加一条每周磁盘阈值提醒** | ★★★ |
| **H2** | 安全巡检 cron | 完全没有 | 每日一次：sshd 失败登录、监听端口变化、证书剩余（快照里已有）、磁盘/内存、待更新的系统包、nginx 配置哈希变化 → 进飞书；异常才报，平时静默 | ★★ |
| **H3** | Kuma 告警入口换成 Hermes 原生 webhook | 现在是 nginx 随机路径 + `hermes send` 裸转发 | Kuma → Hermes webhook 路由（路径/令牌即密钥）→ 触发一次 agent run：先查该项状态与最近心跳、必要时看日志，再把**带上下文**的结论发飞书。切换时先验通新链路再撤旧路径 | ★★ |
| **H4** | GoAccess 流量分析 | 两台都没装 | 边缘机装 + 解析 nginx 日志 + 每日报表进飞书 | ★ |
| **H5** | 文件投放页 | 未开工 | 临时文件上传/取件页（过期 + 口令） | ★ |

## 4. 规模粗估（非承诺）

| 档 | 项数 | 估时 |
|---|---|---|
| P1–P4 | 4 | 约 4 天 |
| D1–D4 | 4 | 约 1.5 天 |
| H1–H5 | 5 | 另算（H1 半小时级，H2/H3 各半天） |

## 5. 待拍板（3 条，各带建议）

1. **范围**：建议本轮做 **P1–P4**（P1 移动网络策略收益最直接，P2 是补上 286 留下的诚实缺口，P3 是监控这条线自然的下一步，P4 顺手降噪）；D 档下轮。
2. **网络策略的默认档**：建议**默认「仅 Wi-Fi」**（远端的文件通常都大），"每次问"作为可选。要更激进（默认都允许、只在超阈值时问）就说。
3. **宿主侧**：建议**先只做 H1（磁盘）**——86% 是当下唯一的真实风险；H2/H3 排在 box 这条线停下之后。若你更想先上安全巡检，说一声我把它提前。

## 7. 执行记录（P1–P4 + H1，全部完成）

| 项 | 提交 | 做了什么 | 验证 |
|---|---|---|---|
| **P1** 移动网络策略 | `f587969` | 原生 `NetworkStatusProvider`（只上报类型、变化主动推）+ 队列网络闸门（三档策略、被拦任务留在队列/不标 running/不挂保活、"仍要传一次"换网络即失效）+ 面板档位菜单与等待横幅 | 新用例 26 个（纯逻辑 13 / 队列状态机 8 / 面板 5）；插件目录 593 条全绿 |
| **P2** 分享诚实计数 | `fb19cc8` | 原生回报 total/received/skipped（超上限的只报名字）；Dart 新增 `ShareInboxBatch`/`SkippedShare`（**新形状与 286 的裸列表都认**）；面板写清"分享 25 个，收到 20 个（5 个超过单次数量上限）"并逐条列出没收到的是谁 | 两种形状/全跳过/计数矛盾/面板文案共 20 条用例 |
| **P3** 监控趋势与详情 | `2917668` | 采样侧环形缓冲（最近 60 次 ≈ 2 小时，`seriesPing` 的 `null` 表示"没采到"而非 0ms）；列表行内自绘迷你折线（零依赖）；点行进详情页（不通时长 / 最近 12 次心跳 / 证书 / 24h 可用率） | 22 条用例；已部署 175 并核对**公网快照**已含序列（4 点、1743B、无 token 仍 404） |
| **P4** 队列优先 + 降噪 | `9ad4523` | `prioritize()` 把排队中的任务提到最前（在跑/暂停/已完成不接受插队）；面板排队行加「优先」；`test/analysis_options.yaml` 只对测试目录关 `avoid_print` | 10 条用例；analyze **218 → 15**；**双向自检**：lib/ 里的 print 仍报、test/ 的不报（探针验过） |
| **H1** 175 磁盘 | 无代码 | `.gradle/caches/8.14/{transforms,kotlin-dsl,fileHashes}`（可重建）、`npm cache clean`、`apt-get clean`、`.dartServer`、`.cache/node-gyp`、scratch 旧轮产物、旧符号表 277–282 | **86% → 71%**（40G 用 34G→28G，清出约 6.4G）；新增 `/usr/local/sbin/disk-guard.sh` + cron `0 9 * * *`，只在跨过 80%/90% 档位时发飞书（自检模式 `--test` 实测发出消息），未动 `/root/restore`、`ha-main-175.tar.gz`、`ha-shards`（备份件，等你确认是否还需要） |

**构建与产物核对（真跑，不看脚本自述）**

- release 构建：`BUILD_EXIT=0`，**27,165,396 字节**，sha256 `a6df6ab3369f9337a70863e624986ad559326369690691af8efa25b2134eaa1d`，符号表归档 `/root/.box-symbols/287`（286 的没被覆盖）。
- 独立核对（`/root/.hermes/cache/scratch/verify287.py`，拿 286 已发布包当基线）：
  - dex 里 9 个原生字符串全中（网络通道名/方法/推送、分享通道与取件、以及 P2 新增的三个跳过原因代号）——注意**类名会被 R8 改名，不能拿类名当"没进包"的证据**；
  - `MainActivity` 子树的 SEND 过滤与 286 完全一致（aapt2 每属性打印两次，期望值是过滤数的两倍）；
  - 17 个新功能标记在 AOT 快照里全部增加（UTF-16LE 精确计数），6 个控制项计数不变。
- 这一步逮到一个**核对脚本自身**的坑：`aapt2` 不在 PATH 上，取不到时脚本静默拿到空输出、进而报"找不到 MainActivity"——所以脚本里补了一条"aapt2 无输出就别下结论"的判断（**工具失败 ≠ 结论成立**）。

**提交链**：`0d62f22`(方案) → `f587969`(P1) → `fb19cc8`(P2) → `2917668`(P3) → `9ad4523`(P4) → `13370b8`(提版 1.20.30+287)。
测试/analyze 口径均在提版前量过：**全量 CI 口径 3273 通过 / 3 跳过 / 0 失败**（286 是 3217，本轮 +56）；插件目录 593 条、监控 50 条全绿；`flutter analyze --no-fatal-infos lib test` = 15 info / 0 warning / 0 error（退出码 0）；悬挂 API 闸门 143 公开方法 / 0 悬挂。

## 6. 一条口径提醒（本轮自查出来的，已在 286 记录里更正）

`flutter analyze | tail` 取到的 `$?` 是 `tail` 的退出码，**不是 analyze 的**；而且仓里 CI 用的命令是
`flutter analyze --no-fatal-infos`（`flutter analyze` 只要有 info 就退出非零）。本轮按正确口径复量时
才发现 286 的 lint 清理里把 map 键写成 `?key`（`invalid_null_aware_operator`，warning，会让 CI 红），
已修（`776d48f`）。**以后报 analyze 必须用 CI 同款命令 + `set -o pipefail`，并分开报 info/warning/error 三个数。**

## 8. 宿主侧 H2 / H3 执行记录

### H2 安全巡检（已上线）

- 脚本 `/usr/local/sbin/security-patrol.py`（cron `30 8 * * *`，日志 `/var/log/security-patrol.log`）。
  检查项：sshd 失败登录（24h）、监听端口变化（本机 + hpa888）、磁盘/内存/swap、
  待安装更新（本机 + hpa888）、证书剩余天数（读采样快照）、边缘机 nginx 配置哈希。
- **只在异常时报，且"同一件事不天天重复"**：每条检查记住上次状态（`/var/lib/security-patrol/state.json`），
  只有"档位变化/明显增长"才发飞书。`--dry-run` **不落状态**（否则试跑一次就把当天告警自己吃掉了），
  `--test` 强制发一条自检。
- 第一次真跑就抓到两件真事：**24 小时内 2553 次 ssh 失败登录**（主要来源 51.89.42.211 一家 2233 次）、
  **本机 52 个待安装更新**。已按设计发出。
- 过程中修掉两个自己的 bug：① 远程检查用 `ssh host bash -lc "a b"` 传参会被拆散 →
  一律改走 `ssh host 'bash -s' < 脚本`；② 见上，dry-run 不该消费状态。

### H3 Kuma 告警入口（已切换到 Hermes 排查）

现状链路：`Kuma → 边缘 nginx（随机路径即密钥，路径不变）→ ssh 隧道 127.0.0.1:3013 → 175 的
kuma 中继 → 起一次 agent 排查（hermes chat -Q -q，带 host-monitoring-and-alerting 技能）→ 结论发飞书`。
中继只监听回环、**一次只跑一个排查**（忙时原样转达，不丢消息、不并发起一堆 agent）、
排查失败就如实说"本次没能起排查"而不是假装成功。

为什么没走"网关内的原生 webhook 路由"：Hermes 的 webhook 路由要求每个 POST 带 HMAC 签名
（Kuma 不会算），而让网关加载 webhook 平台**必须重启网关** —— 从 agent 自己的会话里重启会把
发起命令的自己杀掉（有护栏拦着，这是对的）。kuma-alert 路由已经配好（`hermes webhook list` 可见），
等网关下次重启/重启机器后可直接使用，两条路不冲突。cron 的"监控脚本变化检测"模式也试过：
派发停在 pending（只有 claim 没有执行），所以没采用。

过程中的三件如实说明：
1. `hermes webhook subscribe` **会把密钥打到屏幕上**，我照做了 → 那次的密钥当场轮换作废
   （共轮换两次，第二次是我自己 `print` 原文导致的）。现在密钥只存 `/root/.secrets/kuma-webhook-secret`（600）。
2. 顺带修了一个环境问题：venv 里 `prompt_toolkit` 是残缺安装（缺 `formatted_text/__init__.py`），
   导致 `hermes chat` 直接报 ModuleNotFoundError → 重装为 3.0.53 后正常。
3. 旧的 `kuma-relay.service`（hpa888:3011，直接 `hermes send` 裸转发）已 **stop + disable**，
   单元文件与配置备份都留着，回滚只需 `systemctl enable --now kuma-relay`。

验证：向公网随机路径 POST 真实形状的 Kuma 告警 → HTTP 200、边缘访问日志有记录、
告警落盘 `/var/lib/kuma-alert/last.json`、中继起排查并投递飞书（自检消息若干条，
都是这次联调发出来的）。
