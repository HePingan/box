// 打开外部链接（插件 openUrl 动作）的桥。
//
// 走原生而不是 url_launcher：仓库里没有这个依赖，多处注释明确说过
// （announcement_popup / about / monitor 都是"给复制按钮而不是超链接"）。
// 只接受 https —— 具体原因见 ExternalLinkBridge.kt 的注释。
//
// 非 Android / 通道不可用时返回 false，调用方提示"没有可用的浏览器"，
// 不要把失败吞掉。
import 'package:flutter/services.dart';

class ExternalLinkBridge {
  const ExternalLinkBridge._();

  static const String channelName = 'top.hpa888.box/external_link';

  /// 只放行 https（含主机名）。http 明文、`javascript:`、`intent:` 一律拒绝。
  static bool isOpenable(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    return uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// 打开链接。返回 false 表示没开成（无浏览器 / 非 https / 非 Android）。
  static Future<bool> open(String url) async {
    if (!isOpenable(url)) return false;
    try {
      final ok = await const MethodChannel(
        channelName,
      ).invokeMethod<bool>('openUrl', {'url': url.trim()});
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
