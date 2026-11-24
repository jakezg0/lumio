class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    this.sku = '',
    this.nomenclature = '',
    this.printName = '',
    this.packQty = '',
    this.boxQty = '',
    this.packBarcode = '',
    this.boxBarcode = '',
    this.extraBarcodes = const [],
    this.unitWeight = '',
    this.unit = '',
    this.imagePath = '',
    required this.costPrice,
    required this.sellPrice,
    this.wholesalePrice = 0,
    this.wholesaleMinQty = 0,
    required this.stock,
    this.lowStockThreshold = 5,
    this.expiryDate,
    this.outOfStockSince,
    this.totalOutOfStockDays = 0,
    this.archivedAt,
    this.trashedAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String category;
  final String sku;
  final String nomenclature;
  final String printName;
  final String packQty;
  final String boxQty;
  final String packBarcode;
  final String boxBarcode;
  final List<String> extraBarcodes;
  final String unitWeight;
  final String unit;
  final String imagePath;
  final double costPrice;
  final double sellPrice;
  final double wholesalePrice;
  final int wholesaleMinQty;
  final double stock;
  final int lowStockThreshold;
  final DateTime? expiryDate;
  final DateTime? outOfStockSince;
  final int totalOutOfStockDays;
  final DateTime? archivedAt;
  final DateTime? trashedAt;
  final DateTime updatedAt;

  bool get isArchived => archivedAt != null && trashedAt == null;
  bool get isTrashed => trashedAt != null;
  bool get isActive => archivedAt == null && trashedAt == null;

  bool get hasWholesalePrice => wholesalePrice > 0.009;

  bool get hasAutoWholesale => hasWholesalePrice && wholesaleMinQty > 0;

  bool isAutoWholesaleForQty(num qty) =>
      hasAutoWholesale && qty >= wholesaleMinQty;

  double get unitProfit => sellPrice - costPrice;

  double get marginPercent =>
      sellPrice > 0 ? ((sellPrice - costPrice) / sellPrice) * 100 : 0;

  double get wholesaleMarginPercent => wholesalePrice > 0
      ? ((wholesalePrice - costPrice) / wholesalePrice) * 100
      : 0;

  double get inventoryValue => costPrice * stock;

  double get potentialRevenue => sellPrice * stock;

  bool get isOutOfStock => stock <= 0;

  bool get isLowStock => stock > 0 && stock <= lowStockThreshold;

  bool get hasExpiryDate => expiryDate != null;

  int? daysUntilExpiry({DateTime? now}) {
    final exp = expiryDate;
    if (exp == null) return null;
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final target = DateTime(exp.year, exp.month, exp.day);
    return target.difference(today).inDays;
  }

  bool isExpired({DateTime? now}) {
    final days = daysUntilExpiry(now: now);
    return days != null && days < 0;
  }

  bool isExpiringSoon({int withinDays = 30, DateTime? now}) {
    final days = daysUntilExpiry(now: now);
    return days != null && days >= 0 && days <= withinDays;
  }

  bool isExpiringOrExpired({int withinDays = 30, DateTime? now}) {
    final days = daysUntilExpiry(now: now);
    return days != null && days <= withinDays;
  }

  int get currentOutOfStockDays {
    if (stock > 0) return 0;
    final since = outOfStockSince ?? updatedAt;
    final days = DateTime.now().difference(since).inDays;
    return days < 0 ? 0 : days;
  }

  int get cumulativeOutOfStockDays =>
      totalOutOfStockDays + currentOutOfStockDays;

  Product copyWith({
    String? id,
    String? name,
    String? category,
    String? sku,
    String? nomenclature,
    String? printName,
    String? packQty,
    String? boxQty,
    String? packBarcode,
    String? boxBarcode,
    List<String>? extraBarcodes,
    String? unitWeight,
    String? unit,
    String? imagePath,
    double? costPrice,
    double? sellPrice,
    double? wholesalePrice,
    int? wholesaleMinQty,
    double? stock,
    int? lowStockThreshold,
    DateTime? expiryDate,
    bool clearExpiryDate = false,
    DateTime? outOfStockSince,
    bool clearOutOfStockSince = false,
    int? totalOutOfStockDays,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    DateTime? trashedAt,
    bool clearTrashedAt = false,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      sku: sku ?? this.sku,
      nomenclature: nomenclature ?? this.nomenclature,
      printName: printName ?? this.printName,
      packQty: packQty ?? this.packQty,
      boxQty: boxQty ?? this.boxQty,
      packBarcode: packBarcode ?? this.packBarcode,
      boxBarcode: boxBarcode ?? this.boxBarcode,
      extraBarcodes: extraBarcodes ?? this.extraBarcodes,
      unitWeight: unitWeight ?? this.unitWeight,
      unit: unit ?? this.unit,
      imagePath: imagePath ?? this.imagePath,
      costPrice: costPrice ?? this.costPrice,
      sellPrice: sellPrice ?? this.sellPrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      wholesaleMinQty: wholesaleMinQty ?? this.wholesaleMinQty,
      stock: stock ?? this.stock,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      expiryDate: clearExpiryDate ? null : (expiryDate ?? this.expiryDate),
      outOfStockSince: clearOutOfStockSince
          ? null
          : (outOfStockSince ?? this.outOfStockSince),
      totalOutOfStockDays: totalOutOfStockDays ?? this.totalOutOfStockDays,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      trashedAt: clearTrashedAt ? null : (trashedAt ?? this.trashedAt),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'sku': sku,
      'nomenclature': nomenclature,
      'printName': printName,
      'packQty': packQty,
      'boxQty': boxQty,
      'packBarcode': packBarcode,
      'boxBarcode': boxBarcode,
      if (extraBarcodes.isNotEmpty) 'extraBarcodes': extraBarcodes,
      'unitWeight': unitWeight,
      'unit': unit,
      if (imagePath.isNotEmpty) 'imagePath': imagePath,
      'costPrice': costPrice,
      'sellPrice': sellPrice,
      if (wholesalePrice > 0) 'wholesalePrice': wholesalePrice,
      if (wholesaleMinQty > 0) 'wholesaleMinQty': wholesaleMinQty,
      'stock': stock,
      'lowStockThreshold': lowStockThreshold,
      if (expiryDate != null)
        'expiryDate': expiryDate!.toIso8601String(),
      if (outOfStockSince != null)
        'outOfStockSince': outOfStockSince!.toIso8601String(),
      if (totalOutOfStockDays > 0) 'totalOutOfStockDays': totalOutOfStockDays,
      'archivedAt': archivedAt?.toIso8601String(),
      'trashedAt': trashedAt?.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final expiryRaw = json['expiryDate'] as String?;
    final outOfStockRaw = json['outOfStockSince'] as String?;
    final archivedRaw = json['archivedAt'] as String?;
    final trashedRaw = json['trashedAt'] as String?;
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      category: (json['category'] as String?) ?? 'General',
      sku: (json['sku'] as String?) ?? '',
      nomenclature: (json['nomenclature'] as String?) ?? '',
      printName: (json['printName'] as String?) ?? '',
      packQty: (json['packQty'] as String?) ?? '',
      boxQty: (json['boxQty'] as String?) ?? '',
      packBarcode: (json['packBarcode'] as String?) ?? '',
      boxBarcode: (json['boxBarcode'] as String?) ?? '',
      extraBarcodes: (json['extraBarcodes'] as List<dynamic>? ?? const [])
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      unitWeight: (json['unitWeight'] as String?) ?? '',
      unit: (json['unit'] as String?) ?? '',
      imagePath: (json['imagePath'] as String?) ?? '',
      costPrice: (json['costPrice'] as num).toDouble(),
      sellPrice: (json['sellPrice'] as num).toDouble(),
      wholesalePrice: (json['wholesalePrice'] as num?)?.toDouble() ?? 0,
      wholesaleMinQty:
          ((json['wholesaleMinQty'] as num?)?.toInt() ?? 0).clamp(0, 999999),
      stock: (json['stock'] as num).toDouble(),
      lowStockThreshold: (json['lowStockThreshold'] as num?)?.toInt() ?? 5,
      expiryDate: expiryRaw != null ? DateTime.tryParse(expiryRaw) : null,
      outOfStockSince:
          outOfStockRaw != null ? DateTime.tryParse(outOfStockRaw) : null,
      totalOutOfStockDays:
          (json['totalOutOfStockDays'] as num?)?.toInt() ?? 0,
      archivedAt: archivedRaw != null ? DateTime.tryParse(archivedRaw) : null,
      trashedAt: trashedRaw != null ? DateTime.tryParse(trashedRaw) : null,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

class ProductChangeField {
  const ProductChangeField({
    this.key = '',
    required this.kind,
    required this.label,
    required this.oldValue,
    required this.newValue,
  });

  /// 'sellPrice' | 'costPrice' | 'stock' | 'unitWeight' | 'name' | 'category' | 'sku' | 'lowStockThreshold' | 'unit'
  final String key;
  /// 'price' | 'stock' | 'weight' | 'other'
  final String kind;
  final String label;
  final String oldValue;
  final String newValue;

  Map<String, dynamic> toJson() => {
        if (key.isNotEmpty) 'key': key,
        'kind': kind,
        'label': label,
        'oldValue': oldValue,
        'newValue': newValue,
      };

  factory ProductChangeField.fromJson(Map<String, dynamic> json) {
    return ProductChangeField(
      key: (json['key'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? 'other',
      label: (json['label'] as String?) ?? '',
      oldValue: (json['oldValue'] as String?) ?? '',
      newValue: (json['newValue'] as String?) ?? '',
    );
  }
}

class ProductChangeEntry {
  const ProductChangeEntry({
    required this.id,
    required this.productId,
    required this.productName,
    required this.source,
    required this.fields,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  /// 'edit' | 'stock_in' | 'stocktake' | 'sync'
  final String source;
  final List<ProductChangeField> fields;
  final DateTime createdAt;

  bool hasKind(String kind) => fields.any((f) => f.kind == kind);

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'productName': productName,
        'source': source,
        'fields': fields.map((f) => f.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory ProductChangeEntry.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'] as List<dynamic>? ?? const [];
    return ProductChangeEntry(
      id: (json['id'] as String?) ?? '',
      productId: (json['productId'] as String?) ?? '',
      productName: (json['productName'] as String?) ?? '',
      source: (json['source'] as String?) ?? 'edit',
      fields: rawFields
          .whereType<Map<String, dynamic>>()
          .map(ProductChangeField.fromJson)
          .toList(),
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
