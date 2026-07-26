/// 异常：搜索时所有候选参数均网络/解析失败。
///
/// 与"成功但无结果"区分开来——后者返回空列表 []，前者向上抛，
/// 让调用方知道是源本身不可用而非关键词无匹配。
class AllSearchCandidatesFailedException implements Exception {
  final String baseUrl;
  final String keyword;
  final List<Object?> errors;

  const AllSearchCandidatesFailedException({
    required this.baseUrl,
    required this.keyword,
    required this.errors,
  });

  @override
  String toString() =>
      'AllSearchCandidatesFailedException(baseUrl=$baseUrl, keyword=$keyword, errors=$errors)';
}
