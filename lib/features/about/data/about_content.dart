/// 关于页的静态文案：软件介绍、使用文档、推荐教程。
///
/// 全部集中在这一个文件，是为了避免同一段介绍在弹窗、关于页、应用商店描述里
/// 各写一份然后互相不一致 —— 之前「关于」就因为抽屉和个人中心各有一份实现，
/// 应用名都写得不一样（见 test/ui/about_entry_single_source_test.dart）。
///
/// 写作纪律（重要）：这里只允许写**代码里真实存在**的功能和真实的入口路径。
/// 不写宣传语，也不写"计划中"的能力。初稿里曾写过「投屏」和「音量键下双击停止
/// 播放」，回读代码发现前者项目里根本没有、后者是答题悬浮窗的交互而非播放器，
/// 已删除 —— 关于页是用户查功能的地方，写错等于骗人。
/// 增删功能时这个文件要跟着改，`about_content_accuracy_test.dart` 会盯住
/// 文案里提到的入口名是否还与真实代码一致。
library;

/// 一个「文档小节」：标题 + 若干段落 + 若干条目。
class AboutSection {
  const AboutSection({
    required this.title,
    this.paragraphs = const [],
    this.bullets = const [],
  });

  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
}

/// 推荐教程条目。
///
/// [url] 为空表示「暂无外部链接」，UI 显示为纯说明文字，不做成可点的假链接。
class TutorialEntry {
  const TutorialEntry({
    required this.title,
    required this.description,
    this.url,
  });

  final String title;
  final String description;
  final String? url;

  bool get hasLink => url != null && url!.isNotEmpty;
}

class AboutContent {
  const AboutContent._();

  static const String appName = 'Geek工具箱 Pro';
  static const String tagline = '智能工具集，为极客而生。';
  static const String repoUrl = 'https://github.com/HePingan/box';
  static const String issuesUrl = 'https://github.com/HePingan/box/issues';

  /// 关于页页脚。刻意简短且不含承诺性措辞（"最好用""永久免费"这类），
  /// 页脚是最容易被顺手写成宣传语的地方。
  static const String disclaimerShort =
      '本应用为个人开发的工具集，不内置任何内容资源。\n'
      '内容源由用户自行添加，其合法性由来源方与使用者负责。';

  // ─── 软件介绍 ───

  static const List<AboutSection> introduction = [
    AboutSection(
      title: '这是什么',
      paragraphs: [
        '$appName 是一个把常用功能聚到一处的 Android 应用：影视、小说、题库、'
            '插件市场都在同一个入口里，不用在多个 App 之间来回切。',
        '应用不内置任何内容资源。影视与小说的内容来自你自己添加或启用的第三方'
            '内容源，应用只负责解析与呈现，不对第三方内容负责。',
      ],
    ),
    AboutSection(
      title: '主要功能',
      bullets: [
        '影视：内容源检索、播放（支持倍速、选集）与下载缓存',
        '小说：书架、阅读器、分页与阅读进度记忆',
        '题库：题目导入、练习与错题回顾，支持答题辅助插件',
        '插件市场：投稿、审核、安装插件',
        '个人中心：账号、额度与云同步',
        '备份与恢复：导出或导入收藏、书架、阅读进度、本地题库',
      ],
    ),
    AboutSection(
      title: '关于更新',
      paragraphs: [
        '应用未上架应用商店，通过内置的更新服务分发。「检查更新」会连接更新'
            '服务，安装包在下载后会做完整性与签名校验，校验不通过不会安装。',
      ],
    ),
  ];

  // ─── 使用文档 ───

  static const List<AboutSection> usageDocs = [
    AboutSection(
      title: '开始使用',
      bullets: [
        '侧边栏是主入口：从左侧边缘右滑，或点左上角菜单按钮打开',
        '首屏优先展示收藏库，内容入口可折叠收起',
        '默认行为可在「侧边栏 → 设置」里调整',
      ],
    ),
    AboutSection(
      title: '影视',
      bullets: [
        '播放页支持倍速与选集切换',
        '需要离线看的剧集可以下载缓存，进度在下载面板里查看',
      ],
    ),
    AboutSection(
      title: '小说',
      bullets: [
        '先在「侧边栏 → 书源管理」里添加或启用书源，之后才能检索',
        '阅读器可调字号、行距与翻页方式，也可开启音量键翻页',
        '中断后继续阅读会回到上次的位置',
      ],
    ),
    AboutSection(
      title: '题库与插件',
      bullets: [
        '题库以「题干 + 选项」作为题目标识，重复导入不会产生重复题',
        '答题辅助插件需要在系统设置里授予悬浮窗与无障碍权限',
        '插件从插件市场安装，流程是投稿 → 审核 → 安装',
      ],
    ),
    AboutSection(
      title: '备份与恢复',
      paragraphs: [
        '收藏、书架、阅读进度与本地题库可以整体导出成一个文件，在新设备上导入'
            '即可恢复。入口：侧边栏 → 备份与恢复。',
      ],
    ),
    AboutSection(
      title: '出问题怎么办',
      paragraphs: [
        '遇到异常时打开「调试日志」，勾选「仅看警告与错误」，把内容复制出来'
            '连同操作步骤、机型与系统版本一起反馈，比只描述现象更容易定位问题。',
      ],
      bullets: [
        '调试日志入口：侧边栏 → 调试日志，或关于页 → 调试日志',
        '反馈渠道：GitHub Issues（侧边栏 → 反馈，可复制地址）',
      ],
    ),
  ];

  // ─── 推荐教程 ───
  //
  // 刻意不放外部第三方教程链接：链接会失效，也无法保证第三方内容质量。
  // 这里只指向应用内真实存在的功能路径，路径都跟真实入口名对齐。

  static const List<TutorialEntry> tutorials = [
    TutorialEntry(
      title: '添加第一个书源',
      description: '小说需要先有书源才能检索。'
          '路径：侧边栏 → 书源管理 → 添加，填入源地址后启用。',
    ),
    TutorialEntry(
      title: '让答题辅助插件跑起来',
      description: '插件需要悬浮窗与无障碍权限。'
          '路径：插件市场安装插件 → 按提示授予两项权限 → 在插件设置里启用。',
    ),
    TutorialEntry(
      title: '换机迁移不丢数据',
      description: '收藏、书架、阅读进度与本地题库可整体导出。'
          '路径：侧边栏 → 备份与恢复 → 导出，把文件拷到新设备后导入。',
    ),
    TutorialEntry(
      title: '报障时怎么提供有效信息',
      description: '复现问题后立刻打开「侧边栏 → 调试日志」，'
          '勾「仅看警告与错误」再复制，附上机型与系统版本。',
    ),
    TutorialEntry(
      title: '项目源码与问题反馈',
      description: '源码托管在 GitHub，功能建议与缺陷都在 Issues 里提。',
      url: issuesUrl,
    ),
  ];
}
