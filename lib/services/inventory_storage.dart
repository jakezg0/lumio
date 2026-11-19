import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import '../models/customer.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/stock_in.dart';

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
    this.stockInDraft,
    this.stocktakeDraft,
    this.heldSales = const [],
    this.productChanges = const [],
    this.negativeStockReminders = const {},
    this.allowNegativeStock = true,
    this.autoBackupEnabled = true,
    this.lastAutoBackupAt = '',
    this.cloudBackupHashes = const {},
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
  final StockInDraft? stockInDraft;
  final StocktakeDraft? stocktakeDraft;
  final List<HeldSale> heldSales;
  final List<ProductChangeEntry> productChanges;
  final Map<String, int> negativeStockReminders;
  final bool allowNegativeStock;
  final bool autoBackupEnabled;
  final String lastAutoBackupAt;
  final Map<String, String> cloudBackupHashes;
}

abstract class InventoryStorage {
  Future<ShopDataSnapshot> load();
  Future<void> save(ShopDataSnapshot snapshot);
}

class InMemoryInventoryStorage implements InventoryStorage {
  ShopDataSnapshot _snapshot = const ShopDataSnapshot(
    products: [],
    sales: [],
    expenses: [],
    customers: [],
    stockIns: [],
  );

  @override
  Future<ShopDataSnapshot> load() async => _snapshot;

  @override
  Future<void> save(ShopDataSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}

class JsonFileInventoryStorage implements InventoryStorage {
  JsonFileInventoryStorage({String? filePath}) : _customFilePath = filePath;

  final String? _customFilePath;
  File? _cachedFile;

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
        return const ShopDataSnapshot(products: [], sales: [], expenses: []);
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return const ShopDataSnapshot(products: [], sales: [], expenses: []);
      }
      return await compute(_decodeSnapshotFromRawJson, raw);
    } catch (_) {
      return const ShopDataSnapshot(products: [], sales: [], expenses: []);
    }
  }

  @override
  Future<void> save(ShopDataSnapshot snapshot) async {
    try {
      final file = _resolveFile();
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      final payload = await compute(_encodeSnapshotToJson, snapshot);
      try {
        final tmpFile = File('${file.path}.tmp');
        await tmpFile.writeAsString(payload, flush: true);
        await tmpFile.rename(file.path);
      } catch (_) {
        await file.writeAsString(payload, flush: true);
      }
    } catch (_) {
      // Ignore write failures in restricted environments.
    }
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
    autoBackupEnabled: (decoded['autoBackupEnabled'] as bool?) ?? true,
    lastAutoBackupAt: (decoded['lastAutoBackupAt'] as String?) ?? '',
    cloudBackupHashes:
        (decoded['cloudBackupHashes'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, '$v')),
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
    'autoBackupEnabled': snapshot.autoBackupEnabled,
    if (snapshot.lastAutoBackupAt.isNotEmpty)
      'lastAutoBackupAt': snapshot.lastAutoBackupAt,
    if (snapshot.cloudBackupHashes.isNotEmpty)
      'cloudBackupHashes': snapshot.cloudBackupHashes,
  });
}
