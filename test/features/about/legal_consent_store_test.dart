import 'package:box/features/about/data/legal_documents.dart';
import 'package:box/features/about/domain/legal_consent_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 同意状态必须是**版本化**的。
///
/// 这一组测试锁死的是需求里最容易被"简化"掉的一点：存 bool 看起来够用，
/// 但协议改版后 bool 永远是 true，再没有人会重新同意 —— 第一版之后的所有
/// 修改都拿不到用户授权。所以「协议版本号提升后必须重新拦」这条要有测试盯着。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<LegalConsentStore> store([Map<String, Object>? initial]) async {
    SharedPreferences.setMockInitialValues(initial ?? {});
    return LegalConsentStore(await SharedPreferences.getInstance());
  }

  test('全新用户必须被拦', () async {
    final s = await store();
    expect(s.acceptedVersion, 0);
    expect(s.needsConsent, isTrue);
    expect(s.isReconsent, isFalse, reason: '首次同意不该显示"协议已更新"');
  });

  test('老用户（装着旧版、从未同意过协议）同样被拦', () async {
    // 模拟一个有大量既有数据、但没有同意记录的老用户。
    final s = await store({
      'video_app_debug_logs_v2': '[]',
      'some_existing_user_data': 'x',
    });
    expect(
      s.needsConsent,
      isTrue,
      reason: '本应用此前没有协议，老用户也从未同意过，必须一视同仁',
    );
  });

  test('同意后不再被拦', () async {
    final s = await store();
    expect(await s.accept(), isTrue);
    expect(s.acceptedVersion, kLegalDocumentsVersion);
    expect(s.needsConsent, isFalse);
  });

  test('同意状态跨实例保持（真的写进了存储）', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await LegalConsentStore(prefs).accept();

    // 重新拿一次实例，模拟下次启动
    final again = LegalConsentStore(await SharedPreferences.getInstance());
    expect(again.needsConsent, isFalse);
  });

  test('协议版本提升后重新拦，并标记为"再次确认"', () async {
    // 已同意第 1 版，而这次构建要求第 2 版。
    // 注入 currentVersion 而不是依赖全局常量：常量现在是 1，用 1-1=0 构造
    // 不出"同意过旧版"的状态（会被当成从未同意），这条分支就测不到了。
    SharedPreferences.setMockInitialValues({
      LegalConsentStore.prefsKey: 1,
    });
    final s = LegalConsentStore(
      await SharedPreferences.getInstance(),
      currentVersion: 2,
    );

    expect(
      s.needsConsent,
      isTrue,
      reason: '这是存版本号而非 bool 的全部意义所在',
    );
    expect(
      s.isReconsent,
      isTrue,
      reason: '老用户应看到"协议已更新"，而不是像第一次装一样的措辞',
    );
  });

  test('已同意版本高于当前版本（降级安装）时不重复拦', () async {
    final s = await store({
      LegalConsentStore.prefsKey: kLegalDocumentsVersion + 5,
    });
    expect(
      s.needsConsent,
      isFalse,
      reason: '装回旧版不该再拦一次，用户已经同意过更新的条款',
    );
  });

  test('reset 后重新需要同意（排障用）', () async {
    final s = await store();
    await s.accept();
    expect(s.needsConsent, isFalse);

    await s.reset();
    expect(s.needsConsent, isTrue);
    expect(s.acceptedVersion, 0);
  });

  test('协议版本号必须是正数，否则闸门永不生效', () {
    expect(kLegalDocumentsVersion, greaterThan(0));
  });
}
