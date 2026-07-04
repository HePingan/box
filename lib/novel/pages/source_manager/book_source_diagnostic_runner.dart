import 'dart:async';

import '../../core/models.dart';
import '../../core/novel_source_capability_detector.dart';
import '../../core/novel_source_factory.dart';
import 'book_source_model.dart';
import 'book_source_diagnostic_models.dart';

/// 书源诊断执行器
class BookSourceDiagnosticRunner {
  BookSourceDiagnosticRunner(this.bookSource);

  final BookSourceModel bookSource;

  Future<Map<String, dynamic>> runStaticAnalysis() async {
    final report = NovelSourceCapabilityDetector.detect(bookSource.toJson());
    final raw = bookSource.toJson();
    return {
      'report': report,
      'baseUrl': report.baseUrl,
      'sourceName': report.sourceName,
      'adapterLabel': report.adapterLabel,
      'statusLabel': report.statusLabel,
      'searchUrl': bookSource.searchUrl,
      'exploreUrl': bookSource.exploreUrl,
      'ruleSearch': raw['ruleSearch'],
      'ruleExplore': raw['ruleExplore'],
      'ruleBookInfo': raw['ruleBookInfo'],
      'ruleToc': raw['ruleToc'],
      'ruleContent': raw['ruleContent'],
      'header': raw['header'],
      'bookSourceGroup': bookSource.bookSourceGroup,
      'bookSourceName': bookSource.bookSourceName,
      'bookSourceUrl': bookSource.bookSourceUrl,
      'enabled': bookSource.enabled,
      'loginUrl': raw['loginUrl'],
      'webUrl': raw['webUrl'],
    };
  }

  Future<RuntimeDiagnosticResult> runRuntimeDiagnostic({
    String keyword = '斗罗',
    String? detailUrl,
  }) async {
    final startedAt = DateTime.now();
    final steps = <RuntimeDiagnosticStep>[];

    try {
      final sourceImpl = NovelSourceFactory.fromBookSourceJson(
        bookSource.toJson(),
      );

      // Step 1: 适配器识别
      final capabilityReport = NovelSourceCapabilityDetector.detect(
        bookSource.toJson(),
      );
      steps.add(RuntimeDiagnosticStep(
        title: '适配器识别',
        state: RuntimeDiagnosticStepState.success,
        summary: '当前命中适配器：${capabilityReport.adapterLabel}',
        detail: [
          '书源名：${capabilityReport.sourceName}',
          '站点：${capabilityReport.baseUrl.isNotEmpty ? capabilityReport.baseUrl : "(空)"}',
          '适配器：${capabilityReport.adapterLabel}',
          '静态状态：${capabilityReport.statusLabel}',
        ].join('\n'),
        durationMs: 0,
      ));

      // Step 2: 搜索测试
      List<dynamic> books = const [];
      String firstBookTitle = '';
      String firstBookId = '';
      {
        final sw = Stopwatch()..start();
        try {
          books = await sourceImpl.searchBooks(keyword, page: 1);
          sw.stop();

          if (books.isEmpty) {
            steps.add(RuntimeDiagnosticStep(
              title: '搜索测试',
              state: RuntimeDiagnosticStepState.warning,
              summary: '搜索请求成功，但未返回结果',
              detail: '关键词：$keyword\n'
                  '说明：接口可访问，但当前关键词下没有搜索结果，或解析规则未取到列表。',
              durationMs: sw.elapsedMilliseconds,
            ));
          } else {
            final previewTitles = books
                .take(8)
                .map((e) => (e.title ?? '').toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();
            final first = books.first;
            firstBookTitle = (first.title ?? '').toString();
            firstBookId = (first.id ?? '').toString();

            steps.add(RuntimeDiagnosticStep(
              title: '搜索测试',
              state: RuntimeDiagnosticStepState.success,
              summary: '搜索成功，共 ${books.length} 本',
              detail: '关键词：$keyword\n'
                  '匹配数：${books.length}\n'
                  '预览：${previewTitles.join("、")}',
              durationMs: sw.elapsedMilliseconds,
            ));
          }
        } catch (e) {
          sw.stop();
          steps.add(RuntimeDiagnosticStep(
            title: '搜索测试',
            state: RuntimeDiagnosticStepState.failure,
            summary: '搜索异常',
            detail: '关键词：$keyword\n错误：$e',
            durationMs: sw.elapsedMilliseconds,
          ));
        }
      }

      // Step 3: 详情测试
      if (firstBookTitle.isNotEmpty && firstBookId.isNotEmpty) {
        NovelDetail? detail;
        {
          final sw = Stopwatch()..start();
          try {
            detail = await sourceImpl.fetchDetail(
              bookId: firstBookId,
              detailUrl: detailUrl,
            );
            sw.stop();

            if (detail.chapters.isEmpty) {
              steps.add(RuntimeDiagnosticStep(
                title: '详情页测试',
                state: RuntimeDiagnosticStepState.warning,
                summary: '获取详情成功，但章节列表为空',
                detail: '书名：$firstBookTitle（$firstBookId）\n'
                    '章节数：${detail.chapters.length}',
                durationMs: sw.elapsedMilliseconds,
              ));
            } else {
              final previewChapters = detail.chapters
                  .take(5)
                  .map((e) => e.title)
                  .toList();
              steps.add(RuntimeDiagnosticStep(
                title: '详情页测试',
                state: RuntimeDiagnosticStepState.success,
                summary: '获取详情成功，共 ${detail.chapters.length} 章',
                detail: '书名：$firstBookTitle（$firstBookId）\n'
                    '章节数：${detail.chapters.length}\n'
                    '预览：${previewChapters.join("、")}',
                durationMs: sw.elapsedMilliseconds,
              ));
            }
          } catch (e) {
            sw.stop();
            steps.add(RuntimeDiagnosticStep(
              title: '详情页测试',
              state: RuntimeDiagnosticStepState.failure,
              summary: '获取详情异常',
              detail: '书名：$firstBookTitle（$firstBookId）\n错误：$e',
              durationMs: sw.elapsedMilliseconds,
            ));
          }
        }

        // Step 4: 正文测试
        if (detail != null && detail.chapters.isNotEmpty) {
          {
            final sw = Stopwatch()..start();
            try {
              final content = await sourceImpl.fetchChapter(
                detail: detail,
                chapterIndex: 0,
              );
              sw.stop();

              if (content.content.trim().isEmpty) {
                steps.add(RuntimeDiagnosticStep(
                  title: '正文测试',
                  state: RuntimeDiagnosticStepState.warning,
                  summary: '获取正文成功，但内容为空',
                  detail: '章节：${detail.chapters.first.title}\n'
                      '说明：请求成功但解析后内容为空，请检查正文解析规则。',
                  durationMs: sw.elapsedMilliseconds,
                ));
              } else {
                steps.add(RuntimeDiagnosticStep(
                  title: '正文测试',
                  state: RuntimeDiagnosticStepState.success,
                  summary: '获取正文成功，共 ${content.content.length} 字符',
                  detail: '章节：${detail.chapters.first.title}\n'
                      '字符数：${content.content.length}\n'
                      '预览：${content.content.substring(0, content.content.length.clamp(0, 120))}...',
                  durationMs: sw.elapsedMilliseconds,
                ));
              }
            } catch (e) {
              sw.stop();
              steps.add(RuntimeDiagnosticStep(
                title: '正文测试',
                state: RuntimeDiagnosticStepState.failure,
                summary: '获取正文异常',
                detail: '章节：${detail.chapters.first.title}\n错误：$e',
                durationMs: sw.elapsedMilliseconds,
              ));
            }
          }
        } else {
          steps.add(RuntimeDiagnosticStep(
            title: '正文测试',
            state: RuntimeDiagnosticStepState.skipped,
            summary: '跳过：章节列表为空',
            detail: '详情页未能返回有效章节列表，跳过正文测试。',
            durationMs: 0,
          ));
        }
      } else {
        steps.add(RuntimeDiagnosticStep(
          title: '详情页测试',
          state: RuntimeDiagnosticStepState.skipped,
          summary: '跳过：搜索未返回有效结果',
          detail: '搜索步骤未能获取到有效书籍信息，跳过详情测试。',
          durationMs: 0,
        ));
        steps.add(RuntimeDiagnosticStep(
          title: '正文测试',
          state: RuntimeDiagnosticStepState.skipped,
          summary: '跳过：搜索未返回有效结果',
          detail: '搜索步骤未能获取到有效书籍信息，跳过正文测试。',
          durationMs: 0,
        ));
      }
    } catch (e) {
      steps.add(RuntimeDiagnosticStep(
        title: '整体诊断',
        state: RuntimeDiagnosticStepState.failure,
        summary: '诊断流程异常',
        detail: '错误：$e',
        durationMs: 0,
      ));
    }

    return RuntimeDiagnosticResult(
      keyword: keyword,
      startedAt: startedAt,
      adapterLabel: NovelSourceCapabilityDetector.detect(bookSource.toJson()).adapterLabel,
      steps: steps,
    );
  }
}
