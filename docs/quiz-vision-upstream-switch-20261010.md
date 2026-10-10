# 答题插件「AI 读屏」上游切换（2026-10-10）

## 一句话

读屏上游从 `newapi.hpa888.top/v1` + `deepseek` 切到 `flr.hpa888.top/v1` +
`qodercn/qfmodel`（Qwen3.8-Flash），并顺手修掉两个会让用户「白等一次」的真问题：
上游长思考超时、以及模型返回 JSON 数组时客户端解析失败。

## 为什么要切（旧上游已死）

切换前实测旧上游（用 `/etc/box-image-platform.env` 里那把我方 key 直连）：

```
POST https://newapi.hpa888.top/v1/chat/completions  {"model":"deepseek",...}
→ HTTP 503 {"error":{"code":"model_not_found",
   "message":"No available channel for model deepseek under group default"}}
```

即**渠道里已经没有 `deepseek` 这个模型**了，读屏对所有人都是失败。
所以这次不是「换一个更便宜的」，而是**恢复功能**。

## 改了什么

| 位置 | 内容 |
|---|---|
| 服务端 state（唯一生效点） | `quizVisionProvider`：`baseUrl=https://flr.hpa888.top/v1`、`apiKey=…`、`model=qodercn/qfmodel`、`enabled=true`、新增 `thinkingOff=true` |
| `/opt/box-backend/bin/image_platform_quota_server` | 新二进制（`reasoning_effort=none` 注入 + `thinkingOff` 开关） |
| `lib/.../data/quiz_engine.dart` | `parseVisionJson` 支持「JSON 数组」（围栏内 / 裸数组），取首个对象 |
| `test/quiz_ai_vision_external_search_test.dart` | 数组形态 3 条回归用例 |

**客户端 model 名不用改**：引擎照旧发 `model: "deepseek"`，服务端代理
用后台配置的 `provider.model` 强制覆盖（实测返回体 `model` 字段为 `qfmodel`）。
所以这次是**纯服务端改动 + 不必须发版**。

## 实测数据（全部真实调用，非推断）

### 1. 上游延迟：默认带思考 = 会撞客户端 45s 硬顶

客户端引擎硬顶 45s（`QuizVisionTimeouts.engineHard`），超了就报「读屏超时」。
真实尺寸截图（长边 960，与客户端压缩后一致）：

| 参数 | 实测耗时 |
|---|---|
| 默认（带思考） | 16.4s / 28.1s / 45.5s / 50.3s / **76.0s** / **90s 超时** |
| 追加 `reasoning_effort: "none"` | **1.5 / 2.0 / 2.1 / 2.2 / 2.3 / 3.3 / 3.6 / 3.8 / 4.3s**（9 次） |

带思考时 `completion_tokens_details.reasoning_tokens` 达 1000~5900，钱和时间都烧在思维链上。
关掉后该字段为 `None`，输出更短、更贴 JSON。

**注意**：客户端已经在发 `enable_thinking:false`、`chat_template_kwargs.thinking=false`、
`tool_choice:"none"` —— **这个上游全部忽略，只有 `reasoning_effort:"none"` 有效**。
字段容忍度已实测：`flr` 的 `trae/deepseek-V3`、`buddy/hunyuan-chat` 收到该字段照常 200，
旧 `newapi` 也只是报它自己的 `model_not_found`（不是 400 参数错），故对两档上游都安全。

### 2. 输出形态：8 次样本里 1 次是数组，旧解析器会失败

模型看到截图上有两道题时会返回 `[{"stem":...},{"stem":...}]`（常带 ```json 围栏）。
旧正则 `(\{[\s\S]*?\})` 只认对象，整段匹配落空 → 用户看到「读屏返回无法解析」白等一次。

用**线上同一个解析器**（`flutter test` 直接 import `quiz_engine.dart`）跑发布后真实样本：

- 修前：7/8（`real960#4` 的数组样本解析不到 answer）
- 修后：**8/8**

## 复现命令

```bash
# 上游直连（key 从 state 的 apiKeyCipher 解出，或找管理员要）
curl -s https://flr.hpa888.top/v1/chat/completions \
  -H "Authorization: Bearer <key>" -H 'Content-Type: application/json' \
  -d '{"model":"qodercn/qfmodel","messages":[{"role":"user","content":[
       {"type":"text","text":"只输出 JSON，第一个字符就是 {。"},
       {"type":"image_url","image_url":{"url":"data:image/png;base64,<b64>"}}]}],
       "reasoning_effort":"none","max_tokens":1200}'

# 经平台公网代理（客户端真实路径：匿名设备令牌 → /api/quiz/vision/chat/completions）
curl -s -X POST https://background.hpa888.top/api/quiz/vision/device-token \
  -H 'Content-Type: application/json' -d '{"deviceId":"selftest-xxxxxxxx"}'
```

## 回滚

`provider` 是 state 里的一条配置，回滚 = 用管理接口写回旧值：

```bash
# hpa888 上：/root/.secrets/quiz-vision-rollback.json 存着切换前的 oldProvider（含密文原文）
ssh hpa888
# 用管理员账号 POST /admin/quiz-vision/provider，body 用 oldProvider 里的
#   baseUrl / apiKeyCipher / model / enabled
```

⚠️ 但**旧上游的 `deepseek` 已经 503 了**，回滚只会回到「读屏全失败」。
真要回滚应改成同一个 flr 上的别的模型（候选与实测见下），而不是回 newapi。

若只想关掉「关思考」这一档：`POST /admin/quiz-vision/provider {"thinkingOff": false}`。

## 候选模型（同一把 key 实测，真实尺寸截图）

| 模型 ID | 耗时 | 说明 |
|---|---|---|
| `qodercn/qfmodel` | 2~4s | **本次选用**（Qwen3.8-Flash，支持图片） |
| `qodercn/q37fmodel` | 32.6s | Qwen3.7-Flash，带思考时更慢 |
| `qodercn/auto` | 50.3s | 自动路由，最慢且输出带围栏 |
| `qodercn/qmodel_38max` | 3.7s（小图） | Qwen3.8-Max，更贵，需要更高准确率时可换 |

同类备选（同 flr，均支持图片）：`trae/qwen3.8-flash`、`buddy/glm-5.3-flash`、
`lobsterai/qwen3.8-flash`、`codearts/deepseek-v4-flash`。

## 额度与成本

- 平台仍是**每主体（账号 / 匿名设备）每日 100 次**（`quizVisionDailyCap`），
  突发限流 + 失败统计沿用原逻辑，未动。
- flr 侧按 token 计费（响应 `usage.credits` 可见），关思考后 completion_tokens
  从 3000+ 降到 ~200，**单次成本约降一个数量级**。
