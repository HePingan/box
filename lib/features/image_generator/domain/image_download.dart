/// Cross-platform image download helper.
/// On web, uses AnchorElement to trigger browser download.
@pragma('vm:entry-point')
import 'package:box/features/image_generator/domain/image_download_web.dart'
    if (dart.library.io) 'package:box/features/image_generator/domain/image_download_io.dart';

/// Downloads an image by triggering a browser save dialog.
void downloadImage(String imageUrl) {
  downloadImageOnWeb(imageUrl);
}
