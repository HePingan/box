import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/backup/local_backup_codec.dart';

void main() {
  test('编码并解码完整备份，保留 Hive box 与题库', () {
    final raw = LocalBackupCodec.encode(
      quizJson: jsonEncode({'version': 2, 'items': []}),
      hiveBoxes: {
        'video_favorites_box': [
          {
            'key': 'source::1',
            'value': {'vodId': 1, 'vodName': '片名'},
          },
        ],
      },
    );

    final decoded = LocalBackupCodec.decode(raw);

    expect(
      decoded.hiveBoxes['video_favorites_box']!.single['key'],
      'source::1',
    );
    expect(jsonDecode(decoded.quizJson)['items'], isEmpty);
  });

  test('拒绝缺字段、错误版本和错误记录', () {
    expect(
      () => LocalBackupCodec.decode(
        jsonEncode({'format': 'wrong', 'version': 1}),
      ),
      throwsFormatException,
    );
    expect(
      () => LocalBackupCodec.decode(
        jsonEncode({
          'format': LocalBackupCodec.format,
          'version': 999,
          'quiz': {'items': []},
          'hive': {},
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => LocalBackupCodec.decode(
        jsonEncode({
          'format': LocalBackupCodec.format,
          'version': LocalBackupCodec.version,
          'quiz': {'items': []},
          'hive': {
            'x': [{}],
          },
        }),
      ),
      throwsFormatException,
    );
  });
}
