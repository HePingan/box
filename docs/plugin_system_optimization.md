# Box 插件系统优化方案

> 分析日期：2026-07-12 | 涉及文件：9个，总计约 3,500+ 行

---

## 一、现状评估

### 架构概览

```
lib/features/extensions/
├── core/
│   └── home_plugin_core.dart        ← 核心引擎（~600行）
├── plugins/
│   └── plugin_toolbox.dart          ← 内置工具箱（~500行）
├── market/
│   ├── data/plugin_market_manifest_repository.dart  ← 清单仓库（~280行）
│   ├── domain/plugin_market_manifest.dart           ← 领域模型（~570行）
│   └── presentation/
│       ├── plugin_market_page.dart                  ← 市场页面
│       └── widgets/plugin_market_widgets.dart       ← 市场组件
└── presentation/
    ├── plugin_tab.dart                          ← 导航Tab
    ├── widgets/extension_management_widgets.dart ← 管理UI（~350行）
    └── widgets/plugin_card.dart                 ← 卡片组件
```

### 关键问题矩阵

| 优先级 | 问题 | 影响范围 | 严重程度 |
|--------|------|----------|----------|
| P0 | 内置工具代码膨胀且重复 | plugin_toolbox.dart | 🔴 高 |
| P0 | 硬编码导航耦合 | home_plugin_core.dart | 🔴 高 |
| P1 | ActionRegistry 不可扩展 | home_plugin_core.dart | 🟡 中 |
| P1 | 清单解析无错误边界 | plugin_market_manifest.dart | 🟡 中 |
| P2 | 无生命周期钩子 | 全局 | 🟢 低 |
| P2 | 安全模型薄弱 | 全局 | 🟢 低 |
| P3 | 无事件总线/通信机制 | 全局 | 🟢 低 |

---

## 二、P0 — 内置工具箱重构

### 问题

`plugin_toolbox.dart` 包含 6 个独立工具，每个都是 ~80 行的 showModalBottomSheet + StatefulBuilder 模式，存在大量重复：
- 相同的标题栏结构（Icon + Text + Button）
- 相同的输出区域结构（SelectableText + CopyButton）
- 相同的 controller.dispose() 清理

### 方案：提取通用 Shell 组件

```
plugin_toolbox.dart (精简至 ~50行)
├── _ToolShell (通用底部Sheet骨架)
├── _OutputArea (通用结果展示+复制)
├── showJsonFormatter()      ← 纯业务逻辑
├── showBase64Tool()
├── showPasswordGenerator()
├── showTimestampConverter()
├── showUrlCodec()
└── showQrCodeGenerator()
```

#### 具体改动

**1. 通用 Sheet 骨架：**
```dart
class _ToolShell extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget>? actions;     // 顶部操作按钮组
  final Widget input;              // 输入区
  final Widget? output;            // 输出区（可选）
  final String? error;             // 错误信息
  final double heightRatio;

  // 内部构建 showModalBottomSheet 内容
}
```

**2. 通用输出区域：**
```dart
class _OutputArea extends StatelessWidget {
  final String text;
  final bool selectable;
  // 带复制按钮的只读文本展示
}
```

**3. 各工具函数瘦身：**
每个工具函数只保留：
- 输入控件定义
- 业务逻辑（格式化/编解码/生成等）
- 状态管理回调

预期效果：
- `plugin_toolbox.dart` 从 ~500 行降至 ~150 行
- 新增工具只需 30-50 行

---

## 三、P0 — 解耦硬编码导航

### 问题

`HomePluginActionRegistry` 直接 import 了 `DailyNewsPage`、`NovelListPage`、`VideoListPage`、`ImageGeneratorPage`，导致：
- 模块间循环依赖风险
- 新增页面必须修改插件核心代码
- 无法从外部注册新动作

### 方案：路由表 + 自定义动作注册

**1. 将硬编码路由改为可配置的路由映射：**
```dart
// 不再 import 具体页面
class HomePluginRouteRegistry {
  static final Map<String, WidgetBuilder> _routes = {
    'daily_news': (_) => const DailyNewsPage(),
    'novel_list': (_) => const NovelListPageWithProvider(),
    'video_list': (_) => const VideoListPage(),
    'image_generator': (_) => const ImageGeneratorPage(),
  };

  static void register(String key, WidgetBuilder builder);
  static WidgetBuilder? lookup(String key);
}
```

**2. 支持 deep link / URL 导航：**
```dart
enum HomePluginActionType {
  toast,
  navigate,      // 替换原来的5个具体类型
  custom,
}

// payload 格式统一为 JSON
// {"route": "daily_news"}
// {"url": "https://example.com"}
// {"message": "Hello"}
```

**3. 允许外部注册自定义 handler：**
```dart
HomePluginActionRegistry.register(
  'open_settings',
  (context, actionContext) async {
    await Navigator.push(context,
      MaterialPageRoute(builder: (_) => const SettingsPage()));
  },
);
```

---

## 四、P1 — 可扩展的 Action 系统

### 问题

当前 `HomePluginActionType` 是 enum，每次新增动作都需要改枚举 + switch。

### 方案：动态注册表 + 命名空间

```dart
class HomePluginActionRegistry {
  // 内置动作（不可覆盖）
  static const Map<String, HomePluginActionHandler> builtin = {
    'toast': _showToast,
    'navigate': _navigate,
    'url_open': _openUrl,
  };

  // 用户/插件注册的自定义动作
  static final Map<String, HomePluginActionHandler> custom = {};

  static Future<bool> run(
    String actionCode,
    BuildContext? context,
    HomePluginActionContext actionContext,
  ) {
    final handler = custom[actionCode] ?? builtin[actionCode];
    if (handler == null) return false;
    await handler(context, actionContext);
    return true;
  }
}
```

**配置格式变更：**
```json
{
  "actionType": "custom",
  "actionCode": "my_custom_action",
  "payload": "{\"key\": \"value\"}"
}
```

---

## 五、P1 — 清单解析健壮性

### 问题

`plugin_market_manifest.dart` 中 `parseMarketPluginTemplates()` 对非法数据缺乏防御：
- 颜色解析失败时静默回退到默认值
- 缺少版本兼容性检查
- 网络请求失败后无重试

### 方案

**1. 添加解析错误收集：**
```dart
class ParseResult {
  final List<MarketPluginTemplate> templates;
  final List<ParseError> errors;

  bool get isValid => errors.isEmpty;
  bool get hasWarnings => errors.any((e) => e.severity == Severity.warning);
}

class ParseError {
  final String field;
  final Severity severity;
  final String message;
  final dynamic rawValue;
}
```

**2. 版本号兼容检查：**
```dart
enum ManifestVersion { v1, v2 }

class PluginMarketManifest {
  final int version;
  final List<MarketPluginTemplate> templates;

  bool supportsField(String fieldName) {
    if (version >= 2) return true;
    // v1 不支持的新字段...
    return false;
  }
}
```

**3. 网络请求重试：**
```dart
Future<String?> fetchWithRetry(
  String url, {
  int maxRetries = 2,
  Duration backoff = const Duration(seconds: 1),
}) async {
  for (var i = 0; i <= maxRetries; i++) {
    try {
      return await NetworkAssetBundle(Uri.parse(url)).loadString(url);
    } catch (e) {
      if (i == maxRetries) rethrow;
      await Future.delayed(backoff * (i + 1));
    }
  }
}
```

---

## 六、P2 — 插件生命周期管理

### 问题

当前插件只有 `enabled/disabled` 两种状态，缺少：
- 安装/卸载通知
- 版本更新检测
- 加载失败处理

### 方案：生命周期钩子

```dart
abstract class HomePluginLifecycle {
  /// 插件初始化时调用
  Future<void> onInitialize(BuildContext context, HomePlugin plugin);

  /// 插件被启用时调用
  Future<void> onEnabled(HomePlugin plugin);

  /// 插件被禁用时调用
  Future<void> onDisabled(HomePlugin plugin);

  /// 插件被卸载时调用
  Future<void> onUninstall(HomePlugin plugin);

  /// 插件执行前验证
  Future<bool> validate(HomePlugin plugin);
}

// 使用示例
class AnalyticsPluginLifecycle implements HomePluginLifecycle {
  @override
  Future<void> onEnabled(HomePlugin plugin) async {
    await analytics.logEvent('plugin_enabled', data: {'id': plugin.id});
  }
}
```

---

## 七、P2 — 安全增强

### 问题

当前安全模型仅支持签名验签，缺少：
- 权限控制（插件需要什么权限）
- 沙箱隔离（插件能访问什么资源）
- 风险评估

### 方案：权限声明 + 运行时检查

```dart
enum PluginPermission {
  network,      // 需要网络访问
  storage,      // 需要读写存储
  clipboard,    // 需要剪贴板
  camera,       // 需要相机
  none,         // 无需特殊权限
}

class MarketPluginTemplate {
  // ... 现有字段

  final List<PluginPermission> permissions;
  final String? requiredApiVersion;  // 最低 API 版本要求
  final bool requiresConfirmation;   // 安装前是否需要用户确认
}

// 运行时权限检查
class PermissionChecker {
  static Future<bool> check(
    HomePlugin plugin,
    PluginPermission permission,
  ) async {
    if (!plugin.enabled) return false;

    final template = findTemplate(plugin.id);
    if (template != null && !template.permissions.contains(permission)) {
      return true; // 白名单：模板未声明则允许
    }

    // 请求权限...
    return await requestPermission(permission);
  }
}
```

---

## 八、P3 — 事件总线

### 问题

插件之间、插件与主应用之间没有通信机制。

### 方案：轻量级事件总线

```dart
class PluginEventBus {
  static final PluginEventBus _instance = PluginEventBus._();

  static PluginEventBus get instance => _instance;
  PluginEventBus._();

  final Map<String, List<Function(dynamic)>> _listeners = {};

  void subscribe(String event, Function(dynamic) handler) {
    _listeners.putIfAbsent(event, () => []);
    _listeners[event]!.add(handler);
  }

  void unsubscribe(String event, Function(dynamic) handler) {
    _listeners[event]?.remove(handler);
  }

  void emit(String event, [dynamic data]) {
    final handlers = _listeners[event];
    if (handlers != null) {
      for (final handler in handlers) {
        handler(data);
      }
    }
  }
}

// 使用示例
// 插件A：监听用户登录事件
PluginEventBus.instance.subscribe('user_logged_in', (data) {
  // 同步用户数据到插件
});

// 主应用：发出事件
PluginEventBus.instance.emit('user_logged_in', {'userId': '123'});
```

---

## 九、P3 — UI 一致性改进

### 问题

1. 插件卡片在不同位置渲染不一致（市场页 vs 管理页）
2. 自定义插件图标颜色硬编码在 config 中
3. 无暗色主题支持

### 方案

**1. 统一卡片组件：**
```dart
// 所有地方使用同一个 PluginCard 组件
// 通过参数区分场景：
// - marketMode: 市场浏览模式
// - manageMode: 管理编辑模式
// - listMode: 列表模式
```

**2. 颜色从模板继承：**
```dart
class HomeCustomPluginConfig {
  // 新增：从市场模板继承颜色
  final String? inheritedColorHex;

  Color get effectiveColor {
    if (inheritedColorHex != null) {
      return Color(int.parse(inheritedColorHex!, radix: 16));
    }
    return Color(colorValue);
  }
}
```

---

## 十、实施计划

### Phase 1: 工具箱重构（1天）
- [ ] 提取 `_ToolShell` 通用骨架
- [ ] 提取 `_OutputArea` 输出组件
- [ ] 重构 6 个工具函数
- [ ] 验证所有工具功能正常

### Phase 2: 导航解耦（1天）
- [ ] 创建 `HomePluginRouteRegistry`
- [ ] 改造 `HomePluginActionRegistry` 支持动态注册
- [ ] 移除核心文件中的页面 import
- [ ] 测试所有内置动作

### Phase 3: 清单健壮性（0.5天）
- [ ] 添加 `ParseResult` 错误收集
- [ ] 实现网络重试
- [ ] 添加版本兼容检查
- [ ] 更新测试

### Phase 4: 生命周期 + 事件总线（1.5天）
- [ ] 定义 `HomePluginLifecycle` 接口
- [ ] 实现 `PluginEventBus`
- [ ] 在 `HomePluginHost` 中集成
- [ ] 编写集成测试

### Phase 5: 安全增强（1天）
- [ ] 定义 `PluginPermission` 枚举
- [ ] 扩展 `MarketPluginTemplate` 模型
- [ ] 实现 `PermissionChecker`
- [ ] 更新市场 UI 显示权限信息

**总计：约 5 个工作日**

---

## 十一、收益预估

| 指标 | 优化前 | 优化后 |
|------|--------|--------|
| plugin_toolbox.dart 行数 | ~500 | ~150 (-70%) |
| 新增工具开发时间 | 2小时 | 30分钟 (-75%) |
| 硬编码路由数 | 5 个 | 0 个 |
| 自定义动作注册方式 | 改源码 | 运行时注册 |
| 清单解析错误率 | 静默失败 | 可追踪报告 |
| 插件间通信 | 无 | 事件总线 |
| 安全权限控制 | 无 | 声明式权限 |
