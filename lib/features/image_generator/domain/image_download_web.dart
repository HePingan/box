/// Web-only image download helper.
/// This file is only imported when kIsWeb is true at the call site.
library;

@pragma('vm:entry-point')
import 'dart:html' as html;

void downloadImageOnWeb(String imageUrl) {
  try {
    html.AnchorElement(href: imageUrl)
      ..setAttribute('download', '')
      ..click();
  } catch (_) {
    html.window.open(imageUrl, '_blank');
  }
}
