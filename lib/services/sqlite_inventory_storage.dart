import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:sqflite/sqflite.dart';

import '../models/cash_drawer_movement.dart';
import '../models/customer.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/stock_in.dart';
import 'inventory_storage.dart';

class SqliteInventoryStorage implements InventoryStorage {
  SqliteInventoryStorage({
    String? dbName,
    InventoryStorage? legacyJsonFallback,
    this.schemaVersion = currentSchemaVersion,
  })  : _dbName = dbName ?? 'lumio_shop.db',
        _legacyStorage = legacyJsonFallback ?? JsonFileInventoryStorage();

  static const int currentSchemaVersion = 1;
  static const int inMemoryChangeHistoryDays = 90;
  static const String preUpgradeBackupDbName = 'lumio_pre_upgrade.db';
  static const String lastGoodBackupDbName = 'lumio_last_good.db';
  static const String preRestoreBackupDbName = 'lumio_pre_restore.db';
  static const String preRestoreBackupJsonName = 'lumio_pre_restore.json';

  final String _dbName;
  final InventoryStorage _legacyStorage;
  final int schemaVersion;

  Database? _db;
  bool _useFallback = false;
  Future<void> _saveQueue = Future<void>.value();

  final Map<String, String> _savedProducts = {};
  final Map<String, String> _savedSales = {};
  final Map<String, String> _savedExpenses = {};
  final Map<String, String> _savedCustomers = {};
  final Map<String, String> _savedStockIns = {};
  final Map<String, String> _savedChanges = {};
  final Map<String, DateTime> _savedChangeDates = {};
  final Map<String, String> _savedMeta = {};

  static String preUpgradeBackupPathFor(String dbPath) {
    final parent = File(dbPath).parent.path;
    return '$parent/$preUpgradeBackupDbName';
  }

  static String lastGoodBackupPathFor(String dbPath) {
    final parent = File(dbPath).parent.path;
    return '$parent/$lastGoodBackupDbName';
  }

  static String preRestoreBackupPathFor(String dbPath) {
    final parent = File(dbPath).parent.path;
    return '$parent/$preRestoreBackupDbName';
  }

  static String preRestoreJsonPathFor(String dbPath) {
    final parent = File(dbPath).parent.path;
    return '$parent/$preRestoreBackupJsonName';
  }

  static bool isQuickCheckOk(List<Map<String, Object?>> rows) {
    if (rows.length != 1) return false;
    final val = rows.first.values.isNotEmpty
        ? '${rows.first.values.first ?? ''}'.trim().toLowerCase()
        : '';
    return val == 'ok';
  }

  /// Restores [dbPath] from the latest available local `.db` backup
  /// (`lumio_last_good.db` first, then `lumio_pre_upgrade.db`).
  static Future<String?> restoreDatabaseFromLocalBackup(String dbPath) async {
    final candidates = [
      lastGoodBackupPathFor(dbPath),
      preUpgradeBackupPathFor(dbPath),
    ];
    for (final candidatePath in candidates) {
      final candidate = File(candidatePath);
      if (!await candidate.exists()) continue;
      final len = await candidate.length();
      if (len <= 0) continue;
      for (final suffix in const ['-wal', '-shm']) {
        final stale = File('$dbPath$suffix');
        if (await stale.exists()) {
          await stale.delete();
        }
      }
      await backupDatabaseFileAtomically(candidatePath, targetPath: dbPath);
      return candidatePath;
    }
    return null;
  }

  static Future<File?> backupDatabaseFileAtomically(
    String dbPath, {
    String? targetPath,
  }) async {
    final sourceFile = File(dbPath);
    if (!await sourceFile.exists()) return null;

    final backupPath = targetPath ?? preUpgradeBackupPathFor(dbPath);
    final tempPath = '$backupPath.tmp';
    await sourceFile.copy(tempPath);

    final targetFile = File(backupPath);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    final result = await File(tempPath).rename(backupPath);

    for (final suffix in const ['-wal', '-shm']) {
      final stale = File('$backupPath$suffix');
      if (await stale.exists()) {
        await stale.delete();
      }
    }
    return result;
  }

  Future<void> _backupBeforeUpgradeIfNeeded(
    Database db,
    String dbPath,
  ) async {
    final rows = await db.rawQuery('PRAGMA user_version');
    final currentVersion = rows.isNotEmpty
        ? (rows.first.values.first as num?)?.toInt() ?? 0
        : 0;
    if (currentVersion <= 0 || currentVersion >= schemaVersion) {
      return;
    }
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Best-effort WAL flush before copying the database file.
    }
    await backupDatabaseFileAtomically(dbPath);
  }

  Future<Database?> _getDatabase() async {
    if (_useFallback) return null;
    if (_db != null && _db!.isOpen) return _db;
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      _useFallback = true;
      return null;
    }
    try {
      final dbDir = await getDatabasesPath();
      final dbPath = '$dbDir/$_dbName';
      Future<Database> openAndVerify() async {
        final opened = await openDatabase(
          dbPath,
          version: schemaVersion,
          onConfigure: (db) async {
            await _backupBeforeUpgradeIfNeeded(db, dbPath);
            await db.rawQuery('PRAGMA journal_mode = WAL');
            await db.rawQuery('PRAGMA synchronous = FULL');
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            // Future schema migrations go here (e.g. if (oldVersion < 2) { ... }).
            // lumio_pre_upgrade.db is already saved in onConfigure before this runs.
          },
          onCreate: (db, version) async {
            await _createTables(db);
          },
        );
        final checkRows = await opened.rawQuery('PRAGMA quick_check');
        if (!isQuickCheckOk(checkRows)) {
          await opened.close();
          throw const FormatException('SQLite PRAGMA quick_check failed');
        }
        return opened;
      }

      try {
        _db = await openAndVerify();
      } catch (_) {
        final restoredFrom = await restoreDatabaseFromLocalBackup(dbPath);
        if (restoredFrom == null) rethrow;
        _db = await openAndVerify();
      }
      await _refreshLastGoodBackupIfPossible(_db!, dbPath);
      return _db;
    } catch (_) {
      _useFallback = true;
      return null;
    }
  }

  Future<void> _refreshLastGoodBackupIfPossible(
    Database db,
    String dbPath,
  ) async {
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(PASSIVE)');
      await backupDatabaseFileAtomically(
        dbPath,
        targetPath: lastGoodBackupPathFor(dbPath),
      );
    } catch (_) {
      // Best-effort local backup refresh.
    }
  }

  Future<void> _createTables(Database db) async {
          await db.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              category TEXT NOT NULL,
              sku TEXT NOT NULL,
              sell_price REAL NOT NULL,
              cost_price REAL NOT NULL,
              stock INTEGER NOT NULL,
              status TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              payload TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_products_category ON products(category)',
          );
          await db.execute(
            'CREATE INDEX idx_products_sku ON products(sku)',
          );
          await db.execute(
            'CREATE INDEX idx_products_status ON products(status)',
          );

          await db.execute('''
            CREATE TABLE sales (
              id TEXT PRIMARY KEY,
              created_at TEXT NOT NULL,
              customer_name TEXT NOT NULL,
              total REAL NOT NULL,
              profit REAL NOT NULL,
              status TEXT NOT NULL,
              payload TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_sales_created ON sales(created_at DESC)',
          );
          await db.execute(
            'CREATE INDEX idx_sales_customer ON sales(customer_name)',
          );

          await db.execute('''
            CREATE TABLE expenses (
              id TEXT PRIMARY KEY,
              created_at TEXT NOT NULL,
              category TEXT NOT NULL,
              amount REAL NOT NULL,
              status TEXT NOT NULL,
              payload TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_expenses_created ON expenses(created_at DESC)',
          );

          await db.execute('''
            CREATE TABLE customers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              phone TEXT NOT NULL,
              payload TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_customers_name ON customers(name)',
          );

          await db.execute('''
            CREATE TABLE stock_ins (
              id TEXT PRIMARY KEY,
              created_at TEXT NOT NULL,
              supplier_name TEXT NOT NULL,
              payload TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_stock_ins_created ON stock_ins(created_at DESC)',
          );

          await db.execute('''
            CREATE TABLE product_changes (
              id TEXT PRIMARY KEY,
              product_id TEXT NOT NULL,
              source TEXT NOT NULL,
              created_at TEXT NOT NULL,
              has_price INTEGER NOT NULL,
              payload TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_changes_product_date ON product_changes(product_id, created_at DESC)',
          );
          await db.execute(
            'CREATE INDEX idx_changes_price_date ON product_changes(has_price, created_at DESC)',
          );

          await db.execute('''
            CREATE TABLE meta (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
  }

  static String _productStatus(Product p) {
    if (p.isTrashed) return 'trashed';
    if (p.isArchived) return 'archived';
    return 'active';
  }

  static String _saleStatus(Sale s) {
    if (s.isTrashed) return 'trashed';
    if (s.isArchived) return 'archived';
    return 'active';
  }

  static String _expenseStatus(Expense e) {
    return e.isTrashed ? 'trashed' : 'active';
  }

  Map<String, String> _buildMetaMap(ShopDataSnapshot snapshot) {
    return <String, String>{
      'languageCode': snapshot.languageCode,
      'currencyCode': snapshot.currencyCode,
      'shopName': snapshot.shopName,
      'shopAddress': snapshot.shopAddress,
      'shopPhone': snapshot.shopPhone,
      'receiptFooter': snapshot.receiptFooter,
      'ownerPin': snapshot.ownerPin,
      'useBiometricUnlock': snapshot.useBiometricUnlock ? '1' : '0',
      'cashierMode': snapshot.cashierMode ? '1' : '0',
      'catalogSeeded': snapshot.catalogSeeded ? '1' : '0',
      'googleSheetsUrl': snapshot.googleSheetsUrl,
      'googleSheetsSecret': snapshot.googleSheetsSecret,
      'customCategories': jsonEncode(snapshot.customCategories),
      'hiddenCustomerSuggestions':
          jsonEncode(snapshot.hiddenCustomerSuggestions),
      'stockInDraft': snapshot.stockInDraft != null
          ? jsonEncode(snapshot.stockInDraft!.toJson())
          : '',
      'stocktakeDraft': snapshot.stocktakeDraft != null
          ? jsonEncode(snapshot.stocktakeDraft!.toJson())
          : '',
      'heldSales':
          jsonEncode(snapshot.heldSales.map((h) => h.toJson()).toList()),
      'negativeStockReminders': jsonEncode(snapshot.negativeStockReminders),
      'allowNegativeStock': snapshot.allowNegativeStock ? '1' : '0',
      'allowCashierDiscounts': snapshot.allowCashierDiscounts ? '1' : '0',
      'autoBackupEnabled': snapshot.autoBackupEnabled ? '1' : '0',
      'lastAutoBackupAt': snapshot.lastAutoBackupAt,
      'lastExternalBackupAt': snapshot.lastExternalBackupAt,
      'lastExternalBackupReminderAt': snapshot.lastExternalBackupReminderAt,
      'lastCloudBackupProductsCount':
          '${snapshot.lastCloudBackupProductsCount}',
      'lastCloudBackupSalesCount': '${snapshot.lastCloudBackupSalesCount}',
      'pendingSync': snapshot.pendingSync ? '1' : '0',
      'cloudBackupHashes': jsonEncode(snapshot.cloudBackupHashes),
      'sheetCatalogBaseline': jsonEncode(snapshot.sheetCatalogBaseline),
      'inventorySnapshots': jsonEncode(
        snapshot.inventorySnapshots.map((s) => s.toJson()).toList(),
      ),
      'featureUsage': jsonEncode(
        snapshot.featureUsage.map((k, v) => MapEntry(k, v.toJson())),
      ),
      'inventorySelectedCategory': snapshot.inventorySelectedCategory,
      'inventorySort': snapshot.inventorySort,
      'posSelectedCategory': snapshot.posSelectedCategory,
      'sellers': jsonEncode(snapshot.sellers),
      'activeSeller': snapshot.activeSeller,
      'priceTagQueue': jsonEncode(snapshot.priceTagQueue),
      'cashDrawerMovements': jsonEncode(
        snapshot.cashDrawerMovements.map((e) => e.toJson()).toList(),
      ),
    };
  }

  @override
  Future<ShopDataSnapshot> load() async {
    final db = await _getDatabase();
    if (db == null) {
      return _legacyStorage.load();
    }

    final metaRows = await db.query('meta');
    final meta = <String, String>{
      for (final row in metaRows) '${row['key']}': '${row['value']}',
    };

    final salesCutoffDt = DateTime.now().subtract(const Duration(days: 30));
    final salesCutoff = salesCutoffDt.toIso8601String();
    final productRows = await db.query(
      'products',
      where: 'status = ?',
      whereArgs: ['active'],
    );
    final saleRows = await db.query(
      'sales',
      where: "status = ? AND (created_at >= ? OR payload LIKE '%\"postPay\"%')",
      whereArgs: ['active', salesCutoff],
      orderBy: 'created_at DESC',
    );
    final expenseRows = await db.query(
      'expenses',
      where: 'status = ?',
      whereArgs: ['active'],
      orderBy: 'created_at DESC',
    );
    final customerRows = await db.query('customers');
    final stockInRows = await db.query('stock_ins', orderBy: 'created_at DESC');
    final memoryCutoff = DateTime.now()
        .subtract(const Duration(days: inMemoryChangeHistoryDays))
        .toIso8601String();
    final changeRows = await db.query(
      'product_changes',
      where: 'created_at >= ?',
      whereArgs: [memoryCutoff],
      orderBy: 'created_at DESC',
    );

    var dbIsEmpty = productRows.isEmpty &&
        saleRows.isEmpty &&
        expenseRows.isEmpty &&
        customerRows.isEmpty &&
        stockInRows.isEmpty &&
        meta['migrated_from_json'] != '1';
    if (dbIsEmpty) {
      final countRows = await db.rawQuery(
        'SELECT (SELECT COUNT(*) FROM products) + '
        '(SELECT COUNT(*) FROM sales) + '
        '(SELECT COUNT(*) FROM expenses) AS total_cnt',
      );
      final totalCnt = (countRows.first['total_cnt'] as num?)?.toInt() ?? 0;
      dbIsEmpty = totalCnt == 0;
    }
        saleRows.isEmpty &&
        expenseRows.isEmpty &&
        customerRows.isEmpty &&
        stockInRows.isEmpty &&
        meta['migrated_from_json'] != '1';

    if (dbIsEmpty) {
      final legacy = await _legacyStorage.load();
      final hasLegacyData = legacy.products.isNotEmpty ||
          legacy.sales.isNotEmpty ||
          legacy.expenses.isNotEmpty ||
          legacy.customers.isNotEmpty ||
          legacy.stockIns.isNotEmpty ||
          legacy.googleSheetsUrl.isNotEmpty ||
          legacy.ownerPin.isNotEmpty;
      if (hasLegacyData) {
        await save(legacy);
      }
      await db.insert(
        'meta',
        {'key': 'migrated_from_json', 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return legacy;
    }

    _savedProducts.clear();
    final products = <Product>[];
    for (final row in productRows) {
      final id = '${row['id']}';
      final payload = '${row['payload']}';
      _savedProducts[id] = payload;
      products.add(Product.fromJson(jsonDecode(payload) as Map<String, dynamic>));
    }

    _savedSales.clear();
    final sales = <Sale>[];
    for (final row in saleRows) {
      final id = '${row['id']}';
      final payload = '${row['payload']}';
      final sale = Sale.fromJson(jsonDecode(payload) as Map<String, dynamic>);
      if (sale.isPaid && sale.createdAt.isBefore(salesCutoffDt)) {
        continue;
      }
      _savedSales[id] = payload;
      sales.add(sale);
    }

    _savedExpenses.clear();
    final expenses = <Expense>[];
    for (final row in expenseRows) {
      final id = '${row['id']}';
      final payload = '${row['payload']}';
      _savedExpenses[id] = payload;
      expenses.add(Expense.fromJson(jsonDecode(payload) as Map<String, dynamic>));
    }

    _savedCustomers.clear();
    final customers = <Customer>[];
    for (final row in customerRows) {
      final id = '${row['id']}';
      final payload = '${row['payload']}';
      _savedCustomers[id] = payload;
      customers
          .add(Customer.fromJson(jsonDecode(payload) as Map<String, dynamic>));
    }

    _savedStockIns.clear();
    final stockIns = <StockInRecord>[];
    for (final row in stockInRows) {
      final id = '${row['id']}';
      final payload = '${row['payload']}';
      _savedStockIns[id] = payload;
      stockIns.add(
        StockInRecord.fromJson(jsonDecode(payload) as Map<String, dynamic>),
      );
    }

    _savedChanges.clear();
    _savedChangeDates.clear();
    final productChanges = <ProductChangeEntry>[];
    for (final row in changeRows) {
      final id = '${row['id']}';
      final payload = '${row['payload']}';
      final entry = ProductChangeEntry.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      );
      _savedChanges[id] = payload;
      _savedChangeDates[id] = entry.createdAt;
      productChanges.add(entry);
    }

    _savedMeta
      ..clear()
      ..addAll(meta);

    List<String> decodeStringList(String? raw) {
      if (raw == null || raw.isEmpty) return const [];
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        return list.map((e) => '$e').toList();
      } catch (_) {
        return const [];
      }
    }

    Map<String, String> decodeStringMap(String? raw) {
      if (raw == null || raw.isEmpty) return const {};
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return map.map((k, v) => MapEntry(k, '$v'));
      } catch (_) {
        return const {};
      }
    }

    Map<String, int> decodeIntMap(String? raw) {
      if (raw == null || raw.isEmpty) return const {};
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return map.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0))
          ..removeWhere((_, v) => v <= 0);
      } catch (_) {
        return const {};
      }
    }

    StockInDraft? stockInDraft;
    final rawStockInDraft = meta['stockInDraft'] ?? '';
    if (rawStockInDraft.isNotEmpty) {
      try {
        stockInDraft = StockInDraft.fromJson(
          jsonDecode(rawStockInDraft) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    StocktakeDraft? stocktakeDraft;
    final rawStocktakeDraft = meta['stocktakeDraft'] ?? '';
    if (rawStocktakeDraft.isNotEmpty) {
      try {
        stocktakeDraft = StocktakeDraft.fromJson(
          jsonDecode(rawStocktakeDraft) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    final heldSales = <HeldSale>[];
    final rawHeldSales = meta['heldSales'] ?? '';
    if (rawHeldSales.isNotEmpty) {
      try {
        final list = jsonDecode(rawHeldSales) as List<dynamic>;
        for (final item in list.whereType<Map<String, dynamic>>()) {
          heldSales.add(HeldSale.fromJson(item));
        }
      } catch (_) {}
    }

    final inventorySnapshots = <InventoryValueSnapshot>[];
    final rawSnapshots = meta['inventorySnapshots'] ?? '';
    if (rawSnapshots.isNotEmpty) {
      try {
        final list = jsonDecode(rawSnapshots) as List<dynamic>;
        for (final item in list.whereType<Map<String, dynamic>>()) {
          inventorySnapshots.add(InventoryValueSnapshot.fromJson(item));
        }
      } catch (_) {}
    }

    final featureUsage = <String, FeatureUsageStat>{};
    final rawFeatureUsage = meta['featureUsage'] ?? '';
    if (rawFeatureUsage.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawFeatureUsage);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            if (entry.value is Map<String, dynamic>) {
              final stat = FeatureUsageStat.fromJson(
                entry.value as Map<String, dynamic>,
              );
              if (stat.count > 0) featureUsage[entry.key] = stat;
            }
          }
        }
      } catch (_) {}
    }

    final cashDrawerMovements = <CashDrawerMovement>[];
    final rawCashMovements = meta['cashDrawerMovements'] ?? '';
    if (rawCashMovements.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCashMovements);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              cashDrawerMovements.add(CashDrawerMovement.fromJson(item));
            }
          }
        }
      } catch (_) {}
    }

    final hasAnyData = products.isNotEmpty ||
        sales.isNotEmpty ||
        expenses.isNotEmpty ||
        customers.isNotEmpty ||
        stockIns.isNotEmpty;

    return ShopDataSnapshot(
      products: products,
      sales: sales,
      expenses: expenses,
      customers: customers,
      stockIns: stockIns,
      productChanges: productChanges,
      languageCode: meta['languageCode'] ?? 'auto',
      currencyCode: meta['currencyCode'] ?? 'kzt',
      shopName: meta['shopName'] ?? 'Lumio',
      shopAddress: meta['shopAddress'] ?? '',
      shopPhone: meta['shopPhone'] ?? '',
      receiptFooter: meta['receiptFooter'] ?? '',
      ownerPin: meta['ownerPin'] ?? '',
      useBiometricUnlock: meta['useBiometricUnlock'] == '1',
      cashierMode: meta['cashierMode'] != '0',
      catalogSeeded: meta['catalogSeeded'] == '1' || hasAnyData,
      googleSheetsUrl: meta['googleSheetsUrl'] ?? '',
      googleSheetsSecret: meta['googleSheetsSecret'] ?? '',
      customCategories: decodeStringList(meta['customCategories']),
      hiddenCustomerSuggestions:
          decodeStringList(meta['hiddenCustomerSuggestions']),
      stockInDraft: stockInDraft,
      stocktakeDraft: stocktakeDraft,
      heldSales: heldSales,
      negativeStockReminders: decodeIntMap(meta['negativeStockReminders']),
      allowNegativeStock: meta['allowNegativeStock'] != '0',
      allowCashierDiscounts: meta['allowCashierDiscounts'] != '0',
      autoBackupEnabled: meta['autoBackupEnabled'] != '0',
      lastAutoBackupAt: meta['lastAutoBackupAt'] ?? '',
      lastExternalBackupAt: meta['lastExternalBackupAt'] ?? '',
      lastExternalBackupReminderAt:
          meta['lastExternalBackupReminderAt'] ?? '',
      lastCloudBackupProductsCount:
          int.tryParse(meta['lastCloudBackupProductsCount'] ?? '') ?? -1,
      lastCloudBackupSalesCount:
          int.tryParse(meta['lastCloudBackupSalesCount'] ?? '') ?? -1,
      pendingSync: meta['pendingSync'] == '1' || meta['pendingSync'] == 'true',
      cloudBackupHashes: decodeStringMap(meta['cloudBackupHashes']),
      sheetCatalogBaseline: decodeStringMap(meta['sheetCatalogBaseline']),
      inventorySnapshots: inventorySnapshots,
      featureUsage: featureUsage,
      inventorySelectedCategory: meta['inventorySelectedCategory'] ?? '',
      inventorySort: (meta['inventorySort'] ?? '').isNotEmpty
          ? meta['inventorySort']!
          : 'newest',
      posSelectedCategory: meta['posSelectedCategory'] ?? '',
      sellers: decodeStringList(meta['sellers']),
      activeSeller: meta['activeSeller'] ?? '',
      priceTagQueue: decodeStringList(meta['priceTagQueue']),
      cashDrawerMovements: cashDrawerMovements,
    );
  }

  @override
  Future<({List<Product> products, List<Sale> sales, List<Expense> expenses})>
      loadArchiveAndTrash() async {
    final db = await _getDatabase();
    if (db == null) {
      return _legacyStorage.loadArchiveAndTrash();
    }
    final productRows = await db.query(
      'products',
      where: 'status != ?',
      whereArgs: ['active'],
    );
    final saleRows = await db.query(
      'sales',
      where: 'status != ?',
      whereArgs: ['active'],
      orderBy: 'created_at DESC',
    );
    final expenseRows = await db.query(
      'expenses',
      where: 'status != ?',
      whereArgs: ['active'],
      orderBy: 'created_at DESC',
    );

    final products = <Product>[];
    for (final row in productRows) {
      final id = '${row['id']}';
      final payload = '${row['payload']}';
      _savedProducts[id] = payload;
      products.add(Product.fromJson(jsonDecode(payload) as Map<String, dynamic>));
    }
    final sales = <Sale>[];
    for (final row in saleRows) {
      final id = '${row['id']}';
      final payload = '${row['payload']}';
      _savedSales[id] = payload;
      sales.add(Sale.fromJson(jsonDecode(payload) as Map<String, dynamic>));
    }
    final expenses = <Expense>[];
    for (final row in expenseRows) {
      final id = '${row['id']}';
      final payload = '${row['payload']}';
      _savedExpenses[id] = payload;
      expenses.add(Expense.fromJson(jsonDecode(payload) as Map<String, dynamic>));
    }
    return (products: products, sales: sales, expenses: expenses);
  }

  @override
  Future<List<Sale>> loadAllActiveSales() async {
    final db = await _getDatabase();
    if (db == null) {
      return _legacyStorage.loadAllActiveSales();
    }
    final saleRows = await db.query(
      'sales',
      where: 'status = ?',
      whereArgs: ['active'],
      orderBy: 'created_at DESC',
    );
    final sales = <Sale>[];
    for (final row in saleRows) {
      final id = '${row['id']}';
      final payload = '${row['payload']}';
      _savedSales[id] = payload;
      sales.add(Sale.fromJson(jsonDecode(payload) as Map<String, dynamic>));
    }
    return sales;
  }

  @override
  Future<List<ProductChangeEntry>> loadProductChanges({
    int? days,
    String? productId,
    bool priceOnly = false,
  }) async {
    final db = await _getDatabase();
    if (db == null) {
      return _legacyStorage.loadProductChanges(
        days: days,
        productId: productId,
        priceOnly: priceOnly,
      );
    }
    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    if (days != null && days > 0) {
      final cutoff =
          DateTime.now().subtract(Duration(days: days)).toIso8601String();
      whereParts.add('created_at >= ?');
      whereArgs.add(cutoff);
    }
    if (productId != null && productId.isNotEmpty) {
      whereParts.add('product_id = ?');
      whereArgs.add(productId);
    }
    if (priceOnly) {
      whereParts.add('has_price = 1');
    }
    final rows = await db.query(
      'product_changes',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
    );
    return rows
        .map(
          (row) => ProductChangeEntry.fromJson(
            jsonDecode('${row['payload']}') as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  @override
  Future<int> deleteProductChanges({int? olderThanDays}) async {
    final db = await _getDatabase();
    if (db == null) {
      return _legacyStorage.deleteProductChanges(olderThanDays: olderThanDays);
    }
    if (olderThanDays == null) {
      final count = await db.delete('product_changes');
      _savedChanges.clear();
      _savedChangeDates.clear();
      return count;
    }
    final cutoffDt = DateTime.now().subtract(Duration(days: olderThanDays));
    final count = await db.delete(
      'product_changes',
      where: 'created_at < ?',
      whereArgs: [cutoffDt.toIso8601String()],
    );
    final toRemove = _savedChangeDates.entries
        .where((e) => e.value.isBefore(cutoffDt))
        .map((e) => e.key)
        .toList();
    for (final id in toRemove) {
      _savedChanges.remove(id);
      _savedChangeDates.remove(id);
    }
    return count;
  }

  @override
  Future<void> save(ShopDataSnapshot snapshot) {
    _saveQueue = _saveQueue.then((_) => _saveInternal(snapshot)).catchError((_) {});
    return _saveQueue;
  }

  @override
  Future<void> savePreRestoreBackup(ShopDataSnapshot snapshot) async {
    final db = await _getDatabase();
    if (db == null) {
      await _legacyStorage.savePreRestoreBackup(snapshot);
      return;
    }
    final dbDir = await getDatabasesPath();
    final dbPath = '$dbDir/$_dbName';
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await backupDatabaseFileAtomically(
      dbPath,
      targetPath: preRestoreBackupPathFor(dbPath),
    );
    final payload = await compute(
      encodePreRestoreEnvelope,
      (snapshot: snapshot, savedAt: DateTime.now().toIso8601String()),
    );
    await writeTextFileAtomically(
      File(preRestoreJsonPathFor(dbPath)),
      payload,
      validateJson: true,
    );
  }

  @override
  Future<({ShopDataSnapshot snapshot, DateTime savedAt})?>
      loadPreRestoreBackup() async {
    final db = await _getDatabase();
    if (db == null) {
      return _legacyStorage.loadPreRestoreBackup();
    }
    try {
      final dbDir = await getDatabasesPath();
      final jsonFile = File(preRestoreJsonPathFor('$dbDir/$_dbName'));
      if (await jsonFile.exists()) {
        final raw = await jsonFile.readAsString();
        if (raw.trim().isNotEmpty) {
          return await compute(decodePreRestoreEnvelope, raw);
        }
      }
    } catch (_) {}
    return _legacyStorage.loadPreRestoreBackup();
  }

  Future<void> _saveInternal(ShopDataSnapshot snapshot) async {
    final db = await _getDatabase();
    if (db == null) {
      await _legacyStorage.save(snapshot);
      return;
    }

    final nextProducts = <String, String>{};
    final nextSales = <String, String>{};
    final nextExpenses = <String, String>{};
    final nextCustomers = <String, String>{};
    final nextStockIns = <String, String>{};
    final nextChanges = <String, String>{};
    final nextMeta = _buildMetaMap(snapshot);

    await db.transaction((txn) async {
      final batch = txn.batch();

      // Products diff
      for (final p in snapshot.products) {
        final payload = jsonEncode(p.toJson());
        nextProducts[p.id] = payload;
        if (_savedProducts[p.id] != payload) {
          batch.insert(
            'products',
            {
              'id': p.id,
              'name': p.name,
              'category': p.category,
              'sku': p.sku,
              'sell_price': p.sellPrice,
              'cost_price': p.costPrice,
              'stock': p.stock,
              'status': _productStatus(p),
              'updated_at': p.updatedAt.toIso8601String(),
              'payload': payload,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      for (final oldId in _savedProducts.keys) {
        if (!nextProducts.containsKey(oldId)) {
          batch.delete('products', where: 'id = ?', whereArgs: [oldId]);
        }
      }

      // Sales diff
      for (final s in snapshot.sales) {
        final payload = jsonEncode(s.toJson());
        nextSales[s.id] = payload;
        if (_savedSales[s.id] != payload) {
          batch.insert(
            'sales',
            {
              'id': s.id,
              'created_at': s.createdAt.toIso8601String(),
              'customer_name': s.customerName,
              'total': s.total,
              'profit': s.profit,
              'status': _saleStatus(s),
              'payload': payload,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      for (final oldId in _savedSales.keys) {
        if (!nextSales.containsKey(oldId)) {
          batch.delete('sales', where: 'id = ?', whereArgs: [oldId]);
        }
      }

      // Expenses diff
      for (final e in snapshot.expenses) {
        final payload = jsonEncode(e.toJson());
        nextExpenses[e.id] = payload;
        if (_savedExpenses[e.id] != payload) {
          batch.insert(
            'expenses',
            {
              'id': e.id,
              'created_at': e.createdAt.toIso8601String(),
              'category': e.category.name,
              'amount': e.amount,
              'status': _expenseStatus(e),
              'payload': payload,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      for (final oldId in _savedExpenses.keys) {
        if (!nextExpenses.containsKey(oldId)) {
          batch.delete('expenses', where: 'id = ?', whereArgs: [oldId]);
        }
      }

      // Customers diff
      for (final c in snapshot.customers) {
        final payload = jsonEncode(c.toJson());
        nextCustomers[c.id] = payload;
        if (_savedCustomers[c.id] != payload) {
          batch.insert(
            'customers',
            {
              'id': c.id,
              'name': c.name,
              'phone': c.phone,
              'payload': payload,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      for (final oldId in _savedCustomers.keys) {
        if (!nextCustomers.containsKey(oldId)) {
          batch.delete('customers', where: 'id = ?', whereArgs: [oldId]);
        }
      }

      // Stock-ins diff
      for (final rec in snapshot.stockIns) {
        final payload = jsonEncode(rec.toJson());
        nextStockIns[rec.id] = payload;
        if (_savedStockIns[rec.id] != payload) {
          batch.insert(
            'stock_ins',
            {
              'id': rec.id,
              'created_at': rec.createdAt.toIso8601String(),
              'supplier_name': rec.supplierName,
              'payload': payload,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      for (final oldId in _savedStockIns.keys) {
        if (!nextStockIns.containsKey(oldId)) {
          batch.delete('stock_ins', where: 'id = ?', whereArgs: [oldId]);
        }
      }

      // Product changes (keep recent 90d in memory; preserve older rows in SQLite)
      final nextChangeDates = <String, DateTime>{};
      for (final ch in snapshot.productChanges) {
        final payload = jsonEncode(ch.toJson());
        nextChanges[ch.id] = payload;
        nextChangeDates[ch.id] = ch.createdAt;
        if (_savedChanges[ch.id] != payload) {
          batch.insert(
            'product_changes',
            {
              'id': ch.id,
              'product_id': ch.productId,
              'source': ch.source,
              'created_at': ch.createdAt.toIso8601String(),
              'has_price': ch.hasKind('price') ? 1 : 0,
              'payload': payload,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      final memoryCutoff = DateTime.now()
          .subtract(const Duration(days: inMemoryChangeHistoryDays));
      for (final oldId in _savedChanges.keys) {
        if (!nextChanges.containsKey(oldId)) {
          final oldDt = _savedChangeDates[oldId];
          if (oldDt != null && !oldDt.isBefore(memoryCutoff)) {
            batch.delete('product_changes', where: 'id = ?', whereArgs: [oldId]);
          }
        }
      }

      // Meta diff
      for (final entry in nextMeta.entries) {
        if (_savedMeta[entry.key] != entry.value) {
          batch.insert(
            'meta',
            {'key': entry.key, 'value': entry.value},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      await batch.commit(noResult: true);
      _savedChangeDates
        ..clear()
        ..addAll(nextChangeDates);
    });

    _savedProducts
      ..clear()
      ..addAll(nextProducts);
    _savedSales
      ..clear()
      ..addAll(nextSales);
    _savedExpenses
      ..clear()
      ..addAll(nextExpenses);
    _savedCustomers
      ..clear()
      ..addAll(nextCustomers);
    _savedStockIns
      ..clear()
      ..addAll(nextStockIns);
    _savedChanges
      ..clear()
      ..addAll(nextChanges);
    _savedMeta.addAll(nextMeta);
  }
}
