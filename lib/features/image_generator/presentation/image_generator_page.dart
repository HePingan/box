import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';

import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/features/account/data/account_store.dart';
import 'package:box/features/account/domain/account_models.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import '../data/image_generator_client.dart';
import '../data/image_generator_store.dart';
import '../domain/image_download.dart';
import '../domain/image_generator_models.dart';
import '../domain/image_generator_preflight.dart';
import '../domain/image_generator_presets.dart';
import 'widgets/image_generator_widgets.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/design_system/widgets/app_cards.dart' hide AppEmptyState;
import 'package:box/design_system/widgets/app_empty_state.dart';

class ImageGeneratorPage extends StatefulWidget {
  const ImageGeneratorPage({super.key});

  @override
  State<ImageGeneratorPage> createState() => _ImageGeneratorPageState();
}

class _ImageGeneratorPageState extends State<ImageGeneratorPage> {
  final ImageGeneratorClient _client = const ImageGeneratorClient();
  final ImageGeneratorStore _store = const ImageGeneratorStore();
  final BoxAccountStore _accountStore = BoxAccountStore();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _platformBaseUrlController =
      TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _negativeController = TextEditingController();
  final TextEditingController _referenceImageController =
      TextEditingController();

  Timer? _draftDebounce;
  String _size = '1024x1024';
  String _quality = 'auto';
  String _outputFormat = 'png';
  ImageReferencePayloadField _referenceImageField =
      ImageReferencePayloadField.none;
  ImageGeneratorAccessMode _accessMode = ImageGeneratorAccessMode.ownKey;
  BoxAccountSession? _accountSession;
  ImagePlatformQuota? _platformQuota;
  String? _platformError;
  int _count = 1;
  bool _loading = false;
  bool _loadingModels = false;
  bool _showAllModels = false;
  bool _draftLoaded = false;
  String? _error;
  String? _modelListError;
  ImageGeneratorRequestDiagnostics? _lastDiagnostics;
  List<String> _availableModels = const [];
  List<GeneratedImageResult> _results = const [];
  List<ImageGenerationHistoryItem> _history = const [];
  final Set<String> _selectedStyles = {};

  static const _styleLabels = [
    '写实摄影',
    '二次元插画',
    '赛博朋克',
    '国风插画',
    '产品海报',
    'App 图标',
    '电商主图',
    '社媒封面',
  ];

  @override
  void initState() {
    super.initState();
    _applyDraft(ImageGeneratorDraft.defaults(), notify: false);
    _loadStoredState();
    _loadAccountSession();
    for (final controller in [
      _baseUrlController,
      _platformBaseUrlController,
      _modelController,
      _promptController,
      _negativeController,
      _referenceImageController,
    ]) {
      controller.addListener(_scheduleSaveDraft);
    }
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _saveDraftNow();
    _baseUrlController.dispose();
    _platformBaseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _promptController.dispose();
    _negativeController.dispose();
    _referenceImageController.dispose();
    super.dispose();
  }

  Future<void> _loadStoredState() async {
    final draft = await _store.loadDraft();
    final history = await _store.loadHistory();
    if (!mounted) return;
    setState(() {
      _applyDraft(draft, notify: false);
      _syncPlatformUrlFromAccountIfNeeded();
      _history = history;
      _draftLoaded = true;
    });
  }

  Future<void> _loadAccountSession() async {
    final session = await _accountStore.loadSession();
    if (!mounted) return;
    setState(() {
      _accountSession = session;
      _syncPlatformUrlFromAccountIfNeeded();
    });
  }

  String? get _platformToken => _accountSession?.token;

  String? get _platformAccountLabel {
    final session = _accountSession;
    if (session == null) return null;
    final role = session.user.isAdmin ? '管理员' : '普通用户';
    return '${session.user.username} · $role';
  }

  bool _ensurePlatformSession() {
    if (_accessMode != ImageGeneratorAccessMode.platformQuota) return true;
    if (_accountSession != null) return true;
    setState(() {
      _error = '请先在账号中心登录 Box 账号，再使用平台额度模式。';
      _platformError = '未登录 Box 账号。';
    });
    return false;
  }

  void _syncPlatformUrlFromAccountIfNeeded() {
    final serverUrl = _accountSession?.serverUrl.trim() ?? '';
    if (serverUrl.isEmpty) return;
    if (_platformBaseUrlController.text.trim().isEmpty) {
      _platformBaseUrlController.text = serverUrl;
    }
  }

  void _applyDraft(ImageGeneratorDraft draft, {bool notify = true}) {
    _baseUrlController.text = draft.baseUrl;
    _platformBaseUrlController.text = draft.platformBaseUrl;
    _accessMode = draft.accessMode;
    _modelController.text = draft.model;
    _promptController.text = draft.prompt;
    _negativeController.text = draft.negativePrompt;
    _referenceImageController.text = draft.referenceImageUrl;
    _referenceImageField = draft.referenceImageField;
    _size = draft.size;
    _quality = draft.quality;
    _outputFormat = draft.outputFormat;
    _count = draft.count;
    // Rebuild _selectedStyles from prompt text
    setState(() {
      _selectedStyles.clear();
      for (final label in _styleLabels) {
        if (draft.prompt.contains(label)) {
          _selectedStyles.add(label);
        }
      }
    });
    if (notify) _scheduleSaveDraft();
  }

  ImageGeneratorDraft _currentDraft() {
    return ImageGeneratorDraft(
      baseUrl: _baseUrlController.text.trim(),
      platformBaseUrl: _platformBaseUrlController.text.trim(),
      accessMode: _accessMode,
      model: _modelController.text.trim(),
      prompt: _promptController.text.trim(),
      negativePrompt: _negativeController.text.trim(),
      referenceImageUrl: _referenceImageController.text.trim(),
      referenceImageField: _referenceImageField,
      size: _size,
      quality: _quality,
      outputFormat: _outputFormat,
      count: _count,
    );
  }

  ImageGenerationParams _currentParams() {
    return ImageGenerationParams(
      baseUrl: _baseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      prompt: _promptController.text.trim(),
      negativePrompt: _negativeController.text.trim(),
      referenceImageUrl: _referenceImageController.text.trim(),
      referenceImageField: _referenceImageField,
      size: _size,
      quality: _quality,
      outputFormat: _outputFormat,
      count: _count,
    );
  }

  List<ImageGeneratorPreflightItem> _preflightItems() {
    if (_accessMode == ImageGeneratorAccessMode.platformQuota) {
      final items = <ImageGeneratorPreflightItem>[];
      if (_platformBaseUrlController.text.trim().isEmpty) {
        items.add(
          const ImageGeneratorPreflightItem(
            message: '平台服务地址未配置，需后端提供额度代理。',
            level: ImageGeneratorPreflightLevel.error,
          ),
        );
      } else if (_accountSession == null) {
        items.add(
          const ImageGeneratorPreflightItem(
            message: '平台额度模式需要先在账号中心登录 Box 账号。',
            level: ImageGeneratorPreflightLevel.error,
          ),
        );
      } else {
        items.add(
          const ImageGeneratorPreflightItem(
            message: '平台额度模式不会在前端使用管理员 API Key。',
            level: ImageGeneratorPreflightLevel.ok,
          ),
        );
      }
      if (_promptController.text.trim().isEmpty) {
        items.add(
          const ImageGeneratorPreflightItem(
            message: 'Prompt 为空。',
            level: ImageGeneratorPreflightLevel.warning,
          ),
        );
      }
      return items;
    }
    return buildImageGeneratorPreflight(_currentParams());
  }

  String get _platformGenerateEndpoint {
    final base = _platformBaseUrlController.text.trim().replaceAll(
      RegExp(r'/+$'),
      '',
    );
    return base.isEmpty ? '/api/image/generate' : '$base/api/image/generate';
  }

  String get _activeEndpoint =>
      _accessMode == ImageGeneratorAccessMode.platformQuota
      ? _platformGenerateEndpoint
      : _currentParams().endpoint;

  ImageGeneratorRequestDiagnostics _buildDiagnostics({
    required ImageGenerationParams params,
    required bool success,
    int? statusCode,
    String message = '',
    String rawPreview = '',
    int imageCount = 0,
    String resultFormat = '',
  }) {
    return ImageGeneratorRequestDiagnostics(
      createdAt: DateTime.now(),
      endpoint: _activeEndpoint,
      requestJson: params.prettyRequestJson,
      referenceField: params.referenceImageField,
      success: success,
      statusCode: statusCode,
      message: message,
      rawPreview: rawPreview,
      imageCount: imageCount,
      resultFormat: resultFormat,
    );
  }

  String _resultFormat(List<GeneratedImageResult> images) {
    final hasDataUrl = images.any((image) => image.isDataUrl);
    final hasUrl = images.any((image) => !image.isDataUrl);
    if (hasDataUrl && hasUrl) return 'URL + data URL';
    if (hasDataUrl) return 'data URL';
    if (hasUrl) return 'URL';
    return '';
  }

  List<String> get _recommendedModels {
    const keywords = [
      'gpt-image',
      'dall-e',
      'image',
      'imagen',
      'flux',
      'stable',
      'sd',
      'midjourney',
    ];
    final recommended = _availableModels
        .where(
          (model) =>
              keywords.any((keyword) => model.toLowerCase().contains(keyword)),
        )
        .toList();
    return recommended.isEmpty
        ? _availableModels.take(12).toList()
        : recommended;
  }

  List<String> get _visibleModels {
    if (_showAllModels) return _availableModels;
    return _recommendedModels;
  }

  Future<void> _fetchModels() async {
    if (_accessMode == ImageGeneratorAccessMode.platformQuota) {
      await _fetchPlatformModels();
      return;
    }
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _modelListError = '请先填写 API Key，再获取模型列表。');
      return;
    }
    setState(() {
      _loadingModels = true;
      _modelListError = null;
    });
    try {
      final models = await _client.fetchModels(
        baseUrl: _baseUrlController.text.trim(),
        apiKey: apiKey,
      );
      if (!mounted) return;
      setState(() {
        _availableModels = models;
        _showAllModels = false;
        _loadingModels = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已获取 ${models.length} 个模型，API Key 未保存')),
      );
    } on ImageGeneratorException catch (e) {
      if (!mounted) return;
      setState(() {
        _modelListError = e.message;
        _loadingModels = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelListError = '获取模型列表失败：$e';
        _loadingModels = false;
      });
    }
  }

  Future<void> _fetchPlatformModels() async {
    final platformBase = _platformBaseUrlController.text.trim();
    if (platformBase.isEmpty) {
      setState(() => _modelListError = '请先填写平台服务地址。');
      return;
    }
    setState(() {
      _loadingModels = true;
      _modelListError = null;
    });
    try {
      if (!_ensurePlatformSession()) {
        setState(() => _loadingModels = false);
        return;
      }
      final models = await _client.fetchPlatformModels(
        platformBaseUrl: platformBase,
        platformToken: _platformToken,
      );
      if (!mounted) return;
      setState(() {
        _availableModels = models;
        _showAllModels = false;
        _loadingModels = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已获取平台模型 ${models.length} 个')));
    } on ImageGeneratorException catch (e) {
      if (!mounted) return;
      setState(() {
        _modelListError = e.message;
        _loadingModels = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelListError = '获取平台模型失败：$e';
        _loadingModels = false;
      });
    }
  }

  Future<void> _refreshPlatformQuota() async {
    final platformBase = _platformBaseUrlController.text.trim();
    if (platformBase.isEmpty) {
      setState(() => _platformError = '平台服务地址未配置');
      return;
    }
    setState(() => _platformError = null);
    try {
      if (!_ensurePlatformSession()) return;
      final quota = await _client.fetchPlatformQuota(
        platformBaseUrl: platformBase,
        platformToken: _platformToken,
      );
      if (!mounted) return;
      setState(() => _platformQuota = quota);
    } on ImageGeneratorException catch (e) {
      if (!mounted) return;
      setState(() => _platformError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _platformError = '获取平台额度失败：$e');
    }
  }

  void _setAccessMode(ImageGeneratorAccessMode mode) {
    setState(() {
      _accessMode = mode;
      _error = null;
      _modelListError = null;
    });
    _scheduleSaveDraft();
  }

  void _applyModel(String model) {
    setState(() => _modelController.text = model);
    _scheduleSaveDraft();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已选择模型 $model')));
  }

  void _scheduleSaveDraft() {
    if (!_draftLoaded) return;
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 450), _saveDraftNow);
  }

  Future<void> _saveDraftNow() async {
    if (!_draftLoaded) return;
    try {
      await _store.saveDraft(_currentDraft());
    } catch (_) {}
  }

  void _appendStyle(String style) {
    setState(() {
      _selectedStyles.add(style);
    });
    final current = _promptController.text.trim();
    _promptController.text = current.isEmpty ? style : '$current，$style';
    _promptController.selection = TextSelection.fromPosition(
      TextPosition(offset: _promptController.text.length),
    );
    _scheduleSaveDraft();
  }

  void _applyQuickProfile(ImageApiQuickProfile profile) {
    setState(() {
      _baseUrlController.text = profile.baseUrl;
      _modelController.text = profile.model;
    });
    _scheduleSaveDraft();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已套用 ${profile.title} 配置')));
  }

  void _applyPromptPreset(ImagePromptPreset preset) {
    setState(() {
      _promptController.text = preset.prompt;
      _negativeController.text = preset.negativePrompt;
      _size = preset.size;
      _quality = preset.quality;
      _outputFormat = preset.outputFormat;
    });
    _scheduleSaveDraft();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已套用 ${preset.title} 模板')));
  }

  void _optimizePrompt() {
    final optimized = optimizeImagePrompt(_promptController.text);
    setState(() => _promptController.text = optimized);
    _promptController.selection = TextSelection.fromPosition(
      TextPosition(offset: _promptController.text.length),
    );
    _scheduleSaveDraft();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已按本地规则优化 Prompt')));
  }

  void _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  void _downloadImage(String imageUrl) async {
    if (kIsWeb) {
      // On web, use anchor element to trigger browser download
      try {
        downloadImage(imageUrl);
      } catch (e) {
        await Clipboard.setData(ClipboardData(text: imageUrl));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('下载失败，图片链接已复制到剪贴板')));
      }
      return;
    }

    // On mobile: download image to temp dir, then open with system (saves to gallery)
    try {
      final client = Dio();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/ai_image_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await client.download(imageUrl, file.path);
      if (file.existsSync()) {
        await OpenFilex.open(file.path);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('图片已保存，可在相册中查看')));
      }
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: imageUrl));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('下载失败，图片链接已复制到剪贴板')));
    }
  }

  void _setParam(VoidCallback update) {
    setState(update);
    _scheduleSaveDraft();
  }

  void _restoreHistory(ImageGenerationHistoryItem item) {
    setState(() {
      _promptController.text = item.prompt;
      _negativeController.text = item.negativePrompt;
      _modelController.text = item.model;
      _referenceImageController.text = item.referenceImageUrl;
      _referenceImageField = item.referenceImageField;
      _size = item.size;
      _quality = item.quality;
      _outputFormat = item.outputFormat;
      _results = item.images
          .map((image) => GeneratedImageResult(image: image, rawUrl: image))
          .toList();
    });
    _scheduleSaveDraft();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复用最近生成参数')));
  }

  Future<void> _clearHistory() async {
    await _store.clearHistory();
    if (!mounted) return;
    setState(() => _history = const []);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清空最近生成记录')));
  }

  List<GeneratedImageResult> _proxiedImagesForPlatform(
    List<GeneratedImageResult> images,
  ) {
    if (_accessMode != ImageGeneratorAccessMode.platformQuota) return images;
    final base = _platformBaseUrlController.text.trim().replaceAll(
      RegExp(r'/+$'),
      '',
    );
    if (base.isEmpty) return images;
    return images.map((image) {
      if (image.isDataUrl) return image;
      final raw = _normalizeImageUrl(image.rawUrl ?? image.image);
      final encoded = Uri.encodeQueryComponent(raw);
      return GeneratedImageResult(
        image: '$base/api/image/proxy?url=$encoded',
        rawUrl: raw,
        revisedPrompt: image.revisedPrompt,
      );
    }).toList();
  }

  /// Normalize image URLs for OSS/CDN compatibility.
  /// Some OSS providers (like Aliyun) require lowercase bucket names.
  static String _normalizeImageUrl(String url) {
    try {
      final uri = Uri.parse(url);
      // Lowercase the host (domain + bucket)
      final normalized = uri.replace(host: uri.host.toLowerCase());
      return normalized.toString();
    } catch (_) {
      return url;
    }
  }

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = '请先输入 Prompt');
      return;
    }
    if (_accessMode == ImageGeneratorAccessMode.ownKey && apiKey.isEmpty) {
      setState(() => _error = '请先填写 API Key');
      return;
    }
    if (_accessMode == ImageGeneratorAccessMode.platformQuota &&
        _platformBaseUrlController.text.trim().isEmpty) {
      setState(() => _error = '请先填写平台服务地址，或切回自带 Key 模式。');
      return;
    }
    if (_accessMode == ImageGeneratorAccessMode.platformQuota &&
        !_ensurePlatformSession()) {
      return;
    }
    final referenceUrl = _referenceImageController.text.trim();
    if (_referenceImageField.shouldSend && referenceUrl.isEmpty) {
      setState(() => _error = '请先填写参考图 URL，或把参考图字段改为“不发送”。');
      return;
    }
    if (!_referenceImageField.shouldSend && referenceUrl.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '参考图当前仅保存/预览，不会发送给接口；如需发送请选 image/reference_image/input_image。',
          ),
        ),
      );
    }

    await _saveDraftNow();
    if (!mounted) return;
    final params = _currentParams();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = _accessMode == ImageGeneratorAccessMode.platformQuota
          ? await _client.generateWithPlatformQuota(
              platformBaseUrl: _platformBaseUrlController.text.trim(),
              params: params,
              platformToken: _platformToken,
            )
          : await _client.generate(params);
      final displayImages = _proxiedImagesForPlatform(response.images);
      final history = await _store.addHistory(
        ImageGenerationHistoryItem(
          prompt: prompt,
          negativePrompt: _negativeController.text.trim(),
          referenceImageUrl: referenceUrl,
          referenceImageField: _referenceImageField,
          model: _modelController.text.trim().isEmpty
              ? 'gpt-image-1'
              : _modelController.text.trim(),
          size: _size,
          quality: _quality,
          outputFormat: _outputFormat,
          createdAt: DateTime.now(),
          images: displayImages.map((e) => e.image).toList(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _results = displayImages;
        _history = history;
        _lastDiagnostics = _buildDiagnostics(
          params: params,
          success: true,
          rawPreview: response.rawPreview,
          imageCount: response.images.length,
          resultFormat: _resultFormat(response.images),
        );
        _loading = false;
      });
      if (_accessMode == ImageGeneratorAccessMode.platformQuota) {
        unawaited(_refreshPlatformQuota());
      }
    } on ImageGeneratorException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _lastDiagnostics = _buildDiagnostics(
          params: params,
          success: false,
          statusCode: e.statusCode,
          message: e.message,
          rawPreview: e.rawPreview,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '生成失败：$e';
        _lastDiagnostics = _buildDiagnostics(
          params: params,
          success: false,
          message: '生成失败：$e',
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final parameterSummary =
        '${_modelController.text.trim().isEmpty ? 'gpt-image-1' : _modelController.text.trim()} · $_size · $_quality · $_outputFormat · $_count 张${_referenceImageField.shouldSend ? ' · 参考图:${_referenceImageField.wireName}' : ''}';

    return AppPageScaffold(
      safeBottom: true,
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              // ── Header ──
              ImageGeneratorHeader(onBack: () => Navigator.maybePop(context)),
              const SizedBox(height: 14),

              // ══════════════════════════════════════════
              // BLOCK 1: Configuration
              // ══════════════════════════════════════════
              SurfaceCard(
                child: Column(
                  children: [
                    // ── Top row: always-visible config ──
                    CollapsibleSection(
                      icon: Icons.tune_rounded,
                      title: '配置',
                      subtitle: _accessMode == ImageGeneratorAccessMode.ownKey
                          ? '自带 Key 直连接口'
                          : '平台额度通过后端代理',
                      initialExpanded: true,
                      children: [
                        const SizedBox(height: 8),
                        // Access mode toggle
                        SegmentedButton<ImageGeneratorAccessMode>(
                          segments: ImageGeneratorAccessMode.values
                              .map(
                                (
                                  mode,
                                ) => ButtonSegment<ImageGeneratorAccessMode>(
                                  value: mode,
                                  label: Text(mode.label),
                                  icon: Icon(
                                    mode == ImageGeneratorAccessMode.ownKey
                                        ? Icons.key_rounded
                                        : Icons.admin_panel_settings_rounded,
                                  ),
                                ),
                              )
                              .toList(),
                          selected: {_accessMode},
                          onSelectionChanged: (values) =>
                              _setAccessMode(values.first),
                        ),
                        const SizedBox(height: 12),
                        // Model
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _modelController,
                                decoration: InputDecoration(
                                  labelText: '模型',
                                  hintText: 'gpt-image-1',
                                  filled: true,
                                  border: const OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      final text = _modelController.text.trim();
                                      if (text.isNotEmpty) {
                                        Clipboard.setData(
                                          ClipboardData(text: text),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _loadingModels ? null : _fetchModels,
                                icon: _loadingModels
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.cloud_sync_rounded,
                                        size: 16,
                                      ),
                                label: Text(
                                  _loadingModels
                                      ? '获取中'
                                      : _accessMode ==
                                            ImageGeneratorAccessMode
                                                .platformQuota
                                      ? '获取平台模型'
                                      : '获取模型列表',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_modelListError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _modelListError!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        // Model chips
                        if (_visibleModels.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _showAllModels ? '全部模型（点击填入）' : '推荐生图模型',
                            style: const TextStyle(
                              color: AppTokens.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ..._visibleModels.map(
                                (model) => ActionChip(
                                  avatar: const Icon(
                                    Icons.smart_toy_outlined,
                                    size: 14,
                                  ),
                                  label: Text(model),
                                  tooltip: model,
                                  onPressed: () => _applyModel(model),
                                ),
                              ),
                              if (_availableModels.length > 12)
                                TextButton(
                                  onPressed: _availableModels.isEmpty
                                      ? null
                                      : () => setState(
                                          () =>
                                              _showAllModels = !_showAllModels,
                                        ),
                                  child: Text(
                                    _showAllModels
                                        ? '收起全部'
                                        : '查看全部 ${_availableModels.length} 个',
                                  ),
                                ),
                            ],
                          ),
                        ],
                        // Platform quota card
                        if (_accessMode ==
                            ImageGeneratorAccessMode.platformQuota) ...[
                          const SizedBox(height: 12),
                          ImageGeneratorPlatformQuotaCardCompact(
                            quota: _platformQuota,
                            error: _platformError,
                            accountLabel: _platformAccountLabel,
                            onRefresh: _refreshPlatformQuota,
                          ),
                        ],
                      ],
                    ),

                    // ── Advanced settings: collapsed by default ──
                    const SizedBox(height: 8),
                    CollapsibleSection(
                      icon: Icons.settings_ethernet_rounded,
                      title: '高级设置',
                      subtitle: _accessMode == ImageGeneratorAccessMode.ownKey
                          ? 'BaseUrl · ApiKey · 快捷配置'
                          : '平台服务地址 · 账号同步',
                      initialExpanded: false,
                      children: [
                        if (_accessMode == ImageGeneratorAccessMode.ownKey) ...[
                          const SizedBox(height: 8),
                          // Quick profiles
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: imageApiQuickProfiles
                                .map(
                                  (profile) => ActionChip(
                                    avatar: const Icon(
                                      Icons.flash_on_rounded,
                                      size: 14,
                                    ),
                                    label: Text(profile.title),
                                    tooltip: profile.description,
                                    onPressed: () =>
                                        _applyQuickProfile(profile),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _baseUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Base URL',
                              hintText: 'https://api.openai.com/v1',
                              filled: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _apiKeyController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'API Key',
                              hintText: 'sk-…（仅本次使用，不保存）',
                              filled: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _platformBaseUrlController,
                            decoration: const InputDecoration(
                              labelText: '平台服务地址',
                              hintText: 'https://your-domain.com',
                              filled: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: AppStatusPill(
                                  label: _platformAccountLabel == null
                                      ? '未登录 Box 账号'
                                      : '当前账号：$_platformAccountLabel',
                                  icon: _platformAccountLabel == null
                                      ? Icons.account_circle_outlined
                                      : Icons.verified_user_rounded,
                                  color: _platformAccountLabel == null
                                      ? AppTokens.warning
                                      : AppTokens.success,
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _loadAccountSession,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 16,
                                ),
                                label: const Text('同步'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '平台额度模式不会在前端使用管理员 API Key',
                            style: TextStyle(
                              color: AppTokens.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ══════════════════════════════════════════
              // BLOCK 2: Creation
              // ══════════════════════════════════════════
              const SizedBox(height: 12),
              SurfaceCard(
                child: CollapsibleSection(
                  icon: Icons.auto_awesome_rounded,
                  title: '创作',
                  subtitle: '提示词 · 风格',
                  initialExpanded: true,
                  children: [
                    const SizedBox(height: 4),
                    // ── Prompt presets (horizontal scroll, compact) ──
                    SizedBox(
                      height: 28,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: imagePromptPresets
                              .map(
                                (preset) => Padding(
                                  padding: const EdgeInsets.only(right: 3),
                                  child: ActionChip(
                                    label: Text(
                                      preset.title,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    labelStyle: const TextStyle(fontSize: 10),
                                    avatar: const Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 10,
                                    ),
                                    onPressed: () => _applyPromptPreset(preset),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // ── Style quick-add buttons ──
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: _styleLabels
                          .map(
                            (label) => OutlinedButton(
                              onPressed: () => _appendStyle(label),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: _selectedStyles.contains(label)
                                    ? AppTokens.primaryBlue.withValues(
                                        alpha: 0.12,
                                      )
                                    : null,
                                side: _selectedStyles.contains(label)
                                    ? BorderSide(
                                        color: AppTokens.primaryBlue,
                                        width: 1.5,
                                      )
                                    : null,
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: _selectedStyles.contains(label)
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                  color: _selectedStyles.contains(label)
                                      ? AppTokens.primaryBlue
                                      : null,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 4),
                    // ── Prompt textarea ──
                    TextField(
                      controller: _promptController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Prompt',
                        alignLabelWithHint: true,
                        hintText: '描述主体、风格、镜头、光线、构图和用途…',
                        filled: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.auto_fix_high_rounded,
                            size: 20,
                          ),
                          onPressed: _optimizePrompt,
                          tooltip: 'AI 优化提示词',
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // ── Negative prompt (single line, compact) ──
                    TextField(
                      controller: _negativeController,
                      maxLines: 1,
                      decoration: const InputDecoration(
                        labelText: 'Negative prompt（可选）',
                        hintText: '低清晰度、畸形手指、水印…',
                        filled: true,
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // ── Reference image (collapsible, default collapsed) ──
                    ReferenceSection(
                      controller: _referenceImageController,
                      onReferenceChanged: (hasRef) => _setParam(
                        () => _referenceImageField = hasRef
                            ? ImageReferencePayloadField.image
                            : ImageReferencePayloadField.none,
                      ),
                      onClear: () => _setParam(() {
                        _referenceImageController.clear();
                        _referenceImageField = ImageReferencePayloadField.none;
                      }),
                    ),
                  ],
                ),
              ),

              // ══════════════════════════════════════════
              // BLOCK 3: Results
              // ══════════════════════════════════════════
              const SizedBox(height: 12),
              SurfaceCard(
                child: CollapsibleSection(
                  icon: Icons.image_rounded,
                  title: '结果',
                  subtitle: '生成结果 · 历史记录 · 诊断',
                  initialExpanded: true,
                  children: [
                    const SizedBox(height: 4),
                    // Parameter summary
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTokens.primaryBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTokens.primaryBlue.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        '当前参数：$parameterSummary',
                        style: const TextStyle(
                          color: AppTokens.primaryBlue,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    if (_loading) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTokens.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTokens.warning.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          '⏳ 生成中，通常 1-5 分钟',
                          style: TextStyle(
                            color: AppTokens.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Results
                    if (_results.isEmpty)
                      const AppEmptyState(
                        title: '暂无图片',
                        message: '填入配置和提示词后点击"开始生成"',
                        icon: Icons.image_search_rounded,
                      )
                    else
                      ..._results.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GeneratedImageTileCompact(
                            item: item,
                            onCopy: _copyText,
                            onDownload: _downloadImage,
                            prompt: _promptController.text.trim(),
                            negativePrompt: _negativeController.text.trim(),
                            parameterSummary: parameterSummary,
                          ),
                        ),
                      ),
                    // History
                    const SizedBox(height: 8),
                    HistorySectionCompact(
                      history: _history,
                      onRestore: _restoreHistory,
                      onCopy: _copyText,
                      onClear: _clearHistory,
                    ),
                    // ── Merged request preview + diagnostics ──
                    const SizedBox(height: 8),
                    RequestDetailsCardCompact(
                      endpoint: _activeEndpoint,
                      requestJson: _currentParams().prettyRequestJson,
                      preflightItems: _preflightItems(),
                      diagnostics: _lastDiagnostics,
                      onCopyRequestJson: () =>
                          _copyText(_currentParams().prettyRequestJson),
                      onCopyDiagnostics: _lastDiagnostics == null
                          ? null
                          : () => _copyText(_lastDiagnostics!.toCopyText()),
                      onCopyDiagRequestJson: _lastDiagnostics == null
                          ? null
                          : () => _copyText(_lastDiagnostics!.requestJson),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Floating generate button ──
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: FilledButton.icon(
                onPressed: _loading ? null : _generate,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high_rounded),
                label: Text(_loading ? '生成中…' : '开始生成'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
