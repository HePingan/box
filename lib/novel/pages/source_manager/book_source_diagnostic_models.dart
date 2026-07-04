/// 诊断步骤状态
enum RuntimeDiagnosticStepState { pending, running, success, warning, failure, skipped }

/// 诊断步骤
class RuntimeDiagnosticStep {
  final String title;
  final RuntimeDiagnosticStepState state;
  final String summary;
  final String detail;
  final int durationMs;

  const RuntimeDiagnosticStep({
    required this.title,
    required this.state,
    required this.summary,
    this.detail = '',
    this.durationMs = 0,
  });
}

/// 诊断结果
class RuntimeDiagnosticResult {
  final String keyword;
  final DateTime startedAt;
  final String adapterLabel;
  final List<RuntimeDiagnosticStep> steps;

  const RuntimeDiagnosticResult({
    required this.keyword,
    required this.startedAt,
    required this.adapterLabel,
    required this.steps,
  });

  int get elapsedSeconds => DateTime.now().difference(startedAt).inSeconds;
  int get successCount => steps.where((s) => s.state == RuntimeDiagnosticStepState.success).length;
  int get warningCount => steps.where((s) => s.state == RuntimeDiagnosticStepState.warning).length;
  int get failureCount => steps.where((s) => s.state == RuntimeDiagnosticStepState.failure).length;
  int get skippedCount => steps.where((s) => s.state == RuntimeDiagnosticStepState.skipped).length;

  String get briefReport {
    final buf = StringBuffer()
      ..writeln('🔍 诊断报告')
      ..writeln('关键词: $keyword')
      ..writeln('适配器: $adapterLabel')
      ..writeln('耗时: ${elapsedSeconds}s')
      ..writeln('总计: ${steps.length} 步')
      ..writeln('✅ 成功: $successCount')
      ..writeln('⚠️ 警告: $warningCount');
    if (failureCount > 0) {
      buf.writeln('❌ 失败: $failureCount');
    }
    if (skippedCount > 0) {
      buf.writeln('⏭️ 跳过: $skippedCount');
    }
    return buf.toString();
  }
}
