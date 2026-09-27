// 网页源码获取的真实端到端验证：用真取数（http 包）连一台真服务器。
//
// 为什么要这条：单测里的取数是假的，只能证明「逻辑对」；要证明「真机上会好」
// 必须让生产实现（IoSourceFetch）真发一次请求。默认不随 `flutter test` 跑
// （带 `live` 标签），CI 用 `--exclude-tags live` 排除。
@Tags(['live'])
@Timeout(Duration(minutes: 2))
library;

import 'package:box/features/tools/presentation/source_fetch_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('真连自家发布接口：拿到 200 与真实内容', () async {
    final r = await IoSourceFetch().fetch(
      'https://box.hpa888.top/updates/box/android/release/version.json',
    );

    expect(r.error, isNull, reason: '真机不该连不上自家接口：${r.error}');
    expect(r.statusCode, 200);
    expect(r.bytes, isNotEmpty);
    expect(
      r.text,
      contains('latestVersionCode'),
      reason: '拿到的是发布接口的 JSON，说明真的取到了服务端第一手文本',
    );
  });

  test('反面：解析不了的域名要给出可读原因', () async {
    final r = await IoSourceFetch().fetch(
      'https://nope-does-not-exist-9f3a.invalid/x',
    );

    expect(r.error, isNotNull, reason: '这个域名不该连上');
    expect(r.bytes, isEmpty);
    expect(
      r.error!.isNotEmpty,
      isTrue,
      reason: '原因必须是给人看的文字，不能是空串',
    );
  });
}
