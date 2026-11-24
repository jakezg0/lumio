enum PaymentMethod {
  cash('Cash'),
  kaspiQr('Kaspi QR'),
  card('Card'),
  transfer('Transfer'),
  postPay('Post-pay');

  const PaymentMethod(this.label);
  final String label;

  static PaymentMethod fromName(String? value) {
    return PaymentMethod.values.firstWhere(
      (method) => method.name == value,
      orElse: () => PaymentMethod.cash,
    );
  }
}

class DebtPayment {
  const DebtPayment({
    required this.amount,
    required this.paidAt,
  });

  final double amount;
  final DateTime paidAt;

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'paidAt': paidAt.toIso8601String(),
    };
  }

  factory DebtPayment.fromJson(Map<String, dynamic> json) {
    return DebtPayment(
      amount: (json['amount'] as num).toDouble(),
      paidAt: DateTime.parse(json['paidAt'] as String),
    );
  }
}

class SaleCashAdjustment {
  const SaleCashAdjustment({
    required this.method,
    required this.amount,
    required this.createdAt,
  });

  final PaymentMethod method;
  final double amount;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'method': method.name,
      'amount': amount,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory SaleCashAdjustment.fromJson(Map<String, dynamic> json) {
    return SaleCashAdjustment(
      method: PaymentMethod.fromName(json['method'] as String?),
      amount: (json['amount'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class DefectWriteOffItem {
  const DefectWriteOffItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    this.reason = '',
    required this.createdAt,
  });

  final String productId;
  final String productName;
  final double quantity;
  final double unitCost;
  final String reason;
  final DateTime createdAt;

  double get lineCost => unitCost * quantity;

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unitCost': unitCost,
      if (reason.isNotEmpty) 'reason': reason,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory DefectWriteOffItem.fromJson(Map<String, dynamic> json) {
    return DefectWriteOffItem(
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unitCost: (json['unitCost'] as num).toDouble(),
      reason: (json['reason'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class SaleItem {
  const SaleItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    required this.unitPrice,
  });

  final String productId;
  final String productName;
  final double quantity;
  final double unitCost;
  final double unitPrice;

  double get lineTotal => unitPrice * quantity;
  double get lineCost => unitCost * quantity;
  double get lineProfit => lineTotal - lineCost;

  SaleItem copyWith({
    String? productId,
    String? productName,
    double? quantity,
    double? unitCost,
    double? unitPrice,
  }) {
    return SaleItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unitCost': unitCost,
      'unitPrice': unitPrice,
    };
  }

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unitCost: (json['unitCost'] as num).toDouble(),
      unitPrice: (json['unitPrice'] as num).toDouble(),
    );
  }
}

class Sale {
  const Sale({
    required this.id,
    required this.items,
    required this.paymentMethod,
    this.secondaryPaymentMethod,
    this.secondaryAmount = 0,
    this.customerName = '',
    this.customerPhone = '',
    this.sellerName = '',
    this.discount = 0,
    this.discountReason = '',
    this._paidAmount,
    this.dueDate,
    this.paidAt,
    this.paymentHistory = const [],
    this.cashAdjustments = const [],
    this.defectItems = const [],
    this.refundedAmount = 0,
    this.returnedMoneyTotal = 0,
    this.refundNote = '',
    this.returnReason = '',
    this.archivedAt,
    this.trashedAt,
    required this.createdAt,
  });

  final String id;
  final List<SaleItem> items;
  final PaymentMethod paymentMethod;
  final PaymentMethod? secondaryPaymentMethod;
  final double secondaryAmount;
  final String customerName;
  final String customerPhone;
  final String sellerName;
  final double discount;
  final String discountReason;
  final double? _paidAmount;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final List<DebtPayment> paymentHistory;
  final List<SaleCashAdjustment> cashAdjustments;
  final List<DefectWriteOffItem> defectItems;
  final double refundedAmount;
  final double returnedMoneyTotal;
  final String refundNote;
  final String returnReason;
  final DateTime? archivedAt;
  final DateTime? trashedAt;
  final DateTime createdAt;

  bool get isArchived => archivedAt != null && trashedAt == null;
  bool get isTrashed => trashedAt != null;
  bool get isActive => archivedAt == null && trashedAt == null;
  bool get hasReturn =>
      returnedMoneyTotal > 0.009 || refundedAmount > 0.009 || refundNote.isNotEmpty;

  double get totalUnits => items.fold(0.0, (sum, item) => sum + item.quantity);

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get totalCost => items.fold(0.0, (sum, item) => sum + item.lineCost);

  double get total {
    final value = subtotal - discount - refundedAmount;
    return value < 0 ? 0 : value;
  }

  double get paidAmount {
    if (_paidAmount != null) {
      return _paidAmount.clamp(0.0, total);
    }
    return paymentMethod == PaymentMethod.postPay ? 0.0 : total;
  }

  double get remainingDebt {
    final diff = total - paidAmount;
    return diff <= 0.009 ? 0.0 : diff;
  }

  bool get isPaid => remainingDebt <= 0.009;

  bool get isSplitPayment =>
      secondaryPaymentMethod != null && secondaryAmount > 0.009;

  double get primaryPaymentAmount =>
      isSplitPayment ? (total - secondaryAmount).clamp(0.0, total) : paidAmount;

  double get profit => total - totalCost;

  String get receiptCode {
    final y = (createdAt.year % 100).toString().padLeft(2, '0');
    final m = createdAt.month.toString().padLeft(2, '0');
    final d = createdAt.day.toString().padLeft(2, '0');
    final parts = id.split('_');
    final rawTail = parts.length >= 2 ? parts[1] : id;
    final digits = rawTail.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();
    final suffix = digits.length >= 4
        ? digits.substring(digits.length - 4)
        : digits.padLeft(4, '0');
    final seq = parts.length >= 3 ? parts.last : '';
    final seqClean = seq.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();
    return 'C$y$m$d-$suffix$seqClean';
  }

  Sale copyWith({
    String? id,
    List<SaleItem>? items,
    PaymentMethod? paymentMethod,
    PaymentMethod? secondaryPaymentMethod,
    bool clearSecondaryPaymentMethod = false,
    double? secondaryAmount,
    String? customerName,
    String? customerPhone,
    String? sellerName,
    double? discount,
    String? discountReason,
    double? paidAmount,
    DateTime? dueDate,
    DateTime? paidAt,
    bool clearPaidAt = false,
    List<DebtPayment>? paymentHistory,
    List<SaleCashAdjustment>? cashAdjustments,
    List<DefectWriteOffItem>? defectItems,
    double? refundedAmount,
    double? returnedMoneyTotal,
    String? refundNote,
    String? returnReason,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    DateTime? trashedAt,
    bool clearTrashedAt = false,
    DateTime? createdAt,
  }) {
    return Sale(
      id: id ?? this.id,
      items: items ?? this.items,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      secondaryPaymentMethod: clearSecondaryPaymentMethod
          ? null
          : (secondaryPaymentMethod ?? this.secondaryPaymentMethod),
      secondaryAmount: secondaryAmount ?? this.secondaryAmount,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      sellerName: sellerName ?? this.sellerName,
      discount: discount ?? this.discount,
      discountReason: discountReason ?? this.discountReason,
      paidAmount: paidAmount ?? this.paidAmount,
      dueDate: dueDate ?? this.dueDate,
      paidAt: clearPaidAt ? null : (paidAt ?? this.paidAt),
      paymentHistory: paymentHistory ?? this.paymentHistory,
      cashAdjustments: cashAdjustments ?? this.cashAdjustments,
      defectItems: defectItems ?? this.defectItems,
      refundedAmount: refundedAmount ?? this.refundedAmount,
      returnedMoneyTotal: returnedMoneyTotal ?? this.returnedMoneyTotal,
      refundNote: refundNote ?? this.refundNote,
      returnReason: returnReason ?? this.returnReason,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      trashedAt: clearTrashedAt ? null : (trashedAt ?? this.trashedAt),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'items': items.map((item) => item.toJson()).toList(),
      'paymentMethod': paymentMethod.name,
      if (secondaryPaymentMethod != null)
        'secondaryPaymentMethod': secondaryPaymentMethod!.name,
      if (secondaryAmount > 0) 'secondaryAmount': secondaryAmount,
      'customerName': customerName,
      if (customerPhone.isNotEmpty) 'customerPhone': customerPhone,
      if (sellerName.isNotEmpty) 'sellerName': sellerName,
      'discount': discount,
      if (discountReason.isNotEmpty) 'discountReason': discountReason,
      'paidAmount': paidAmount,
      'dueDate': dueDate?.toIso8601String(),
      'paidAt': paidAt?.toIso8601String(),
      'paymentHistory': paymentHistory.map((p) => p.toJson()).toList(),
      if (cashAdjustments.isNotEmpty)
        'cashAdjustments': cashAdjustments.map((c) => c.toJson()).toList(),
      if (defectItems.isNotEmpty)
        'defectItems': defectItems.map((d) => d.toJson()).toList(),
      if (refundedAmount > 0) 'refundedAmount': refundedAmount,
      if (returnedMoneyTotal > 0) 'returnedMoneyTotal': returnedMoneyTotal,
      if (refundNote.isNotEmpty) 'refundNote': refundNote,
      if (returnReason.isNotEmpty) 'returnReason': returnReason,
      'archivedAt': archivedAt?.toIso8601String(),
      'trashedAt': trashedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Sale.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>? ?? const []);
    final rawHistory = (json['paymentHistory'] as List<dynamic>? ?? const []);
    final rawAdjustments =
        (json['cashAdjustments'] as List<dynamic>? ?? const []);
    final rawDefects = (json['defectItems'] as List<dynamic>? ?? const []);
    final dueDateRaw = json['dueDate'] as String?;
    final paidAtRaw = json['paidAt'] as String?;
    final archivedRaw = json['archivedAt'] as String?;
    final trashedRaw = json['trashedAt'] as String?;
    return Sale(
      id: json['id'] as String,
      items: rawItems
          .map((item) => SaleItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      paymentMethod: PaymentMethod.fromName(json['paymentMethod'] as String?),
      secondaryPaymentMethod: json['secondaryPaymentMethod'] != null
          ? PaymentMethod.fromName(json['secondaryPaymentMethod'] as String?)
          : null,
      secondaryAmount: (json['secondaryAmount'] as num?)?.toDouble() ?? 0,
      customerName: (json['customerName'] as String?) ?? '',
      customerPhone: (json['customerPhone'] as String?) ?? '',
      sellerName: (json['sellerName'] as String?) ?? '',
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      discountReason: (json['discountReason'] as String?) ?? '',
      paidAmount: (json['paidAmount'] as num?)?.toDouble(),
      dueDate: dueDateRaw != null ? DateTime.tryParse(dueDateRaw) : null,
      paidAt: paidAtRaw != null ? DateTime.tryParse(paidAtRaw) : null,
      paymentHistory: rawHistory
          .map((p) => DebtPayment.fromJson(p as Map<String, dynamic>))
          .toList(),
      cashAdjustments: rawAdjustments
          .map((c) => SaleCashAdjustment.fromJson(c as Map<String, dynamic>))
          .toList(),
      defectItems: rawDefects
          .map((d) => DefectWriteOffItem.fromJson(d as Map<String, dynamic>))
          .toList(),
      refundedAmount: (json['refundedAmount'] as num?)?.toDouble() ?? 0,
      returnedMoneyTotal:
          (json['returnedMoneyTotal'] as num?)?.toDouble() ?? 0,
      refundNote: (json['refundNote'] as String?) ?? '',
      returnReason: (json['returnReason'] as String?) ?? '',
      archivedAt: archivedRaw != null ? DateTime.tryParse(archivedRaw) : null,
      trashedAt: trashedRaw != null ? DateTime.tryParse(trashedRaw) : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class HeldSale {
  const HeldSale({
    required this.id,
    this.label = '',
    required this.quantities,
    required this.createdAt,
  });

  final String id;
  final String label;
  final Map<String, double> quantities;
  final DateTime createdAt;

  double get totalUnits =>
      quantities.values.fold(0.0, (sum, q) => sum + (q > 0 ? q : 0));

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'quantities': quantities,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory HeldSale.fromJson(Map<String, dynamic> json) {
    final rawQty = json['quantities'] as Map<String, dynamic>? ?? const {};
    return HeldSale(
      id: json['id'] as String,
      label: (json['label'] as String?) ?? '',
      quantities: {
        for (final entry in rawQty.entries)
          if ((entry.value as num).toDouble() > 0)
            entry.key: (entry.value as num).toDouble(),
      },
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
