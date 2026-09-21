# 答题插件 · 下一步打磨方案（P0–P3）

> 版本：2026-09-16 起草　基线：`1.20.6+259`（已发布 / id=101）
> 全部数字均在本轮**重新 grep 实测**，未沿用上一轮记忆。取证位置附在每节末尾。

---

## 第 0 节：上版（259）修了什么、没修什么

必须先说清进度停在哪，避免重听背景。

### ✅ 已修（259 已发布，公网可验）

| 项 | 内容 | 状态 |
|---|---|---|
| 考试模式恒小窗 | `examOverlayDimensions()` 的 px/dp 单位错配 → 尺寸决策搬进 `OverlayGeometryPolicy.examSize()`，三档改占屏宽比例 | 已进 259 包（dex 验到 0.36/0.58/0.86） |
| 三档塌成一档 | 下限 240dp 高于窄屏 small 档产出（130dp）→ 降到 120dp + 锁「三档严格递增」测试 | 已修 |
| 标题栏按钮被裁 | 窄窗下低频两键（框选/题库）收进既有 ⋯ 菜单，AI/眼睛/⋯ 恒常驻 | 已进 259 包（`titlebar.collapse` 日志串已验） |
| analyze 遗留错 | `quiz_overlay_titlebar_tokens_test.dart` 的 `const File` 编译错误（adf5c30 遗留） | 已修，analyze 0 error |

### ⏳ 未修 / 未验证（**本轮方案要接着做的**）

1. **真机手感未验证** —— 三档实际大小、收拢阈值是否合适，只有真机知道。这部分是**启发式**。
2. **考试窗位置硬编码右上角** —— `params.x = widthPixels - w - 3%屏宽`，用户拖走后**下次重新进入考试模式会弹回右上角**（见 P1-2）。
3. **push 未做** —— 本地 4 个 commit 未推（`c34bb5c` 最新）。
4. **`OverlayGeometryPolicy` 只管「尺寸」，不管「位置」** —— 位置仍散落在 service 的 12 处 `params.x =`。

---

## P0 ｜ 立即可做：真机验收闭环（低风险）

**为什么排最前**：259 的修复是**推理链 + 单测**证明的，真机手感是**未验证**的。
在未验证基础上继续叠功能，一旦有问题就分不清是新功能还是 259 的回退。

### P0-1　收真机证据（3 分钟，用户自助）

App 内已有调试日志面板（无需 adb）。请用户装 259 后照做：

1. 开考试模式，分别切「小 / 标准 / 大」各截图一张；
2. 「关于页 → 调试日志」复制含以下关键串的原文发来：
   - `overlay.apply ... applied=` → 实际生效尺寸
   - `exam` / `titlebar.collapse` → 考试模式与收拢是否触发

**判据**：`applied` 的宽度应随档位出现**三个不同值**（真机 1260px/3.5 预期约 454 / 730 / 1084 px）。
若两档相同 → 说明仍有夹取，需回查 `examSize`。

**取证**：日志串名见 `QuizAccessibilityService.kt` 的 `logDebug("overlay.apply ...")`；
`titlebar.collapse` 已在 259 公网 APK 的 dex 中验到（2 处）。

### P0-2　收拢阈值实测校准（**启发式，必须标参数**）

- **常量**：`OverlayGeometryPolicy.titleBarFits(availableWidthPx, density, requiredDp = TITLE_BAR_REQUIRED_DP)`
- **调大 `TITLE_BAR_REQUIRED_DP` 的方向** = **更早收拢**（更保守，窄窗更整洁）
- **调小** = 更晚收拢（尽量平铺，少一次点击）

**这是启发式兜底**，非精确布局：阈值用「全部按钮 dp 需求」估算，未计真实 padding 差异。
需用户给**一张窄窗截图**才能调准。请拍板：先按当前值试，还是要我据截图调。

### P0-3　push（**须用户明说**）

本地 4 个 commit 未推：`c34bb5c` / `adf5c30` / `4a5596d` / `e7382f5`。
按既有约定，**不擅自 push**。

---

## P1 ｜ 中等收益（中风险，建议 259 真机通过后做）

### P1-1　考试窗位置：从「硬编码右上角」改为「记忆上次位置」（中风险）

**为什么**：现在每次进入考试模式都强制弹回右上角：

```kotlin
// QuizAccessibilityService.kt:826
params.x = (dm.widthPixels - w - dm.widthPixels * 0.03f).toInt().coerceAtLeast(0)
params.y = (dm.heightPixels * 0.08f).toInt()
```

而**普通模式是有记忆的** —— `KEY_OVERLAY_GEOMETRY` = `"$x,$y"` 会持久化（`:3682`）。
两条路径口径不一致，属用户明确反对的「同类能力两套实现」。

**方案**：
- 考试模式首次进入仍用右上角（**保底，不变**）；
- 用户**拖动过**则写入 `KEY_EXAM_GEOMETRY`，下次优先恢复；
- 「重置悬浮窗大小」菜单项**一并清掉**考试位置（否则用户无法自救）。

**代价**：多一个持久化键，需防「存了个屏外坐标」→ 恢复时 `clampParamsToScreen`。

**可调参数**：`KEY_EXAM_GEOMETRY`（新增）；是否记忆 = 一个布尔常量开关，可一键回退。

**待拍板**：①记忆（推荐）②永远右上角（保持现状）。

### P1-2　位置决策也收进 policy（低风险，为 P2 铺路）

`params.x =` 在 service 中散落 **12 处**（`:826 :1181 :1466 :1736 :2139 :2253 :2362 :2380 :2389 :2522` 等），
`params.y` 同理。尺寸已收口到 `OverlayGeometryPolicy`，**位置没有** —— 同一类缺陷的另一半。

**方案**：`OverlayGeometryPolicy.examAnchor(...)` / `restoreOrAnchor(...)` 承接定位决策，service 只做搬运。
**收益**：位置也能 JVM 单测穷举（屏外、旋转、小屏）。
**风险低**：纯函数搬迁，行为逐位等价。

---

## P2 ｜ 结构性（观察项，暂不建议动手）

### P2-1　`QuizAccessibilityService.kt` 拆分评估

**实测体量（本轮 grep）**：

| 指标 | 值 |
|---|---|
| 行数 | **4576** |
| 成员声明 | **178** |
| 尺寸写点 | **16** |
| `updateViewLayout` 出口 | **16** |

尺寸已收口，但**服务整体仍是 4576 行的巨石**。
**为什么排在最后**：P1-2（位置收口）恰是在为拆分铺路 —— 先搬逻辑，再搬文件，风险最低。
现在直接拆会把「尺寸修复」和「结构搬迁」两个变更混在一次发布里，出问题难定位。

**判据**：若下次再出现「改了没变化」类问题，**此拆分优先级立刻提到 P0**。

### P2-2　Dart 侧大文件（观察，暂不动）

| 文件 | 行数 |
|---|---|
| `quiz_plugin_entry.dart` | 2128 |
| `quiz_bank_view_page.dart` | 1814 |
| `quiz_engine.dart` | 1711 |
| `quiz_bank.dart` | 1610 |

quiz_plugin 共 29 文件 / **14560 行**。**当前无 TODO 残留**（grep 计数 0），无紧迫性。

---

## P3 ｜ 可选（低优先）

- **P3-1**　~~考试模式「记忆上次档位」~~ —— **已核实：本就持久化，无需开发。**
  `examOverlaySize` 随 `QuizPluginEntry.saveConfig(_cfg)` 写入配置，
  读取端 `examSizePreference()` 从同一份 JSON 解析（`QuizAccessibilityService.kt:778`）。
  **本项撤回**（核实后不成立，如实列出而非静默删除）。
- **P3-2**　三档语义文案复核 —— 259 后「大」档会明显更宽（肯挡题），设置页文案是否需同步说明取舍。

---

## 待拍板（请用编号短答即可）

| # | 事项 | 选项 | 我的建议 |
|---|---|---|---|
| 1 | 真机验收 | A. 这就去装 259 试三档　B. 先不管，继续做 P1 | **A**（未验证就叠功能风险最高） |
| 2 | 收拢阈值 | A. 先按当前值试　B. 据我截图调 | **A**（先试，有截图再调） |
| 3 | 考试窗位置记忆（P1-1） | A. 记忆上次位置　B. 永远右上角 | **A**（普通模式已有记忆，口径应统一） |
| 4 | 位置收口进 policy（P1-2） | A. 做　B. 先不做 | **A**（低风险，为拆分铺路） |
| 5 | push 4 个 commit | A. 允许　B. 先不推 | 听你的 |

答完我直接落成 todo 开做，不再反问。

---

## 附录：本轮取证位置一览（可自行复核）

| 结论 | 命令 / 位置 |
|---|---|
| 服务 4576 行 / 178 成员 / 16 写点 / 16 出口 | `wc -l` + `grep -c` on `QuizAccessibilityService.kt` |
| 位置 12 处散落 | `grep -n "params.x = " QuizAccessibilityService.kt` |
| 考试窗硬编码右上角 | `QuizAccessibilityService.kt:826-827`（另 `:1181` 同型） |
| 普通模式位置有记忆 | `QuizAccessibilityService.kt:3682`（`putString(KEY_OVERLAY_GEOMETRY, "$x,$y")`） |
| policy 能力边界 | `OverlayGeometryPolicy.kt`：`defaultSize:166` / `floorSize:181` / `decide:201` / `ExamSize:269` / `examSize:322` / `titleBarFits:354` / `expandedSize:370` |
| 三档比例现值 | `examSize()`：`EXAM_WIDTH_RATIO_{SMALL,STANDARD,LARGE}` = 0.36 / 0.58 / 0.86 |
| 考试模式进入/退出链 | `QuizAccessibilityService.kt:714-724`（`autoExamByForeground` 内存标志） |
| 259 修复已进包 | 公网 APK dex：0.36/0.58/0.86 各命中；`titlebar.collapse` 2 处 |
| 未 push 的 commit | `git log --oneline origin/main..HEAD` → 4 个 |
