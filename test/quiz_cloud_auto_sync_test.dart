import 'package:box/features/quiz_plugin/data/quiz_cloud_auto_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('auto sync enabled flag defaults true and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final auto = QuizCloudAutoSync.instance;
    expect(await auto.isEnabled(), isTrue);
    await auto.setEnabled(false);
    expect(await auto.isEnabled(), isFalse);
    await auto.setEnabled(true);
    expect(await auto.isEnabled(), isTrue);
  });
}
