# 答题插件「AI 读屏」直连档的模型名可配（2026-11-17）

## 一句话

模型名从**硬编码 `deepseek`** 改成「用户填了就用自己的、留空用 flr 默认
`qodercn/qfmodel`」。这修的是**手填 key 直连**那一档一直以来的静默失败。

## 病灶

引擎里 `QuizEngine.visionModel` 是常量 `'deepseek'` —— 这是 NewAPI 渠道
（`newapi.hpa888.top/v1`）时代的写法：那个渠道用渠道名掩盖真实上游，所以
「模型名 = 渠道名 = deepseek」能通。

2026-10-10 上游切到 flr 后，两条路径的命运分开了：

| 档 | 行为 | 结果 |
|---|---|---|
| 平台代理（不填 key，默认） | 客户端仍发 `model: deepseek`，**服务端**用后台配置的 `provider.model`（`qodercn/qfmodel`）强制覆盖 | 正常 |
| 手填 key 直连（`allowExternalApi` + 自填地址/key） | 客户端直接把 `model: deepseek` 发到 flr | **flr 没有这个模型 ⇒ 每次「模型不存在」** |

上一轮切换文档里写的是「客户端 model 名不用改」—— 那句话对代理档成立，
对直连档是错的，而当时没人在直连档上验过。

## 改了什么

| 文件 | 内容 |
|---|---|
| `lib/features/quiz_plugin/domain/quiz_config.dart` | 新增 `apiModel`（默认 `''` = 用内置默认）；`copyWith` / `toJson` / `fromJson` 全通；**旧配置缺键 ⇒ 空串**，不做「把 deepseek 猜成新名字」的迁移（用户可能真的在用某个自建通道里的 deepseek） |
| `lib/features/quiz_plugin/data/quiz_engine.dart` | `visionModel` 常量值改 `qodercn/qfmodel` 并改名为主用 `defaultVisionModel`；新增**顶层纯函数** `visionModelFor(config)`；请求体与日志/进度文案一律用它 |
| `lib/features/quiz_plugin/presentation/quiz_plugin_config_widgets.part.dart` | 「自定义 API 通道（高级）」折叠区加「模型名（可选）」输入，提示 `qodercn/qfmodel`，并注明代理档会被服务端覆盖 |
| `test/quiz_vision_model_config_test.dart` | 7 条回归：默认值、空白算未配置、用户值原样、只 trim、JSON 往返、旧配置回退、copyWith 隔离 |

顶层纯函数而不是 `QuizEngine` 的方法：设置页与测试都要能直接调，
不实例化引擎（`searchVisionApi` 是实例方法，测试里要造 engine 才能碰就太重了）。

## 验证（真跑，非推断）

本机没有 Flutter SDK，验证在 **175** 上做（`/opt/flutter-3.44.6`）：

```bash
scp <改动文件> root@175:/root/box/...
ssh root@175 'cd /root/box && PATH=/opt/flutter-3.44.6/bin:$PATH \
  && flutter analyze lib/features/quiz_plugin test/quiz_vision_model_config_test.dart \
  && flutter test $(ls test/*quiz*.dart)'
```

- `flutter analyze` → **No issues found**
- `flutter test test/quiz_*.dart` → **717 passed**
- 上游真打（本机 flr 直连，同一张 960×540 识别题截图）：

| 模型 | 耗时 | 结果 |
|---|---|---|
| `qodercn/qfmodel` | **1.7s** | 正确读出题干/四个选项，勾选判 B |
| `aggregate/deepseek-v4-1-flash` | 8.3s | 也正确，但慢 5 倍 |
| `qoder/qfmodel`（国际版同款） | 90.5s | 502 上游挂死 —— **别选这家** |

- 平台代理链路（服务端持 key）：`POST /api/quiz/vision/device-token` → 拿设备令牌
  → `POST /api/quiz/vision/chat/completions`（带图）→ **200 / 2.4s**，返回
  `model: qfmodel`，答案正确。即服务端→flr 这一段本来就是通的，坏的只有直连档。

## 遗留

- 默认值 `qodercn/qfmodel` 写死在客户端，只是「开箱可用」的兜底。用户换成自己的
  通道时应在设置里改模型名 —— UI 已给入口，别再回到「客户端写死模型」的老路。
- 若某天 flr 上 `qodercn` 渠道整体失效，需要发版改默认值；缓解办法是让用户改设置
  （或在后台代理侧指定，代理档不受影响）。
