# 后端缺陷报告：无法给已有题目补图（已修复）

**状态**：✅ 已修复并上线（2026-08-22 验证）
**服务**：`https://background.hpa888.top` → `47.109.97.1`
**后端源码**：`/opt/box-backend/box-inspect/tool/image_platform_quota_server.dart`（Dart，6941 行）
**systemd 单元**：`box-image-platform.service`，监听 `127.0.0.1:8799`，nginx 反代
**影响（修复前）**：管理后台无法给云端任何一道已有题目添加或更换图片。功能完全不可用，没有客户端绕行方案。
**定位**：`PATCH /admin/quiz/questions/:id` 的唯一性校验会撞上库中 `identityKey` 相同的记录。

---

## 现象（修复前）

后台题库点「补图/换图」，选好图片上传成功后，写回题目时服务端返回：

```
题干与完整选项集已存在，不能合并覆盖
```

改走「删旧题 + 按原内容重建」的兜底方案，`POST /admin/quiz/questions` 返回：

```
题干与完整选项集已存在，不能重复创建
```

两条路被同一套校验封死。

---

## 根因

黑盒阶段的判断只对了一半。当时的推断是「校验没排除被更新的记录本身，撞上了自己」，依据是请求体里只有 `image` 一个字段：

```http
PATCH /admin/quiz/questions/<id>
{"image":"https://.../uploaded.png"}
```

拿到服务器权限后读源码 + 查生产数据，发现真实成因更麻烦：

**库里本来就存在 `identityKey` 相同的多条记录。** 生产库 2000 道题中有 **4 组重复、共涉及 9 道题**。成因是早期指纹算法没把答案纳入 `identityKey`，看图题批量录入时产生了孪生记录。

所以「排除自身」不足以解决问题 —— 即使 `AND id != :id` 排除了自己，这 9 道题改图时仍会撞上它的历史孪生记录，照样 409。

---

## 实际修复方案

**不是**简单排除自身，而是**比对更新前后各自撞到的记录集合**，只拦本次更新新引入的冲突：

```dart
// 查重只拦「本次更新新引入的冲突」，不拦已经存在的历史冲突。
Set<String> conflictIds(String identityKey) => store.quizQuestions.values
    .where((q) =>
        q.id != id &&
        q.identityKey == identityKey &&
        q.status != 'archived')
    .map((q) => q.id)
    .toSet();

final newConflicts =
    conflictIds(question.identityKey).difference(conflictIds(old.identityKey));
if (newConflicts.isNotEmpty) {
  // 409 题干与完整选项集已存在，不能合并覆盖。
}
```

判定逻辑：

| 场景 | 冲突集合变化 | 结果 |
|---|---|---|
| 给历史重复组的题改图/改分类 | 集合不变（撞的还是原来那条） | ✅ 放行 |
| 把 A 题改成 B 题的题干+选项 | 集合新增了 B | ❌ 409 拦下 |

集合没变大 → 冲突是历史遗留的，本次更新既没制造新重复也没加重问题 → 放行。一旦撞上原先没撞的记录，说明是真的想把两道不同的题合并成一道 → 拦下。

这个做法同时满足两个目标：让存量脏数据不再阻塞正常编辑，又不放过真正的重复合并。

> **修正记录**：本报告早期版本建议的 `AND id != :id`（排除自身）是不完整方案，不能覆盖历史孪生记录的情况，已作废。

---

## 验证结果

### 正向：历史重复组补图应放行

目标题 `q_Z7lHN4EF6yDN`（「这是什么交通标志？」），与另一题 `identityKey` 完全相同，属 4 组重复之一：

```bash
curl -X PATCH "https://background.hpa888.top/admin/quiz/questions/q_Z7lHN4EF6yDN" \
  -H "Authorization: Bearer ***" -H 'Content-Type: application/json' \
  -d '{"image":"/uploads/xxx.jpg"}'
```

结果：**HTTP 200**，`image` 写入成功，题干与选项不变。

### 负向：真合并仍应拦下

取一道无历史冲突的题，把它改成库中另一道已存在题目的题干+选项：

```bash
curl -X PATCH "https://background.hpa888.top/admin/quiz/questions/<无冲突题ID>" \
  -H "Authorization: Bearer ***" -H 'Content-Type: application/json' \
  -d '{"question":"如图所示，驾驶机动车行驶至铁路道口时，以下做法正确的是什么？","options":[...],"correctAnswer":"停车等待"}'
```

结果：**HTTP 409** `题干与完整选项集已存在，不能合并覆盖。` —— 正确拦下。

### 回归：关键路由（经公网 HTTPS）

| 路由 | 状态 |
|---|---|
| `GET /admin/quiz/questions` | 200 |
| `GET /admin/quiz/incomplete` | 200 |
| `GET /admin/image/usage/summary` | 200 |
| `GET /admin/policy/plugins` | 200 |
| `GET /admin/plugins/submissions` | 200 |
| `GET /admin/quiz/questions`（无 token） | 401 |

验证时的两个自身误判，供后来者避坑：

1. **负向测试第一版无效**。编了道「以下哪个是编程语言」想触发 409，实际返回 200 —— 查库发现该题在生产库里根本不存在（匹配数 0），不构成冲突，200 才是正确行为。**冲突源必须取自生产库真实存在的题目。**
2. **路径靠猜会误判成缺陷**。`/admin/quota/summary` 返回 404，真实路径是 `/admin/image/usage/summary`；`/admin/accounts` 的 404 同理 —— 它只注册了 POST/PATCH/DELETE，没有 GET。**测接口前先从源码 `grep` 出真实路由表。**

另外，仅凭「源文件 mtime 晚于进程启动时间」推断进程在跑旧代码是不可靠的，必须实测端点。

---

## 部署方式变更（2026-08-22）

原来 `ExecStart=/opt/dart-sdk/bin/dart run tool/image_platform_quota_server.dart`，每次启动都要重新编译 6941 行源码，重启窗口 5-15 秒。已改为预编译 AOT 二进制：

```ini
ExecStart=/opt/box-backend/bin/image_platform_quota_server
```

重启窗口从 5-15 秒降到 **0.28 秒**（约 40 倍），内存占用也更低（AOT 不带 JIT）。

⚠️ **副作用：改后端 `.dart` 源码不再自动生效，必须重新编译。**

```bash
sudo /opt/dart-sdk/bin/dart compile exe \
  /opt/box-backend/box-inspect/tool/image_platform_quota_server.dart \
  -o /opt/box-backend/bin/image_platform_quota_server
sudo systemctl restart box-image-platform.service
```

回滚材料（`TS=20260822115343`）：

- 单元文件：`/etc/systemd/system/box-image-platform.service.bak.before-aot-$TS`
- 状态数据：`/opt/box-backend/data/image-platform-state.json.bak.before-aot-$TS`

回退步骤：恢复单元文件 → `systemctl daemon-reload` → `systemctl restart`。源码原地未动，`dart run` 路径随时可用。

---

## 附：黑盒阶段探测过的其他路径

拿到源码后确认，这些结论仍然成立 —— 服务端没有别的补图入口：

| 请求 | 结果 |
|---|---|
| `PUT /admin/quiz/questions/:id` | 不支持 |
| `POST\|PATCH\|PUT /admin/quiz/questions/:id/image` | 404 接口不存在 |
| `POST\|PATCH\|PUT /admin/quiz/questions/:id/cover` | 404 接口不存在 |
| `POST\|PUT /admin/quiz/questions/import` | 404 接口不存在 |
| `POST\|PUT /admin/quiz/questions/upsert` | 404 接口不存在 |
| `DELETE /admin/quiz/questions/:id` | 支持 |
| `POST /admin/quiz/images/upload` | 支持 |

正解就是修 PATCH 的校验，已完成。

---

## 遗留：投稿侧补图仍不支持

投稿链路上有一个同源的设计问题，**本次未修**：普通用户推送带图题目时，若题干与选项和云端已有题目相同，服务端判定 `merged` 不建待审核记录。这是合理的去重，但结果是「给已有题目补图」在投稿侧无法完成，用户只能走后台。

后台这条路现在通了，所以这个问题不再是阻塞级。如果希望支持「补图投稿」，需要服务端区分「内容重复」和「补充缺失字段」两种情况。

## 遗留：存量重复数据未清理

生产库 4 组、9 道题 `identityKey` 重复的脏数据仍在。当前修复让它们不再阻塞编辑，但根上应该清理（合并或重算指纹）。清理前建议先备份 `image-platform-state.json`。
