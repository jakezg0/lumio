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
    this.unitWeight = '',
    this.unit = '',
    required this.costPrice,
    required this.sellPrice,
    required this.stock,
    this.lowStockThreshold = 5,
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
  final String unitWeight;
  final String unit;
  final double costPrice;
  final double sellPrice;
  final int stock;
  final int lowStockThreshold;
  final DateTime? archivedAt;
  final DateTime? trashedAt;
  final DateTime updatedAt;

  bool get isArchived => archivedAt != null && trashedAt == null;
  bool get isTrashed => trashedAt != null;
  bool get isActive => archivedAt == null && trashedAt == null;

  double get unitProfit => sellPrice - costPrice;

  double get marginPercent =>
      sellPrice > 0 ? ((sellPrice - costPrice) / sellPrice) * 100 : 0;

  double get inventoryValue => costPrice * stock;

  double get potentialRevenue => sellPrice * stock;

  bool get isOutOfStock => stock <= 0;

  bool get isLowStock => stock > 0 && stock <= lowStockThreshold;

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
    String? unitWeight,
    String? unit,
    double? costPrice,
    double? sellPrice,
    int? stock,
    int? lowStockThreshold,
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
      unitWeight: unitWeight ?? this.unitWeight,
      unit: unit ?? this.unit,
      costPrice: costPrice ?? this.costPrice,
      sellPrice: sellPrice ?? this.sellPrice,
      stock: stock ?? this.stock,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
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
      'unitWeight': unitWeight,
      'unit': unit,
      'costPrice': costPrice,
      'sellPrice': sellPrice,
      'stock': stock,
      'lowStockThreshold': lowStockThreshold,
      'archivedAt': archivedAt?.toIso8601String(),
      'trashedAt': trashedAt?.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Product.fromJson(Map<String, dynamic> json) {
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
      unitWeight: (json['unitWeight'] as String?) ?? '',
      unit: (json['unit'] as String?) ?? '',
      costPrice: (json['costPrice'] as num).toDouble(),
      sellPrice: (json['sellPrice'] as num).toDouble(),
      stock: (json['stock'] as num).toInt(),
      lowStockThreshold: (json['lowStockThreshold'] as num?)?.toInt() ?? 5,
      archivedAt: archivedRaw != null ? DateTime.tryParse(archivedRaw) : null,
      trashedAt: trashedRaw != null ? DateTime.tryParse(trashedRaw) : null,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
