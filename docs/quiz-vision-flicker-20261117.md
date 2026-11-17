# 「一直读屏闪烁不出答案」定位与修复（2026-11-17）

## 一句话结论

**模型和网络都是好的，答案每次都拿到了，是客户端把答案判成「过期」丢弃了。**

## 凭什么这么说（真数据，不是推测）

1. 后端 `box-image-platform` 日志里，用户两次点读屏都有记录：

```
2026-11-17T21:05:49 quiz-vision subject=u_admin upstream=200 bytes=554
2026-11-17T21:06:49 quiz-vision subject=u_admin upstream=200 bytes=575
```

`upstream=200` + 550 字节级响应体 = 上游正常返回了一次完整 chat completion。

2. flr 侧对应时刻：`POST /v1/chat/completions 200 OK (10502ms)` / `(1594ms)`。

3. 用**同一份真实题库题目**渲一张 1080×2340 的手机截图，按 App 自己的压缩规则
   （`visionMaxEdge=960` → 443×960）配上 App 的原始 `visionPrompt`，走代理实测 3 次：

| 次数 | 耗时 | 响应体 | finish | content |
|---|---|---|---|---|
| 1 | 1.5s | 663B | stop | `{"stem":"…仪表是什么？","options":[…],"answer":"A","confidence":0.95}` |
| 2 | 1.0s | 665B | stop | 同上 |
| 3 | 1.4s | 665B | stop | 同上 |

响应体字节数与用户那两次（554/575）同量级 ⇒ 用户拿到的也是结构化 JSON。
**`parseVisionJson` 完全能解析它**（围栏/裸对象/数组/散文五种形态都兼容）。

4. 于是问题只剩「拿到之后没上屏」。读代码找到两处：

## 根因一：题目身份被 dHash 污染（主因）

`quiz_plugin_entry.dart` 里：

```dart
// 旧
static bool _isCurrentRequest(int generation, String fingerprint) =>
    generation == _searchGeneration &&
    fingerprint == _activeQuestionFingerprint;   // ← 字面量比较
```

传进来的 `requestFingerprint` 是 `'<纯题干>|image:<dHash>'`。而 dHash 是**整屏视觉指纹**，
它随屏幕任何变化而变 —— **包括我们自己的悬浮窗刚刚画上去的答案与进度行**。

于是形成闭环：

```
读屏请求在飞（1.5~10.5s）
   → 自动捕获又抓一屏
   → 悬浮窗内容变了 ⇒ dHash 变了 ⇒ 指纹不相等
   → 「换题」⇒ _searchGeneration++ ⇒ 重画「新题 · 检索中…」（闪）
   → 答案回来时 _isCurrentRequest == false ⇒ 静默 return（没答案）
   → 悬浮窗再变 ⇒ dHash 再变 → …
```

用户看到的就是**一直闪、始终没有答案**。

**修法**：题目身份收口成纯题干（`QuizSearchPolicy.sameStemIdentity`），
题图 dHash 只用于消歧，不参与「是否换题」：

- `_isCurrentRequest` 按纯题干比对（17 个调用点一起受益）；
- 捕获入口的 `isNewQuestion` 按纯题干判定（不再因自己重绘而清空）；
- 新增 `_acceptVisionResult`：读屏结果是**同一道题**就上屏，
  哪怕期间 generation 漂移过（付费慢请求不该被「又抓了一屏」否掉）。

## 根因二：过程区块连续推送（次要，但它是「闪」的可见来源）

`AiProcessBridge.push` 每推一行，原生悬浮窗整块重绘一次。读屏链路在压缩/请求/重试
阶段会连推 4~6 次。新增 `QuizProcThrottle`：内容去重 + 250ms 窗口，
终态（`④ 识别成功` / `✖ 失败`）用 `force: true` 必推，不会丢掉最后一行。

## 顺带补的一条：同题并发守卫

`_visionInFlightStem`：同一道题同时只允许一条读屏请求在飞。以前自动捕获与手动按钮
各起一条时，两条结果互相顶 → 「检索中 → 答案 → 检索中」来回跳，还白烧一次付费调用。

## 改动清单

| 文件 | 改动 |
|---|---|
| `domain/quiz_search_policy.dart` | 新增 `sameStemIdentity(a, b)`：纯题干相等即同题（空指纹恒 false） |
| `domain/quiz_proc_throttle.dart` | 新增 `QuizProcThrottle`：过程推送合并器（可注入时钟，可单测） |
| `data/quiz_engine.dart` | 过程推送改走 `QuizProcThrottle`；成功/失败终态 `force: true` |
| `presentation/quiz_plugin_entry.dart` | `_isCurrentRequest` 改纯题干判据；`isNewQuestion` 同口径；新增 `_acceptVisionResult` 救回同题答案；新增 `_visionInFlightStem` 并发守卫 |
| `test/quiz_vision_flicker_regression_test.dart` | 新增回归：dHash 变化不改身份、换题仍判新题、空指纹、空白/大小写、推送合并与终态必推 |

## 验证

- 175 上 `flutter analyze lib/features/quiz_plugin` 干净
- 新增回归测试全绿；`test/*quiz*.dart` 全量通过
- 上游实测（代理链路）：同一 prompt + 真实截图，1.0~1.5s 返回可解析 JSON

## 没做（避免无据改动）

- **没有**调整 `visionMaxEdge`（960）：本轮证据里模型在 443×960 下都能正确读出题干与
  四个选项，没有「压太小读不出」的证据。真要调需要真机小字样本对比，不靠猜。
- **没有**改 prompt 文案：读数正常，问题不在提示词。
