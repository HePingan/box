# 起播优化：不再为坏线路干等（2026-10-03）

上一版（`ff78516`）解决的是「地址是网页 → 播不了」，这一版解决的是**等**。

## 实测（走 App 同一条解析链，真网络，2026-10-03）

| 线路 | 解析(resolve) | 探测(probe) | 合计 |
|---|---|---|---|
| `play.xluuss.com/play/…` | 1391ms | 503ms | 1895ms |
| `hd.kuktxu.com/play/…` | 134ms | 12ms | 146ms |
| `v.lzcdn28.com/share/…` | 436ms | 10ms | 447ms |
| `cdn.ryplay11.com/share/…` | 650ms | 157ms | 807ms |
| 直连 m3u8（bfikuncdn） | 0ms | 571ms | 571ms |
| **不可达线路** | 0ms | **12001ms** | **12001ms** |

结论：**典型不慢（146ms ~ 1.9s），痛在坏线路要一直等到封顶**。而旧代码的封顶是
「云播页整段 12s + 直连解析 8s + HLS 预探测 6s」串行 —— 一条坏线路能让用户干等十几秒，
再叠上换线重试就更久。

## 改了什么

### ① 超时口径收紧 + 统一到一处
- 单次探测 `CloudPlayUrlResolver.probeTimeout`：5s → **4s**（实测正常探测 10ms ~ 570ms，
  4s 已是 7 倍余量）。
- 新增 `PlayerStartupResolver`：云播页整段 **6s**、直连解析 **5s**；播放容器只留 12s 兜底。
- HLS 预探测 `probeHls` 超时：6s → **4s**。

### ② 解析结果缓存（5 分钟）+ 详情页预热
新增 `StreamResolveCache`（纯逻辑、可单测）与 `PlayerStartupResolver`：
- **同一 key 的并发调用合并成一次**（详情页预热与播放器起播同时发生也只解析一次）；
- **只缓存成功**，失败立刻可重试；TTL 5 分钟（源站地址常带 `sign=` 短时令牌）；
- 缓存键 = 地址 + **Referer**（有些源按 Referer 签名，不能互相污染）；
- 详情页 `selectEpisode` / `selectLine` 时预热当前集 —— 用户点完集数到播放器起来那一小段，
  地址已经解析好了。

### ③ 预取下一集
播放开始后（`_prewarmNextEpisode`）顺手解析下一集的地址写进缓存，切集与
「播完自动续播」都直接命中 —— 不再等一次解析。

### ⑤ 起播可见化（不再只有黑屏转圈）
- 每次起播在日志里留一行：`起播完成：解析 XXXms（缓存命中）+ 初始化 XXXms，换线 N 次`；
- 起播 ≥ 3s 或发生换线时，**在页面上说一句**（SnackBar）：换线说原因，
  慢起播说耗时；
- 调试浮层（`showDebugInfo`）多了「解析/总耗时/换线次数」两行。
- 失败地址的缓存会被作废（`invalidate`），免得换回来又拿到同一个坏地址。

## 测试

- `test/video/stream_resolve_cache_test.dart`：命中/过期（注入时钟）/并发合并/
  force/invalidate/peek 不计命中。
- `test/video/player_startup_resolver_test.dart`：两段链 + 缓存命中不联网/
  网页判死抛异常/预热与「已热不重复请求」/Referer 分桶/invalidate/预热失败不抛错。
- 反向测试思路：把「缓存命中」开关关掉（force=true）消息数不变；把 TTL 调到 0 则每次都联网
  —— 用例里就是这两个方向。

## ④ 亮度 / 音量垂直手势

- **左半屏上下拖 = 亮度，右半屏上下拖 = 音量**（与主流播放器一致，右手持机时拇指在右半屏）；
- 拖动时显示浮层（图标 + 百分比 + 进度条），松手 800ms 后自动消失；
- 起手值先向原生问一次当前值（亮度跟随系统时读回 -1 → 用中间值起手），不会一按就跳变；
- **亮度只改当前窗口**（`WindowManager.LayoutParams.screenBrightness`）：不动系统设置、
  不需要 `WRITE_SETTINGS`；离开播放器时**交还系统**（否则整个 App 会留在播放器调过的亮度上）；
- 音量走 `AudioManager` 的媒体流，`MODIFY_AUDIO_SETTINGS`（普通权限，装上就有）；
- 原生的通道是 `top.hpa888.box/player_gesture`（`PlayerGestureChannel.kt`），
  拿不到能力（桌面 / 测试环境 / 个别 ROM）时一律静默降级：不显示浮层、不接管手势，
  页面该滚动还能滚动 —— 手势是锦上添花，绝不能因此让播放崩掉。

手感口径：拖 0.8 屏 ≈ 走满 100%（`PlayerGestureMath.travelRatio = 0.8`）。

水平拖 seek、长按倍速、锁屏（`_isLocked`）行为都不变；锁定时三种手势一起禁用。
