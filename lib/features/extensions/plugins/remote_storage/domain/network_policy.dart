/// 传输的网络条件策略（287 P1）。
///
/// 纯逻辑、**不依赖 dart:io / Flutter**：解析与判定都能直接跑单测。
/// 判定立场是「**拿不准就当不能传**」——未知网络按移动网络对待、读不到网络状态
/// 按未知对待，宁可让用户点一下"仍要传"，也不要在不知情的移动网络上跑掉几百兆。
library;

/// 当前网络类型。原生侧只上报类型，**做什么决定由 Dart 侧策略定**。
enum NetworkKind {
  wifi,
  mobile,
  ethernet,

  /// 完全没有网络（原生明确说没有可用网络）。
  none,

  /// 未知/其它（VPN、读不到、原生报了个没见过的值）。
  other,
}

/// 三档策略。
enum TransferNetworkPolicy {
  /// 只在 Wi-Fi/以太网上传（默认）。
  wifiOnly,

  /// 移动网络上先问一次。
  askEachTime,

  /// 任何网络都传。
  allowAll,
}

const String kNetworkKindWifi = 'wifi';
const String kNetworkKindMobile = 'mobile';
const String kNetworkKindEthernet = 'ethernet';
const String kNetworkKindNone = 'none';

/// 原生字符串 → 枚举。**没有默认成 wifi 这一说**：不认识的一律 [NetworkKind.other]。
NetworkKind networkKindFromName(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case kNetworkKindWifi:
      return NetworkKind.wifi;
    case kNetworkKindMobile:
      return NetworkKind.mobile;
    case kNetworkKindEthernet:
      return NetworkKind.ethernet;
    case kNetworkKindNone:
      return NetworkKind.none;
    default:
      return NetworkKind.other;
  }
}

String networkKindName(NetworkKind kind) {
  switch (kind) {
    case NetworkKind.wifi:
      return kNetworkKindWifi;
    case NetworkKind.mobile:
      return kNetworkKindMobile;
    case NetworkKind.ethernet:
      return kNetworkKindEthernet;
    case NetworkKind.none:
      return kNetworkKindNone;
    case NetworkKind.other:
      return 'other';
  }
}

/// 落盘字符串 → 策略；不认识的一律回默认 [TransferNetworkPolicy.wifiOnly]。
TransferNetworkPolicy networkPolicyFromName(String? raw) {
  switch ((raw ?? '').trim()) {
    case 'allowAll':
      return TransferNetworkPolicy.allowAll;
    case 'askEachTime':
      return TransferNetworkPolicy.askEachTime;
    case 'wifiOnly':
      return TransferNetworkPolicy.wifiOnly;
    default:
      return TransferNetworkPolicy.wifiOnly;
  }
}

String networkPolicyName(TransferNetworkPolicy policy) {
  switch (policy) {
    case TransferNetworkPolicy.wifiOnly:
      return 'wifiOnly';
    case TransferNetworkPolicy.askEachTime:
      return 'askEachTime';
    case TransferNetworkPolicy.allowAll:
      return 'allowAll';
  }
}

String networkPolicyLabel(TransferNetworkPolicy policy) {
  switch (policy) {
    case TransferNetworkPolicy.wifiOnly:
      return '仅 Wi-Fi';
    case TransferNetworkPolicy.askEachTime:
      return '移动网络先询问';
    case TransferNetworkPolicy.allowAll:
      return '不限网络';
  }
}

/// 这个网络类型下，策略是否允许直接开传（不含"用户刚点了仍要传一次"的临时放行）。
bool networkAllowsTransfer(TransferNetworkPolicy policy, NetworkKind kind) {
  switch (kind) {
    case NetworkKind.none:
      // 没网就谁也传不了，别把任务标成"在跑"再失败。
      return false;
    case NetworkKind.wifi:
    case NetworkKind.ethernet:
      return true;
    case NetworkKind.mobile:
    case NetworkKind.other:
      // 移动网络与"未知"都按需谨慎处理；allowAll 才直接放行。
      return policy == TransferNetworkPolicy.allowAll;
  }
}

/// 被拦下时给用户看的短句。
String networkWaitLabel(TransferNetworkPolicy policy, NetworkKind kind) {
  if (kind == NetworkKind.none) return '等待网络';
  if (policy == TransferNetworkPolicy.askEachTime) return '等待确认（移动网络）';
  return '等待 Wi-Fi';
}
