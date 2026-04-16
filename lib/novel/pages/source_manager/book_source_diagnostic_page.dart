import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/novel_source_capability.dart';
import '../../core/novel_source_capability_detector.dart';
import '../../core/novel_source_factory.dart';
import 'book_source_model.dart';

class BookSourceDiagnosticPage extends StatefulWidget {
  const BookSourceDiagnosticPage({
    super.key,
    required this.source,
    this.initialKeyword = '斗罗',
  });

  final BookSourceModel source;
  final String initialKeyword;

  @override
  State<BookSourceDiagnosticPage> createState() =>
      _BookSourceDiagnosticPageState();
}

class _BookSourceDiagnosticPageState extends State<BookSourceDiagnosticPage> {
  late final TextEditingController _keywordController;
  late NovelSourceCapabilityReport _capabilityReport;

  bool _running = false;
  String _runtimeError = '';
  _RuntimeDiagnosticResult? _runtimeResult;

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController(text: widget.initialKeyword);
    _capabilityReport =
        NovelSourceCapabilityDetector.detect(widget.source.toJson());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runDiagnostic();
    });
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _runDiagnostic() async {
    final keyword = _keywordController.text.trim().isEmpty
        ? '斗罗'
        : _keywordController.text.trim();

    setState(() {
      _running = true;
      _runtimeError = '';
    });

    final startedAt = DateTime.now();
    final steps = <_RuntimeDiagnosticStep>[];

    _RuntimeDiagnosticResult? nextResult;
    String nextError = '';

    try {
      final sourceImpl =
          NovelSourceFactory.fromBookSourceJson(widget.source.toJson());

      steps.add(
        _RuntimeDiagnosticStep(
          title: '适配器识别',
          state: _RuntimeDiagnosticStepState.success,
          summary: '当前命中适配器：${_capabilityReport.adapterLabel}',
          detail: [
            '书源名：${_capabilityReport.sourceName}',
            '站点：${_capabilityReport.baseUrl.isNotEmpty ? _capabilityReport.baseUrl : "(空)"}',
            '适配器：${_capabilityReport.adapterLabel}',
            '静态状态：${_capabilityReport.statusLabel}',
          ].join('\n'),
          durationMs: 0,
        ),
      );

      List<dynamic> books = const [];
      dynamic detail;
      String firstBookTitle = '';
      String firstBookId = '';

      {
        final sw = Stopwatch()..start();
        try {
          books = await sourceImpl.searchBooks(keyword, page: 1);
          sw.stop();

          if (books.isEmpty) {
            steps.add(
              _RuntimeDiagnosticStep(
                title: '搜索测试',
                state: _RuntimeDiagnosticStepState.warning,
                summary: '搜索请求成功，但未返回结果',
                detail: '关键词：$keyword\n'
                    '说明：接口可访问，但当前关键词下没有搜索结果，或解析规则未取到列表。',
                durationMs: sw.elapsedMilliseconds,
              ),
            );
          } else {
            final previewTitles = books
                .take(8)
                .map((e) => (e.title ?? '').toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();

            final first = books.first;
            firstBookTitle = (first.title ?? '').toString();
            firstBookId = (first.id ?? '').toString();

            steps.add(
              _RuntimeDiagnosticStep(
                title: '搜索测试',
                state: _RuntimeDiagnosticStepState.success,
                summary: '搜索成功，共返回 ${books.length} 条结果',
                detail: [
                  '关键词：$keyword',
                  '结果数：${books.length}',
                  if (previewTitles.isNotEmpty) ...[
                    '前几本书：',
                    ...previewTitles.map((e) => '• $e'),
                  ],
                ].join('\n'),
                durationMs: sw.elapsedMilliseconds,
              ),
            );
          }
        } catch (e) {
          sw.stop();
          steps.add(
            _RuntimeDiagnosticStep(
              title: '搜索测试',
              state: _RuntimeDiagnosticStepState.failure,
              summary: '搜索阶段失败',
              detail: '关键词：$keyword\n错误：$e',
              durationMs: sw.elapsedMilliseconds,
            ),
          );
        }
      }

      if (books.isNotEmpty) {
        final first = books.first;

        final sw = Stopwatch()..start();
        try {
          detail = await sourceImpl.fetchDetail(
            bookId: (first.id ?? '').toString(),
            detailUrl: (first.detailUrl ?? '').toString().trim().isEmpty
                ? null
                : (first.detailUrl ?? '').toString(),
          );
          sw.stop();

          final chapters = detail.chapters as List<dynamic>;
          final chapterCount = chapters.length;

          if (chapterCount == 0) {
            steps.add(
              _RuntimeDiagnosticStep(
                title: '详情 / 目录测试',
                state: _RuntimeDiagnosticStepState.warning,
                summary: '详情获取成功，但目录为空',
                detail: [
                  '书名：${detail.book.title}',
                  '书籍 ID：${detail.book.id}',
                  '目录数：0',
                  '说明：详情页可访问，但没有取到章节列表。',
                ].join('\n'),
                durationMs: sw.elapsedMilliseconds,
              ),
            );
          } else {
            final previewTitles = chapters
                .take(8)
                .map((e) => (e.title ?? '').toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();

            steps.add(
              _RuntimeDiagnosticStep(
                title: '详情 / 目录测试',
                state: _RuntimeDiagnosticStepState.success,
                summary: '详情与目录解析成功，共 $chapterCount 章',
                detail: [
                  '书名：${detail.book.title}',
                  '书籍 ID：${detail.book.id}',
                  '目录数：$chapterCount',
                  if (previewTitles.isNotEmpty) ...[
                    '前几章：',
                    ...previewTitles.map((e) => '• $e'),
                  ],
                ].join('\n'),
                durationMs: sw.elapsedMilliseconds,
              ),
            );
          }
        } catch (e) {
          sw.stop();
          steps.add(
            _RuntimeDiagnosticStep(
              title: '详情 / 目录测试',
              state: _RuntimeDiagnosticStepState.failure,
              summary: '详情或目录阶段失败',
              detail: [
                '目标书籍：${firstBookTitle.isNotEmpty ? firstBookTitle : "(未知)"}',
                if (firstBookId.isNotEmpty) '书籍 ID：$firstBookId',
                '错误：$e',
              ].join('\n'),
              durationMs: sw.elapsedMilliseconds,
            ),
          );
        }
      } else {
        steps.add(
          const _RuntimeDiagnosticStep(
            title: '详情 / 目录测试',
            state: _RuntimeDiagnosticStepState.skipped,
            summary: '由于搜索无结果，跳过详情与目录测试',
            detail: '没有搜索结果可用于详情测试。',
            durationMs: 0,
          ),
        );
      }

      if (detail != null &&
          detail.chapters is List &&
          (detail.chapters as List).isNotEmpty) {
        final sw = Stopwatch()..start();
        try {
          final content = await sourceImpl.fetchChapter(
            detail: detail,
            chapterIndex: 0,
          );
          sw.stop();

          final text = (content.content ?? '').toString().trim();

          if (text.isEmpty) {
            steps.add(
              _RuntimeDiagnosticStep(
                title: '正文测试',
                state: _RuntimeDiagnosticStepState.warning,
                summary: '章节请求成功，但正文为空',
                detail: [
                  '章节：${content.title}',
                  '说明：章节接口可访问，但正文解析结果为空。',
                ].join('\n'),
                durationMs: sw.elapsedMilliseconds,
              ),
            );
          } else {
            final preview = text.length > 220
                ? '${text.substring(0, 220)}...'
                : text;

            steps.add(
              _RuntimeDiagnosticStep(
                title: '正文测试',
                state: _RuntimeDiagnosticStepState.success,
                summary: '正文解析成功，已获取首章内容',
                detail: [
                  '章节：${content.title}',
                  '正文预览：',
                  preview,
                ].join('\n\n'),
                durationMs: sw.elapsedMilliseconds,
              ),
            );
          }
        } catch (e) {
          sw.stop();
          steps.add(
            _RuntimeDiagnosticStep(
              title: '正文测试',
              state: _RuntimeDiagnosticStepState.failure,
              summary: '正文阶段失败',
              detail: '错误：$e',
              durationMs: sw.elapsedMilliseconds,
            ),
          );
        }
      } else {
        steps.add(
          const _RuntimeDiagnosticStep(
            title: '正文测试',
            state: _RuntimeDiagnosticStepState.skipped,
            summary: '由于目录为空或详情失败，跳过正文测试',
            detail: '没有可用章节可用于正文测试。',
            durationMs: 0,
          ),
        );
      }

      nextResult = _RuntimeDiagnosticResult(
        keyword: keyword,
        startedAt: startedAt,
        adapterLabel: _capabilityReport.adapterLabel,
        steps: steps,
      );
    } catch (e) {
      nextError = '诊断执行失败：$e';
    }

    if (!mounted) return;

    setState(() {
      _runtimeResult = nextResult;
      _runtimeError = nextError;
      _running = false;
      _capabilityReport =
          NovelSourceCapabilityDetector.detect(widget.source.toJson());
    });
  }

  Future<void> _copyReport() async {
    final capability = _capabilityReport;
    final runtime = _runtimeResult;

    final lines = <String>[
      '【书源诊断报告】',
      '书源名：${widget.source.bookSourceName}',
      '站点：${widget.source.bookSourceUrl}',
      '适配器：${capability.adapterLabel}',
      '静态状态：${capability.statusLabel}',
      '',
      '【能力支持】',
      ...capability.capabilityItems.map(
        (e) => '- ${e.label}：${e.supported ? "支持" : "不支持"}',
      ),
      '',
      '【命中特征】',
      if (capability.matchedSignals.isEmpty) '- 无',
      ...capability.matchedSignals.map((e) => '- $e'),
      '',
      '【高级规则特征】',
      ..._enabledFeatureLabels(capability),
      '',
      '【阻塞项】',
      if (capability.blockers.isEmpty) '- 无',
      ...capability.blockers.map((e) => '- $e'),
      '',
      '【警告 / 建议】',
      if (capability.warnings.isEmpty) '- 无',
      ...capability.warnings.map((e) => '- $e'),
    ];

    if (runtime != null) {
      lines
        ..add('')
        ..add('【运行时测试】')
        ..add('关键词：${runtime.keyword}')
        ..add('时间：${runtime.startedAt.toLocal()}')
        ..add('总体结果：${runtime.overallSummary}')
        ..add('')
        ..addAll(
          runtime.steps.asMap().entries.expand((entry) {
            final index = entry.key;
            final step = entry.value;
            return [
              '[$index] ${step.title}',
              '状态：${_stateText(step.state)}',
              '耗时：${step.durationMs} ms',
              '摘要：${step.summary}',
              if (step.detail.trim().isNotEmpty) '详情：${step.detail}',
              '',
            ];
          }),
        );
    }

    if (_runtimeError.trim().isNotEmpty) {
      lines
        ..add('')
        ..add('【运行时错误】')
        ..add(_runtimeError.trim());
    }

    await Clipboard.setData(
      ClipboardData(text: lines.join('\n')),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('诊断报告已复制到剪贴板')),
    );
  }

  List<String> _enabledFeatureLabels(NovelSourceCapabilityReport report) {
    final enabled = report.featureFlags.entries.where((e) => e.value).toList();
    if (enabled.isEmpty) return const ['- 无'];

    return enabled.map((e) => '- ${_featureLabel(e.key)}').toList();
  }

  Color _stateColor(_RuntimeDiagnosticStepState state) {
    switch (state) {
      case _RuntimeDiagnosticStepState.success:
        return Colors.green;
      case _RuntimeDiagnosticStepState.warning:
        return Colors.orange;
      case _RuntimeDiagnosticStepState.failure:
        return Colors.redAccent;
      case _RuntimeDiagnosticStepState.skipped:
        return Colors.grey;
    }
  }

  IconData _stateIcon(_RuntimeDiagnosticStepState state) {
    switch (state) {
      case _RuntimeDiagnosticStepState.success:
        return Icons.check_circle_rounded;
      case _RuntimeDiagnosticStepState.warning:
        return Icons.warning_amber_rounded;
      case _RuntimeDiagnosticStepState.failure:
        return Icons.cancel_rounded;
      case _RuntimeDiagnosticStepState.skipped:
        return Icons.skip_next_rounded;
    }
  }

  String _stateText(_RuntimeDiagnosticStepState state) {
    switch (state) {
      case _RuntimeDiagnosticStepState.success:
        return '成功';
      case _RuntimeDiagnosticStepState.warning:
        return '警告';
      case _RuntimeDiagnosticStepState.failure:
        return '失败';
      case _RuntimeDiagnosticStepState.skipped:
        return '跳过';
    }
  }

  String _featureLabel(String key) {
    switch (key) {
      case 'hasAtJs':
        return '@js';
      case 'hasJsBlock':
        return '<js>脚本块';
      case 'hasJavaAjax':
        return 'java.ajax';
      case 'hasJavaMd5':
        return 'java.md5Encode';
      case 'hasJavaPut':
        return 'java.put';
      case 'hasJavaGet':
        return 'java.get';
      case 'hasAtPut':
        return '@put';
      case 'hasAesDecode':
        return 'AES 解密';
      case 'hasExploreMenu':
        return '发现页菜单数组';
      case 'hasHeaderAuth':
        return '自定义鉴权头';
      default:
        return key;
    }
  }

  Widget _buildSourceCard() {
    final source = widget.source;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            source.bookSourceName.isNotEmpty ? source.bookSourceName : '未命名书源',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '地址：${source.bookSourceUrl.isNotEmpty ? source.bookSourceUrl : "(空)"}',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            '分组：${source.bookSourceGroup.isNotEmpty ? source.bookSourceGroup : "(空)"}',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            '搜索：${source.searchUrl.isNotEmpty ? source.searchUrl : "(空)"}',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            '发现页：${source.exploreUrl.isNotEmpty ? source.exploreUrl : "(空)"}',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '测试参数',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keywordController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _runDiagnostic(),
            decoration: InputDecoration(
              labelText: '测试关键词',
              hintText: '例如：斗罗 / 凡人 / 遮天',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFFF7F8FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _running ? null : _runDiagnostic,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(_running ? '诊断中...' : '开始诊断'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: (_runtimeResult == null && _runtimeError.isEmpty) || _running
                    ? null
                    : _copyReport,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('复制报告'),
              ),
            ],
          ),
          if (_runtimeError.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _runtimeError,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStaticSummaryCard() {
    final report = _capabilityReport;

    final overallColor = report.isUsableForRead
        ? Colors.green
        : report.isPartiallySupported
            ? Colors.orange
            : Colors.redAccent;

    Widget statChip(String text, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '静态规则分析',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: overallColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '状态：${report.statusLabel}\n适配器：${report.adapterLabel}',
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              statChip(
                '搜索 ${report.supportsSearch ? "支持" : "不支持"}',
                report.supportsSearch ? Colors.green : Colors.grey,
              ),
              statChip(
                '发现 ${report.supportsExplore ? "支持" : "不支持"}',
                report.supportsExplore ? Colors.green : Colors.grey,
              ),
              statChip(
                '详情 ${report.supportsDetail ? "支持" : "不支持"}',
                report.supportsDetail ? Colors.green : Colors.grey,
              ),
              statChip(
                '目录 ${report.supportsToc ? "支持" : "不支持"}',
                report.supportsToc ? Colors.green : Colors.grey,
              ),
              statChip(
                '正文 ${report.supportsContent ? "支持" : "不支持"}',
                report.supportsContent ? Colors.green : Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (report.matchedSignals.isNotEmpty) ...[
            const Text(
              '命中特征',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ...report.matchedSignals.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $e',
                  style: const TextStyle(fontSize: 12.8, color: Colors.black87),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (report.blockers.isNotEmpty) ...[
            const Text(
              '阻塞项',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 6),
            ...report.blockers.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $e',
                  style: const TextStyle(
                    fontSize: 12.8,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (report.warnings.isNotEmpty) ...[
            const Text(
              '警告 / 建议',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 6),
            ...report.warnings.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $e',
                  style: const TextStyle(
                    fontSize: 12.8,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRuntimeSummaryCard(_RuntimeDiagnosticResult report) {
    final overallColor = report.hasFailure
        ? Colors.redAccent
        : (report.warningCount > 0 || report.skippedCount > 0)
            ? Colors.orange
            : Colors.green;

    Widget statChip(String text, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '运行时测试结果',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: overallColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            report.overallSummary,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              statChip('成功 ${report.successCount}', Colors.green),
              statChip('警告 ${report.warningCount}', Colors.orange),
              statChip('失败 ${report.failureCount}', Colors.redAccent),
              statChip('跳过 ${report.skippedCount}', Colors.grey),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '关键词：${report.keyword}',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            '时间：${report.startedAt.toLocal()}',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            '适配器：${report.adapterLabel}',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(_RuntimeDiagnosticStep step, int index) {
    final color = _stateColor(step.state);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(_stateIcon(step.state), color: color),
          title: Text(
            '${index + 1}. ${step.title}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              step.summary,
              style: const TextStyle(
                fontSize: 12.5,
                color: Colors.black54,
              ),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _stateText(step.state),
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${step.durationMs} ms',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
          children: [
            if (step.detail.trim().isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '暂无更多详情',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black45,
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  step.detail,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: Colors.black87,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportSection() {
    if (_running && _runtimeResult == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        alignment: Alignment.center,
        child: const Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text(
              '正在诊断书源，请稍候...',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    }

    final runtime = _runtimeResult;
    if (runtime == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        alignment: Alignment.center,
        child: const Text(
          '点击“开始诊断”后查看结果',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRuntimeSummaryCard(runtime),
        const SizedBox(height: 12),
        const Text(
          '诊断步骤',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...runtime.steps.asMap().entries.map(
              (entry) => _buildStepCard(entry.value, entry.key),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sourceName = widget.source.bookSourceName.isNotEmpty
        ? widget.source.bookSourceName
        : '书源诊断';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          sourceName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '重新诊断',
            onPressed: _running ? null : _runDiagnostic,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '复制报告',
            onPressed: (_runtimeResult == null && _runtimeError.isEmpty) || _running
                ? null
                : _copyReport,
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildSourceCard(),
          const SizedBox(height: 12),
          _buildInputCard(),
          const SizedBox(height: 12),
          _buildStaticSummaryCard(),
          const SizedBox(height: 12),
          _buildReportSection(),
        ],
      ),
    );
  }
}

enum _RuntimeDiagnosticStepState {
  success,
  warning,
  failure,
  skipped,
}

class _RuntimeDiagnosticStep {
  const _RuntimeDiagnosticStep({
    required this.title,
    required this.state,
    required this.summary,
    required this.detail,
    required this.durationMs,
  });

  final String title;
  final _RuntimeDiagnosticStepState state;
  final String summary;
  final String detail;
  final int durationMs;
}

class _RuntimeDiagnosticResult {
  const _RuntimeDiagnosticResult({
    required this.keyword,
    required this.startedAt,
    required this.adapterLabel,
    required this.steps,
  });

  final String keyword;
  final DateTime startedAt;
  final String adapterLabel;
  final List<_RuntimeDiagnosticStep> steps;

  int get successCount =>
      steps.where((e) => e.state == _RuntimeDiagnosticStepState.success).length;

  int get warningCount =>
      steps.where((e) => e.state == _RuntimeDiagnosticStepState.warning).length;

  int get failureCount =>
      steps.where((e) => e.state == _RuntimeDiagnosticStepState.failure).length;

  int get skippedCount =>
      steps.where((e) => e.state == _RuntimeDiagnosticStepState.skipped).length;

  bool get hasFailure => failureCount > 0;

  String get overallSummary {
    if (hasFailure) {
      return '本次诊断存在失败步骤，建议根据步骤详情继续排查。';
    }
    if (warningCount > 0 || skippedCount > 0) {
      return '本次诊断可以运行，但存在警告或跳过步骤，兼容性可能不完整。';
    }
    return '本次诊断全部关键步骤通过，书源可用性较好。';
    }
}