import '../data/announcement_service.dart';
import 'cloud_sync_models.dart';

/// 公告的启动拉取 / 红点 / 弹窗决策。
///
/// 抽成纯函数是为了能直接测：这套判断以前没有实现，导致公告实际上只在用户
/// 主动打开个人中心（抽屉 → 账号 → 个人中心，三层深）时才会拉一次 ——
/// 线上出故障时根本触达不到用户。
///
/// 计数与排序复用 [AnnouncementState] 已有的 unreadCount / hasUnread /
/// sorted，这里只补真正缺的两件事：启动节流与弹窗挑选。
class AnnouncementStartupPolicy {
  const AnnouncementStartupPolicy._();

  /// 启动拉取的最小间隔。调小 → 公告更及时但冷启动网络请求更频繁；
  /// 调大 → 更省流量但故障通知到达更慢。与书源同步的 6h 保持一致。
  static const Duration minFetchInterval = Duration(hours: 6);

  /// 启动时是否该打网络拉公告。
  ///
  /// 时钟回拨（now 早于 lastFetchedAt）也返回 true：否则用户改过系统时间后
  /// 会被永久卡住，再也收不到公告。
  static bool shouldFetch({
    required DateTime? lastFetchedAt,
    required DateTime now,
  }) {
    if (lastFetchedAt == null) return true;
    if (now.isBefore(lastFetchedAt)) return true;
    return now.difference(lastFetchedAt) >= minFetchInterval;
  }

  /// 未读条数。已读集合里可能残留已下线公告的 id，所以以当前列表为基准；
  /// id 为空的脏数据不计入，因为它的已读状态存不住。
  static int unreadCount(AnnouncementState state) {
    var count = 0;
    for (final item in state.items) {
      if (item.id.isEmpty) continue;
      if (!state.readIds.contains(item.id)) count++;
    }
    return count;
  }

  static bool hasUnread(AnnouncementState state) => unreadCount(state) > 0;

  /// 该弹窗提醒的那一条，没有则返回 null。
  ///
  /// 只弹 warning：info/notice 属于日常通知，弹窗会变成骚扰。
  /// 排序沿用 [AnnouncementState.sorted]（pinned 优先，再按发布时间倒序）。
  /// id 为空的脏数据直接跳过 —— markRead 存不住空 id，会导致反复弹。
  static AnnouncementEntry? popupCandidate(AnnouncementState state) {
    for (final item in state.sorted) {
      if (item.id.isEmpty) continue;
      if (item.level != 'warning') continue;
      if (state.readIds.contains(item.id)) continue;
      return item;
    }
    return null;
  }
}
