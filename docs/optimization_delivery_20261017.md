# Box 优化交付记录（2026-10-17）

> 口径：本轮不改玩法、不加功能，只收「用户看得见或迟早撞上」的确定性问题。
> 每条都先量过现场（文件:行号 / 实测输出），再改；改完跑 analyze + 全量测试。

## 一、本轮做了什么

### 1. AI 生图下载残留：每下载一张，文档目录里永久多一份

- **现场**：`image_generator_download.part.dart` 有 6 处把原图写进
  `应用文档目录/box_downloads/ai_img_*.png`，随后交给「保存到相册 / 分享」。
  `Gal.putImage` 只把文件**复制**进相册（MediaStore），源文件留在应用私有目录，
  **全仓没有任何删除点**。
- **后果**：用户看不见、设置里的「清理缓存」也清不到（那是文档目录，不是缓存），
  只有卸载应用才消失。两张截屏兜底还直接写在系统临时目录**根**下。
- **改法**：新增 `lib/features/image_generator/data/ai_image_download_store.dart`，
  把落盘统一到 `create()`；保存到相册 / 分享成功后 `deleteQuietly()` + `prune()`；
  截屏兜底也改落同一目录（`ai_original_` 前缀）；上限 40 个文件 / 80MB，
  超了按 mtime 删到 60%（兜住「进程被杀」「删失败」的残骸）。

### 2. 「清理缓存」终于覆盖这类残留

- `PersonalCenterCacheService` 增加 `clearAiImageDownloads`（默认调 `clear()`），
  字节数与漫画图片合并上报。
- 设置页确认文案补上「AI 生图下载的中间文件」。
- **注意（有意行为）**：`prune()` 是「超限才收」，`clear()` 是「用户主动全清」——
  清理入口用后者，否则按了没反应。

### 3. 音乐入口：从「阶段1验证」的试验页收成能用的页

- `_urlController` 从未 `dispose()`（监听链泄漏）；
- 裸 `Dio()` **零超时**：站点挂住时用户永远停在「下载中…」，只能杀进程；
- 下载的音频落在临时目录**根**下，离开页面不删 —— 每播一首留一份，几 MB～几十 MB。
- 改法：`dispose()` 里销毁控制器并删临时文件；`Dio` 加 10s 连接 / 30s 接收超时；
  标题从「音乐（阶段1验证）」改为「音乐」。

### 4. 漫画导入把整本 CBZ 解压了两遍

- `comic_importer_widget.dart:43-44` 调 `extractPages()` + `extractCover()`，
  而这两个方法各自 `extract()` 一次 —— 注释写着「解压只做一次」，代码是两次。
  第一份产物（整个临时目录里的全部页图）**直接成了垃圾**。
- 改法：改成单次 `ComicImporter.extract()`，页面与封面取自同一个结果。
- **已知局限（已写进代码注释）**：解压目录落在系统临时目录，而路径被记进
  `ComicBook.pages` 长期使用 —— 系统清临时目录后书会白。根治要迁到文档目录，
  会牵动备份/离线链路，留作单独一版。

### 5. 题库导出 JSON 残留

- `quiz_bank_view_page.dart` 导出后把 JSON 写在临时目录根下，分享完不删
  （题库 JSON 可以几十 MB）。改为分享后删除，删失败不影响「已导出」。

## 二、验证

| 项 | 结果 |
|---|---|
| `flutter analyze --no-pub` | **10 issues，全是 info**（本轮前也是 10 条，零新增；其中 6 条在 `tool/`、4 条在既有测试） |
| 全量测试 `--exclude-tags live` | **4537 通过 / 3 跳过 / 0 失败**（基线 4527/3，+10 为新增用例） |
| 新增用例 | `test/features/image_generator/ai_image_download_store_test.dart`（9 条：create/删除/全清/按 mtime 淘汰最旧/字节超限） |
| 改动用例 | `test/account/personal_center_cache_service_test.dart`（+1 条合并上报）、`test/ui/drawer_check_update_and_clear_cache_test.dart`（注入新依赖 + 文案对齐） |

## 三、下一轮建议（按性价比排序，都没动）

1. **漫画导入目录迁到文档目录**（承接第 4 条）—— 当前是「系统清临时目录，导入的书变白页」
   的真实隐患；牵动 `ComicBook.pages` 与备份，值得单独一版。
2. **漫画区的那 6 个 3000 行级文件拆分** —— `comic_online_page.dart`（3223 行）、
   `local_tool_panels.dart`（3772 行）、`api_hub_page.dart`（2904 行）。不是 bug，
   但改一处要读三千行的成本会一直涨。
3. **音乐阶段 2/3**（`docs/music_area_entry_plan.md`）：接入 `HomePluginArea.music` 分区；
   本地扫描属新领域（MediaStore 权限），建议独立一版。
4. **图片工具第一批**（压缩/格式转换/九宫格/拼接）—— 待办清单里唯二的真欠债之一，
   需新增依赖，注意构建环境网络受限时的成本。
