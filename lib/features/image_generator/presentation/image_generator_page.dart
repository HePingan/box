import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/design_system/widgets/app_page_scaffold.dart';
import 'package:box/features/account/data/account_store.dart';
import 'package:box/features/account/domain/account_models.dart';

import '../data/image_generator_client.dart';
import '../data/image_generator_store.dart';
import '../domain/image_generator_models.dart';
import '../domain/image_generator_preflight.dart';
import '../domain/image_generator_presets.dart';
import 'widgets/image_generator_widgets.dart';

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

  Future<void> _resetDraft() async {
    _draftDebounce?.cancel();
    await _store.resetDraft();
    if (!mounted) return;
    setState(() => _applyDraft(ImageGeneratorDraft.defaults(), notify: false));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已恢复默认生图参数，API Key 未保存')));
  }

  void _appendStyle(String style) {
    final current = _promptController.text.trim();
    _promptController.text = current.isEmpty ? style : '$current，$style';
    _promptController.selection = TextSelection.fromPosition(
      TextPosition(offset: _promptController.text.length),
    );
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

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
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
    return AppPageScaffold(
      safeBottom: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ImageGeneratorHeader(onBack: () => Navigator.maybePop(context)),
          const SizedBox(height: 14),
          ImageGeneratorConfigCard(
            baseUrlController: _baseUrlController,
            apiKeyController: _apiKeyController,
            modelController: _modelController,
            platformBaseUrlController: _platformBaseUrlController,
            accessMode: _accessMode,
            quickProfiles: imageApiQuickProfiles,
            availableModels: _visibleModels,
            totalModelCount: _availableModels.length,
            showingAllModels: _showAllModels,
            loadingModels: _loadingModels,
            modelListError: _modelListError,
            onApplyQuickProfile: _applyQuickProfile,
            onResetDraft: _resetDraft,
            onFetchModels: _fetchModels,
            onApplyModel: _applyModel,
            onAccessModeChanged: _setAccessMode,
            onToggleShowAllModels: _availableModels.isEmpty
                ? null
                : () => setState(() => _showAllModels = !_showAllModels),
            platformAccountLabel: _platformAccountLabel,
            onReloadAccount: _loadAccountSession,
          ),
          if (_accessMode == ImageGeneratorAccessMode.platformQuota) ...[
            const SizedBox(height: 12),
            ImageGeneratorPlatformQuotaCard(
              quota: _platformQuota,
              error: _platformError,
              platformBaseUrl: _platformBaseUrlController.text.trim(),
              accountLabel: _platformAccountLabel,
              onRefresh: _refreshPlatformQuota,
            ),
          ],
          const SizedBox(height: 12),
          ImageGeneratorPromptCard(
            promptController: _promptController,
            negativeController: _negativeController,
            presets: imagePromptPresets,
            onAppendStyle: _appendStyle,
            onApplyPreset: _applyPromptPreset,
            onOptimizePrompt: _optimizePrompt,
          ),
          const SizedBox(height: 12),
          ImageGeneratorParamsCard(
            size: _size,
            quality: _quality,
            outputFormat: _outputFormat,
            count: _count,
            onSizeChanged: (value) => _setParam(() => _size = value),
            onQualityChanged: (value) => _setParam(() => _quality = value),
            onOutputFormatChanged: (value) =>
                _setParam(() => _outputFormat = value),
            onCountChanged: (value) => _setParam(() => _count = value),
          ),
          const SizedBox(height: 12),
          ImageGeneratorReferenceCard(
            controller: _referenceImageController,
            payloadField: _referenceImageField,
            onPayloadFieldChanged: (value) =>
                _setParam(() => _referenceImageField = value),
            onClear: () => _setParam(() {
              _referenceImageController.clear();
              _referenceImageField = ImageReferencePayloadField.none;
            }),
          ),
          const SizedBox(height: 12),
          ImageGeneratorRequestPreviewCard(
            endpoint: _activeEndpoint,
            requestJson: _currentParams().prettyRequestJson,
            preflightItems: _preflightItems(),
            onCopyRequestJson: () =>
                _copyText(_currentParams().prettyRequestJson),
          ),
          const SizedBox(height: 12),
          ImageGeneratorDiagnosticsCard(
            diagnostics: _lastDiagnostics,
            onCopyDiagnostics: _lastDiagnostics == null
                ? null
                : () => _copyText(_lastDiagnostics!.toCopyText()),
            onCopyRequestJson: _lastDiagnostics == null
                ? null
                : () => _copyText(_lastDiagnostics!.requestJson),
          ),
          const SizedBox(height: 12),
          ImageGeneratorResultCard(
            loading: _loading,
            error: _error,
            results: _results,
            history: _history,
            onGenerate: _generate,
            onCopy: _copyText,
            onRestoreHistory: _restoreHistory,
            onClearHistory: _clearHistory,
            parameterSummary:
                '${_modelController.text.trim().isEmpty ? 'gpt-image-1' : _modelController.text.trim()} · $_size · $_quality · $_outputFormat · $_count 张${_referenceImageField.shouldSend ? ' · 参考图:${_referenceImageField.wireName}' : ''}',
            currentPrompt: _promptController.text.trim(),
            currentNegativePrompt: _negativeController.text.trim(),
          ),
        ],
      ),
    );
  }
}
