import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/design_system/widgets/app_page_scaffold.dart';

import '../data/image_generator_client.dart';
import '../domain/image_generator_models.dart';
import 'widgets/image_generator_widgets.dart';

class ImageGeneratorPage extends StatefulWidget {
  const ImageGeneratorPage({super.key});

  @override
  State<ImageGeneratorPage> createState() => _ImageGeneratorPageState();
}

class _ImageGeneratorPageState extends State<ImageGeneratorPage> {
  final ImageGeneratorClient _client = const ImageGeneratorClient();
  final TextEditingController _baseUrlController = TextEditingController(
    text: 'https://api.openai.com/v1',
  );
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController(
    text: 'gpt-image-1',
  );
  final TextEditingController _promptController = TextEditingController(
    text: '一张用于工具箱 App 的 AI 生图入口海报，蓝紫渐变，玻璃拟态，科技感构图，移动端 UI 宣传图',
  );
  final TextEditingController _negativeController = TextEditingController(
    text: '低清晰度，文字错误，水印，畸形手指',
  );

  String _size = '1024x1024';
  String _quality = 'auto';
  String _outputFormat = 'png';
  int _count = 1;
  bool _loading = false;
  String? _error;
  List<GeneratedImageResult> _results = const [];

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _promptController.dispose();
    _negativeController.dispose();
    super.dispose();
  }

  void _appendStyle(String style) {
    final current = _promptController.text.trim();
    _promptController.text = current.isEmpty ? style : '$current，$style';
    _promptController.selection = TextSelection.fromPosition(
      TextPosition(offset: _promptController.text.length),
    );
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
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
          size: _size,
          quality: _quality,
          outputFormat: _outputFormat,
          count: _count,
        ),
      );
      if (!mounted) return;
      setState(() {
        _results = response.images;
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
          ),
          const SizedBox(height: 12),
          ImageGeneratorPromptCard(
            promptController: _promptController,
            negativeController: _negativeController,
            onAppendStyle: _appendStyle,
          ),
          const SizedBox(height: 12),
          ImageGeneratorParamsCard(
            size: _size,
            quality: _quality,
            outputFormat: _outputFormat,
            count: _count,
            onSizeChanged: (value) => setState(() => _size = value),
            onQualityChanged: (value) => setState(() => _quality = value),
            onOutputFormatChanged: (value) =>
                setState(() => _outputFormat = value),
            onCountChanged: (value) => setState(() => _count = value),
          ),
          const SizedBox(height: 12),
          ImageGeneratorResultCard(
            loading: _loading,
            error: _error,
            results: _results,
            onGenerate: _generate,
            onCopy: _copyText,
          ),
        ],
      ),
    );
  }
}
