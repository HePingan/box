# 视频播放器：云播页线路的三处修复

**一轮的起因**：用户问「看一下视频播放器有什么问题吗」。查下来播放器内核没问题，
坏的是**喂给它的地址** —— 采集站里约三分之一的线路给的不是媒体流，而是云播/解析网页。

## 实测（2026-10-02，走 App 同一条链路：本机 → `proxy.shuabu.eu.org` → 采集站）

「庆余年」在目录 28 个源上的 31 条播放线路：

| 项 | 数 |
|---|---|
| 真能播（`#EXTM3U` + 分片 `206 video/mp2t`） | 20 / 31 |
| 播不了 | 11（9 条返回 HTML 网页、1 条 404、1 条主机连不上） |
| 默认选中第一条线路就是坏的影片 | 10 / 21 |

## 三处修改

### 1. 云播页地址在解析阶段就被换成真流（`lib/video/utils/play_url_policy.dart` + `lib/video/services/cloud_play_url_resolver.dart`）

两条确定性规则，实测命中率：

- `/play/<id>` → 补 `/index.m3u8`：**6/6 命中**（拿到真 HLS + AES-128）；
- `/share/<id>` → 拉页面取 `var main = "/path/index.m3u8?sign=…"`：**2/2 命中**
  （这类补 `/index.m3u8` 是 404，只有这条路）。

判定不了就**原样返回**，宁可让播放器照旧报错，也不猜一个地址。
接入点：`VideoPlayContainer` 解析链最前面；解析完若仍是网页 → 抛
`_UnresolvedPageUrlException`，文案「该线路是网页线路」，不再让 ExoPlayer 去啃 HTML。

### 2. 「失败自动换线路」原来根本不会触发（`lib/video/widgets/player/line_failover_policy.dart`）

原实现：`_consecutiveFailures >= 2` 才换线，但同一分支的 `_failFast()` 会把计数器清零、
`_initPlayer()` 每次重试也清零一次 —— 计数器永远到不了 2，这条 B2 功能是死代码。
现在把计数抽成 `LineFailoverPolicy`：跨重试保留、**只有真正起播成功才清零**；
网页线路这种「重试也没意义」的失败（`decisive`）一次就换。

### 3. 源健康检测的 play 阶段原来永远报「可用」（`lib/video/services/source_health_service.dart`）

旧规则：只要能拼出「格式合法的绝对地址」就判可用 → 播不了的源永远显示健康。
现在分三档：拿到媒体 → 可用；没拿到响应（超时/被拒/DNS）→ 仍判可用（保留原判断：
媒体常带非标端口/refer/geo 校验，裸探测会被拒而 ExoPlayer 能播）；
**服务器答了但不是媒体（HTML 页、404）→ 播放阶段失败**，如实记。

### 附带（同一条链路上的两个小口子）

- 详情页默认线路优先选「给的是真媒体地址」的那条（`detail_play_parser.dart`）：
  原先默认选中第一条，实测 21 部里 10 部第一条就是网页线路。
- 下载入口拒绝云播页地址（`video_download_controller.dart`）：原先会把网页存成
  「视频」文件。

## 判据（新增/加严的用例）

| 文件 | 钉住什么 |
|---|---|
| `test/video/play_url_policy_test.dart` | 形态判定、`/play/<id>` 候选、分享页 `var main` 提取（用实测页面原文，含 `\/` 转义）、探测判定三档 |
| `test/video/cloud_play_url_resolver_test.dart` | 注入假探测：两条规则各自命中、都命中不了必须原样返回、已是媒体则零请求、探测抛异常不带崩播放路径 |
| `test/video/cloud_play_url_live_test.dart` | **真连**：4 条实测播不了的云播页，只要主机有响应就必须解析成真流；主机彻底答不了才跳过（源站改名不误报，答了 HTML 却解析不出来必红） |
| `test/video/line_failover_policy_test.dart` | 计数器跨重试保留、起播成功才清零、无线路可换时不残留 |
| `test/video/video_play_parser_test.dart` | 默认线路优先真媒体；全是网页线路时退回第一条 |
| `test/video/video_download_controller_test.dart` | 云播页地址不许进下载队列 |

## 验证记录

| 项 | 结果 |
|---|---|
| `flutter analyze --no-fatal-infos` | 28 issues = 本轮基线（0 error / 0 warning） |
| `flutter test --exclude-tags live` | **4223 passed / 0 failed** |
| `flutter test --tags live test/video/cloud_play_url_live_test.dart` | **通过**：解析成功 4 / 可达但失败 0 |
| 同一批 31 条线路用生产代码真跑（临时量尺，跑完删除） | 改前 20 → **改后 27**（+7；8 条网页线路被换成真流，另 1 条原本可播的线路本次探测未通，属源站抖动） |

## 明确没做（留待用户点档）

- **B/C 档**：搜索前过滤坏源、播放层失败的源自动隐藏（C 档）；本轮只做 A 档。
- 仍解析不出来的少数线路：`/share/<id>` 里没有 `var main` 的（如 U酷 404、
  非凡 `vip.ffzy-online2.com`）与媒体域名彻底连不上的（艾旦 `hd.ijycnd.com`）。
  这些现在会被如实判为「网页线路」并自动换线路，不再是一句「播放失败」。
- 目录里 5 个源自身就是坏的（豆瓣/茅台 `code:1002` 禁关键词搜索、卧龙/旺旺接口返回网页、
  无尽被 Cloudflare 403），属于源目录治理，不在本轮。
