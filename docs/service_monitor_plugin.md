# 服务监控插件（box × Uptime Kuma）

把 175 上 Uptime Kuma 的探针状态放进 box：首页插件区的**服务监控**，一眼看到
每个站点的在线状态、延迟与 24 小时可用率，不用再开浏览器看面板。

## 一、数据从哪来（链路）

```
Uptime Kuma（175, Docker, 127.0.0.1:3010）
        │  /metrics（Prometheus 文本，Basic 认证 = Kuma 账号）
        │  kuma.db（只读 URI，取 24h 可用率）
        ▼
175: /opt/kuma-monitor/gen_monitors_json.py   ← cron 每 2 分钟
        │  scp/ssh 推送（原子：.tmp → mv）
        ▼
边缘机: /home/update-server/public/monitors.json
        │  nginx（box.hpa888.top 的 location = /monitors.json）
        ▼
https://box.hpa888.top/monitors.json   ← box 插件读这个
```

- 生成脚本：`/opt/kuma-monitor/gen_monitors_json.py`（175，cron `*/2 * * * *`，日志 `/var/log/kuma-monitor.log`）
- 边缘机配置：`/www/server/panel/vhost/nginx/box.hpa888.top.conf` 里的 `location = /monitors.json`
  （精确匹配优先于 `location /` 的反代；已带 `Cache-Control: no-cache` 与 `Access-Control-Allow-Origin: *`）
- 自检：`python3 /opt/kuma-monitor/gen_monitors_json.py`（会打印项数、字节数、推送结果）
  与 `curl -s https://box.hpa888.top/monitors.json | jq .summary`

### 快照格式（刻意很小）

```json
{
  "generatedAt": "2026-09-25T10:37:13+08:00",
  "panelUrl": "https://ham.hpa888.top/",
  "summary": {"total": 10, "up": 10, "down": 0},
  "monitors": [
    {"name": "myb2api 码友邦桥接", "up": true, "id": 1, "pingMs": 118, "uptime24h": 100.0}
  ]
}
```

- **不含被监控的 URL**：这个端点是公开的（无鉴权），不该顺带泄露内网/服务地址。
- `generatedAt` 是服务端采样时刻；插件用它显示「采样于 N 分钟前」，也是判断快照新旧的唯一依据。
- `uptime24h` 来自 Kuma 的 heartbeat 表（不可读时**省略该字段**，插件显示 `—`）。

## 二、插件本体（box 侧）

| 文件 | 职责 |
|---|---|
| `lib/features/extensions/plugins/monitor/monitor_models.dart` | 纯数据 + 解析 + 文案（不依赖 dart:io / Flutter，单测直接跑） |
| `lib/features/extensions/plugins/monitor/monitor_service.dart` | 抓取（可注入 fetcher）+ 缓存上次成功快照 |
| `lib/features/extensions/plugins/monitor/monitor_page.dart` | 页面（汇总卡 + 列表 + 横幅 + 复制面板地址 + 清除本地快照） |
| `lib/features/extensions/core/builtin_plugin_catalog.dart` | 目录条目 `builtin_service_monitor`（中心区，sort 60） |
| `lib/features/extensions/core/builtin_plugin_pages.dart` | 路由码 `service_monitor` / `openServiceMonitor` |

几条刻意的取舍：

- **解析怎么变都不许把整页搞崩**：顶层结构不对 → `MonitorFormatException`（当作"这份快照不可用"，
  回退上次成功的或报错）；单个条目缺字段 → 尽量修（字符串数字、1/0 当真假），**连名字都没有就丢那一条**。
- **冷启动先用上次的快照渲染**，同时后台刷新；刷新失败**保留旧内容**并把原因写进横幅
  （`显示的是上次的内容（12 分钟前）`）—— 与远端存储插件 D7 同一形状。
- **仓库没有 url_launcher**（见 `announcement_popup.dart` 的说明），所以面板入口是
  「复制面板地址」而不是可点链接。
- 页面不整页报错、列表行不做 spinner；加载中有不确定进度圈，所以用例一律**有界 pump**，
  不用 `pumpAndSettle`。
- 测试接缝：`debugSetServiceMonitorRuntime(service:)`，widget 测试用 `_FakeService extends ServiceMonitorService`
  **必须覆写 `fetch()` 与 `cached()`**（不覆写会继承真实现去真联网）。

## 三、验证

```bash
# 插件目录用例（27 条：模型 10 + 服务 10 + 页面 7）
flutter test test/features/extensions/monitor

# 悬挂 API 闸门（285 起把 monitor 也纳入扫描范围）
python3 tool/scan_dangling_apis.py
```

## 四、已知边界

- 快照是**静态文件**：Kuma 挂了、生成脚本跑不动、边缘机收不到推送，客户端都可能拿到旧快照；
  这也是为什么页面必须显示 `generatedAt` 而不是假装数据是实时的。
- 生成脚本推送失败（ssh 不通）时**边缘机继续提供上一份**，脚本退出码 1 且日志留痕 —— 不静默。
- Kuma 的 `/metrics` 需要账号（Basic）。**不要把 Kuma 账号塞进 app**：app 只读我们的静态快照。
- 闸门脚本的调用点搜索范围包含 `test/`，所以"只在测试里被调用"的公开方法不会被它抓出来
  （已知边界；真正想抓这种，得把 `test/` 从 SEARCH 里摘掉并单独看）。
- 未发版：本轮只做到"可构建可测试"，发不发由你定。
