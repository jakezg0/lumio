import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/l10n/app_strings.dart';
import 'package:flutter_application_1/models/customer.dart';
import 'package:flutter_application_1/models/expense.dart';
import 'package:flutter_application_1/models/sale.dart';
import 'package:flutter_application_1/models/stock_in.dart';
import 'package:flutter_application_1/models/product.dart';
import 'package:flutter_application_1/services/catalog_health_service.dart';
import 'package:flutter_application_1/services/daily_local_backup_service.dart';
import 'package:flutter_application_1/services/export_service.dart';
import 'package:flutter_application_1/services/google_sheets_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/services/input_normalizer.dart';
import 'package:flutter_application_1/services/thermal_printer_service.dart';
import 'package:flutter_application_1/widgets/hardware_barcode_listener.dart';
import 'package:flutter_application_1/widgets/stock_in_sheet.dart';
import 'package:flutter_application_1/services/inventory_storage.dart';
import 'package:flutter_application_1/services/product_image_service.dart';
import 'package:flutter_application_1/services/whatsapp_launcher.dart';
import 'package:flutter_application_1/services/sheet_export_helper.dart';
import 'package:flutter_application_1/services/sqlite_inventory_storage.dart';
import 'package:flutter_application_1/state/shop_controller.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lumio_migration_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'loads legacy v1 shop_data.json with missing optional fields and preserves products, receipts, and debts',
    () async {
      final legacyFile = File('${tempDir.path}/legacy_shop_data.json');
      final legacyPayload = {
        'languageCode': 'ru',
        'currencyCode': 'kzt',
        'shopName': 'Тастак Маркет',
        'cashierMode': false,
        'products': [
          {
            'id': 'prd_legacy_1',
            'name': 'Плинтус 55мм',
            'category': 'Плинтусы',
            'sku': '4601234567890',
            'costPrice': 200,
            'sellPrice': 350,
            'stock': 40,
            'lowStockThreshold': 5,
            'updatedAt': '2025-05-10T10:00:00.000',
          },
        ],
        'sales': [
          {
            'id': 'sal_legacy_1',
            'items': [
              {
                'productId': 'prd_legacy_1',
                'productName': 'Плинтус 55мм',
                'quantity': 10,
                'unitCost': 200,
                'unitPrice': 350,
              },
            ],
            'paymentMethod': 'postPay',
            'customerName': 'Марат',
            'discount': 100,
            'paidAmount': 1400,
            'dueDate': '2025-05-20T00:00:00.000',
            'paymentHistory': [
              {'amount': 1400, 'paidAt': '2025-05-10T12:00:00.000'},
            ],
            'createdAt': '2025-05-10T12:00:00.000',
          },
          {
            'id': 'sal_legacy_2',
            'items': [
              {
                'productId': 'prd_legacy_1',
                'productName': 'Плинтус 55мм',
                'quantity': 2,
                'unitCost': 200,
                'unitPrice': 350,
              },
            ],
            'paymentMethod': 'kaspiQr',
            'createdAt': '2025-05-11T09:30:00.000',
          },
        ],
        'expenses': [
          {
            'id': 'exp_legacy_1',
            'title': 'Аренда',
            'category': 'rent',
            'amount': 50000,
            'createdAt': '2025-05-01T09:00:00.000',
          },
        ],
        'customers': [
          {
            'id': 'cus_legacy_1',
            'name': 'Марат',
            'phone': '+77011234567',
            'createdAt': '2025-05-10T12:00:00.000',
          },
        ],
      };
      await legacyFile.writeAsString(jsonEncode(legacyPayload));

      final storage = JsonFileInventoryStorage(filePath: legacyFile.path);
      final controller = ShopController(storage: storage);
      await controller.initialize();

      expect(controller.shopName, 'Тастак Маркет');
      expect(controller.cashierMode, isFalse);

      // Legacy product defaults
      expect(controller.products.length, 1);
      final prod = controller.products.first;
      expect(prod.name, 'Плинтус 55мм');
      expect(prod.wholesalePrice, 0);
      expect(prod.nomenclature, '');
      expect(prod.stock, 40);

      // Legacy sales & debt integrity
      expect(controller.sales.length, 2);
      final debtSale = controller.sales.firstWhere((s) => s.id == 'sal_legacy_1');
      expect(debtSale.total, 3400);
      expect(debtSale.paidAmount, 1400);
      expect(debtSale.remainingDebt, 2000);
      expect(debtSale.isPaid, isFalse);
      expect(debtSale.paymentHistory.length, 1);

      final qrSale = controller.sales.firstWhere((s) => s.id == 'sal_legacy_2');
      expect(qrSale.total, 700);
      expect(qrSale.isPaid, isTrue);

      // Debtors & customer segment fallback
      expect(controller.debtors.length, 1);
      expect(controller.debtors.first.customerName, 'Марат');
      expect(controller.debtors.first.totalDebt, 2000);
      expect(controller.debtors.first.hasOverdue, isTrue);
      expect(
        controller.customerSegmentByName('Марат'),
        CustomerSegment.retail,
      );

      // Expenses
      expect(controller.expenses.length, 1);
      expect(controller.expenses.first.amount, 50000);
    },
  );

  test(
    'persists and reloads new features (split payments, returns, wholesale prices, debts, snapshots) through storage across restarts',
    () async {
      final dbFile = File('${tempDir.path}/roundtrip_shop_data.json');
      final storage1 = SqliteInventoryStorage(
        dbName: 'test_roundtrip_${DateTime.now().microsecondsSinceEpoch}.db',
        legacyJsonFallback: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      final controller1 = ShopController(storage: storage1);
      await controller1.initialize();
      await controller1.exitCashierMode('');

      final product = await controller1.addProduct(
        name: 'Кабель-канал 40x25',
        category: 'Электрика',
        sku: '2001234567893',
        costPrice: 500,
        sellPrice: 900,
        wholesalePrice: 750,
        stock: 30,
      );

      // 1. Split payment sale
      controller1.addToCart(product.id, quantity: 4);
      final splitSale = await controller1.completeSale(
        paymentMethod: PaymentMethod.cash,
        secondaryPaymentMethod: PaymentMethod.kaspiQr,
        secondaryAmount: 1600,
        customerName: 'ТОО Строй',
        customerSegment: CustomerSegment.wholesale,
      );
      expect(splitSale, isNotNull);
      expect(splitSale!.isSplitPayment, isTrue);

      // 2. Post-pay debt sale + partial repayment
      controller1.addToCart(product.id, quantity: 2);
      final debtSale = await controller1.completeSale(
        paymentMethod: PaymentMethod.postPay,
        customerName: 'Асет',
        customerPhone: '+77075551122',
        paidAmount: 500,
        dueDate: DateTime(2027, 1, 15),
      );
      expect(debtSale, isNotNull);
      await controller1.recordSalePayment(debtSale!.id, 300);

      // 3. Return 1 unit from splitSale as defect
      await controller1.processSaleReturnOrExchange(
        saleId: splitSale.id,
        returnQuantities: {product.id: 1},
        returnToStock: false,
        settlementMethod: PaymentMethod.cash,
        returnReason: 'Заводской брак',
      );

      // 4. Stock-in & monthly snapshot
      await controller1.receiveStock(
        supplierName: 'Опт База',
        items: [
          StockInItem(
            productId: product.id,
            productName: product.name,
            quantity: 5,
            unitCost: 520,
          ),
        ],
      );
      await controller1.captureMonthlyInventorySnapshot(
        forceUpdateCurrentMonth: true,
      );

      // Restart with fresh storage & controller
      final storage2 = SqliteInventoryStorage(
        dbName: 'test_roundtrip_reload_${DateTime.now().microsecondsSinceEpoch}.db',
        legacyJsonFallback: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      final controller2 = ShopController(storage: storage2);
      await controller2.initialize();

      final reloadedProd = controller2.findProductById(product.id);
      expect(reloadedProd, isNotNull);
      expect(reloadedProd!.wholesalePrice, 750);
      expect(reloadedProd.costPrice, 520);
      expect(reloadedProd.stock, 29); // 30 - 4 - 2 + 5

      final reloadedSplit =
          controller2.sales.firstWhere((s) => s.id == splitSale.id);
      expect(reloadedSplit.isSplitPayment, isTrue);
      expect(reloadedSplit.hasReturn, isTrue);
      expect(reloadedSplit.defectItems.length, 1);
      expect(reloadedSplit.defectItems.first.reason, 'Заводской брак');

      final reloadedDebt =
          controller2.sales.firstWhere((s) => s.id == debtSale.id);
      expect(reloadedDebt.paidAmount, 800);
      expect(reloadedDebt.remainingDebt, 1000);
      expect(reloadedDebt.paymentHistory.length, 2);
      expect(controller2.debtors.length, 1);
      expect(controller2.debtors.first.phone, '+77075551122');

      expect(controller2.inventorySnapshots, isNotEmpty);
      expect(controller2.stockIns.length, 1);
      expect(
        controller2.customerSegmentByName('ТОО Строй'),
        CustomerSegment.wholesale,
      );
    },
  );

  test(
    'ExportService parses legacy v1 JSON backups and round-trips v2 JSON backups without data loss',
    () async {
      // 1. Legacy v1 JSON backup (minimal fields)
      final legacyBackupJson = jsonEncode({
        'languageCode': 'ru',
        'currencyCode': 'kzt',
        'shopName': 'Старый Бэкап',
        'products': [
          {
            'id': 'p1',
            'name': 'Уголок 20мм',
            'category': 'Фурнитура',
            'sku': '111222333',
            'costPrice': 100,
            'sellPrice': 180,
            'stock': 15,
            'lowStockThreshold': 3,
            'updatedAt': '2024-12-01T10:00:00.000',
          },
        ],
        'sales': [
          {
            'id': 's1',
            'items': [
              {
                'productId': 'p1',
                'productName': 'Уголок 20мм',
                'quantity': 5,
                'unitCost': 100,
                'unitPrice': 180,
              },
            ],
            'paymentMethod': 'postPay',
            'customerName': 'Болат',
            'paidAmount': 400,
            'createdAt': '2024-12-02T14:00:00.000',
          },
        ],
        'expenses': [],
      });

      final parsedLegacy = ExportService.parseBackupJson(legacyBackupJson);
      expect(parsedLegacy.shopName, 'Старый Бэкап');
      expect(parsedLegacy.products.length, 1);
      expect(parsedLegacy.sales.length, 1);
      expect(parsedLegacy.sales.first.remainingDebt, 500);

      // 2. Full v2 JSON backup round-trip
      final storage = InMemoryInventoryStorage();
      final sourceCtrl = ShopController(storage: storage);
      await sourceCtrl.updateShopProfile(
        shopName: 'Lumio Pro',
        shopAddress: 'Тастак, ряд 3',
        shopPhone: '+77001112233',
        receiptFooter: 'Спасибо за покупку!',
      );
      await sourceCtrl.setOwnerPin('4321');
      final p = await sourceCtrl.addProduct(
        name: 'Саморез 35мм',
        category: 'Крепёж',
        sku: '2009998887771',
        costPrice: 10,
        sellPrice: 20,
        wholesalePrice: 15,
        stock: 100,
      );
      sourceCtrl.addToCart(p.id, quantity: 10);
      final sale = await sourceCtrl.completeSale(
        paymentMethod: PaymentMethod.postPay,
        customerName: 'Данияр',
        customerPhone: '+77019998877',
        paidAmount: 50,
      );
      expect(sale, isNotNull);
      await sourceCtrl.addExpense(
        title: 'Доставка',
        category: ExpenseCategory.delivery,
        amount: 1200,
      );
      await sourceCtrl.captureMonthlyInventorySnapshot(
        forceUpdateCurrentMonth: true,
      );

      final exportedJson =
          ExportService.buildBackupJson(sourceCtrl.createBackupSnapshot());
      final restoredSnapshot = ExportService.parseBackupJson(exportedJson);

      final targetCtrl = ShopController(storage: InMemoryInventoryStorage());
      await targetCtrl.restoreFromSnapshot(restoredSnapshot);

      expect(targetCtrl.shopName, 'Lumio Pro');
      expect(targetCtrl.shopAddress, 'Тастак, ряд 3');
      expect(targetCtrl.shopPhone, '+77001112233');
      expect(targetCtrl.receiptFooter, 'Спасибо за покупку!');
      expect(targetCtrl.ownerPin, '4321');
      expect(targetCtrl.products.length, 1);
      expect(targetCtrl.products.first.wholesalePrice, 15);
      expect(targetCtrl.sales.length, 1);
      expect(targetCtrl.sales.first.receiptCode, sale!.receiptCode);
      expect(targetCtrl.totalUnpaidDebt, 150);
      expect(targetCtrl.debtors.first.phone, '+77019998877');
      expect(targetCtrl.expenses.length, 1);
      expect(targetCtrl.inventorySnapshots.length, 1);
    },
  );

  test(
    'restoreFromSnapshot with includeSettings=false restores goods, sales & debts without overwriting local settings or PIN',
    () async {
      final sourceCtrl = ShopController(storage: InMemoryInventoryStorage());
      await sourceCtrl.setLanguage(AppLanguage.en);
      await sourceCtrl.setCurrency(AppCurrency.usd);
      await sourceCtrl.updateShopProfile(
        shopName: 'Old Shop',
        shopAddress: 'Old Street',
        shopPhone: '+111',
        receiptFooter: 'Old Footer',
      );
      await sourceCtrl.setOwnerPin('1111');
      await sourceCtrl.enterCashierMode();

      final p = await sourceCtrl.addProduct(
        name: 'Дюбель 6x40',
        category: 'Крепёж',
        costPrice: 5,
        sellPrice: 12,
        stock: 100,
      );
      sourceCtrl.addToCart(p.id, quantity: 5);
      await sourceCtrl.completeSale(
        paymentMethod: PaymentMethod.postPay,
        customerName: 'Серик',
        paidAmount: 20,
      );
      final backupSnapshot = sourceCtrl.createBackupSnapshot();

      final targetCtrl = ShopController(storage: InMemoryInventoryStorage());
      await targetCtrl.setLanguage(AppLanguage.ru);
      await targetCtrl.setCurrency(AppCurrency.kzt);
      await targetCtrl.updateShopProfile(
        shopName: 'Новый Телефон',
        shopAddress: 'Тастак 5',
        shopPhone: '+77071234567',
        receiptFooter: 'Ждём вас снова!',
      );
      await targetCtrl.setOwnerPin('9999');
      await targetCtrl.exitCashierMode('9999');

      await targetCtrl.restoreFromSnapshot(
        backupSnapshot,
        includeSettings: false,
      );

      expect(targetCtrl.products.length, 1);
      expect(targetCtrl.products.first.name, 'Дюбель 6x40');
      expect(targetCtrl.sales.length, 1);
      expect(targetCtrl.totalUnpaidDebt, 40);

      expect(targetCtrl.language, AppLanguage.ru);
      expect(targetCtrl.currency, AppCurrency.kzt);
      expect(targetCtrl.shopName, 'Новый Телефон');
      expect(targetCtrl.shopAddress, 'Тастак 5');
      expect(targetCtrl.shopPhone, '+77071234567');
      expect(targetCtrl.receiptFooter, 'Ждём вас снова!');
      expect(targetCtrl.ownerPin, '9999');
      expect(targetCtrl.cashierMode, isFalse);
    },
  );

  test(
    'backupDatabaseFileAtomically copies .db to lumio_pre_upgrade.db and cleans stale WAL/SHM files',
    () async {
      final dbPath = '${tempDir.path}/lumio_shop.db';
      final dbBytes = utf8.encode('SQLite format 3\x00test_payload_v1');
      await File(dbPath).writeAsBytes(dbBytes);

      final expectedBackupPath =
          SqliteInventoryStorage.preUpgradeBackupPathFor(dbPath);
      expect(
        expectedBackupPath,
        '${tempDir.path}/${SqliteInventoryStorage.preUpgradeBackupDbName}',
      );

      // Simulate stale WAL/SHM files from an earlier backup
      await File('$expectedBackupPath-wal').writeAsString('stale wal');
      await File('$expectedBackupPath-shm').writeAsString('stale shm');

      final backupFile =
          await SqliteInventoryStorage.backupDatabaseFileAtomically(dbPath);
      expect(backupFile, isNotNull);
      expect(backupFile!.path, expectedBackupPath);
      expect(await backupFile.readAsBytes(), dbBytes);
      expect(await File('$expectedBackupPath-wal').exists(), isFalse);
      expect(await File('$expectedBackupPath-shm').exists(), isFalse);
      expect(await File('$expectedBackupPath.tmp').exists(), isFalse);
    },
  );

  test(
    'shouldPromptExternalBackup reminds once per week in owner mode and persists snooze/save timestamps',
    () async {
      final storage = InMemoryInventoryStorage();
      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      // Cashier mode & empty shop -> no reminder
      expect(ctrl.shouldPromptExternalBackup, isFalse);

      await ctrl.exitCashierMode('');
      expect(ctrl.shouldPromptExternalBackup, isFalse);

      await ctrl.addProduct(
        name: 'Плинтус 60мм',
        category: 'Плинтусы',
        costPrice: 300,
        sellPrice: 500,
        stock: 10,
      );
      expect(ctrl.shouldPromptExternalBackup, isTrue);

      await ctrl.snoozeExternalBackupReminder();
      expect(ctrl.shouldPromptExternalBackup, isFalse);

      await ctrl.markExternalBackupSaved();
      expect(ctrl.lastExternalBackupAt, isNotEmpty);
      expect(ctrl.shouldPromptExternalBackup, isFalse);

      // Reload from storage and verify timestamps survived
      final reloaded = ShopController(storage: storage);
      await reloaded.initialize();
      expect(reloaded.lastExternalBackupAt, ctrl.lastExternalBackupAt);
      expect(reloaded.shouldPromptExternalBackup, isFalse);
    },
  );

  test(
    'cloud backup shrink protection blocks sharp drops without bulk delete and allows intentional bulk delete',
    () async {
      final now = DateTime.now();
      final initialProducts = List.generate(
        20,
        (i) => Product(
          id: 'prd_$i',
          name: 'Товар $i',
          category: 'Тест',
          costPrice: 100,
          sellPrice: 200,
          stock: 10,
          updatedAt: now,
        ),
      );
      final storage = InMemoryInventoryStorage();
      await storage.save(
        ShopDataSnapshot(
          products: initialProducts,
          sales: const [],
          expenses: const [],
          googleSheetsUrl: 'https://example.com/exec',
          lastCloudBackupProductsCount: 20,
          lastCloudBackupSalesCount: 0,
        ),
      );

      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();
      expect(ctrl.detectCloudBackupShrinkAnomaly(), isNull);

      // Simulate sudden unexplained drop (20 -> 2 products) without bulk deletion
      await ctrl.restoreFromSnapshot(
        ShopDataSnapshot(
          products: initialProducts.take(2).toList(),
          sales: const [],
          expenses: const [],
          googleSheetsUrl: 'https://example.com/exec',
          lastCloudBackupProductsCount: 20,
          lastCloudBackupSalesCount: 0,
        ),
        includeSettings: true,
      );
      final anomaly = ctrl.detectCloudBackupShrinkAnomaly();
      expect(anomaly, isNotNull);
      expect(anomaly!.prevProducts, 20);
      expect(anomaly.currentProducts, 2);

      await expectLater(
        () => ctrl.syncCloudBackupDelta(forceFull: false),
        throwsA(isA<CloudBackupShrinkException>()),
      );

      // Intentional bulk delete by user authorizes the shrink
      await ctrl.moveAllProductsToTrash();
      expect(ctrl.isBulkDeleteAuthorized, isTrue);
    },
  );

  test(
    'pendingSync flag persists on disk across restarts until sync succeeds',
    () async {
      final storage = InMemoryInventoryStorage();
      await storage.save(
        const ShopDataSnapshot(
          products: [],
          sales: [],
          expenses: [],
          catalogSeeded: true,
          googleSheetsUrl: 'https://invalid.local/exec',
          autoBackupEnabled: true,
        ),
      );

      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();
      expect(ctrl.pendingSync, isFalse);

      // Adding a product marks pendingSync=true on disk before timer fires
      await ctrl.addProduct(
        name: 'Офлайн-товар',
        category: 'Тест',
        costPrice: 100,
        sellPrice: 150,
        stock: 5,
      );
      expect(ctrl.pendingSync, isTrue);

      // Simulate app killed before sync completes and restarted
      final reloaded = ShopController(storage: storage);
      await reloaded.initialize();
      expect(reloaded.pendingSync, isTrue);
      ctrl.dispose();
      reloaded.dispose();
    },
  );

  test(
    'writeTextFileAtomically writes via .tmp, validates JSON, and preserves previous file on invalid JSON',
    () async {
      final target = File('${tempDir.path}/shop_backup.json');
      const initialValid = '{"version":2,"ok":true}';
      await writeTextFileAtomically(target, initialValid, validateJson: true);
      expect(await target.readAsString(), initialValid);
      expect(await File('${target.path}.tmp').exists(), isFalse);

      // Attempt to overwrite with corrupted JSON -> must throw and keep initialValid intact
      await expectLater(
        () => writeTextFileAtomically(
          target,
          '{"broken": [1, 2',
          validateJson: true,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(await target.readAsString(), initialValid);
      expect(await File('${target.path}.tmp').exists(), isFalse);
    },
  );

  test(
    'isQuickCheckOk validates PRAGMA quick_check output and restoreDatabaseFromLocalBackup restores from lumio_last_good.db or lumio_pre_upgrade.db',
    () async {
      expect(
        SqliteInventoryStorage.isQuickCheckOk(const [
          {'quick_check': 'ok'},
        ]),
        isTrue,
      );
      expect(
        SqliteInventoryStorage.isQuickCheckOk(const [
          {'quick_check': 'row 4 missing from index idx_products_sku'},
        ]),
        isFalse,
      );
      expect(SqliteInventoryStorage.isQuickCheckOk(const []), isFalse);

      final dbPath = '${tempDir.path}/lumio_shop.db';
      final lastGoodPath = SqliteInventoryStorage.lastGoodBackupPathFor(dbPath);
      final preUpgradePath =
          SqliteInventoryStorage.preUpgradeBackupPathFor(dbPath);

      final corruptBytes = utf8.encode('corrupted_db_bytes');
      final lastGoodBytes = utf8.encode('SQLite format 3\x00last_good');
      final preUpgradeBytes = utf8.encode('SQLite format 3\x00pre_upgrade');

      await File(dbPath).writeAsBytes(corruptBytes);
      await File('$dbPath-wal').writeAsString('stale wal');
      await File('$dbPath-shm').writeAsString('stale shm');
      await File(preUpgradePath).writeAsBytes(preUpgradeBytes);
      await File(lastGoodPath).writeAsBytes(lastGoodBytes);

      final restored =
          await SqliteInventoryStorage.restoreDatabaseFromLocalBackup(dbPath);
      expect(restored, lastGoodPath);
      expect(await File(dbPath).readAsBytes(), lastGoodBytes);
      expect(await File('$dbPath-wal').exists(), isFalse);
      expect(await File('$dbPath-shm').exists(), isFalse);
    },
  );

  test(
    'detectRemoteCatalogShrinkAnomaly blocks empty or nearly-empty local catalog from overwriting a populated Google Sheet',
    () async {
      final storage = InMemoryInventoryStorage();
      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      // Fresh install (0 local products) vs populated sheet (20 or 2 products) -> blocked
      final emptyVs20 = ctrl.detectRemoteCatalogShrinkAnomaly(20);
      expect(emptyVs20, isNotNull);
      expect(emptyVs20!.prevProducts, 20);
      expect(emptyVs20.currentProducts, 0);

      final emptyVs2 = ctrl.detectRemoteCatalogShrinkAnomaly(2);
      expect(emptyVs2, isNotNull);

      // Empty remote sheet (0 products) -> allowed
      expect(ctrl.detectRemoteCatalogShrinkAnomaly(0), isNull);

      // Add 2 local products (nearly empty) -> still blocked against 5 or 20 remote products,
      // but allowed against a small 2-product sheet
      for (var i = 0; i < 2; i++) {
        await ctrl.addProduct(
          name: 'Новый товар $i',
          category: 'Тест',
          costPrice: 100,
          sellPrice: 200,
          stock: 5,
        );
      }
      expect(ctrl.detectRemoteCatalogShrinkAnomaly(20), isNotNull);
      expect(ctrl.detectRemoteCatalogShrinkAnomaly(5), isNotNull);
      expect(ctrl.detectRemoteCatalogShrinkAnomaly(2), isNull);

      // Populate 18 local products -> allowed against 20 remote products
      for (var i = 2; i < 18; i++) {
        await ctrl.addProduct(
          name: 'Новый товар $i',
          category: 'Тест',
          costPrice: 100,
          sellPrice: 200,
          stock: 5,
        );
      }
      expect(ctrl.detectRemoteCatalogShrinkAnomaly(20), isNull);
    },
  );

  test(
    'restoreFromSnapshot always saves a pre-restore snapshot first and allows full rollback across restarts',
    () async {
      final dbFile = File('${tempDir.path}/pre_restore_shop_data.json');
      final storage = JsonFileInventoryStorage(filePath: dbFile.path);
      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();
      await ctrl.updateShopProfile(
        shopName: 'Оригинал Магазин',
        shopAddress: 'Тастак 1',
        shopPhone: '+77010001122',
        receiptFooter: 'Чек 1',
      );
      await ctrl.addProduct(
        name: 'Оригинальный товар',
        category: 'Плинтусы',
        costPrice: 500,
        sellPrice: 900,
        stock: 25,
      );
      expect(ctrl.hasPreRestoreBackup, isFalse);

      // Restore a different snapshot (simulating accidental/erroneous restore)
      await ctrl.restoreFromSnapshot(
        ShopDataSnapshot(
          products: [
            Product(
              id: 'prd_new',
              name: 'Чужой товар',
              category: 'Другое',
              costPrice: 10,
              sellPrice: 20,
              stock: 1,
              updatedAt: DateTime.now(),
            ),
          ],
          sales: const [],
          expenses: const [],
          shopName: 'Чужой Магазин',
        ),
        includeSettings: true,
      );

      expect(ctrl.hasPreRestoreBackup, isTrue);
      expect(ctrl.products.length, 1);
      expect(ctrl.products.first.name, 'Чужой товар');
      expect(ctrl.shopName, 'Чужой Магазин');

      // Reload controller from disk -> pre-restore backup must survive restart
      final reloaded = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await reloaded.initialize();
      expect(reloaded.hasPreRestoreBackup, isTrue);

      // Roll back to pre-restore snapshot
      final rolledBack = await reloaded.rollbackToPreRestoreBackup();
      expect(rolledBack, isTrue);
      expect(reloaded.products.length, 1);
      expect(reloaded.products.first.name, 'Оригинальный товар');
      expect(reloaded.products.first.stock, 25);
      expect(reloaded.shopName, 'Оригинал Магазин');
    },
  );

  test(
    'restoreFromSnapshot aborts without overwriting data if saving pre-restore snapshot fails',
    () async {
      final storage = _FailingPreRestoreStorage();
      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();
      await ctrl.addProduct(
        name: 'Защищённый товар',
        category: 'Тест',
        costPrice: 100,
        sellPrice: 200,
        stock: 10,
      );

      await expectLater(
        () => ctrl.restoreFromSnapshot(
          const ShopDataSnapshot(products: [], sales: [], expenses: []),
        ),
        throwsA(isA<FileSystemException>()),
      );

      // Original data must remain completely intact
      expect(ctrl.products.length, 1);
      expect(ctrl.products.first.name, 'Защищённый товар');
      expect(ctrl.hasPreRestoreBackup, isFalse);
    },
  );
  test(
    'archivablePastYears, year archive export, and archiveAndCompressYear compress past-year records to monthly totals while keeping unpaid debts',
    () async {
      final dbFile = File('${tempDir.path}/year_archive_shop_data.json');
      final storage = JsonFileInventoryStorage(filePath: dbFile.path);
      final pastYear = DateTime.now().year - 1;

      await storage.save(
        ShopDataSnapshot(
          products: const [],
          sales: [
            // 2 paid sales in Jan of pastYear
            Sale(
              id: 'sal_jan_1',
              items: const [
                SaleItem(
                  productId: 'p1',
                  productName: 'Товар А',
                  quantity: 2,
                  unitCost: 100,
                  unitPrice: 200,
                ),
              ],
              paymentMethod: PaymentMethod.cash,
              createdAt: DateTime(pastYear, 1, 10, 12),
            ),
            Sale(
              id: 'sal_jan_2',
              items: const [
                SaleItem(
                  productId: 'p2',
                  productName: 'Товар Б',
                  quantity: 3,
                  unitCost: 50,
                  unitPrice: 120,
                ),
              ],
              paymentMethod: PaymentMethod.kaspiQr,
              discount: 60,
              createdAt: DateTime(pastYear, 1, 20, 15),
            ),
            // 1 unpaid debt in Feb of pastYear -> must NOT be compressed
            Sale(
              id: 'sal_feb_debt',
              items: const [
                SaleItem(
                  productId: 'p1',
                  productName: 'Товар А',
                  quantity: 1,
                  unitCost: 100,
                  unitPrice: 200,
                ),
              ],
              paymentMethod: PaymentMethod.postPay,
              customerName: 'Должник',
              paidAmount: 50,
              createdAt: DateTime(pastYear, 2, 5, 11),
            ),
            // 1 sale in current year -> untouched
            Sale(
              id: 'sal_cur_1',
              items: const [
                SaleItem(
                  productId: 'p1',
                  productName: 'Товар А',
                  quantity: 1,
                  unitCost: 100,
                  unitPrice: 200,
                ),
              ],
              paymentMethod: PaymentMethod.cash,
              createdAt: DateTime.now(),
            ),
          ],
          stockIns: [
            StockInRecord(
              id: 'in_jan_1',
              supplierName: 'Поставщик 1',
              items: const [
                StockInItem(
                  productId: 'p1',
                  productName: 'Товар А',
                  quantity: 10,
                  unitCost: 100,
                ),
              ],
              createdAt: DateTime(pastYear, 1, 3, 9),
            ),
            StockInRecord(
              id: 'in_jan_2',
              supplierName: 'Поставщик 2',
              items: const [
                StockInItem(
                  productId: 'p2',
                  productName: 'Товар Б',
                  quantity: 5,
                  unitCost: 50,
                ),
              ],
              createdAt: DateTime(pastYear, 1, 15, 9),
            ),
          ],
          expenses: const [],
        ),
      );

      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      final years = ctrl.archivablePastYears;
      expect(years.length, 1);
      expect(years.first.year, pastYear);
      expect(years.first.salesCount, 3);
      expect(years.first.unpaidSalesCount, 1);
      expect(years.first.stockInsCount, 2);

      // Export raw year archive JSON & CSV before compression
      final rawSales = ctrl.rawSalesForYear(pastYear);
      final rawStockIns = ctrl.rawStockInsForYear(pastYear);
      final archiveJson = ExportService.buildYearArchiveJson(
        year: pastYear,
        sales: rawSales,
        stockIns: rawStockIns,
        currency: ctrl.currency,
      );
      final decoded = jsonDecode(archiveJson) as Map<String, dynamic>;
      expect(decoded['year'], pastYear);
      expect(decoded['salesCount'], 3);
      expect(decoded['stockInsCount'], 2);

      final archiveCsv = ExportService.buildYearArchiveCsvWithBom(
        year: pastYear,
        sales: rawSales,
        stockIns: rawStockIns,
      );
      expect(archiveCsv, contains('=== SALES $pastYear ==='));
      expect(archiveCsv, contains('=== STOCK-IN INVOICES $pastYear ==='));

      // Compress pastYear to monthly summaries
      final res = await ctrl.archiveAndCompressYear(pastYear);
      expect(res.compressedSales, 2);
      expect(res.compressedStockIns, 2);
      expect(res.keptUnpaidSales, 1);
      expect(res.monthlySummariesCreated, 2);

      // Verify exact totals preserved in Jan summary
      final janSummary = ctrl.sales.firstWhere(
        (s) => s.id == 'yrsum_sal_${pastYear}_01',
      );
      expect(janSummary.total, closeTo(700, 0.01)); // 400 + (360 - 60)
      expect(janSummary.totalCost, closeTo(350, 0.01)); // 200 + 150
      expect(janSummary.profit, closeTo(350, 0.01));
      expect(janSummary.totalUnits, 5);

      // Unpaid debt & current year sale remain untouched
      expect(ctrl.sales.any((s) => s.id == 'sal_feb_debt'), isTrue);
      expect(ctrl.sales.any((s) => s.id == 'sal_cur_1'), isTrue);

      // Stock-ins compressed to 1 monthly summary
      expect(ctrl.stockIns.length, 1);
      expect(ctrl.stockIns.first.id, 'yrsum_in_${pastYear}_01');
      expect(ctrl.stockIns.first.totalUnits, 15);
      expect(ctrl.stockIns.first.totalCost, closeTo(1250, 0.01));

      // No more uncompressed past-year records remain (except unpaid debt)
      expect(ctrl.archivablePastYears.first.salesCount, 1);
      expect(ctrl.archivablePastYears.first.stockInsCount, 0);
    },
  );
  test(
    'InputNormalizer normalizes phones (+7/8/spaces), double spaces in names, barcodes, and detects intra-product barcode conflicts',
    () async {
      // Phone normalization
      expect(InputNormalizer.normalizePhone('+7 (701) 123-45-67'), '+77011234567');
      expect(InputNormalizer.normalizePhone('8 701 123 45 67'), '+77011234567');
      expect(InputNormalizer.normalizePhone('87011234567'), '+77011234567');
      expect(InputNormalizer.normalizePhone('7011234567'), '+77011234567');

      // Name double-space & barcode normalization
      expect(
        InputNormalizer.normalizeDisplayName('  Плинтус   70мм   Белый  '),
        'Плинтус 70мм Белый',
      );
      expect(InputNormalizer.normalizeBarcode(' 460 123 456 '), '460123456');

      // Strict uniqueness check between SKU, Pack, Box
      final conflicts = InputNormalizer.findIntraProductBarcodeConflicts(
        sku: ' 2001234567893 ',
        packBarcode: '2001234567893',
        boxBarcode: '2021234567891',
      );
      expect(conflicts.length, 1);
      expect(conflicts.first.fieldA, 'sku');
      expect(conflicts.first.fieldB, 'pack');

      // Customer deduplication by normalized phone in ShopController
      final ctrl = ShopController(storage: InMemoryInventoryStorage());
      await ctrl.initialize();
      await ctrl.addCustomer(name: 'Марат', phone: '8 (701) 555-11-22');
      await ctrl.addCustomer(name: '  Марат   Клиент ', phone: '+77015551122');
      expect(ctrl.customers.length, 1);
      expect(ctrl.customers.first.phone, '+77015551122');
    },
  );
  test(
    'CatalogHealthService detects empty name, zero price, sell below cost, duplicate barcodes, and negative stock',
    () {
      final now = DateTime.now();
      final issues = CatalogHealthService.analyze([
        Product(
          id: 'p1',
          name: '   ',
          category: 'Тест',
          sku: '460111',
          costPrice: 100,
          sellPrice: 0,
          stock: -3,
          updatedAt: now,
        ),
        Product(
          id: 'p2',
          name: 'Товар ниже закупа',
          category: 'Тест',
          sku: '460111',
          costPrice: 500,
          sellPrice: 400,
          stock: 10,
          updatedAt: now,
        ),
        Product(
          id: 'p3',
          name: 'Здоровый товар',
          category: 'Тест',
          sku: '460222',
          costPrice: 100,
          sellPrice: 200,
          stock: 5,
          updatedAt: now,
        ),
      ]);

      expect(
        issues.any((i) => i.type == CatalogHealthIssueType.emptyName),
        isTrue,
      );
      expect(
        issues.any((i) => i.type == CatalogHealthIssueType.zeroPrice),
        isTrue,
      );
      expect(
        issues.any((i) => i.type == CatalogHealthIssueType.negativeStock),
        isTrue,
      );
      expect(
        issues.any((i) => i.type == CatalogHealthIssueType.sellBelowCost),
        isTrue,
      );
      expect(
        issues
            .where((i) => i.type == CatalogHealthIssueType.duplicateBarcode)
            .length,
        2,
      );

      // Clean catalog -> 0 issues
      expect(
        CatalogHealthService.analyze([
          Product(
            id: 'ok1',
            name: 'Чистый товар',
            category: 'Тест',
            sku: '460999',
            costPrice: 100,
            sellPrice: 200,
            stock: 5,
            updatedAt: now,
          ),
        ]),
        isEmpty,
      );
    },
  );
  test(
    'DailyLocalBackupService creates gzipped daily snapshots, deduplicates same-day writes, rotates to 7 days, and restores offline',
    () async {
      final backupDir = Directory('${tempDir.path}/daily_backups_test');
      final service = DailyLocalBackupService(
        customDirectory: backupDir,
        maxBackups: 7,
      );

      final sourceCtrl = ShopController(storage: InMemoryInventoryStorage());
      await sourceCtrl.initialize();
      await sourceCtrl.addProduct(
        name: 'Бэкап-товар',
        category: 'Тест',
        costPrice: 100,
        sellPrice: 200,
        stock: 12,
      );
      final snapshot = sourceCtrl.createBackupSnapshot();

      final day1 = DateTime(2026, 4, 1, 10, 0);
      expect(
        await service.saveDailyBackupIfNeeded(snapshot, now: day1),
        isTrue,
      );
      // Second write on same day without force is skipped
      expect(
        await service.saveDailyBackupIfNeeded(
          snapshot,
          now: DateTime(2026, 4, 1, 18, 0),
        ),
        isFalse,
      );

      // Write 8 more days -> total 9 days created, rotated down to latest 7
      for (var d = 2; d <= 9; d++) {
        await service.saveDailyBackupIfNeeded(
          snapshot,
          now: DateTime(2026, 4, d, 9, 0),
        );
      }

      final backups = await service.listBackups();
      expect(backups.length, 7);
      expect(backups.first.dateKey, '2026-04-09');
      expect(backups.last.dateKey, '2026-04-03');

      // Restore on a fresh/empty controller from offline daily backup
      final restoreCtrl = ShopController(
        storage: InMemoryInventoryStorage(),
        dailyBackupService: service,
      );
      await restoreCtrl.initialize();
      expect(restoreCtrl.products, isEmpty);

      final restored = await restoreCtrl.restoreFromDailyLocalBackup(
        backups.first,
        includeSettings: false,
      );
      expect(restored, isTrue);
      expect(restoreCtrl.products.length, 1);
      expect(restoreCtrl.products.first.name, 'Бэкап-товар');
      expect(restoreCtrl.products.first.stock, 12);
    },
  );
  test(
    'cloud timestamp protection blocks stale phone overwrite and warns when restoring older cloud backup over newer local data',
    () async {
      final t1 = DateTime(2026, 11, 20, 10, 0);
      final t2NewerCloud = DateTime(2026, 11, 21, 15, 0);
      final t3NewerLocal = DateTime(2026, 11, 22, 18, 0);

      // 1. Phone never synced (_lastAutoBackupAt is empty), cloud has a backup -> block overwrite
      final neverSyncedCtrl = ShopController(storage: InMemoryInventoryStorage());
      await neverSyncedCtrl.initialize();
      final conflictNeverSynced = neverSyncedCtrl.detectCloudNewerThanLocal(
        remoteBackupUpdatedAt: t2NewerCloud,
      );
      expect(conflictNeverSynced, isNotNull);
      expect(conflictNeverSynced!.isCloudNewer, isTrue);

      // 2. Phone synced at t1, cloud updated at t2 (from another device / PC) -> block overwrite
      final staleStorage = InMemoryInventoryStorage();
      await staleStorage.save(
        ShopDataSnapshot(
          products: [
            Product(
              id: 'p1',
              name: 'Товар 1',
              category: 'Тест',
              costPrice: 100,
              sellPrice: 200,
              stock: 5,
              updatedAt: t1,
            ),
          ],
          sales: const [],
          expenses: const [],
          lastAutoBackupAt: t1.toIso8601String(),
        ),
      );
      final staleCtrl = ShopController(storage: staleStorage);
      await staleCtrl.initialize();

      final conflictCloudNewer = staleCtrl.detectCloudNewerThanLocal(
        remoteBackupUpdatedAt: t2NewerCloud,
      );
      expect(conflictCloudNewer, isNotNull);
      expect(conflictCloudNewer!.isCloudNewer, isTrue);

      // Catalog-only newer edit on PC also triggers protection
      final conflictCatalogNewer = staleCtrl.detectCloudNewerThanLocal(
        remoteBackupUpdatedAt: t1,
        remoteCatalogUpdatedAt: t2NewerCloud,
      );
      expect(conflictCatalogNewer, isNotNull);

      // Up-to-date phone (cloud timestamp <= lastAutoBackupAt + 10s) -> allowed
      expect(
        staleCtrl.detectCloudNewerThanLocal(
          remoteBackupUpdatedAt: t1,
          remoteCatalogUpdatedAt: t1.add(const Duration(seconds: 5)),
        ),
        isNull,
      );

      // 3. Before restore: local has newer sale (t3) than cloud backup (t2) -> warn
      final newerLocalStorage = InMemoryInventoryStorage();
      await newerLocalStorage.save(
        ShopDataSnapshot(
          products: const [],
          sales: [
            Sale(
              id: 's_new',
              items: const [
                SaleItem(
                  productId: 'p1',
                  productName: 'Товар 1',
                  quantity: 1,
                  unitCost: 100,
                  unitPrice: 200,
                ),
              ],
              paymentMethod: PaymentMethod.cash,
              createdAt: t3NewerLocal,
            ),
          ],
          expenses: const [],
          lastAutoBackupAt: t1.toIso8601String(),
        ),
      );
      final newerLocalCtrl = ShopController(storage: newerLocalStorage);
      await newerLocalCtrl.initialize();

      final restoreWarning = newerLocalCtrl.detectLocalNewerThanCloud(
        remoteBackupUpdatedAt: t2NewerCloud,
      );
      expect(restoreWarning, isNotNull);
      expect(restoreWarning!.isCloudNewer, isFalse);

      // Cloud backup is newer than local data -> no warning
      expect(
        newerLocalCtrl.detectLocalNewerThanCloud(
          remoteBackupUpdatedAt: t3NewerLocal.add(const Duration(minutes: 5)),
        ),
        isNull,
      );
    },
  );
  test(
    'purgeExpiredTrash auto-deletes trashed products, sales, and expenses older than trashRetentionDays while keeping recent items',
    () async {
      final now = DateTime.now();
      final oldTrashedAt = now.subtract(const Duration(days: 45));
      final recentTrashedAt = now.subtract(const Duration(days: 10));

      final storage = InMemoryInventoryStorage();
      await storage.save(
        ShopDataSnapshot(
          products: [
            Product(
              id: 'p_old',
              name: 'Старый удалённый товар',
              category: 'Тест',
              costPrice: 100,
              sellPrice: 200,
              stock: 1,
              updatedAt: oldTrashedAt,
              trashedAt: oldTrashedAt,
            ),
            Product(
              id: 'p_recent',
              name: 'Недавно удалённый товар',
              category: 'Тест',
              costPrice: 100,
              sellPrice: 200,
              stock: 2,
              updatedAt: recentTrashedAt,
              trashedAt: recentTrashedAt,
            ),
            Product(
              id: 'p_active',
              name: 'Активный товар',
              category: 'Тест',
              costPrice: 100,
              sellPrice: 200,
              stock: 5,
              updatedAt: oldTrashedAt,
            ),
          ],
          sales: [
            Sale(
              id: 's_old',
              items: const [
                SaleItem(
                  productId: 'p_active',
                  productName: 'Активный товар',
                  quantity: 1,
                  unitCost: 100,
                  unitPrice: 200,
                ),
              ],
              paymentMethod: PaymentMethod.cash,
              createdAt: oldTrashedAt,
              trashedAt: oldTrashedAt,
            ),
            Sale(
              id: 's_recent',
              items: const [
                SaleItem(
                  productId: 'p_active',
                  productName: 'Активный товар',
                  quantity: 1,
                  unitCost: 100,
                  unitPrice: 200,
                ),
              ],
              paymentMethod: PaymentMethod.cash,
              createdAt: recentTrashedAt,
              trashedAt: recentTrashedAt,
            ),
          ],
          expenses: [
            Expense(
              id: 'e_old',
              title: 'Старый расход',
              category: ExpenseCategory.other,
              amount: 500,
              createdAt: oldTrashedAt,
              trashedAt: oldTrashedAt,
            ),
            Expense(
              id: 'e_recent',
              title: 'Недавний расход',
              category: ExpenseCategory.other,
              amount: 300,
              createdAt: recentTrashedAt,
              trashedAt: recentTrashedAt,
            ),
          ],
          trashRetentionDays: 30,
        ),
      );

      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      // Items older than 30 days are purged on initialize; recent & active items stay
      expect(ctrl.trashedProducts.map((p) => p.id), ['p_recent']);
      expect(ctrl.trashedSales.map((s) => s.id), ['s_recent']);
      expect(ctrl.trashedExpenses.map((e) => e.id), ['e_recent']);
      expect(ctrl.products.map((p) => p.id), ['p_active']);

      // Setting retention to 60 days preserves the 10-day-old items; setting 5 days purges them
      await ctrl.setTrashRetentionDays(60);
      expect(ctrl.trashRetentionDays, 60);
      expect(ctrl.trashCount, 3);

      final purged = await ctrl.setTrashRetentionDays(5);
      expect(purged, 3);
      expect(ctrl.trashCount, 0);
    },
  );
  test(
    'readableSectionsForSync keeps only sales in instant sync after daily heavy tabs sync and restores full 9 sections on next day or forceFull',
    () async {
      final storage = InMemoryInventoryStorage();
      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      final day1 = DateTime(2026, 11, 23, 10, 0);
      final day1Later = DateTime(2026, 11, 23, 18, 30);
      final day2 = DateTime(2026, 11, 24, 9, 0);

      // Before first sync of day1 -> all 9 sections are due
      expect(ctrl.isDailySectionsSyncDue(now: day1), isTrue);
      expect(
        ctrl.readableSectionsForSync(forceFull: false, now: day1).length,
        9,
      );

      // After daily sync completes on day1 -> instant sync only includes Sales
      ctrl.markDailySectionsSynced(now: day1);
      await storage.save(ctrl.createBackupSnapshot());
      expect(ctrl.isDailySectionsSyncDue(now: day1Later), isFalse);
      final instantSections =
          ctrl.readableSectionsForSync(forceFull: false, now: day1Later);
      expect(instantSections, [SheetExportSection.sales]);

      // Manual forceFull always includes all 9 sections on the same day
      expect(
        ctrl.readableSectionsForSync(forceFull: true, now: day1Later).length,
        9,
      );

      // Reload from storage -> daily sync date persists across restarts
      final reloaded = ShopController(storage: storage);
      await reloaded.initialize();
      expect(reloaded.isDailySectionsSyncDue(now: day1Later), isFalse);
      expect(
        reloaded.readableSectionsForSync(forceFull: false, now: day1Later),
        [SheetExportSection.sales],
      );

      // Next calendar day -> daily sections become due again
      expect(reloaded.isDailySectionsSyncDue(now: day2), isTrue);
      expect(
        reloaded.readableSectionsForSync(forceFull: false, now: day2).length,
        9,
      );
    },
  );
  test(
    'coalesces frequent edits of the same product within 2 minutes, cancels reverted fields, and keeps separate entries after window',
    () async {
      final ctrl = ShopController(storage: InMemoryInventoryStorage());
      await ctrl.initialize();

      final product = await ctrl.addProduct(
        name: 'Плинтус 60',
        category: 'Плинтусы',
        costPrice: 100,
        sellPrice: 200,
        stock: 10,
      );
      final initialChangesCount = ctrl.productChanges.length; // 1 ('create')

      final t0 = DateTime.now();
      // Edit 1 at t0: price 200 -> 250, name typo
      await ctrl.updateProduct(
        product.copyWith(sellPrice: 250, name: 'Плинтус 60м'),
        at: t0,
      );
      expect(ctrl.productChanges.length, initialChangesCount + 1);

      // Edit 2 at t0 + 45s: fix price 250 -> 280 and name typo -> 'Плинтус 60 мм'
      await ctrl.updateProduct(
        ctrl.findProductById(product.id)!.copyWith(
              sellPrice: 280,
              name: 'Плинтус 60 мм',
            ),
        at: t0.add(const Duration(seconds: 45)),
      );
      // Still 1 merged 'edit' entry!
      expect(ctrl.productChanges.length, initialChangesCount + 1);
      final merged = ctrl.productChanges.first;
      expect(merged.source, 'edit');
      expect(merged.productName, 'Плинтус 60 мм');
      final priceField = merged.fields.firstWhere((f) => f.key == 'sellPrice');
      expect(priceField.oldValue, '200');
      expect(priceField.newValue, '280');
      final nameField = merged.fields.firstWhere((f) => f.key == 'name');
      expect(nameField.oldValue, 'Плинтус 60');
      expect(nameField.newValue, 'Плинтус 60 мм');

      // Edit 3 at t0 + 90s: revert sellPrice back to 200 -> price field cancels out, name stays
      await ctrl.updateProduct(
        ctrl.findProductById(product.id)!.copyWith(sellPrice: 200),
        at: t0.add(const Duration(seconds: 90)),
      );
      expect(ctrl.productChanges.length, initialChangesCount + 1);
      expect(
        ctrl.productChanges.first.fields.any((f) => f.key == 'sellPrice'),
        isFalse,
      );
      expect(
        ctrl.productChanges.first.fields.any((f) => f.key == 'name'),
        isTrue,
      );

      // Edit 4 at t0 + 5 minutes (outside 2-minute window) -> creates a new separate entry
      await ctrl.updateProduct(
        ctrl.findProductById(product.id)!.copyWith(sellPrice: 300),
        at: t0.add(const Duration(minutes: 5)),
      );
      expect(ctrl.productChanges.length, initialChangesCount + 2);
      expect(ctrl.productChanges.first.fields.first.oldValue, '200');
      expect(ctrl.productChanges.first.fields.first.newValue, '300');
    },
  );
  test(
    'keeps only last 90 days of productChanges in memory and loads older 5-year entries from storage on demand',
    () async {
      final now = DateTime.now();
      final recentAt = now.subtract(const Duration(days: 15));
      final oldAt = now.subtract(const Duration(days: 400));

      final storage = InMemoryInventoryStorage();
      await storage.save(
        ShopDataSnapshot(
          products: [
            Product(
              id: 'p1',
              name: 'Товар 1',
              category: 'Тест',
              costPrice: 100,
              sellPrice: 250,
              stock: 10,
              updatedAt: recentAt,
            ),
          ],
          sales: const [],
          expenses: const [],
          productChanges: [
            ProductChangeEntry(
              id: 'chg_recent',
              productId: 'p1',
              productName: 'Товар 1',
              source: 'edit',
              fields: const [
                ProductChangeField(
                  key: 'sellPrice',
                  kind: 'price',
                  label: 'Цена',
                  oldValue: '200',
                  newValue: '250',
                ),
              ],
              createdAt: recentAt,
            ),
            ProductChangeEntry(
              id: 'chg_old',
              productId: 'p1',
              productName: 'Товар 1',
              source: 'edit',
              fields: const [
                ProductChangeField(
                  key: 'sellPrice',
                  kind: 'price',
                  label: 'Цена',
                  oldValue: '150',
                  newValue: '200',
                ),
              ],
              createdAt: oldAt,
            ),
          ],
        ),
      );

      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      // Only the recent (<= 90d) entry is kept in RAM
      expect(ctrl.productChanges.map((e) => e.id), ['chg_recent']);

      // Loading full history on demand returns both recent and 400-day-old entries
      final fullHistory = await ctrl.loadProductChanges(
        days: ShopController.changeHistoryRetentionDays,
      );
      expect(fullHistory.map((e) => e.id), ['chg_recent', 'chg_old']);

      // Per-product 5-year price history also returns both
      final priceHistory = await ctrl.loadPriceChangesForProduct('p1');
      expect(priceHistory.map((e) => e.id), ['chg_recent', 'chg_old']);

      // Clearing entries older than 30 days removes the 400-day-old entry from storage too
      final removed = await ctrl.clearProductChanges(olderThanDays: 30);
      expect(removed, 1);
      final afterClear = await ctrl.loadProductChanges(
        days: ShopController.changeHistoryRetentionDays,
      );
      expect(afterClear.map((e) => e.id), ['chg_recent']);
    },
  );
  test(
    'persists last selected category and sort for inventory and POS across restarts without triggering pendingSync',
    () async {
      final dbFile = File('${tempDir.path}/view_prefs_shop_data.json');
      final storage1 = JsonFileInventoryStorage(filePath: dbFile.path);
      final ctrl1 = ShopController(storage: storage1);
      await ctrl1.initialize();
      expect(ctrl1.inventorySelectedCategory, isEmpty);
      expect(ctrl1.inventorySort, 'newest');
      expect(ctrl1.posSelectedCategory, isEmpty);

      await ctrl1.setInventoryViewPreferences(
        category: 'Плинтусы',
        updateCategory: true,
        sort: 'priceDesc',
      );
      await ctrl1.setPosSelectedCategory('Электрика');
      expect(ctrl1.pendingSync, isFalse);

      // Restart with fresh controller
      final storage2 = JsonFileInventoryStorage(filePath: dbFile.path);
      final ctrl2 = ShopController(storage: storage2);
      await ctrl2.initialize();

      expect(ctrl2.inventorySelectedCategory, 'Плинтусы');
      expect(ctrl2.inventorySort, 'priceDesc');
      expect(ctrl2.posSelectedCategory, 'Электрика');

      // Reset category back to "All" (null)
      await ctrl2.setInventoryViewPreferences(category: null, updateCategory: true);
      await ctrl2.setPosSelectedCategory(null);

      final ctrl3 = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await ctrl3.initialize();
      expect(ctrl3.inventorySelectedCategory, isEmpty);
      expect(ctrl3.inventorySort, 'priceDesc');
      expect(ctrl3.posSelectedCategory, isEmpty);
    },
  );
  test(
    'attachBarcodeToProduct links new batch barcodes without overwriting primary SKU, finds by extraBarcodes, and persists',
    () async {
      final dbFile = File('${tempDir.path}/extra_barcodes_shop_data.json');
      final ctrl = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await ctrl.initialize();

      final p1 = await ctrl.addProduct(
        name: 'Плинтус Дуб',
        category: 'Плинтусы',
        sku: '4601112223334',
        costPrice: 200,
        sellPrice: 350,
        stock: 20,
      );
      final p2 = await ctrl.addProduct(
        name: 'Угол Дуб',
        category: 'Плинтусы',
        sku: '4609998887776',
        costPrice: 100,
        sellPrice: 200,
        stock: 15,
      );

      // Attach new batch barcode to p1
      final updated =
          await ctrl.attachBarcodeToProduct(p1.id, '460 555 666 777 8');
      expect(updated, isNotNull);
      expect(updated!.sku, '4601112223334'); // primary SKU preserved
      expect(updated.extraBarcodes, ['4605556667778']);

      // Both old and new barcodes resolve to p1
      expect(ctrl.findProductBySku('4601112223334')?.id, p1.id);
      expect(ctrl.findProductBySku('4605556667778')?.id, p1.id);

      // Attaching a barcode that already belongs to p2 is rejected (returns null)
      final conflict = await ctrl.attachBarcodeToProduct(p1.id, p2.sku);
      expect(conflict, isNull);

      // Persists across restart
      final reloaded = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await reloaded.initialize();
      expect(reloaded.findProductBySku('4605556667778')?.id, p1.id);
    },
  );
  test(
    'ExportService.buildCartEstimateText formats cart lines and total without modifying stock or creating sales',
    () async {
      final ctrl = ShopController(storage: InMemoryInventoryStorage());
      await ctrl.initialize();
      await ctrl.updateShopProfile(
        shopName: 'Тастак Склад',
        shopAddress: 'Ряд 4, место 12',
        shopPhone: '+77011234567',
        receiptFooter: '',
      );
      final p1 = await ctrl.addProduct(
        name: 'Плинтус 70мм',
        category: 'Плинтусы',
        costPrice: 200,
        sellPrice: 350,
        wholesalePrice: 280,
        wholesaleMinQty: 5,
        stock: 30,
      );
      final p2 = await ctrl.addProduct(
        name: 'Угол 70мм',
        category: 'Плинтусы',
        costPrice: 100,
        sellPrice: 180,
        stock: 15,
      );

      ctrl.setCartQuantity(p1.id, 5); // auto wholesale 280 * 5 = 1400
      ctrl.setCartQuantity(p2.id, 2); // 180 * 2 = 360

      final estimate = ExportService.buildCartEstimateText(
        ctrl.cartLines
            .map(
              (line) => (
                name: line.product.name,
                quantity: line.quantity,
                unitPrice: line.unitPrice,
                lineTotal: line.lineTotal,
                isWholesale: line.isWholesalePriceApplied,
              ),
            )
            .toList(),
        AppStrings(AppLanguage.ru),
        AppCurrency.kzt,
        shopName: ctrl.shopName,
        shopAddress: ctrl.shopAddress,
        shopPhone: ctrl.shopPhone,
        createdAt: DateTime(2026, 11, 23, 14, 30),
      );

      expect(estimate, contains('*Тастак Склад*'));
      expect(estimate, contains('Предварительный расчёт (смета)'));
      expect(estimate, contains('1. Плинтус 70мм: 5 ×'));
      expect(estimate, contains('2. Угол 70мм: 2 ×'));
      expect(estimate, contains('Позиций: 2 (7 шт.)'));
      expect(estimate, contains('Итого по смете:'));
      expect(estimate, contains('товар не списан'));

      // Stock, sales, and cart remain completely untouched
      expect(ctrl.findProductById(p1.id)!.stock, 30);
      expect(ctrl.findProductById(p2.id)!.stock, 15);
      expect(ctrl.sales, isEmpty);
      expect(ctrl.cartItemCount, 7);
    },
  );
  test(
    'ShopController defers archived/trashed items and old paid sales at startup and loads them on demand',
    () async {
      final now = DateTime.now();
      final recentAt = now.subtract(const Duration(days: 5));
      final oldAt = now.subtract(const Duration(days: 90));

      final fullSnapshot = ShopDataSnapshot(
        products: [
          Product(
            id: 'p_active',
            name: 'Активный товар',
            category: 'Тест',
            costPrice: 100,
            sellPrice: 200,
            stock: 10,
            updatedAt: recentAt,
          ),
          Product(
            id: 'p_arch',
            name: 'Архивный товар',
            category: 'Тест',
            costPrice: 100,
            sellPrice: 200,
            stock: 0,
            archivedAt: oldAt,
            updatedAt: oldAt,
          ),
          Product(
            id: 'p_trash',
            name: 'Удалённый товар',
            category: 'Тест',
            costPrice: 100,
            sellPrice: 200,
            stock: 0,
            trashedAt: recentAt,
            updatedAt: recentAt,
          ),
        ],
        sales: [
          Sale(
            id: 's_recent',
            items: const [
              SaleItem(
                productId: 'p_active',
                productName: 'Активный товар',
                quantity: 1,
                unitCost: 100,
                unitPrice: 200,
              ),
            ],
            paymentMethod: PaymentMethod.cash,
            createdAt: recentAt,
          ),
          Sale(
            id: 's_old_paid',
            items: const [
              SaleItem(
                productId: 'p_active',
                productName: 'Активный товар',
                quantity: 2,
                unitCost: 100,
                unitPrice: 200,
              ),
            ],
            paymentMethod: PaymentMethod.cash,
            createdAt: oldAt,
          ),
          Sale(
            id: 's_old_debt',
            items: const [
              SaleItem(
                productId: 'p_active',
                productName: 'Активный товар',
                quantity: 1,
                unitCost: 100,
                unitPrice: 200,
              ),
            ],
            paymentMethod: PaymentMethod.postPay,
            customerName: 'Должник',
            paidAmount: 50,
            createdAt: oldAt,
          ),
        ],
        expenses: [
          Expense(
            id: 'e_active',
            title: 'Аренда',
            category: ExpenseCategory.rent,
            amount: 1000,
            createdAt: recentAt,
          ),
          Expense(
            id: 'e_trash',
            title: 'Удалённый расход',
            category: ExpenseCategory.other,
            amount: 500,
            createdAt: recentAt,
            trashedAt: recentAt,
          ),
        ],
        catalogSeeded: true,
      );

      final storage = _LazyStartupStorage(fullSnapshot);
      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      // Startup only loaded active products, recent sales + unpaid debt, active expenses
      expect(ctrl.products.map((p) => p.id), ['p_active']);
      expect(ctrl.archivedProducts, isEmpty);
      expect(ctrl.trashedProducts, isEmpty);
      expect(ctrl.sales.map((s) => s.id), ['s_recent', 's_old_debt']);
      expect(ctrl.expenses.map((e) => e.id), ['e_active']);

      // Opening Archive/Trash loads archived/trashed products & expenses
      await ctrl.ensureArchiveAndTrashLoaded();
      expect(ctrl.archivedProducts.map((p) => p.id), ['p_arch']);
      expect(ctrl.trashedProducts.map((p) => p.id), ['p_trash']);
      expect(ctrl.trashedExpenses.map((e) => e.id), ['e_trash']);

      // Switching Sales filter to "All" loads old paid sales
      await ctrl.ensureAllSalesLoaded();
      expect(
        ctrl.sales.map((s) => s.id),
        unorderedEquals(['s_recent', 's_old_paid', 's_old_debt']),
      );
    },
  );
  test(
    'ShopController persists sellers list, activeSeller, and stamps sellerName on sales and returns',
    () async {
      final dbFile = File('${tempDir.path}/sellers_shop_data.json');
      final ctrl = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await ctrl.initialize();

      final p = await ctrl.addProduct(
        name: 'Плинтус 80мм',
        category: 'Плинтусы',
        costPrice: 200,
        sellPrice: 400,
        stock: 20,
      );

      await ctrl.addSeller('Айгерим');
      await ctrl.addSeller('Данияр');
      expect(ctrl.sellers, ['Айгерим', 'Данияр']);
      expect(ctrl.activeSeller, 'Данияр');

      ctrl.addToCart(p.id, quantity: 2);
      final sale1 = await ctrl.completeSale();
      expect(sale1, isNotNull);
      expect(sale1!.sellerName, 'Данияр');

      // Switch seller in 1 tap and record another sale + partial return
      await ctrl.setActiveSeller('Айгерим');
      ctrl.addToCart(p.id, quantity: 3);
      final sale2 = await ctrl.completeSale();
      expect(sale2, isNotNull);
      expect(sale2!.sellerName, 'Айгерим');

      await ctrl.processSaleReturnOrExchange(
        saleId: sale2.id,
        returnQuantities: {p.id: 1},
        returnToStock: true,
        settlementMethod: PaymentMethod.cash,
      );

      // Reload from storage -> sellers, activeSeller, and sale.sellerName persist
      final reloaded = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await reloaded.initialize();
      expect(reloaded.sellers, ['Айгерим', 'Данияр']);
      expect(reloaded.activeSeller, 'Айгерим');
      final reloadedSale2 =
          reloaded.sales.firstWhere((s) => s.id == sale2.id);
      expect(reloadedSale2.sellerName, 'Айгерим');
      expect(reloadedSale2.hasReturn, isTrue);
    },
  );
  test(
    'supports fractional quantities (0.5, 1.25) in products, cart, sales, stock-in, stocktake, and persistence',
    () async {
      final dbFile = File('${tempDir.path}/fractional_qty_shop_data.json');
      final ctrl = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await ctrl.initialize();

      final cable = await ctrl.addProduct(
        name: 'Кабель ВВГ 3x2.5',
        category: 'Электрика',
        unit: 'м',
        costPrice: 400,
        sellPrice: 600,
        stock: 10.5,
      );

      // Sell 1.25m on POS
      ctrl.setCartQuantity(cable.id, 1.25);
      expect(ctrl.cartQuantityFor(cable.id), closeTo(1.25, 0.0001));
      expect(ctrl.cartSubtotal, closeTo(750, 0.01));
      final sale = await ctrl.completeSale();
      expect(sale, isNotNull);
      expect(sale!.items.single.quantity, closeTo(1.25, 0.0001));
      expect(ctrl.findProductById(cable.id)!.stock, closeTo(9.25, 0.0001));

      // Stock-in 0.5m
      await ctrl.receiveStock(
        supplierName: 'Опт',
        items: [
          StockInItem(
            productId: cable.id,
            productName: cable.name,
            quantity: 0.5,
            unitCost: 400,
          ),
        ],
      );
      expect(ctrl.findProductById(cable.id)!.stock, closeTo(9.75, 0.0001));

      // Reload from disk -> fractional stock and sale quantity survive
      final reloaded = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await reloaded.initialize();
      expect(reloaded.findProductById(cable.id)!.stock, closeTo(9.75, 0.0001));
      expect(reloaded.sales.single.items.single.quantity, closeTo(1.25, 0.0001));
    },
  );
  test(
    'receiveStock automatically adds products with changed sellPrice to priceTagQueue, persists across restarts, and removes on markPriceTagPrinted',
    () async {
      final dbFile = File('${tempDir.path}/price_tag_queue_shop_data.json');
      final ctrl = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await ctrl.initialize();

      final pChanged = await ctrl.addProduct(
        name: 'Плинтус 80мм',
        category: 'Плинтусы',
        costPrice: 200,
        sellPrice: 350,
        stock: 10,
      );
      final pSame = await ctrl.addProduct(
        name: 'Угол 80мм',
        category: 'Плинтусы',
        costPrice: 100,
        sellPrice: 180,
        stock: 10,
      );

      // Stock-in changes sellPrice of pChanged (350 -> 420), keeps pSame at 180
      await ctrl.receiveStock(
        supplierName: 'Опт',
        items: [
          StockInItem(
            productId: pChanged.id,
            productName: pChanged.name,
            quantity: 5,
            unitCost: 240,
            newSellPrice: 420,
          ),
          StockInItem(
            productId: pSame.id,
            productName: pSame.name,
            quantity: 5,
            unitCost: 110,
          ),
        ],
      );

      expect(ctrl.priceTagQueue, [pChanged.id]);
      expect(ctrl.priceTagQueueProducts.map((p) => p.id), [pChanged.id]);

      // Persists across restart
      final reloaded = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await reloaded.initialize();
      expect(reloaded.priceTagQueue, [pChanged.id]);

      // Marking as printed removes it from queue
      await reloaded.markPriceTagPrinted(pChanged.id);
      expect(reloaded.priceTagQueue, isEmpty);
    },
  );
  test(
    'isSaleBelowCost detects manual price or discount below cost, blocks cashier without owner PIN, and allows with valid PIN',
    () async {
      final ctrl = ShopController(storage: InMemoryInventoryStorage());
      await ctrl.initialize();
      await ctrl.setOwnerPin('4321');
      await ctrl.enterCashierMode();

      final p = await ctrl.addProduct(
        name: 'Плинтус 80мм',
        category: 'Плинтусы',
        costPrice: 300,
        sellPrice: 500,
        stock: 10,
      );

      ctrl.setCartQuantity(p.id, 2); // totalCost=600, subtotal=1000
      expect(ctrl.isSaleBelowCost(), isFalse);
      expect(ctrl.isSaleBelowCost(discount: 300), isFalse); // 700 >= 600
      expect(ctrl.isSaleBelowCost(discount: 500), isTrue); // 500 < 600

      // Cashier cannot complete below-cost sale by discount without owner PIN
      final blockedDiscount = await ctrl.completeSale(discount: 500);
      expect(blockedDiscount, isNull);
      expect(ctrl.sales, isEmpty);

      // Cashier cannot complete below-cost sale by manual price edit without owner PIN
      ctrl.setCartItemPrice(p.id, 250);
      expect(ctrl.hasBelowCostCartItems, isTrue);
      expect(ctrl.isSaleBelowCost(), isTrue);
      final blockedManual = await ctrl.completeSale();
      expect(blockedManual, isNull);

      // Wrong PIN is also rejected
      final blockedWrongPin = await ctrl.completeSale(ownerPinAttempt: '0000');
      expect(blockedWrongPin, isNull);

      // Valid owner PIN allows completing the sale
      final allowed = await ctrl.completeSale(ownerPinAttempt: '4321');
      expect(allowed, isNotNull);
      expect(ctrl.sales.length, 1);
    },
  );
  test(
    'captureCartSnapshot and restoreCartSnapshot restore cleared cart quantities, custom prices, and wholesale mode for Undo',
    () async {
      final ctrl = ShopController(storage: InMemoryInventoryStorage());
      await ctrl.initialize();

      final p = await ctrl.addProduct(
        name: 'Плинтус 80мм',
        category: 'Плинтусы',
        costPrice: 200,
        sellPrice: 350,
        wholesalePrice: 280,
        stock: 20,
      );

      ctrl.setCartQuantity(p.id, 2.5);
      ctrl.setCartItemPrice(p.id, 310);
      ctrl.setWholesaleCartMode(true);

      final snapshot = ctrl.captureCartSnapshot();
      ctrl.clearCart();
      expect(ctrl.cartLines, isEmpty);
      expect(ctrl.wholesaleCartMode, isFalse);

      ctrl.restoreCartSnapshot(snapshot);
      expect(ctrl.cartLines.length, 1);
      expect(ctrl.cartQuantityFor(p.id), closeTo(2.5, 0.0001));
      expect(ctrl.cartLines.single.unitPrice, 310);
      expect(ctrl.wholesaleCartMode, isTrue);
    },
  );
  test(
    'buildPurchaseOrderSuggestions collects negative, zero, and low-stock products with lastSupplier and formats WhatsApp order',
    () async {
      final ctrl = ShopController(storage: InMemoryInventoryStorage());
      await ctrl.initialize();
      await ctrl.exitCashierMode('');

      final pNeg = await ctrl.addProduct(
        name: 'Кабель 3x2.5',
        category: 'Электрика',
        sku: '460111',
        unit: 'м',
        costPrice: 300,
        sellPrice: 500,
        stock: 0,
        lowStockThreshold: 5,
      );
      ctrl.setCartQuantity(pNeg.id, 2);
      await ctrl.completeSale(); // stock = -2
      final pLow = await ctrl.addProduct(
        name: 'Автомат 16А',
        category: 'Электрика',
        costPrice: 800,
        sellPrice: 1200,
        stock: 2,
        lowStockThreshold: 5,
      );
      final pOk = await ctrl.addProduct(
        name: 'Розетка',
        category: 'Электрика',
        costPrice: 500,
        sellPrice: 900,
        stock: 20,
        lowStockThreshold: 5,
      );

      await ctrl.receiveStock(
        supplierName: 'ЭлектроСнаб',
        items: [
          StockInItem(
            productId: pLow.id,
            productName: pLow.name,
            quantity: 1,
            unitCost: 800,
          ),
        ],
      ); // pLow stock = 3 (still <= 5)

      final suggestions = ctrl.buildPurchaseOrderSuggestions();
      expect(suggestions.map((s) => s.product.id), [pNeg.id, pLow.id]);
      expect(suggestions.any((s) => s.product.id == pOk.id), isFalse);
      // pNeg (-2, threshold 5 -> target 10 -> suggested 12)
      expect(suggestions.first.suggestedQty, closeTo(12, 0.001));
      // pLow (3, threshold 5 -> target 10 -> suggested 7)
      expect(suggestions.last.suggestedQty, closeTo(7, 0.001));
      expect(suggestions.last.lastSupplier, 'ЭлектроСнаб');

      final orderText = ExportService.buildPurchaseOrderText(
        suggestions
            .map((s) => (product: s.product, quantity: s.suggestedQty))
            .toList(),
        AppStrings(AppLanguage.ru),
        supplierName: 'ЭлектроСнаб',
        shopName: 'Тастак Склад',
        createdAt: DateTime(2026, 11, 24, 10, 55),
      );
      expect(orderText, contains('Заявка поставщику: ЭлектроСнаб'));
      expect(orderText, contains('Кабель 3x2.5 (460111) — 12 м'));
      expect(orderText, contains('Автомат 16А — 7'));
    },
  );
  test(
    'Product.imagePath serializes, persists across restarts, and ProductImageService saves and deletes thumbnail files',
    () async {
      final imgDir = Directory('${tempDir.path}/product_images');
      final savedPath = await ProductImageService.saveImageBytes(
        utf8.encode('fake_jpeg_bytes'),
        productId: 'prd_photo_1',
        customDirectory: imgDir,
      );
      expect(await File(savedPath).exists(), isTrue);

      final dbFile = File('${tempDir.path}/photo_shop_data.json');
      final ctrl = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await ctrl.initialize();

      final added = await ctrl.addProduct(
        name: 'Плинтус Белый',
        category: 'Плинтусы',
        costPrice: 200,
        sellPrice: 350,
        stock: 10,
        imagePath: savedPath,
      );
      expect(added.imagePath, savedPath);

      final reloaded = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await reloaded.initialize();
      expect(reloaded.findProductById(added.id)!.imagePath, savedPath);

      await ProductImageService.deleteImageFile(savedPath);
      expect(await File(savedPath).exists(), isFalse);
    },
  );
  test(
    'applyCustomerSegmentForCart enables wholesaleCartMode for wholesale customers and reverts when switched to retail',
    () async {
      final ctrl = ShopController(storage: InMemoryInventoryStorage());
      await ctrl.initialize();

      final p = await ctrl.addProduct(
        name: 'Плинтус 80мм',
        category: 'Плинтусы',
        costPrice: 200,
        sellPrice: 400,
        wholesalePrice: 300,
        stock: 20,
      );
      await ctrl.addCustomer(
        name: 'ТОО СтройОпт',
        segment: CustomerSegment.wholesale,
      );
      await ctrl.addCustomer(
        name: 'Асет',
        segment: CustomerSegment.retail,
      );

      ctrl.setCartQuantity(p.id, 2);
      expect(ctrl.wholesaleCartMode, isFalse);
      expect(ctrl.cartSubtotal, 800);

      // Selecting wholesale customer switches cart to wholesale prices
      final seg1 = ctrl.applyCustomerSegmentForCart('ТОО СтройОпт');
      expect(seg1, CustomerSegment.wholesale);
      expect(ctrl.wholesaleCartMode, isTrue);
      expect(ctrl.cartSubtotal, 600);

      // Switching to retail customer reverts auto-enabled wholesale mode
      final seg2 = ctrl.applyCustomerSegmentForCart('Асет');
      expect(seg2, CustomerSegment.retail);
      expect(ctrl.wholesaleCartMode, isFalse);
      expect(ctrl.cartSubtotal, 800);

      // Manual wholesale mode is preserved when clearing customer
      ctrl.setWholesaleCartMode(true);
      ctrl.applyCustomerSegmentForCart('');
      expect(ctrl.wholesaleCartMode, isTrue);
    },
  );
  test(
    'WhatsAppLauncher builds direct chat URI from normalized phone and formats overdue debt reminder',
    () {
      expect(
        WhatsAppLauncher.normalizeWhatsAppDigits('8 (701) 555-11-22'),
        '77015551122',
      );
      expect(WhatsAppLauncher.normalizeWhatsAppDigits('123'), isEmpty);

      final msg = AppStrings(AppLanguage.ru).debtReminderMessage(
        customerName: 'Марат',
        amount: '15 000 ₸',
        dueDate: '2026-11-20',
        isOverdue: true,
        shopName: 'Тастак Склад',
      );
      expect(msg, contains('Здравствуйте, Марат!'));
      expect(msg, contains('15 000 ₸'));
      expect(msg, contains('просрочено с 2026-11-20'));

      final uri = WhatsAppLauncher.buildWhatsAppUri(
        phone: '+7 (701) 555-11-22',
        message: msg,
      );
      expect(uri, isNotNull);
      expect(uri!.host, 'wa.me');
      expect(uri.path, '/77015551122');
      expect(uri.queryParameters['text'], msg);
    },
  );

  test(
    'cash drawer deposits and withdrawals persist and calculate daily totals separately from expenses',
    () async {
      final storage = InMemoryInventoryStorage();
      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      await ctrl.addCashDrawerMovement(
        isDeposit: true,
        amount: 5000,
        note: 'Размен утром',
      );
      await ctrl.addCashDrawerMovement(
        isDeposit: false,
        amount: 12000,
        note: 'Инкассация владельцу',
      );

      expect(ctrl.todayCashDepositsTotal, 5000);
      expect(ctrl.todayCashWithdrawalsTotal, 12000);
      expect(ctrl.todayCashDrawerMovements.length, 2);
      expect(ctrl.totalExpensesFor(SalesDateFilter.today), 0);

      final ctrl2 = ShopController(storage: storage);
      await ctrl2.initialize();
      expect(ctrl2.todayCashDepositsTotal, 5000);
      expect(ctrl2.todayCashWithdrawalsTotal, 12000);

      final depositId = ctrl2.cashDrawerMovements
          .firstWhere((m) => m.isDeposit)
          .id;
      await ctrl2.deleteCashDrawerMovement(depositId);
      expect(ctrl2.todayCashDepositsTotal, 0);
      expect(ctrl2.todayCashWithdrawalsTotal, 12000);
    },
  );

  test(
    'buildSupplierDirectory and buildCheapestSupplierByProduct aggregate purchase history and find cheapest last supplier',
    () async {
      final storage = InMemoryInventoryStorage();
      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      await ctrl.addProduct(
        name: 'Чай Ассам',
        category: 'Продукты',
        costPrice: 500,
        sellPrice: 700,
        stock: 5,
      );
      final tea = ctrl.products.first;

      await ctrl.receiveStock(
        supplierName: 'База Юг',
        items: [
          StockInItem(
            productId: tea.id,
            productName: tea.name,
            quantity: 10,
            unitCost: 520,
          ),
        ],
      );
      await ctrl.receiveStock(
        supplierName: 'Алматы Опт',
        items: [
          StockInItem(
            productId: tea.id,
            productName: tea.name,
            quantity: 20,
            unitCost: 450,
          ),
        ],
      );

      final dir = ctrl.buildSupplierDirectory();
      expect(dir.length, 2);
      expect(dir.map((s) => s.name), containsAll(['База Юг', 'Алматы Опт']));

      final hints = ctrl.buildCheapestSupplierByProduct();
      expect(hints.length, 1);
      expect(hints.first.cheapestSupplier, 'Алматы Опт');
      expect(hints.first.cheapestPrice, 450);
      expect(hints.first.quotes.length, 2);
    },
  );

  test(
    'InputNormalizer.matchesProductSearch supports trailing 4 barcode digits and EN/RU keyboard layout swap',
    () {
      final now = DateTime.now();
      final milk = Product(
        id: 'p_milk',
        name: 'Молоко 3.2%',
        category: 'Молочка',
        costPrice: 300,
        sellPrice: 450,
        stock: 10,
        sku: '4870001234821',
        extraBarcodes: const ['4607001119988'],
        updatedAt: now,
      );
      final cola = Product(
        id: 'p_cola',
        name: 'Coca-Cola 1L',
        category: 'Напитки',
        costPrice: 280,
        sellPrice: 420,
        stock: 8,
        sku: '5449000000996',
        updatedAt: now,
      );

      expect(InputNormalizer.matchesProductSearch(milk, '4821'), isTrue);
      expect(InputNormalizer.matchesProductSearch(milk, '9988'), isTrue);
      expect(InputNormalizer.matchesProductSearch(milk, '9999'), isFalse);

      expect(InputNormalizer.matchesProductSearch(milk, 'vjkjrj'), isTrue);
      expect(InputNormalizer.matchesProductSearch(cola, 'сщдф'), isTrue);
    },
  );

  test(
    'repeatSaleToCart copies items from previous customer order and enables wholesale for wholesale customer',
    () async {
      final storage = InMemoryInventoryStorage();
      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      await ctrl.addCustomer(
        name: 'Опт Мир',
        segment: CustomerSegment.wholesale,
      );
      await ctrl.addProduct(
        name: 'Сахар 1кг',
        category: 'Продукты',
        costPrice: 300,
        sellPrice: 400,
        wholesalePrice: 350,
        stock: 20,
      );
      final sugar = ctrl.products.first;

      ctrl.addToCart(sugar.id);
      ctrl.setCartQuantity(sugar.id, 5);
      final sale = await ctrl.completeSale(customerName: 'Опт Мир');
      expect(sale, isNotNull);
      expect(ctrl.cartItemCount, 0);

      ctrl.setWholesaleCartMode(false);
      final res = ctrl.repeatSaleToCart(sale!);
      expect(res.addedLines, 1);
      expect(res.skippedCount, 0);
      expect(ctrl.cartQuantityFor(sugar.id), 5);
      expect(ctrl.wholesaleCartMode, isTrue);
    },
  );

  test(
    'HardwareBarcodeBuffer collects fast HID scanner keystrokes and emits code on Enter',
    () {
      final buf = HardwareBarcodeBuffer();
      var t = DateTime(2026, 11, 24, 13, 0, 0);
      for (final ch in '4870001234821'.split('')) {
        final res = buf.processKey(
          logicalKey: LogicalKeyboardKey.digit0,
          character: ch,
          now: t,
        );
        expect(res, isNull);
        t = t.add(const Duration(milliseconds: 20));
      }
      final scanned = buf.processKey(
        logicalKey: LogicalKeyboardKey.enter,
        character: null,
        now: t.add(const Duration(milliseconds: 20)),
      );
      expect(scanned, '4870001234821');

      // Slow manual typing > 400ms resets buffer
      buf.processKey(
        logicalKey: LogicalKeyboardKey.digit1,
        character: '1',
        now: t,
      );
      final afterPause = buf.processKey(
        logicalKey: LogicalKeyboardKey.enter,
        character: null,
        now: t.add(const Duration(milliseconds: 500)),
      );
      expect(afterPause, isNull);
    },
  );

  test(
    'addCustomCartItem adds free-form item without creating a product card and completes sale',
    () async {
      final storage = InMemoryInventoryStorage();
      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      expect(ctrl.products, isEmpty);
      final customId = ctrl.addCustomCartItem(
        price: 150,
        name: 'Пакет майка',
        quantity: 2,
      );
      expect(customId, isNotEmpty);
      expect(ctrl.cartSubtotal, 300);
      expect(ctrl.cartItemCount, 2);

      final sale = await ctrl.completeSale();
      expect(sale, isNotNull);
      expect(sale!.total, 300);
      expect(sale.items.single.productName, 'Пакет майка');
      expect(ctrl.products, isEmpty);
      expect(ctrl.cartLines, isEmpty);
    },
  );

  test(
    'ThermalPrinterService encodes CP866 Cyrillic and builds ESC/POS receipt & price tag bytes',
    () {
      final cp866 = ThermalPrinterService.encodeCp866('Привет №1');
      expect(cp866, isNotEmpty);
      expect(cp866.first, 0x8F); // 'П' in CP866

      final strings = AppStrings(AppLanguage.ru);
      final now = DateTime(2026, 11, 24, 13, 40);
      final sale = Sale(
        id: 's_print_1',
        paymentMethod: PaymentMethod.cash,
        items: const [
          SaleItem(
            productId: 'p1',
            productName: 'Молоко',
            quantity: 2,
            unitCost: 300,
            unitPrice: 450,
          ),
        ],
        createdAt: now,
      );
      final receipt58 = ThermalPrinterService.buildReceiptEscPos(
        sale: sale,
        strings: strings,
        currency: AppCurrency.kzt,
        is80mm: false,
        shopName: 'Тастак',
      );
      expect(receipt58.take(5).toList(), [0x1B, 0x40, 0x1B, 0x74, 0x11]);
      expect(receipt58.length, greaterThan(40));

      final tag = ThermalPrinterService.buildPriceTagEscPos(
        product: Product(
          id: 'p1',
          name: 'Молоко',
          category: 'Молочка',
          costPrice: 300,
          sellPrice: 450,
          stock: 10,
          sku: '4870001234821',
          updatedAt: now,
        ),
        currency: AppCurrency.kzt,
        is80mm: true,
      );
      expect(tag.take(5).toList(), [0x1B, 0x40, 0x1B, 0x74, 0x11]);
      expect(tag.length, greaterThan(20));
    },
  );

  test(
    'frequentlyBoughtTogetherForCart recommends co-occurring products ranked by frequency',
    () async {
      final storage = InMemoryInventoryStorage();
      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      await ctrl.addProduct(
        name: 'Кофе',
        category: 'Напитки',
        costPrice: 400,
        sellPrice: 600,
        stock: 20,
      );
      await ctrl.addProduct(
        name: 'Молоко',
        category: 'Молочка',
        costPrice: 300,
        sellPrice: 450,
        stock: 20,
      );
      await ctrl.addProduct(
        name: 'Сахар',
        category: 'Продукты',
        costPrice: 250,
        sellPrice: 350,
        stock: 20,
      );

      final coffee = ctrl.products.firstWhere((p) => p.name == 'Кофе');
      final milk = ctrl.products.firstWhere((p) => p.name == 'Молоко');
      final sugar = ctrl.products.firstWhere((p) => p.name == 'Сахар');

      // 2 receipts with Coffee + Milk, 1 receipt with Coffee + Sugar
      for (var i = 0; i < 2; i++) {
        ctrl.addToCart(coffee.id);
        ctrl.addToCart(milk.id);
        await ctrl.completeSale();
      }
      ctrl.addToCart(coffee.id);
      ctrl.addToCart(sugar.id);
      await ctrl.completeSale();

      ctrl.addToCart(coffee.id);
      final upsell = ctrl.frequentlyBoughtTogetherForCart(limit: 3);
      expect(upsell.map((p) => p.name).toList(), ['Молоко', 'Сахар']);

      // Once Milk is added to cart, only Sugar remains suggested
      ctrl.addToCart(milk.id);
      final upsellAfter = ctrl.frequentlyBoughtTogetherForCart(limit: 3);
      expect(upsellAfter.map((p) => p.name).toList(), ['Сахар']);
    },
  );

  test(
    'ExportService.buildPriceListText filters by category, in-stock, and new arrivals and formats retail & wholesale prices',
    () {
      final now = DateTime(2026, 11, 24, 15, 0);
      final strings = AppStrings(AppLanguage.ru);
      final products = [
        Product(
          id: 'p1',
          name: 'Плинтус 70мм',
          category: 'Плинтусы',
          costPrice: 200,
          sellPrice: 350,
          wholesalePrice: 280,
          wholesaleMinQty: 10,
          stock: 25,
          updatedAt: now.subtract(const Duration(days: 2)),
        ),
        Product(
          id: 'p2',
          name: 'Угол 70мм',
          category: 'Плинтусы',
          costPrice: 100,
          sellPrice: 180,
          stock: 0,
          updatedAt: now.subtract(const Duration(days: 30)),
        ),
        Product(
          id: 'p3',
          name: 'Кабель 3x2.5',
          category: 'Электрика',
          unit: 'м',
          costPrice: 300,
          sellPrice: 450,
          stock: 50,
          updatedAt: now.subtract(const Duration(days: 30)),
        ),
      ];

      final groupList = ExportService.buildPriceListText(
        products: products,
        strings: strings,
        currency: AppCurrency.kzt,
        category: 'Плинтусы',
        inStockOnly: true,
        includeWholesale: true,
        includeStock: true,
        shopName: 'Тастак',
        now: now,
      );
      expect(groupList, contains('*Тастак*'));
      expect(groupList, contains('Плинтус 70мм'));
      expect(groupList, contains('Опт:'));
      expect(groupList, contains('от 10 шт.'));
      expect(groupList, isNot(contains('Угол 70мм')));
      expect(groupList, isNot(contains('Кабель 3x2.5')));

      final newOnly = ExportService.buildPriceListText(
        products: products,
        strings: strings,
        currency: AppCurrency.kzt,
        inStockOnly: false,
        newArrivalsOnly: true,
        now: now,
      );
      expect(newOnly, contains('Плинтус 70мм'));
      expect(newOnly, isNot(contains('Угол 70мм')));
      expect(newOnly, isNot(contains('Кабель 3x2.5')));
    },
  );

  test(
    'estimatedDaysOfStockByProduct computes remaining stock days from recent sales pace',
    () async {
      final storage = InMemoryInventoryStorage();
      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      final hit = await ctrl.addProduct(
        name: 'Вода 1л',
        category: 'Напитки',
        costPrice: 100,
        sellPrice: 200,
        stock: 10,
      );
      final slow = await ctrl.addProduct(
        name: 'Редкий товар',
        category: 'Разное',
        costPrice: 100,
        sellPrice: 200,
        stock: 10,
      );

      // Sell 4 units of hit today (4/day pace -> remaining 6 units => ~2 days)
      ctrl.setCartQuantity(hit.id, 4);
      await ctrl.completeSale();

      // Sell only 1 unit of slow (below 3-unit threshold -> omitted)
      ctrl.setCartQuantity(slow.id, 1);
      await ctrl.completeSale();

      final daysMap = ctrl.estimatedDaysOfStockByProduct();
      expect(daysMap[hit.id], 2);
      expect(daysMap.containsKey(slow.id), isFalse);
    },
  );

  test(
    'frozenCashSummary ranks in-stock slow movers by tied-up cost value and filters by 30-60+ idle days',
    () async {
      final now = DateTime(2026, 11, 24, 12, 0);
      final storage = InMemoryInventoryStorage();
      await storage.save(
        ShopDataSnapshot(
          products: [
            Product(
              id: 'p_40d',
              name: 'Люстра 40д',
              category: 'Свет',
              costPrice: 5000,
              sellPrice: 8000,
              stock: 10, // frozen = 50 000
              updatedAt: now.subtract(const Duration(days: 50)),
            ),
            Product(
              id: 'p_never_50d',
              name: 'Бра 50д (не продавался)',
              category: 'Свет',
              costPrice: 4000,
              sellPrice: 7000,
              stock: 5, // frozen = 20 000
              updatedAt: now.subtract(const Duration(days: 50)),
            ),
            Product(
              id: 'p_active_10d',
              name: 'Лампа ходовая',
              category: 'Свет',
              costPrice: 6000,
              sellPrice: 9000,
              stock: 10,
              updatedAt: now.subtract(const Duration(days: 60)),
            ),
            Product(
              id: 'p_75d',
              name: 'Старый неликвид 75д',
              category: 'Свет',
              costPrice: 3000,
              sellPrice: 5000,
              stock: 10, // frozen = 30 000
              updatedAt: now.subtract(const Duration(days: 80)),
            ),
            Product(
              id: 'p_zero',
              name: 'Пустой остаток',
              category: 'Свет',
              costPrice: 9000,
              sellPrice: 12000,
              stock: 0,
              updatedAt: now.subtract(const Duration(days: 45)),
            ),
          ],
          sales: [
            Sale(
              id: 's_40d',
              items: const [
                SaleItem(
                  productId: 'p_40d',
                  productName: 'Люстра 40д',
                  quantity: 1,
                  unitCost: 5000,
                  unitPrice: 8000,
                ),
              ],
              paymentMethod: PaymentMethod.cash,
              createdAt: now.subtract(const Duration(days: 40)),
            ),
            Sale(
              id: 's_10d',
              items: const [
                SaleItem(
                  productId: 'p_active_10d',
                  productName: 'Лампа ходовая',
                  quantity: 2,
                  unitCost: 6000,
                  unitPrice: 9000,
                ),
              ],
              paymentMethod: PaymentMethod.cash,
              createdAt: now.subtract(const Duration(days: 10)),
            ),
            Sale(
              id: 's_75d',
              items: const [
                SaleItem(
                  productId: 'p_75d',
                  productName: 'Старый неликвид 75д',
                  quantity: 1,
                  unitCost: 3000,
                  unitPrice: 5000,
                ),
              ],
              paymentMethod: PaymentMethod.cash,
              createdAt: now.subtract(const Duration(days: 75)),
            ),
          ],
          expenses: const [],
        ),
      );

      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      final range30To60 = ctrl.frozenCashSummary(
        minIdleDays: 30,
        maxIdleDays: 60,
        now: now,
      );
      expect(range30To60.totalCount, 2);
      expect(range30To60.totalFrozenValue, 70000);
      expect(
        range30To60.items.map((e) => e.product.id).toList(),
        ['p_40d', 'p_never_50d'],
      );
      expect(range30To60.items.first.daysWithoutSales, 40);
      expect(range30To60.items.first.hasEverSold, isTrue);
      expect(range30To60.items.last.hasEverSold, isFalse);

      final all30Plus = ctrl.frozenCashSummary(
        minIdleDays: 30,
        now: now,
      );
      expect(all30Plus.totalCount, 3);
      expect(all30Plus.totalFrozenValue, 100000);
      expect(
        all30Plus.items.map((e) => e.product.id).toList(),
        ['p_40d', 'p_75d', 'p_never_50d'],
      );
    },
  );

  test(
    'StockInMarginAlert flags red margin and computes +X% sell price raise when purchase cost increases',
    () {
      // Old cost 1000, old sell 1500 (margin 33.3%). New cost rises to 1200.
      final alert = StockInMarginAlert.evaluate(
        oldCost: 1000,
        newCost: 1200,
        oldSell: 1500,
        currentSell: 1500,
      );
      expect(alert.costIncreased, isTrue);
      expect(alert.newMarginPercent, closeTo(20.0, 0.01));
      expect(alert.isMarginRed, isTrue);
      expect(alert.suggestedSellPrice, 1800);
      expect(alert.raisePercent, 20);
      expect(alert.canRaiseSellPrice, isTrue);

      // After tapping raise button (currentSell = 1800), margin is restored and no longer red
      final afterRaise = StockInMarginAlert.evaluate(
        oldCost: 1000,
        newCost: 1200,
        oldSell: 1500,
        currentSell: 1800,
      );
      expect(afterRaise.costIncreased, isTrue);
      expect(afterRaise.newMarginPercent, closeTo(33.33, 0.1));
      expect(afterRaise.isMarginRed, isFalse);
      expect(afterRaise.canRaiseSellPrice, isFalse);

      // Selling at a loss (new cost 1600 > sell 1500) -> negative margin in red
      final lossAlert = StockInMarginAlert.evaluate(
        oldCost: 1000,
        newCost: 1600,
        oldSell: 1500,
        currentSell: 1500,
      );
      expect(lossAlert.isMarginRed, isTrue);
      expect(lossAlert.newMarginPercent, lessThan(0));
      expect(lossAlert.suggestedSellPrice, 2400);
      expect(lossAlert.raisePercent, 60);
    },
  );

  test(
    'auto-wholesale triggers at wholesaleMinQty, setWholesaleDisabledFor reverts line to retail, and allowCashierDiscounts blocks cashier discounts across restarts',
    () async {
      final dbFile = File('${tempDir.path}/no_discount_shop_data.json');
      final storage1 = JsonFileInventoryStorage(filePath: dbFile.path);
      final ctrl = ShopController(storage: storage1);
      await ctrl.initialize();
      await ctrl.exitCashierMode('');

      final p = await ctrl.addProduct(
        name: 'Плинтус 70мм',
        category: 'Плинтусы',
        costPrice: 200,
        sellPrice: 400,
        wholesalePrice: 300,
        wholesaleMinQty: 10,
        stock: 30,
      );

      // 9 units -> retail 400; 10 units -> auto wholesale 300
      ctrl.setCartQuantity(p.id, 9);
      expect(ctrl.cartLines.single.unitPrice, 400);
      expect(ctrl.cartLines.single.isAutoWholesaleApplied, isFalse);

      ctrl.setCartQuantity(p.id, 10);
      expect(ctrl.cartLines.single.unitPrice, 300);
      expect(ctrl.cartLines.single.isAutoWholesaleApplied, isTrue);

      // Opt-out ("Без скидки (розница)") reverts to 400; restoring brings back 300
      ctrl.setWholesaleDisabledFor(p.id, true);
      expect(ctrl.cartLines.single.unitPrice, 400);
      expect(ctrl.cartLines.single.isAutoWholesaleApplied, isFalse);
      ctrl.setWholesaleDisabledFor(p.id, false);
      expect(ctrl.cartLines.single.unitPrice, 300);

      // Disable cashier discounts
      await ctrl.setAllowCashierDiscounts(false);
      await ctrl.enterCashierMode();
      expect(ctrl.canGiveDiscounts, isFalse);

      // Cashier cannot lower line price below defaultUnitPrice
      ctrl.setCartItemPrice(p.id, 250);
      expect(ctrl.cartLines.single.unitPrice, 300);

      // Cashier receipt discount is forced to 0
      final sale = await ctrl.completeSale(discount: 500, discountReason: 'Тест');
      expect(sale, isNotNull);
      expect(sale!.discount, 0);
      expect(sale.total, 3000);

      // Setting persists across restart; owner mode still allows discounts
      final reloaded = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await reloaded.initialize();
      expect(reloaded.allowCashierDiscounts, isFalse);
      expect(reloaded.canGiveDiscounts, isFalse);

      await reloaded.exitCashierMode('');
      expect(reloaded.canGiveDiscounts, isTrue);
    },
  );

  test(
    'buildPurchaseOrderSuggestions includes fast-moving products running out within 7 days by sales velocity and builds direct WhatsApp URI',
    () async {
      final now = DateTime.now();
      final twoDaysAgo = now.subtract(const Duration(days: 2));
      final storage = InMemoryInventoryStorage();
      await storage.save(
        ShopDataSnapshot(
          products: [
            Product(
              id: 'p_fast',
              name: 'Хит продаж',
              category: 'Напитки',
              costPrice: 100,
              sellPrice: 200,
              stock: 15, // above lowStockThreshold (5), but 4/day pace => ~4 days left
              lowStockThreshold: 5,
              updatedAt: twoDaysAgo,
            ),
            Product(
              id: 'p_slow',
              name: 'Спокойный товар',
              category: 'Разное',
              costPrice: 100,
              sellPrice: 200,
              stock: 15, // above lowStockThreshold (5), 0 sales => omitted
              lowStockThreshold: 5,
              updatedAt: twoDaysAgo,
            ),
          ],
          sales: [
            Sale(
              id: 's_fast_1',
              items: const [
                SaleItem(
                  productId: 'p_fast',
                  productName: 'Хит продаж',
                  quantity: 12,
                  unitCost: 100,
                  unitPrice: 200,
                ),
              ],
              paymentMethod: PaymentMethod.cash,
              createdAt: twoDaysAgo,
            ),
          ],
          expenses: const [],
        ),
      );

      final ctrl = ShopController(storage: storage);
      await ctrl.initialize();

      // observedDays = 3 -> dailyPace = 12 / 3 = 4/day -> daysLeft = (15 / 4).round() = 4
      // targetCoverageDays = 14 -> velocityTarget = 56 -> suggestedQty = 56 - 15 = 41
      final suggestions = ctrl.buildPurchaseOrderSuggestions(now: now);
      expect(suggestions.map((s) => s.product.id).toList(), ['p_fast']);
      expect(suggestions.single.daysLeft, 4);
      expect(suggestions.single.suggestedQty, closeTo(41, 0.001));

      final orderText = ExportService.buildPurchaseOrderText(
        suggestions
            .map((s) => (product: s.product, quantity: s.suggestedQty))
            .toList(),
        AppStrings(AppLanguage.ru),
        supplierName: 'База Опт',
        shopName: 'Тастак',
        createdAt: DateTime(2026, 11, 24, 16, 0),
      );
      final uri = WhatsAppLauncher.buildWhatsAppUri(
        phone: '+7 (701) 555-00-11',
        message: orderText,
      );
      expect(uri, isNotNull);
      expect(uri!.host, 'wa.me');
      expect(uri.path, '/77015550011');
      expect(uri.queryParameters['text'], contains('Хит продаж — 41'));
    },
  );

  test(
    'supplier credit stock-in tracks remainingDebt, supports partial and full repayments, records expenses, and persists across restarts',
    () async {
      final dbFile = File('${tempDir.path}/supplier_debt_shop_data.json');
      final storage1 = JsonFileInventoryStorage(filePath: dbFile.path);
      final ctrl = ShopController(storage: storage1);
      await ctrl.initialize();

      final p = await ctrl.addProduct(
        name: 'Труба ППР 25',
        category: 'Сантехника',
        costPrice: 400,
        sellPrice: 650,
        stock: 0,
      );

      // 1. Receive 10 units @ 400 (total 4000) on credit with 1000 paid upfront
      await ctrl.receiveStock(
        supplierName: 'СантехОпт',
        items: [
          StockInItem(
            productId: p.id,
            productName: p.name,
            quantity: 10,
            unitCost: 400,
          ),
        ],
        recordAsExpense: true,
        isCredit: true,
        paidAmount: 1000,
      );

      expect(ctrl.totalSupplierDebt, 3000);
      expect(ctrl.unpaidStockIns.length, 1);
      expect(ctrl.stockIns.first.isCredit, isTrue);
      expect(ctrl.stockIns.first.effectivePaidAmount, 1000);
      expect(ctrl.stockIns.first.remainingDebt, 3000);
      expect(ctrl.stockIns.first.isPaid, isFalse);
      // Only the upfront 1000 was recorded as an expense
      expect(ctrl.expenses.length, 1);
      expect(ctrl.expenses.first.amount, 1000);

      // 2. Partial repayment of 1500
      await ctrl.recordSupplierPayment(ctrl.stockIns.first.id, 1500);
      expect(ctrl.totalSupplierDebt, 1500);
      expect(ctrl.stockIns.first.effectivePaidAmount, 2500);
      expect(ctrl.stockIns.first.isPartiallyPaid, isTrue);
      expect(ctrl.stockIns.first.paymentHistory.length, 2);
      expect(ctrl.expenses.length, 2);
      expect(ctrl.expenses.first.amount, 1500);

      // 3. Reload from storage -> supplier debt & payment history persist
      final reloaded = ShopController(
        storage: JsonFileInventoryStorage(filePath: dbFile.path),
      );
      await reloaded.initialize();
      expect(reloaded.totalSupplierDebt, 1500);
      expect(reloaded.stockIns.first.paymentHistory.length, 2);

      final dir = reloaded.buildSupplierDirectory();
      expect(dir.single.name, 'СантехОпт');
      expect(dir.single.totalDebt, 1500);

      // 4. Settle remaining debt
      await reloaded.markStockInPaid(reloaded.stockIns.first.id);
      expect(reloaded.totalSupplierDebt, 0);
      expect(reloaded.unpaidStockIns, isEmpty);
      expect(reloaded.stockIns.first.isPaid, isTrue);
      expect(reloaded.stockIns.first.remainingDebt, 0);
    },
  );
}

class _LazyStartupStorage extends InMemoryInventoryStorage {
  _LazyStartupStorage(this._full);

  final ShopDataSnapshot _full;

  @override
  Future<ShopDataSnapshot> load() async {
    final salesCutoff = DateTime.now().subtract(const Duration(days: 30));
    return ShopDataSnapshot(
      products: _full.products.where((p) => p.isActive).toList(),
      sales: _full.sales
          .where(
            (s) =>
                s.isActive &&
                (!s.isPaid || !s.createdAt.isBefore(salesCutoff)),
          )
          .toList(),
      expenses: _full.expenses.where((e) => !e.isTrashed).toList(),
      catalogSeeded: _full.catalogSeeded,
    );
  }

  @override
  Future<({List<Product> products, List<Sale> sales, List<Expense> expenses})>
      loadArchiveAndTrash() async => (
        products: _full.products.where((p) => !p.isActive).toList(),
        sales: _full.sales.where((s) => !s.isActive).toList(),
        expenses: _full.expenses.where((e) => e.isTrashed).toList(),
      );

  @override
  Future<List<Sale>> loadAllActiveSales() async =>
      _full.sales.where((s) => s.isActive).toList();
}

class _FailingPreRestoreStorage extends InMemoryInventoryStorage {
  @override
  Future<void> savePreRestoreBackup(ShopDataSnapshot snapshot) async {
    throw const FileSystemException('Disk full');
  }
}
