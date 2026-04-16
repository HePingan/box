# Flutter 小说阅读器 - MVC 架构重构

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── controllers/                 # Controller 层（MVC）
│   ├── novel_list_controller.dart    # 小说列表页控制器
│   └── novel_detail_controller.dart  # 小说详情页控制器
├── core/                        # Model & 核心数据层
│   ├── models.dart              # 数据模型（Model）
│   ├── novel_repository.dart    # 数据仓库
│   ├── novel_source.dart        # 书源接口
│   ├── qm_novel_source.dart     # 七猫书源实现
│   ├── cache_store.dart         # 缓存存储
│   ├── bookshelf_manager.dart  # 书架管理
│   └── ...
├── pages/                       # View 层（UI）
│   ├── novel_list_page.dart     # 小说列表页
│   ├── novel_detail_page.dart   # 小说详情页
│   ├── reader_page.dart         # 阅读器页面
│   └── reader/                  # 阅读器组件（已有Controller）
└── novel_module.dart            # 模块入口配置
```

## MVC 架构说明

### 1. Model 层
- **位置**: `core/models.dart`
- **职责**: 定义数据结构，包括小说、章节、阅读进度、阅读器设置等
- **特点**: 纯数据类，不包含业务逻辑

### 2. Controller 层
- **位置**: `controllers/`
- **职责**: 处理业务逻辑，包括数据加载、搜索、缓存、状态管理等
- **特点**: 
  - 使用 `ChangeNotifier` 进行状态管理
  - 通过 `provider` 与 View 层通信
  - 不依赖具体的 UI 实现

### 3. View 层
- **位置**: `pages/`
- **职责**: UI 展示，响应用户交互
- **特点**:
  - 只负责渲染和事件转发
  - 业务逻辑委托给 Controller
  - 通过 `provider` `watch` / `read` 获取状态

## 已重构完成的页面

| 页面 | Controller | 说明 |
|------|------------|------|
| 小说列表 | `NovelListController` | ✅ 已分离所有业务逻辑 |
| 小说详情 | `NovelDetailController` | ✅ 已分离所有业务逻辑 |
| 阅读器 | `ReaderController` / `ReaderNavigationController` | ✅ 已有Controller，结构保持 |

## 运行项目

```bash
flutter pub get
flutter run
```

## 依赖

- `provider: ^6.1.1` - 状态管理
- `http: ^1.1.0` - 网络请求
- `html: ^0.15.4` - HTML解析
- `shared_preferences: ^2.2.2` - 本地存储
- 其他依赖详见 `pubspec.yaml`

## 书源配置

项目支持多种书源配置方式：

```dart
// 1. 七猫小说
NovelModule.configureQimao(baseUrl: 'https://www.qimao.com');

// 2. 通用HTML书源
NovelModule.configureHtml(
  baseUrl: 'https://example.com',
  rules: SourceRules(...),
);

// 3. 规则书源JSON
NovelModule.configureRuleSource(bookSourceJson: json);
```
