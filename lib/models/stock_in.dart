enum StockInDiscrepancyType {
  shortage,
  defect,
  mismatch,
}

class SupplierDebtPayment {
  const SupplierDebtPayment({
    required this.amount,
    required this.paidAt,
  });

  final double amount;
  final DateTime paidAt;

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'paidAt': paidAt.toIso8601String(),
      };

  factory SupplierDebtPayment.fromJson(Map<String, dynamic> json) {
    return SupplierDebtPayment(
      amount: (json['amount'] as num).toDouble(),
      paidAt: DateTime.parse(json['paidAt'] as String),
    );
  }
}

class StockInItem {
  const StockInItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    this.newSellPrice,
    this.discrepancyType,
    this.discrepancyQty = 0,
    this.discrepancyNote = '',
  });

  final String productId;
  final String productName;
  final double quantity;
  final double unitCost;
  final double? newSellPrice;
  final StockInDiscrepancyType? discrepancyType;
  final double discrepancyQty;
  final String discrepancyNote;

  double get lineTotal => quantity * unitCost;

  bool get hasDiscrepancy =>
      discrepancyType != null && discrepancyQty > 0.0005;

  double get discrepancyCost =>
      hasDiscrepancy ? discrepancyQty * unitCost : 0.0;

  StockInItem copyWith({
    String? productId,
    String? productName,
    double? quantity,
    double? unitCost,
    double? newSellPrice,
    StockInDiscrepancyType? discrepancyType,
    bool clearDiscrepancy = false,
    double? discrepancyQty,
    String? discrepancyNote,
  }) {
    return StockInItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
      newSellPrice: newSellPrice ?? this.newSellPrice,
      discrepancyType:
          clearDiscrepancy ? null : (discrepancyType ?? this.discrepancyType),
      discrepancyQty:
          clearDiscrepancy ? 0 : (discrepancyQty ?? this.discrepancyQty),
      discrepancyNote:
          clearDiscrepancy ? '' : (discrepancyNote ?? this.discrepancyNote),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unitCost': unitCost,
      if (newSellPrice != null) 'newSellPrice': newSellPrice,
      if (hasDiscrepancy) 'discrepancyType': discrepancyType!.name,
      if (hasDiscrepancy) 'discrepancyQty': discrepancyQty,
      if (hasDiscrepancy && discrepancyNote.trim().isNotEmpty)
        'discrepancyNote': discrepancyNote.trim(),
    };
  }

  factory StockInItem.fromJson(Map<String, dynamic> json) {
    final rawType = json['discrepancyType'] as String?;
    StockInDiscrepancyType? parsedType;
    if (rawType != null && rawType.isNotEmpty) {
      for (final t in StockInDiscrepancyType.values) {
        if (t.name == rawType) {
          parsedType = t;
          break;
        }
      }
    }
    return StockInItem(
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unitCost: (json['unitCost'] as num).toDouble(),
      newSellPrice: (json['newSellPrice'] as num?)?.toDouble(),
      discrepancyType: parsedType,
      discrepancyQty: (json['discrepancyQty'] as num?)?.toDouble() ?? 0.0,
      discrepancyNote: (json['discrepancyNote'] as String?) ?? '',
    );
  }
}

class StockInRecord {
  const StockInRecord({
    required this.id,
    this.supplierName = '',
    this.currencyCode = '',
    this.exchangeRate,
    required this.items,
    this.isCredit = false,
    this.paidAmount = 0,
    this.paidAt,
    this.paymentHistory = const [],
    required this.createdAt,
  });

  final String id;
  final String supplierName;
  final String currencyCode;
  final double? exchangeRate;
  final List<StockInItem> items;
  final bool isCredit;
  final double paidAmount;
  final DateTime? paidAt;
  final List<SupplierDebtPayment> paymentHistory;
  final DateTime createdAt;

  double get totalUnits => items.fold(0.0, (sum, item) => sum + item.quantity);
  double get totalCost => items.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get effectivePaidAmount =>
      isCredit ? paidAmount.clamp(0.0, totalCost) : totalCost;

  double get remainingDebt =>
      isCredit ? (totalCost - effectivePaidAmount).clamp(0.0, double.infinity) : 0.0;

  bool get isPaid => !isCredit || remainingDebt <= 0.009;

  bool get isPartiallyPaid =>
      isCredit && effectivePaidAmount > 0.009 && !isPaid;

  bool get hasDiscrepancy => items.any((i) => i.hasDiscrepancy);

  List<StockInItem> get discrepancyItems =>
      items.where((i) => i.hasDiscrepancy).toList(growable: false);

  double get totalDiscrepancyUnits => items.fold(
        0.0,
        (sum, i) => sum + (i.hasDiscrepancy ? i.discrepancyQty : 0.0),
      );

  double get totalDiscrepancyCost =>
      items.fold(0.0, (sum, i) => sum + i.discrepancyCost);

  String get exchangeRateLabel {
    final code = currencyCode.trim().toUpperCase();
    final rate = exchangeRate;
    if (code.isEmpty || rate == null || rate <= 0) return '';
    final rateStr = rate == rate.roundToDouble()
        ? rate.toStringAsFixed(0)
        : rate.toStringAsFixed(2);
    return '1 $code = $rateStr';
  }

  StockInRecord copyWith({
    String? id,
    String? supplierName,
    String? currencyCode,
    double? exchangeRate,
    List<StockInItem>? items,
    bool? isCredit,
    double? paidAmount,
    DateTime? paidAt,
    bool clearPaidAt = false,
    List<SupplierDebtPayment>? paymentHistory,
    DateTime? createdAt,
  }) {
    return StockInRecord(
      id: id ?? this.id,
      supplierName: supplierName ?? this.supplierName,
      currencyCode: currencyCode ?? this.currencyCode,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      items: items ?? this.items,
      isCredit: isCredit ?? this.isCredit,
      paidAmount: paidAmount ?? this.paidAmount,
      paidAt: clearPaidAt ? null : (paidAt ?? this.paidAt),
      paymentHistory: paymentHistory ?? this.paymentHistory,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'supplierName': supplierName,
      if (currencyCode.trim().isNotEmpty) 'currencyCode': currencyCode.trim(),
      if (exchangeRate != null && exchangeRate! > 0)
        'exchangeRate': exchangeRate,
      'items': items.map((i) => i.toJson()).toList(),
      if (isCredit) 'isCredit': true,
      if (isCredit) 'paidAmount': paidAmount,
      if (paidAt != null) 'paidAt': paidAt!.toIso8601String(),
      if (paymentHistory.isNotEmpty)
        'paymentHistory': paymentHistory.map((p) => p.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory StockInRecord.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>? ?? const []);
    final rawHistory = (json['paymentHistory'] as List<dynamic>? ?? const []);
    return StockInRecord(
      id: json['id'] as String,
      supplierName: (json['supplierName'] as String?) ?? '',
      currencyCode: (json['currencyCode'] as String?) ?? '',
      exchangeRate: (json['exchangeRate'] as num?)?.toDouble(),
      items: rawItems
          .map((e) => StockInItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      isCredit: (json['isCredit'] as bool?) ?? false,
      paidAmount: (json['paidAmount'] as num?)?.toDouble() ?? 0.0,
      paidAt: json['paidAt'] != null
          ? DateTime.parse(json['paidAt'] as String)
          : null,
      paymentHistory: rawHistory
          .map((e) => SupplierDebtPayment.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class StockInDraft {
  const StockInDraft({
    this.supplierName = '',
    this.supplierPhone = '',
    this.currencyCode = '',
    this.exchangeRate,
    this.recordAsExpense = true,
    this.isCredit = false,
    this.initialPaidAmount = 0,
    this.quantities = const {},
    this.unitCosts = const {},
    this.sellPrices = const {},
    this.discrepancyTypes = const {},
    this.discrepancyQtys = const {},
    this.discrepancyNotes = const {},
  });

  final String supplierName;
  final String supplierPhone;
  final String currencyCode;
  final double? exchangeRate;
  final bool recordAsExpense;
  final bool isCredit;
  final double initialPaidAmount;
  final Map<String, double> quantities;
  final Map<String, double> unitCosts;
  final Map<String, double> sellPrices;
  final Map<String, StockInDiscrepancyType> discrepancyTypes;
  final Map<String, double> discrepancyQtys;
  final Map<String, String> discrepancyNotes;

  double get totalUnits =>
      quantities.values.fold(0.0, (sum, q) => sum + (q > 0 ? q : 0));

  bool get hasContent =>
      supplierName.trim().isNotEmpty ||
      supplierPhone.trim().isNotEmpty ||
      (exchangeRate != null && exchangeRate! > 0) ||
      isCredit ||
      initialPaidAmount > 0 ||
      quantities.values.any((q) => q > 0) ||
      discrepancyQtys.values.any((q) => q > 0);

  Map<String, dynamic> toJson() {
    return {
      'supplierName': supplierName,
      if (supplierPhone.trim().isNotEmpty) 'supplierPhone': supplierPhone.trim(),
      if (currencyCode.trim().isNotEmpty) 'currencyCode': currencyCode.trim(),
      if (exchangeRate != null && exchangeRate! > 0)
        'exchangeRate': exchangeRate,
      'recordAsExpense': recordAsExpense,
      if (isCredit) 'isCredit': true,
      if (initialPaidAmount > 0) 'initialPaidAmount': initialPaidAmount,
      'quantities': quantities,
      'unitCosts': unitCosts,
      'sellPrices': sellPrices,
      if (discrepancyTypes.isNotEmpty)
        'discrepancyTypes': discrepancyTypes.map((k, v) => MapEntry(k, v.name)),
      if (discrepancyQtys.isNotEmpty) 'discrepancyQtys': discrepancyQtys,
      if (discrepancyNotes.isNotEmpty) 'discrepancyNotes': discrepancyNotes,
    };
  }

  factory StockInDraft.fromJson(Map<String, dynamic> json) {
    final rawQty = json['quantities'] as Map<String, dynamic>? ?? const {};
    final rawCosts = json['unitCosts'] as Map<String, dynamic>? ?? const {};
    final rawSells = json['sellPrices'] as Map<String, dynamic>? ?? const {};
    final rawDiscTypes =
        json['discrepancyTypes'] as Map<String, dynamic>? ?? const {};
    final rawDiscQtys =
        json['discrepancyQtys'] as Map<String, dynamic>? ?? const {};
    final rawDiscNotes =
        json['discrepancyNotes'] as Map<String, dynamic>? ?? const {};
    final parsedDiscTypes = <String, StockInDiscrepancyType>{};
    for (final entry in rawDiscTypes.entries) {
      for (final t in StockInDiscrepancyType.values) {
        if (t.name == entry.value) {
          parsedDiscTypes[entry.key] = t;
          break;
        }
      }
    }
    return StockInDraft(
      supplierName: (json['supplierName'] as String?) ?? '',
      supplierPhone: (json['supplierPhone'] as String?) ?? '',
      currencyCode: (json['currencyCode'] as String?) ?? '',
      exchangeRate: (json['exchangeRate'] as num?)?.toDouble(),
      recordAsExpense: (json['recordAsExpense'] as bool?) ?? true,
      isCredit: (json['isCredit'] as bool?) ?? false,
      initialPaidAmount:
          (json['initialPaidAmount'] as num?)?.toDouble() ?? 0.0,
      quantities: {
        for (final entry in rawQty.entries)
          if ((entry.value as num).toDouble() > 0)
            entry.key: (entry.value as num).toDouble(),
      },
      unitCosts: {
        for (final entry in rawCosts.entries)
          entry.key: (entry.value as num).toDouble(),
      },
      sellPrices: {
        for (final entry in rawSells.entries)
          entry.key: (entry.value as num).toDouble(),
      },
      discrepancyTypes: parsedDiscTypes,
      discrepancyQtys: {
        for (final entry in rawDiscQtys.entries)
          if ((entry.value as num).toDouble() > 0)
            entry.key: (entry.value as num).toDouble(),
      },
      discrepancyNotes: {
        for (final entry in rawDiscNotes.entries)
          if ('${entry.value}'.trim().isNotEmpty)
            entry.key: '${entry.value}'.trim(),
      },
    );
  }
}

class StocktakeDraft {
  const StocktakeDraft({
    this.counts = const {},
    this.countedIds = const [],
    this.countFromZero = false,
    this.selectedCategory,
  });

  final Map<String, double> counts;
  final List<String> countedIds;
  final bool countFromZero;
  final String? selectedCategory;

  bool get hasContent =>
      counts.isNotEmpty || countedIds.isNotEmpty || countFromZero;

  Map<String, dynamic> toJson() {
    return {
      'counts': counts,
      'countedIds': countedIds,
      'countFromZero': countFromZero,
      if (selectedCategory != null) 'selectedCategory': selectedCategory,
    };
  }

  factory StocktakeDraft.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['counts'] as Map<String, dynamic>? ?? const {};
    final rawCounted = json['countedIds'] as List<dynamic>? ?? const [];
    return StocktakeDraft(
      counts: {
        for (final entry in rawCounts.entries)
          entry.key: (entry.value as num).toDouble(),
      },
      countedIds: rawCounted.map((e) => '$e').toList(),
      countFromZero: (json['countFromZero'] as bool?) ?? false,
      selectedCategory: json['selectedCategory'] as String?,
    );
  }
}
