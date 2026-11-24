import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import '../models/cash_drawer_movement.dart';
import '../models/customer.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/stock_in.dart';

class InventoryValueSnapshot {
  const InventoryValueSnapshot({
    required this.monthKey,
    required this.capturedAt,
    required this.productsCount,
    required this.totalUnits,
    required this.costValue,
    required this.sellValue,
  });

  /// Format: 'YYYY-MM', e.g. '2026-11'
  final String monthKey;
  final DateTime capturedAt;
  final int productsCount;
  final double totalUnits;
  final double costValue;
  final double sellValue;

  double get expectedProfit => sellValue - costValue;

  int get year {
    final parts = monthKey.split('-');
    return parts.isNotEmpty
        ? (int.tryParse(parts[0]) ?? capturedAt.year)
        : capturedAt.year;
  }

  int get month {
    final parts = monthKey.split('-');
    return parts.length >= 2
        ? (int.tryParse(parts[1]) ?? capturedAt.month)
        : capturedAt.month;
  }

  Map<String, dynamic> toJson() => {
        'monthKey': monthKey,
        'capturedAt': capturedAt.toIso8601String(),
        'productsCount': productsCount,
        'totalUnits': totalUnits,
        'costValue': costValue,
        'sellValue': sellValue,
      };

  factory InventoryValueSnapshot.fromJson(Map<String, dynamic> json) {
    final captured =
        DateTime.tryParse('${json['capturedAt'] ?? ''}') ?? DateTime.now();
    final rawKey = '${json['monthKey'] ?? ''}'.trim();
    final key = rawKey.isNotEmpty
        ? rawKey
        : '${captured.year}-${captured.month.toString().padLeft(2, '0')}';
    return InventoryValueSnapshot(
      monthKey: key,
      capturedAt: captured,
      productsCount: (json['productsCount'] as num?)?.toInt() ?? 0,
      totalUnits: (json['totalUnits'] as num?)?.toDouble() ?? 0.0,
      costValue: (json['costValue'] as num?)?.toDouble() ?? 0.0,
      sellValue: (json['sellValue'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class FeatureUsageStat {
  const FeatureUsageStat({
    required this.count,
    this.lastUsedAt,
  });

  final int count;
  final DateTime? lastUsedAt;

  Map<String, dynamic> toJson() => {
        'count': count,
        if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
      };

  factory FeatureUsageStat.fromJson(Map<String, dynamic> json) {
    final rawDate = '${json['lastUsedAt'] ?? ''}'.trim();
    return FeatureUsageStat(
      count: (json['count'] as num?)?.toInt() ?? 0,
      lastUsedAt: rawDate.isNotEmpty ? DateTime.tryParse(rawDate) : null,
    );
  }
}

class ShopDataSnapshot {
  const ShopDataSnapshot({
    required this.products,
    required this.sales,
    this.expenses = const [],
    this.customers = const [],
    this.stockIns = const [],
    this.languageCode = 'auto',
    this.currencyCode = 'kzt',
    this.shopName = 'Lumio',
    this.shopAddress = '',
    this.shopPhone = '',
    this.receiptFooter = '',
    this.ownerPin = '',
    this.useBiometricUnlock = false,
    this.cashierMode = true,
    this.catalogSeeded = false,
    this.googleSheetsUrl = '',
    this.googleSheetsSecret = '',
    this.customCategories = const [],
    this.hiddenCustomerSuggestions = const [],
    this.stockInDraft,
    this.stocktakeDraft,
    this.heldSales = const [],
    this.productChanges = const [],
    this.negativeStockReminders = const {},
    this.allowNegativeStock = true,
    this.allowCashierDiscounts = true,
    this.autoBackupEnabled = true,
    this.lastAutoBackupAt = '',
    this.lastExternalBackupAt = '',
    this.lastExternalBackupReminderAt = '',
    this.lastCloudBackupProductsCount = -1,
    this.lastCloudBackupSalesCount = -1,
    this.pendingSync = false,
    this.cloudBackupHashes = const {},
    this.sheetCatalogBaseline = const {},
    this.inventorySnapshots = const [],
    this.featureUsage = const {},
    this.trashRetentionDays = 30,
    this.inventorySelectedCategory = '',
    this.inventorySort = 'newest',
    this.posSelectedCategory = '',
    this.sellers = const [],
    this.activeSeller = '',
    this.priceTagQueue = const [],
    this.cashDrawerMovements = const [],
  });

  final List<Product> products;
  final List<Sale> sales;
  final List<Expense> expenses;
  final List<Customer> customers;
  final List<StockInRecord> stockIns;
  final String languageCode;
  final String currencyCode;
  final String shopName;
  final String shopAddress;
  final String shopPhone;
  final String receiptFooter;
  final String ownerPin;
  final bool useBiometricUnlock;
  final bool cashierMode;
  final bool catalogSeeded;
  final String googleSheetsUrl;
  final String googleSheetsSecret;
  final List<String> customCategories;
  final List<String> hiddenCustomerSuggestions;
  final StockInDraft? stockInDraft;
  final StocktakeDraft? stocktakeDraft;
  final List<HeldSale> heldSales;
  final List<ProductChangeEntry> productChanges;
  final Map<String, int> negativeStockReminders;
  final bool allowNegativeStock;
  final bool allowCashierDiscounts;
  final bool autoBackupEnabled;
  final String lastAutoBackupAt;
  final String lastExternalBackupAt;
  final String lastExternalBackupReminderAt;
  final int lastCloudBackupProductsCount;
  final int lastCloudBackupSalesCount;
  final bool pendingSync;
  final Map<String, String> cloudBackupHashes;
  final Map<String, String> sheetCatalogBaseline;
  final List<InventoryValueSnapshot> inventorySnapshots;
  final Map<String, FeatureUsageStat> featureUsage;
  final int trashRetentionDays;
  final String inventorySelectedCategory;
  final String inventorySort;
  final String posSelectedCategory;
  final List<String> sellers;
  final String activeSeller;
  final List<String> priceTagQueue;
  final List<CashDrawerMovement> cashDrawerMovements;
}

abstract class InventoryStorage {
  Future<ShopDataSnapshot> load();
  Future<void> save(ShopDataSnapshot snapshot);
  Future<void> savePreRestoreBackup(ShopDataSnapshot snapshot);
  Future<({ShopDataSnapshot snapshot, DateTime savedAt})?>
      loadPreRestoreBackup();
  Future<List<ProductChangeEntry>> loadProductChanges({
    int? days,
    String? productId,
    bool priceOnly = false,
  });
  Future<int> deleteProductChanges({int? olderThanDays});
  Future<({List<Product> products, List<Sale> sales, List<Expense> expenses})>
      loadArchiveAndTrash();
  Future<List<Sale>> loadAllActiveSales();
}

List<ProductChangeEntry> filterProductChangesList(
  List<ProductChangeEntry> source, {
  int? days,
  String? productId,
  bool priceOnly = false,
}) {
  final cutoff = (days != null && days > 0)
      ? DateTime.now().subtract(Duration(days: days))
      : null;
  final result = source.where((e) {
    if (cutoff != null && e.createdAt.isBefore(cutoff)) return false;
    if (productId != null && productId.isNotEmpty && e.productId != productId) {
      return false;
    }
    if (priceOnly && !e.hasKind('price')) return false;
    return true;
  }).toList();
  result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return result;
}

ShopDataSnapshot _copySnapshotWithProductChanges(
  ShopDataSnapshot s,
  List<ProductChangeEntry> productChanges,
) {
  return ShopDataSnapshot(
    products: s.products,
    sales: s.sales,
    expenses: s.expenses,
    customers: s.customers,
    stockIns: s.stockIns,
    languageCode: s.languageCode,
    currencyCode: s.currencyCode,
    shopName: s.shopName,
    shopAddress: s.shopAddress,
    shopPhone: s.shopPhone,
    receiptFooter: s.receiptFooter,
    ownerPin: s.ownerPin,
    useBiometricUnlock: s.useBiometricUnlock,
    cashierMode: s.cashierMode,
    catalogSeeded: s.catalogSeeded,
    googleSheetsUrl: s.googleSheetsUrl,
    googleSheetsSecret: s.googleSheetsSecret,
    customCategories: s.customCategories,
    hiddenCustomerSuggestions: s.hiddenCustomerSuggestions,
    stockInDraft: s.stockInDraft,
    stocktakeDraft: s.stocktakeDraft,
    heldSales: s.heldSales,
    productChanges: productChanges,
    negativeStockReminders: s.negativeStockReminders,
    allowNegativeStock: s.allowNegativeStock,
    allowCashierDiscounts: s.allowCashierDiscounts,
    autoBackupEnabled: s.autoBackupEnabled,
    lastAutoBackupAt: s.lastAutoBackupAt,
    lastExternalBackupAt: s.lastExternalBackupAt,
    lastExternalBackupReminderAt: s.lastExternalBackupReminderAt,
    lastCloudBackupProductsCount: s.lastCloudBackupProductsCount,
    lastCloudBackupSalesCount: s.lastCloudBackupSalesCount,
    pendingSync: s.pendingSync,
    cloudBackupHashes: s.cloudBackupHashes,
    sheetCatalogBaseline: s.sheetCatalogBaseline,
    inventorySnapshots: s.inventorySnapshots,
    featureUsage: s.featureUsage,
    trashRetentionDays: s.trashRetentionDays,
    inventorySelectedCategory: s.inventorySelectedCategory,
    inventorySort: s.inventorySort,
    posSelectedCategory: s.posSelectedCategory,
    sellers: s.sellers,
    activeSeller: s.activeSeller,
    priceTagQueue: s.priceTagQueue,
    cashDrawerMovements: s.cashDrawerMovements,
  );
}

ShopDataSnapshot _mergeOlderProductChanges(
  ShopDataSnapshot next,
  List<ProductChangeEntry> existingChanges, {
  int inMemoryDays = 90,
}) {
  if (existingChanges.isEmpty) return next;
  final cutoff = DateTime.now().subtract(Duration(days: inMemoryDays));
  final nextIds = next.productChanges.map((e) => e.id).toSet();
  final preservedOld = existingChanges
      .where((e) => e.createdAt.isBefore(cutoff) && !nextIds.contains(e.id))
      .toList();
  if (preservedOld.isEmpty) return next;
  return _copySnapshotWithProductChanges(
    next,
    [...next.productChanges, ...preservedOld],
  );
}

class InMemoryInventoryStorage implements InventoryStorage {
  ShopDataSnapshot _snapshot = const ShopDataSnapshot(
    products: [],
    sales: [],
    expenses: [],
    customers: [],
    stockIns: [],
  );
  ({ShopDataSnapshot snapshot, DateTime savedAt})? _preRestoreBackup;

  @override
  Future<ShopDataSnapshot> load() async => _snapshot;

  @override
  Future<void> save(ShopDataSnapshot snapshot) async {
    _snapshot = _mergeOlderProductChanges(snapshot, _snapshot.productChanges);
  }

  @override
  Future<void> savePreRestoreBackup(ShopDataSnapshot snapshot) async {
    _preRestoreBackup = (snapshot: snapshot, savedAt: DateTime.now());
  }

  @override
  Future<({ShopDataSnapshot snapshot, DateTime savedAt})?>
      loadPreRestoreBackup() async => _preRestoreBackup;

  @override
  Future<({List<Product> products, List<Sale> sales, List<Expense> expenses})>
      loadArchiveAndTrash() async => (
        products: _snapshot.products.where((p) => !p.isActive).toList(),
        sales: _snapshot.sales.where((s) => !s.isActive).toList(),
        expenses: _snapshot.expenses.where((e) => e.isTrashed).toList(),
      );

  @override
  Future<List<Sale>> loadAllActiveSales() async =>
      _snapshot.sales.where((s) => s.isActive).toList();

  @override
  Future<List<ProductChangeEntry>> loadProductChanges({
    int? days,
    String? productId,
    bool priceOnly = false,
  }) async {
    return filterProductChangesList(
      _snapshot.productChanges,
      days: days,
      productId: productId,
      priceOnly: priceOnly,
    );
  }

  @override
  Future<int> deleteProductChanges({int? olderThanDays}) async {
    final before = _snapshot.productChanges.length;
    if (before == 0) return 0;
    final List<ProductChangeEntry> remaining;
    if (olderThanDays == null) {
      remaining = const [];
    } else {
      final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
      remaining = _snapshot.productChanges
          .where((e) => !e.createdAt.isBefore(cutoff))
          .toList();
    }
    final removed = before - remaining.length;
    if (removed > 0) {
      _snapshot = ShopDataSnapshot(
        products: _snapshot.products,
        sales: _snapshot.sales,
        expenses: _snapshot.expenses,
        customers: _snapshot.customers,
        stockIns: _snapshot.stockIns,
        languageCode: _snapshot.languageCode,
        currencyCode: _snapshot.currencyCode,
        shopName: _snapshot.shopName,
        shopAddress: _snapshot.shopAddress,
        shopPhone: _snapshot.shopPhone,
        receiptFooter: _snapshot.receiptFooter,
        ownerPin: _snapshot.ownerPin,
        useBiometricUnlock: _snapshot.useBiometricUnlock,
        cashierMode: _snapshot.cashierMode,
        catalogSeeded: _snapshot.catalogSeeded,
        googleSheetsUrl: _snapshot.googleSheetsUrl,
        googleSheetsSecret: _snapshot.googleSheetsSecret,
        customCategories: _snapshot.customCategories,
        hiddenCustomerSuggestions: _snapshot.hiddenCustomerSuggestions,
        stockInDraft: _snapshot.stockInDraft,
        stocktakeDraft: _snapshot.stocktakeDraft,
        heldSales: _snapshot.heldSales,
        productChanges: remaining,
        negativeStockReminders: _snapshot.negativeStockReminders,
        allowNegativeStock: _snapshot.allowNegativeStock,
        allowCashierDiscounts: _snapshot.allowCashierDiscounts,
        autoBackupEnabled: _snapshot.autoBackupEnabled,
        lastAutoBackupAt: _snapshot.lastAutoBackupAt,
        lastExternalBackupAt: _snapshot.lastExternalBackupAt,
        lastExternalBackupReminderAt: _snapshot.lastExternalBackupReminderAt,
        lastCloudBackupProductsCount: _snapshot.lastCloudBackupProductsCount,
        lastCloudBackupSalesCount: _snapshot.lastCloudBackupSalesCount,
        pendingSync: _snapshot.pendingSync,
        cloudBackupHashes: _snapshot.cloudBackupHashes,
        sheetCatalogBaseline: _snapshot.sheetCatalogBaseline,
        inventorySnapshots: _snapshot.inventorySnapshots,
        featureUsage: _snapshot.featureUsage,
        trashRetentionDays: _snapshot.trashRetentionDays,
      );
    }
    return removed;
  }
}

class JsonFileInventoryStorage implements InventoryStorage {
  JsonFileInventoryStorage({String? filePath}) : _customFilePath = filePath;

  final String? _customFilePath;
  File? _cachedFile;
  List<ProductChangeEntry> _archivedProductChanges = const [];

  String _androidPackageName() {
    try {
      final raw = File('/proc/self/cmdline').readAsStringSync();
      final clean = raw.split('\x00').first.split(':').first.trim();
      if (clean.isNotEmpty) return clean;
    } catch (_) {}
    return 'com.example.flutter_application_1';
  }

  String _androidDataRoot(String pkg) {
    for (final candidate in ['/data/user/0/$pkg', '/data/data/$pkg']) {
      if (Directory(candidate).existsSync()) return candidate;
    }
    final tempDir = Directory.systemTemp;
    if (tempDir.path.endsWith('/cache') ||
        tempDir.path.endsWith('/code_cache')) {
      return tempDir.parent.path;
    }
    return tempDir.path;
  }

  File _resolveFile() {
    if (_cachedFile != null) return _cachedFile!;
    if (_customFilePath != null && _customFilePath.isNotEmpty) {
      return _cachedFile = File(_customFilePath);
    }
    if (Platform.isAndroid) {
      final pkg = _androidPackageName();
      final appDataRoot = _androidDataRoot(pkg);
      final permanentDir = Directory('$appDataRoot/files/small_shop_inventory');
      if (!permanentDir.existsSync()) {
        permanentDir.createSync(recursive: true);
      }
      final permanentFile = File('${permanentDir.path}/shop_data.json');
      if (!permanentFile.existsSync()) {
        final tempPath = Directory.systemTemp.path;
        final legacyPaths = <String>[
          '$appDataRoot/code_cache/files/small_shop_inventory/shop_data.json',
          '$appDataRoot/code_cache/small_shop_inventory/shop_data.json',
          '$appDataRoot/cache/small_shop_inventory/shop_data.json',
          '$tempPath/files/small_shop_inventory/shop_data.json',
          '$tempPath/small_shop_inventory/shop_data.json',
        ];
        for (final legacyPath in legacyPaths) {
          if (legacyPath == permanentFile.path) continue;
          final legacyFile = File(legacyPath);
          if (legacyFile.existsSync()) {
            legacyFile.copySync(permanentFile.path);
            break;
          }
        }
      }
      return _cachedFile = permanentFile;
    }
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final baseDir = home != null && home.isNotEmpty
        ? Directory('$home/.small_shop_inventory')
        : Directory('${Directory.systemTemp.path}/small_shop_inventory');
    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
    }
    return _cachedFile = File('${baseDir.path}/shop_data.json');
  }

  @override
  Future<ShopDataSnapshot> load() async {
    try {
      final file = _resolveFile();
      if (!await file.exists()) {
        _archivedProductChanges = const [];
        return const ShopDataSnapshot(products: [], sales: [], expenses: []);
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _archivedProductChanges = const [];
        return const ShopDataSnapshot(products: [], sales: [], expenses: []);
      }
      final snapshot = await compute(_decodeSnapshotFromRawJson, raw);
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      _archivedProductChanges = snapshot.productChanges
          .where((e) => e.createdAt.isBefore(cutoff))
          .toList();
      return snapshot;
    } catch (_) {
      return const ShopDataSnapshot(products: [], sales: [], expenses: []);
    }
  }

  File _resolvePreRestoreFile() {
    final mainFile = _resolveFile();
    final path = mainFile.path;
    if (path.endsWith('.json')) {
      return File('${path.substring(0, path.length - 5)}_pre_restore.json');
    }
    return File('${path}_pre_restore.json');
  }

  @override
  Future<void> save(ShopDataSnapshot snapshot) async {
    try {
      final merged = _mergeOlderProductChanges(snapshot, _archivedProductChanges);
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      _archivedProductChanges = merged.productChanges
          .where((e) => e.createdAt.isBefore(cutoff))
          .toList();
      final file = _resolveFile();
      final payload = await compute(_encodeSnapshotToJson, merged);
      await writeTextFileAtomically(file, payload, validateJson: true);
    } catch (_) {
      // Preserve the previous valid file on write/verification failure.
    }
  }

  @override
  Future<void> savePreRestoreBackup(ShopDataSnapshot snapshot) async {
    final file = _resolvePreRestoreFile();
    final payload = await compute(
      _encodePreRestoreEnvelope,
      (snapshot: snapshot, savedAt: DateTime.now().toIso8601String()),
    );
    await writeTextFileAtomically(file, payload, validateJson: true);
  }

  @override
  Future<List<ProductChangeEntry>> loadProductChanges({
    int? days,
    String? productId,
    bool priceOnly = false,
  }) async {
    final snapshot = await load();
    return filterProductChangesList(
      snapshot.productChanges,
      days: days,
      productId: productId,
      priceOnly: priceOnly,
    );
  }

  @override
  Future<int> deleteProductChanges({int? olderThanDays}) async {
    final snapshot = await load();
    final before = snapshot.productChanges.length;
    if (before == 0) return 0;
    final List<ProductChangeEntry> remaining;
    if (olderThanDays == null) {
      remaining = const [];
    } else {
      final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
      remaining = snapshot.productChanges
          .where((e) => !e.createdAt.isBefore(cutoff))
          .toList();
    }
    final removed = before - remaining.length;
    if (removed > 0) {
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      _archivedProductChanges = remaining
          .where((e) => e.createdAt.isBefore(cutoff))
          .toList();
      await save(
        ShopDataSnapshot(
          products: snapshot.products,
          sales: snapshot.sales,
          expenses: snapshot.expenses,
          customers: snapshot.customers,
          stockIns: snapshot.stockIns,
          languageCode: snapshot.languageCode,
          currencyCode: snapshot.currencyCode,
          shopName: snapshot.shopName,
          shopAddress: snapshot.shopAddress,
          shopPhone: snapshot.shopPhone,
          receiptFooter: snapshot.receiptFooter,
          ownerPin: snapshot.ownerPin,
          useBiometricUnlock: snapshot.useBiometricUnlock,
          cashierMode: snapshot.cashierMode,
          catalogSeeded: snapshot.catalogSeeded,
          googleSheetsUrl: snapshot.googleSheetsUrl,
          googleSheetsSecret: snapshot.googleSheetsSecret,
          customCategories: snapshot.customCategories,
          hiddenCustomerSuggestions: snapshot.hiddenCustomerSuggestions,
          stockInDraft: snapshot.stockInDraft,
          stocktakeDraft: snapshot.stocktakeDraft,
          heldSales: snapshot.heldSales,
          productChanges: remaining,
          negativeStockReminders: snapshot.negativeStockReminders,
          allowNegativeStock: snapshot.allowNegativeStock,
          allowCashierDiscounts: snapshot.allowCashierDiscounts,
          autoBackupEnabled: snapshot.autoBackupEnabled,
          lastAutoBackupAt: snapshot.lastAutoBackupAt,
          lastExternalBackupAt: snapshot.lastExternalBackupAt,
          lastExternalBackupReminderAt: snapshot.lastExternalBackupReminderAt,
          lastCloudBackupProductsCount: snapshot.lastCloudBackupProductsCount,
          lastCloudBackupSalesCount: snapshot.lastCloudBackupSalesCount,
          pendingSync: snapshot.pendingSync,
          cloudBackupHashes: snapshot.cloudBackupHashes,
          sheetCatalogBaseline: snapshot.sheetCatalogBaseline,
          inventorySnapshots: snapshot.inventorySnapshots,
          featureUsage: snapshot.featureUsage,
          trashRetentionDays: snapshot.trashRetentionDays,
        ),
      );
    }
    return removed;
  }

  @override
  Future<({ShopDataSnapshot snapshot, DateTime savedAt})?>
      loadPreRestoreBackup() async {
    try {
      final file = _resolvePreRestoreFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return await compute(decodePreRestoreEnvelope, raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<({List<Product> products, List<Sale> sales, List<Expense> expenses})>
      loadArchiveAndTrash() async {
    final snapshot = await load();
    return (
      products: snapshot.products.where((p) => !p.isActive).toList(),
      sales: snapshot.sales.where((s) => !s.isActive).toList(),
      expenses: snapshot.expenses.where((e) => e.isTrashed).toList(),
    );
  }

  @override
  Future<List<Sale>> loadAllActiveSales() async {
    final snapshot = await load();
    return snapshot.sales.where((s) => s.isActive).toList();
  }
}

/// Atomically writes [content] via a `.tmp` sibling, verifies readback (and JSON
/// validity when [validateJson] is true), and only then replaces [targetFile].
Future<void> writeTextFileAtomically(
  File targetFile,
  String content, {
  bool validateJson = false,
}) async {
  final parent = targetFile.parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }
  final tmpFile = File('${targetFile.path}.tmp');
  try {
    await tmpFile.writeAsString(content, flush: true);
    final readBack = await tmpFile.readAsString();
    if (readBack != content) {
      throw const FileSystemException(
        'Atomic write verification failed: content mismatch',
      );
    }
    if (validateJson) {
      final decoded = jsonDecode(readBack);
      if (decoded is! Map && decoded is! List) {
        throw const FormatException(
          'Atomic JSON verification failed: root is not an object or array',
        );
      }
    }
    await tmpFile.rename(targetFile.path);
  } catch (_) {
    try {
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
    } catch (_) {}
    rethrow;
  }
}

ShopDataSnapshot _decodeSnapshotFromRawJson(String raw) {
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final rawProducts = decoded['products'] as List<dynamic>? ?? const [];
  final rawSales = decoded['sales'] as List<dynamic>? ?? const [];
  final rawExpenses = decoded['expenses'] as List<dynamic>? ?? const [];
  final rawCustomers = decoded['customers'] as List<dynamic>? ?? const [];
  final rawStockIns = decoded['stockIns'] as List<dynamic>? ?? const [];
  final rawCustomCats =
      decoded['customCategories'] as List<dynamic>? ?? const [];
  final rawHiddenCustomers =
      decoded['hiddenCustomerSuggestions'] as List<dynamic>? ?? const [];
  final rawHeldSales = decoded['heldSales'] as List<dynamic>? ?? const [];
  final hasAnyData = rawProducts.isNotEmpty ||
      rawSales.isNotEmpty ||
      rawExpenses.isNotEmpty ||
      rawCustomers.isNotEmpty ||
      rawStockIns.isNotEmpty;
  return ShopDataSnapshot(
    products: rawProducts
        .map((item) => Product.fromJson(item as Map<String, dynamic>))
        .toList(),
    sales: rawSales
        .map((item) => Sale.fromJson(item as Map<String, dynamic>))
        .toList(),
    expenses: rawExpenses
        .map((item) => Expense.fromJson(item as Map<String, dynamic>))
        .toList(),
    customers: rawCustomers
        .map((item) => Customer.fromJson(item as Map<String, dynamic>))
        .toList(),
    stockIns: rawStockIns
        .map((item) => StockInRecord.fromJson(item as Map<String, dynamic>))
        .toList(),
    languageCode: (decoded['languageCode'] as String?) ?? 'auto',
    currencyCode: (decoded['currencyCode'] as String?) ?? 'kzt',
    shopName: (decoded['shopName'] as String?) ?? 'Lumio',
    shopAddress: (decoded['shopAddress'] as String?) ?? '',
    shopPhone: (decoded['shopPhone'] as String?) ?? '',
    receiptFooter: (decoded['receiptFooter'] as String?) ?? '',
    ownerPin: (decoded['ownerPin'] as String?) ?? '',
    useBiometricUnlock: (decoded['useBiometricUnlock'] as bool?) ?? false,
    cashierMode: (decoded['cashierMode'] as bool?) ?? true,
    catalogSeeded: (decoded['catalogSeeded'] as bool?) ?? hasAnyData,
    googleSheetsUrl: (decoded['googleSheetsUrl'] as String?) ?? '',
    googleSheetsSecret: (decoded['googleSheetsSecret'] as String?) ?? '',
    customCategories: rawCustomCats.map((e) => '$e').toList(),
    hiddenCustomerSuggestions: rawHiddenCustomers.map((e) => '$e').toList(),
    stockInDraft: decoded['stockInDraft'] is Map<String, dynamic>
        ? StockInDraft.fromJson(
            decoded['stockInDraft'] as Map<String, dynamic>,
          )
        : null,
    stocktakeDraft: decoded['stocktakeDraft'] is Map<String, dynamic>
        ? StocktakeDraft.fromJson(
            decoded['stocktakeDraft'] as Map<String, dynamic>,
          )
        : null,
    heldSales: rawHeldSales
        .map((item) => HeldSale.fromJson(item as Map<String, dynamic>))
        .toList(),
    productChanges: (decoded['productChanges'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProductChangeEntry.fromJson)
        .toList(),
    negativeStockReminders:
        (decoded['negativeStockReminders'] as Map<String, dynamic>? ??
                const {})
            .map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0))
          ..removeWhere((_, v) => v <= 0),
    allowNegativeStock: (decoded['allowNegativeStock'] as bool?) ?? true,
    allowCashierDiscounts: (decoded['allowCashierDiscounts'] as bool?) ?? true,
    autoBackupEnabled: (decoded['autoBackupEnabled'] as bool?) ?? true,
    lastAutoBackupAt: (decoded['lastAutoBackupAt'] as String?) ?? '',
    lastExternalBackupAt: (decoded['lastExternalBackupAt'] as String?) ?? '',
    lastExternalBackupReminderAt:
        (decoded['lastExternalBackupReminderAt'] as String?) ?? '',
    lastCloudBackupProductsCount:
        (decoded['lastCloudBackupProductsCount'] as num?)?.toInt() ?? -1,
    lastCloudBackupSalesCount:
        (decoded['lastCloudBackupSalesCount'] as num?)?.toInt() ?? -1,
    pendingSync: (decoded['pendingSync'] as bool?) ?? false,
    cloudBackupHashes:
        (decoded['cloudBackupHashes'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, '$v')),
    sheetCatalogBaseline:
        (decoded['sheetCatalogBaseline'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, '$v')),
    inventorySnapshots:
        (decoded['inventorySnapshots'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(InventoryValueSnapshot.fromJson)
            .toList(),
    featureUsage: _decodeFeatureUsageMap(decoded['featureUsage']),
    trashRetentionDays:
        (decoded['trashRetentionDays'] as num?)?.toInt() ?? 30,
    inventorySelectedCategory:
        (decoded['inventorySelectedCategory'] as String?) ?? '',
    inventorySort: (decoded['inventorySort'] as String?) ?? 'newest',
    posSelectedCategory: (decoded['posSelectedCategory'] as String?) ?? '',
    sellers: (decoded['sellers'] as List<dynamic>? ?? const [])
        .map((e) => '$e')
        .where((e) => e.trim().isNotEmpty)
        .toList(),
    activeSeller: (decoded['activeSeller'] as String?) ?? '',
    priceTagQueue: (decoded['priceTagQueue'] as List<dynamic>? ?? const [])
        .map((e) => '$e')
        .where((e) => e.trim().isNotEmpty)
        .toList(),
    cashDrawerMovements: (decoded['cashDrawerMovements'] as List<dynamic>? ??
            const [])
        .whereType<Map<String, dynamic>>()
        .map(CashDrawerMovement.fromJson)
        .toList(),
  );
}

String encodePreRestoreEnvelope(
  ({ShopDataSnapshot snapshot, String savedAt}) args,
) {
  return jsonEncode({
    'savedAt': args.savedAt,
    'snapshot': jsonDecode(_encodeSnapshotToJson(args.snapshot)),
  });
}

String _encodePreRestoreEnvelope(
  ({ShopDataSnapshot snapshot, String savedAt}) args,
) =>
    encodePreRestoreEnvelope(args);

({ShopDataSnapshot snapshot, DateTime savedAt}) decodePreRestoreEnvelope(
  String raw,
) {
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final savedAt = DateTime.tryParse('${decoded['savedAt'] ?? ''}') ??
      DateTime.now();
  final snapMap = decoded['snapshot'] as Map<String, dynamic>;
  return (
    snapshot: _decodeSnapshotFromRawJson(jsonEncode(snapMap)),
    savedAt: savedAt,
  );
}

String _encodeSnapshotToJson(ShopDataSnapshot snapshot) {
  return jsonEncode({
    'products': snapshot.products.map((p) => p.toJson()).toList(),
    'sales': snapshot.sales.map((s) => s.toJson()).toList(),
    'expenses': snapshot.expenses.map((e) => e.toJson()).toList(),
    'customers': snapshot.customers.map((c) => c.toJson()).toList(),
    'stockIns': snapshot.stockIns.map((s) => s.toJson()).toList(),
    'languageCode': snapshot.languageCode,
    'currencyCode': snapshot.currencyCode,
    'shopName': snapshot.shopName,
    'shopAddress': snapshot.shopAddress,
    'shopPhone': snapshot.shopPhone,
    'receiptFooter': snapshot.receiptFooter,
    'ownerPin': snapshot.ownerPin,
    'useBiometricUnlock': snapshot.useBiometricUnlock,
    'cashierMode': snapshot.cashierMode,
    'catalogSeeded': snapshot.catalogSeeded,
    if (snapshot.googleSheetsUrl.isNotEmpty)
      'googleSheetsUrl': snapshot.googleSheetsUrl,
    if (snapshot.googleSheetsSecret.isNotEmpty)
      'googleSheetsSecret': snapshot.googleSheetsSecret,
    'customCategories': snapshot.customCategories,
    if (snapshot.hiddenCustomerSuggestions.isNotEmpty)
      'hiddenCustomerSuggestions': snapshot.hiddenCustomerSuggestions,
    if (snapshot.stockInDraft != null)
      'stockInDraft': snapshot.stockInDraft!.toJson(),
    if (snapshot.stocktakeDraft != null)
      'stocktakeDraft': snapshot.stocktakeDraft!.toJson(),
    if (snapshot.heldSales.isNotEmpty)
      'heldSales': snapshot.heldSales.map((h) => h.toJson()).toList(),
    if (snapshot.productChanges.isNotEmpty)
      'productChanges':
          snapshot.productChanges.map((c) => c.toJson()).toList(),
    if (snapshot.negativeStockReminders.isNotEmpty)
      'negativeStockReminders': snapshot.negativeStockReminders,
    'allowNegativeStock': snapshot.allowNegativeStock,
    'allowCashierDiscounts': snapshot.allowCashierDiscounts,
    'autoBackupEnabled': snapshot.autoBackupEnabled,
    if (snapshot.lastAutoBackupAt.isNotEmpty)
      'lastAutoBackupAt': snapshot.lastAutoBackupAt,
    if (snapshot.lastExternalBackupAt.isNotEmpty)
      'lastExternalBackupAt': snapshot.lastExternalBackupAt,
    if (snapshot.lastExternalBackupReminderAt.isNotEmpty)
      'lastExternalBackupReminderAt': snapshot.lastExternalBackupReminderAt,
    if (snapshot.lastCloudBackupProductsCount >= 0)
      'lastCloudBackupProductsCount': snapshot.lastCloudBackupProductsCount,
    if (snapshot.lastCloudBackupSalesCount >= 0)
      'lastCloudBackupSalesCount': snapshot.lastCloudBackupSalesCount,
    if (snapshot.pendingSync) 'pendingSync': true,
    if (snapshot.cloudBackupHashes.isNotEmpty)
      'cloudBackupHashes': snapshot.cloudBackupHashes,
    if (snapshot.sheetCatalogBaseline.isNotEmpty)
      'sheetCatalogBaseline': snapshot.sheetCatalogBaseline,
    if (snapshot.inventorySnapshots.isNotEmpty)
      'inventorySnapshots':
          snapshot.inventorySnapshots.map((s) => s.toJson()).toList(),
    if (snapshot.featureUsage.isNotEmpty)
      'featureUsage': snapshot.featureUsage.map(
        (k, v) => MapEntry(k, v.toJson()),
      ),
    if (snapshot.trashRetentionDays != 30)
      'trashRetentionDays': snapshot.trashRetentionDays,
    if (snapshot.inventorySelectedCategory.isNotEmpty)
      'inventorySelectedCategory': snapshot.inventorySelectedCategory,
    if (snapshot.inventorySort != 'newest' && snapshot.inventorySort.isNotEmpty)
      'inventorySort': snapshot.inventorySort,
    if (snapshot.posSelectedCategory.isNotEmpty)
      'posSelectedCategory': snapshot.posSelectedCategory,
    if (snapshot.sellers.isNotEmpty) 'sellers': snapshot.sellers,
    if (snapshot.activeSeller.isNotEmpty)
      'activeSeller': snapshot.activeSeller,
    if (snapshot.priceTagQueue.isNotEmpty)
      'priceTagQueue': snapshot.priceTagQueue,
    if (snapshot.cashDrawerMovements.isNotEmpty)
      'cashDrawerMovements':
          snapshot.cashDrawerMovements.map((e) => e.toJson()).toList(),
  });
}

Map<String, FeatureUsageStat> _decodeFeatureUsageMap(dynamic raw) {
  if (raw is! Map) return const {};
  final result = <String, FeatureUsageStat>{};
  for (final entry in raw.entries) {
    final key = '${entry.key}'.trim();
    if (key.isEmpty) continue;
    if (entry.value is Map<String, dynamic>) {
      final stat = FeatureUsageStat.fromJson(entry.value as Map<String, dynamic>);
      if (stat.count > 0) result[key] = stat;
    } else if (entry.value is num) {
      final c = (entry.value as num).toInt();
      if (c > 0) result[key] = FeatureUsageStat(count: c);
    }
  }
  return result;
}
