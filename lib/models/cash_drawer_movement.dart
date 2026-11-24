class CashDrawerMovement {
  const CashDrawerMovement({
    required this.id,
    required this.isDeposit,
    required this.amount,
    this.note = '',
    this.sellerName = '',
    required this.createdAt,
  });

  final String id;
  final bool isDeposit;
  final double amount;
  final String note;
  final String sellerName;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'isDeposit': isDeposit,
      'amount': amount,
      'note': note,
      'sellerName': sellerName,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory CashDrawerMovement.fromJson(Map<String, dynamic> json) {
    return CashDrawerMovement(
      id: (json['id'] as String?) ?? '',
      isDeposit: json['isDeposit'] == true,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      note: (json['note'] as String?) ?? '',
      sellerName: (json['sellerName'] as String?) ?? '',
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
    );
  }
}
