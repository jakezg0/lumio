class StockInItem {
  const StockInItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    this.newSellPrice,
  });

  final String productId;
  final String productName;
  final int quantity;
  final double unitCost;
  final double? newSellPrice;

  double get lineTotal => quantity * unitCost;

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unitCost': unitCost,
      if (newSellPrice != null) 'newSellPrice': newSellPrice,
    };
  }

  factory StockInItem.fromJson(Map<String, dynamic> json) {
    return StockInItem(
      productId: json['productId'] as String,
      productName: json['productName'] as String,
      quantity: (json['quantity'] as num).toInt(),
      unitCost: (json['unitCost'] as num).toDouble(),
      newSellPrice: (json['newSellPrice'] as num?)?.toDouble(),
    );
  }
}

class StockInRecord {
  const StockInRecord({
    required this.id,
    this.supplierName = '',
    required this.items,
    required this.createdAt,
  });

  final String id;
  final String supplierName;
  final List<StockInItem> items;
  final DateTime createdAt;

  int get totalUnits => items.fold(0, (sum, item) => sum + item.quantity);
  double get totalCost => items.fold(0.0, (sum, item) => sum + item.lineTotal);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'supplierName': supplierName,
      'items': items.map((i) => i.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory StockInRecord.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>? ?? const []);
    return StockInRecord(
      id: json['id'] as String,
      supplierName: (json['supplierName'] as String?) ?? '',
      items: rawItems
          .map((e) => StockInItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class StockInDraft {
  const StockInDraft({
    this.supplierName = '',
    this.recordAsExpense = true,
    this.quantities = const {},
    this.unitCosts = const {},
    this.sellPrices = const {},
  });

  final String supplierName;
  final bool recordAsExpense;
  final Map<String, int> quantities;
  final Map<String, double> unitCosts;
  final Map<String, double> sellPrices;

  int get totalUnits =>
      quantities.values.fold(0, (sum, q) => sum + (q > 0 ? q : 0));

  bool get hasContent =>
      supplierName.trim().isNotEmpty ||
      quantities.values.any((q) => q > 0);

  Map<String, dynamic> toJson() {
    return {
      'supplierName': supplierName,
      'recordAsExpense': recordAsExpense,
      'quantities': quantities,
      'unitCosts': unitCosts,
      'sellPrices': sellPrices,
    };
  }

  factory StockInDraft.fromJson(Map<String, dynamic> json) {
    final rawQty = json['quantities'] as Map<String, dynamic>? ?? const {};
    final rawCosts = json['unitCosts'] as Map<String, dynamic>? ?? const {};
    final rawSells = json['sellPrices'] as Map<String, dynamic>? ?? const {};
    return StockInDraft(
      supplierName: (json['supplierName'] as String?) ?? '',
      recordAsExpense: (json['recordAsExpense'] as bool?) ?? true,
      quantities: {
        for (final entry in rawQty.entries)
          if ((entry.value as num).toInt() > 0)
            entry.key: (entry.value as num).toInt(),
      },
      unitCosts: {
        for (final entry in rawCosts.entries)
          entry.key: (entry.value as num).toDouble(),
      },
      sellPrices: {
        for (final entry in rawSells.entries)
          entry.key: (entry.value as num).toDouble(),
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

  final Map<String, int> counts;
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
          entry.key: (entry.value as num).toInt(),
      },
      countedIds: rawCounted.map((e) => '$e').toList(),
      countFromZero: (json['countFromZero'] as bool?) ?? false,
      selectedCategory: json['selectedCategory'] as String?,
    );
  }
}
