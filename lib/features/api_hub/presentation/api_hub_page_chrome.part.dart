part of './api_hub_page.dart';

// 跨面板共用的辅助方法：返回「最近使用」、记录工具切换、复制文本、
// 各面板的预置快选，以及目录条目的状态过滤。
//
// on `_ApiHubPageActions`：预置快选会调用 _buildDummyImage 等构建动作。

mixin _ApiHubPageChrome on _ApiHubPageStateBase, _ApiHubPageActions {
  /// 共享记录变了（在别处点过工具，或本页自己刚记了一笔）→ 重画「最近使用」。
  void _onUsageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// 最近用过的 API 面板 —— 来自共享的使用记录，不再是写死的 6 个 id。
  ///
  /// 记录以**工具名**为键（工具页的派发点就是这么记的），这里按 `kToolTargets`
  /// 换成 API Hub 的面板 id。一条记录都没有时这一行整块不渲染：
  /// 拿没点过的工具冒充「最近使用」，和工具页那个「计划中」是同一类假承诺。
  List<PublicApiToolDefinition> get _recentTools {
    final seen = <String>{};
    final specs = <PublicApiToolDefinition>[];
    for (final name in ToolUsageStore.instance.recentNames(limit: 20)) {
      final target = kToolTargets[name];
      if (target is! ApiHubToolTarget) continue;
      final panelId = target.toolId;
      if (panelId == null || !seen.add(panelId)) continue;
      // 用 tryById 而不是 byId：byId 取不到会兜底成 weather，
      // 那会在「最近使用」里凭空多出一个天气，用户会以为是自己点的。
      final spec = PublicApiRegistry.tryById(panelId);
      if (spec == null) continue;
      specs.add(spec);
      if (specs.length >= 6) break;
    }
    return specs;
  }

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制$label'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _ipInfoText(IpInfoResult info) {
    return [
      'IP: ${info.ip}',
      if (info.city.isNotEmpty ||
          info.region.isNotEmpty ||
          info.country.isNotEmpty)
        '位置: ${[info.city, info.region, info.country].where((e) => e.isNotEmpty).join(' / ')}',
      if (info.org.isNotEmpty) '组织: ${info.org}',
      if (info.timezone.isNotEmpty) '时区: ${info.timezone}',
    ].join('\n');
  }

  void _applyImagePreset({
    required String size,
    required String background,
    required String foreground,
    String? text,
  }) {
    setState(() {
      _imageSizeController.text = size;
      _imageBgController.text = background;
      _imageFgController.text = foreground;
      if (text != null) _imageTextController.text = text;
    });
    _buildDummyImage();
  }

  void _applyQrPreset(String text, {String size = '220x220'}) {
    setState(() {
      _qrTextController.text = text;
      _qrSizeController.text = size;
    });
    _buildQrCode();
  }

  void _applyAvatarPreset({
    required String name,
    required String background,
    required String foreground,
  }) {
    setState(() {
      _avatarNameController.text = name;
      _avatarBgController.text = background;
      _avatarFgController.text = foreground;
    });
    _buildAvatar();
  }

  void _applyCoverPreset({
    required String width,
    required String height,
    required String seed,
  }) {
    setState(() {
      _coverWidthController.text = width;
      _coverHeightController.text = height;
      _coverSeedController.text = seed;
    });
    _buildCoverImage();
  }

  List<PublicApiDirectoryEntry> _filteredDirectoryEntries() {
    return _directoryEntries.where((entry) {
      return switch (_directoryStatus) {
        '已接入' => entry.isIntegrated,
        '推荐接入' => entry.isRecommended && !entry.isIntegrated,
        '待接入' => !entry.isIntegrated,
        _ => true,
      };
    }).toList();
  }
}
