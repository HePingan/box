/// 异步加载的「请求身份」守卫。
///
/// `mounted` 只能防止 dispose 后写状态，**不能**防止一个较早发出、较晚返回的
/// 请求覆盖较新请求的结果。真实症状：搜「斗罗」后立刻搜「遮天」，若前者响应
/// 更慢，列表最终显示的是「斗罗」的结果，而搜索框里是「遮天」。
///
/// 用法：每次发起加载前 `final token = gen.begin(intent)`，响应回来后先问
/// `gen.isCurrent(token)`，false 就整段丢弃（连 error 也不要写）。
class LoadGeneration {
  int _current = 0;
  Object? _intent;

  /// 当前代号（用于断言/调试）。
  int get current => _current;

  /// 当前意图标识（如搜索关键词、发现页索引）。
  Object? get intent => _intent;

  /// 开启新一代加载，作废所有在途请求。
  LoadToken begin(Object? intent) {
    _current++;
    _intent = intent;
    return LoadToken(_current, intent);
  }

  /// 该 token 是否仍代表最新一次加载。
  ///
  /// 同时校验代号与意图：代号防「后发先至」，意图防「同代号但目标已变」。
  bool isCurrent(LoadToken token) {
    return token.generation == _current && token.intent == _intent;
  }

  /// 作废全部在途请求（例如取消搜索、离开页面）。
  void invalidate() {
    _current++;
    _intent = null;
  }
}

/// 一次加载的身份凭据。
class LoadToken {
  const LoadToken(this.generation, this.intent);

  final int generation;
  final Object? intent;

  @override
  String toString() => 'LoadToken(gen: $generation, intent: $intent)';
}
