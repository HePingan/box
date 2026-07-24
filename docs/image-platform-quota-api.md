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
https://background.hpa888.top
http://47.109.97.1:8799
http://127.0.0.1:8787
https://your-domain.com
```

前端会拼接以下接口：

```text
GET  /
POST /api/auth/register
POST /api/auth/login
GET  /api/auth/me
POST /api/auth/logout
GET  /api/image/quota
GET  /api/image/models
POST /api/image/generate
GET  /api/image/usage
GET  /api/image/proxy?url=<image-url>
```

除登录接口外，真实代理服务要求携带：

```http
Authorization: Bearer <box-session-token>
```

## CORS

Flutter Web 调试需要后端允许 CORS：

```http
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PATCH, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization, X-Admin-Token
```

真实生产环境建议将 `Access-Control-Allow-Origin` 收窄到你的 Web 域名。

## GET /

健康检查接口，方便直接在浏览器打开 Base URL 确认服务在线。

```json
{
  "ok": true,
  "service": "box-image-platform",
  "message": "Box Image Platform API running"
}
```

## 鉴权建议

真实代理服务内置 Box 账号注册/登录接口。Flutter 端默认连接 `https://background.hpa888.top`，也可在高级场景改成自有服务器地址。注册或登录后，再用返回的 session token 访问平台额度和管理员接口。

### POST /api/auth/register

```http
POST /api/auth/register
Content-Type: application/json
```

```json
{
  "username": "user001",
  "password": "your-password"
}
```

规则：

- 用户名 3-20 位，只支持字母、数字、下划线。
- 密码至少 6 位。
- `admin`、`root`、`system` 等为保留用户名。
- 注册账号默认为普通用户，初始平台图片额度由服务端 `IMAGE_REGISTER_DEFAULT_QUOTA` 控制，当前建议为 5 点。
- 服务端可通过 `IMAGE_REGISTRATION_ENABLED=false` 临时关闭开放注册；关闭后管理员仍可在后台创建账号。
- 注册成功后自动返回 session token，可直接登录使用。

返回：

```json
{
  "token": "box_session_xxx",
  "user": {
    "id": "u_xxx",
    "username": "user001",
    "role": "user",
    "status": "normal"
  },
  "quota": {
    "remaining": 5,
    "dailyLimit": 5,
    "usedToday": 0,
    "totalLimit": 5,
    "status": "normal"
  }
}
```

### POST /api/auth/login

```http
POST /api/auth/login
Content-Type: application/json
```

```json
{
  "username": "admin",
  "password": "your-password"
}
```

返回：

```json
{
  "token": "box_session_xxx",
  "user": {
    "id": "u_admin",
    "username": "admin",
    "role": "admin",
    "status": "normal"
  }
}
```

### GET /api/auth/me

```http
GET /api/auth/me
Authorization: Bearer <box-session-token>
```

返回当前用户公开信息。

### POST /api/auth/logout

```http
POST /api/auth/logout
Authorization: Bearer <box-session-token>
```

服务端会删除当前 session。

角色：

| role | 说明 |
| --- | --- |
| `user` | 普通用户，可使用自己的生图额度 |
| `admin` | 管理员，可使用生图额度，也可访问 `/admin/*` |

不要把管理员 Key 下发给前端。管理员账号只代表“可操作后台”，上游 API Key 仍只保存在服务器环境变量。

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

## GET /api/image/proxy

平台代理图片预览接口，用于手机端无法直接访问上游图片 CDN 时，通过 Box 后端转发图片内容。

```http
GET /api/image/proxy?url=https%3A%2F%2Fimage.example.com%2Fresult.png
Authorization: Bearer <box-s...ken>
```

限制：

- 仅支持 `http` / `https` 图片地址。
- 上游响应必须是 `image/*`。
- 单张图片代理上限 8MB。
- 该接口只用于预览图片，不记录 prompt，不返回 API Key。

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

## 题库云端管理与离线同步

题库沿用同一账号体系，但答题过程始终优先使用本地 SQLite，不会因为网络请求阻塞悬浮窗。

```text
管理员 CRUD/审核 → 云端 published 题库 → /api/quiz/sync 游标增量 → 客户端离线镜像
OCR/手工录入 → /api/quiz/submissions → pending 候选池 → 管理员 approve/reject
```

### 公开同步接口

```text
GET  /api/quiz/catalogs
GET  /api/quiz/sync?cursor=0&category=drive_ev
POST /api/quiz/submissions        # 需要登录
```

`/api/quiz/sync` 返回 `cursor` 与 `changes`。客户端只在本地空闲时拉取增量，并把成功应用后的 cursor 持久化；`upsert` 写入云端镜像记录，`delete` 仅删除云端镜像，不能删除用户本机私有 OCR 题。

### 管理员接口

```text
GET    /admin/quiz/questions?q=<keyword>&status=published
POST   /admin/quiz/questions
PATCH  /admin/quiz/questions/<id>
DELETE /admin/quiz/questions/<id>   # 软下架并下发 delete change
POST   /admin/quiz/questions/bulk   # 正式题批量 set_image / set_category
POST   /admin/quiz/categories/bulk  # 正式题批量设分类（兼容）
GET    /admin/quiz/incomplete?filter=missing_answer&q=关键词
POST   /admin/quiz/incomplete/bulk  # discard / set_category / publish
PATCH  /admin/quiz/incomplete/<id>  # 单条补全发布
POST   /admin/quiz/images/upload    # base64 题图上传
GET    /admin/quiz/submissions?status=pending
POST   /admin/quiz/submissions/<id>/approve
POST   /admin/quiz/submissions/<id>/reject
POST   /admin/quiz/import
```

#### 待补全批量 `POST /admin/quiz/incomplete/bulk`

```json
{
  "action": "publish",
  "ids": ["qi_xxx", "qi_yyy"],
  "correctAnswer": "A",
  "category": "驾驶理论题库-20260719",
  "answers": { "qi_xxx": "B" }
}
```

- `discard`：从队列移除，不进正式库  
- `set_category`：批量写分类  
- `publish`：校验后发布；可用统一 `correctAnswer`，或 `answers[id]` 覆盖单题；失败项 `skipped` 并保留队列  

#### 正式题批量 `POST /admin/quiz/questions/bulk`

```json
{
  "action": "set_image",
  "ids": ["q_1", "q_2"],
  "image": "/api/quiz/images/xxx.png"
}
```

支持 `set_image` / `set_category`，成功后对 published 题写增量 change。

题目唯一键由“规范化题干 + 排序后的规范化选项”构成。因此同题干但选项集不同会作为变体保留，不会被错误合并。

### 客户端离线同步策略（摘要）

- 入口：题库页「更新/分类/仅补图/全量重拉」；设置页「云端题库」卡片  
- 自动增量：启动/回前台，默认间隔 ≥ 6 小时，可关闭  
- 本地字段：`category`、`origin(local|cloud)`、`image`（优先本地缓存路径）  

### 备份与恢复

状态文件默认：`IMAGE_STATE_PATH`（默认 `.var/image_platform_state.json`）  
题图目录：`.var/quiz_images/`

推荐定期备份：

```bash
# 在服务工作目录执行
bash scripts/backup_quiz_platform.sh
# 恢复示例
# bash scripts/backup_quiz_platform.sh restore /path/to/backup_dir
```

生产机（background）建议 cron 每日拷贝 state + quiz_images 到独立磁盘，并保留近 7 份。

### 题目请求示例

```json
{
  "question": "驾驶电动汽车，图中指示灯亮起表示（）。",
  "type": "single_choice",
  "options": ["低荷电状态警告", "正在充电", "动力蓄电池故障", "驱动功率限制"],
  "correctAnswer": "A",
  "analysis": "……",
  "category": "drive_ev",
  "source": "管理员录入"
}
```


项目还提供一个最小真实代理服务：

```bash
IMAGE_ADMIN_BASE_URL=https://api.openai.com/v1 \
IMAGE_ADMIN_API_KEY=sk-xxx \
BOX_ADMIN_USERNAME=admin \
BOX_ADMIN_PASSWORD=change-me-now \
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
| `BOX_ADMIN_USERNAME` | `admin` | 首次初始化管理员用户名 |
| `BOX_ADMIN_PASSWORD` | 空 | 首次初始化管理员密码。已有管理员后不再生效 |
| `IMAGE_ALLOWED_MODELS` | 空 | 逗号分隔模型白名单，例如 `gpt-image-1,dall-e-3` |
| `IMAGE_DEFAULT_QUOTA` | `20` | 新用户默认额度 |
| `IMAGE_STATE_PATH` | `.var/image_platform_state.json` | JSON 状态文件 |
| `IMAGE_ADMIN_TOKEN` | 空 | 管理接口 token。为空时管理接口关闭 |

也可用启动参数覆盖监听地址：

```bash
dart run tool/image_platform_quota_server.dart --host 0.0.0.0 --port 8788
```

### 用户识别

真实代理服务通过登录 session 识别用户：

```http
Authorization: Bearer <box-session-token>
```

首次启动时，如果状态文件中还没有管理员账号，且提供了 `BOX_ADMIN_PASSWORD`，服务会创建：

```text
username = BOX_ADMIN_USERNAME 或 admin
role     = admin
```

密码只保存 salted sha256 hash，不保存明文。

如果没有携带 token，`/api/image/*` 会返回 `401`。

### 注册与公网控制环境变量

```text
IMAGE_REGISTRATION_ENABLED=true
IMAGE_REGISTER_DEFAULT_QUOTA=5
```

- `IMAGE_REGISTRATION_ENABLED=false` 会关闭 `POST /api/auth/register` 开放注册。
- `IMAGE_REGISTER_DEFAULT_QUOTA` 控制自注册用户初始额度、每日额度和总额度。
- 管理员后台创建用户不受注册开关影响。

### 状态文件

服务会写入：

```text
.var/image_platform_state.json
```

保存内容包括：

- Box 账号
- 登录 session
- 用户额度
- 今日已用
- 用户状态
- 最近用量记录

不要把真实生产状态文件提交到 Git。

### 管理接口

管理接口需要管理员登录 token：

```http
Authorization: Bearer <admin-box-session-token>
```

也兼容早期本地调试用：

```http
X-Admin-Token: <IMAGE_ADMIN_TOKEN>
```

查看用户与用量：

```http
GET /admin/image/users
```

查看上游 Provider 配置：

```http
GET /admin/image/provider
Authorization: Bearer <admin...ken>
```

返回不会包含明文 API Key：

```json
{
  "baseUrl": "https://api.openai.com/v1",
  "apiKeyMask": "sk-...abcd",
  "hasApiKey": true,
  "allowedModels": ["gpt-image-1", "dall-e-3"],
  "updatedAt": "2026-06-14T07:30:00.000"
}
```

保存上游 Provider 配置：

```http
POST /admin/image/provider
Content-Type: application/json
Authorization: Bearer <admin...ken>
```

```json
{
  "baseUrl": "https://api.openai.com/v1",
  "apiKey": "sk-xxx",
  "allowedModels": ["gpt-image-1", "dall-e-3"]
}
```

测试上游 Provider 连接：

```http
POST /admin/image/provider/test
Authorization: Bearer <admin...ken>
```

成功或失败均返回 HTTP 200，通过 `ok` 判断健康状态。该接口只测试上游 `/models`，不会发起付费生图。

```json
{
  "ok": true,
  "statusCode": 200,
  "baseUrl": "https://api.openai.com/v1",
  "hasApiKey": true,
  "modelCount": 12,
  "modelsPreview": ["gpt-image-1", "dall-e-3"],
  "message": "Provider 连接正常"
}
```

未配置 Key 示例：

```json
{
  "ok": false,
  "statusCode": null,
  "baseUrl": "https://api.openai.com/v1",
  "hasApiKey": false,
  "modelCount": 0,
  "modelsPreview": [],
  "message": "未配置上游 API Key"
}
```

查看最近使用记录：

```http
GET /admin/image/usage?userId=u_admin&success=false&limit=20
Authorization: Bearer ***
```

返回最近生图上游请求记录，不包含 prompt、图片 URL 或 API Key。管理员接口支持：

- `userId`：按用户 ID 过滤，留空不过滤。
- `success`：`true` / `false`，留空不过滤。
- `limit`：默认 200，最大 200。

```json
{
  "usage": [
    {
      "createdAt": "2026-06-14T08:10:00.000",
      "userId": "u_admin",
      "username": "admin",
      "model": "gpt-image-1",
      "cost": 1,
      "success": false,
      "statusCode": 503,
      "errorPreview": "上游 Provider 请求失败"
    }
  ]
}
```

用户查看自己的最近生图记录：

```http
GET /api/image/usage?success=false&limit=20
Authorization: Bearer ***
```

普通用户只能看到自己的记录，支持 `success` 和 `limit`，不支持查看其他用户。

查看用量概览：

```http
GET /admin/image/usage/summary
Authorization: Bearer ***
```

基于 usage 记录聚合，不包含 prompt、图片 URL 或 API Key。MVP 使用服务器本机日期统计，不处理复杂时区配置。

```json
{
  "today": {
    "date": "2026-06-14",
    "requests": 2,
    "success": 0,
    "failed": 2,
    "cost": 2,
    "activeUsers": 2
  },
  "last7Days": [
    {
      "date": "2026-06-14",
      "requests": 2,
      "success": 0,
      "failed": 2,
      "cost": 2,
      "activeUsers": 2
    }
  ],
  "topUsersToday": [
    {
      "userId": "u_admin",
      "username": "admin",
      "requests": 1,
      "success": 0,
      "failed": 1,
      "cost": 1
    }
  ]
}
```

导出使用记录 CSV：

```http
GET /admin/image/usage/export.csv?userId=u_admin&success=false&limit=200
Authorization: Bearer ***
```

管理员只读，与使用记录列表筛选一致。`limit` 默认 200，最大 1000。CSV 不包含 prompt、图片 URL 或 API Key。

CSV 字段：

```csv
createdAt,userId,username,model,cost,success,statusCode,errorPreview
```

规则：

- `baseUrl` 必须是 `http` / `https` 地址。
- `apiKey` 为空或不传表示保持旧 key 不变。
- `clearApiKey: true` 表示清空 key。
- `allowedModels` 支持数组，也支持逗号分隔字符串。
- 返回只包含 `apiKeyMask` / `hasApiKey`，不会返回明文 key。
- 状态文件中的 `providerConfig.apiKeyCipher` 是 MVP 存储字段，不是生产安全方案；生产必须接入 KMS / Secret Manager。
- `providerConfig` 优先于环境变量 `IMAGE_ADMIN_BASE_URL` / `IMAGE_ADMIN_API_KEY` / `IMAGE_ALLOWED_MODELS`。

创建用户：

```http
POST /admin/accounts
Content-Type: application/json
Authorization: Bearer <admin...ken>
```

```json
{
  "username": "user001",
  "password": "initial-pass",
  "role": "user",
  "dailyLimit": 20,
  "remaining": 20
}
```

约束：

- `username` 必填，大小写不允许重复。
- `password` 必填，长度至少 6 位，服务端只保存 salted sha256 hash。
- `role` 只允许 `user` / `admin`。
- 创建后自动初始化 quota。

更新用户角色/状态/密码：

```http
PATCH /admin/accounts/u_xxx
Content-Type: application/json
Authorization: Bearer <admin...ken>
```

```json
{
  "role": "user",
  "status": "disabled",
  "password": "new-pass"
}
```

约束：

- 字段均可选；不传或传空密码表示不修改密码。
- `status` 只允许 `normal` / `disabled`。
- 不允许降级或禁用最后一个正常管理员账号。
- 禁用账号会清理该账号已有 session。

快速禁用/恢复用户：

```http
POST /admin/accounts/u_xxx/status
Content-Type: application/json
Authorization: Bearer ***
```

```json
{
  "status": "disabled"
}
```

返回：

```json
{
  "user": { "id": "u_xxx", "username": "user001", "role": "user", "status": "disabled" },
  "quota": { "remaining": 5, "dailyLimit": 5, "status": "disabled" }
}
```

删除普通用户：

```http
DELETE /admin/accounts/u_xxx
Authorization: Bearer ***
```

约束：

- 管理员账号不能删除。
- 删除会移除账号、额度和该用户所有 session。
- 历史 usage 记录会保留；记录里仍保留 `userId` 用于审计。

调整用户额度：

```http
POST /admin/image/users/demo/quota
Content-Type: application/json
Authorization: Bearer <admin-box-session-token>
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
