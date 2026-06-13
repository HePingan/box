# AI 生图平台额度 API

本文档定义 AI 生图工坊「平台额度」模式期望的后端代理协议。

## 目标

客户端不内置管理员 API Key。客户端只请求平台后端，由平台后端完成：

- 用户鉴权
- 管理员 API Key 保管
- 模型白名单
- 额度检查与扣减
- 失败回滚 / 失败不扣费
- 限流
- 用量日志
- 调用真实 OpenAI 兼容生图接口

```text
Flutter Web / APK
  -> 平台额度后端
  -> OpenAI / 中转 / One API / New API
```

## Base URL

前端平台服务地址示例：

```text
http://127.0.0.1:8787
https://your-domain.com
```

前端会拼接以下接口：

```text
GET  /api/image/quota
GET  /api/image/models
POST /api/image/generate
```

## CORS

Flutter Web 调试需要后端允许 CORS：

```http
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
```

真实生产环境建议将 `Access-Control-Allow-Origin` 收窄到你的 Web 域名。

## 鉴权建议

当前前端 scaffold 不强制鉴权头，但真实后端应使用任一方式识别用户：

- App 登录态 Cookie
- `Authorization: Bearer <user-token>`
- 设备绑定 token
- 网关层统一鉴权

不要把管理员 Key 下发给前端。

## GET /api/image/quota

查询当前用户额度。

### Request

```http
GET /api/image/quota
```

### Response 200

```json
{
  "remaining": 20,
  "dailyLimit": 30,
  "usedToday": 10,
  "totalLimit": 100,
  "status": "normal",
  "message": "今日剩余 20 次"
}
```

字段说明：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `remaining` | number | 是 | 当前剩余额度 |
| `dailyLimit` | number | 是 | 每日额度上限 |
| `usedToday` | number | 是 | 今日已使用额度 |
| `totalLimit` | number/null | 否 | 总额度上限 |
| `status` | string | 否 | `normal` / `disabled` / `limited` |
| `message` | string | 否 | 给用户看的说明 |

前端也兼容部分别名：

```json
{
  "remainingQuota": 20,
  "dailyQuota": 30,
  "used": 10
}
```

## GET /api/image/models

查询平台允许用户使用的生图模型。

### Request

```http
GET /api/image/models
```

### Response 200: 简单格式

```json
{
  "models": [
    "gpt-image-1",
    "dall-e-3",
    "flux-dev"
  ]
}
```

### Response 200: OpenAI 兼容格式

```json
{
  "data": [
    { "id": "gpt-image-1" },
    { "id": "dall-e-3" }
  ]
}
```

前端会去重、排序，并优先展示疑似生图模型。

## POST /api/image/generate

使用平台额度生成图片。

### Request

请求体复用 OpenAI 兼容生图 JSON。

```http
POST /api/image/generate
Content-Type: application/json
```

```json
{
  "model": "gpt-image-1",
  "prompt": "一张蓝紫渐变科技感海报",
  "size": "1024x1024",
  "quality": "auto",
  "n": 1,
  "output_format": "png"
}
```

可选图生图兼容字段：

```json
{
  "image": "https://example.com/ref.png"
}
```

或：

```json
{
  "reference_image": "https://example.com/ref.png",
  "input_image": "https://example.com/ref.png"
}
```

后端应校验并过滤：

- 模型是否允许
- 数量上限
- 尺寸/质量是否合法
- 用户额度是否足够
- 参考图 URL 是否允许访问

### Response 200: URL

```json
{
  "data": [
    {
      "url": "https://example.com/generated.png",
      "revised_prompt": "optional"
    }
  ]
}
```

### Response 200: base64

```json
{
  "data": [
    {
      "b64_json": "iVBORw0KGgo...",
      "revised_prompt": "optional"
    }
  ]
}
```

前端同时支持 `url` 与 `b64_json`。

## 错误响应

建议统一返回：

```json
{
  "error": {
    "message": "额度不足，请明天再试",
    "code": "quota_exhausted"
  }
}
```

也兼容：

```json
{
  "message": "额度不足，请明天再试"
}
```

推荐状态码：

| 状态码 | 场景 |
| --- | --- |
| 400 | 参数非法 |
| 401 | 用户未登录 / token 无效 |
| 403 | 用户被禁用 / 模型无权限 |
| 404 | 接口不存在 |
| 408 | 上游超时 |
| 429 | 额度不足 / 限流 |
| 500 | 后端异常 |
| 502 | 上游接口异常 |
| 503 | 上游不可用 |

## 扣费建议

推荐后端事务流程：

1. 鉴权用户。
2. 校验参数和模型白名单。
3. 计算本次预计消耗。
4. 检查额度是否足够。
5. 创建 pending 用量记录。
6. 调用上游生图接口。
7. 成功：扣减额度并标记 success。
8. 失败：标记 failed，不扣费或回滚预扣。

示例扣费规则：

```text
基础：每张图 1 点
高清 / high quality：每张图 2 点
参考图：额外 1 点
```

## 真实平台额度代理服务

项目还提供一个最小真实代理服务：

```bash
IMAGE_ADMIN_BASE_URL=https://api.openai.com/v1 \
IMAGE_ADMIN_API_KEY=sk-xxx \
IMAGE_ADMIN_TOKEN=local-admin-token \
IMAGE_DEFAULT_QUOTA=20 \
PORT=8788 \
dart run tool/image_platform_quota_server.dart
```

默认监听：

```text
http://127.0.0.1:8788
```

前端「平台服务地址」填入该地址即可使用真实平台额度代理。

### 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `HOST` | `127.0.0.1` | 监听地址 |
| `PORT` | `8788` | 监听端口 |
| `IMAGE_ADMIN_BASE_URL` | `https://api.openai.com/v1` | 上游 OpenAI 兼容 Base URL |
| `IMAGE_ADMIN_API_KEY` | 空 | 上游管理员 Key。为空时不允许真实生图 |
| `IMAGE_ALLOWED_MODELS` | 空 | 逗号分隔模型白名单，例如 `gpt-image-1,dall-e-3` |
| `IMAGE_DEFAULT_QUOTA` | `20` | 新用户默认额度 |
| `IMAGE_STATE_PATH` | `.var/image_platform_state.json` | JSON 状态文件 |
| `IMAGE_ADMIN_TOKEN` | 空 | 管理接口 token。为空时管理接口关闭 |

也可用启动参数覆盖监听地址：

```bash
dart run tool/image_platform_quota_server.dart --host 0.0.0.0 --port 8788
```

### 用户识别

最小实现支持：

```http
X-User-Id: demo
```

也支持 query：

```text
/api/image/quota?userId=demo
```

如果都没有，默认用户为：

```text
demo
```

真实生产环境应接入登录态或网关鉴权，不应只依赖用户自填 header。

### 状态文件

服务会写入：

```text
.var/image_platform_state.json
```

保存内容包括：

- 用户额度
- 今日已用
- 用户状态
- 最近用量记录

不要把真实生产状态文件提交到 Git。

### 管理接口

管理接口需要：

```http
X-Admin-Token: <IMAGE_ADMIN_TOKEN>
```

查看用户与用量：

```http
GET /admin/image/users
```

调整用户额度：

```http
POST /admin/image/users/demo/quota
Content-Type: application/json
X-Admin-Token: <IMAGE_ADMIN_TOKEN>
```

```json
{
  "remaining": 50,
  "dailyLimit": 50,
  "usedToday": 0,
  "totalLimit": 100,
  "status": "normal",
  "message": "已充值 50 点"
}
```

### 真实生图代理流程

`POST /api/image/generate` 会：

1. 校验后端是否配置 `IMAGE_ADMIN_API_KEY`。
2. 读取用户额度。
3. 校验 prompt、模型白名单和用户状态。
4. 按 `n`、`quality`、参考图字段计算消耗。
5. 额度不足返回 `429`，不请求上游。
6. 请求 `{IMAGE_ADMIN_BASE_URL}/images/generations`。
7. 上游失败：记录失败用量，不扣额度，透传上游响应。
8. 上游成功：扣减额度，记录成功用量，返回上游 JSON。

当前 MVP 为轻量 JSON 文件存储，适合本地/小规模内测；生产环境建议改为数据库事务、正式鉴权、限流与审计日志。

## 本地 Mock 服务

项目提供开发用脚本：

```bash
dart run tool/image_platform_mock_server.dart
```

默认监听：

```text
http://127.0.0.1:8787
```

前端「平台服务地址」填入该地址即可联调。
