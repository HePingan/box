# Geek工具箱 Pro

> 一款跨平台的极客工具箱移动/Web 应用 — 工具、内容、扩展，一应俱全。

**版本:** 1.1.8+118  
**平台:** Android · iOS · Web · Windows · Linux · macOS

---

## 📋 功能概览

### 🏠 首页
智能问候（根据时段显示不同的问候语）、每日资讯速览、快捷功能卡片、插件推荐。插件化的首页卡片体系，支持动态加载和自定义。

### 🧰 百种工具
集中了 **100+ 实用工具**，分类清晰，支持搜索：

| 分类 | 包含工具 |
|------|----------|
| **日常工具** | 每日早报、每日一文、每日英语、央视新闻、步数修改、在线翻译、菜谱大全、全国降水量、历史上的今天、节假日查询 |
| **系统操作** | APK 提取、APK.1 安装器、系统界面调节、字体调节、屏幕坏点检测、壁纸提取、空文件夹清理、扬声器清灰、动态视频壁纸、设备信息、刻度尺、指南针、水平仪、分贝仪、秒表、计时器 |
| **图片工具** | 在线 PS、图片压缩、格式转换、九宫格切图、水印添加、老照片修复、黑白上色、图片拼接、壁纸提取 |
| **查询工具** | 快递查询、天气预报、IP 地址查询、API 查询、归属地查询、老黄历、成语词典、近义词、垃圾分类 |
| **提取工具** | 短视频去水印、图集提取、网页音频提取、B站封面提取、文案提取、图片文字识别 |
| **开发工具** | 时间戳转换、Base64 编解码、二维码生成/识别、JSON 格式化、正则测试、Hosts 编辑、颜色转换、UUID 生成、UserAgent 解析、端口扫描、IP 计算器、进制转换、Unicode 编码 |

### 🎬 视频模块
视频资源聚合与播放，支持多平台内容源，集成 Chewie 视频播放器。

### 📚 小说模块
小说阅读器，支持多书源（含自定义书源规则），书架管理、详情页、阅读器一应俱全。

### 🏪 内容仓库
内容资源管理中心 — 书籍、漫画、视频、音乐的聚合展示，支持收藏与管理。

### 🧩 扩展市场
插件化扩展体系，支持从市场下载安装第三方插件，含安全签名校验机制。

### 🤖 AI 图片生成
集成 AI 生图功能，支持多种 API 后端（兼容标准 API 格式），提供风格预设、提示词模板、历史记录管理。

### 🔌 API 中心
统一的 API 管理和测试入口，支持多工具调用。

---

## 🏗️ 技术架构

```
box-inspect
├── lib/
│   ├── app/                  # 应用核心（启动、路由、主题、Shell）
│   ├── features/             # 功能模块（业务代码）
│   │   ├── account/          # 账户模块
│   │   ├── api_hub/          # API 中心
│   │   ├── content/          # 内容仓库
│   │   ├── extensions/       # 扩展市场
│   │   ├── home/             # 首页
│   │   ├── image_generator/  # AI 图片生成
│   │   └── tools/            # 工具箱
│   ├── config/               # 应用配置
│   ├── design_system/        # 设计系统（主题、组件、Token）
│   ├── novel/                # 小说模块
│   ├── update/               # 更新检查
│   ├── utils/                # 工具函数
│   ├── pages/                # 通用页面
│   ├── plugin_market/        # 插件市场模型
│   └── video-Pro/            # 视频模块
├── assets/                   # 静态资源
├── docs/                     # 文档
├── scripts/                  # 构建脚本
├── test/                     # 测试
└── tool/                     # 开发工具
```

### 技术栈

| 技术 | 用途 |
|------|------|
| **Flutter** | 跨平台 UI 框架 |
| **Dart** | 开发语言 |
| **Provider** | 状态管理 |
| **Hive** | 本地持久化存储 |
| **Dio / http** | 网络请求 |
| **WebView** | 内嵌网页 |
| **Chewie** | 视频播放 |
| **CachedNetworkImage** | 图片缓存 |
| **FilePicker / ImagePicker** | 文件选择 |
| **encrypt / crypto** | 数据加密 |
| **xml / html** | 内容解析 |
| **SharedPreferences** | 偏好设置 |

### 架构模式

每个 `feature/` 模块采用 **data/domain/presentation** 三层架构：

```
feature/
├── data/           # 数据层（API 调用、本地缓存、数据模型）
├── domain/         # 领域层（实体、仓库接口、业务逻辑）
└── presentation/   # 展示层（页面、组件、状态管理）
```

---

## 🚀 快速开始

### 环境要求

- Flutter SDK (^3.11.1)
- Dart SDK (^3.11.1)
- JDK 17（Android 构建）
- Android SDK（Android 构建）

### 本地配置

```bash
# 克隆项目
git clone <repo-url> box-inspect
cd box-inspect

# 安装依赖
flutter pub get

# 运行 Web 预览（推荐开发方式）
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080

# 运行 Windows 桌面版
flutter run -d windows

# 构建 APK
flutter build apk
```

> **注意:** 本项目优先使用 Web 预览进行开发迭代，构建 APK 仅在需要发布时执行。

### 环境变量（Windows）

```bash
set JAVA_HOME=C:\tools\jdk17\jdk-17.0.19+10
set ANDROID_SDK_ROOT=C:\Android\Sdk
set ANDROID_HOME=C:\Android\Sdk
set PATH=%PATH%;%JAVA_HOME%\bin;C:\Android\Sdk\cmdline-tools\latest\bin;C:\Android\Sdk\platform-tools
```

---

## 🧑‍💻 开发指南

### 开发工作流

1. 代码修改 → `dart format` 格式化
2. 静态分析 → `flutter analyze`（确保无 issues）
3. 运行验证 → 重启 Web 预览，确认 HTTP 200

### 代码规范

- 遵循 `flutter_lints` 推荐规则
- 功能模块按 feature 拆分，内部按 data/domain/presentation 分层
- 公共组件放 `design_system/widgets/`
- 主题 Token 统一在 `design_system/app_tokens.dart` 管理

### 项目管理

- 版本号: `x.y.z+build` 格式（如 `1.1.8+118`）
- 更新检查: 内置更新服务，启动时检查新版本
- 底部导航: `首页 / 工具 / 内容 / 扩展`

---

## 📄 开源说明

本项目为私有项目，未公开发布至 pub.dev。

```
publish_to: 'none'
```

---

## 📮 相关资源

- [Flutter 官方文档](https://docs.flutter.dev/)
- [Dart 官方文档](https://dart.dev/)
