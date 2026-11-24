import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/sale.dart';
import 'package:flutter_application_1/services/inventory_storage.dart';
import 'package:flutter_application_1/state/shop_controller.dart';

void main() {
  test(
    'Cashier Mode prohibits deleting, trashing, or archiving receipts without Owner PIN, while allowing Return / Exchange with audit trail',
    () async {
      final controller = ShopController(storage: InMemoryInventoryStorage());
      await controller.initialize();
      await controller.exitCashierMode('');

      final product = await controller.addProduct(
        name: 'Профиль 60x27',
        category: 'Профили',
        costPrice: 400,
        sellPrice: 700,
        stock: 20,
      );

      controller.addToCart(product.id, quantity: 3);
      final sale = await controller.completeSale(
        paymentMethod: PaymentMethod.cash,
        customerName: 'Иван',
      );
      expect(sale, isNotNull);
      expect(controller.findProductById(product.id)!.stock, 17);

      // Switch to Cashier Mode without PIN set
      await controller.enterCashierMode();
      expect(controller.cashierMode, isTrue);

      // Without PIN, all deletion/archiving methods must be blocked
      expect(await controller.moveSaleToTrash(sale!.id), isFalse);
      expect(await controller.voidSale(sale.id), isFalse);
      expect(await controller.archiveSale(sale.id), isFalse);
      expect(await controller.deleteSalePermanently(sale.id), isFalse);
      expect(controller.sales.length, 1);
      expect(controller.trashedSales, isEmpty);
      expect(controller.archivedSales, isEmpty);
      expect(controller.findProductById(product.id)!.stock, 17);

      // Set Owner PIN and re-enter Cashier Mode
      await controller.exitCashierMode('');
      await controller.setOwnerPin('1234');
      await controller.enterCashierMode();

      // Wrong PIN or omitted PIN must still be blocked
      expect(
        await controller.moveSaleToTrash(sale.id, ownerPinAttempt: '0000'),
        isFalse,
      );
      expect(
        await controller.archiveSale(sale.id, ownerPinAttempt: '9999'),
        isFalse,
      );
      expect(
        await controller.deleteSalePermanently(sale.id, ownerPinAttempt: ''),
        isFalse,
      );
      expect(controller.sales.length, 1);

      // Return / Exchange MUST work in Cashier Mode and leave an audit trail
      await controller.processSaleReturnOrExchange(
        saleId: sale.id,
        returnQuantities: {product.id: 1},
        returnToStock: true,
        settlementMethod: PaymentMethod.cash,
        returnReason: 'Не подошёл размер',
      );

      final updatedSale = controller.sales.firstWhere((s) => s.id == sale.id);
      expect(updatedSale.hasReturn, isTrue);
      expect(updatedSale.refundNote, isNotEmpty);
      expect(updatedSale.returnReason, 'Не подошёл размер');
      expect(updatedSale.returnedMoneyTotal, 700);
      expect(updatedSale.total, 1400);
      expect(controller.findProductById(product.id)!.stock, 18);

      // Valid Owner PIN allows moving to trash
      expect(
        await controller.moveSaleToTrash(sale.id, ownerPinAttempt: '1234'),
        isTrue,
      );
      expect(controller.sales, isEmpty);
      expect(controller.trashedSales.length, 1);
      expect(controller.findProductById(product.id)!.stock, 20);

      // emptyTrash without Owner PIN in Cashier Mode must NOT purge trashed sales
      await controller.emptyTrash();
      expect(controller.trashedSales.length, 1);

      // emptyTrash with valid Owner PIN purges trashed sales
      await controller.emptyTrash(ownerPinAttempt: '1234');
      expect(controller.trashedSales, isEmpty);
    },
  );

  test(
    'Owner Mode allows archiving and trashing receipts without passing Owner PIN',
    () async {
      final controller = ShopController(storage: InMemoryInventoryStorage());
      await controller.initialize();
      await controller.exitCashierMode('');
      await controller.setOwnerPin('5678');

      final product = await controller.addProduct(
        name: 'Саморез',
        category: 'Крепёж',
        costPrice: 10,
        sellPrice: 25,
        stock: 50,
      );

      controller.addToCart(product.id, quantity: 2);
      final sale = await controller.completeSale(
        paymentMethod: PaymentMethod.kaspiQr,
      );
      expect(sale, isNotNull);

      expect(await controller.archiveSale(sale!.id), isTrue);
      expect(controller.archivedSales.length, 1);
      await controller.unarchiveSale(sale.id);
      expect(await controller.moveSaleToTrash(sale.id), isTrue);
      expect(controller.trashedSales.length, 1);
      expect(await controller.deleteSalePermanently(sale.id), isTrue);
      expect(controller.trashedSales, isEmpty);
    },
  );
}
