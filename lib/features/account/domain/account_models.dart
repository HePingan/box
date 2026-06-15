class BoxAccountDefaults {
  const BoxAccountDefaults._();

  static const serverUrl = 'http://47.109.97.1:8799';
}

class BoxAccountUser {
  const BoxAccountUser({
    required this.id,
    required this.username,
    required this.role,
    required this.status,
    this.createdAt,
    this.lastLoginAt,
  });

  factory BoxAccountUser.fromJson(Map<String, dynamic> json) {
    return BoxAccountUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      status: json['status']?.toString() ?? 'normal',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      lastLoginAt: DateTime.tryParse(json['lastLoginAt']?.toString() ?? ''),
    );
  }

  final String id;
  final String username;
  final String role;
  final String status;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  bool get isAdmin => role == 'admin';

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'role': role,
    'status': status,
    'createdAt': createdAt?.toIso8601String(),
    'lastLoginAt': lastLoginAt?.toIso8601String(),
  };
}

class BoxAccountSession {
  const BoxAccountSession({
    required this.serverUrl,
    required this.token,
    required this.user,
  });

  final String serverUrl;
  final String token;
  final BoxAccountUser user;
}

class BoxAccountException implements Exception {
  const BoxAccountException(this.message, {this.statusCode, this.rawPreview});

  final String message;
  final int? statusCode;
  final String? rawPreview;

  @override
  String toString() => message;
}
