/// 调试日志的分类维度。
///
/// 为什么要有它：改之前 App 里有**两套互不相通**的日志系统——
/// `AppLogger`（抽屉「更多 → 调试日志」，1000 行，JSON 持久化）和
/// `ReaderDebugLog`（阅读器里那个橙色虫子按钮，200 行，换行拼接持久化）。
/// 用户报障时只会截其中一个，另一半线索直接丢失；而 tag 又是各处手写的
/// 裸字符串（PLAYER / VISIBILITY / latest / FLUTTER …，其中 `latest` 明显
/// 是误传的参数值而不是分类），28 处调用干脆没传 tag 全落进默认 APP。
///
/// 所以分类不按「模块目录」切，而按**排障时会一起看的东西**切：用户报
/// 「视频卡」就只看 player，报「继续阅读跳错位置」就只看 reader，两边互不干扰。
enum LogChannel {
  /// 应用启动、生命周期、未归类的通用事件。
  system('SYSTEM', '系统'),

  /// 窗口尺寸 / 分屏 / DPI 变化等平台侧诊断（分屏问题排障靠它）。
  window('WINDOW', '窗口'),

  /// 视频播放器：起播、切源、缓冲、错误。
  player('PLAYER', '播放'),

  /// 影视目录、详情、接口拉取。
  video('VIDEO', '影视'),

  /// 小说阅读器：分页、进度保存与恢复（原 ReaderDebugLog 的去处）。
  reader('READER', '阅读'),

  /// 题库、答题插件、OCR。
  quiz('QUIZ', '题库'),

  /// 账号、额度、登录态。
  account('ACCOUNT', '账号'),

  /// 网络请求与更新检查。
  network('NETWORK', '网络'),

  /// 异常与错误。单独成类，便于「只看出错的」。
  error('ERROR', '错误');

  const LogChannel(this.tag, this.label);

  /// 写进日志行的标签，保持全大写英文，方便用户复制后我们直接 grep。
  final String tag;

  /// 给中文界面用的筛选器名字。
  final String label;

  /// 把历史遗留的裸 tag 归位到频道。
  ///
  /// 旧日志已经存在用户手机的 SharedPreferences 里，升级后仍要能正确筛选，
  /// 所以这里必须认得那些历史写法，而不是只认新枚举。
  static LogChannel fromTag(String? raw) {
    if (raw == null) return LogChannel.system;
    final normalized = raw.trim().toUpperCase();
    switch (normalized) {
      case 'PLAYER':
        return LogChannel.player;
      case 'VIDEO':
      case 'VISIBILITY':
      case 'COVER':
      case 'CATALOG':
      case 'VIDEO_CATALOG':
      case 'VIDEO_API':
      case 'DETAIL_FILL':
      case 'DETAIL_CTRL':
      case 'HISTORY':
        return LogChannel.video;
      case 'FLUTTER':
      case 'WINDOW':
        return LogChannel.window;
      case 'READER':
        return LogChannel.reader;
      case 'QUIZ':
        return LogChannel.quiz;
      case 'ACCOUNT':
        return LogChannel.account;
      case 'NETWORK':
      case 'UPDATE':
        return LogChannel.network;
      case 'ERROR':
      // app_bootstrap 的 PlatformDispatcher.onError 写的是 'DART'。
      // 这是未捕获异常的崩溃现场，必须能被「错误」频道筛到。
      case 'DART':
      case 'EXCEPTION':
        return LogChannel.error;
      case 'APP':
      case 'SYSTEM':
        return LogChannel.system;
      default:
        // `latest` 这类明显是把参数值当 tag 传进来的历史 bug，
        // 不丢弃、不新建分类，统一收进 system 兜底。
        return LogChannel.system;
    }
  }
}

/// 日志级别。分类之外再给一个正交维度：用户报障时先看 warn/error。
enum LogLevel {
  debug('D'),
  info('I'),
  warn('W'),
  error('E');

  const LogLevel(this.mark);

  final String mark;

  static LogLevel fromMark(String? raw) {
    switch (raw?.trim().toUpperCase()) {
      case 'E':
        return LogLevel.error;
      case 'W':
        return LogLevel.warn;
      case 'D':
        return LogLevel.debug;
      case 'I':
        return LogLevel.info;
      default:
        return LogLevel.info;
    }
  }
}

/// 一条已解析的日志。
///
/// 解析是尽力而为：认不出格式的旧行不丢弃，整行塞进 [message]，
/// 频道落到 system、级别落到 info。日志是排障证据，宁可显示得糙一点，
/// 也不能因为格式不合就吞掉。
class LogEntry {
  const LogEntry({
    required this.raw,
    required this.channel,
    required this.level,
    required this.message,
    this.timestamp,
  });

  final String raw;
  final LogChannel channel;
  final LogLevel level;
  final String message;
  final DateTime? timestamp;

  /// 同时兼容三种历史格式：
  /// - 新格式 `[时间戳][TAG][级别] 正文`
  /// - AppLogger 旧格式 `[时间戳][TAG] 正文`
  /// - ReaderDebugLog 旧格式 `[12:34:56.789] 正文`（无 tag）
  static LogEntry parse(String line, {LogChannel? fallbackChannel}) {
    final match = RegExp(
      r'^\[([^\]]*)\]\[([^\]]*)\](?:\[([^\]]*)\])?\s?(.*)$',
      dotAll: true,
    ).firstMatch(line);

    if (match != null) {
      return LogEntry(
        raw: line,
        channel: LogChannel.fromTag(match.group(2)),
        level: LogLevel.fromMark(match.group(3)),
        message: match.group(4) ?? '',
        timestamp: DateTime.tryParse(match.group(1) ?? ''),
      );
    }

    // 只有一个方括号的旧阅读器日志：没有 tag，靠调用方告知归属。
    final legacy = RegExp(
      r'^\[([^\]]*)\]\s?(.*)$',
      dotAll: true,
    ).firstMatch(line);
    if (legacy != null) {
      return LogEntry(
        raw: line,
        channel: fallbackChannel ?? LogChannel.system,
        level: LogLevel.info,
        message: legacy.group(2) ?? '',
        timestamp: DateTime.tryParse(legacy.group(1) ?? ''),
      );
    }

    return LogEntry(
      raw: line,
      channel: fallbackChannel ?? LogChannel.system,
      level: LogLevel.info,
      message: line,
    );
  }
}
