enum NovelSourceAdapterKind {
  rule,
  wtzw,
  unsupported,
}

class NovelSourceCapabilityReport {
  const NovelSourceCapabilityReport({
    required this.sourceName,
    required this.baseUrl,
    required this.adapterKind,
    required this.adapterLabel,
    required this.supportsSearch,
    required this.supportsExplore,
    required this.supportsDetail,
    required this.supportsToc,
    required this.supportsContent,
    required this.featureFlags,
    required this.matchedSignals,
    required this.warnings,
    required this.blockers,
  });

  final String sourceName;
  final String baseUrl;

  final NovelSourceAdapterKind adapterKind;
  final String adapterLabel;

  final bool supportsSearch;
  final bool supportsExplore;
  final bool supportsDetail;
  final bool supportsToc;
  final bool supportsContent;

  final Map<String, bool> featureFlags;
  final List<String> matchedSignals;
  final List<String> warnings;
  final List<String> blockers;

  bool get isUsableForRead =>
      supportsSearch && supportsDetail && supportsToc && supportsContent;

  bool get isPartiallySupported =>
      !isUsableForRead &&
      (supportsSearch ||
          supportsExplore ||
          supportsDetail ||
          supportsToc ||
          supportsContent);

  bool get hasWarnings => warnings.isNotEmpty;
  bool get hasBlockers => blockers.isNotEmpty;

  String get statusLabel {
    if (isUsableForRead) return '可用';
    if (isPartiallySupported) return '部分支持';
    return '暂不支持';
  }

  String get primaryBlocker => blockers.isNotEmpty ? blockers.first : '';

  List<_CapabilityItem> get capabilityItems => [
        _CapabilityItem('搜索', supportsSearch),
        _CapabilityItem('发现', supportsExplore),
        _CapabilityItem('详情', supportsDetail),
        _CapabilityItem('目录', supportsToc),
        _CapabilityItem('正文', supportsContent),
      ];
}

class _CapabilityItem {
  const _CapabilityItem(this.label, this.supported);

  final String label;
  final bool supported;
}