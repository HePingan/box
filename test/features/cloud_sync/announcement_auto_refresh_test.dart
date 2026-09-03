import 'package:box/features/cloud_sync/data/announcement_service.dart';
import 'package:box/features/cloud_sync/domain/announcement_center.dart';
import 'package:box/features/cloud_sync/domain/cloud_sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AnnouncementEntry _entry(String id, {String level = 'info'}) =>
    AnnouncementEntry(
      id: id,
      title: 't-$id',
      body: 'b-$id',
      level: level,
      publishedAt: DateTime(2026, 9, 3),
      pinned: false,
      linkUrl: '',
    );

AnnouncementState _state(
  List<AnnouncementEntry> items, {
  DateTime? fetchedAt,
}) => AnnouncementState(
  items: items,
  readIds: const {},
  fetchedAt: fetchedAt,
  fromCache: false,
);

class _Service extends AnnouncementService {
  _Service({required this.cached, required this.remote}) : super(prefs: _prefs);

  static late SharedPreferences _prefs;
  final AnnouncementState cached;
  AnnouncementState remote;
  int networkCalls = 0;

  @override
  Future<AnnouncementState> load({bool force = false}) async {
    networkCalls++;
    return remote;
  }

  @override
  Future<AnnouncementState> loadCachedOnly() async => cached;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _Service._prefs = await SharedPreferences.getInstance();
  });

  test('进入 App：即使缓存不足 6 小时，也强制刷新并取得新 warning', () async {
    final service = _Service(
      cached: _state([
        _entry('old'),
      ], fetchedAt: DateTime.now().subtract(const Duration(minutes: 1))),
      remote: _state([_entry('new-warning', level: 'warning')]),
    );
    final center = AnnouncementCenter(service: service);

    await center.bootstrap();

    expect(service.networkCalls, 1, reason: '进入 App 不能被 6h 缓存挡住');
    expect(
      center.takePopup()?.id,
      'new-warning',
      reason: '刚拉到的未读重要提醒应立刻可供启动弹窗显示',
    );
  });

  test('回到前台：强制刷新后新 warning 可立即弹窗', () async {
    final service = _Service(
      cached: _state([_entry('old')]),
      remote: _state([_entry('still-normal')]),
    );
    final center = AnnouncementCenter(service: service);
    await center.bootstrap();
    expect(center.takePopup(), isNull, reason: '启动时没有重要提醒不应弹窗');

    service.remote = _state([_entry('foreground-warning', level: 'warning')]);
    await center.refresh();

    expect(service.networkCalls, 2, reason: '回前台必须绕开缓存检查新公告');
    expect(center.takePopup()?.id, 'foreground-warning');
  });
}
