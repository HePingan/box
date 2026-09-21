# 方案 v2：AI 读屏凭证管理后台化（多 agent 调查后重写）

> 2026-09-19 · 多 agent 实地调查（update-server 全貌 / dart 后端全貌 / 客户端全接入点）后定稿，取代同文件 v1 草案。
> 核心变化：发现 box 管理后台已有**服务端保管 key、客户端零 key** 的完整先例（生图平台额度模式），读屏凭证直接照搬该模式，比 v1 的「下发 key 到客户端」更优。

## 一、调查结论（三方事实）

### 管理后台现状
- **dart 后端（background.hpa888.top，box-image-platform，7794 行，active）** = 真正的账户/策略服务器：auth(register/login/me)、`GET /api/policy/plugins`（公开）+ `GET/PUT /admin/policy/plugins`（requireAdmin:3087）、quiz 同步、书源。持久化 state.json。**客户端每次启动+回前台都会访问它**（main.dart:17-23、app_shell.dart:150-152）。
- **它已有「管理员存 key、只回显掩码」的现成模式**：`POST /admin/image/provider`（admin_client.dart:37-56，服务端存 key，客户端只见 `apiKeyMask`）+ 应用内管理 UI（image_provider_tab.dart:170-183）。生图走**代理模式**：客户端只带 session token 调 `/api/image/generate`，服务端持有真实 key 转发上游——客户端从头到尾不碰 key。
- update-server（box.hpa888.top）：纯发版后台（JWT+审计+备份齐全但**无 KV/远程配置能力**），客户端只在升级时才访问。往它身上挂凭证 = 加表+加端点+加面板 ≈0.5-1 人日，且鉴权域、访问时机全不对。**否决**。

### 客户端现状（key 唯一烧死点）
- `quiz_plugin_entry.dart:1484` 唯一内置 key（sk-1XI…fiSC）；解析收敛点 `effectiveVisionApiKey()`:1493（手填>内置）；注入点 `_tryVisionFallback()`:1543-1547；出口 `quiz_engine.dart:1250-1254`（Bearer POST newapi /chat/completions，退避 2/5/10/15s、45s 预算、:1228 已有 401/403 标志位）。
- 生图页已有双模式枚举先例（ownKey / platformQuota，image_generator_models.dart:3-18）可直接仿写。

## 二、三方案对比

| | **A. 服务端代理（推荐）** | B. 凭证下发（v1 草案） | C. 扩展 update-server |
|---|---|---|---|
| 原理 | 客户端带 session token 调自家服务器，服务器持 key 转发 newapi | 服务器把 key 下发给客户端，客户端直连 newapi | 发版后台加配置模块下发 key |
| key 暴露面 | **零**（不出服务器） | 公开端点=事实公开，还进客户端缓存 | 同 B |
| 换 key 生效 | **服务端改配置即时生效，零客户端参与** | 需客户端缓存过期/401 强刷（最长 6h 窗口） | 同 B |
| 管理入口 | **现成模式照搬**：应用内 admin「视觉识别」tab 贴 key，掩码回显 | 同左但少先例 | 网页后台加面板，另建 JWT 域 |
| 401 处理 | 客户端 401=session 过期（已有重登流程），**吊销风暴从客户端消失** | 需新增 401 强刷重试逻辑 | 同 B |
| 代价 | 读屏请求多一跳（预计 +1~2s）；截图流量过服务器（~150KB/次，不落盘） | 服务器零负担 | 与发版共域，读屏挂可能拖累发版 |
| 新增代码 | 服务端 ~120 行 + 客户端 ~150 行 | 服务端 ~80 行 + 客户端 ~150 行+401 逻辑 | ~300 行 + 面板 |

**选 A 的决定性理由**：今天的事故是「key 被吊销→客户端全体超时→被迫发版」。方案 A 里 key 与客户端完全解耦，吊销/更换只是管理员在后台换一个字符串；方案 B/C 仍要把 key 送进每一台手机，缓存一致性、401 风暴、公开泄露面全都还在。用户明示「不在意 token 消耗」，多一跳的延迟/流量成本可接受。

## 三、方案 A 详设

### 服务端（image_platform_quota_server.dart，仿 image/provider 全套）
1. state.json 新增 `quizVisionProvider = {apiUrl, apiKey, enabled, updatedAt}`（与 image provider 同套原子落盘）。
2. `POST/GET /admin/quiz-vision/provider`（requireAdmin）：写入 apiUrl/apiKey/enabled；GET 只回掩码（`sk-1XI…fiSC` 格式）+ updatedAt，**永不回显完整 key**（协议文档 :181 既有原则）。
3. `POST /api/quiz/vision`（登录 session，Bearer session token）：body 透传 chat/completions 格式（model/messages 含截图 base64）；服务端注入真实 Authorization 转发 `apiUrl`；响应原样回传（含非 200 状态与错误体，让客户端复用现有重试/诊断）。**图片不落盘、不记内容**，日志只记耗时/状态码/账号 id/字节数。
4. 防滥用：每账号每日次数上限（常量 `quizVisionDailyCap`，默认 100，超出回 429+提示）。register 本就公开，必须设闸。

### 客户端（quiz_plugin）
1. QuizConfig 新增凭证模式枚举 `ownKey / platformProxy`（仿 image_generator_models），设置页加二选一，默认 `platformProxy`（新语义：跟随后台）。
2. `_tryVisionFallback()` 分流：platformProxy 且已登录 → POST `${serverUrl}/api/quiz/vision`（Bearer session token），key 字段留空；未登录或 ownKey → 走现直连路径（含手填 key、内置兜底，原逻辑原样保留）。
3. 代理路径遇 401/403 → 提示登录态过期走既有重登；遇 429 → 提示今日次数用完。**不再需要 v1 的 401 强刷凭证逻辑**（key 不在客户端，无从强刷）。
4. QuizDiag 新增：`vision.mode`（proxy/ownKey/builtinFallback）、`vision.upstream`（状态码+耗时+重试序号）。不记 key、不记题目内容。
5. 内置兜底 key 保留为「代理不可达且未登录」时的最后手段（死手开关，见拍板项 2）。

### 管理端 UX
应用内管理后台新增「AI 读屏」tab（仿 image_provider_tab）：粘贴 apiUrl/key、enabled 开关、掩码回显、保存即生效。换 key 全流程：打开后台→粘贴→保存，**不发版、不重启**。

## 四、代价与可调参数（如实）
- **延迟**：多一跳，实测基线 5.7~15.8s（直连 newapi），预计 +1~2s；服务器（47.109.97.1）与 newapi 同域内网互通概率高，实际增幅以真机实测为准。
- **流量**：服务器多吃 ~150KB/请求上行（截图转发），个人量级无压力；不落盘故不占磁盘。
- **可用性**：dart 后端成为读屏热路径；三级降级=代理→直连内置 key→失败提示，代理挂掉不致读屏全瘫（代价：降级时仍暴露兜底 key，与现状同级）。
- **可调常量**：`quizVisionDailyCap`（100，调小=更防白嫖）、客户端代理超时 45s（与现预算一致）、重试退避不变。
- 上线顺序：服务端先行（老客户端不认识新端点，零影响）→ 客户端 v272 非强更 → 后台贴 key → iQOO 真机验证调试日志 `vision.mode=proxy`。

## 五、实施清单（拍板后执行）
1. 服务端：3 个端点 + state 字段 + 编译重启 + curl 三层实测（匿名 401/登录 200/管理员掩码回显）。
2. 客户端：红灯测试先行（模式分流×3、降级×2、429 文案）→ 实现 → analyze 无新增 + 全测过。
3. v272 发布 + 后台配置 + 真机验证。
4. 收尾：v1 遗留的 `docs/quiz-vision-credential-delivery-plan.md` 被本文件取代（同文件已重写）。

## 六、待拍板项
1. **架构**：1=A 服务端代理（推荐）／2=B 凭证下发（省服务器流量，接受 key 下发）／3=C 扩展 update-server（不推荐）。
2. **内置兜底 key**：1=保留（代理/登录全挂时应急，推荐）／2=停用（key 彻底出包，接受服务端单点）。
3. **每账号每日限额**：1=加，默认 100 次/日（推荐）／2=先不限。
4. **默认模式**：1=platformProxy 为默认（推荐，跟随后台）／2=ownKey 为默认（尊重已手填 key 的老用户行为）。
