# 视频源可用性与线路记忆（①②）

两件事放在一起，因为它们是同一个现象的两端：**目录里有一批源/线路其实取不到东西，
但界面上看不出任何预兆** —— 用户只能靠"卡一下""被自动换线"感觉到。

## ① 坏源过滤：把「源可见性」层接上聚合搜索

### 实测（2026-10-03，28 个源，走 App 同一条代理，关键词「战狼」）

| 源 | 上游接口 | 症状 | 判档 |
|---|---|---|---|
| 豆瓣资源 dbzy.tv | caiji.dbzy5.com | `{"code":1002,"msg":"Current API forbids keyword search"}` | keywordForbidden |
| 茅台资源 mtzy.me | caiji.maotaizy.cc | 同上 code=1002 | keywordForbidden |
| 卧龙资源 wolongzyw.com | wolongzyw.com | 返回 HTML 网页（已不是 VOD 接口） | notAnApi |
| 旺旺资源 api.wwzy.tv | api.wwzy.tv | 本机不可达；代理拿回的是别的站点页面 | notAnApi |
| 无尽资源 wujinzy.me | api.wujinapi.me | 403（WAF 拒机房 IP） | blocked |
| 速播资源 www.subozy.com | subocaiji.com | 522 / 502（源站宕机） | unreachable |
| 百度云 zy bdzy1.com | pz.v88.qzz.io 转发 | 404（转发路径已下线） | notAnApi |
| 艾旦影视 lovedan.net | pz.v88.qzz.io 转发 | 404 | notAnApi |

**8/28 ≈ 29% 的源在「关键词搜索」这一档就不可用。**
其中 code=1002 那两类还会被解析成"成功但 0 结果"——界面上完全看不见，
只能从总耗时感觉到（每个接口坏的源都要陪跑一次 fastFail 预算）。

### 关键发现：这条路**铺了一半没接线**

`SourceVisibilityRecord` / `SourceVisibilityRepository` 以及 `VideoModule` 上的
`isSourceVisible` / `visibleSourcesOf` / `markSourceSuccess` / `markSourceFailure` /
`setSourceAutoHidden` 全都有定义、也都有用例，但 **`lib/` 下零调用** ——
聚合搜索只看模型上的 `isAvailable`，所以"自动隐藏坏源"永远不会发生。

> 教训：**「有定义 + 有用例」不等于「在跑」**。动这类功能前先
> `grep -rn "markSourceFailure\|isSourceVisible" lib/ | grep -v 定义文件`，
> 调用点为空就是假功能，要做的不是新写而是接线。

### 实现

- `lib/video/services/source_capability.dart`
  - `classifySearchResponse()`：**纯函数**，把一次真实响应判成 6 档能力
    （searchable / keywordForbidden / notAnApi / blocked / unreachable / unknown）。
    判据顺序 = 状态码 → 正文形态（`<` 开头即网页）→ `code` 字段。
  - `SourceSearchCapabilityProbe`：并发 4、单源 8s，异常一律记 `unknown`，**永不抛出**。
  - `isStructurallyBroken()`：只有 keywordForbidden / notAnApi 够格直接隐藏；
    blocked / unreachable 只计数 —— 实测有源是 WAF 拦出口 IP，换条路可能就好。
- `VideoApiService.probeSearchResponse()` / `buildSearchProbeUrl()`：
  与 `searchVideo` 走**同一条地址构造路径**（同样解第三方转发、同样包代理、
  参数同样落进内层目标），否则探测结果不代表搜索时的行为。
- 聚合搜索：改用 `VideoModule.visibleSourcesOf()` 取源；界面多一颗
  「已跳过 N 个已知不可用源」（跳过 ≠ 失败，两者分开说）；
  成功/失败分别落账；**只对失败的源**补一次能力探测 → 接口层坏的自动隐藏并留下理由。

## ② 线路可用性前置标注

### 现状

部分采集线路拿不到流：`/share/<id>` 这类网页地址里没有 `var main`；
个别媒体域名 DNS/TCP 直连不上。以前没有任何预兆 —— 点进去先卡一次，
再被自动换线。

### 实现

- `lib/video/services/line_reachability_store.dart`：按 **源 + 线路名**（不是按单片）
  聚合记忆"最近取不到流"，TTL 6 小时，成功起播立刻清除。
  按线路名聚合才有统计意义 —— 同名线路多走同一家采集/CDN。
- 写点：
  - 失败：`selectFallbackLine()` 里记下"刚换掉的那条线"（该方法的调用语义只有失败恢复）；
  - 成功：容器新增 `onPlaybackStarted`（判据与 `recordPlaybackStarted` 同一处 ——
    "真正 isInitialized" 而不是"这次没报错"），详情页回调里清标记。
- 读点：
  - **chip 前置标注**：淡橙描边 + 线路名弱化 + 小 `wifi_off` 图标；
  - **默认不选**：`_findPreferredLineIndex` / `findFallbackLineIndex` 跳过被标记的线路；
  - **全都标记时忽略标记**：那更像网络环境/代理的问题，不是线路本身的问题，
    此时按原判据选 —— 别把用户锁死。

### 验证方式

- 单测：`test/video/line_reachability_test.dart`（记忆判据含过期、默认选线跳过、
  全标记回落、起播清标记、换线记账）。
- 真机：连续两次进入同一部片，第二次被标记的那条线路 chip 上应带图标，
  且默认停在另一条线上。

### 踩到的坑：**别在 `loadDetail` 里 await 存储**

第一版在 `loadDetail` 里 `await LineReachabilityStore.ensureLoaded()` 再选线，结果
`video_download_bottom_sheet_test` 两条用例红了，报 `pumpAndSettle timed out`：
存储没就绪时 `isLoading` 一直是 true，loading 转圈动画让 `pumpAndSettle` 永不收敛。
（我单独写的探针用例是**假阴性** —— 那是个普通 `test()`，走真实异步，能过；
`testWidgets` 里时钟/调度不同就露馅了。）

改法：`loadDetail` 只 `unawaited(LineReachabilityStore.ensureLoaded())`，
预热放到 `main.dart` 启动处 —— 记忆读不出来就当没有标记，走原判据。
**规律**：详情页/列表页这类"首屏 loading"里不要 await 可选存储，
只有写路径（记账）才需要 await。
