// ignore_for_file: non_const_argument_for_const_parameter

// P2-2：内置插件目录（从 home_plugin_core.dart 拆出）。
//
// 这里只放「有哪些内置插件 + 各自点开去哪」；注册表 / 持久化 / 事件总线
// 仍留在 home_plugin_core.dart。拆分的目的是让 core 不再直接 import 具体 UI 页
// （此前 core 横跨 5 个 feature、依赖 9 个具体页面）。

import 'package:flutter/material.dart';

import 'package:box/features/extensions/core/home_plugin_core.dart';
import 'package:box/features/extensions/plugins/plugin_toolbox.dart';
import 'package:box/features/extensions/plugins/monitor/monitor_page.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_page.dart';
import 'package:box/features/image_generator/presentation/image_generator_page.dart';
import 'package:box/features/policy/plugin_policy.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_bank_view_page.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_entry_page.dart';
import 'package:box/features/quiz_plugin/presentation/quiz_plugin_entry.dart';
import 'package:box/daily_news_page.dart';
import 'package:box/novel/pages/novel_list_page.dart';
import 'package:box/video/video_compat_pages.dart';

/// 内置插件目录（P2-2 从 home_plugin_core.dart 拆出）。
///
/// 15 个内置插件的元数据 + onTap 装配入口。拆分动机：core 原先同时承担
/// 注册表 / 内置目录 / 页面装配三职，胀到 1500+ 行，任何页面改路径都要动 core。
List<HomePlugin> buildDefaultPlugins() {
  // 注册答题插件自动搜题的 MethodChannel handler
  QuizPluginEntry.initAutoSearch();
  return <HomePlugin>[
    HomePlugin(
      id: 'builtin_daily_news',
      title: '日报详情',
      subtitle: '查看完整热闻列表',
      icon: Icons.newspaper_outlined,
      color: Colors.deepPurple,
      area: HomePluginArea.recommend,
      builtIn: true,
      sort: 10,
      onTap: (context) async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DailyNewsPage()),
        );
      },
    ),
    HomePlugin(
      id: 'builtin_json_formatter',
      title: 'JSON 格式化',
      subtitle: '粘贴 JSON 一键格式化与校验',
      icon: Icons.data_object_rounded,
      color: Colors.orange,
      area: HomePluginArea.recommend,
      builtIn: true,
      sort: 15,
      onTap: (context) async {
        await PluginToolbox.showJsonFormatter(context);
      },
    ),
    HomePlugin(
      id: 'builtin_base64',
      title: 'Base64 编解码',
      subtitle: '文本 ↔ Base64 双向转换',
      icon: Icons.lock_outline,
      color: Colors.teal,
      area: HomePluginArea.recommend,
      builtIn: true,
      sort: 20,
      onTap: (context) async {
        await PluginToolbox.showBase64Tool(context);
      },
    ),
    HomePlugin(
      id: 'builtin_password_gen',
      title: '密码生成器',
      subtitle: '随机生成强密码，安全可靠',
      icon: Icons.vpn_key_outlined,
      color: Colors.red,
      area: HomePluginArea.center,
      builtIn: true,
      sort: 25,
      onTap: (context) async {
        await PluginToolbox.showPasswordGenerator(context);
      },
    ),
    HomePlugin(
      id: 'builtin_timestamp',
      title: '时间戳转换',
      subtitle: 'Unix 时间戳 ↔ 日期互转',
      icon: Icons.schedule_rounded,
      color: Colors.deepPurple,
      area: HomePluginArea.center,
      builtIn: true,
      sort: 30,
      onTap: (context) async {
        await PluginToolbox.showTimestampConverter(context);
      },
    ),
    HomePlugin(
      id: 'builtin_url_codec',
      title: 'URL 编解码',
      subtitle: 'URL 编码 / 解码转换工具',
      icon: Icons.link_rounded,
      color: Colors.indigo,
      area: HomePluginArea.center,
      builtIn: true,
      sort: 35,
      onTap: (context) async {
        await PluginToolbox.showUrlCodec(context);
      },
    ),
    HomePlugin(
      id: 'builtin_qrcode',
      title: '二维码生成',
      subtitle: '文本/链接一键生成二维码',
      icon: Icons.qr_code_2_rounded,
      color: Colors.blueGrey,
      area: HomePluginArea.center,
      builtIn: true,
      sort: 40,
      onTap: (context) async {
        await PluginToolbox.showQrCodeGenerator(context);
      },
    ),
    HomePlugin(
      id: 'builtin_quiz_entry',
      title: '录入题目',
      subtitle: '录入题目、选项、答案和解析',
      icon: Icons.edit_note_rounded,
      color: const Color(0xFF0891B2),
      area: HomePluginArea.center,
      builtIn: true,
      sort: 50,
      onTap: (context) async {
        final denial = await PluginGate.denial(
          PluginIds.quizEntry,
          feature: PluginFeature.entry,
          highRisk: false,
        );
        if (denial != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(denial)),
          );
          return;
        }
        if (!context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QuizEntryPage()),
        );
      },
    ),
    HomePlugin(
      id: 'builtin_quiz_bank_view',
      title: '题库查看',
      subtitle: '查看、复制、删除已录入题目',
      icon: Icons.library_books_outlined,
      color: const Color(0xFF7C3AED),
      area: HomePluginArea.center,
      builtIn: true,
      sort: 48,
      onTap: (context) async {
        final denial = await PluginGate.denial(
          PluginIds.quizBankView,
          feature: PluginFeature.view,
          highRisk: false,
        );
        if (denial != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(denial)),
          );
          return;
        }
        if (!context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QuizBankViewPage()),
        );
      },
    ),
    HomePlugin(
      id: 'builtin_quiz_plugin',
      title: '答题助手',
      subtitle: '捕获屏幕题目，自动搜索答案',
      icon: Icons.quiz_outlined,
      color: const Color(0xFF4F46E5),
      area: HomePluginArea.center,
      builtIn: true,
      sort: 46,
      onTap: (context) async {
        final denial = await PluginGate.denial(
          PluginIds.quizAnswer,
          highRisk: false,
        );
        if (denial != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(denial)),
          );
          // 仍打开配置页，但开关会被禁用
        }
        if (!context.mounted) return;
        await QuizPluginEntry.showConfigSheet(context);
      },
    ),
    HomePlugin(
      id: 'builtin_video_search',
      title: '公共影视搜索',
      subtitle: '合法免费片源检索',
      icon: Icons.video_collection_outlined,
      color: Colors.indigo,
      area: HomePluginArea.video,
      builtIn: true,
      sort: 10,
      onTap: (context) async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VideoListPage()),
        );
      },
    ),
    HomePlugin(
      id: 'builtin_comic_shelf',
      title: '漫画收藏',
      subtitle: '管理你的漫画收藏列表',
      icon: Icons.collections_bookmark_outlined,
      color: Colors.teal,
      area: HomePluginArea.comic,
      builtIn: true,
      sort: 10,
      onTap: (context) async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('漫画收藏')),
              body: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.collections_bookmark_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      '漫画功能将在后续版本上线',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
    HomePlugin(
      id: 'builtin_novel_search',
      title: '快速找书',
      subtitle: '进入小说列表页',
      icon: Icons.search,
      color: Colors.orange,
      area: HomePluginArea.novel,
      builtIn: true,
      sort: 8,
      onTap: (context) async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const NovelListPageWithProvider(),
          ),
        );
      },
    ),
    HomePlugin(
      id: 'builtin_image_generator',
      title: 'AI 生图',
      subtitle: '多模型、多方式 AI 图像生成',
      icon: Icons.auto_awesome_rounded,
      color: const Color(0xFF7C3AED),
      area: HomePluginArea.recommend,
      builtIn: true,
      sort: 5,
      onTap: (context) async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ImageGeneratorPage()),
        );
      },
    ),
    HomePlugin(
      id: 'builtin_service_monitor',
      title: '服务监控',
      subtitle: '各站点探针状态、延迟与可用率',
      icon: Icons.monitor_heart_outlined,
      color: const Color(0xFF0EA5E9),
      area: HomePluginArea.center,
      builtIn: true,
      sort: 60,
      onTap: (context) async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ServiceMonitorPage()),
        );
      },
    ),
    HomePlugin(
      id: 'builtin_server_ops',
      title: '服务器运维',
      subtitle: '主机指标 / 运维文件 / 终端',
      icon: Icons.terminal_rounded,
      color: const Color(0xFF334155),
      area: HomePluginArea.center,
      builtIn: true,
      sort: 58,
      onTap: (context) async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ServerOpsPage()),
        );
      },
    ),
    HomePlugin(
      id: 'builtin_plugin_help',
      title: '插件接入说明',
      subtitle: '查看注册方式与示例',
      icon: Icons.help_outline,
      color: Colors.blueGrey,
      area: HomePluginArea.center,
      builtIn: true,
      sort: 1,
      onTap: (context) async {
        await showDialog<void>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('插件接入说明'),
              content: const SelectableText(
                '可在任意模块中调用：\n\n'
                'HomePluginHost.instance.register(\n'
                '  HomePlugin(\n'
                "    id: 'my_plugin_id',\n"
                "    title: '我的插件',\n"
                "    subtitle: '一句描述',\n"
                '    icon: Icons.extension,\n'
                '    color: Colors.teal,\n'
                '    area: HomePluginArea.recommend,\n'
                '    onTap: (context) async { ... },\n'
                '  ),\n'
                ');\n',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('知道了'),
                ),
              ],
            );
          },
        );
      },
    ),
  ];
}
