/// 单条生图用量记录（对应服务端 UsageRecord.toJson）。
class PersonalUsageRecord {
  const PersonalUsageRecord({
    required this.createdAt,
    required this.model,
    required this.cost,
    required this.success,
    this.statusCode,
    this.errorPreview = '',
  });

  factory PersonalUsageRecord.fromJson(Map<String, dynamic> json) =>
      PersonalUsageRecord(
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        model: json['model']?.toString() ?? '',
        cost: _asInt(json['cost']),
        success: json['success'] == true,
        statusCode: json['statusCode'] == null
            ? null
            : _asInt(json['statusCode']),
        errorPreview: json['errorPreview']?.toString() ?? '',
      );

  final DateTime? createdAt;
  final String model;
  final int cost;
  final bool success;
  final int? statusCode;
  final String errorPreview;

  String get modelLabel => model.isEmpty ? '未知模型' : model;

  /// `2026-08-15 09:24` 形式的本地时间，缺失时返回占位符。
  String get timeLabel {
    final value = createdAt;
    if (value == null) return '时间未知';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static int _asInt(Object? value) =>
      value is num ? value.round() : int.tryParse(value?.toString() ?? '') ?? 0;
}

class PersonalQuotaSummary {
  const PersonalQuotaSummary({
    required this.total,
    required this.totalCost,
    required this.totalSuccess,
    required this.totalFailed,
    required this.transactions,
    this.returned = 0,
  });

  factory PersonalQuotaSummary.fromJson(Map<String, dynamic> json) {
    // Server shape: { transactions: [...],
    //   summary: { total, returned, totalCost, totalSuccess, totalFailed } }
    final summary = (json['summary'] ?? json) as Map<String, dynamic>;
    final records = (json['transactions'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => PersonalUsageRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    // 旧版服务端没有 returned 字段，用实际条数兜底。
    final returned = summary.containsKey('returned')
        ? _asInt(summary['returned'])
        : records.length;
    return PersonalQuotaSummary(
      total: _asInt(summary['total']),
      totalCost: _asInt(summary['totalCost']),
      totalSuccess: _asInt(summary['totalSuccess']),
      totalFailed: _asInt(summary['totalFailed']),
      transactions: records,
      returned: returned,
    );
  }

  /// 过滤后的记录总数（未被 limit 截断）。
  final int total;

  /// 本次响应实际返回的条数。
  final int returned;
  final int totalCost;
  final int totalSuccess;
  final int totalFailed;
  final List<PersonalUsageRecord> transactions;

  bool get truncated => total > returned;

  static int _asInt(Object? value) =>
      value is num ? value.round() : int.tryParse(value?.toString() ?? '') ?? 0;
}

class PersonalActivityDay {
  const PersonalActivityDay({
    required this.date,
    required this.requests,
    required this.success,
    required this.cost,
  });

  factory PersonalActivityDay.fromJson(Map<String, dynamic> json) =>
      PersonalActivityDay(
        date: json['date']?.toString() ?? '',
        requests: _asInt(json['requests']),
        success: _asInt(json['success']),
        cost: _asInt(json['cost']),
      );

  final String date;
  final int requests;
  final int success;
  final int cost;

  static int _asInt(Object? value) =>
      value is num ? value.round() : int.tryParse(value?.toString() ?? '') ?? 0;
}

class PersonalQuizPage {
  const PersonalQuizPage({
    required this.questions,
    required this.total,
    required this.offset,
    required this.limit,
    required this.hasMore,
  });

  factory PersonalQuizPage.fromJson(Map<String, dynamic> json) {
    final items = (json['questions'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => PersonalQuizItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    return PersonalQuizPage(
      questions: items,
      total: _asInt(json['total']),
      offset: _asInt(json['offset']),
      limit: _asInt(json['limit']),
      hasMore: json['hasMore'] == true,
    );
  }

  final List<PersonalQuizItem> questions;
  final int total;
  final int offset;
  final int limit;
  final bool hasMore;

  static int _asInt(Object? value) =>
      value is num ? value.round() : int.tryParse(value?.toString() ?? '') ?? 0;
}

class PersonalPluginPage {
  const PersonalPluginPage({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
    required this.hasMore,
  });

  factory PersonalPluginPage.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map(
          (item) =>
              PersonalPluginItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
    return PersonalPluginPage(
      items: items,
      total: _asInt(json['total'] ?? json['count']),
      offset: _asInt(json['offset']),
      limit: _asInt(json['limit']),
      hasMore: json['hasMore'] == true,
    );
  }

  final List<PersonalPluginItem> items;
  final int total;
  final int offset;
  final int limit;
  final bool hasMore;

  static int _asInt(Object? value) =>
      value is num ? value.round() : int.tryParse(value?.toString() ?? '') ?? 0;
}

class PersonalPluginItem {
  const PersonalPluginItem({
    required this.id,
    required this.pluginId,
    required this.title,
    required this.subtitle,
    required this.version,
    required this.status,
    required this.permissions,
    required this.tags,
    required this.reviewNote,
    this.createdAt,
    this.reviewedAt,
  });

  factory PersonalPluginItem.fromJson(Map<String, dynamic> json) =>
      PersonalPluginItem(
        id: json['id']?.toString() ?? '',
        pluginId: json['pluginId']?.toString() ?? '',
        title: json['title']?.toString() ?? json['name']?.toString() ?? '',
        subtitle:
            json['subtitle']?.toString() ??
            json['description']?.toString() ??
            '',
        version: json['version']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending_review',
        permissions: _strings(json['permissions']),
        tags: _strings(json['tags']),
        reviewNote: json['reviewNote']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        reviewedAt: DateTime.tryParse(json['reviewedAt']?.toString() ?? ''),
      );

  final String id;
  final String pluginId;
  final String title;
  final String subtitle;
  final String version;
  final String status;
  final List<String> permissions;
  final List<String> tags;
  final String reviewNote;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  String get statusLabel => switch (status) {
    'published' || 'approved' => '已发布',
    'rejected' => '已拒绝',
    'yanked' => '已下架',
    'draft' => '草稿',
    _ => '审核中',
  };

  static List<String> _strings(Object? value) => value is List
      ? value
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
      : const [];
}

class PersonalQuizItem {
  const PersonalQuizItem({
    required this.id,
    required this.title,
    required this.status,
    this.createdAt,
    this.category = '',
    this.reviewNote = '',
    this.linkedQuestionId,
  });

  factory PersonalQuizItem.fromJson(Map<String, dynamic> json) {
    // Server returns: { id, question: {id, question, type, options, correctAnswer, analysis, category, source, status, revision, createdAt, updatedAt}, status, submittedAt, reviewNote, linkedQuestionId?, reviewedAt? }
    // or:          { id, question: 'string title', status, submittedAt, ... }
    final questionData = json['question'];
    final String questionText;
    final String category;
    if (questionData is Map<String, dynamic> &&
        questionData['question'] != null) {
      questionText = questionData['question'].toString();
      category = questionData['category']?.toString() ?? '';
    } else {
      questionText = questionData?.toString() ?? '';
      category = json['category']?.toString() ?? '';
    }
    return PersonalQuizItem(
      id: json['id']?.toString() ?? '',
      title: questionText,
      status: json['status']?.toString() ?? 'pending_review',
      createdAt: DateTime.tryParse(json['submittedAt']?.toString() ?? ''),
      category: category,
      reviewNote: json['reviewNote']?.toString() ?? '',
      linkedQuestionId: json['linkedQuestionId']?.toString(),
    );
  }

  final String id;
  final String title;
  final String status;
  final DateTime? createdAt;
  final String category;
  final String reviewNote;
  final String? linkedQuestionId;

  String get statusLabel => switch (status) {
    'published' || 'approved' => '已发布',
    'rejected' => '已拒绝',
    'draft' => '草稿',
    'merged' => '已合并',
    'pending' => '审核中',
    _ => '审核中',
  };
}

class PersonalOverview {
  const PersonalOverview({
    required this.user,
    required this.quota,
    required this.stats,
  });

  factory PersonalOverview.fromJson(Map<String, dynamic> json) {
    final quotaJson = json['quota'] as Map<String, dynamic>? ?? {};
    final statsJson = json['stats'] as Map<String, dynamic>? ?? {};
    final userJson = json['user'] as Map<String, dynamic>? ?? {};
    return PersonalOverview(
      user: PersonalUser.fromJson(userJson),
      quota: PersonalQuota.fromJson(quotaJson),
      stats: PersonalStats.fromJson(statsJson),
    );
  }

  final PersonalUser user;
  final PersonalQuota quota;
  final PersonalStats stats;
}

class PersonalQuota {
  const PersonalQuota({
    required this.remaining,
    required this.dailyLimit,
    required this.usedToday,
    this.totalLimit,
    this.status = 'normal',
    this.message = '',
  });

  factory PersonalQuota.fromJson(Map<String, dynamic> json) {
    int asInt(Object? value) {
      if (value is num) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return PersonalQuota(
      remaining: asInt(
        json['remaining'] ?? json['remainingQuota'] ?? json['quota'],
      ),
      dailyLimit: asInt(json['dailyLimit'] ?? json['dailyQuota']),
      usedToday: asInt(json['usedToday'] ?? json['dailyUsed'] ?? json['used']),
      totalLimit: json['totalLimit'] == null ? null : asInt(json['totalLimit']),
      status: json['status']?.toString() ?? 'normal',
      message: json['message']?.toString() ?? '',
    );
  }

  final int remaining;
  final int dailyLimit;
  final int usedToday;
  final int? totalLimit;
  final String status;
  final String message;

  int get used => (totalLimit ?? 0) - usedToday;
  double get progress {
    final total = totalLimit ?? dailyLimit;
    if (total <= 0) return 0;
    return (usedToday / total).clamp(0, 1).toDouble();
  }
}

class PersonalUser {
  const PersonalUser({
    required this.id,
    required this.username,
    this.nickname = '',
    required this.role,
    required this.status,
    this.createdAt,
    this.lastLoginAt,
  });

  factory PersonalUser.fromJson(Map<String, dynamic> json) => PersonalUser(
    id: json['id']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    // 服务端 toPublicJson 始终返回 nickname，旧数据兜底 username。
    nickname:
        json['nickname']?.toString() ?? json['username']?.toString() ?? '',
    role: json['role']?.toString() ?? 'user',
    status: json['status']?.toString() ?? 'normal',
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    lastLoginAt: DateTime.tryParse(json['lastLoginAt']?.toString() ?? ''),
  );

  final String id;
  final String username;
  final String nickname;
  final String role;
  final String status;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  /// 优先昵称，其次用户名。
  String get displayName => nickname.isNotEmpty ? nickname : username;

  PersonalUser copyWith({String? nickname, String? role, String? status}) =>
      PersonalUser(
        id: id,
        username: username,
        nickname: nickname ?? this.nickname,
        role: role ?? this.role,
        status: status ?? this.status,
        createdAt: createdAt,
        lastLoginAt: lastLoginAt,
      );
}

class PersonalStats {
  const PersonalStats({
    this.todayRequests = 0,
    this.todaySuccess = 0,
    this.todayCost = 0,
    this.mySubmissions = 0,
    this.myPendingSubmissions = 0,
    this.myMergedSubmissions = 0,
    this.myApprovedSubmissions = 0,
    this.publishedQuestions = 0,
  });

  factory PersonalStats.fromJson(Map<String, dynamic> json) => PersonalStats(
    todayRequests: _asInt(json['todayRequests']),
    todaySuccess: _asInt(json['todaySuccess']),
    todayCost: _asInt(json['todayCost']),
    mySubmissions: _asInt(json['mySubmissions']),
    myPendingSubmissions: _asInt(json['myPendingSubmissions']),
    myMergedSubmissions: _asInt(json['myMergedSubmissions']),
    myApprovedSubmissions: _asInt(json['myApprovedSubmissions']),
    publishedQuestions: _asInt(json['publishedQuestions']),
  );

  final int todayRequests;
  final int todaySuccess;
  final int todayCost;
  final int mySubmissions;
  final int myPendingSubmissions;
  final int myMergedSubmissions;
  final int myApprovedSubmissions;
  final int publishedQuestions;

  static int _asInt(Object? value) =>
      value is num ? value.round() : int.tryParse(value?.toString() ?? '') ?? 0;
}
