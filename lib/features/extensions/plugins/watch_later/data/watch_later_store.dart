/// 稍后看的存储接缝 + 远程存储实现。
///
/// 接缝存在的理由与便签一致：页面要能在 widget 测试里跑完整流程
/// （添加 → 列表 → 去重 → 删除），真实现会连 WebDAV、写临时文件、碰 prefs。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../remote_storage/application/remote_storage_service.dart';
import '../../remote_storage/application/remote_text_file.dart';
import '../../remote_storage/domain/remote_storage_models.dart';
import '../domain/watch_later_item.dart';

abstract class WatchLaterStore {
  Future<List<RemoteStorageAccount>> accounts();

  Future<String?> lastAccountId();

  Future<void> rememberAccount(String accountId);

  /// 读清单（文件不存在 = 空清单，不是错误）。
  Future<List<WatchLaterItem>> load(RemoteStorageAccount account);

  Future<void> save(
    RemoteStorageAccount account,
    List<WatchLaterItem> items,
  );
}

/// 走远程存储的清单文件（`box-watchlist/watch-later.json`）。
class WebdavWatchLaterStore implements WatchLaterStore {
  WebdavWatchLaterStore({
    RemoteStorageService? service,
    RemoteTextFile? textFile,
  }) : _service = service ?? remoteStorageService() {
    _textFile = textFile ?? RemoteTextFile(service: _service);
  }

  final RemoteStorageService _service;
  late final RemoteTextFile _textFile;

  static const String _prefsKey = 'watch_later_account_id';

  @override
  Future<List<RemoteStorageAccount>> accounts() => _service.loadAccounts();

  @override
  Future<String?> lastAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
  }

  @override
  Future<void> rememberAccount(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, accountId);
  }

  @override
  Future<List<WatchLaterItem>> load(RemoteStorageAccount account) async {
    final raw = await _textFile.read(account, kWatchLaterPath);
    return parseWatchLaterDoc(raw);
  }

  @override
  Future<void> save(
    RemoteStorageAccount account,
    List<WatchLaterItem> items,
  ) async {
    await _textFile.write(account, kWatchLaterPath, encodeWatchLaterDoc(items));
  }
}

/// 内存实现（进程内有效，不落盘不联网），给 widget 测试与调试用。
class InMemoryWatchLaterStore implements WatchLaterStore {
  InMemoryWatchLaterStore({
    List<RemoteStorageAccount>? accounts,
    List<WatchLaterItem>? seed,
  })  : _accounts = accounts ?? const [],
        _items = [...?seed];

  final List<RemoteStorageAccount> _accounts;
  List<WatchLaterItem> _items;
  String? _lastAccountId;

  @override
  Future<List<RemoteStorageAccount>> accounts() async => _accounts;

  @override
  Future<String?> lastAccountId() async => _lastAccountId;

  @override
  Future<void> rememberAccount(String accountId) async {
    _lastAccountId = accountId;
  }

  @override
  Future<List<WatchLaterItem>> load(RemoteStorageAccount account) async =>
      [..._items];

  @override
  Future<void> save(
    RemoteStorageAccount account,
    List<WatchLaterItem> items,
  ) async {
    _items = [...items];
  }
}
