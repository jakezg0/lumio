import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import '../data/initial_catalog.dart';
import '../l10n/app_strings.dart';
import '../models/customer.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/stock_in.dart';
import '../services/inventory_storage.dart';

enum SalesDateFilter {
  today,
  last7Days,
  all,
}

class CartLine {
  const CartLine({
    required this.product,
    required this.quantity,
    this.customUnitPrice,
  });

  final Product product;
  final int quantity;
  final double? customUnitPrice;

  double get unitPrice => customUnitPrice ?? product.sellPrice;
  bool get hasCustomPrice =>
      customUnitPrice != null &&
      (customUnitPrice! - product.sellPrice).abs() > 0.009;
  double get lineTotal => unitPrice * quantity;
  double get lineCost => product.costPrice * quantity;
  double get lineProfit => lineTotal - lineCost;
}

class DebtorSummary {
  const DebtorSummary({
    required this.customerName,
    required this.sales,
    required this.totalDebt,
    this.earliestDueDate,
    required this.hasOverdue,
  });

  final String customerName;
  final List<Sale> sales;
  final double totalDebt;
  final DateTime? earliestDueDate;
  final bool hasOverdue;
}

class TopProductStat {
  const TopProductStat({
    required this.productId,
    required this.productName,
    required this.unitsSold,
    required this.revenue,
    required this.profit,
  });

  final String productId;
  final String productName;
  final int unitsSold;
  final double revenue;
  final double profit;
}

class CustomerStats {
  const CustomerStats({
    required this.ordersCount,
    required this.totalSpent,
    required this.unpaidDebt,
  });

  final int ordersCount;
  final double totalSpent;
  final double unpaidDebt;
}

class IncomingPriceEntry {
  const IncomingPriceEntry({
    required this.createdAt,
    required this.supplierName,
    required this.quantity,
    required this.unitCost,
  });

  final DateTime createdAt;
  final String supplierName;
  final int quantity;
  final double unitCost;
}

class IncomingPriceAnalysis {
  const IncomingPriceAnalysis({
    required this.productId,
    required this.productName,
    required this.deliveriesCount,
    required this.totalUnits,
    required this.totalSpend,
    required this.latestCost,
    this.previousCost,
    required this.avgCost,
    required this.minCost,
    required this.maxCost,
    this.currentSellPrice,
    required this.entries,
  });

  final String productId;
  final String productName;
  final int deliveriesCount;
  final int totalUnits;
  final double totalSpend;
  final double latestCost;
  final double? previousCost;
  final double avgCost;
  final double minCost;
  final double maxCost;
  final double? currentSellPrice;
  final List<IncomingPriceEntry> entries;

  double get priceDelta =>
      previousCost == null ? 0.0 : latestCost - previousCost!;

  double get priceDeltaPercent =>
      (previousCost != null && previousCost! > 0)
          ? (priceDelta / previousCost!) * 100
          : 0.0;

  bool get isPriceUp => priceDelta > 0.009;
  bool get isPriceDown => priceDelta < -0.009;

  double? get marginPercentAtLatest {
    final sell = currentSellPrice;
    if (sell == null || sell <= 0) return null;
    return ((sell - latestCost) / sell) * 100;
  }
}

class ShopController extends ChangeNotifier {
  ShopController({InventoryStorage? storage})
      : _storage = storage ?? JsonFileInventoryStorage();

  final InventoryStorage _storage;

  final List<Product> _products = [];
  final List<Sale> _sales = [];
  final List<Expense> _expenses = [];
  final List<Customer> _customers = [];
  final List<StockInRecord> _stockIns = [];
  final Map<String, int> _cart = {};
  final Map<String, double> _cartCustomPrices = {};

  AppLanguage _language = AppLanguage.en;
  bool _followSystemLanguage = true;
  AppCurrency _currency = AppCurrency.kzt;
  String _shopName = 'Lumio';
  String _shopAddress = '';
  String _shopPhone = '';
  String _receiptFooter = '';
  String _ownerPin = '';
  bool _cashierMode = false;
  bool _catalogSeeded = false;
  final List<String> _customCategories = [];
  StockInDraft? _stockInDraft;
  StocktakeDraft? _stocktakeDraft;
  final List<HeldSale> _heldSales = [];
  bool _isLoaded = false;
  int _idCounter = 0;

  bool get isLoaded => _isLoaded;
  AppLanguage get language => _language;
  bool get followSystemLanguage => _followSystemLanguage;
  AppCurrency get currency => _currency;
  AppStrings get strings => AppStrings(_language);
  String get shopName => _shopName;
  String get shopAddress => _shopAddress;
  String get shopPhone => _shopPhone;
  String get receiptFooter => _receiptFooter;
  String get ownerPin => _ownerPin;
  bool get hasOwnerPin => _ownerPin.isNotEmpty;
  bool get cashierMode => _cashierMode;

  List<Product> get products =>
      _products.where((p) => p.isActive).toList(growable: false);
  List<Product> get archivedProducts =>
      _products.where((p) => p.isArchived).toList(growable: false);
  List<Product> get trashedProducts =>
      _products.where((p) => p.isTrashed).toList(growable: false);

  List<Sale> get sales =>
      _sales.where((s) => s.isActive).toList(growable: false);
  List<Sale> get archivedSales =>
      _sales.where((s) => s.isArchived).toList(growable: false);
  List<Sale> get trashedSales =>
      _sales.where((s) => s.isTrashed).toList(growable: false);

  List<Expense> get expenses =>
      _expenses.where((e) => e.isActive).toList(growable: false);
  List<Expense> get trashedExpenses =>
      _expenses.where((e) => e.isTrashed).toList(growable: false);

  List<Customer> get customers => List.unmodifiable(_customers);
  List<String> get recentCustomerNames {
    final seen = <String>{};
    final result = <String>[];
    for (final c in _customers) {
      final name = c.name.trim();
      if (name.isNotEmpty && seen.add(name.toLowerCase())) {
        result.add(name);
      }
    }
    for (final s in sales) {
      final name = s.customerName.trim();
      if (name.isNotEmpty &&
          name.toLowerCase() != 'unknown' &&
          seen.add(name.toLowerCase())) {
        result.add(name);
        if (result.length >= 15) break;
      }
    }
    return result;
  }
  List<StockInRecord> get stockIns => List.unmodifiable(_stockIns);
  List<String> get recentSuppliers {
    final seen = <String>{};
    final result = <String>[];
    for (final inv in _stockIns) {
      final s = inv.supplierName.trim();
      if (s.isNotEmpty && seen.add(s.toLowerCase())) {
        result.add(s);
        if (result.length >= 15) break;
      }
    }
    return result;
  }
  StockInDraft? get stockInDraft => _stockInDraft;
  bool get hasStockInDraft =>
      _stockInDraft != null && _stockInDraft!.hasContent;
  StocktakeDraft? get stocktakeDraft => _stocktakeDraft;
  bool get hasStocktakeDraft =>
      _stocktakeDraft != null && _stocktakeDraft!.hasContent;
  List<HeldSale> get heldSales => List.unmodifiable(_heldSales);

  int get archiveCount => archivedProducts.length + archivedSales.length;
  int get trashCount =>
      trashedProducts.length + trashedSales.length + trashedExpenses.length;

  String _nextId(String prefix) {
    _idCounter += 1;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  Future<void> initialize() async {
    final snapshot = await _storage.load();
    _applySnapshot(snapshot);
    final isFreshInstall = !_catalogSeeded &&
        _products.isEmpty &&
        _sales.isEmpty &&
        _expenses.isEmpty &&
        _customers.isEmpty &&
        _stockIns.isEmpty;
    if (isFreshInstall) {
      _products.addAll(buildInitialCatalog());
      _catalogSeeded = true;
      await _persist();
    } else if (!_catalogSeeded) {
      _catalogSeeded = true;
      await _persist();
    }
    _isLoaded = true;
    notifyListeners();
  }

  void _applySnapshot(ShopDataSnapshot snapshot) {
    _products
      ..clear()
      ..addAll(snapshot.products);
    _sales
      ..clear()
      ..addAll(snapshot.sales);
    _sales.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _expenses
      ..clear()
      ..addAll(snapshot.expenses);
    _expenses.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _customers
      ..clear()
      ..addAll(snapshot.customers);
    _customers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _stockIns
      ..clear()
      ..addAll(snapshot.stockIns);
    _stockIns.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final rawLang = snapshot.languageCode.trim().toLowerCase();
    if (rawLang.isEmpty || rawLang == 'auto') {
      _followSystemLanguage = true;
      _language = AppLanguage.fromSystemLocales(
        PlatformDispatcher.instance.locales,
      );
    } else {
      _followSystemLanguage = false;
      _language = AppLanguage.fromCode(rawLang);
    }
    _currency = AppCurrency.fromCode(snapshot.currencyCode);
    _shopName = snapshot.shopName;
    _shopAddress = snapshot.shopAddress;
    _shopPhone = snapshot.shopPhone;
    _receiptFooter = snapshot.receiptFooter;
    _ownerPin = snapshot.ownerPin;
    _cashierMode = snapshot.cashierMode;
    _catalogSeeded = snapshot.catalogSeeded ||
        _products.isNotEmpty ||
        _sales.isNotEmpty ||
        _expenses.isNotEmpty ||
        _customers.isNotEmpty ||
        _stockIns.isNotEmpty;
    _customCategories
      ..clear()
      ..addAll(
        snapshot.customCategories
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty),
      );
    _stockInDraft = snapshot.stockInDraft;
    _stocktakeDraft = snapshot.stocktakeDraft;
    _heldSales
      ..clear()
      ..addAll(snapshot.heldSales);
    _heldSales.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  ShopDataSnapshot createBackupSnapshot() {
    return ShopDataSnapshot(
      products: List.unmodifiable(_products),
      sales: List.unmodifiable(_sales),
      expenses: List.unmodifiable(_expenses),
      customers: List.unmodifiable(_customers),
      stockIns: List.unmodifiable(_stockIns),
      languageCode: _followSystemLanguage ? 'auto' : _language.code,
      currencyCode: _currency.code,
      shopName: _shopName,
      shopAddress: _shopAddress,
      shopPhone: _shopPhone,
      receiptFooter: _receiptFooter,
      ownerPin: _ownerPin,
      cashierMode: _cashierMode,
      catalogSeeded: _catalogSeeded,
      customCategories: List.unmodifiable(_customCategories),
      stockInDraft: _stockInDraft,
      stocktakeDraft: _stocktakeDraft,
      heldSales: List.unmodifiable(_heldSales),
    );
  }

  Future<HeldSale?> holdCurrentCart({String label = ''}) async {
    if (_cart.isEmpty) return null;
    final held = HeldSale(
      id: _nextId('hld'),
      label: label.trim(),
      quantities: Map<String, int>.from(_cart),
      createdAt: DateTime.now(),
    );
    _heldSales.insert(0, held);
    _cart.clear();
    _cartCustomPrices.clear();
    notifyListeners();
    await _persist();
    return held;
  }

  Future<void> resumeHeldSale(String heldId) async {
    final index = _heldSales.indexWhere((h) => h.id == heldId);
    if (index == -1) return;
    final held = _heldSales.removeAt(index);
    if (_cart.isNotEmpty) {
      _heldSales.insert(
        0,
        HeldSale(
          id: _nextId('hld'),
          label: '',
          quantities: Map<String, int>.from(_cart),
          createdAt: DateTime.now(),
        ),
      );
    }
    _cart.clear();
    _cartCustomPrices.clear();
    for (final entry in held.quantities.entries) {
      final product = findProductById(entry.key);
      if (product == null || !product.isActive || product.stock <= 0) continue;
      final qty = entry.value > product.stock ? product.stock : entry.value;
      if (qty > 0) {
        _cart[product.id] = qty;
      }
    }
    notifyListeners();
    await _persist();
  }

  Future<void> deleteHeldSale(String heldId) async {
    final before = _heldSales.length;
    _heldSales.removeWhere((h) => h.id == heldId);
    if (_heldSales.length != before) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> saveStockInDraft(StockInDraft? draft) async {
    final next = (draft != null && draft.hasContent) ? draft : null;
    final hadDraft = hasStockInDraft;
    _stockInDraft = next;
    if (hadDraft != hasStockInDraft || next != null) {
      notifyListeners();
    }
    await _persist();
  }

  Future<void> clearStockInDraft() async {
    if (_stockInDraft == null) return;
    _stockInDraft = null;
    notifyListeners();
    await _persist();
  }

  Future<int> addProductToStockInDraft(
    Product product, {
    int delta = 1,
  }) async {
    final existing = _stockInDraft;
    final quantities = Map<String, int>.from(existing?.quantities ?? const {});
    final unitCosts = Map<String, double>.from(existing?.unitCosts ?? const {});
    final sellPrices = Map<String, double>.from(existing?.sellPrices ?? const {});
    final nextQty = ((quantities[product.id] ?? 0) + delta).clamp(0, 999999);
    if (nextQty > 0) {
      quantities[product.id] = nextQty;
      unitCosts.putIfAbsent(product.id, () => product.costPrice);
      sellPrices.putIfAbsent(product.id, () => product.sellPrice);
    } else {
      quantities.remove(product.id);
    }
    await saveStockInDraft(
      StockInDraft(
        supplierName: existing?.supplierName ?? '',
        recordAsExpense: existing?.recordAsExpense ?? true,
        quantities: quantities,
        unitCosts: unitCosts,
        sellPrices: sellPrices,
      ),
    );
    return nextQty;
  }

  Future<void> saveStocktakeDraft(StocktakeDraft? draft) async {
    final next = (draft != null && draft.hasContent) ? draft : null;
    final hadDraft = hasStocktakeDraft;
    _stocktakeDraft = next;
    if (hadDraft != hasStocktakeDraft || next != null) {
      notifyListeners();
    }
    await _persist();
  }

  Future<void> clearStocktakeDraft() async {
    if (_stocktakeDraft == null) return;
    _stocktakeDraft = null;
    notifyListeners();
    await _persist();
  }

  Future<void> restoreFromSnapshot(ShopDataSnapshot snapshot) async {
    _applySnapshot(snapshot);
    _cart.clear();
    _cartCustomPrices.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    await _storage.save(createBackupSnapshot());
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (!_followSystemLanguage && _language == language) return;
    _followSystemLanguage = false;
    _language = language;
    notifyListeners();
    await _persist();
  }

  Future<void> setFollowSystemLanguage() async {
    final resolved = AppLanguage.fromSystemLocales(
      PlatformDispatcher.instance.locales,
    );
    if (_followSystemLanguage && _language == resolved) return;
    _followSystemLanguage = true;
    _language = resolved;
    notifyListeners();
    await _persist();
  }

  void syncWithSystemLocales(List<Locale> locales) {
    if (!_followSystemLanguage) return;
    final resolved = AppLanguage.fromSystemLocales(locales);
    if (resolved != _language) {
      _language = resolved;
      notifyListeners();
    }
  }

  Future<void> setCurrency(AppCurrency currency) async {
    if (_currency == currency) return;
    _currency = currency;
    notifyListeners();
    await _persist();
  }

  Future<void> updateShopProfile({
    required String shopName,
    required String shopAddress,
    required String shopPhone,
    required String receiptFooter,
  }) async {
    _shopName = shopName.trim().isEmpty ? 'Lumio' : shopName.trim();
    _shopAddress = shopAddress.trim();
    _shopPhone = shopPhone.trim();
    _receiptFooter = receiptFooter.trim();
    notifyListeners();
    await _persist();
  }

  Future<void> setOwnerPin(String pin) async {
    _ownerPin = pin.trim();
    notifyListeners();
    await _persist();
  }

  Future<void> enterCashierMode() async {
    if (_cashierMode) return;
    _cashierMode = true;
    notifyListeners();
    await _persist();
  }

  Future<bool> exitCashierMode(String pinAttempt) async {
    if (_ownerPin.isNotEmpty && pinAttempt.trim() != _ownerPin) {
      return false;
    }
    _cashierMode = false;
    notifyListeners();
    await _persist();
    return true;
  }

  List<String> get categories {
    final set = <String>{..._customCategories};
    for (final product in products) {
      final category = product.category.trim();
      if (category.isNotEmpty) {
        set.add(category);
      }
    }
    final sorted = set.toList()..sort();
    return sorted;
  }

  Future<String?> createCategory(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    final exists = categories.any(
      (c) => c.toLowerCase() == clean.toLowerCase(),
    );
    if (!exists && !_customCategories.contains(clean)) {
      _customCategories.add(clean);
      notifyListeners();
      await _persist();
    }
    return clean;
  }

  Future<void> deleteEmptyCategory(String name) async {
    final clean = name.trim();
    final hasProducts = products.any((p) => p.category == clean);
    if (hasProducts) return;
    if (_customCategories.remove(clean)) {
      notifyListeners();
      await _persist();
    }
  }

  int get totalStockUnits =>
      products.fold(0, (sum, product) => sum + product.stock);

  double get totalInventoryCostValue =>
      products.fold(0.0, (sum, product) => sum + product.inventoryValue);

  double get totalPotentialRevenue =>
      products.fold(0.0, (sum, product) => sum + product.potentialRevenue);

  List<Product> get lowStockProducts => products
      .where((product) => product.isLowStock || product.isOutOfStock)
      .toList();

  int get lowStockCount => lowStockProducts.length;

  List<Sale> get unpaidSales =>
      sales.where((sale) => !sale.isPaid).toList();

  double get totalUnpaidDebt =>
      unpaidSales.fold(0.0, (sum, sale) => sum + sale.remainingDebt);

  List<DebtorSummary> get debtors {
    final grouped = <String, List<Sale>>{};
    for (final sale in unpaidSales) {
      final name = sale.customerName.trim().isEmpty
          ? 'Unknown'
          : sale.customerName.trim();
      grouped.putIfAbsent(name, () => []).add(sale);
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final result = <DebtorSummary>[];

    for (final entry in grouped.entries) {
      final list = entry.value;
      final debt = list.fold(0.0, (sum, s) => sum + s.remainingDebt);
      DateTime? earliest;
      var overdue = false;
      for (final s in list) {
        final due = s.dueDate;
        if (due != null) {
          if (earliest == null || due.isBefore(earliest)) {
            earliest = due;
          }
          if (due.isBefore(todayStart)) {
            overdue = true;
          }
        }
      }
      result.add(
        DebtorSummary(
          customerName: entry.key,
          sales: list,
          totalDebt: debt,
          earliestDueDate: earliest,
          hasOverdue: overdue,
        ),
      );
    }

    result.sort((a, b) => b.totalDebt.compareTo(a.totalDebt));
    return result;
  }

  Future<void> markAllCustomerDebtsPaid(String customerName) async {
    final target = customerName.trim();
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _sales.length; i++) {
      final s = _sales[i];
      if (!s.isActive || s.isPaid) continue;
      final name = s.customerName.trim().isEmpty
          ? 'Unknown'
          : s.customerName.trim();
      if (name == target) {
        final history = List<DebtPayment>.from(s.paymentHistory);
        if (s.remainingDebt > 0) {
          history.add(DebtPayment(amount: s.remainingDebt, paidAt: now));
        }
        _sales[i] = s.copyWith(
          paidAmount: s.total,
          paidAt: now,
          paymentHistory: history,
        );
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> addCustomer({
    required String name,
    String phone = '',
    String note = '',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final customer = Customer(
      id: _nextId('cus'),
      name: cleanName,
      phone: phone.trim(),
      note: note.trim(),
      createdAt: DateTime.now(),
    );
    _customers.add(customer);
    _customers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    await _persist();
  }

  Future<void> updateCustomer({
    required String customerId,
    required String name,
    String phone = '',
    String note = '',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final index = _customers.indexWhere((c) => c.id == customerId);
    if (index == -1) return;
    _customers[index] = _customers[index].copyWith(
      name: cleanName,
      phone: phone.trim(),
      note: note.trim(),
    );
    _customers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    await _persist();
  }

  Future<void> deleteCustomer(String customerId) async {
    _customers.removeWhere((c) => c.id == customerId);
    notifyListeners();
    await _persist();
  }

  CustomerStats statsForCustomer(String customerName) {
    final target = customerName.trim().toLowerCase();
    var orders = 0;
    var spent = 0.0;
    var debt = 0.0;
    for (final s in sales) {
      if (s.customerName.trim().toLowerCase() == target) {
        orders += 1;
        spent += s.total;
        debt += s.remainingDebt;
      }
    }
    return CustomerStats(
      ordersCount: orders,
      totalSpent: spent,
      unpaidDebt: debt,
    );
  }

  List<Sale> get todaySales {
    final now = DateTime.now();
    return sales.where((sale) {
      return sale.createdAt.year == now.year &&
          sale.createdAt.month == now.month &&
          sale.createdAt.day == now.day;
    }).toList();
  }

  double get todayRevenue =>
      todaySales.fold(0.0, (sum, sale) => sum + sale.total);

  double get todayProfit =>
      todaySales.fold(0.0, (sum, sale) => sum + sale.profit);

  List<Sale> filteredSales(
    SalesDateFilter filter, {
    bool unpaidOnly = false,
    bool returnsOnly = false,
  }) {
    final now = DateTime.now();
    Iterable<Sale> result;
    switch (filter) {
      case SalesDateFilter.today:
        result = todaySales;
      case SalesDateFilter.last7Days:
        final cutoff = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
        result = sales.where((sale) => !sale.createdAt.isBefore(cutoff));
      case SalesDateFilter.all:
        result = sales;
    }
    if (unpaidOnly) {
      result = result.where((sale) => !sale.isPaid);
    }
    if (returnsOnly) {
      result = result.where((sale) => sale.hasReturn);
    }
    return result.toList();
  }

  List<({String receiptCode, DefectWriteOffItem item})> defectWriteOffs(
    SalesDateFilter filter,
  ) {
    final entries = <({String receiptCode, DefectWriteOffItem item})>[];
    for (final sale in filteredSales(filter)) {
      for (final item in sale.defectItems) {
        entries.add((receiptCode: sale.receiptCode, item: item));
      }
    }
    entries.sort((a, b) => b.item.createdAt.compareTo(a.item.createdAt));
    return entries;
  }

  List<TopProductStat> topSellingProducts(SalesDateFilter filter) {
    final units = <String, int>{};
    final rev = <String, double>{};
    final prof = <String, double>{};
    final names = <String, String>{};

    for (final sale in filteredSales(filter)) {
      for (final item in sale.items) {
        names[item.productId] = item.productName;
        units[item.productId] = (units[item.productId] ?? 0) + item.quantity;
        rev[item.productId] = (rev[item.productId] ?? 0.0) + item.lineTotal;
        prof[item.productId] = (prof[item.productId] ?? 0.0) + item.lineProfit;
      }
    }

    final list = units.keys
        .map(
          (id) => TopProductStat(
            productId: id,
            productName: names[id] ?? id,
            unitsSold: units[id] ?? 0,
            revenue: rev[id] ?? 0.0,
            profit: prof[id] ?? 0.0,
          ),
        )
        .toList();

    list.sort((a, b) => b.unitsSold.compareTo(a.unitsSold));
    return list;
  }

  List<Product> slowMovingProducts(SalesDateFilter filter) {
    final soldIds = <String>{};
    for (final sale in filteredSales(filter)) {
      for (final item in sale.items) {
        soldIds.add(item.productId);
      }
    }
    return products
        .where((p) => p.stock > 0 && !soldIds.contains(p.id))
        .toList();
  }

  Map<PaymentMethod, double> paymentBreakdown(SalesDateFilter filter) {
    final totals = <PaymentMethod, double>{
      for (final method in PaymentMethod.values) method: 0.0,
    };
    for (final sale in filteredSales(filter)) {
      if (sale.paymentMethod == PaymentMethod.postPay) {
        totals[PaymentMethod.postPay] =
            (totals[PaymentMethod.postPay] ?? 0.0) + sale.remainingDebt;
        if (sale.paidAmount > 0) {
          totals[PaymentMethod.cash] =
              (totals[PaymentMethod.cash] ?? 0.0) + sale.paidAmount;
        }
      } else if (sale.cashAdjustments.isNotEmpty) {
        final adjSum =
            sale.cashAdjustments.fold(0.0, (sum, a) => sum + a.amount);
        final baseTotal = sale.total - adjSum;
        if (sale.isSplitPayment) {
          final basePrimary = (baseTotal - sale.secondaryAmount).clamp(0.0, baseTotal);
          totals[sale.paymentMethod] =
              (totals[sale.paymentMethod] ?? 0.0) + basePrimary;
          totals[sale.secondaryPaymentMethod!] =
              (totals[sale.secondaryPaymentMethod!] ?? 0.0) +
                  sale.secondaryAmount;
        } else {
          totals[sale.paymentMethod] =
              (totals[sale.paymentMethod] ?? 0.0) + baseTotal;
        }
        for (final adj in sale.cashAdjustments) {
          totals[adj.method] = (totals[adj.method] ?? 0.0) + adj.amount;
        }
      } else if (sale.isSplitPayment) {
        totals[sale.paymentMethod] =
            (totals[sale.paymentMethod] ?? 0.0) + sale.primaryPaymentAmount;
        totals[sale.secondaryPaymentMethod!] =
            (totals[sale.secondaryPaymentMethod!] ?? 0.0) +
                sale.secondaryAmount;
      } else {
        totals[sale.paymentMethod] =
            (totals[sale.paymentMethod] ?? 0.0) + sale.total;
      }
    }
    return totals;
  }

  List<Expense> filteredExpenses(SalesDateFilter filter) {
    final now = DateTime.now();
    switch (filter) {
      case SalesDateFilter.today:
        return expenses.where((e) {
          return e.createdAt.year == now.year &&
              e.createdAt.month == now.month &&
              e.createdAt.day == now.day;
        }).toList();
      case SalesDateFilter.last7Days:
        final cutoff = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
        return expenses.where((e) => !e.createdAt.isBefore(cutoff)).toList();
      case SalesDateFilter.all:
        return expenses;
    }
  }

  double totalExpensesFor(SalesDateFilter filter) =>
      filteredExpenses(filter).fold(0.0, (sum, e) => sum + e.amount);

  List<StockInRecord> filteredStockIns(SalesDateFilter filter) {
    final now = DateTime.now();
    switch (filter) {
      case SalesDateFilter.today:
        return _stockIns.where((s) {
          return s.createdAt.year == now.year &&
              s.createdAt.month == now.month &&
              s.createdAt.day == now.day;
        }).toList();
      case SalesDateFilter.last7Days:
        final cutoff = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
        return _stockIns.where((s) => !s.createdAt.isBefore(cutoff)).toList();
      case SalesDateFilter.all:
        return stockIns;
    }
  }

  List<IncomingPriceAnalysis> incomingPriceAnalytics({
    SalesDateFilter filter = SalesDateFilter.all,
  }) {
    final records = filteredStockIns(filter);
    final entriesByProduct = <String, List<IncomingPriceEntry>>{};
    final namesByProduct = <String, String>{};

    for (final record in records) {
      for (final item in record.items) {
        if (item.quantity <= 0) continue;
        namesByProduct[item.productId] = item.productName;
        entriesByProduct.putIfAbsent(item.productId, () => []).add(
              IncomingPriceEntry(
                createdAt: record.createdAt,
                supplierName: record.supplierName,
                quantity: item.quantity,
                unitCost: item.unitCost,
              ),
            );
      }
    }

    final result = <IncomingPriceAnalysis>[];
    for (final entry in entriesByProduct.entries) {
      final list = entry.value
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final latestCost = list.first.unitCost;
      final previousCost = list.length > 1 ? list[1].unitCost : null;
      var totalUnits = 0;
      var totalSpend = 0.0;
      var minCost = list.first.unitCost;
      var maxCost = list.first.unitCost;
      for (final e in list) {
        totalUnits += e.quantity;
        totalSpend += e.quantity * e.unitCost;
        if (e.unitCost < minCost) minCost = e.unitCost;
        if (e.unitCost > maxCost) maxCost = e.unitCost;
      }
      final avgCost = totalUnits > 0 ? totalSpend / totalUnits : latestCost;
      final product = findProductById(entry.key);

      result.add(
        IncomingPriceAnalysis(
          productId: entry.key,
          productName: product?.name ?? namesByProduct[entry.key] ?? entry.key,
          deliveriesCount: list.length,
          totalUnits: totalUnits,
          totalSpend: totalSpend,
          latestCost: latestCost,
          previousCost: previousCost,
          avgCost: avgCost,
          minCost: minCost,
          maxCost: maxCost,
          currentSellPrice: product?.sellPrice,
          entries: List.unmodifiable(list),
        ),
      );
    }

    result.sort((a, b) {
      final deltaCmp = b.priceDelta.abs().compareTo(a.priceDelta.abs());
      if (deltaCmp != 0) return deltaCmp;
      return b.totalSpend.compareTo(a.totalSpend);
    });
    return result;
  }

  Product? findProductById(String id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }
    return null;
  }

  Product? findProductBySku(String sku) {
    final normalized = sku.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final product in products) {
      if (product.sku.trim().toLowerCase() == normalized ||
          product.packBarcode.trim().toLowerCase() == normalized ||
          product.boxBarcode.trim().toLowerCase() == normalized ||
          product.nomenclature.trim().toLowerCase() == normalized) {
        return product;
      }
    }
    return null;
  }

  Future<Product> addProduct({
    required String name,
    required String category,
    String sku = '',
    String nomenclature = '',
    String printName = '',
    String packQty = '',
    String boxQty = '',
    String packBarcode = '',
    String boxBarcode = '',
    String unitWeight = '',
    String unit = '',
    required double costPrice,
    required double sellPrice,
    required int stock,
    int lowStockThreshold = 5,
  }) async {
    final product = Product(
      id: _nextId('prd'),
      name: name.trim(),
      category: category.trim().isEmpty ? 'General' : category.trim(),
      sku: sku.trim(),
      nomenclature: nomenclature.trim(),
      printName: printName.trim(),
      packQty: packQty.trim(),
      boxQty: boxQty.trim(),
      packBarcode: packBarcode.trim(),
      boxBarcode: boxBarcode.trim(),
      unitWeight: unitWeight.trim(),
      unit: unit.trim(),
      costPrice: costPrice,
      sellPrice: sellPrice,
      stock: stock < 0 ? 0 : stock,
      lowStockThreshold: lowStockThreshold < 0 ? 0 : lowStockThreshold,
      updatedAt: DateTime.now(),
    );
    _products.insert(0, product);
    notifyListeners();
    await _persist();
    return product;
  }

  Future<void> updateProduct(Product updated) async {
    final index = _products.indexWhere((p) => p.id == updated.id);
    if (index == -1) return;
    _products[index] = updated.copyWith(updatedAt: DateTime.now());
    final currentCartQty = _cart[updated.id] ?? 0;
    if (!updated.isActive || updated.stock <= 0) {
      _cart.remove(updated.id);
      _cartCustomPrices.remove(updated.id);
    } else if (currentCartQty > updated.stock) {
      _cart[updated.id] = updated.stock;
    }
    notifyListeners();
    await _persist();
  }

  Future<int> moveProductsToCategory(
    Iterable<String> productIds,
    String targetCategory,
  ) async {
    final targetIds = productIds.toSet();
    final cleanCategory =
        targetCategory.trim().isEmpty ? 'General' : targetCategory.trim();
    if (targetIds.isEmpty) return 0;
    final now = DateTime.now();
    var moved = 0;
    for (var i = 0; i < _products.length; i++) {
      final current = _products[i];
      if (targetIds.contains(current.id) &&
          current.category != cleanCategory) {
        _products[i] = current.copyWith(
          category: cleanCategory,
          updatedAt: now,
        );
        moved += 1;
      }
    }
    if (moved > 0) {
      notifyListeners();
      await _persist();
    }
    return moved;
  }

  Future<int> moveCategoryToCategory(
    String fromCategory,
    String toCategory,
  ) async {
    final cleanTarget =
        toCategory.trim().isEmpty ? 'General' : toCategory.trim();
    if (fromCategory == cleanTarget) return 0;
    final ids = products
        .where((p) => p.category == fromCategory)
        .map((p) => p.id)
        .toList();
    return moveProductsToCategory(ids, cleanTarget);
  }

  Future<void> adjustStock(String productId, int delta) async {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return;
    final current = _products[index];
    final nextStock = current.stock + delta;
    await updateProduct(
      current.copyWith(stock: nextStock < 0 ? 0 : nextStock),
    );
  }

  Future<void> receiveStock({
    String supplierName = '',
    required List<StockInItem> items,
    bool recordAsExpense = true,
  }) async {
    if (items.isEmpty) return;
    final now = DateTime.now();

    for (final item in items) {
      if (item.quantity <= 0) continue;
      final index = _products.indexWhere((p) => p.id == item.productId);
      if (index != -1) {
        final current = _products[index];
        _products[index] = current.copyWith(
          stock: current.stock + item.quantity,
          costPrice: item.unitCost > 0 ? item.unitCost : current.costPrice,
          sellPrice: (item.newSellPrice != null && item.newSellPrice! > 0)
              ? item.newSellPrice!
              : current.sellPrice,
          updatedAt: now,
        );
      }
    }

    final record = StockInRecord(
      id: _nextId('in'),
      supplierName: supplierName.trim(),
      items: items,
      createdAt: now,
    );
    _stockIns.insert(0, record);
    _stockInDraft = null;

    if (recordAsExpense && record.totalCost > 0) {
      final label = supplierName.trim().isEmpty
          ? 'Stock-in (${record.totalUnits})'
          : 'Stock-in: ${supplierName.trim()}';
      _expenses.insert(
        0,
        Expense(
          id: _nextId('exp'),
          title: label,
          category: ExpenseCategory.purchase,
          amount: record.totalCost,
          createdAt: now,
        ),
      );
    }

    notifyListeners();
    await _persist();
  }

  Future<int> applyStocktake(Map<String, int> actualCounts) async {
    var adjusted = 0;
    final now = DateTime.now();
    for (final entry in actualCounts.entries) {
      final index = _products.indexWhere((p) => p.id == entry.key);
      if (index == -1) continue;
      final cleanCount = entry.value < 0 ? 0 : entry.value;
      if (_products[index].stock != cleanCount) {
        _products[index] = _products[index].copyWith(
          stock: cleanCount,
          updatedAt: now,
        );
        adjusted += 1;
      }
    }
    final hadDraft = _stocktakeDraft != null;
    _stocktakeDraft = null;
    if (adjusted > 0 || hadDraft) {
      notifyListeners();
      await _persist();
    }
    return adjusted;
  }

  Future<void> archiveProduct(String productId) async {
    await archiveProducts([productId]);
  }

  Future<int> archiveProducts(Iterable<String> productIds) async {
    final targetIds = productIds.toSet();
    if (targetIds.isEmpty) return 0;
    final now = DateTime.now();
    var moved = 0;
    for (var i = 0; i < _products.length; i++) {
      final current = _products[i];
      if (targetIds.contains(current.id) &&
          !current.isArchived &&
          !current.isTrashed) {
        _products[i] = current.copyWith(
          archivedAt: now,
          clearTrashedAt: true,
          updatedAt: now,
        );
        _cart.remove(current.id);
        moved += 1;
      }
    }
    if (moved > 0) {
      notifyListeners();
      await _persist();
    }
    return moved;
  }

  Future<int> archiveCategory(String category) async {
    final ids = products
        .where((p) => p.category == category)
        .map((p) => p.id)
        .toList();
    return archiveProducts(ids);
  }

  Future<int> archiveAllProducts() async {
    final ids = products.map((p) => p.id).toList();
    return archiveProducts(ids);
  }

  Future<void> unarchiveProduct(String productId) async {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return;
    _products[index] = _products[index].copyWith(
      clearArchivedAt: true,
      clearTrashedAt: true,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _persist();
  }

  Future<int> restoreAllProductsFromArchive() async {
    final now = DateTime.now();
    var restored = 0;
    for (var i = 0; i < _products.length; i++) {
      if (_products[i].isArchived) {
        _products[i] = _products[i].copyWith(
          clearArchivedAt: true,
          clearTrashedAt: true,
          updatedAt: now,
        );
        restored += 1;
      }
    }
    if (restored > 0) {
      notifyListeners();
      await _persist();
    }
    return restored;
  }

  Future<void> moveProductToTrash(String productId) async {
    await moveProductsToTrash([productId]);
  }

  Future<int> moveProductsToTrash(Iterable<String> productIds) async {
    final targetIds = productIds.toSet();
    if (targetIds.isEmpty) return 0;
    final now = DateTime.now();
    var moved = 0;
    for (var i = 0; i < _products.length; i++) {
      final current = _products[i];
      if (targetIds.contains(current.id) && !current.isTrashed) {
        _products[i] = current.copyWith(
          trashedAt: now,
          updatedAt: now,
        );
        _cart.remove(current.id);
        moved += 1;
      }
    }
    if (moved > 0) {
      notifyListeners();
      await _persist();
    }
    return moved;
  }

  Future<int> moveCategoryToTrash(String category) async {
    final ids = products
        .where((p) => p.category == category)
        .map((p) => p.id)
        .toList();
    return moveProductsToTrash(ids);
  }

  Future<int> moveAllProductsToTrash() async {
    final ids = products.map((p) => p.id).toList();
    return moveProductsToTrash(ids);
  }

  Future<void> restoreProductFromTrash(String productId) async {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return;
    _products[index] = _products[index].copyWith(
      clearArchivedAt: true,
      clearTrashedAt: true,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _persist();
  }

  Future<int> restoreAllProductsFromTrash() async {
    final now = DateTime.now();
    var restored = 0;
    for (var i = 0; i < _products.length; i++) {
      if (_products[i].isTrashed) {
        _products[i] = _products[i].copyWith(
          clearArchivedAt: true,
          clearTrashedAt: true,
          updatedAt: now,
        );
        restored += 1;
      }
    }
    if (restored > 0) {
      notifyListeners();
      await _persist();
    }
    return restored;
  }

  Future<void> moveTrashedProductToArchive(String productId) async {
    await moveTrashedProductsToArchive([productId]);
  }

  Future<int> moveTrashedProductsToArchive(Iterable<String> productIds) async {
    final targetIds = productIds.toSet();
    if (targetIds.isEmpty) return 0;
    final now = DateTime.now();
    var moved = 0;
    for (var i = 0; i < _products.length; i++) {
      final current = _products[i];
      if (targetIds.contains(current.id) && current.isTrashed) {
        _products[i] = current.copyWith(
          archivedAt: now,
          clearTrashedAt: true,
          updatedAt: now,
        );
        moved += 1;
      }
    }
    if (moved > 0) {
      notifyListeners();
      await _persist();
    }
    return moved;
  }

  Future<int> moveAllTrashedProductsToArchive() async {
    final ids = trashedProducts.map((p) => p.id).toList();
    return moveTrashedProductsToArchive(ids);
  }

  Future<int> unarchiveProducts(Iterable<String> productIds) async {
    final targetIds = productIds.toSet();
    if (targetIds.isEmpty) return 0;
    final now = DateTime.now();
    var restored = 0;
    for (var i = 0; i < _products.length; i++) {
      final current = _products[i];
      if (targetIds.contains(current.id) && current.isArchived) {
        _products[i] = current.copyWith(
          clearArchivedAt: true,
          clearTrashedAt: true,
          updatedAt: now,
        );
        restored += 1;
      }
    }
    if (restored > 0) {
      notifyListeners();
      await _persist();
    }
    return restored;
  }

  Future<int> restoreTrashedProducts(Iterable<String> productIds) async {
    final targetIds = productIds.toSet();
    if (targetIds.isEmpty) return 0;
    final now = DateTime.now();
    var restored = 0;
    for (var i = 0; i < _products.length; i++) {
      final current = _products[i];
      if (targetIds.contains(current.id) && current.isTrashed) {
        _products[i] = current.copyWith(
          clearArchivedAt: true,
          clearTrashedAt: true,
          updatedAt: now,
        );
        restored += 1;
      }
    }
    if (restored > 0) {
      notifyListeners();
      await _persist();
    }
    return restored;
  }

  Future<int> deleteTrashedProductsPermanently(
    Iterable<String> productIds,
  ) async {
    final targetIds = productIds.toSet();
    if (targetIds.isEmpty) return 0;
    final before = _products.length;
    _products.removeWhere((p) => targetIds.contains(p.id) && p.isTrashed);
    final removed = before - _products.length;
    if (removed > 0) {
      for (final id in targetIds) {
        _cart.remove(id);
      }
      notifyListeners();
      await _persist();
    }
    return removed;
  }

  Future<void> deleteProductPermanently(String productId) async {
    _products.removeWhere((p) => p.id == productId);
    _cart.remove(productId);
    notifyListeners();
    await _persist();
  }

  Future<void> deleteProduct(String productId) => moveProductToTrash(productId);

  List<CartLine> get cartLines {
    final lines = <CartLine>[];
    for (final entry in _cart.entries) {
      final product = findProductById(entry.key);
      if (product != null && product.isActive && entry.value > 0) {
        lines.add(
          CartLine(
            product: product,
            quantity: entry.value,
            customUnitPrice: _cartCustomPrices[entry.key],
          ),
        );
      }
    }
    return lines;
  }

  int get cartItemCount =>
      _cart.values.fold(0, (sum, quantity) => sum + quantity);

  double get cartSubtotal =>
      cartLines.fold(0.0, (sum, line) => sum + line.lineTotal);

  double get cartEstimatedProfit =>
      cartLines.fold(0.0, (sum, line) => sum + line.lineProfit);

  int cartQuantityFor(String productId) => _cart[productId] ?? 0;

  bool addToCart(String productId, {int quantity = 1}) {
    final product = findProductById(productId);
    if (product == null || !product.isActive || product.stock <= 0) {
      return false;
    }
    final existing = _cart[productId] ?? 0;
    final next = existing + quantity;
    if (next > product.stock) return false;
    _cart[productId] = next;
    notifyListeners();
    return true;
  }

  void setCartQuantity(String productId, int quantity) {
    final product = findProductById(productId);
    if (product == null || !product.isActive || quantity <= 0) {
      _cart.remove(productId);
      _cartCustomPrices.remove(productId);
      notifyListeners();
      return;
    }
    _cart[productId] = quantity > product.stock ? product.stock : quantity;
    notifyListeners();
  }

  void setCartItemPrice(String productId, double? price) {
    final product = findProductById(productId);
    if (product == null ||
        price == null ||
        price <= 0 ||
        (price - product.sellPrice).abs() < 0.009) {
      _cartCustomPrices.remove(productId);
    } else {
      _cartCustomPrices[productId] = price;
    }
    notifyListeners();
  }

  void clearCart() {
    if (_cart.isEmpty) return;
    _cart.clear();
    _cartCustomPrices.clear();
    notifyListeners();
  }

  Future<Sale?> completeSale({
    PaymentMethod paymentMethod = PaymentMethod.cash,
    PaymentMethod? secondaryPaymentMethod,
    double secondaryAmount = 0,
    String customerName = '',
    double discount = 0,
    double? paidAmount,
    DateTime? dueDate,
  }) async {
    final lines = cartLines;
    if (lines.isEmpty) return null;

    for (final line in lines) {
      if (line.quantity > line.product.stock) {
        return null;
      }
    }

    final saleItems = lines
        .map(
          (line) => SaleItem(
            productId: line.product.id,
            productName: line.product.name,
            quantity: line.quantity,
            unitCost: line.product.costPrice,
            unitPrice: line.unitPrice,
          ),
        )
        .toList();

    final now = DateTime.now();
    final cleanDiscount = discount < 0 ? 0.0 : discount;
    final subtotal = saleItems.fold(0.0, (sum, item) => sum + item.lineTotal);
    final total = (subtotal - cleanDiscount).clamp(0.0, double.infinity);
    final hasValidSplit = secondaryPaymentMethod != null &&
        secondaryPaymentMethod != paymentMethod &&
        paymentMethod != PaymentMethod.postPay &&
        secondaryPaymentMethod != PaymentMethod.postPay &&
        secondaryAmount > 0.009 &&
        secondaryAmount < total;

    final double resolvedPaid;
    if (paymentMethod == PaymentMethod.postPay) {
      resolvedPaid = (paidAmount ?? 0.0).clamp(0.0, total);
    } else {
      resolvedPaid = total;
    }

    final sale = Sale(
      id: _nextId('sal'),
      items: saleItems,
      paymentMethod: paymentMethod,
      secondaryPaymentMethod: hasValidSplit ? secondaryPaymentMethod : null,
      secondaryAmount: hasValidSplit ? secondaryAmount : 0,
      customerName: customerName.trim(),
      discount: cleanDiscount,
      paidAmount: resolvedPaid,
      dueDate: paymentMethod == PaymentMethod.postPay ? dueDate : null,
      paidAt: resolvedPaid >= total ? now : null,
      paymentHistory: (paymentMethod == PaymentMethod.postPay && resolvedPaid > 0)
          ? [DebtPayment(amount: resolvedPaid, paidAt: now)]
          : const [],
      createdAt: now,
    );

    for (final line in lines) {
      final index = _products.indexWhere((p) => p.id == line.product.id);
      if (index != -1) {
        final current = _products[index];
        _products[index] = current.copyWith(
          stock: current.stock - line.quantity,
          updatedAt: now,
        );
      }
    }

    _sales.insert(0, sale);
    _cart.clear();
    _cartCustomPrices.clear();
    notifyListeners();
    await _persist();
    return sale;
  }

  Future<void> recordSalePayment(String saleId, double amount) async {
    if (amount <= 0) return;
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) return;
    final sale = _sales[index];
    final nextPaid = (sale.paidAmount + amount).clamp(0.0, sale.total);
    final applied = nextPaid - sale.paidAmount;
    if (applied <= 0) return;
    final now = DateTime.now();
    final history = List<DebtPayment>.from(sale.paymentHistory)
      ..add(DebtPayment(amount: applied, paidAt: now));
    _sales[index] = sale.copyWith(
      paidAmount: nextPaid,
      paidAt: nextPaid >= sale.total - 0.009 ? now : null,
      paymentHistory: history,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> markSalePaid(String saleId) async {
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) return;
    final sale = _sales[index];
    final now = DateTime.now();
    final history = List<DebtPayment>.from(sale.paymentHistory);
    if (sale.remainingDebt > 0) {
      history.add(DebtPayment(amount: sale.remainingDebt, paidAt: now));
    }
    _sales[index] = sale.copyWith(
      paidAmount: sale.total,
      paidAt: now,
      paymentHistory: history,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> processSaleReturnOrExchange({
    required String saleId,
    required Map<String, int> returnQuantities,
    double customRefundAmount = 0,
    List<({Product product, int quantity, double? customUnitPrice})> exchangeItems = const [],
    bool returnToStock = true,
    PaymentMethod? settlementMethod,
  }) async {
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) return;
    final sale = _sales[index];
    final now = DateTime.now();

    final updatedItems = <SaleItem>[];
    final updatedDefectItems = List<DefectWriteOffItem>.from(sale.defectItems);
    var returnedValue = 0.0;
    var defectCostTotal = 0.0;
    final returnedParts = <String>[];

    for (final item in sale.items) {
      final retQty =
          (returnQuantities[item.productId] ?? 0).clamp(0, item.quantity);
      if (retQty > 0) {
        returnedValue += item.unitPrice * retQty;
        returnedParts.add('${item.productName} × $retQty');
        if (returnToStock) {
          final productIndex =
              _products.indexWhere((p) => p.id == item.productId);
          if (productIndex != -1) {
            final current = _products[productIndex];
            _products[productIndex] = current.copyWith(
              stock: current.stock + retQty,
              updatedAt: now,
            );
          }
        } else {
          defectCostTotal += item.unitCost * retQty;
          updatedDefectItems.add(
            DefectWriteOffItem(
              productId: item.productId,
              productName: item.productName,
              quantity: retQty,
              unitCost: item.unitCost,
              createdAt: now,
            ),
          );
        }
      }
      final leftQty = item.quantity - retQty;
      if (leftQty > 0) {
        updatedItems.add(item.copyWith(quantity: leftQty));
      }
    }

    var exchangeValue = 0.0;
    final exchangeParts = <String>[];
    for (final ex in exchangeItems) {
      if (ex.quantity <= 0) continue;
      final productIndex =
          _products.indexWhere((p) => p.id == ex.product.id);
      if (productIndex == -1) continue;
      final current = _products[productIndex];
      final takeQty = ex.quantity > current.stock ? current.stock : ex.quantity;
      if (takeQty <= 0) continue;

      final unitPrice =
          (ex.customUnitPrice != null && ex.customUnitPrice! > 0)
              ? ex.customUnitPrice!
              : current.sellPrice;

      _products[productIndex] = current.copyWith(
        stock: current.stock - takeQty,
        updatedAt: now,
      );
      exchangeValue += unitPrice * takeQty;
      exchangeParts.add('${current.name} × $takeQty');

      final existingIdx = updatedItems.indexWhere(
        (i) =>
            i.productId == current.id &&
            (i.unitPrice - unitPrice).abs() < 0.009,
      );
      if (existingIdx != -1) {
        final existing = updatedItems[existingIdx];
        updatedItems[existingIdx] = existing.copyWith(
          quantity: existing.quantity + takeQty,
        );
      } else {
        updatedItems.add(
          SaleItem(
            productId: current.id,
            productName: current.name,
            quantity: takeQty,
            unitCost: current.costPrice,
            unitPrice: unitPrice,
          ),
        );
      }
    }

    final oldSubtotal = sale.subtotal;
    final effectiveRatio = oldSubtotal > 0
        ? ((oldSubtotal - sale.discount) / oldSubtotal).clamp(0.0, 1.0)
        : 1.0;
    final returnedEffectiveValue = returnedValue * effectiveRatio;
    final newDiscount = (oldSubtotal > 0 && returnedValue > 0)
        ? (sale.discount * ((oldSubtotal - returnedValue) / oldSubtotal))
            .clamp(0.0, sale.discount)
        : sale.discount;

    final maxCashRefund = sale.paidAmount;
    final cappedCustomRefund = customRefundAmount.clamp(0.0, maxCashRefund);

    var nextRefundedAmount = sale.refundedAmount;
    if (exchangeItems.isEmpty && cappedCustomRefund > 0) {
      final extraRefund = cappedCustomRefund - returnedEffectiveValue;
      if (extraRefund > 0.009) {
        nextRefundedAmount += extraRefund;
      }
    }

    final newSubtotal =
        updatedItems.fold(0.0, (sum, item) => sum + item.lineTotal);
    final newTotal =
        (newSubtotal - newDiscount - nextRefundedAmount).clamp(0.0, double.infinity);

    final cashDelta = exchangeItems.isNotEmpty
        ? (exchangeValue - returnedEffectiveValue)
        : -(cappedCustomRefund > 0
            ? cappedCustomRefund
            : returnedEffectiveValue.clamp(0.0, maxCashRefund));

    final updatedAdjustments = List<SaleCashAdjustment>.from(sale.cashAdjustments);
    if (settlementMethod != null &&
        settlementMethod != PaymentMethod.postPay &&
        sale.paymentMethod != PaymentMethod.postPay &&
        cashDelta.abs() > 0.009) {
      updatedAdjustments.add(
        SaleCashAdjustment(
          method: settlementMethod,
          amount: cashDelta,
          createdAt: now,
        ),
      );
    }

    final noteParts = <String>[
      if (sale.refundNote.isNotEmpty) sale.refundNote,
      if (returnedParts.isNotEmpty)
        '− ${returnedParts.join(', ')}${returnToStock ? '' : ' (${strings.defectTag})'}',
      if (exchangeParts.isNotEmpty) '+ ${exchangeParts.join(', ')}',
      if (exchangeItems.isEmpty && cappedCustomRefund > 0)
        '(${cappedCustomRefund.toStringAsFixed(0)})',
      if (settlementMethod != null &&
          settlementMethod != PaymentMethod.postPay &&
          cashDelta.abs() > 0.009)
        '[${strings.paymentMethodLabel(settlementMethod.name)}]',
    ];

    final double nextPaidAmount;
    if (sale.paymentMethod == PaymentMethod.postPay) {
      final cashBack = exchangeItems.isEmpty ? cappedCustomRefund : 0.0;
      nextPaidAmount = (sale.paidAmount - cashBack).clamp(0.0, newTotal);
    } else {
      nextPaidAmount = newTotal;
    }

    final moneyReturned = cashDelta < 0 ? (-cashDelta).clamp(0.0, maxCashRefund) : 0.0;

    _sales[index] = sale.copyWith(
      items: updatedItems,
      discount: newDiscount,
      cashAdjustments: updatedAdjustments,
      defectItems: updatedDefectItems,
      refundedAmount: nextRefundedAmount,
      returnedMoneyTotal: sale.returnedMoneyTotal + moneyReturned,
      refundNote: noteParts.join(' • '),
      paidAmount: nextPaidAmount,
    );
    if (!returnToStock && defectCostTotal > 0.009) {
      _expenses.insert(
        0,
        Expense(
          id: _nextId('exp'),
          title: strings.defectWriteOffTitle(sale.receiptCode),
          category: ExpenseCategory.other,
          amount: defectCostTotal,
          note: returnedParts.join(', '),
          createdAt: now,
        ),
      );
    }
    notifyListeners();
    await _persist();
  }

  Future<void> updateSalePaymentMethod(
    String saleId, {
    required PaymentMethod paymentMethod,
    PaymentMethod? secondaryPaymentMethod,
    double secondaryAmount = 0,
  }) async {
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) return;
    final sale = _sales[index];
    final now = DateTime.now();
    final hasValidSplit = secondaryPaymentMethod != null &&
        secondaryPaymentMethod != paymentMethod &&
        paymentMethod != PaymentMethod.postPay &&
        secondaryPaymentMethod != PaymentMethod.postPay &&
        secondaryAmount > 0.009 &&
        secondaryAmount < sale.total;

    if (paymentMethod == PaymentMethod.postPay) {
      _sales[index] = sale.copyWith(
        paymentMethod: PaymentMethod.postPay,
        clearSecondaryPaymentMethod: true,
        secondaryAmount: 0,
        paidAmount: sale.paymentMethod == PaymentMethod.postPay
            ? sale.paidAmount
            : 0.0,
        clearPaidAt: true,
      );
    } else {
      _sales[index] = sale.copyWith(
        paymentMethod: paymentMethod,
        secondaryPaymentMethod: hasValidSplit ? secondaryPaymentMethod : null,
        clearSecondaryPaymentMethod: !hasValidSplit,
        secondaryAmount: hasValidSplit ? secondaryAmount : 0,
        paidAmount: sale.total,
        paidAt: sale.paidAt ?? now,
      );
    }
    notifyListeners();
    await _persist();
  }

  Future<void> archiveSale(String saleId) async {
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) return;
    _sales[index] = _sales[index].copyWith(
      archivedAt: DateTime.now(),
      clearTrashedAt: true,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> unarchiveSale(String saleId) async {
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) return;
    _sales[index] = _sales[index].copyWith(
      clearArchivedAt: true,
      clearTrashedAt: true,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> moveSaleToTrash(String saleId) async {
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) return;
    final sale = _sales[index];
    if (sale.isTrashed) return;
    final now = DateTime.now();

    for (final item in sale.items) {
      final productIndex = _products.indexWhere((p) => p.id == item.productId);
      if (productIndex != -1) {
        final current = _products[productIndex];
        _products[productIndex] = current.copyWith(
          stock: current.stock + item.quantity,
          updatedAt: now,
        );
      }
    }

    _sales[index] = sale.copyWith(trashedAt: now);
    notifyListeners();
    await _persist();
  }

  Future<void> restoreSaleFromTrash(String saleId) async {
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) return;
    final sale = _sales[index];
    if (!sale.isTrashed) return;
    final now = DateTime.now();

    for (final item in sale.items) {
      final productIndex = _products.indexWhere((p) => p.id == item.productId);
      if (productIndex != -1) {
        final current = _products[productIndex];
        final nextStock = current.stock - item.quantity;
        _products[productIndex] = current.copyWith(
          stock: nextStock < 0 ? 0 : nextStock,
          updatedAt: now,
        );
      }
    }

    _sales[index] = sale.copyWith(
      clearArchivedAt: true,
      clearTrashedAt: true,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> moveTrashedSaleToArchive(String saleId) async {
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) return;
    final sale = _sales[index];
    if (!sale.isTrashed) return;
    final now = DateTime.now();

    for (final item in sale.items) {
      final productIndex = _products.indexWhere((p) => p.id == item.productId);
      if (productIndex != -1) {
        final current = _products[productIndex];
        final nextStock = current.stock - item.quantity;
        _products[productIndex] = current.copyWith(
          stock: nextStock < 0 ? 0 : nextStock,
          updatedAt: now,
        );
      }
    }

    _sales[index] = sale.copyWith(
      archivedAt: now,
      clearTrashedAt: true,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> deleteSalePermanently(String saleId) async {
    _sales.removeWhere((s) => s.id == saleId);
    notifyListeners();
    await _persist();
  }

  Future<void> voidSale(String saleId) => moveSaleToTrash(saleId);

  Future<void> addExpense({
    required String title,
    required ExpenseCategory category,
    required double amount,
    String note = '',
  }) async {
    final expense = Expense(
      id: _nextId('exp'),
      title: title.trim(),
      category: category,
      amount: amount < 0 ? 0 : amount,
      note: note.trim(),
      createdAt: DateTime.now(),
    );
    _expenses.insert(0, expense);
    notifyListeners();
    await _persist();
  }

  Future<void> updateExpense({
    required String expenseId,
    required String title,
    required ExpenseCategory category,
    required double amount,
    String note = '',
  }) async {
    final index = _expenses.indexWhere((e) => e.id == expenseId);
    if (index == -1) return;
    _expenses[index] = _expenses[index].copyWith(
      title: title.trim(),
      category: category,
      amount: amount < 0 ? 0 : amount,
      note: note.trim(),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> moveExpenseToTrash(String expenseId) async {
    final index = _expenses.indexWhere((e) => e.id == expenseId);
    if (index == -1) return;
    _expenses[index] = _expenses[index].copyWith(trashedAt: DateTime.now());
    notifyListeners();
    await _persist();
  }

  Future<void> restoreExpenseFromTrash(String expenseId) async {
    final index = _expenses.indexWhere((e) => e.id == expenseId);
    if (index == -1) return;
    _expenses[index] = _expenses[index].copyWith(clearTrashedAt: true);
    notifyListeners();
    await _persist();
  }

  Future<void> deleteExpensePermanently(String expenseId) async {
    _expenses.removeWhere((e) => e.id == expenseId);
    notifyListeners();
    await _persist();
  }

  Future<void> emptyTrash() async {
    _products.removeWhere((p) => p.isTrashed);
    _sales.removeWhere((s) => s.isTrashed);
    _expenses.removeWhere((e) => e.isTrashed);
    notifyListeners();
    await _persist();
  }

  Future<void> loadSampleData() async {
    final now = DateTime.now();
    _products
      ..clear()
      ..addAll([
        Product(
          id: _nextId('prd'),
          name: 'Arabica Coffee Beans 250g',
          category: 'Beverages',
          sku: 'COF-250',
          costPrice: 2800,
          sellPrice: 4500,
          stock: 18,
          lowStockThreshold: 5,
          updatedAt: now,
        ),
        Product(
          id: _nextId('prd'),
          name: 'Green Tea Box (25 bags)',
          category: 'Beverages',
          sku: 'TEA-025',
          costPrice: 950,
          sellPrice: 1700,
          stock: 4,
          lowStockThreshold: 5,
          updatedAt: now,
        ),
        Product(
          id: _nextId('prd'),
          name: 'Notebook A5 Hardcover',
          category: 'Stationery',
          sku: 'STN-A5',
          costPrice: 1400,
          sellPrice: 2600,
          stock: 24,
          lowStockThreshold: 6,
          updatedAt: now,
        ),
        Product(
          id: _nextId('prd'),
          name: 'Gel Pen Pack (5 pcs)',
          category: 'Stationery',
          sku: 'PEN-005',
          costPrice: 800,
          sellPrice: 1500,
          stock: 0,
          lowStockThreshold: 5,
          updatedAt: now,
        ),
        Product(
          id: _nextId('prd'),
          name: 'Stainless Water Bottle 750ml',
          category: 'Accessories',
          sku: 'BOT-750',
          costPrice: 3200,
          sellPrice: 5900,
          stock: 9,
          lowStockThreshold: 3,
          updatedAt: now,
        ),
      ]);
    _cart.clear();
    notifyListeners();
    await _persist();
  }
}
