# 答题插件读屏模型：改由后台管理（2026-11-17）

## 一句话

读屏用哪个模型，现在**在 box 后台管理**（`/admin/quiz-vision/*`），不再需要改代码或
发版；候选列表从上游现拉，写错名字会被拒（除非显式 force），每次切换留审计。

## 为什么原来不行

- 客户端模型名曾硬编码 `deepseek`（NewAPI 时代）→ 直连档在 flr 上必然失败。
- 后台只有 `GET/POST /admin/quiz-vision/provider`：能改模型，但
  ① 没有候选列表（名字靠人记，抄错一个字母 = 读屏全挂且状态页一切正常）；
  ② 没有校验（不存在的模型照样写进去）；
  ③ 没有留痕（出事后无法确定「什么时候换的、换自哪里」）。

## 新增/变更的端点

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/admin/quiz-vision/models` | 从**当前上游**拉 `/models`，默认只回能识图的（`imageOnly=0` 看全部，`refresh=1` 绕过 60s 缓存）。带 `current` / `currentKnown`（当前模型是否还存在于上游）。 |
| POST | `/admin/quiz-vision/model` | **只切模型**（不动 baseUrl/key/开关）。默认要求模型存在于上游，否则 400 + 可识图候选；`force:true` 强写并在响应里标 `modelKnown:false`。 |
| GET | `/api/quiz/vision/config` | **公开**只读：`{enabled, model, thinkingOff, dailyCapPerAccount, updatedAt}`。给客户端/自检页看「现在到底用哪个模型」。**不含** baseUrl、key、key 指纹。 |

原有 `POST /admin/quiz-vision/provider` 保留（改地址/key/开关/总开关）。

审计：切模型会在 state 里记 `quizVisionProviderHistory`（最多 20 条，最新在前：
`{at, from, to, modelKnown, forced}`），切模型的响应里直接带回。
`GET /admin/quiz-vision/provider` 也可查。

## 实现要点（都是踩过的坑）

1. **模型候选必须现拉上游**：flr 上模型会变（本次实测 95 个，其中 56 个能识图），
   后端写死一张表必然过期。缓存 60s，避免每点一次都打上游。
2. **拉不到目录 ≠ 目录为空**：失败时返回 502 + 明文原因（key 过期/地址错），
   **不返回空数组** —— 空数组会让人以为「上游没模型」，指错方向。
3. **默认拒绝不存在的模型名**，并回候选列表。这类后台最贵的错误就是
   「切了个不存在的名字，读屏全挂但状态页一切正常」。
4. 上游模型条目里带 `supportsImage` / `isFree`：不支持识图的模型选了等于白搭，
   免费档关系到要不要花钱（`qodercn/qfmodel` 是 `isFree=true`）。
5. 客户端代理档的 model 会被服务端覆盖，故客户端进度文案改成
   「② 提交模型（代理档，实际由后台指定）」，不再让人以为客户端说了算。

## 验证（真跑）

编译机 = **175**（本机没有 Dart SDK；线上跑的是 AOT 二进制）：

```bash
# 175 上编译（flutter 自带 dart 3.12.2）
cd /root/boxbe && PATH=/opt/flutter-3.44.6/bin:$PATH \
  && dart pub get && dart analyze tool/image_platform_quota_server.dart \
  && dart compile exe tool/image_platform_quota_server.dart -o server.new
```

- `dart analyze` → **No issues found**
- 临时端口 18831 + 独立 state 的 10 步冒烟：
  - `GET /admin/quiz-vision/models` → `total 95 / imageOnly 56 / current qodercn/qfmodel / known true`
  - 切不存在的模型 → **400** + 候选（文案里带真实模型名）
  - 切 `qodercn/lmodel` → 200，`modelKnown=true`，history 记 1 条
  - `force:true` 强写 `ghost/model` → 200，`modelKnown=false`
  - 切回 `qodercn/qfmodel` → 200，history 三条（`qfmodel ← ghost/model ← lmodel`）
  - `GET /api/quiz/vision/config` → 无鉴权可读，且**不含** baseUrl/key
  - 端到端读屏（设备令牌 + 真截图）→ **200 / 1.4s / model=qfmodel**
- 生产 state 兼容性：用**生产 state 的副本**在 18804 起新二进制，
  provider 读得到、models 拉得到（56 个识图候选）、日志无异常
- 线上部署：备份 `image_platform_quota_server.bak.20261117pre` → stop → mv → start；
  `is-active=active`、`NRestarts=0`、`/proc/<MainPID>/exe` 非 `(deleted)`
- 线上真链路：`/api/quiz/vision/config` 200；`/admin/quiz-vision/models` 未登录 **401**
  （生产环境没配 `IMAGE_ADMIN_TOKEN`，管理员必须走账号登录 —— 权限没被新端点打开）；
  设备令牌 + 截图 → **200 / 2.4s / model=qfmodel**

## 用法

后台（或 curl，带管理员 session 或 `x-admin-token`）：

```bash
# 看候选（只列能识图的）
curl -s -H "x-admin-token: $TOKEN" https://background.hpa888.top/admin/quiz-vision/models
# 切模型
curl -s -X POST -H "x-admin-token: $TOKEN" -H 'Content-Type: application/json' \
  -d '{"model":"qodercn/qfmodel"}' https://background.hpa888.top/admin/quiz-vision/model
```

切完立即生效（代理档每次请求都读 state 里的 model），客户端**不用发版**。

## 遗留

- 后台目前是纯 API，没有 Web 页面；这套端点已按「给页面用」的形状设计
  （候选带 `current`/`supportsImage`/`isFree`，切换回审计），
  以后做管理页直接消费即可。
- 生产未配置 `IMAGE_ADMIN_TOKEN`，管理员需用账号登录换 session。
