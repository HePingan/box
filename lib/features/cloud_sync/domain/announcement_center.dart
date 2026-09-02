import 'package:flutter/foundation.dart';

import '../data/announcement_service.dart';
import 'announcement_startup_policy.dart';
import 'cloud_sync_models.dart';

/// App 级公告中心。
///
/// 为什么需要它：公告以前只由 PersonalCenterController 持有，而那个 controller
/// 是个人中心页 create 出来的 —— 页面不打开就没有对象，公告既不会拉、红点也
/// 不会亮。线上 183/184/185 更新验签事故时，公告发出去了却没人看得到，就是
/// 因为入口埋在「抽屉 → 账号 → 个人中心」三层之下。
///
/// 这个类挂在 app 作用域，启动后台拉一次，供任意位置读红点/弹窗。
class AnnouncementCenter extends ChangeNotifier {
  AnnouncementCenter({AnnouncementService? service})
      : _service = service ?? AnnouncementService();

  final AnnouncementService _service;

  AnnouncementState _state = AnnouncementState.empty;
  AnnouncementState get state => _state;

  bool _bootstrapped = false;
  bool _popupDelivered = false;

  /// 最近一次拉取的错误，仅用于排查；失败不打断启动。
  Object? lastError;

  int get unreadCount => AnnouncementStartupPolicy.unreadCount(_state);
  bool get hasUnread => AnnouncementStartupPolicy.hasUnread(_state);

  /// 启动流程：先读本地缓存让红点在首帧就能亮，再按节流决定是否打网络。
  /// 幂等 —— 重复调用不会重复打网络。
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    try {
      final cached = await _service.loadCachedOnly();
      if (cached.items.isNotEmpty) {
        _state = cached;
        notifyListeners();
      }

      if (!AnnouncementStartupPolicy.shouldFetch(
        lastFetchedAt: cached.fetchedAt,
        now: DateTime.now(),
      )) {
        return;
      }

      _state = await _service.load();
      notifyListeners();
    } catch (e) {
      // 公告拉取失败不能影响启动，留痕即可。
      lastError = e;
    }
  }

  /// 取出该弹窗的那一条；同一次启动内只交付一次，避免切 tab 反复弹。
  AnnouncementEntry? takePopup() {
    if (_popupDelivered) return null;
    final candidate = AnnouncementStartupPolicy.popupCandidate(_state);
    if (candidate == null) return null;
    _popupDelivered = true;
    return candidate;
  }

  /// 用户看过之后写入已读，跨启动生效。
  Future<void> acknowledge(String id) async {
    if (id.isEmpty) return;
    final ids = await _service.markRead(id);
    _state = AnnouncementState(
      items: _state.items,
      readIds: ids,
      fetchedAt: _state.fetchedAt,
      fromCache: _state.fromCache,
    );
    notifyListeners();
  }

  /// 手动刷新（下拉等场景），绕过节流。
  Future<void> refresh() async {
    try {
      _state = await _service.load(force: true);
      lastError = null;
      notifyListeners();
    } catch (e) {
      lastError = e;
      notifyListeners();
    }
  }
}
