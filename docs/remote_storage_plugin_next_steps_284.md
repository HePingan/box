# Remote Storage 插件 · 下一步打磨方案（284 轮）

> 本轮定位：**打磨（polish）**，不动架构、不加新依赖。目标是修掉 283 上线后暴露的
> "用得着但差一点"的地方，并把上一轮遗留的**未知项**变成可见数字。
> 所有"现状"都在本仓库实测过并给出`文件:行号`，不是记忆。

## 1. 结论先行

- **建议本轮范围**：P1–P5（五项打磨，合计约一天），D6/D7 顺延，D8–D10 仍单独立项。
- 其中 **P1（删账户清理本地残留）** 和 **P3（EXIF 命中数可见）** 是我最建议先做的两项：
  前者是真残留（会永久留在用户手机上），后者能把 283 唯一说不清的未知项直接变成面板上的数字。
- **不建议**本轮动：`kThumbnailMaxBytes`、目录快照、递归下载（理由见 §6）。

## 2. 事实基线核对（本轮实测，含与既有文档的偏差）

| # | 事实 | 证据（`文件:行号`） |
|---|---|---|
| 1 | 283 已上线为 **1.20.26+283**（release id=125），283 文档 §8 的"待拍板 3 条"已全部落地，文档已改写成执行记录 | 线上 `version.json latestVersionCode=283`；`docs/remote_storage_plugin_next_steps_283.md` §7/§8 |
| 2 | 283 §5 的两条未验证项**仍未验证**：EXIF 内嵌缩略图命中率、Flutter 是否应用 EXIF Orientation | 真机才可判；本轮 P3 让命中率变可见 |
| 3 | 插件内"悬挂 API"已清零：脚本扫全部 70 个公开方法，**0 引用 = 0 个**（283 前 `clearThumbnailCache` 曾是零调用） | 扫描脚本（recon 用，未入库）|
| 4 | **新缺口**：`deleteAccount()` 只清账户表/客户端/目录缓存，**不清**该账户的播放进度与滚动位置 | `application/remote_storage_service.dart:308-314`；`data/playback_progress_store.dart:16-47`（一条进度 = 一个 prefs 键）；`data/remote_storage_store.dart:117-118`（滚动位置按 `accountId|path` 存）|
| 5 | **新缺口**：播放器**没有倍速**（全仓无 `playbackSpeed` 调用）；`video_player ^2.11.1` 自带 `setPlaybackSpeed`，可零新依赖实现 | `presentation/remote_storage_player_page.dart`（无倍速相关代码）；`pubspec.yaml:44` |
| 6 | **新缺口**：图片预览对话框只有"关闭"，没有分享/保存；而下载完成对话框已有成熟的一套 | `presentation/image_preview_dialog.dart:158`、`:181`；对照 `presentation/remote_storage_browser_page.dart:1030-1050`（保存到…/分享/打开，`share_plus` 已在用）|
| 7 | **粗糙点**：列表行在 `initState` 就取缩略图（预建的行也发请求），取图队列是 FIFO + 3 并发、**没有取消/丢弃** | `presentation/remote_thumbnail.dart:44-48`；`application/thumbnail_loader.dart:80-100` |
| 8 | **既定项仍未做**：多选下载拒绝文件夹；目录缓存 `list()` 是纯内存 TTL 15s / 64 条，冷启动必空等 | `presentation/remote_storage_browser_page.dart:451-453`；`application/remote_storage_service.dart:378-390`、`:1072-1075` |
| 9 | 与 283 文档的**偏差**：283 把 D6/D7 列为"下轮"，本轮实际是打磨轮 → D6/D7 继续顺延（§4），不算"欠账"，但仍记录在册 | 283 文档 §6/§8 |

> 说明：第 3 条那个扫描脚本是本轮临时写的（扫"公开方法是否有插件外调用点"），
> 如果决定保留，可以入库成 `tool/scan_dangling_apis.py`——它能复现 283 前
> `clearThumbnailCache` 那类"写了没用"的问题。这一点列在 §9 待拍板。

## 3. 打磨项（P 组，建议本轮全做）

### P1 删账户时清理该账户的本地残留

- **现状**：`deleteAccount`（service:308-314）清了账户表、客户端、`_dirCache`，但
  播放进度（`playback_progress_store.dart`：每条 `accountId+path` 一个 prefs 键）、
  滚动位置（`remote_storage_store.dart:117-118` 的 map 内 `accountId|path` 条目）、
  磁盘缩略图（键含 `account.id`）都留下。
- **做法**：`deleteAccount` 里补三件事——① 清该账户的全部播放进度（**需要索引**：
  现在没有"该账户有哪些 path"的索引，加一个 `remoteStorage.playbackIndex`（JSON 数组，
  cap 500）随写随更新）；② 从滚动位置 map 里删掉 `accountId|` 前缀的条目；
  ③ 让 `RemoteThumbnailCache` 支持按前缀清理（文件名的键就是 `accountId|path`，
  删匹配前缀的文件即可，不必动 32MB/400 张的淘汰逻辑）。
- **收益**：删账户 = 真的删干净。不做的后果是"删了账户，手机上还留着它看过哪些视频
  看到第几秒"——既是残留也近似隐私问题。
- **成本**：中（新增一个索引键 + 两处前缀清理 + 用例）；不引依赖。
- **验收**：新增用例——建账户→跑播放进度/滚动位置/缩略图→删账户→断言三类残留全空；
  且"另一个账户的数据不被误删"（前缀隔离用例）。

### P2 预览页直接「分享 / 保存到…」

- **现状**：预览对话框只有"关闭"（`image_preview_dialog.dart:158/:181`）；要分享得先
  下载、再从"下载完成"对话框分享（`browser_page.dart:1030-1050`）。
- **做法**：预览已经把整张图取回并解码（≤20MB，`kPreviewImageMaxBytes`），
  在对话框底部加"保存到…/分享"：字节写进临时文件后复用**既有两条路径**——
  `exportStrategyFor(size)` 判断 SAF 还是分享（`browser_page.dart:1038` 的分支逻辑），
  超大图沿用现有"改用分享→保存到文件/相册"的提示文案。
- **收益**：相册场景最常用的动作（看→存/发给别人）少两次跳转；不增加任何下载。
- **成本**：小到中（对话框加按钮 + 临时文件写出 + 两条既有路径的复用 + 用例）。
- **验收**：widget 用例——预览页存在"分享/保存到…"、点击后走到对应路径；
  超大图给出既有提示；含中文文件名不炸（`kMaxRemoteSegmentBytes` 相关）。

### P3 「缩略图缓存」面板显示 EXIF 命中数

- **现状**：283 D1 的 EXIF 内嵌缩略图走的是**独立缓存键** `'$key|exif'`
  （`service.dart:958-960`），但我无法从手机上知道它到底命中了几张——
  这是 283 §5 唯一悬着的未知项。
- **做法**：`ThumbnailLoader`/`RemoteThumbnailCache` 记两个计数（整取命中 / EXIF 命中，
  内存计数即可，跨会话用持久化会引入"数字不准"的麻烦），在 D3 已建的
  「缩略图缓存」面板里加一行：`其中 N 张来自 EXIF 内嵌缩略图（M 次探测未命中）`。
- **收益**：把"命中率到底如何"变成用户和我都能一眼看到的数字——如果 N 很小，
  就说明"提高 `kThumbnailMaxBytes`"这条退路值得重新讨论（否则免谈）。
- **成本**：小（计数 + 面板一行 + 用例）。
- **验收**：用例——走 EXIF 路径一次后计数 +1；走整取路径不计入 EXIF 计数；
  面板文案在 0 次时不显示该行（不制造噪音）。

### P4 播放器倍速 + 记住选择

- **现状**：没有倍速（全仓无 `playbackSpeed`）。
- **做法**：播放页顶栏加倍速入口（0.5 / 0.75 / 1.0 / 1.25 / 1.5 / 2.0），
  调 `VideoPlayerController.setPlaybackSpeed`；选择记住（复用现有 prefs 通道，
  和缩略图开关同一种做法）；**不**做"每文件独立倍速"，全局一个值即可。
- **收益**：长视频（课程/会议录像）最常见的诉求；零新依赖。
- **成本**：小（一个菜单 + 一次 setPlaybackSpeed + 一个偏好键 + 用例）。
- **验收**：用例——选 1.5 后 controller 的 speed 为 1.5、偏好落盘、重进页面恢复；
  音频音调不保证（`video_player` 不改音调），文案上不承诺。

### P5 队列「全部重试」+ 失败原因可复制

- **现状**：283 D4 做了单条「重试」（`transfer_queue.dart` 的 `retry`），
  失败原因只显示在行里，长文案看不全也没法复制。
- **做法**：队列面板加"全部重试"（对所有 `failed` 任务逐个 `retry`，与单条共用同一实现）；
  失败行点击弹一个只读对话框，展示完整错误并可"复制"（`Clipboard.setData`）。
- **收益**：弱网下多条同时失败时不用一条条点；求助/反馈时能贴出完整报错。
- **成本**：小。
- **验收**：用例——3 条失败 → 全部重试 → 3 条都回到 queued 且各自 runner 被调用；
  成功/进行中任务不被"全部重试"碰（守住 D4 的既有语义）。

## 4. 顺延的既定项（不欠账，但记在册）

- **D6 递归下载文件夹**：现状 `browser_page.dart:451-453` 明确拒绝"选中的都是文件夹"。
  设计要点沿用原方案：递归收集 → 保持相对路径 → 冲突策略复用 → **失败清单可续跑**
  （一个目录 300 个文件必然有失败项，不能只吐一个"部分失败"）。收益大、成本中大，
  建议 285 轮做。
- **D7 目录快照**：`list()` 纯内存 TTL 15s（`service.dart:378-390`、`:1072-1075`）。
  要点：冷启动先显示上次列表（带"可能不是最新"标识）再后台刷新；必须有过期标识，
  否则用户会以为看到了最新状态。建议排在 D6 之后。

## 5. 单独立项（本轮不做）

- **D8 视频缩略图**：需要抽帧（新依赖或先播放），成本高；`video_player` 不能直接取帧。
- **D9 上传整个文件夹**：要保持目录结构 + 冲突策略 + 中断续跑，复杂度接近一个子系统。
- **D10 跨目录搜索**：WebDAV 没有服务端搜索，只能遍历——坚果云遍历慢，体验会"假死"。

## 6. 明确不做（避免下一轮再讨论一遍）

S3/对象存储支持、投屏/DLNA、网盘解析提速、上传分块与断点续传（B4）、Unicode 改写
（O6 的结论仍成立）、全仓 `dart format`（CI 只门禁 analyze + tests）、
嵌套压缩包预览、把 `kThumbnailMaxBytes` 从 3MB 提到 5MB（P3 给出数字后再议）。

## 7. 验证计划

1. 每项**单独提交 + 单独用例**（沿用 283 的节奏）；P1 涉及删除语义，用例必须包含
   "另一个账户不受影响"。
2. 交付前跑**全仓 CI 口径**：`flutter analyze`（0 error / 0 warning，infos 允许基线）
   + `flutter test --exclude-tags live`；P4/P5 涉及 UI，**别用 `pumpEventQueue()`**
   （在 `testWidgets` 的 fake-async 里永不推进，283 踩过），用 `tester.pump(duration)`。
3. 涉及 UI 文字的项，盯一下仓库自带的 `test/lint/mounted_guard_after_await_test.dart`：
   它在全量里才会跑到，且**连注释一起扫**（283 踩过，`unawaited(` 里的子串会假阳性）。
4. 发版若做，沿用五路独立复核（公网字节比对 / 19 字段 HMAC 重算 / 仓库验签工具 /
   `version_code` 提示行为 / 服务端记录）+ AOT UTF-16LE 入包证据。

## 8. 规模粗估

| 项 | 落点 | 预估 |
|---|---|---|
| P1 | service / store / playback_progress_store / thumbnail cache | ~120 行 + 5 用例 |
| P2 | image_preview_dialog / browser_page 复用 | ~60 行 + 4 用例 |
| P3 | thumbnail_loader / cache / browser_page 面板 | ~50 行 + 3 用例 |
| P4 | player_page / store / models | ~70 行 + 4 用例 |
| P5 | page.dart（队列面板）/ transfer_queue | ~50 行 + 4 用例 |

合计约 350 行改动、约 20 个用例；**不动 domain 层的纯判定/纯键函数约定**
（283 的既有约定：domain 零 `dart:io`）。

## 9. 待拍板（3 条，各带建议）

1. **范围**：建议 P1–P5 全做（一天量级），D6/D7 放到 285。
   若只想做两件：**P1 + P3**（一个修真残留、一个把未知变已知）。
2. **P4 倍速的音调**：`video_player` 变速会连音调一起变（不保音调）。
   建议先做、在文案上不承诺保音调；若你觉得"听课变速音调变了很难受"，
   那就先不做（换 `media_kit` 是另一个量级的事）。
3. **P3 的计数是否入库扫描脚本**：本轮为了核对"悬挂 API 清零"临时写了扫描脚本。
   建议入库成 `tool/scan_dangling_apis.py` 并接进 CI（能防 283 前那种"写了没用"重现）；
   若嫌 CI 变重，就只留脚本不接 CI。
