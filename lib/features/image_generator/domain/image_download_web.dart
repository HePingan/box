/// Web-only image download helper.
/// This file is only imported when kIsWeb is true at the call site.
///
/// Uses dart:html for browser download — still works in production, 
/// though the analyzer considers it deprecated in favour of package:web.
/// Keeping this approach for reliability: it's a well-tested path for
/// triggering browser downloads.
library;

// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

@pragma('vm:entry-point')
import 'dart:html' as html;

/// Triggers a file download in the browser by creating a temporary
/// anchor element and simulating a click.
void downloadImageOnWeb(String imageUrl) {
  try {
    html.AnchorElement(href: imageUrl)
      ..setAttribute('download', '')
      ..click();
  } catch (_) {
    html.window.open(imageUrl, '_blank');
  }
}
