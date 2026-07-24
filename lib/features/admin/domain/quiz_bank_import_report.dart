class QuizBankImportReport {
  const QuizBankImportReport({
    required this.dryRun,
    required this.mode,
    required this.total,
    required this.inserted,
    required this.duplicateSkipped,
    required this.invalid,
    this.errors = const [],
  });

  final bool dryRun;
  final String mode;
  final int total;
  final int inserted;
  final int duplicateSkipped;
  final int invalid;
  final List<Map<String, dynamic>> errors;

  factory QuizBankImportReport.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    return QuizBankImportReport(
      dryRun: json['dryRun'] == true,
      mode: (json['mode'] ?? '').toString(),
      total: int.tryParse((json['total'] ?? 0).toString()) ?? 0,
      inserted: int.tryParse((json['inserted'] ?? 0).toString()) ?? 0,
      duplicateSkipped:
          int.tryParse((json['duplicateSkipped'] ?? 0).toString()) ?? 0,
      invalid: int.tryParse((json['invalid'] ?? 0).toString()) ?? 0,
      errors: rawErrors is List
          ? rawErrors
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false)
          : const [],
    );
  }
}
