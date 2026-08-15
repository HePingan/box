import 'package:flutter_test/flutter_test.dart';

import 'package:box/features/account/domain/account_models.dart';

void main() {
  test('uses server nickname and persists it in account JSON', () {
    final user = BoxAccountUser.fromJson({
      'id': 'u_1',
      'username': 'login-name',
      'nickname': '展示昵称',
      'role': 'user',
      'status': 'normal',
    });

    expect(user.username, 'login-name');
    expect(user.nickname, '展示昵称');
    expect(user.toJson()['nickname'], '展示昵称');
  });

  test(
    'falls back to login username for existing sessions without nickname',
    () {
      final user = BoxAccountUser.fromJson({
        'id': 'u_1',
        'username': 'legacy-name',
        'role': 'user',
        'status': 'normal',
      });

      expect(user.nickname, 'legacy-name');
    },
  );
}
