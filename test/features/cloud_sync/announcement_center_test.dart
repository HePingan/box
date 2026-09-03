import 'package:box/features/cloud_sync/data/announcement_service.dart';
import 'package:box/features/cloud_sync/domain/announcement_center.dart';
import 'package:box/features/cloud_sync/domain/cloud_sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AnnouncementEntry entry(
  String id, {
  String level = 'info',
  bool pinned = false,
  DateTime? at,
}) {
  return AnnouncementEntry(
    id: id,
    title: 't-$id',
    body: 'b-$id',
    level: level,
    publishedAt: at ?? DateTime(2026, 1, 1),
    pinned: pinned,
    linkUrl: '',
  );
}

/// 假的公告服务：记录调用次数，避免测试打真网络。
class _FakeService extends AnnouncementService {
  _FakeService({
    required this.remote,
    required this.cached,
    this.throwOnLoad = false,
  }) : super(prefs: _prefs);

  static late SharedPreferences _prefs;

  final AnnouncementState remote;
  final AnnouncementState cached;
  final bool throwOnLoad;

  int loadCalls = 0;
  int cachedCalls = 0;
  final List<String> readMarks = [];

  @override
  Future<AnnouncementState> load({bool force = false}) async {
    loadCalls++;
    if (throwOnLoad) throw Exception('网络炸了');
    return remote;
  }

  @override
  Future<AnnouncementState> loadCachedOnly() async {
    cachedCalls++;
    return cached;
  }

  @override
  Future<Set<String>> markRead(String id) async {
    readMarks.add(id);
    return {...cached.readIds, id};
  }
}

AnnouncementState state(
  List<AnnouncementEntry> items, {
  Set<String> read = const {},
  DateTime? fetchedAt,
}) {
  return AnnouncementState(
    items: items,
    readIds: read,
    fetchedAt: fetchedAt,
    fromCache: false,
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _FakeService._prefs = await SharedPreferences.getInstance();
  });

  test('启动：先读缓存点亮红点，再立即打网络刷新', () async {
    final svc = _FakeService(
      remote: state([entry('a'), entry('b')]),
      cached: state([entry('a')], fetchedAt: null),
    );
    final center = AnnouncementCenter(service: svc);

    await center.bootstrap();

    expect(svc.cachedCalls, 1, reason: '应先读缓存，让红点在首帧就能亮');
    expect(svc.loadCalls, 1, reason: '缓存无 fetchedAt，应打网络');
    expect(center.unreadCount, 2);
    expect(center.hasUnread, isTrue);
  });

  test('启动：即使距上次拉取不足 6h，也打网络刷新', () async {
    final recent = DateTime.now().subtract(const Duration(hours: 1));
    final svc = _FakeService(
      remote: state([entry('a'), entry('b')]),
      cached: AnnouncementState(
        items: [entry('a')],
        readIds: const {},
        fetchedAt: recent,
        fromCache: true,
      ),
    );
    final center = AnnouncementCenter(service: svc);

    await center.bootstrap();

    expect(svc.loadCalls, 1, reason: '进入 App 必须刷新，不能被 6h 缓存挡住');
    expect(center.unreadCount, 2, reason: '应以网络结果覆盖缓存');
  });

  test('启动：网络失败静默降级，不抛给调用方，红点仍按缓存显示', () async {
    final svc = _FakeService(
      remote: AnnouncementState.empty,
      cached: state([entry('a')]),
      throwOnLoad: true,
    );
    final center = AnnouncementCenter(service: svc);

    await center.bootstrap();

    expect(center.unreadCount, 1);
    expect(center.lastError, isNotNull, reason: '错误应留痕便于排查');
  });

  test('弹窗：未读 warning 只交付一次，取走后不再交付', () async {
    final svc = _FakeService(
      remote: state([entry('w', level: 'warning', pinned: true)]),
      cached: AnnouncementState.empty,
    );
    final center = AnnouncementCenter(service: svc);
    await center.bootstrap();

    final first = center.takePopup();
    expect(first?.id, 'w');

    expect(center.takePopup(), isNull, reason: '同一次启动内不应重复弹，否则切 tab 就再弹一次');
  });

  test('弹窗：确认后写入已读，下次启动不再弹', () async {
    final svc = _FakeService(
      remote: state([entry('w', level: 'warning')]),
      cached: AnnouncementState.empty,
    );
    final center = AnnouncementCenter(service: svc);
    await center.bootstrap();

    final popup = center.takePopup();
    expect(popup, isNotNull);
    await center.acknowledge(popup!.id);

    expect(svc.readMarks, ['w'], reason: '应落库已读，跨启动生效');
    expect(center.hasUnread, isFalse);
  });

  test('弹窗：info 级不弹', () async {
    final svc = _FakeService(
      remote: state([entry('i', level: 'info')]),
      cached: AnnouncementState.empty,
    );
    final center = AnnouncementCenter(service: svc);
    await center.bootstrap();

    expect(center.takePopup(), isNull);
    expect(center.hasUnread, isTrue, reason: '不弹窗但红点仍要亮');
  });

  test('bootstrap 幂等：重复调用不重复打网络', () async {
    final svc = _FakeService(
      remote: state([entry('a')]),
      cached: AnnouncementState.empty,
    );
    final center = AnnouncementCenter(service: svc);

    await center.bootstrap();
    await center.bootstrap();

    expect(svc.loadCalls, 1);
  });
}
