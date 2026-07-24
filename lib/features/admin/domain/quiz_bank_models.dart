import 'admin_resource.dart';

class QuizBankQuestion extends ResourceData {
  const QuizBankQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.answer,
    required this.status,
    required this.tags,
    this.explanation = '',
    this.category = '',
    this.source = '',
    this.type = 'single_choice',
    this.revision = 0,
    this.createdAt,
    this.updatedAt,
    this.submitter,
    this.image = '',
  });

  final String id;
  final String question;
  final List<String> options;
  final String answer;
  final String status;
  final List<String> tags;
  final String explanation;
  final String category;
  final String source;
  final String type;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? submitter;
  final String image;

  bool get isPublished => status == 'published' || status == 'active';

  String get statusLabel => switch (status) {
    'published' || 'active' => '已发布',
    'pending' => '待审核',
    'rejected' => '已拒绝',
    'draft' => '草稿',
    _ => status.isEmpty ? '未知' : status,
  };

  factory QuizBankQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'] ?? json['choices'];
    final rawTags = json['tags'];
    return QuizBankQuestion(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      question: (json['question'] ?? json['title'] ?? json['content'] ?? '')
          .toString(),
      options: rawOptions is List
          ? rawOptions.map((value) => value.toString()).toList(growable: false)
          : const [],
      answer: (json['answer'] ?? json['correctAnswer'] ?? '').toString(),
      status: (json['status'] ?? 'draft').toString(),
      tags: rawTags is List
          ? rawTags.map((value) => value.toString()).toList(growable: false)
          : const [],
      explanation: (json['explanation'] ?? json['analysis'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      type: (json['type'] ?? 'single_choice').toString(),
      revision: int.tryParse((json['revision'] ?? 0).toString()) ?? 0,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
      submitter:
          json['submitter']?.toString() ?? json['submittedBy']?.toString(),
      image: (json['image'] ?? json['imageUrl'] ?? '').toString(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'question': question,
    'options': options,
    'answer': answer,
    'correctAnswer': answer,
    'type': type,
    if (category.isNotEmpty) 'category': category,
    if (source.isNotEmpty) 'source': source,
    'status': status,
    'tags': tags,
    if (explanation.isNotEmpty) 'explanation': explanation,
    if (explanation.isNotEmpty) 'analysis': explanation,
    if (image.isNotEmpty) 'image': image,
  };
}

class QuizBankSubmission {
  const QuizBankSubmission({
    required this.id,
    required this.question,
    required this.status,
    this.submitter,
    this.submittedAt,
    this.reviewNote = '',
    this.linkedQuestionId,
  });

  final String id;
  final QuizBankQuestion question;
  final String status;
  final String? submitter;
  final DateTime? submittedAt;
  final String reviewNote;
  final String? linkedQuestionId;

  bool get isPending => status == 'pending';
  bool get isMerged => status == 'merged';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  String get statusLabel => switch (status) {
    'pending' => '待审核',
    'approved' => '已通过',
    'merged' => '云端已有',
    'rejected' => '已拒绝',
    _ => status.isEmpty ? '未知' : status,
  };

  factory QuizBankSubmission.fromJson(Map<String, dynamic> json) {
    final question = json['question'];
    return QuizBankSubmission(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      question: QuizBankQuestion.fromJson(
        question is Map<String, dynamic>
            ? question
            : question is Map
            ? Map<String, dynamic>.from(question)
            : json,
      ),
      status: (json['status'] ?? 'pending').toString(),
      submitter:
          json['submitter']?.toString() ??
          json['submittedBy']?.toString() ??
          json['submitterUserId']?.toString(),
      submittedAt: DateTime.tryParse(
        (json['submittedAt'] ?? json['createdAt'] ?? '').toString(),
      ),
      reviewNote: (json['reviewNote'] ?? '').toString(),
      linkedQuestionId: json['linkedQuestionId']?.toString(),
    );
  }
}
