/// 为异步截图提供单飞、可验证的请求归属。
///
/// Android 会按 requestId 回调字节；旧请求/已消费的结果一律不可读取，
/// 防止 OCR 自动搜题、录入和区域试识互相使用对方的截图。
class QuizCaptureSessionCoordinator {
  int _sequence = 0;
  int? _activeId;
  final Map<int, List<int>> _results = {};

  int begin() {
    final id = ++_sequence;
    _activeId = id;
    _results.clear();
    return id;
  }

  bool accept(int requestId, List<int> bytes) {
    if (requestId != _activeId || bytes.isEmpty) return false;
    _results[requestId] = List<int>.unmodifiable(bytes);
    return true;
  }

  List<int>? take(int requestId) => _results.remove(requestId);
}
