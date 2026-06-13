import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../data/image_generator_client.dart';
import '../data/image_generator_store.dart';
import '../domain/image_generator_models.dart';
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
  final TextEditingController _baseUrlController = TextEditingController();
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
  int _count = 1;
  bool _loading = false;
  bool _draftLoaded = false;
  String? _error;
  List<GeneratedImageResult> _results = const [];
  List<ImageGenerationHistoryItem> _history = const [];

  @override
  void initState() {
    super.initState();
    _applyDraft(ImageGeneratorDraft.defaults(), notify: false);
    _loadStoredState();
    for (final controller in [
      _baseUrlController,
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
      _history = history;
      _draftLoaded = true;
    });
  }

  void _applyDraft(ImageGeneratorDraft draft, {bool notify = true}) {
    _baseUrlController.text = draft.baseUrl;
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

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = '请先输入 Prompt');
      return;
    }
    if (apiKey.isEmpty) {
      setState(() => _error = '请先填写 API Key');
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
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _client.generate(
        ImageGenerationParams(
          baseUrl: _baseUrlController.text,
          apiKey: apiKey,
          model: _modelController.text,
          prompt: prompt,
          negativePrompt: _negativeController.text,
          referenceImageUrl: referenceUrl,
          referenceImageField: _referenceImageField,
          size: _size,
          quality: _quality,
          outputFormat: _outputFormat,
          count: _count,
        ),
      );
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
          images: response.images.map((e) => e.image).toList(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _results = response.images;
        _history = history;
        _loading = false;
      });
    } on ImageGeneratorException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '生成失败：$e';
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
            quickProfiles: imageApiQuickProfiles,
            onApplyQuickProfile: _applyQuickProfile,
            onResetDraft: _resetDraft,
          ),
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
