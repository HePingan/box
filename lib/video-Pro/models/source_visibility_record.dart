class SourceVisibilityRecord {
  final String key;
  final bool manualHidden;
  final bool autoHidden;
  final int failCount;
  final DateTime? lastCheckedAt;
  final String? lastReason;
  final bool? lastPlayable;

  const SourceVisibilityRecord({
    required this.key,
    this.manualHidden = false,
    this.autoHidden = false,
    this.failCount = 0,
    this.lastCheckedAt,
    this.lastReason,
    this.lastPlayable,
  });

  bool get isHidden => manualHidden || autoHidden;
  bool get isVisible => !isHidden;

  SourceVisibilityRecord copyWith({
    bool? manualHidden,
    bool? autoHidden,
    int? failCount,
    DateTime? lastCheckedAt,
    String? lastReason,
    bool? lastPlayable,
  }) {
    return SourceVisibilityRecord(
      key: key,
      manualHidden: manualHidden ?? this.manualHidden,
      autoHidden: autoHidden ?? this.autoHidden,
      failCount: failCount ?? this.failCount,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      lastReason: lastReason ?? this.lastReason,
      lastPlayable: lastPlayable ?? this.lastPlayable,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'manualHidden': manualHidden,
        'autoHidden': autoHidden,
        'failCount': failCount,
        'lastCheckedAt': lastCheckedAt?.toIso8601String(),
        'lastReason': lastReason,
        'lastPlayable': lastPlayable,
      };

  factory SourceVisibilityRecord.fromJson(Map<String, dynamic> json) {
    return SourceVisibilityRecord(
      key: json['key'] as String,
      manualHidden: json['manualHidden'] as bool? ?? false,
      autoHidden: json['autoHidden'] as bool? ?? false,
      failCount: json['failCount'] as int? ?? 0,
      lastCheckedAt: json['lastCheckedAt'] == null
          ? null
          : DateTime.tryParse(json['lastCheckedAt'] as String),
      lastReason: json['lastReason'] as String?,
      lastPlayable: json['lastPlayable'] as bool?,
    );
  }
}