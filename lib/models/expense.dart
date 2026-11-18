enum ExpenseCategory {
  purchase('purchase'),
  rent('rent'),
  delivery('delivery'),
  utilities('utilities'),
  other('other');

  const ExpenseCategory(this.code);
  final String code;

  static ExpenseCategory fromCode(String? code) {
    return ExpenseCategory.values.firstWhere(
      (c) => c.code == code,
      orElse: () => ExpenseCategory.other,
    );
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    this.note = '',
    this.trashedAt,
    required this.createdAt,
  });

  final String id;
  final String title;
  final ExpenseCategory category;
  final double amount;
  final String note;
  final DateTime? trashedAt;
  final DateTime createdAt;

  bool get isTrashed => trashedAt != null;
  bool get isActive => trashedAt == null;

  Expense copyWith({
    String? id,
    String? title,
    ExpenseCategory? category,
    double? amount,
    String? note,
    DateTime? trashedAt,
    bool clearTrashedAt = false,
    DateTime? createdAt,
  }) {
    return Expense(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      note: note ?? this.note,
      trashedAt: clearTrashedAt ? null : (trashedAt ?? this.trashedAt),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'category': category.code,
      'amount': amount,
      'note': note,
      'trashedAt': trashedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Expense.fromJson(Map<String, dynamic> json) {
    final trashedRaw = json['trashedAt'] as String?;
    return Expense(
      id: json['id'] as String,
      title: json['title'] as String,
      category: ExpenseCategory.fromCode(json['category'] as String?),
      amount: (json['amount'] as num).toDouble(),
      note: (json['note'] as String?) ?? '',
      trashedAt: trashedRaw != null ? DateTime.tryParse(trashedRaw) : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
