class PersonalQuotaSummary {
  const PersonalQuotaSummary({
    required this.total,
    required this.totalCost,
    required this.totalSuccess,
    required this.totalFailed,
    required this.transactions,
  });

  factory PersonalQuotaSummary.fromJson(Map<String, dynamic> json) {
    // Server wraps data under 'summary' key: { transactions: [...], summary: { total, totalCost, totalSuccess, totalFailed } }
    final summary = (json['summary'] ?? json) as Map<String, dynamic>;
    return PersonalQuotaSummary(
      total: _asInt(summary['total']),
      totalCost: _asInt(summary['totalCost']),
      totalSuccess: _asInt(summary['totalSuccess']),
      totalFailed: _asInt(summary['totalFailed']),
      transactions: (json['transactions'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false),
    );
  }

  final int total;
  final int totalCost;
  final int totalSuccess;
  final int totalFailed;
  final List<Map<String, dynamic>> transactions;

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
      limit: _asInt(json['limit']),
      hasMore: json['hasMore'] == true,
    );
  }

  final List<PersonalQuizItem> questions;
  final int total;
  final int limit;
  final bool hasMore;

  static int _asInt(Object? value) =>
      value is num ? value.round() : int.tryParse(value?.toString() ?? '') ?? 0;
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
    if (questionData is Map<String, dynamic> && questionData['question'] != null) {
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
    required this.role,
    required this.status,
    this.createdAt,
    this.lastLoginAt,
  });

  factory PersonalUser.fromJson(Map<String, dynamic> json) => PersonalUser(
    id: json['id']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    role: json['role']?.toString() ?? 'user',
    status: json['status']?.toString() ?? 'normal',
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    lastLoginAt: DateTime.tryParse(json['lastLoginAt']?.toString() ?? ''),
  );

  final String id;
  final String username;
  final String role;
  final String status;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
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
