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

## 10. 执行记录（284 拍板结果与落地）

拍板：**1. 全做 / 2. 先做（倍速照做、不承诺保音调） / 3. 做（脚本入库 + 接 CI）**。
落地情况（每项一个提交，逐项验证过）：

| 项 | 提交 | 实施上的偏差与要点 |
|---|---|---|
| P1 | `0be3e62` | **不需要索引**：`SharedPreferences.getKeys()` 能列出所有键，按前缀过滤即可——比索引更对，因为索引漏掉"本次改动之前写下的历史键"，而那正是要清的。播放进度的前缀抽成 `playbackProgressKeyPrefix()`（单一事实来源，避免改了键格式后清理静默失效）。缩略图磁盘文件名是键的 sha1（反推不出账户）→ **作用域落到目录上**：`<sha1(账户)>/<sha1(键)>.bin`，`usage()`/`prune()` 同步改成递归扫描（否则加了子目录后 32MB 上限会失效），另给 `clearScope()`。边界：`clearScope` 只数磁盘文件，内存条目顺带清掉 |
| P2 | `2b48fa5` | 对话框只加两个回调，**导出流程留在浏览器页**（写临时文件 + SAF + SharePlus 都是它已有的），避免两套提示文案/大小判断。预览字节已在内存（≤20MB），不再下载第二次 |
| P3 | `0206025` | 新增 `ExifThumbnailStats`（纯类型，进 domain）；命中/未命中各按条目去重，**只统计本次运行**（跨会话靠缓存、不重复探测），界面文案写明了这一点；没探测过不显示该行 |
| P4 | `ca729fa` | 档位与文案进 domain（`kPlaybackSpeeds`/`formatPlaybackSpeed`）；`ChewieController` **没有** `setPlaybackSpeed`（只有 `VideoPlayerController` 有）；菜单拆成公开组件 `PlaybackSpeedMenu` 才可单测（播放页要真视频控制器，单测起不来） |
| P5 | `a3ac6ea` | `retryAllFailed()` 复用既有 `retry()`（token 复位等易漏细节都在里面）；先收集再改列表（`retry` 会 notify + `_pump`）。失败原因点开是 `SelectableText` + 「复制」 |
| 拍板 3 | `955f8b0` | `tool/scan_dangling_apis.py` 入库并接进 CI `guardrails` job（当前插件 88 个公开方法、0 个悬挂） |

**本轮新增的三条测试/工具基建教训**（每条都是真踩到的）：

1. **AppLogger 的 250ms 合并落盘定时器会让 widget 测试判"Timer is still pending"**：
   队列失败会记一条日志 → 测试结束前定时器还挂着 → 断言失败。修法：测试末尾
   `await tester.pump(const Duration(milliseconds: 300))` 把它跑掉。
2. **用可重试的错误类型造"失败任务"，会留下退避定时器**（同一个坑的另一种形态）：
   widget 测试里用**不重试**的错误（凭证/权限/冲突类）造失败态，队列就不会排定时器。
3. **写"闸门"脚本必须自检它能红**：
   - 第一版把方法**定义行**也算成调用 → 任何方法都至少 1 次调用 → 闸门永远绿（静默失效的
     闸门比没有闸门更糟）；
   - 第二版 `--dir` 只改扫描范围、调用点只搜 `lib/`+`test/` → 指向别处时明明有调用也判悬挂。
   两处都是靠"故意造一个该红的用例"发现的。已用 `probe` 目录验过：该红时 exit 1、补上调用点后 exit 0。
## 11. D6 / D7 执行记录（284 拍板「按你的方案执行」后落地）

| 项 | 提交 | 实施要点与偏差 |
|---|---|---|
| D6 递归下载文件夹 | `e9b5acd` | 纯路径数学进 domain（`recursiveDownloadTarget` + `sanitizeLocalSubPath`，逐段清洗，`..`/空段不会把文件写到下载目录之外）；service 加 `listRecursive`（跳系统目录、单目录失败**跳过并计数**、文件 300 / 目录 200 上限 → `truncated`）；`download(subDir:)` + `isAlreadyDownloaded`（同名同大小 → 跳过，续跑不重下也不生成 `xx (1).jpg`）；确认框摆出规模/截断/无权限数；只选文件夹时按钮不再禁用 |
| D7 目录快照先显示 | `e9b5acd` | 快照 = 每账户每目录一条（JSON，>200 条不存、最多 30 目录按时间淘汰、坏数据当没有）；`list()` 成功后顺手存（失败不影响列表）；页面先把上次内容显示出来 + `显示的是上次的内容（N 分钟前）· 正在刷新` 横幅；刷新失败保留旧内容并在横幅写明原因（不整页报错）；删账户一并清快照 |

D6 与 D7 落在**同一个提交**：两者改的是同一批文件（models/service/page + 4 个测试），
在文件里又相邻 → 同一个 hunk，强行按 hunk 拆出来的中间态无法编译验证（试过，回退）。
下次要"每项一个提交"，就在写的时候把两块代码放到相隔 ≥3 行的地方，或分开文件。

**D6/D7 期间新增的教训**：

1. **`patch` 的 `old_string` 必须是读过的原文**：凭记忆写
   `await _store.clearBrowserScrollOffsets(account.id);`，模糊匹配命中了旁边长得很像的
   `final offsets = await _store.clearBrowserScrollOffsetsForAccount(id);` 并把它改写掉
   → 编译报 `account` 未定义才发现。改代码前先 `grep`/`read_file` 拿到精确原文。
2. **测试里匹配假服务器路径要用 `uri.pathSegments`**（已解码），`uri.path` 是百分号编码的
   ——中文目录名拿原始 path 比永远匹配不上（这次先在测试里踩了）。
3. **在别的语言里生成 Dart 字符串时 `\$` 是转义**：写进 `.dart` 后 `'\${x}'` 等于字面量
   `${x}`，断言里就成了未插值的文本，Dart 侧不会报错、只是永远比对不上。
4. **用不重试的错误类型造失败态**（见 §10 教训 2）在 D7 里又验证了一次：
   让 `list` 抛 `RemoteStorageException(RemoteStorageError.http, ...)` 才能稳定拿到
   "刷新失败"分支，且不留定时器。
5. **已知 flake**：`上传 并发同名上传：第二个视为已存在，不静默覆盖（C7）` 在**全量并发**下
   偶发失败（复跑即过，单跑 3/3 稳定），与 D6/D7 无关；出现时先单跑确认，别追。
