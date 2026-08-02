enum VideoDownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

extension VideoDownloadStatusValue on VideoDownloadStatus {
  String get value => name;

  static VideoDownloadStatus parse(Object? value) {
    return VideoDownloadStatus.values.firstWhere(
      (item) => item.name == value?.toString(),
      orElse: () => VideoDownloadStatus.queued,
    );
  }
}

class VideoDownloadTask {
  const VideoDownloadTask({
    required this.id,
    required this.sourceId,
    required this.vodId,
    required this.vodName,
    required this.vodPic,
    required this.sourceName,
    required this.episodeName,
    required this.mediaUrl,
    required this.createdAt,
    this.referer = '',
    this.status = VideoDownloadStatus.queued,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.downloadSpeedBytesPerSecond = 0,
    this.localPath = '',
    this.errorMessage = '',
    this.isPlaybackActive = false,
    this.updatedAt,
  });

  final String id;
  final String sourceId;
  final String vodId;
  final String vodName;
  final String vodPic;
  final String sourceName;
  final String episodeName;

  /// Kept only in local persistence so the native worker can resume a task.
  final String mediaUrl;
  final String referer;
  final VideoDownloadStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final int downloadSpeedBytesPerSecond;
  final String localPath;
  final String errorMessage;
  final bool isPlaybackActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isPlayableOffline =>
      status == VideoDownloadStatus.completed && localPath.trim().isNotEmpty;

  double get progress {
    if (totalBytes <= 0) return status == VideoDownloadStatus.completed ? 1 : 0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  double get downloadPercent {
    if (status == VideoDownloadStatus.completed) return 1.0;
    if (totalBytes <= 0) return 0.0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  String get sizeLabel {
    if (totalBytes > 0) {
      return '${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)}';
    }
    return downloadedBytes > 0 ? _formatBytes(downloadedBytes) : '';
  }

  String get remainingTimeLabel {
    if (status == VideoDownloadStatus.completed) return '已完成';
    final remainingBytes = totalBytes - downloadedBytes;
    if (remainingBytes <= 0 || downloadSpeedBytesPerSecond <= 0) {
      return '剩余时间计算中…';
    }
    final seconds = (remainingBytes / downloadSpeedBytesPerSecond).ceil();
    if (seconds < 60) return '预计剩余 ${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '预计剩余 $minutes分${seconds % 60}s';
    final hours = minutes ~/ 60;
    return '预计剩余 $hours时${minutes % 60}分';
  }

  String _formatBytes(int bytes) {
    const unit = 'B';
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(1)}G$unit';
    }
    if (bytes >= 1048576) {
      return '${(bytes / 1048576).toStringAsFixed(1)}M$unit';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)}K$unit';
    }
    return '$bytes$unit';
  }

  String get speedLabel {
    final bytesPerSecond = downloadSpeedBytesPerSecond;
    if (bytesPerSecond <= 0) return '计算中…';
    if (bytesPerSecond >= 1073741824) {
      return '${(bytesPerSecond / 1073741824).toStringAsFixed(1)} GB/s';
    }
    if (bytesPerSecond >= 1048576) {
      return '${(bytesPerSecond / 1048576).toStringAsFixed(1)} MB/s';
    }
    if (bytesPerSecond >= 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
    }
    return '$bytesPerSecond B/s';
  }

  VideoDownloadTask copyWith({
    String? sourceName,
    String? episodeName,
    VideoDownloadStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    int? downloadSpeedBytesPerSecond,
    String? localPath,
    String? errorMessage,
    bool? isPlaybackActive,
    DateTime? updatedAt,
  }) {
    return VideoDownloadTask(
      id: id,
      sourceId: sourceId,
      vodId: vodId,
      vodName: vodName,
      vodPic: vodPic,
      sourceName: sourceName ?? this.sourceName,
      episodeName: episodeName ?? this.episodeName,
      mediaUrl: mediaUrl,
      referer: referer,
      status: status ?? this.status,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadSpeedBytesPerSecond:
          downloadSpeedBytesPerSecond ?? this.downloadSpeedBytesPerSecond,
      localPath: localPath ?? this.localPath,
      errorMessage: errorMessage ?? this.errorMessage,
      isPlaybackActive: isPlaybackActive ?? this.isPlaybackActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'sourceId': sourceId,
    'vodId': vodId,
    'vodName': vodName,
    'vodPic': vodPic,
    'sourceName': sourceName,
    'episodeName': episodeName,
    'mediaUrl': mediaUrl,
    'referer': referer,
    'status': status.value,
    'downloadedBytes': downloadedBytes,
    'totalBytes': totalBytes,
    'downloadSpeedBytesPerSecond': downloadSpeedBytesPerSecond,
    'localPath': localPath,
    'errorMessage': errorMessage,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  /// Safe for logs, UI diagnostics and bug reports. Never includes source URL,
  /// referer, local filesystem path or server error details.
  Map<String, dynamic> toSafeMap() => {
    'id': id,
    'sourceId': sourceId,
    'vodId': vodId,
    'vodName': vodName,
    'sourceName': sourceName,
    'episodeName': episodeName,
    'status': status.value,
    'downloadedBytes': downloadedBytes,
    'totalBytes': totalBytes,
    'createdAt': createdAt.toIso8601String(),
  };

  factory VideoDownloadTask.fromMap(Map<dynamic, dynamic> raw) {
    int asInt(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    return VideoDownloadTask(
      id: raw['id']?.toString() ?? '',
      sourceId: raw['sourceId']?.toString() ?? '',
      vodId: raw['vodId']?.toString() ?? '',
      vodName: raw['vodName']?.toString() ?? '',
      vodPic: raw['vodPic']?.toString() ?? '',
      sourceName: raw['sourceName']?.toString() ?? '',
      episodeName: raw['episodeName']?.toString() ?? '',
      mediaUrl: raw['mediaUrl']?.toString() ?? '',
      referer: raw['referer']?.toString() ?? '',
      status: VideoDownloadStatusValue.parse(raw['status']),
      downloadedBytes: asInt(raw['downloadedBytes']),
      totalBytes: asInt(raw['totalBytes']),
      downloadSpeedBytesPerSecond: asInt(raw['downloadSpeedBytesPerSecond']),
      localPath: raw['localPath']?.toString() ?? '',
      errorMessage: raw['errorMessage']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(raw['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(raw['updatedAt']?.toString() ?? ''),
    );
  }
}
