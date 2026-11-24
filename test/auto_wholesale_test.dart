import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/product.dart';
import 'package:flutter_application_1/services/inventory_storage.dart';
import 'package:flutter_application_1/state/shop_controller.dart';

class _InMemoryStorage extends InMemoryInventoryStorage {}

void main() {
  group('Auto wholesale from N units', () {
    test('Product serializes and deserializes wholesaleMinQty', () {
      final product = Product(
        id: 'p1',
        name: 'Coffee',
        category: 'Drinks',
        costPrice: 500,
        sellPrice: 1000,
        wholesalePrice: 800,
        wholesaleMinQty: 5,
        stock: 20,
        updatedAt: DateTime(2026, 1, 1),
      );

      final json = product.toJson();
      expect(json['wholesaleMinQty'], 5);
      final restored = Product.fromJson(json);
      expect(restored.wholesaleMinQty, 5);
      expect(restored.hasAutoWholesale, isTrue);
      expect(restored.isAutoWholesaleForQty(4), isFalse);
      expect(restored.isAutoWholesaleForQty(5), isTrue);
    });

    test('CartLine automatically switches to wholesalePrice at >= N and reverts below N', () async {
      final controller = ShopController(storage: _InMemoryStorage());
      await controller.initialize();

      final product = await controller.addProduct(
        name: 'Плинтус 70мм',
        category: 'Плинтусы',
        costPrice: 200,
        sellPrice: 350,
        wholesalePrice: 280,
        wholesaleMinQty: 5,
        stock: 30,
      );

      controller.setCartQuantity(product.id, 4);
      var line = controller.cartLines.single;
      expect(line.unitPrice, 350);
      expect(line.isWholesalePriceApplied, isFalse);
      expect(line.isAutoWholesaleApplied, isFalse);
      expect(controller.cartSubtotal, 1400);

      controller.setCartQuantity(product.id, 5);
      line = controller.cartLines.single;
      expect(line.unitPrice, 280);
      expect(line.isWholesalePriceApplied, isTrue);
      expect(line.isAutoWholesaleApplied, isTrue);
      expect(controller.cartSubtotal, 1400);

      controller.setCartQuantity(product.id, 6);
      line = controller.cartLines.single;
      expect(line.unitPrice, 280);
      expect(controller.cartSubtotal, 1680);

      // Dropping below threshold reverts to retail price
      controller.setCartQuantity(product.id, 3);
      line = controller.cartLines.single;
      expect(line.unitPrice, 350);
      expect(line.isWholesalePriceApplied, isFalse);
      expect(controller.cartSubtotal, 1050);
    });

    test('completeSale records discounted wholesale unitPrice when qty >= wholesaleMinQty', () async {
      final controller = ShopController(storage: _InMemoryStorage());
      await controller.initialize();

      final product = await controller.addProduct(
        name: 'Угол 70мм',
        category: 'Плинтусы',
        costPrice: 150,
        sellPrice: 300,
        wholesalePrice: 240,
        wholesaleMinQty: 5,
        stock: 20,
      );

      controller.setCartQuantity(product.id, 5);
      final sale = await controller.completeSale();
      expect(sale, isNotNull);
      expect(sale!.items.single.unitPrice, 240);
      expect(sale.total, 1200);
    });

    test('customUnitPrice overrides auto-wholesale and wholesaleCartMode works with wholesaleMinQty == 0', () async {
      final controller = ShopController(storage: _InMemoryStorage());
      await controller.initialize();

      final autoProd = await controller.addProduct(
        name: 'AutoItem',
        category: 'General',
        costPrice: 100,
        sellPrice: 200,
        wholesalePrice: 160,
        wholesaleMinQty: 3,
        stock: 10,
      );
      final manualProd = await controller.addProduct(
        name: 'ManualItem',
        category: 'General',
        costPrice: 100,
        sellPrice: 250,
        wholesalePrice: 210,
        wholesaleMinQty: 0,
        stock: 10,
      );

      controller.setCartQuantity(autoProd.id, 3);
      controller.setCartQuantity(manualProd.id, 1);

      expect(controller.cartLines[0].unitPrice, 160);
      expect(controller.cartLines[1].unitPrice, 250);

      // Custom price overrides auto wholesale
      controller.setCartItemPrice(autoProd.id, 175);
      expect(controller.cartLines[0].unitPrice, 175);
      expect(controller.cartLines[0].hasCustomPrice, isTrue);

      // Resetting to defaultPrice (160) clears custom override
      controller.setCartItemPrice(autoProd.id, 160);
      expect(controller.cartLines[0].hasCustomPrice, isFalse);

      // Global wholesale mode applies to manualProd too
      controller.setWholesaleCartMode(true);
      expect(controller.cartLines[1].unitPrice, 210);
    });
  });
}
