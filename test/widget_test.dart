import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/data/initial_catalog.dart';
import 'package:flutter_application_1/l10n/app_strings.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/models/expense.dart';
import 'package:flutter_application_1/models/sale.dart';
import 'package:flutter_application_1/models/stock_in.dart';
import 'package:flutter_application_1/services/export_service.dart';
import 'package:flutter_application_1/services/inventory_storage.dart';
import 'package:flutter_application_1/state/shop_controller.dart';

void main() {
  testWidgets(
    'verifies keyboard search layout, debtors summary & partial payments, WhatsApp/PDF receipts, expenses & stock-in net profit, and PIN/cashier mode dialogs',
    (WidgetTester tester) async {
      final controller = ShopController(storage: InMemoryInventoryStorage());
      await controller.addProduct(
        name: 'Espresso Beans',
        category: 'Beverages',
        sku: 'ESP-1',
        nomenclature: 'NOM-ESP-1',
        printName: 'Espresso Beans 1kg',
        packQty: '6',
        boxQty: '24',
        packBarcode: '4600000000011',
        boxBarcode: '4600000000028',
        unitWeight: '1.0',
        unit: 'шт',
        costPrice: 1500,
        sellPrice: 3000,
        stock: 10,
      );

      await tester.pumpWidget(ShopInventoryApp(controller: controller));
      await tester.pumpAndSettle();

      // 1. Search field with keyboard inset (no Bottom Overflow)
      await tester.enterText(find.byType(TextField).first, 'NOM-ESP-1');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Espresso Beans'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();

      final espresso = controller.products.first;

      // 2. Post-pay sales, partial payment history, and overdue debtor grouping
      controller.addToCart(espresso.id, quantity: 1);
      final sale1 = await controller.completeSale(
        paymentMethod: PaymentMethod.postPay,
        customerName: 'Aidos',
        paidAmount: 1000,
        dueDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(sale1, isNotNull);

      // 3. WhatsApp text & 80mm PDF receipt generation
      final receiptText = ExportService.buildSaleReceiptText(
        sale1!,
        controller.strings,
        AppCurrency.kzt,
        shopName: controller.shopName,
      );
      expect(receiptText, contains('Aidos'));
      expect(receiptText, contains('2 000'));

      final pdfBytes = await ExportService.buildSaleReceiptPdfBytes(
        sale1,
        controller.strings,
        AppCurrency.kzt,
        shopName: controller.shopName,
      );
      expect(ascii.decode(pdfBytes.take(5).toList()), '%PDF-');

      controller.addToCart(espresso.id, quantity: 1);
      final sale2 = await controller.completeSale(
        paymentMethod: PaymentMethod.postPay,
        customerName: 'Aidos',
      );
      expect(sale2, isNotNull);

      await controller.recordSalePayment(sale2!.id, 500);

      final debtors = controller.debtors;
      expect(debtors.length, 1);
      expect(debtors.first.customerName, 'Aidos');
      expect(debtors.first.sales.length, 2);
      expect(debtors.first.totalDebt, 4500);
      expect(debtors.first.hasOverdue, isTrue);

      await controller.markAllCustomerDebtsPaid('Aidos');
      expect(controller.debtors, isEmpty);

      // 4. Stock-in invoice & operating expenses -> net profit calculation
      await controller.receiveStock(
        supplierName: 'Coffee Wholesale',
        items: [
          StockInItem(
            productId: espresso.id,
            productName: espresso.name,
            quantity: 2,
            unitCost: 1500,
          ),
        ],
      );
      await controller.addExpense(
        title: 'Shop Rent',
        category: ExpenseCategory.rent,
        amount: 500,
      );
      expect(controller.stockIns.length, 1);
      expect(controller.totalExpensesFor(SalesDateFilter.today), 3500);

      // 5. Owner PIN & Cashier Mode transition without _dependents.isEmpty error
      await controller.setOwnerPin('1234');
      await controller.enterCashierMode();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.cashierMode, isTrue);

      final wrongUnlock = await controller.exitCashierMode('0000');
      expect(wrongUnlock, isFalse);
      final rightUnlock = await controller.exitCashierMode('1234');
      expect(rightUnlock, isTrue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.cashierMode, isFalse);
    },
  );

  test(
    'initial catalog includes nomenclature, barcodes, pack/box, weight, and unit metadata',
    () async {
      final catalog = buildInitialCatalog();
      expect(catalog.length, 3400);

      final withBarcode = catalog.where((p) => p.sku.isNotEmpty).toList();
      expect(withBarcode.length, 3250);

      final sample = catalog.firstWhere((p) => p.sku == '4690653225262');
      expect(sample.nomenclature, 'Д-П55 001 БЕЛ');
      expect(sample.printName, contains('Деконика'));
      expect(sample.boxQty, '20');
      expect(sample.boxBarcode, '4690653225279');
      expect(sample.unitWeight, '0.424');
      expect(sample.unit, 'шт');

      final controller = ShopController(storage: InMemoryInventoryStorage());
      await controller.initialize();
      expect(controller.findProductBySku('4690653225262')?.id, sample.id);
      expect(controller.findProductBySku('4690653225279')?.id, sample.id);
      expect(controller.findProductBySku('Д-П55 001 БЕЛ')?.id, sample.id);
    },
  );

  test(
    'incomingPriceAnalytics tracks price changes, weighted average cost, min/max, and margin impact',
    () async {
      final controller = ShopController(storage: InMemoryInventoryStorage());
      await controller.addProduct(
        name: 'Plinth 55mm',
        category: 'Плинтус',
        costPrice: 1000,
        sellPrice: 2000,
        stock: 5,
      );
      final product = controller.products.first;

      await controller.receiveStock(
        supplierName: 'Supplier A',
        items: [
          StockInItem(
            productId: product.id,
            productName: product.name,
            quantity: 10,
            unitCost: 1000,
          ),
        ],
      );
      await controller.receiveStock(
        supplierName: 'Supplier B',
        items: [
          StockInItem(
            productId: product.id,
            productName: product.name,
            quantity: 10,
            unitCost: 1200,
          ),
        ],
      );

      final analysis = controller.incomingPriceAnalytics();
      expect(analysis.length, 1);
      final item = analysis.first;
      expect(item.deliveriesCount, 2);
      expect(item.totalUnits, 20);
      expect(item.totalSpend, 22000);
      expect(item.latestCost, 1200);
      expect(item.previousCost, 1000);
      expect(item.avgCost, 1100);
      expect(item.minCost, 1000);
      expect(item.maxCost, 1200);
      expect(item.isPriceUp, isTrue);
      expect(item.priceDelta, 200);
      expect(item.priceDeltaPercent, closeTo(20.0, 0.01));
      expect(item.marginPercentAtLatest, closeTo(40.0, 0.01));
    },
  );

  test(
    'supports selective, group, and delete-all goods to trash with restore',
    () async {
      final controller = ShopController(storage: InMemoryInventoryStorage());
      await controller.addProduct(
        name: 'Item A1',
        category: 'Group A',
        costPrice: 100,
        sellPrice: 200,
        stock: 5,
      );
      await controller.addProduct(
        name: 'Item A2',
        category: 'Group A',
        costPrice: 100,
        sellPrice: 200,
        stock: 5,
      );
      await controller.addProduct(
        name: 'Item B1',
        category: 'Group B',
        costPrice: 100,
        sellPrice: 200,
        stock: 5,
      );
      await controller.addProduct(
        name: 'Item C1',
        category: 'Group C',
        costPrice: 100,
        sellPrice: 200,
        stock: 5,
      );

      expect(controller.products.length, 4);

      // 1. Selective move to trash
      final b1 = controller.products.firstWhere((p) => p.name == 'Item B1');
      final movedSelective = await controller.moveProductsToTrash([b1.id]);
      expect(movedSelective, 1);
      expect(controller.products.length, 3);
      expect(controller.trashedProducts.length, 1);

      // 2. Group move to trash
      final movedGroup = await controller.moveCategoryToTrash('Group A');
      expect(movedGroup, 2);
      expect(controller.products.length, 1);
      expect(controller.trashedProducts.length, 3);

      // 3. Delete all remaining goods to trash
      final movedAll = await controller.moveAllProductsToTrash();
      expect(movedAll, 1);
      expect(controller.products, isEmpty);
      expect(controller.trashedProducts.length, 4);

      // 4. Restore all from trash
      final restored = await controller.restoreAllProductsFromTrash();
      expect(restored, 4);
      expect(controller.products.length, 4);
      expect(controller.trashedProducts, isEmpty);

      // 5. Archive selective, group, and all goods + restore all from archive
      expect(await controller.archiveProducts([b1.id]), 1);
      expect(controller.archivedProducts.length, 1);
      expect(await controller.archiveCategory('Group A'), 2);
      expect(controller.archivedProducts.length, 3);
      expect(await controller.archiveAllProducts(), 1);
      expect(controller.products, isEmpty);
      expect(controller.archivedProducts.length, 4);
      expect(await controller.restoreAllProductsFromArchive(), 4);
      expect(controller.products.length, 4);
      expect(controller.archivedProducts, isEmpty);

      // 6. Move individual and whole-group products to another category
      expect(
        await controller.moveProductsToCategory([b1.id], 'Group A'),
        1,
      );
      expect(
        controller.products.where((p) => p.category == 'Group A').length,
        3,
      );
      expect(
        await controller.moveCategoryToCategory('Group A', 'Group C'),
        3,
      );
      expect(
        controller.products.where((p) => p.category == 'Group C').length,
        4,
      );
      expect(controller.categories, ['Group C']);
    },
  );

  test(
    'preserves products, archive, trash, and permanent deletions across restarts/updates',
    () async {
      final storage = InMemoryInventoryStorage();
      final controller1 = ShopController(storage: storage);
      await controller1.initialize();
      final initialCount = controller1.products.length;
      expect(initialCount, 3400);

      final first = controller1.products[0];
      final second = controller1.products[1];
      final third = controller1.products[2];

      await controller1.archiveProduct(first.id);
      await controller1.moveProductToTrash(second.id);
      await controller1.moveProductToTrash(third.id);
      await controller1.deleteProductPermanently(third.id);

      // Simulate app restart / update with a fresh controller reading the same storage
      final controller2 = ShopController(storage: storage);
      await controller2.initialize();

      expect(controller2.products.length, initialCount - 3);
      expect(controller2.archivedProducts.map((p) => p.id), [first.id]);
      expect(controller2.trashedProducts.map((p) => p.id), [second.id]);
      expect(controller2.findProductById(third.id), isNull);

      // Move selected trashed product to archive
      await controller2.moveTrashedProductsToArchive([second.id]);
      expect(controller2.trashedProducts, isEmpty);
      expect(controller2.archivedProducts.map((p) => p.id), [first.id, second.id]);

      // Create standalone custom group and persist across restarts
      await controller2.createCategory('Распродажа');
      expect(controller2.categories, contains('Распродажа'));
      final controller3 = ShopController(storage: storage);
      await controller3.initialize();
      expect(controller3.categories, contains('Распродажа'));

      // Stock-in draft persists across restarts and clears after receiveStock
      await controller3.saveStockInDraft(
        StockInDraft(
          supplierName: 'ZT Wholesale',
          quantities: {first.id: 12},
          unitCosts: {first.id: 950},
        ),
      );
      final controller4 = ShopController(storage: storage);
      await controller4.initialize();
      expect(controller4.hasStockInDraft, isTrue);
      expect(controller4.stockInDraft?.supplierName, 'ZT Wholesale');
      expect(controller4.stockInDraft?.quantities[first.id], 12);
      expect(controller4.stockInDraft?.unitCosts[first.id], 950);

      await controller4.receiveStock(
        supplierName: 'ZT Wholesale',
        items: [
          StockInItem(
            productId: first.id,
            productName: first.name,
            quantity: 12,
            unitCost: 950,
            newSellPrice: 1900,
          ),
        ],
      );
      expect(controller4.hasStockInDraft, isFalse);
      expect(controller4.findProductById(first.id)?.sellPrice, 1900);

      // Hold a sale, serve another customer, then resume the held sale
      final prodA = controller4.products[0];
      final prodB = controller4.products[1];
      controller4.addToCart(prodA.id, quantity: 2);
      final held = await controller4.holdCurrentCart(label: 'Клиент 1');
      expect(held, isNotNull);
      expect(controller4.cartItemCount, 0);
      expect(controller4.heldSales.length, 1);

      controller4.addToCart(prodB.id, quantity: 1);
      expect(controller4.cartItemCount, 1);

      await controller4.resumeHeldSale(held!.id);
      expect(controller4.cartQuantityFor(prodA.id), 2);
      // Previous active cart (prodB) was automatically parked instead of lost
      expect(controller4.heldSales.length, 1);
    },
  );
}
