import 'package:shared_preferences/shared_preferences.dart';

import '../data/legal_documents.dart';

/// 用户协议 / 隐私政策的同意状态。
///
/// 存的是**已同意的协议版本号**而不是 bool。用 bool 的话协议一旦改版，
/// 就再也没有人会重新同意，等于第一版之后的所有修改从未获得授权。
/// 存版本号后，把 [kLegalDocumentsVersion] +1 即可让所有人重新阅读并同意。
///
/// 老用户同样会被拦：本应用此前从未有过协议，没有任何人同意过，
/// 所以"已装着旧版的用户"和新装用户一视同仁 —— 这是需求明确要求的。
class LegalConsentStore {
  /// [currentVersion] 默认取全局的 [kLegalDocumentsVersion]，可注入是为了能测
  /// "协议改版后重新拦"这条路径：当前常量还是 1 时，写死常量的实现根本构造不出
  /// "已同意旧版"的状态（1-1=0 会被当成从未同意），最关键的分支就永远测不到。
  LegalConsentStore(this._prefs, {int? currentVersion})
      : currentVersion = currentVersion ?? kLegalDocumentsVersion;

  final SharedPreferences _prefs;

  /// 本次构建所要求的协议版本。
  final int currentVersion;

  /// 键名带 `_version` 后缀，是为了跟"可能存在的历史 bool 键"区分开。
  /// 本次是首个协议版本，不存在历史键，但保留这个命名习惯以免将来撞键。
  static const String prefsKey = 'legal_consent_accepted_version';

  /// 已同意的协议版本。从未同意过返回 0。
  int get acceptedVersion => _prefs.getInt(prefsKey) ?? 0;

  /// 是否需要展示协议闸门。
  ///
  /// 只要已同意版本低于当前版本就要拦 —— 涵盖"从未同意"和"协议已改版"两种情况。
  bool get needsConsent => acceptedVersion < currentVersion;

  /// 是否是「协议更新后的再次确认」而非首次同意。
  /// UI 据此把标题从"请阅读并同意"改成"协议已更新"，避免老用户以为应用重装了。
  bool get isReconsent => acceptedVersion > 0 && needsConsent;

  /// 记录同意。
  ///
  /// 写入失败（存储满、平台异常）时返回 false 而不是静默成功：
  /// 调用方若把失败当成功，用户下次启动会再次被拦，还不知道为什么。
  Future<bool> accept() async {
    try {
      return await _prefs.setInt(prefsKey, currentVersion);
    } catch (_) {
      return false;
    }
  }

  /// 仅供测试与排障使用：撤销同意，让闸门重新出现。
  Future<void> reset() async {
    try {
      await _prefs.remove(prefsKey);
    } catch (_) {
      // 撤销失败不影响任何用户可见行为，无需上报。
    }
  }
}
