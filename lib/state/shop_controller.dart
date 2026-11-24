import 'dart:async' show Timer;
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:math' show Random;
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import '../l10n/app_strings.dart';
import '../models/cash_drawer_movement.dart';
import '../models/customer.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/stock_in.dart';
import '../services/daily_local_backup_service.dart';
import '../services/google_sheets_service.dart';
import '../services/input_normalizer.dart';
import '../services/inventory_storage.dart';
import '../services/sheet_export_helper.dart';
import '../services/sqlite_inventory_storage.dart';

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
    this.useWholesalePrice = false,
    this.wholesaleDisabled = false,
  });

  final Product product;
  final double quantity;
  final double? customUnitPrice;
  final bool useWholesalePrice;
  final bool wholesaleDisabled;

  bool get isAutoWholesaleApplied =>
      !wholesaleDisabled && product.isAutoWholesaleForQty(quantity);

  bool get effectiveUseWholesale =>
      !wholesaleDisabled &&
      product.hasWholesalePrice &&
      (useWholesalePrice || isAutoWholesaleApplied);

  double get defaultUnitPrice =>
      effectiveUseWholesale ? product.wholesalePrice : product.sellPrice;

  double get unitPrice => customUnitPrice ?? defaultUnitPrice;

  bool get hasCustomPrice =>
      customUnitPrice != null &&
      (customUnitPrice! - defaultUnitPrice).abs() > 0.009;

  bool get isWholesalePriceApplied =>
      !hasCustomPrice && effectiveUseWholesale;

  double get lineTotal => unitPrice * quantity;
  double get lineCost => product.costPrice * quantity;
  double get lineProfit => lineTotal - lineCost;
}

class DebtorSummary {
  const DebtorSummary({
    required this.customerName,
    this.phone = '',
    required this.sales,
    this.allDebtSales = const [],
    this.totalDebtPurchasesCount = 0,
    this.repayments = const [],
    required this.totalDebt,
    this.earliestDueDate,
    required this.hasOverdue,
  });

  final String customerName;
  final String phone;
  final List<Sale> sales;
  final List<Sale> allDebtSales;
  final int totalDebtPurchasesCount;
  final List<({DateTime date, double amount, String receiptCode})> repayments;
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
  final double unitsSold;
  final double revenue;
  final double profit;
}

class SalesTimeBucketStat {
  const SalesTimeBucketStat({
    required this.key,
    required this.ordersCount,
    required this.unitsSold,
    required this.revenue,
    required this.profit,
  });

  final int key;
  final int ordersCount;
  final double unitsSold;
  final double revenue;
  final double profit;
}

class OutOfStockStat {
  const OutOfStockStat({
    required this.product,
    required this.currentDays,
    required this.totalDays,
    required this.avgDailyUnits,
    required this.estimatedLostRevenue,
    required this.estimatedLostProfit,
  });

  final Product product;
  final int currentDays;
  final int totalDays;
  final double avgDailyUnits;
  final double estimatedLostRevenue;
  final double estimatedLostProfit;
}

class FrozenCashItem {
  const FrozenCashItem({
    required this.product,
    required this.frozenValue,
    required this.potentialRevenue,
    required this.daysWithoutSales,
    required this.hasEverSold,
  });

  final Product product;
  final double frozenValue;
  final double potentialRevenue;
  final int daysWithoutSales;
  final bool hasEverSold;
}

enum AdviceSeverity { urgent, warning, opportunity, info }

enum AdviceActionType {
  none,
  addToStockIn,
  editPrice,
  barcodeLabel,
  openProduct,
  messageCustomer,
}

class DailyProductAdvice {
  const DailyProductAdvice({
    required this.id,
    required this.severity,
    required this.title,
    required this.body,
    this.product,
    this.customerName,
    this.customerPhone,
    this.whatsappMessage,
    this.actionType = AdviceActionType.none,
  });

  final String id;
  final AdviceSeverity severity;
  final String title;
  final String body;
  final Product? product;
  final String? customerName;
  final String? customerPhone;
  final String? whatsappMessage;
  final AdviceActionType actionType;
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
    this.currencyCode = '',
    this.exchangeRate,
    required this.quantity,
    required this.unitCost,
  });

  final DateTime createdAt;
  final String supplierName;
  final String currencyCode;
  final double? exchangeRate;
  final double quantity;
  final double unitCost;

  String get exchangeRateLabel {
    final code = currencyCode.trim().toUpperCase();
    final rate = exchangeRate;
    if (code.isEmpty || rate == null || rate <= 0) return '';
    final rateStr = rate == rate.roundToDouble()
        ? rate.toStringAsFixed(0)
        : rate.toStringAsFixed(2);
    return '1 $code = $rateStr';
  }
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
  final double totalUnits;
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

abstract final class FeatureUsageKeys {
  static const String tabGoods = 'tab_goods';
  static const String tabSell = 'tab_sell';
  static const String tabSales = 'tab_sales';
  static const String tabExpenses = 'tab_expenses';

  static const String barcodeScan = 'barcode_scan';
  static const String barcodeLabel = 'barcode_label';
  static const String stockIn = 'stock_in';
  static const String stocktake = 'stocktake';
  static const String productAdd = 'product_add';
  static const String productEdit = 'product_edit';
  static const String changeHistory = 'change_history';
  static const String dailyAdvice = 'daily_advice';
  static const String stockValue = 'stock_value';
  static const String duplicateCheck = 'duplicate_check';

  static const String saleComplete = 'sale_complete';
  static const String holdSale = 'hold_sale';
  static const String wholesaleMode = 'wholesale_mode';
  static const String returnExchange = 'return_exchange';
  static const String debtors = 'debtors';
  static const String customers = 'customers';
  static const String analytics = 'analytics';
  static const String invoicesHistory = 'invoices_history';
  static const String defectReport = 'defect_report';

  static const String expenseAdd = 'expense_add';
  static const String incomingPrices = 'incoming_prices';
  static const String googleSheets = 'google_sheets';
  static const String backupExport = 'backup_export';
  static const String archiveTrash = 'archive_trash';

  static const List<String> all = [
    tabGoods,
    tabSell,
    tabSales,
    tabExpenses,
    barcodeScan,
    barcodeLabel,
    stockIn,
    stocktake,
    productAdd,
    productEdit,
    changeHistory,
    dailyAdvice,
    stockValue,
    duplicateCheck,
    saleComplete,
    holdSale,
    wholesaleMode,
    returnExchange,
    debtors,
    customers,
    analytics,
    invoicesHistory,
    defectReport,
    expenseAdd,
    incomingPrices,
    googleSheets,
    backupExport,
    archiveTrash,
  ];
}

class ShopController extends ChangeNotifier {
  ShopController({
    InventoryStorage? storage,
    DailyLocalBackupService? dailyBackupService,
  })  : _storage = storage ?? SqliteInventoryStorage(),
        _dailyBackupService = dailyBackupService ?? DailyLocalBackupService();

  final InventoryStorage _storage;
  final DailyLocalBackupService _dailyBackupService;

  final List<Product> _products = [];
  final List<Sale> _sales = [];
  final List<Expense> _expenses = [];
  final List<Customer> _customers = [];
  final List<StockInRecord> _stockIns = [];
  final Map<String, double> _cart = {};
  final Map<String, double> _cartCustomPrices = {};
  final Map<String, Product> _customCartProducts = {};
  final Set<String> _wholesaleDisabledProducts = {};
  bool _wholesaleCartMode = false;

  AppLanguage _language = AppLanguage.en;
  bool _followSystemLanguage = true;
  AppCurrency _currency = AppCurrency.kzt;
  String _shopName = 'Lumio';
  String _shopAddress = '';
  String _shopPhone = '';
  String _receiptFooter = '';
  String _ownerPin = '';
  bool _useBiometricUnlock = false;
  bool _cashierMode = true;
  bool _allowNegativeStock = true;
  bool _allowCashierDiscounts = true;
  bool _autoBackupEnabled = true;
  String _lastAutoBackupAt = '';
  String _lastExternalBackupAt = '';
  String _lastExternalBackupReminderAt = '';
  String _lastAutoBackupError = '';
  int _lastCloudBackupProductsCount = -1;
  int _lastCloudBackupSalesCount = -1;
  bool _bulkDeleteAuthorized = false;
  bool _pendingSync = false;
  final Map<String, String> _cloudBackupHashes = {};
  final Map<String, String> _sheetCatalogBaseline = {};
  Timer? _autoBackupTimer;
  bool _autoBackupInProgress = false;
  bool _autoBackupPending = false;
  bool _suppressAutoBackup = false;
  bool _sheetPullInProgress = false;
  DateTime? _lastSheetPullAt;
  String _lastSheetSyncNotice = '';
  bool _lastSheetSyncIsError = false;
  int _syncNoticeVersion = 0;
  bool _catalogSeeded = false;
  String _googleSheetsUrl = '';
  String _googleSheetsSecret = '';
  final List<String> _customCategories = [];
  final Set<String> _hiddenCustomerSuggestions = {};
  StockInDraft? _stockInDraft;
  StocktakeDraft? _stocktakeDraft;
  final List<HeldSale> _heldSales = [];
  final List<ProductChangeEntry> _productChanges = [];
  final Map<String, int> _negativeStockReminders = {};
  final List<InventoryValueSnapshot> _inventorySnapshots = [];
  final Map<String, FeatureUsageStat> _featureUsage = {};
  int _trashRetentionDays = 30;
  String _inventorySelectedCategory = '';
  String _inventorySort = 'newest';
  String _posSelectedCategory = '';
  final List<String> _sellers = [];
  String _activeSeller = '';
  final List<String> _priceTagQueue = [];
  final List<CashDrawerMovement> _cashDrawerMovements = [];
  Timer? _usageSaveTimer;
  bool _hasPreRestoreBackup = false;
  DateTime? _preRestoreBackupAt;
  String _lastDailyLocalBackupDate = '';
  bool _dailyLocalBackupInProgress = false;
  bool _isLoaded = false;
  bool _archiveAndTrashLoaded = false;
  bool _allSalesLoaded = false;
  int _idCounter = 0;
  List<DailyProductAdvice>? _cachedDailyAdvices;
  String _cachedDailyAdvicesKey = '';
  Map<String, double>? _cachedSoldUnitsByProduct;
  Map<String, int>? _cachedDaysOfStockLeft;
  ({double units, double costValue, double sellValue, List<Product> lowStock})?
      _cachedInventoryTotals;
  Map<String, Map<String, int>>? _cachedCoOccurrence;
  int _cachedCoOccurrenceSalesCount = -1;
  String _cachedCoOccurrenceTopSaleId = '';

  @override
  void notifyListeners() {
    _cachedDailyAdvices = null;
    _cachedSoldUnitsByProduct = null;
    _cachedDaysOfStockLeft = null;
    _cachedInventoryTotals = null;
    super.notifyListeners();
  }

  bool get hasPreRestoreBackup => _hasPreRestoreBackup;
  DateTime? get preRestoreBackupAt => _preRestoreBackupAt;
  bool get isLoaded => _isLoaded;
  bool get archiveAndTrashLoaded => _archiveAndTrashLoaded;
  bool get allSalesLoaded => _allSalesLoaded;

  Future<void> ensureArchiveAndTrashLoaded() async {
    if (_archiveAndTrashLoaded) return;
    final loaded = await _storage.loadArchiveAndTrash();
    _archiveAndTrashLoaded = true;
    var changed = false;
    final prodIds = _products.map((p) => p.id).toSet();
    for (final p in loaded.products) {
      if (prodIds.add(p.id)) {
        _products.add(p);
        changed = true;
      }
    }
    final saleIds = _sales.map((s) => s.id).toSet();
    for (final s in loaded.sales) {
      if (saleIds.add(s.id)) {
        _sales.add(s);
        changed = true;
      }
    }
    final expIds = _expenses.map((e) => e.id).toSet();
    for (final e in loaded.expenses) {
      if (expIds.add(e.id)) {
        _expenses.add(e);
        changed = true;
      }
    }
    if (changed) {
      _sales.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _expenses.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      purgeExpiredTrash();
      notifyListeners();
    }
  }

  Future<void> ensureAllSalesLoaded() async {
    if (_allSalesLoaded) return;
    final loadedSales = await _storage.loadAllActiveSales();
    _allSalesLoaded = true;
    final saleIds = _sales.map((s) => s.id).toSet();
    var changed = false;
    for (final s in loadedSales) {
      if (saleIds.add(s.id)) {
        _sales.add(s);
        changed = true;
      }
    }
    if (changed) {
      _sales.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }
  }

  Future<void> ensureFullHistoryLoaded() async {
    await ensureArchiveAndTrashLoaded();
    await ensureAllSalesLoaded();
  }
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
  bool get useBiometricUnlock => _useBiometricUnlock;
  bool get hasOwnerAuth => _ownerPin.isNotEmpty || _useBiometricUnlock;
  bool get cashierMode => _cashierMode;
  bool get allowNegativeStock => _allowNegativeStock;
  bool get canSellNegativeStock => _allowNegativeStock && !_cashierMode;
  bool get allowCashierDiscounts => _allowCashierDiscounts;
  bool get canGiveDiscounts => !_cashierMode || _allowCashierDiscounts;
  bool get autoBackupEnabled => _autoBackupEnabled;
  String get lastAutoBackupAt => _lastAutoBackupAt;
  String get lastExternalBackupAt => _lastExternalBackupAt;
  bool get shouldPromptExternalBackup {
    if (!_isLoaded || _cashierMode) return false;
    if (_products.isEmpty && _sales.isEmpty) return false;
    final now = DateTime.now();
    final lastBackup = DateTime.tryParse(_lastExternalBackupAt);
    if (lastBackup != null &&
        now.difference(lastBackup) < const Duration(days: 7)) {
      return false;
    }
    final lastPrompt = DateTime.tryParse(_lastExternalBackupReminderAt);
    if (lastPrompt != null &&
        now.difference(lastPrompt) < const Duration(days: 7)) {
      return false;
    }
    return true;
  }
  bool get autoBackupInProgress => _autoBackupInProgress;
  bool get sheetPullInProgress => _sheetPullInProgress;
  bool get isSyncing => _sheetPullInProgress || _autoBackupInProgress;
  String get lastAutoBackupError => _lastAutoBackupError;
  int get lastCloudBackupProductsCount => _lastCloudBackupProductsCount;
  int get lastCloudBackupSalesCount => _lastCloudBackupSalesCount;
  bool get isBulkDeleteAuthorized => _bulkDeleteAuthorized;
  bool get pendingSync => _pendingSync;
  String get lastSheetSyncNotice => _lastSheetSyncNotice;
  bool get lastSheetSyncIsError => _lastSheetSyncIsError;
  int get syncNoticeVersion => _syncNoticeVersion;
  DateTime? get lastSheetPullAt => _lastSheetPullAt;
  String get googleSheetsUrl => _googleSheetsUrl;
  String get googleSheetsSecret => _googleSheetsSecret;

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
  List<String> get sellers => List.unmodifiable(_sellers);
  String get activeSeller => _activeSeller;
  List<String> get priceTagQueue => List.unmodifiable(_priceTagQueue);
  List<Product> get priceTagQueueProducts {
    final result = <Product>[];
    for (final id in _priceTagQueue) {
      final p = findProductById(id);
      if (p != null && p.isActive) {
        result.add(p);
      }
    }
    return result;
  }

  List<CashDrawerMovement> get cashDrawerMovements =>
      List.unmodifiable(_cashDrawerMovements);

  List<CashDrawerMovement> get todayCashDrawerMovements {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return _cashDrawerMovements
        .where((m) => !m.createdAt.isBefore(start) && m.createdAt.isBefore(end))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  double get todayCashDepositsTotal => todayCashDrawerMovements
      .where((m) => m.isDeposit)
      .fold(0.0, (sum, m) => sum + m.amount);

  double get todayCashWithdrawalsTotal => todayCashDrawerMovements
      .where((m) => !m.isDeposit)
      .fold(0.0, (sum, m) => sum + m.amount);
  List<String> get recentCustomerNames {
    final seen = <String>{};
    final result = <String>[];
    for (final c in _customers) {
      final name = c.name.trim();
      final lower = name.toLowerCase();
      if (name.isNotEmpty &&
          !_hiddenCustomerSuggestions.contains(lower) &&
          seen.add(lower)) {
        result.add(name);
      }
    }
    for (final s in sales) {
      final name = s.customerName.trim();
      final lower = name.toLowerCase();
      if (name.isNotEmpty &&
          lower != 'unknown' &&
          !_hiddenCustomerSuggestions.contains(lower) &&
          seen.add(lower)) {
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
  List<ProductChangeEntry> get productChanges =>
      List.unmodifiable(_productChanges);
  List<InventoryValueSnapshot> get inventorySnapshots =>
      List.unmodifiable(_inventorySnapshots);
  Map<String, FeatureUsageStat> get featureUsage =>
      Map.unmodifiable(_featureUsage);
  int get totalFeatureUsageCount =>
      _featureUsage.values.fold(0, (sum, stat) => sum + stat.count);

  int get archiveCount => archivedProducts.length + archivedSales.length;
  int get trashCount =>
      trashedProducts.length + trashedSales.length + trashedExpenses.length;
  int get trashRetentionDays => _trashRetentionDays;
  String get inventorySelectedCategory => _inventorySelectedCategory;
  String get inventorySort => _inventorySort;
  String get posSelectedCategory => _posSelectedCategory;

  String _nextId(String prefix) {
    _idCounter += 1;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  Future<void> _refreshPreRestoreStatus() async {
    final backup = await _storage.loadPreRestoreBackup();
    _hasPreRestoreBackup = backup != null;
    _preRestoreBackupAt = backup?.savedAt;
  }

  Future<void> initialize() async {
    final snapshot = await _storage.load();
    _applySnapshot(snapshot);
    await _refreshPreRestoreStatus();
    var needsPersist = false;
    if (!_catalogSeeded) {
      _catalogSeeded = true;
      needsPersist = true;
    }
    if (_captureCurrentMonthSnapshotIfMissing()) {
      needsPersist = true;
    }
    if (purgeExpiredTrash() > 0) {
      needsPersist = true;
    }
    if (needsPersist) {
      await _persist();
    }
    _isLoaded = true;
    notifyListeners();
    _maybeSaveDailyLocalBackup();
    if (_autoBackupEnabled && _googleSheetsUrl.trim().isNotEmpty) {
      syncFromSheetInBackground(force: true);
    }
  }

  void _applySnapshot(
    ShopDataSnapshot snapshot, {
    bool includeSettings = true,
  }) {
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
    if (includeSettings) {
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
      _useBiometricUnlock = snapshot.useBiometricUnlock;
      _cashierMode = snapshot.cashierMode;
      _allowNegativeStock = snapshot.allowNegativeStock;
      _allowCashierDiscounts = snapshot.allowCashierDiscounts;
      _autoBackupEnabled = snapshot.autoBackupEnabled;
      _lastAutoBackupAt = snapshot.lastAutoBackupAt;
      _lastExternalBackupAt = snapshot.lastExternalBackupAt;
      _lastExternalBackupReminderAt = snapshot.lastExternalBackupReminderAt;
      _lastCloudBackupProductsCount = snapshot.lastCloudBackupProductsCount;
      _lastCloudBackupSalesCount = snapshot.lastCloudBackupSalesCount;
      _bulkDeleteAuthorized = false;
      _pendingSync = snapshot.pendingSync;
      _cloudBackupHashes
        ..clear()
        ..addAll(snapshot.cloudBackupHashes);
      _sheetCatalogBaseline
        ..clear()
        ..addAll(snapshot.sheetCatalogBaseline);
      _googleSheetsUrl = snapshot.googleSheetsUrl;
      _googleSheetsSecret = snapshot.googleSheetsSecret;
    }
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
    _hiddenCustomerSuggestions
      ..clear()
      ..addAll(
        snapshot.hiddenCustomerSuggestions
            .map((c) => c.trim().toLowerCase())
            .where((c) => c.isNotEmpty),
      );
    _stockInDraft = snapshot.stockInDraft;
    _stocktakeDraft = snapshot.stocktakeDraft;
    _heldSales
      ..clear()
      ..addAll(snapshot.heldSales);
    _heldSales.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final memoryCutoff =
        DateTime.now().subtract(const Duration(days: inMemoryChangeHistoryDays));
    _productChanges
      ..clear()
      ..addAll(
        snapshot.productChanges.where((e) => !e.createdAt.isBefore(memoryCutoff)),
      );
    _productChanges.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _negativeStockReminders
      ..clear()
      ..addAll(snapshot.negativeStockReminders);
    _pruneResolvedNegativeReminders();
    final dedupedSnaps = <String, InventoryValueSnapshot>{};
    for (final s in snapshot.inventorySnapshots) {
      final existing = dedupedSnaps[s.monthKey];
      if (existing == null || s.capturedAt.isAfter(existing.capturedAt)) {
        dedupedSnaps[s.monthKey] = s;
      }
    }
    _inventorySnapshots
      ..clear()
      ..addAll(dedupedSnaps.values)
      ..sort((a, b) => b.monthKey.compareTo(a.monthKey));
    if (includeSettings) {
      _featureUsage
        ..clear()
        ..addAll(snapshot.featureUsage);
      _trashRetentionDays =
          snapshot.trashRetentionDays < 0 ? 30 : snapshot.trashRetentionDays;
      _inventorySelectedCategory = snapshot.inventorySelectedCategory;
      _inventorySort = snapshot.inventorySort.isNotEmpty
          ? snapshot.inventorySort
          : 'newest';
      _posSelectedCategory = snapshot.posSelectedCategory;
      _sellers
        ..clear()
        ..addAll(snapshot.sellers);
      _activeSeller = snapshot.activeSeller;
      _priceTagQueue
        ..clear()
        ..addAll(snapshot.priceTagQueue);
      _cashDrawerMovements
        ..clear()
        ..addAll(snapshot.cashDrawerMovements);
    }
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
      useBiometricUnlock: _useBiometricUnlock,
      cashierMode: _cashierMode,
      catalogSeeded: _catalogSeeded,
      googleSheetsUrl: _googleSheetsUrl,
      googleSheetsSecret: _googleSheetsSecret,
      customCategories: List.unmodifiable(_customCategories),
      hiddenCustomerSuggestions: List.unmodifiable(_hiddenCustomerSuggestions),
      stockInDraft: _stockInDraft,
      stocktakeDraft: _stocktakeDraft,
      heldSales: List.unmodifiable(_heldSales),
      productChanges: List.unmodifiable(_productChanges),
      negativeStockReminders: Map.unmodifiable(_negativeStockReminders),
      allowNegativeStock: _allowNegativeStock,
      allowCashierDiscounts: _allowCashierDiscounts,
      autoBackupEnabled: _autoBackupEnabled,
      lastAutoBackupAt: _lastAutoBackupAt,
      lastExternalBackupAt: _lastExternalBackupAt,
      lastExternalBackupReminderAt: _lastExternalBackupReminderAt,
      lastCloudBackupProductsCount: _lastCloudBackupProductsCount,
      lastCloudBackupSalesCount: _lastCloudBackupSalesCount,
      pendingSync: _pendingSync,
      cloudBackupHashes: Map.unmodifiable(_cloudBackupHashes),
      sheetCatalogBaseline: Map.unmodifiable(_sheetCatalogBaseline),
      inventorySnapshots: List.unmodifiable(_inventorySnapshots),
      featureUsage: Map.unmodifiable(_featureUsage),
      trashRetentionDays: _trashRetentionDays,
      inventorySelectedCategory: _inventorySelectedCategory,
      inventorySort: _inventorySort,
      posSelectedCategory: _posSelectedCategory,
      sellers: List.unmodifiable(_sellers),
      activeSeller: _activeSeller,
      priceTagQueue: List.unmodifiable(_priceTagQueue),
      cashDrawerMovements: List.unmodifiable(_cashDrawerMovements),
    );
  }

  Future<void> markPriceTagPrinted(String productId) async {
    if (!_priceTagQueue.remove(productId)) return;
    notifyListeners();
    await _storage.save(createBackupSnapshot());
  }

  Future<void> clearPriceTagQueue() async {
    if (_priceTagQueue.isEmpty) return;
    _priceTagQueue.clear();
    notifyListeners();
    await _storage.save(createBackupSnapshot());
  }

  Future<void> addCashDrawerMovement({
    required bool isDeposit,
    required double amount,
    String note = '',
  }) async {
    if (amount <= 0) return;
    final movement = CashDrawerMovement(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_cashDrawerMovements.length}',
      isDeposit: isDeposit,
      amount: amount,
      note: note.trim(),
      sellerName: _activeSeller,
      createdAt: DateTime.now(),
    );
    _cashDrawerMovements.insert(0, movement);
    if (_cashDrawerMovements.length > 500) {
      _cashDrawerMovements.removeRange(500, _cashDrawerMovements.length);
    }
    notifyListeners();
    await _storage.save(createBackupSnapshot());
  }

  Future<void> deleteCashDrawerMovement(String id) async {
    final before = _cashDrawerMovements.length;
    _cashDrawerMovements.removeWhere((m) => m.id == id);
    if (_cashDrawerMovements.length == before) return;
    notifyListeners();
    await _storage.save(createBackupSnapshot());
  }

  Future<void> setActiveSeller(String name) async {
    final clean = InputNormalizer.normalizeDisplayName(name);
    if (_activeSeller == clean) return;
    _activeSeller = clean;
    notifyListeners();
    await _storage.save(createBackupSnapshot());
  }

  Future<void> addSeller(String name) async {
    final clean = InputNormalizer.normalizeDisplayName(name);
    if (clean.isEmpty) return;
    final exists = _sellers.any((s) => s.toLowerCase() == clean.toLowerCase());
    if (!exists) {
      _sellers.add(clean);
    }
    _activeSeller = clean;
    notifyListeners();
    await _storage.save(createBackupSnapshot());
  }

  Future<void> removeSeller(String name) async {
    final clean = name.trim().toLowerCase();
    final before = _sellers.length;
    _sellers.removeWhere((s) => s.toLowerCase() == clean);
    if (_activeSeller.toLowerCase() == clean) {
      _activeSeller = '';
    }
    if (_sellers.length != before || _activeSeller.isEmpty) {
      notifyListeners();
      await _storage.save(createBackupSnapshot());
    }
  }

  Future<void> setInventoryViewPreferences({
    String? category,
    bool updateCategory = false,
    String? sort,
  }) async {
    var changed = false;
    if (updateCategory) {
      final clean = (category ?? '').trim();
      if (_inventorySelectedCategory != clean) {
        _inventorySelectedCategory = clean;
        changed = true;
      }
    }
    if (sort != null && sort.isNotEmpty && _inventorySort != sort) {
      _inventorySort = sort;
      changed = true;
    }
    if (!changed) return;
    await _storage.save(createBackupSnapshot());
  }

  Future<void> setPosSelectedCategory(String? category) async {
    final clean = (category ?? '').trim();
    if (_posSelectedCategory == clean) return;
    _posSelectedCategory = clean;
    await _storage.save(createBackupSnapshot());
  }

  Future<HeldSale?> holdCurrentCart({String label = ''}) async {
    if (_cart.isEmpty) return null;
    final held = HeldSale(
      id: _nextId('hld'),
      label: label.trim(),
      quantities: Map<String, double>.from(_cart),
      createdAt: DateTime.now(),
    );
    _heldSales.insert(0, held);
    _cart.clear();
    _cartCustomPrices.clear();
    _wholesaleDisabledProducts.clear();
    _incrementFeatureUsageInMemory(FeatureUsageKeys.holdSale);
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
          quantities: Map<String, double>.from(_cart),
          createdAt: DateTime.now(),
        ),
      );
    }
    _cart.clear();
    _cartCustomPrices.clear();
    _wholesaleDisabledProducts.clear();
    for (final entry in held.quantities.entries) {
      final product = findProductById(entry.key);
      if (product == null || !product.isActive) continue;
      if (entry.value > 0) {
        _cart[product.id] = entry.value;
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

  Future<double> addProductToStockInDraft(
    Product product, {
    double delta = 1,
  }) async {
    final existing = _stockInDraft;
    final quantities = Map<String, double>.from(existing?.quantities ?? const {});
    final unitCosts = Map<String, double>.from(existing?.unitCosts ?? const {});
    final sellPrices = Map<String, double>.from(existing?.sellPrices ?? const {});
    final nextQty = ((quantities[product.id] ?? 0) + delta).clamp(0.0, 999999.0);
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

  Future<void> restoreFromSnapshot(
    ShopDataSnapshot snapshot, {
    bool includeSettings = true,
  }) async {
    // Hard rule: always save an automatic pre-restore snapshot of the current
    // state before overwriting anything, so the owner can roll back on error.
    await ensureFullHistoryLoaded();
    await _storage.savePreRestoreBackup(createBackupSnapshot());
    _hasPreRestoreBackup = true;
    _preRestoreBackupAt = DateTime.now();

    final prevUrl = _googleSheetsUrl;
    final prevSecret = _googleSheetsSecret;
    _applySnapshot(snapshot, includeSettings: includeSettings);
    _archiveAndTrashLoaded = true;
    _allSalesLoaded = true;
    if (includeSettings) {
      if (_googleSheetsUrl.isEmpty && prevUrl.isNotEmpty) {
        _googleSheetsUrl = prevUrl;
      }
      if (_googleSheetsSecret.isEmpty && prevSecret.isNotEmpty) {
        _googleSheetsSecret = prevSecret;
      }
    }
    _cart.clear();
    _cartCustomPrices.clear();
    _pendingSync = false;
    notifyListeners();
    _suppressAutoBackup = true;
    try {
      await _persist();
    } finally {
      _suppressAutoBackup = false;
    }
  }

  Future<bool> rollbackToPreRestoreBackup() async {
    final backup = await _storage.loadPreRestoreBackup();
    if (backup == null) {
      _hasPreRestoreBackup = false;
      _preRestoreBackupAt = null;
      notifyListeners();
      return false;
    }
    _applySnapshot(backup.snapshot, includeSettings: true);
    _cart.clear();
    _cartCustomPrices.clear();
    _pendingSync = false;
    notifyListeners();
    _suppressAutoBackup = true;
    try {
      await _persist();
    } finally {
      _suppressAutoBackup = false;
    }
    return true;
  }

  List<({Product product, int remaining})> get activeNegativeStockReminders {
    final result = <({Product product, int remaining})>[];
    for (final entry in _negativeStockReminders.entries) {
      if (entry.value <= 0) continue;
      final product = findProductById(entry.key);
      if (product != null && product.isActive && product.stock < 0) {
        result.add((product: product, remaining: entry.value));
      }
    }
    return result;
  }

  int get negativeStockProductsCount =>
      products.where((p) => p.stock < 0).length;

  void _pruneResolvedNegativeReminders() {
    _negativeStockReminders.removeWhere((id, remaining) {
      if (remaining <= 0) return true;
      final p = findProductById(id);
      return p == null || !p.isActive || p.stock >= 0;
    });
  }

  bool _openStockInRequested = false;
  bool get openStockInRequested => _openStockInRequested;

  void requestOpenStockIn() {
    _openStockInRequested = true;
    notifyListeners();
  }

  void clearOpenStockInRequest() {
    _openStockInRequested = false;
  }

  Future<int> prepareStockInForNegativeProducts() async {
    final negativeProducts = products.where((p) => p.stock < 0).toList();
    if (negativeProducts.isEmpty) return 0;

    final existing = _stockInDraft;
    final quantities = Map<String, double>.from(existing?.quantities ?? const {});
    final unitCosts = Map<String, double>.from(existing?.unitCosts ?? const {});
    final sellPrices = Map<String, double>.from(existing?.sellPrices ?? const {});

    for (final p in negativeProducts) {
      final needed = -p.stock;
      final current = quantities[p.id] ?? 0;
      if (current < needed) {
        quantities[p.id] = needed;
      }
      unitCosts.putIfAbsent(p.id, () => p.costPrice);
      sellPrices.putIfAbsent(p.id, () => p.sellPrice);
    }

    await saveStockInDraft(
      StockInDraft(
        supplierName: existing?.supplierName ?? '',
        recordAsExpense: true,
        quantities: quantities,
        unitCosts: unitCosts,
        sellPrices: sellPrices,
      ),
    );
    return negativeProducts.length;
  }

  Future<void> acknowledgeNegativeStockReminders() async {
    _pruneResolvedNegativeReminders();
    if (_negativeStockReminders.isEmpty) return;
    final keys = _negativeStockReminders.keys.toList();
    for (final id in keys) {
      final next = (_negativeStockReminders[id] ?? 0) - 1;
      if (next <= 0) {
        _negativeStockReminders.remove(id);
      } else {
        _negativeStockReminders[id] = next;
      }
    }
    notifyListeners();
    await _persist();
  }

  static String currentMonthKey([DateTime? dt]) {
    final d = dt ?? DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  }

  InventoryValueSnapshot _buildCurrentInventorySnapshot([DateTime? now]) {
    final ts = now ?? DateTime.now();
    final active = products;
    return InventoryValueSnapshot(
      monthKey: currentMonthKey(ts),
      capturedAt: ts,
      productsCount: active.length,
      totalUnits: totalStockUnits,
      costValue: totalInventoryCostValue,
      sellValue: totalPotentialRevenue,
    );
  }

  bool _captureCurrentMonthSnapshotIfMissing() {
    if (products.isEmpty) return false;
    final key = currentMonthKey();
    if (_inventorySnapshots.any((s) => s.monthKey == key)) return false;
    _inventorySnapshots.add(_buildCurrentInventorySnapshot());
    _inventorySnapshots.sort((a, b) => b.monthKey.compareTo(a.monthKey));
    return true;
  }

  Future<InventoryValueSnapshot> captureMonthlyInventorySnapshot({
    bool forceUpdateCurrentMonth = true,
  }) async {
    final snap = _buildCurrentInventorySnapshot();
    final idx =
        _inventorySnapshots.indexWhere((s) => s.monthKey == snap.monthKey);
    if (idx != -1) {
      if (!forceUpdateCurrentMonth) return _inventorySnapshots[idx];
      _inventorySnapshots[idx] = snap;
    } else {
      _inventorySnapshots.add(snap);
    }
    _inventorySnapshots.sort((a, b) => b.monthKey.compareTo(a.monthKey));
    notifyListeners();
    await _persist();
    return snap;
  }

  void _incrementFeatureUsageInMemory(String key) {
    final clean = key.trim();
    if (clean.isEmpty) return;
    final prev = _featureUsage[clean];
    _featureUsage[clean] = FeatureUsageStat(
      count: (prev?.count ?? 0) + 1,
      lastUsedAt: DateTime.now(),
    );
  }

  /// Tracks a screen/button tap locally without triggering Google Sheets sync.
  void trackFeatureUsage(String key) {
    _incrementFeatureUsageInMemory(key);
    _usageSaveTimer?.cancel();
    _usageSaveTimer = Timer(const Duration(seconds: 3), () {
      _storage.save(createBackupSnapshot());
    });
  }

  Future<void> clearFeatureUsage() async {
    _usageSaveTimer?.cancel();
    _featureUsage.clear();
    notifyListeners();
    await _storage.save(createBackupSnapshot());
  }

  void _maybeSaveDailyLocalBackup() {
    if (_dailyLocalBackupInProgress) return;
    if (_products.isEmpty && _sales.isEmpty && _expenses.isEmpty) return;
    final now = DateTime.now();
    final todayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (_lastDailyLocalBackupDate == todayKey) return;
    _dailyLocalBackupInProgress = true;
    final snapshot = createBackupSnapshot();
    _dailyBackupService.saveDailyBackupIfNeeded(snapshot, now: now).then((_) {
      _lastDailyLocalBackupDate = todayKey;
    }).catchError((Object e) {
      debugPrint('Daily local backup error: $e');
    }).whenComplete(() {
      _dailyLocalBackupInProgress = false;
    });
  }

  Future<List<DailyBackupEntry>> listDailyLocalBackups() =>
      _dailyBackupService.listBackups();

  Future<bool> createDailyLocalBackupNow() async {
    final now = DateTime.now();
    final saved = await _dailyBackupService.saveDailyBackupIfNeeded(
      createBackupSnapshot(),
      now: now,
      force: true,
    );
    if (saved) {
      _lastDailyLocalBackupDate =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }
    return saved;
  }

  Future<bool> restoreFromDailyLocalBackup(
    DailyBackupEntry entry, {
    bool includeSettings = false,
  }) async {
    final snapshot = await _dailyBackupService.loadBackup(entry);
    if (snapshot == null) return false;
    await restoreFromSnapshot(snapshot, includeSettings: includeSettings);
    return true;
  }

  Future<void> _persist() async {
    _usageSaveTimer?.cancel();
    _pruneResolvedNegativeReminders();
    _captureCurrentMonthSnapshotIfMissing();
    final shouldAutoSync = !_suppressAutoBackup &&
        _autoBackupEnabled &&
        _googleSheetsUrl.trim().isNotEmpty;
    if (shouldAutoSync && !_pendingSync) {
      _pendingSync = true;
      notifyListeners();
    }
    await _storage.save(createBackupSnapshot());
    if (!_suppressAutoBackup) {
      _maybeSaveDailyLocalBackup();
    }
    if (shouldAutoSync) {
      _scheduleAutoBackup();
    }
  }

  void _scheduleAutoBackup() {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = Timer(const Duration(milliseconds: 1500), () {
      _runAutoBackupSilently();
    });
  }

  void flushAutoBackupIfPending() {
    if (_usageSaveTimer?.isActive == true) {
      _usageSaveTimer?.cancel();
      _storage.save(createBackupSnapshot());
    }
    if (_autoBackupTimer?.isActive == true) {
      _autoBackupTimer?.cancel();
      _runAutoBackupSilently();
    }
  }

  Future<void> _runAutoBackupSilently() async {
    if (!_autoBackupEnabled || _googleSheetsUrl.trim().isEmpty) return;
    if (_autoBackupInProgress) {
      _autoBackupPending = true;
      return;
    }
    _autoBackupInProgress = true;
    _lastAutoBackupError = '';
    notifyListeners();
    try {
      await syncCloudBackupDelta(forceFull: false);
    } on CloudBackupShrinkException catch (e) {
      debugPrint('Auto-backup shrink blocked: $e');
      _lastAutoBackupError = '$e';
      _lastSheetSyncNotice = '$e';
      _lastSheetSyncIsError = true;
      _syncNoticeVersion += 1;
    } on CloudTimestampConflictException catch (e) {
      debugPrint('Auto-backup timestamp blocked: $e');
      _lastAutoBackupError = '$e';
      _lastSheetSyncNotice = '$e';
      _lastSheetSyncIsError = true;
      _syncNoticeVersion += 1;
    } catch (e, st) {
      debugPrint('Auto-backup error: $e\n$st');
      _lastAutoBackupError = '$e';
    } finally {
      _autoBackupInProgress = false;
      notifyListeners();
      if (_autoBackupPending) {
        _autoBackupPending = false;
        _scheduleAutoBackup();
      }
    }
  }

  String _encodeBaselineProduct(Product p) {
    return jsonEncode({
      'name': p.name.trim(),
      'category': p.category.trim(),
      'sku': p.sku.trim(),
      'nomenclature': p.nomenclature.trim(),
      'printName': p.printName.trim(),
      'packQty': p.packQty.trim(),
      'boxQty': p.boxQty.trim(),
      'packBarcode': p.packBarcode.trim(),
      'boxBarcode': p.boxBarcode.trim(),
      'unitWeight': p.unitWeight.trim(),
      'unit': p.unit.trim(),
      'costPrice': p.costPrice,
      'sellPrice': p.sellPrice,
      'wholesalePrice': p.wholesalePrice,
      'wholesaleMinQty': p.wholesaleMinQty,
      'stock': p.stock,
      'lowStockThreshold': p.lowStockThreshold,
    });
  }

  Map<String, dynamic>? _decodeBaseline(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void recordSheetCatalogBaseline() {
    _sheetCatalogBaseline.clear();
    for (final p in products) {
      _sheetCatalogBaseline[p.id] = _encodeBaselineProduct(p);
    }
  }

  Future<void> syncFromSheetInBackground({bool force = false}) async {
    if (!_autoBackupEnabled || _googleSheetsUrl.trim().isEmpty) return;
    if (_sheetPullInProgress || _autoBackupInProgress) return;
    final now = DateTime.now();
    if (!force &&
        _lastSheetPullAt != null &&
        now.difference(_lastSheetPullAt!) < const Duration(seconds: 20)) {
      return;
    }
    _sheetPullInProgress = true;
    _lastSheetPullAt = now;
    notifyListeners();
    try {
      // Only pull edits made in Google Sheets on app start/resume;
      // never overwrite the sheet automatically on launch.
      final res = await pullCatalogChangesFromSheet(
        pushMergedIfLocalChanged: false,
      );
      _lastAutoBackupError = '';
      if (res.updatedFromSheet > 0 || res.addedFromSheet > 0) {
        _lastSheetSyncNotice = strings.sheetSyncUpdatedNotice(
          res.updatedFromSheet,
          res.addedFromSheet,
        );
        _lastSheetSyncIsError = false;
        _syncNoticeVersion += 1;
      } else if (force) {
        _lastSheetSyncNotice = strings.sheetSyncUpToDateNotice;
        _lastSheetSyncIsError = false;
        _syncNoticeVersion += 1;
      }
    } catch (e, st) {
      debugPrint('Background sheet sync error: $e\n$st');
      _lastAutoBackupError = '$e';
      _lastSheetSyncNotice = strings.sheetSyncErrorNotice('$e');
      _lastSheetSyncIsError = true;
      _syncNoticeVersion += 1;
    } finally {
      _sheetPullInProgress = false;
      notifyListeners();
      if (_pendingSync &&
          _autoBackupEnabled &&
          _googleSheetsUrl.trim().isNotEmpty) {
        _runAutoBackupSilently();
      }
    }
  }

  Future<({int updatedFromSheet, int addedFromSheet})>
      pullCatalogChangesFromSheet({
    bool pushMergedIfLocalChanged = false,
  }) async {
    final url = _googleSheetsUrl.trim();
    if (url.isEmpty) return (updatedFromSheet: 0, addedFromSheet: 0);
    const service = GoogleSheetsService();
    final rawRemoteProducts = await service.fetchProducts(
      url,
      secret: _googleSheetsSecret,
    );
    final remoteProducts =
        GoogleSheetsService.deduplicateProducts(rawRemoteProducts);

    final localActive = products;
    final localById = <String, Product>{for (final p in localActive) p.id: p};
    final localByBarcode = <String, Product>{};
    final localByName = <String, Product>{};
    for (final p in localActive) {
      for (final code in GoogleSheetsService.extractBarcodes(p)) {
        localByBarcode.putIfAbsent(code, () => p);
      }
      final normName = GoogleSheetsService.normalizeName(p.name);
      if (normName.isNotEmpty) {
        localByName.putIfAbsent(normName, () => p);
      }
    }

    final lastBackupTime = DateTime.tryParse(_lastAutoBackupAt);
    final updatedProducts = <Product>[];
    final newProducts = <Product>[];
    final nextBaseline = <String, String>{};
    var anyDiffRemainingBetweenLocalAndSheet = false;

    for (final remote in remoteProducts) {
      Product? local;
      if (remote.id.trim().isNotEmpty && localById.containsKey(remote.id)) {
        local = localById[remote.id];
      }
      if (local == null) {
        for (final code in GoogleSheetsService.extractBarcodes(remote)) {
          if (localByBarcode.containsKey(code)) {
            local = localByBarcode[code];
            break;
          }
        }
      }
      if (local == null) {
        final normName = GoogleSheetsService.normalizeName(remote.name);
        if (normName.isNotEmpty && localByName.containsKey(normName)) {
          local = localByName[normName];
        }
      }

      if (local == null) {
        newProducts.add(remote);
        continue;
      }

      final normalizedRemote = remote.copyWith(id: local.id);
      final base = _decodeBaseline(_sheetCatalogBaseline[local.id]);

      T pickVal<T>(T localVal, T remoteVal, String key) {
        if (localVal == remoteVal) return localVal;
        if (base != null && base.containsKey(key)) {
          final baseVal = base[key];
          final sheetChanged = remoteVal != baseVal;
          final phoneChanged = localVal != baseVal;
          if (sheetChanged && !phoneChanged) return remoteVal;
          return localVal;
        }
        final phoneUntouchedSinceBackup = lastBackupTime == null ||
            !local!.updatedAt.isAfter(
              lastBackupTime.add(const Duration(seconds: 5)),
            );
        return phoneUntouchedSinceBackup ? remoteVal : localVal;
      }

      double pickDouble(double localVal, double remoteVal, String key) {
        if ((localVal - remoteVal).abs() <= 0.009) return localVal;
        if (base != null && base.containsKey(key)) {
          final baseVal = (base[key] as num?)?.toDouble() ?? localVal;
          final sheetChanged = (remoteVal - baseVal).abs() > 0.009;
          final phoneChanged = (localVal - baseVal).abs() > 0.009;
          if (sheetChanged && !phoneChanged) return remoteVal;
          return localVal;
        }
        final phoneUntouchedSinceBackup = lastBackupTime == null ||
            !local!.updatedAt.isAfter(
              lastBackupTime.add(const Duration(seconds: 5)),
            );
        return phoneUntouchedSinceBackup ? remoteVal : localVal;
      }

      final merged = local.copyWith(
        name: pickVal(local.name.trim(), normalizedRemote.name.trim(), 'name'),
        category: pickVal(
          local.category.trim(),
          normalizedRemote.category.trim(),
          'category',
        ),
        sku: pickVal(local.sku.trim(), normalizedRemote.sku.trim(), 'sku'),
        nomenclature: pickVal(
          local.nomenclature.trim(),
          normalizedRemote.nomenclature.trim(),
          'nomenclature',
        ),
        printName: pickVal(
          local.printName.trim(),
          normalizedRemote.printName.trim(),
          'printName',
        ),
        packQty: pickVal(
          local.packQty.trim(),
          normalizedRemote.packQty.trim(),
          'packQty',
        ),
        boxQty: pickVal(
          local.boxQty.trim(),
          normalizedRemote.boxQty.trim(),
          'boxQty',
        ),
        packBarcode: pickVal(
          local.packBarcode.trim(),
          normalizedRemote.packBarcode.trim(),
          'packBarcode',
        ),
        boxBarcode: pickVal(
          local.boxBarcode.trim(),
          normalizedRemote.boxBarcode.trim(),
          'boxBarcode',
        ),
        unitWeight: pickVal(
          local.unitWeight.trim(),
          normalizedRemote.unitWeight.trim(),
          'unitWeight',
        ),
        unit: pickVal(local.unit.trim(), normalizedRemote.unit.trim(), 'unit'),
        costPrice: pickDouble(
          local.costPrice,
          normalizedRemote.costPrice,
          'costPrice',
        ),
        sellPrice: pickDouble(
          local.sellPrice,
          normalizedRemote.sellPrice,
          'sellPrice',
        ),
        wholesalePrice: pickDouble(
          local.wholesalePrice,
          normalizedRemote.wholesalePrice,
          'wholesalePrice',
        ),
        wholesaleMinQty: pickVal(
          local.wholesaleMinQty,
          normalizedRemote.wholesaleMinQty,
          'wholesaleMinQty',
        ),
        stock: pickVal(local.stock, normalizedRemote.stock, 'stock'),
        lowStockThreshold: pickVal(
          local.lowStockThreshold,
          normalizedRemote.lowStockThreshold,
          'lowStockThreshold',
        ),
      );

      final mergedJson = _encodeBaselineProduct(merged);
      nextBaseline[local.id] = mergedJson;
      if (mergedJson != _encodeBaselineProduct(local)) {
        updatedProducts.add(merged);
      }
      if (mergedJson != _encodeBaselineProduct(normalizedRemote)) {
        anyDiffRemainingBetweenLocalAndSheet = true;
      }
    }

    if (updatedProducts.isNotEmpty || newProducts.isNotEmpty) {
      _suppressAutoBackup = true;
      try {
        await applySyncedProducts(
          updatedProducts: updatedProducts,
          newProducts: newProducts,
        );
      } finally {
        _suppressAutoBackup = false;
      }
    }

    for (final p in products) {
      nextBaseline.putIfAbsent(p.id, () => _encodeBaselineProduct(p));
    }
    _sheetCatalogBaseline
      ..clear()
      ..addAll(nextBaseline);

    if (pushMergedIfLocalChanged &&
        products.isNotEmpty &&
        (anyDiffRemainingBetweenLocalAndSheet ||
            remoteProducts.length != products.length)) {
      await service.pushProducts(
        url,
        products,
        secret: _googleSheetsSecret,
      );
      recordSheetCatalogBaseline();
    }

    _suppressAutoBackup = true;
    try {
      await _storage.save(createBackupSnapshot());
    } finally {
      _suppressAutoBackup = false;
    }

    return (
      updatedFromSheet: updatedProducts.length,
      addedFromSheet: newProducts.length,
    );
  }

  CloudBackupShrinkException? detectCloudBackupShrinkAnomaly() {
    final curProducts = products.length;
    final curSales = sales.length;
    final prevProducts = _lastCloudBackupProductsCount;
    final prevSales = _lastCloudBackupSalesCount;

    final productsDropped = prevProducts > 0 &&
        ((prevProducts >= 10 &&
                prevProducts - curProducts >= 5 &&
                curProducts <= prevProducts * 0.5) ||
            curProducts == 0);
    final salesDropped = prevSales > 0 &&
        ((prevSales >= 10 &&
                prevSales - curSales >= 5 &&
                curSales <= prevSales * 0.5) ||
            curSales == 0);

    if (!productsDropped && !salesDropped) return null;
    return CloudBackupShrinkException(
      message: strings.cloudBackupShrinkBlockedMsg(
        prevProducts,
        curProducts,
        prevSales,
        curSales,
      ),
      prevProducts: prevProducts,
      currentProducts: curProducts,
      prevSales: prevSales,
      currentSales: curSales,
    );
  }

  CloudBackupShrinkException? detectRemoteCatalogShrinkAnomaly(
    int remoteProductsCount,
  ) {
    if (remoteProductsCount <= 0) return null;
    final curProducts = products.length;
    final isEmptyOverPopulated = curProducts == 0 && remoteProductsCount > 0;
    final isNearlyEmptyOverPopulated =
        curProducts <= 3 && remoteProductsCount >= 5;
    final isSharpDrop = remoteProductsCount >= 10 &&
        remoteProductsCount - curProducts >= 5 &&
        curProducts <= remoteProductsCount * 0.5;
    if (!isEmptyOverPopulated &&
        !isNearlyEmptyOverPopulated &&
        !isSharpDrop) {
      return null;
    }
    return CloudBackupShrinkException(
      message: strings.remoteCatalogOverwriteBlockedMsg(
        remoteProductsCount,
        curProducts,
      ),
      prevProducts: remoteProductsCount,
      currentProducts: curProducts,
      prevSales:
          _lastCloudBackupSalesCount < 0 ? 0 : _lastCloudBackupSalesCount,
      currentSales: sales.length,
    );
  }

  String _formatConflictTimestamp(DateTime dt) {
    final l = dt.toLocal();
    final d = l.day.toString().padLeft(2, '0');
    final m = l.month.toString().padLeft(2, '0');
    final h = l.hour.toString().padLeft(2, '0');
    final min = l.minute.toString().padLeft(2, '0');
    return '$d.$m.${l.year} $h:$min';
  }

  DateTime? get latestLocalDataAt {
    DateTime? latest = DateTime.tryParse(_lastAutoBackupAt);
    void consider(DateTime? dt) {
      if (dt == null) return;
      if (latest == null || dt.isAfter(latest!)) {
        latest = dt;
      }
    }

    for (final p in _products) {
      consider(p.updatedAt);
    }
    for (final s in _sales) {
      consider(s.createdAt);
      consider(s.paidAt);
    }
    for (final r in _stockIns) {
      consider(r.createdAt);
    }
    for (final e in _expenses) {
      consider(e.createdAt);
    }
    for (final c in _productChanges) {
      consider(c.createdAt);
    }
    return latest;
  }

  CloudTimestampConflictException? detectCloudNewerThanLocal({
    DateTime? remoteBackupUpdatedAt,
    DateTime? remoteCatalogUpdatedAt,
  }) {
    DateTime? effectiveRemote = remoteBackupUpdatedAt;
    if (remoteCatalogUpdatedAt != null &&
        (effectiveRemote == null ||
            remoteCatalogUpdatedAt.isAfter(effectiveRemote))) {
      effectiveRemote = remoteCatalogUpdatedAt;
    }
    if (effectiveRemote == null) return null;

    final localSyncAt = DateTime.tryParse(_lastAutoBackupAt);
    final isStale = localSyncAt == null
        ? remoteBackupUpdatedAt != null
        : effectiveRemote.isAfter(
            localSyncAt.add(const Duration(seconds: 10)),
          );
    if (!isStale) return null;

    final cloudStr = _formatConflictTimestamp(effectiveRemote);
    final localStr = localSyncAt != null
        ? _formatConflictTimestamp(localSyncAt)
        : strings.neverSyncedLabel;
    return CloudTimestampConflictException(
      message: strings.cloudNewerOverwriteBlockedMsg(cloudStr, localStr),
      remoteUpdatedAt: effectiveRemote,
      localLastSyncAt: localSyncAt,
      latestLocalDataAt: latestLocalDataAt,
      isCloudNewer: true,
    );
  }

  CloudTimestampConflictException? detectLocalNewerThanCloud({
    DateTime? remoteBackupUpdatedAt,
  }) {
    if (remoteBackupUpdatedAt == null) return null;
    final localLatest = latestLocalDataAt;
    if (localLatest == null) return null;
    if (!localLatest.isAfter(
      remoteBackupUpdatedAt.add(const Duration(minutes: 1)),
    )) {
      return null;
    }
    return CloudTimestampConflictException(
      message: strings.localNewerRestoreWarningMsg(
        _formatConflictTimestamp(localLatest),
        _formatConflictTimestamp(remoteBackupUpdatedAt),
      ),
      remoteUpdatedAt: remoteBackupUpdatedAt,
      localLastSyncAt: DateTime.tryParse(_lastAutoBackupAt),
      latestLocalDataAt: localLatest,
      isCloudNewer: false,
    );
  }

  Future<void> markCloudCatalogPushed() async {
    _lastAutoBackupAt = DateTime.now().toIso8601String();
    _lastCloudBackupProductsCount = products.length;
    _lastCloudBackupSalesCount = sales.length;
    recordSheetCatalogBaseline();
    notifyListeners();
    _suppressAutoBackup = true;
    try {
      await _storage.save(createBackupSnapshot());
    } finally {
      _suppressAutoBackup = false;
    }
  }

  static const List<SheetExportSection> instantReadableSections = [
    SheetExportSection.sales,
  ];

  static String _dayKey(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  bool isDailySectionsSyncDue({DateTime? now}) {
    final key = _dayKey(now ?? DateTime.now());
    return _cloudBackupHashes['sheet_daily_date'] != key;
  }

  List<SheetExportSection> readableSectionsForSync({
    required bool forceFull,
    DateTime? now,
  }) {
    if (forceFull || isDailySectionsSyncDue(now: now)) {
      return SheetExportSection.values;
    }
    return instantReadableSections;
  }

  void markDailySectionsSynced({DateTime? now}) {
    _cloudBackupHashes['sheet_daily_date'] = _dayKey(now ?? DateTime.now());
  }

  Future<int> syncCloudBackupDelta({
    bool forceFull = false,
    bool syncReadableSheets = true,
    bool allowShrinkOverride = false,
    bool allowTimestampOverride = false,
  }) async {
    final url = _googleSheetsUrl.trim();
    if (url.isEmpty) return 0;
    await ensureFullHistoryLoaded();
    if (!forceFull &&
        products.isEmpty &&
        sales.isEmpty &&
        expenses.isEmpty &&
        customers.isEmpty &&
        stockIns.isEmpty) {
      return 0;
    }
    const service = GoogleSheetsService();
    if (!allowShrinkOverride && !_bulkDeleteAuthorized) {
      final anomaly = detectCloudBackupShrinkAnomaly();
      if (anomaly != null) {
        throw anomaly;
      }
      if (_lastCloudBackupProductsCount < 0 || products.length <= 3) {
        final remoteProducts = await service.fetchProducts(
          url,
          secret: _googleSheetsSecret,
        );
        final remoteAnomaly = detectRemoteCatalogShrinkAnomaly(
          GoogleSheetsService.deduplicateProducts(remoteProducts).length,
        );
        if (remoteAnomaly != null) {
          throw remoteAnomaly;
        }
      }
    }
    if (!allowTimestampOverride) {
      final meta = await service.fetchCloudBackupMeta(
        url,
        secret: _googleSheetsSecret,
      );
      final tsConflict = detectCloudNewerThanLocal(
        remoteBackupUpdatedAt: meta.updatedAt,
        remoteCatalogUpdatedAt: meta.catalogUpdatedAt,
      );
      if (tsConflict != null) {
        throw tsConflict;
      }
    }

    final shouldPullFirst = syncReadableSheets &&
        !forceFull &&
        (_lastSheetPullAt == null ||
            DateTime.now().difference(_lastSheetPullAt!) >
                const Duration(seconds: 60));
    if (shouldPullFirst) {
      try {
        await pullCatalogChangesFromSheet(pushMergedIfLocalChanged: false);
        _lastSheetPullAt = DateTime.now();
      } catch (_) {
        // Proceed with backup even if catalog pull fails transiently.
      }
    }

    final snapshot = createBackupSnapshot();
    final prevBackupHashes = forceFull
        ? const <String, String>{}
        : Map<String, String>.fromEntries(
            _cloudBackupHashes.entries
                .where((e) => !e.key.startsWith('sheet_')),
          );
    final prepared = await compute(
      _prepareCloudBackupDelta,
      (snapshot: snapshot, prevHashes: prevBackupHashes, forceFull: forceFull),
    );

    var totalUpdated = 0;

    final productHashParts = prepared.newHashes.entries
        .where((e) => e.key.startsWith('products_'))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final catalogHash = GoogleSheetsService.hashText(
      productHashParts.map((e) => '${e.key}:${e.value}').join('|'),
    );

    final uploadTasks = <Future<void> Function()>[];

    final hasBackupChanges = forceFull ||
        prepared.changedCompressed.isNotEmpty ||
        prepared.removedSections.isNotEmpty;
    if (hasBackupChanges) {
      uploadTasks.add(() async {
        final sentBackup = await service.pushBackupDelta(
          webAppUrl: url,
          changedCompressedSections: prepared.changedCompressed,
          removedSections: prepared.removedSections,
          resetAll: forceFull,
          secret: _googleSheetsSecret,
        );
        totalUpdated += sentBackup;
        _cloudBackupHashes.removeWhere((k, _) => !k.startsWith('sheet_'));
        _cloudBackupHashes.addAll(prepared.newHashes);
      });
    }

    final syncNow = DateTime.now();
    var dailyMarkedNow = false;
    if (syncReadableSheets) {
      if ((forceFull || _cloudBackupHashes['sheet_catalog'] != catalogHash) &&
          (forceFull || products.isNotEmpty)) {
        final activeProducts = products;
        uploadTasks.add(() async {
          await service.pushProducts(
            url,
            activeProducts,
            secret: _googleSheetsSecret,
          );
          _cloudBackupHashes['sheet_catalog'] = catalogHash;
          recordSheetCatalogBaseline();
          totalUpdated += 1;
        });
      }

      final includeDailySections =
          forceFull || isDailySectionsSyncDue(now: syncNow);
      final targetSections =
          readableSectionsForSync(forceFull: forceFull, now: syncNow);
      for (final section in targetSections) {
        final table = SheetExportHelper.buildTable(section, this);
        final tableHash = GoogleSheetsService.hashText(jsonEncode(table.rows));
        final hashKey = 'sheet_${section.name}';
        if (forceFull || _cloudBackupHashes[hashKey] != tableHash) {
          final tabName = SheetExportHelper.defaultTabName(section, strings);
          uploadTasks.add(() async {
            await service.pushTable(
              webAppUrl: url,
              sheetName: tabName,
              headers: table.headers,
              rows: table.rows,
              secret: _googleSheetsSecret,
            );
            _cloudBackupHashes[hashKey] = tableHash;
            totalUpdated += 1;
          });
        }
      }

      const maxParallel = 4;
      for (var i = 0; i < uploadTasks.length; i += maxParallel) {
        final end = (i + maxParallel < uploadTasks.length)
            ? i + maxParallel
            : uploadTasks.length;
        await Future.wait(uploadTasks.sublist(i, end).map((t) => t()));
      }
      if (includeDailySections) {
        markDailySectionsSynced(now: syncNow);
        dailyMarkedNow = true;
      }
    } else {
      for (final task in uploadTasks) {
        await task();
      }
      _cloudBackupHashes['sheet_catalog'] = catalogHash;
      for (final section in SheetExportSection.values) {
        final table = SheetExportHelper.buildTable(section, this);
        _cloudBackupHashes['sheet_${section.name}'] =
            GoogleSheetsService.hashText(jsonEncode(table.rows));
      }
      markDailySectionsSynced(now: syncNow);
      dailyMarkedNow = true;
    }

    _lastAutoBackupError = '';
    final shouldSaveMeta = totalUpdated > 0 ||
        forceFull ||
        dailyMarkedNow ||
        _lastCloudBackupProductsCount < 0 ||
        _pendingSync;
    if (shouldSaveMeta) {
      _lastCloudBackupProductsCount = products.length;
      _lastCloudBackupSalesCount = sales.length;
      _bulkDeleteAuthorized = false;
      _pendingSync = false;
      if (totalUpdated > 0 || forceFull) {
        _lastAutoBackupAt = DateTime.now().toIso8601String();
      }
      notifyListeners();
      _suppressAutoBackup = true;
      try {
        await _storage.save(createBackupSnapshot());
      } finally {
        _suppressAutoBackup = false;
      }
    }
    return totalUpdated;
  }

  Future<void> setAutoBackupEnabled(bool value) async {
    if (_autoBackupEnabled == value) return;
    _autoBackupEnabled = value;
    notifyListeners();
    await _persist();
  }

  Future<void> markExternalBackupSaved() async {
    final nowIso = DateTime.now().toIso8601String();
    _lastExternalBackupAt = nowIso;
    _lastExternalBackupReminderAt = nowIso;
    notifyListeners();
    await _persist();
  }

  Future<void> snoozeExternalBackupReminder() async {
    _lastExternalBackupReminderAt = DateTime.now().toIso8601String();
    await _persist();
  }

  @override
  void dispose() {
    _usageSaveTimer?.cancel();
    _autoBackupTimer?.cancel();
    super.dispose();
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

  Future<void> setUseBiometricUnlock(bool value) async {
    if (_useBiometricUnlock == value) return;
    _useBiometricUnlock = value;
    notifyListeners();
    await _persist();
  }

  Future<void> enterCashierMode() async {
    if (_cashierMode) return;
    _cashierMode = true;
    notifyListeners();
    await _persist();
  }

  Future<void> unlockOwnerByBiometrics() async {
    if (!_cashierMode) return;
    _cashierMode = false;
    notifyListeners();
    await _persist();
  }

  bool verifyOwnerPin(String pinAttempt) {
    if (_ownerPin.isEmpty) return false;
    return pinAttempt.trim() == _ownerPin;
  }

  bool _canMutateOrDeleteSale(String? ownerPinAttempt) {
    if (!_cashierMode) return true;
    if (ownerPinAttempt == null) return false;
    return verifyOwnerPin(ownerPinAttempt);
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

  Future<void> resetOwnerPinAndUnlock() async {
    _ownerPin = '';
    _cashierMode = false;
    notifyListeners();
    await _persist();
  }

  Future<void> setAllowNegativeStock(bool value) async {
    if (_allowNegativeStock == value) return;
    _allowNegativeStock = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setAllowCashierDiscounts(bool value) async {
    if (_allowCashierDiscounts == value) return;
    _allowCashierDiscounts = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setGoogleSheetsConfig({
    required String url,
    required String secret,
  }) async {
    _googleSheetsUrl = url.trim();
    _googleSheetsSecret = secret.trim();
    notifyListeners();
    await _persist();
  }

  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  void _recordProductChange(
    Product before,
    Product after,
    String source, {
    DateTime? now,
  }) {
    final fields = <ProductChangeField>[];
    if ((before.sellPrice - after.sellPrice).abs() > 0.009) {
      fields.add(
        ProductChangeField(
          key: 'sellPrice',
          kind: 'price',
          label: strings.sellShort,
          oldValue: _fmtNum(before.sellPrice),
          newValue: _fmtNum(after.sellPrice),
        ),
      );
    }
    if ((before.costPrice - after.costPrice).abs() > 0.009) {
      fields.add(
        ProductChangeField(
          key: 'costPrice',
          kind: 'price',
          label: strings.costShort,
          oldValue: _fmtNum(before.costPrice),
          newValue: _fmtNum(after.costPrice),
        ),
      );
    }
    if ((before.wholesalePrice - after.wholesalePrice).abs() > 0.009) {
      fields.add(
        ProductChangeField(
          key: 'wholesalePrice',
          kind: 'price',
          label: strings.wholesaleShort,
          oldValue: _fmtNum(before.wholesalePrice),
          newValue: _fmtNum(after.wholesalePrice),
        ),
      );
    }
    if (before.wholesaleMinQty != after.wholesaleMinQty) {
      fields.add(
        ProductChangeField(
          key: 'wholesaleMinQty',
          kind: 'other',
          label: strings.wholesaleMinQtyLabel,
          oldValue: '${before.wholesaleMinQty}',
          newValue: '${after.wholesaleMinQty}',
        ),
      );
    }
    if (before.stock != after.stock) {
      fields.add(
        ProductChangeField(
          key: 'stock',
          kind: 'stock',
          label: strings.stockQtyRequired.replaceAll(' *', ''),
          oldValue: '${before.stock}',
          newValue: '${after.stock}',
        ),
      );
    }
    if (before.unitWeight.trim() != after.unitWeight.trim()) {
      fields.add(
        ProductChangeField(
          key: 'unitWeight',
          kind: 'weight',
          label: strings.unitWeightLabel,
          oldValue: before.unitWeight.trim().isEmpty ? '—' : before.unitWeight.trim(),
          newValue: after.unitWeight.trim().isEmpty ? '—' : after.unitWeight.trim(),
        ),
      );
    }
    if (before.name.trim() != after.name.trim()) {
      fields.add(
        ProductChangeField(
          key: 'name',
          kind: 'other',
          label: strings.productNameRequired.replaceAll(' *', ''),
          oldValue: before.name,
          newValue: after.name,
        ),
      );
    }
    if (before.category.trim() != after.category.trim()) {
      fields.add(
        ProductChangeField(
          key: 'category',
          kind: 'other',
          label: strings.categoryLabel,
          oldValue: before.category,
          newValue: after.category,
        ),
      );
    }
    if (before.sku.trim() != after.sku.trim()) {
      fields.add(
        ProductChangeField(
          key: 'sku',
          kind: 'other',
          label: strings.skuLabel,
          oldValue: before.sku.trim().isEmpty ? '—' : before.sku.trim(),
          newValue: after.sku.trim().isEmpty ? '—' : after.sku.trim(),
        ),
      );
    }
    if (before.lowStockThreshold != after.lowStockThreshold) {
      fields.add(
        ProductChangeField(
          key: 'lowStockThreshold',
          kind: 'other',
          label: strings.lowStockAlertLabel,
          oldValue: '${before.lowStockThreshold}',
          newValue: '${after.lowStockThreshold}',
        ),
      );
    }
    if (before.unit.trim() != after.unit.trim()) {
      fields.add(
        ProductChangeField(
          key: 'unit',
          kind: 'other',
          label: strings.unitMeasureLabel,
          oldValue: before.unit.trim().isEmpty ? '—' : before.unit.trim(),
          newValue: after.unit.trim().isEmpty ? '—' : after.unit.trim(),
        ),
      );
    }
    if (before.packQty.trim() != after.packQty.trim()) {
      fields.add(
        ProductChangeField(
          key: 'packQty',
          kind: 'other',
          label: strings.packQtyLabel,
          oldValue: before.packQty.trim().isEmpty ? '—' : before.packQty.trim(),
          newValue: after.packQty.trim().isEmpty ? '—' : after.packQty.trim(),
        ),
      );
    }
    if (before.boxQty.trim() != after.boxQty.trim()) {
      fields.add(
        ProductChangeField(
          key: 'boxQty',
          kind: 'other',
          label: strings.boxQtyLabel,
          oldValue: before.boxQty.trim().isEmpty ? '—' : before.boxQty.trim(),
          newValue: after.boxQty.trim().isEmpty ? '—' : after.boxQty.trim(),
        ),
      );
    }
    if (before.packBarcode.trim() != after.packBarcode.trim()) {
      fields.add(
        ProductChangeField(
          key: 'packBarcode',
          kind: 'other',
          label: strings.packBarcodeLabel,
          oldValue: before.packBarcode.trim().isEmpty ? '—' : before.packBarcode.trim(),
          newValue: after.packBarcode.trim().isEmpty ? '—' : after.packBarcode.trim(),
        ),
      );
    }
    if (before.boxBarcode.trim() != after.boxBarcode.trim()) {
      fields.add(
        ProductChangeField(
          key: 'boxBarcode',
          kind: 'other',
          label: strings.boxBarcodeLabel,
          oldValue: before.boxBarcode.trim().isEmpty ? '—' : before.boxBarcode.trim(),
          newValue: after.boxBarcode.trim().isEmpty ? '—' : after.boxBarcode.trim(),
        ),
      );
    }
    if (before.nomenclature.trim() != after.nomenclature.trim()) {
      fields.add(
        ProductChangeField(
          key: 'nomenclature',
          kind: 'other',
          label: strings.nomenclatureLabel,
          oldValue: before.nomenclature.trim().isEmpty ? '—' : before.nomenclature.trim(),
          newValue: after.nomenclature.trim().isEmpty ? '—' : after.nomenclature.trim(),
        ),
      );
    }
    if (before.printName.trim() != after.printName.trim()) {
      fields.add(
        ProductChangeField(
          key: 'printName',
          kind: 'other',
          label: strings.printNameLabel,
          oldValue: before.printName.trim().isEmpty ? '—' : before.printName.trim(),
          newValue: after.printName.trim().isEmpty ? '—' : after.printName.trim(),
        ),
      );
    }
    if (fields.isEmpty) return;
    _appendProductChange(
      ProductChangeEntry(
        id: _nextId('chg'),
        productId: after.id,
        productName: after.name,
        source: source,
        fields: fields,
        createdAt: now ?? DateTime.now(),
      ),
    );
  }

  static const int inMemoryChangeHistoryDays = 90;
  static const int changeHistoryRetentionDays = 1827;

  List<ProductChangeEntry> productChangesForDays(int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return _productChanges
        .where((e) => !e.createdAt.isBefore(cutoff))
        .toList(growable: false);
  }

  Future<List<ProductChangeEntry>> loadProductChanges({int? days}) async {
    if (days != null && days <= inMemoryChangeHistoryDays) {
      return productChangesForDays(days);
    }
    final stored = await _storage.loadProductChanges(days: days);
    final mergedById = <String, ProductChangeEntry>{
      for (final e in stored) e.id: e,
      for (final e in _productChanges) e.id: e,
    };
    final cutoff = (days != null && days > 0)
        ? DateTime.now().subtract(Duration(days: days))
        : null;
    final result = mergedById.values
        .where((e) => cutoff == null || !e.createdAt.isBefore(cutoff))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  List<ProductChangeEntry> priceChangesForProduct(String productId) {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: changeHistoryRetentionDays));
    return _productChanges
        .where(
          (e) =>
              e.productId == productId &&
              !e.createdAt.isBefore(cutoff) &&
              e.hasKind('price'),
        )
        .toList(growable: false);
  }

  Future<List<ProductChangeEntry>> loadPriceChangesForProduct(
    String productId,
  ) async {
    final stored = await _storage.loadProductChanges(
      days: changeHistoryRetentionDays,
      productId: productId,
      priceOnly: true,
    );
    final mergedById = <String, ProductChangeEntry>{
      for (final e in stored) e.id: e,
      for (final e in priceChangesForProduct(productId)) e.id: e,
    };
    final result = mergedById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  static const Duration changeCoalesceWindow = Duration(minutes: 2);

  void _appendProductChange(ProductChangeEntry entry) {
    if (entry.source == 'edit') {
      final existingIdx = _productChanges.indexWhere((e) {
        if (e.productId != entry.productId || e.source != 'edit') return false;
        return entry.createdAt.difference(e.createdAt).abs() <=
            changeCoalesceWindow;
      });
      if (existingIdx != -1) {
        final existing = _productChanges[existingIdx];
        final mergedFields = List<ProductChangeField>.from(existing.fields);
        for (final inc in entry.fields) {
          final incId = inc.key.isNotEmpty ? inc.key : inc.label;
          final idx = mergedFields.indexWhere(
            (f) => (f.key.isNotEmpty ? f.key : f.label) == incId,
          );
          if (idx != -1) {
            final prev = mergedFields[idx];
            if (prev.oldValue == inc.newValue) {
              mergedFields.removeAt(idx);
            } else {
              mergedFields[idx] = ProductChangeField(
                key: inc.key.isNotEmpty ? inc.key : prev.key,
                kind: inc.kind,
                label: inc.label,
                oldValue: prev.oldValue,
                newValue: inc.newValue,
              );
            }
          } else {
            mergedFields.add(inc);
          }
        }
        _productChanges.removeAt(existingIdx);
        if (mergedFields.isNotEmpty) {
          _productChanges.insert(
            0,
            ProductChangeEntry(
              id: existing.id,
              productId: existing.productId,
              productName: entry.productName,
              source: existing.source,
              fields: mergedFields,
              createdAt: entry.createdAt,
            ),
          );
        }
        final memoryCutoff = DateTime.now()
            .subtract(const Duration(days: inMemoryChangeHistoryDays));
        _productChanges.removeWhere((e) => e.createdAt.isBefore(memoryCutoff));
        return;
      }
    }
    _productChanges.insert(0, entry);
    final memoryCutoff =
        DateTime.now().subtract(const Duration(days: inMemoryChangeHistoryDays));
    _productChanges.removeWhere((e) => e.createdAt.isBefore(memoryCutoff));
  }

  void _recordProductCreated(Product product, String source) {
    _appendProductChange(
      ProductChangeEntry(
        id: _nextId('chg'),
        productId: product.id,
        productName: product.name,
        source: source,
        fields: [
          ProductChangeField(
            key: 'sellPrice',
            kind: 'price',
            label: strings.sellShort,
            oldValue: '0',
            newValue: _fmtNum(product.sellPrice),
          ),
          if (product.costPrice > 0)
            ProductChangeField(
              key: 'costPrice',
              kind: 'price',
              label: strings.costShort,
              oldValue: '0',
              newValue: _fmtNum(product.costPrice),
            ),
          ProductChangeField(
            key: 'stock',
            kind: 'stock',
            label: strings.stockQtyRequired.replaceAll(' *', ''),
            oldValue: '0',
            newValue: '${product.stock}',
          ),
        ],
        createdAt: DateTime.now(),
      ),
    );
  }

  void _recordProductStatusChange(
    Product product,
    String oldStatus,
    String newStatus,
    String source,
  ) {
    _appendProductChange(
      ProductChangeEntry(
        id: _nextId('chg'),
        productId: product.id,
        productName: product.name,
        source: source,
        fields: [
          ProductChangeField(
            key: 'status',
            kind: 'other',
            label: strings.statusFieldLabel,
            oldValue: oldStatus,
            newValue: newStatus,
          ),
        ],
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<int> clearProductChanges({int? olderThanDays}) async {
    final before = _productChanges.length;
    if (olderThanDays == null) {
      _productChanges.clear();
    } else {
      final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
      _productChanges.removeWhere((e) => e.createdAt.isBefore(cutoff));
    }
    final removedInMemory = before - _productChanges.length;
    final removedInDb = await _storage.deleteProductChanges(
      olderThanDays: olderThanDays,
    );
    final removed = removedInDb > removedInMemory ? removedInDb : removedInMemory;
    if (removedInMemory > 0) {
      notifyListeners();
      await _persist();
    } else if (removedInDb > 0) {
      notifyListeners();
    }
    return removed;
  }

  Future<bool> revertProductChange(
    String changeId, {
    ProductChangeEntry? fallbackEntry,
  }) async {
    final entryIdx = _productChanges.indexWhere((e) => e.id == changeId);
    final entry = entryIdx != -1 ? _productChanges[entryIdx] : fallbackEntry;
    if (entry == null) return false;
    final productIdx = _products.indexWhere((p) => p.id == entry.productId);
    if (productIdx == -1 || !_products[productIdx].isActive) return false;

    final before = _products[productIdx];
    var next = before;
    for (final f in entry.fields) {
      final rawOld = f.oldValue == '—' ? '' : f.oldValue;
      final key = f.key.isNotEmpty ? f.key : _inferFieldKey(f);
      switch (key) {
        case 'sellPrice':
          final v = double.tryParse(rawOld.replaceAll(',', '.'));
          if (v != null && v >= 0) next = next.copyWith(sellPrice: v);
        case 'costPrice':
          final v = double.tryParse(rawOld.replaceAll(',', '.'));
          if (v != null && v >= 0) next = next.copyWith(costPrice: v);
        case 'wholesalePrice':
          final v = double.tryParse(rawOld.replaceAll(',', '.'));
          if (v != null && v >= 0) next = next.copyWith(wholesalePrice: v);
        case 'wholesaleMinQty':
          final v = int.tryParse(rawOld);
          if (v != null && v >= 0) next = next.copyWith(wholesaleMinQty: v);
        case 'stock':
          final v = double.tryParse(rawOld.replaceAll(',', '.'));
          if (v != null && v >= 0) next = next.copyWith(stock: v);
        case 'unitWeight':
          next = next.copyWith(unitWeight: rawOld);
        case 'name':
          if (rawOld.trim().isNotEmpty) next = next.copyWith(name: rawOld.trim());
        case 'category':
          if (rawOld.trim().isNotEmpty) next = next.copyWith(category: rawOld.trim());
        case 'sku':
          next = next.copyWith(sku: rawOld);
        case 'lowStockThreshold':
          final v = int.tryParse(rawOld);
          if (v != null && v >= 0) next = next.copyWith(lowStockThreshold: v);
        case 'unit':
          next = next.copyWith(unit: rawOld);
        case 'packQty':
          next = next.copyWith(packQty: rawOld);
        case 'boxQty':
          next = next.copyWith(boxQty: rawOld);
        case 'packBarcode':
          next = next.copyWith(packBarcode: rawOld);
        case 'boxBarcode':
          next = next.copyWith(boxBarcode: rawOld);
        case 'nomenclature':
          next = next.copyWith(nomenclature: rawOld);
        case 'printName':
          next = next.copyWith(printName: rawOld);
      }
    }

    final now = DateTime.now();
    next = _applyStockOutTracking(before, next.copyWith(updatedAt: now), now);
    _products[productIdx] = next;
    _recordProductChange(before, next, 'revert');
    notifyListeners();
    await _persist();
    return true;
  }

  String _inferFieldKey(ProductChangeField f) {
    if (f.label == strings.sellShort) return 'sellPrice';
    if (f.label == strings.costShort) return 'costPrice';
    if (f.label == strings.wholesaleShort) return 'wholesalePrice';
    if (f.label == strings.wholesaleMinQtyLabel) return 'wholesaleMinQty';
    if (f.kind == 'stock') return 'stock';
    if (f.kind == 'weight') return 'unitWeight';
    if (f.label == strings.categoryLabel) return 'category';
    if (f.label == strings.skuLabel) return 'sku';
    if (f.label == strings.lowStockAlertLabel) return 'lowStockThreshold';
    if (f.label == strings.unitMeasureLabel) return 'unit';
    if (f.label == strings.packQtyLabel) return 'packQty';
    if (f.label == strings.boxQtyLabel) return 'boxQty';
    if (f.label == strings.packBarcodeLabel) return 'packBarcode';
    if (f.label == strings.boxBarcodeLabel) return 'boxBarcode';
    if (f.label == strings.nomenclatureLabel) return 'nomenclature';
    if (f.label == strings.printNameLabel) return 'printName';
    if (f.label == strings.productNameRequired.replaceAll(' *', '')) return 'name';
    return '';
  }

  List<({Product product, List<String> reasons})> findDuplicateProducts({
    required String name,
    String sku = '',
    String packBarcode = '',
    String boxBarcode = '',
    String? excludeProductId,
  }) {
    final normName = GoogleSheetsService.normalizeName(name);
    final inputCodes = <String, String>{};
    for (final raw in [sku, packBarcode, boxBarcode]) {
      final trimmed = raw.trim();
      final lower = trimmed.toLowerCase();
      if (lower.isNotEmpty) {
        inputCodes.putIfAbsent(lower, () => trimmed);
      }
    }

    final matches = <({Product product, List<String> reasons})>[];
    for (final p in products) {
      if (excludeProductId != null && p.id == excludeProductId) continue;
      final reasons = <String>[];
      if (normName.isNotEmpty &&
          GoogleSheetsService.normalizeName(p.name) == normName) {
        reasons.add(strings.duplicateMatchName);
      }
      final existingCodes = GoogleSheetsService.extractBarcodes(p);
      for (final entry in inputCodes.entries) {
        if (existingCodes.contains(entry.key)) {
          reasons.add('${strings.duplicateMatchBarcode}: ${entry.value}');
        }
      }
      if (reasons.isNotEmpty) {
        matches.add((product: p, reasons: reasons));
      }
    }
    return matches;
  }

  List<ProductDuplicateGroup> findLocalDuplicateGroups() {
    return GoogleSheetsService.findDuplicateGroups(products, strings);
  }

  Future<void> applySyncedProducts({
    required List<Product> updatedProducts,
    required List<Product> newProducts,
  }) async {
    final now = DateTime.now();
    for (final updated in updatedProducts) {
      final index = _products.indexWhere((p) => p.id == updated.id);
      if (index != -1) {
        final before = _products[index];
        final next = _applyStockOutTracking(
          before,
          updated.copyWith(updatedAt: now),
          now,
        );
        _products[index] = next;
        _recordProductChange(before, next, 'sync');
        if (!updated.isActive) {
          _cart.remove(updated.id);
          _cartCustomPrices.remove(updated.id);
        }
      }
    }
    for (final item in newProducts) {
      final itemCodes = GoogleSheetsService.extractBarcodes(item);
      final itemNormName = GoogleSheetsService.normalizeName(item.name);
      final existingIndex = _products.indexWhere((p) {
        if (!p.isActive) return false;
        if (item.id.trim().isNotEmpty && p.id == item.id.trim()) return true;
        if (itemCodes.isNotEmpty &&
            GoogleSheetsService.extractBarcodes(p).any(itemCodes.contains)) {
          return true;
        }
        if (itemNormName.isNotEmpty &&
            GoogleSheetsService.normalizeName(p.name) == itemNormName) {
          return true;
        }
        return false;
      });
      if (existingIndex != -1) {
        final before = _products[existingIndex];
        final next = _applyStockOutTracking(
          before,
          item.copyWith(id: before.id, updatedAt: now),
          now,
        );
        _products[existingIndex] = next;
        _recordProductChange(before, next, 'sync');
        continue;
      }
      final assignedId = item.id.trim().isEmpty ? _nextId('prd') : item.id.trim();
      final created = item.copyWith(
        id: assignedId,
        outOfStockSince: item.stock <= 0 ? (item.outOfStockSince ?? now) : null,
        clearOutOfStockSince: item.stock > 0,
        updatedAt: now,
      );
      _products.insert(0, created);
      _recordProductCreated(created, 'sync');
    }
    notifyListeners();
    await _persist();
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

  ({double units, double costValue, double sellValue, List<Product> lowStock})
      _ensureInventoryTotals() {
    final cached = _cachedInventoryTotals;
    if (cached != null) return cached;
    var units = 0.0;
    var costValue = 0.0;
    var sellValue = 0.0;
    final lowStock = <Product>[];
    for (final product in products) {
      units += product.stock;
      costValue += product.inventoryValue;
      sellValue += product.potentialRevenue;
      if (product.isLowStock || product.isOutOfStock) {
        lowStock.add(product);
      }
    }
    final computed = (
      units: units,
      costValue: costValue,
      sellValue: sellValue,
      lowStock: List<Product>.unmodifiable(lowStock),
    );
    _cachedInventoryTotals = computed;
    return computed;
  }

  Map<String, double> get soldUnitsByProduct {
    final cached = _cachedSoldUnitsByProduct;
    if (cached != null) return cached;
    final counts = <String, double>{};
    for (final sale in sales) {
      for (final item in sale.items) {
        counts[item.productId] = (counts[item.productId] ?? 0) + item.quantity;
      }
    }
    final unmodifiable = Map<String, double>.unmodifiable(counts);
    _cachedSoldUnitsByProduct = unmodifiable;
    return unmodifiable;
  }

  Map<String, double> _dailySalesPaceByProduct({
    int windowDays = 30,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final cutoff = current.subtract(Duration(days: windowDays));
    final unitsInWindow = <String, double>{};
    DateTime? earliestSale;

    for (final sale in sales) {
      if (sale.createdAt.isBefore(cutoff)) continue;
      if (earliestSale == null || sale.createdAt.isBefore(earliestSale)) {
        earliestSale = sale.createdAt;
      }
      for (final item in sale.items) {
        if (item.quantity <= 0) continue;
        unitsInWindow[item.productId] =
            (unitsInWindow[item.productId] ?? 0) + item.quantity;
      }
    }

    if (earliestSale == null) return const {};

    final observedDays = (current.difference(earliestSale).inDays + 1)
        .clamp(1, windowDays);
    final result = <String, double>{};
    for (final entry in unitsInWindow.entries) {
      if (entry.value < 3) continue;
      final dailyPace = entry.value / observedDays;
      if (dailyPace > 0) {
        result[entry.key] = dailyPace;
      }
    }
    return result;
  }

  Map<String, int> estimatedDaysOfStockByProduct({
    int windowDays = 30,
    DateTime? now,
  }) {
    if (now == null && windowDays == 30 && _cachedDaysOfStockLeft != null) {
      return _cachedDaysOfStockLeft!;
    }
    final paceByProduct =
        _dailySalesPaceByProduct(windowDays: windowDays, now: now);
    if (paceByProduct.isEmpty) {
      if (now == null && windowDays == 30) {
        _cachedDaysOfStockLeft = const {};
      }
      return const {};
    }

    final result = <String, int>{};
    for (final p in products) {
      if (p.stock <= 0) continue;
      final dailyPace = paceByProduct[p.id];
      if (dailyPace == null || dailyPace <= 0) continue;
      final estDays = (p.stock / dailyPace).round();
      if (estDays <= 30) {
        result[p.id] = estDays < 1 ? 1 : estDays;
      }
    }

    final unmodifiable = Map<String, int>.unmodifiable(result);
    if (now == null && windowDays == 30) {
      _cachedDaysOfStockLeft = unmodifiable;
    }
    return unmodifiable;
  }

  double get totalStockUnits => _ensureInventoryTotals().units;

  double get totalInventoryCostValue => _ensureInventoryTotals().costValue;

  double get totalPotentialRevenue => _ensureInventoryTotals().sellValue;

  List<Product> get lowStockProducts => _ensureInventoryTotals().lowStock;

  int get lowStockCount => lowStockProducts.length;

  List<
      ({
        Product product,
        double suggestedQty,
        String lastSupplier,
        int? daysLeft,
      })> buildPurchaseOrderSuggestions({
    int velocityThresholdDays = 7,
    int targetCoverageDays = 14,
    DateTime? now,
  }) {
    final lastSupplierByProduct = <String, String>{};
    for (final rec in _stockIns) {
      final sup = rec.supplierName.trim();
      if (sup.isEmpty) continue;
      for (final item in rec.items) {
        lastSupplierByProduct.putIfAbsent(item.productId, () => sup);
      }
    }

    final paceByProduct = _dailySalesPaceByProduct(now: now);
    final daysLeftByProduct = estimatedDaysOfStockByProduct(now: now);

    final result = <({
      Product product,
      double suggestedQty,
      String lastSupplier,
      int? daysLeft,
    })>[];

    for (final p in products) {
      final isThresholdLow = p.isLowStock || p.isOutOfStock;
      final daysLeft = daysLeftByProduct[p.id];
      final isVelocityLow =
          p.stock > 0 && daysLeft != null && daysLeft <= velocityThresholdDays;
      if (!isThresholdLow && !isVelocityLow) continue;

      final targetLevel =
          (p.lowStockThreshold > 0 ? p.lowStockThreshold * 2 : 5).toDouble();
      double suggested;
      if (p.stock < 0) {
        suggested = -p.stock + targetLevel;
      } else if (p.stock == 0) {
        suggested = targetLevel;
      } else if (isThresholdLow) {
        suggested = (targetLevel - p.stock).clamp(1.0, 999999.0);
      } else {
        suggested = 1.0;
      }

      final dailyPace = paceByProduct[p.id];
      if (dailyPace != null && dailyPace > 0) {
        final velocityTarget = (dailyPace * targetCoverageDays).ceilToDouble();
        final velocitySuggested = p.stock < 0
            ? (-p.stock + velocityTarget)
            : (velocityTarget - p.stock).clamp(1.0, 999999.0);
        if (velocitySuggested > suggested) {
          suggested = velocitySuggested;
        }
      }

      result.add((
        product: p,
        suggestedQty: suggested,
        lastSupplier: lastSupplierByProduct[p.id] ?? '',
        daysLeft: daysLeft,
      ));
    }

    result.sort((a, b) {
      final aOut = a.product.stock <= 0 ? 0 : 1;
      final bOut = b.product.stock <= 0 ? 0 : 1;
      if (aOut != bOut) return aOut.compareTo(bOut);
      final aDays = a.daysLeft ?? 9999;
      final bDays = b.daysLeft ?? 9999;
      if (aDays != bDays) return aDays.compareTo(bDays);
      return a.product.name
          .toLowerCase()
          .compareTo(b.product.name.toLowerCase());
    });
    return result;
  }

  List<StockInRecord> get unpaidStockIns =>
      _stockIns.where((r) => !r.isPaid).toList(growable: false);

  double get totalSupplierDebt =>
      unpaidStockIns.fold(0.0, (sum, r) => sum + r.remainingDebt);

  List<
      ({
        String name,
        int invoicesCount,
        double totalSpend,
        double totalDebt,
        DateTime lastDeliveryAt,
        int uniqueProductsCount,
        List<StockInRecord> invoices,
      })> buildSupplierDirectory() {
    final sorted = List<StockInRecord>.from(_stockIns)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final byKey = <String,
        ({
      String name,
      double totalSpend,
      double totalDebt,
      DateTime lastDeliveryAt,
      Set<String> productIds,
      List<StockInRecord> invoices,
    })>{};

    for (final rec in sorted) {
      final rawName = rec.supplierName.trim();
      if (rawName.isEmpty && rec.isPaid) continue;
      final key = rawName.toLowerCase();
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = (
          name: rawName,
          totalSpend: rec.totalCost,
          totalDebt: rec.remainingDebt,
          lastDeliveryAt: rec.createdAt,
          productIds: {for (final item in rec.items) item.productId},
          invoices: [rec],
        );
      } else {
        existing.productIds.addAll(rec.items.map((i) => i.productId));
        existing.invoices.add(rec);
        byKey[key] = (
          name: existing.name,
          totalSpend: existing.totalSpend + rec.totalCost,
          totalDebt: existing.totalDebt + rec.remainingDebt,
          lastDeliveryAt: existing.lastDeliveryAt.isAfter(rec.createdAt)
              ? existing.lastDeliveryAt
              : rec.createdAt,
          productIds: existing.productIds,
          invoices: existing.invoices,
        );
      }
    }

    final result = [
      for (final entry in byKey.values)
        (
          name: entry.name,
          invoicesCount: entry.invoices.length,
          totalSpend: entry.totalSpend,
          totalDebt: entry.totalDebt,
          lastDeliveryAt: entry.lastDeliveryAt,
          uniqueProductsCount: entry.productIds.length,
          invoices: List<StockInRecord>.unmodifiable(entry.invoices),
        ),
    ];
    result.sort((a, b) {
      final aHasDebt = a.totalDebt > 0.009 ? 0 : 1;
      final bHasDebt = b.totalDebt > 0.009 ? 0 : 1;
      if (aHasDebt != bHasDebt) return aHasDebt.compareTo(bHasDebt);
      final debtCmp = b.totalDebt.compareTo(a.totalDebt);
      if (debtCmp != 0) return debtCmp;
      return b.lastDeliveryAt.compareTo(a.lastDeliveryAt);
    });
    return result;
  }

  List<
      ({
        String productId,
        String productName,
        String cheapestSupplier,
        double cheapestPrice,
        DateTime cheapestDate,
        List<({String supplierName, double lastPrice, DateTime date})> quotes,
      })> buildCheapestSupplierByProduct() {
    final sorted = List<StockInRecord>.from(_stockIns)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final productNames = <String, String>{};
    final latestQuotes =
        <String, Map<String, ({String supplierName, double lastPrice, DateTime date})>>{};

    for (final rec in sorted) {
      final supplier = rec.supplierName.trim();
      if (supplier.isEmpty) continue;
      final supKey = supplier.toLowerCase();
      for (final item in rec.items) {
        if (item.unitCost <= 0) continue;
        productNames.putIfAbsent(
          item.productId,
          () => findProductById(item.productId)?.name ?? item.productName,
        );
        final bySup = latestQuotes.putIfAbsent(item.productId, () => {});
        bySup.putIfAbsent(
          supKey,
          () => (
            supplierName: supplier,
            lastPrice: item.unitCost,
            date: rec.createdAt,
          ),
        );
      }
    }

    final result = <({
      String productId,
      String productName,
      String cheapestSupplier,
      double cheapestPrice,
      DateTime cheapestDate,
      List<({String supplierName, double lastPrice, DateTime date})> quotes,
    })>[];

    for (final entry in latestQuotes.entries) {
      final quotes = entry.value.values.toList()
        ..sort((a, b) => a.lastPrice.compareTo(b.lastPrice));
      if (quotes.isEmpty) continue;
      final best = quotes.first;
      result.add((
        productId: entry.key,
        productName: productNames[entry.key] ?? '',
        cheapestSupplier: best.supplierName,
        cheapestPrice: best.lastPrice,
        cheapestDate: best.date,
        quotes: List.unmodifiable(quotes),
      ));
    }

    result.sort((a, b) {
      final aMulti = a.quotes.length >= 2 ? 0 : 1;
      final bMulti = b.quotes.length >= 2 ? 0 : 1;
      if (aMulti != bMulti) return aMulti.compareTo(bMulti);
      return a.productName
          .toLowerCase()
          .compareTo(b.productName.toLowerCase());
    });
    return result;
  }

  List<Sale> get unpaidSales =>
      sales.where((sale) => !sale.isPaid).toList();

  double get totalUnpaidDebt =>
      unpaidSales.fold(0.0, (sum, sale) => sum + sale.remainingDebt);

  String customerPhoneByName(String name) {
    final target = name.trim().toLowerCase();
    if (target.isEmpty) return '';
    for (final c in _customers) {
      if (c.name.trim().toLowerCase() == target && c.phone.trim().isNotEmpty) {
        return c.phone.trim();
      }
    }
    for (final s in sales) {
      if (s.customerName.trim().toLowerCase() == target &&
          s.customerPhone.trim().isNotEmpty) {
        return s.customerPhone.trim();
      }
    }
    return '';
  }

  List<DebtorSummary> _buildDebtSummaries({required bool unpaidOnly}) {
    final source = unpaidOnly
        ? unpaidSales
        : sales.where((s) => s.paymentMethod == PaymentMethod.postPay || !s.isPaid).toList();
    final grouped = <String, List<Sale>>{};
    final displayNames = <String, String>{};
    for (final sale in source) {
      final rawName = sale.customerName.trim().isEmpty
          ? 'Unknown'
          : sale.customerName.trim();
      final key = rawName.toLowerCase();
      displayNames.putIfAbsent(key, () => rawName);
      grouped.putIfAbsent(key, () => []).add(sale);
    }

    final allPostPayByCustomer = <String, List<Sale>>{};
    for (final s in sales) {
      if (s.paymentMethod == PaymentMethod.postPay || !s.isPaid) {
        final rawName =
            s.customerName.trim().isEmpty ? 'Unknown' : s.customerName.trim();
        allPostPayByCustomer.putIfAbsent(rawName.toLowerCase(), () => []).add(s);
      }
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final result = <DebtorSummary>[];

    for (final entry in grouped.entries) {
      final key = entry.key;
      final name = displayNames[key] ?? key;
      final unpaidList = entry.value.where((s) => !s.isPaid).toList();
      final allDebtList = allPostPayByCustomer[key] ?? entry.value;
      final debt = unpaidList.fold(0.0, (sum, s) => sum + s.remainingDebt);
      DateTime? earliest;
      var overdue = false;
      for (final s in unpaidList) {
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

      final repayments =
          <({DateTime date, double amount, String receiptCode})>[];
      for (final s in allDebtList) {
        if (s.paymentHistory.isNotEmpty) {
          for (final p in s.paymentHistory) {
            repayments.add((
              date: p.paidAt,
              amount: p.amount,
              receiptCode: s.receiptCode,
            ));
          }
        } else if (s.paidAmount > 0.009) {
          repayments.add((
            date: s.paidAt ?? s.createdAt,
            amount: s.paidAmount,
            receiptCode: s.receiptCode,
          ));
        }
      }
      repayments.sort((a, b) => b.date.compareTo(a.date));

      result.add(
        DebtorSummary(
          customerName: name,
          phone: customerPhoneByName(name),
          sales: unpaidList,
          allDebtSales: allDebtList,
          totalDebtPurchasesCount: allDebtList.length,
          repayments: repayments,
          totalDebt: debt,
          earliestDueDate: earliest,
          hasOverdue: overdue,
        ),
      );
    }

    result.sort((a, b) {
      final debtCmp = b.totalDebt.compareTo(a.totalDebt);
      if (debtCmp != 0) return debtCmp;
      return b.totalDebtPurchasesCount.compareTo(a.totalDebtPurchasesCount);
    });
    return result;
  }

  List<DebtorSummary> get debtors => _buildDebtSummaries(unpaidOnly: true);

  List<DebtorSummary> get allDebtCustomers =>
      _buildDebtSummaries(unpaidOnly: false);

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

  Customer? findCustomerByName(String name) {
    final target = name.trim().toLowerCase();
    if (target.isEmpty) return null;
    for (final c in _customers) {
      if (c.name.trim().toLowerCase() == target) return c;
    }
    return null;
  }

  CustomerSegment customerSegmentByName(String name) =>
      findCustomerByName(name)?.segment ?? CustomerSegment.retail;

  Future<void> addCustomer({
    required String name,
    String phone = '',
    String note = '',
    CustomerSegment segment = CustomerSegment.retail,
  }) async {
    final cleanName = InputNormalizer.normalizeDisplayName(name);
    if (cleanName.isEmpty) return;
    final cleanPhone = InputNormalizer.normalizePhone(phone);
    final cleanNote = InputNormalizer.normalizeDisplayName(note);
    final normNameKey = InputNormalizer.normalizeNameKey(cleanName);
    _hiddenCustomerSuggestions.remove(cleanName.toLowerCase());

    final existingIdx = _customers.indexWhere((c) {
      if (cleanPhone.isNotEmpty &&
          InputNormalizer.normalizePhone(c.phone) == cleanPhone) {
        return true;
      }
      return InputNormalizer.normalizeNameKey(c.name) == normNameKey;
    });
    if (existingIdx != -1) {
      final existing = _customers[existingIdx];
      _customers[existingIdx] = existing.copyWith(
        name: cleanName,
        phone: cleanPhone.isNotEmpty ? cleanPhone : existing.phone,
        note: cleanNote.isNotEmpty ? cleanNote : existing.note,
        segment: segment,
      );
    } else {
      final customer = Customer(
        id: _nextId('cus'),
        name: cleanName,
        phone: cleanPhone,
        note: cleanNote,
        segment: segment,
        createdAt: DateTime.now(),
      );
      _customers.add(customer);
    }
    _customers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    await _persist();
  }

  Future<void> updateCustomer({
    required String customerId,
    required String name,
    String phone = '',
    String note = '',
    CustomerSegment? segment,
  }) async {
    final cleanName = InputNormalizer.normalizeDisplayName(name);
    if (cleanName.isEmpty) return;
    final index = _customers.indexWhere((c) => c.id == customerId);
    if (index == -1) return;
    _hiddenCustomerSuggestions.remove(cleanName.toLowerCase());
    _customers[index] = _customers[index].copyWith(
      name: cleanName,
      phone: InputNormalizer.normalizePhone(phone),
      note: InputNormalizer.normalizeDisplayName(note),
      segment: segment,
    );
    _customers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    await _persist();
  }

  Future<void> deleteCustomer(String customerId) async {
    final idx = _customers.indexWhere((c) => c.id == customerId);
    if (idx != -1) {
      final removedName = _customers[idx].name.trim().toLowerCase();
      if (removedName.isNotEmpty) {
        _hiddenCustomerSuggestions.add(removedName);
      }
      _customers.removeAt(idx);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> renameCustomerRecommendation({
    required String oldName,
    required String newName,
    String? phone,
  }) async {
    final cleanOld = oldName.trim();
    final cleanNew = newName.trim();
    if (cleanOld.isEmpty || cleanNew.isEmpty) return;
    final oldLower = cleanOld.toLowerCase();
    final newLower = cleanNew.toLowerCase();
    final cleanPhone = phone?.trim();

    _hiddenCustomerSuggestions.remove(newLower);
    if (oldLower != newLower) {
      _hiddenCustomerSuggestions.remove(oldLower);
    }

    final oldIdx = _customers.indexWhere(
      (c) => c.name.trim().toLowerCase() == oldLower,
    );
    final existingNewIdx = _customers.indexWhere(
      (c) => c.name.trim().toLowerCase() == newLower,
    );

    if (oldIdx != -1) {
      if (existingNewIdx != -1 && existingNewIdx != oldIdx) {
        final mergedPhone = (cleanPhone != null && cleanPhone.isNotEmpty)
            ? cleanPhone
            : (_customers[existingNewIdx].phone.isNotEmpty
                ? _customers[existingNewIdx].phone
                : _customers[oldIdx].phone);
        _customers[existingNewIdx] = _customers[existingNewIdx].copyWith(
          name: cleanNew,
          phone: mergedPhone,
        );
        _customers.removeAt(oldIdx);
      } else {
        _customers[oldIdx] = _customers[oldIdx].copyWith(
          name: cleanNew,
          phone: cleanPhone ?? _customers[oldIdx].phone,
        );
      }
    } else if (existingNewIdx != -1) {
      _customers[existingNewIdx] = _customers[existingNewIdx].copyWith(
        name: cleanNew,
        phone: (cleanPhone != null && cleanPhone.isNotEmpty)
            ? cleanPhone
            : _customers[existingNewIdx].phone,
      );
    } else {
      _customers.add(
        Customer(
          id: _nextId('cus'),
          name: cleanNew,
          phone: cleanPhone ?? customerPhoneByName(cleanOld),
          createdAt: DateTime.now(),
        ),
      );
    }
    _customers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    for (var i = 0; i < _sales.length; i++) {
      final s = _sales[i];
      if (s.customerName.trim().toLowerCase() == oldLower) {
        _sales[i] = s.copyWith(
          customerName: cleanNew,
          customerPhone: (cleanPhone != null && cleanPhone.isNotEmpty)
              ? cleanPhone
              : s.customerPhone,
        );
      }
    }

    notifyListeners();
    await _persist();
  }

  Future<void> deleteCustomerRecommendation(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final targetLower = clean.toLowerCase();
    _customers.removeWhere((c) => c.name.trim().toLowerCase() == targetLower);
    _hiddenCustomerSuggestions.add(targetLower);
    notifyListeners();
    await _persist();
  }

  List<Sale> salesForCustomer(String customerName) {
    final target = customerName.trim().toLowerCase();
    if (target.isEmpty) return const [];
    return sales
        .where((s) => s.customerName.trim().toLowerCase() == target)
        .toList(growable: false);
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
    final units = <String, double>{};
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

  ({
    List<FrozenCashItem> items,
    int totalCount,
    double totalFrozenValue,
  }) frozenCashSummary({
    int minIdleDays = 30,
    int? maxIdleDays,
    int limit = 10,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final lastSoldByProduct = <String, DateTime>{};
    for (final sale in sales) {
      for (final item in sale.items) {
        if (item.quantity <= 0) continue;
        final prev = lastSoldByProduct[item.productId];
        if (prev == null || sale.createdAt.isAfter(prev)) {
          lastSoldByProduct[item.productId] = sale.createdAt;
        }
      }
    }

    final matches = <FrozenCashItem>[];
    var totalFrozenValue = 0.0;
    for (final p in products) {
      if (p.stock <= 0 || p.inventoryValue <= 0) continue;
      final lastSold = lastSoldByProduct[p.id];
      final refDate = lastSold ?? p.updatedAt;
      final daysIdle = current.difference(refDate).inDays;
      if (daysIdle < minIdleDays) continue;
      if (maxIdleDays != null && daysIdle > maxIdleDays) continue;
      totalFrozenValue += p.inventoryValue;
      matches.add(
        FrozenCashItem(
          product: p,
          frozenValue: p.inventoryValue,
          potentialRevenue: p.potentialRevenue,
          daysWithoutSales: daysIdle,
          hasEverSold: lastSold != null,
        ),
      );
    }

    matches.sort((a, b) {
      final valCmp = b.frozenValue.compareTo(a.frozenValue);
      if (valCmp != 0) return valCmp;
      return b.daysWithoutSales.compareTo(a.daysWithoutSales);
    });

    return (
      items: matches.take(limit).toList(growable: false),
      totalCount: matches.length,
      totalFrozenValue: totalFrozenValue,
    );
  }

  List<int> get salesYears {
    final years = <int>{};
    for (final s in sales) {
      years.add(s.createdAt.year);
    }
    final list = years.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  List<SalesTimeBucketStat> salesByMonth({int? year}) {
    final orders = List<int>.filled(12, 0);
    final units = List<double>.filled(12, 0.0);
    final revenue = List<double>.filled(12, 0.0);
    final profit = List<double>.filled(12, 0.0);

    for (final s in sales) {
      if (year != null && s.createdAt.year != year) continue;
      final idx = s.createdAt.month - 1;
      orders[idx] += 1;
      units[idx] += s.totalUnits;
      revenue[idx] += s.total;
      profit[idx] += s.profit;
    }

    return [
      for (var i = 0; i < 12; i++)
        SalesTimeBucketStat(
          key: i + 1,
          ordersCount: orders[i],
          unitsSold: units[i],
          revenue: revenue[i],
          profit: profit[i],
        ),
    ];
  }

  List<SalesTimeBucketStat> salesByWeekday(SalesDateFilter filter) {
    final orders = List<int>.filled(7, 0);
    final units = List<double>.filled(7, 0.0);
    final revenue = List<double>.filled(7, 0.0);
    final profit = List<double>.filled(7, 0.0);

    for (final s in filteredSales(filter)) {
      final idx = s.createdAt.weekday - 1;
      orders[idx] += 1;
      units[idx] += s.totalUnits;
      revenue[idx] += s.total;
      profit[idx] += s.profit;
    }

    return [
      for (var i = 0; i < 7; i++)
        SalesTimeBucketStat(
          key: i + 1,
          ordersCount: orders[i],
          unitsSold: units[i],
          revenue: revenue[i],
          profit: profit[i],
        ),
    ];
  }

  List<SalesTimeBucketStat> salesByHour(SalesDateFilter filter) {
    final orders = List<int>.filled(24, 0);
    final units = List<double>.filled(24, 0.0);
    final revenue = List<double>.filled(24, 0.0);
    final profit = List<double>.filled(24, 0.0);

    for (final s in filteredSales(filter)) {
      final h = s.createdAt.hour;
      orders[h] += 1;
      units[h] += s.totalUnits;
      revenue[h] += s.total;
      profit[h] += s.profit;
    }

    return [
      for (var h = 0; h < 24; h++)
        SalesTimeBucketStat(
          key: h,
          ordersCount: orders[h],
          unitsSold: units[h],
          revenue: revenue[h],
          profit: profit[h],
        ),
    ];
  }

  Product _applyStockOutTracking(Product before, Product after, DateTime now) {
    if (before.stock > 0 && after.stock <= 0) {
      return after.copyWith(outOfStockSince: now);
    }
    if (before.stock <= 0 && after.stock > 0) {
      final since = before.outOfStockSince ?? before.updatedAt;
      final elapsedDays = now.difference(since).inDays.clamp(0, 36500);
      return after.copyWith(
        totalOutOfStockDays: before.totalOutOfStockDays + elapsedDays,
        clearOutOfStockSince: true,
      );
    }
    if (before.stock <= 0 && after.stock <= 0 && after.outOfStockSince == null) {
      return after.copyWith(
        outOfStockSince: before.outOfStockSince ?? before.updatedAt,
        totalOutOfStockDays: before.totalOutOfStockDays,
      );
    }
    return after.copyWith(
      outOfStockSince: before.outOfStockSince,
      totalOutOfStockDays: before.totalOutOfStockDays,
    );
  }

  List<OutOfStockStat> outOfStockAnalytics({int velocityWindowDays = 90}) {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: velocityWindowDays));
    final unitsInWindow = <String, double>{};
    DateTime? earliestSaleInWindow;

    for (final s in sales) {
      if (s.createdAt.isBefore(cutoff)) continue;
      if (earliestSaleInWindow == null ||
          s.createdAt.isBefore(earliestSaleInWindow)) {
        earliestSaleInWindow = s.createdAt;
      }
      for (final item in s.items) {
        if (item.quantity <= 0) continue;
        unitsInWindow[item.productId] =
            (unitsInWindow[item.productId] ?? 0) + item.quantity;
      }
    }

    final observedSpanDays = earliestSaleInWindow == null
        ? velocityWindowDays
        : (now.difference(earliestSaleInWindow).inDays + 1)
            .clamp(1, velocityWindowDays);

    final result = <OutOfStockStat>[];
    for (final p in products) {
      if (!p.isOutOfStock && p.totalOutOfStockDays <= 0) continue;
      final currentDays = p.currentOutOfStockDays;
      final totalDays = p.cumulativeOutOfStockDays;
      final soldUnits = unitsInWindow[p.id] ?? 0;
      final activeDays = (observedSpanDays - currentDays.clamp(0, observedSpanDays))
          .clamp(1, observedSpanDays);
      final avgDaily = soldUnits / activeDays;
      final lostUnits = p.isOutOfStock ? avgDaily * currentDays : 0.0;
      result.add(
        OutOfStockStat(
          product: p,
          currentDays: currentDays,
          totalDays: totalDays,
          avgDailyUnits: avgDaily,
          estimatedLostRevenue: lostUnits * p.sellPrice,
          estimatedLostProfit: lostUnits * p.unitProfit,
        ),
      );
    }

    result.sort((a, b) {
      if (a.product.isOutOfStock != b.product.isOutOfStock) {
        return a.product.isOutOfStock ? -1 : 1;
      }
      final lossCmp = b.estimatedLostRevenue.compareTo(a.estimatedLostRevenue);
      if (lossCmp != 0) return lossCmp;
      final curCmp = b.currentDays.compareTo(a.currentDays);
      if (curCmp != 0) return curCmp;
      return b.totalDays.compareTo(a.totalDays);
    });
    return result;
  }

  String _fmtAdviceMoney(double value) {
    final rounded = value.round();
    final digits = rounded.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final posFromRight = digits.length - i;
      if (i > 0 && posFromRight % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final sign = rounded < 0 ? '-' : '';
    return '$sign${buf.toString()} ${_currency.symbol}';
  }

  /// Generates daily, data-driven advice cards about the shop's products.
  List<DailyProductAdvice> dailyProductAdvices() {
    final active = products;
    if (active.isEmpty) return const [];
    final now = DateTime.now();
    final cacheKey = '${now.year}-${now.month}-${now.day}|${_language.code}';
    final cached = _cachedDailyAdvices;
    if (cached != null && _cachedDailyAdvicesKey == cacheKey) {
      return cached;
    }
    final s = strings;
    final advices = <DailyProductAdvice>[];

    // 1. Urgent: Best-selling out-of-stock products losing revenue.
    final oosList = outOfStockAnalytics(velocityWindowDays: 60)
        .where((e) => e.product.isOutOfStock && e.avgDailyUnits > 0)
        .toList();
    for (final oos in oosList.take(5)) {
      advices.add(
        DailyProductAdvice(
          id: 'oos_${oos.product.id}',
          severity: AdviceSeverity.urgent,
          title: s.adviceRestockHitTitle(oos.product.name),
          body: s.adviceRestockHitBody(
            oos.currentDays < 1 ? 1 : oos.currentDays,
            _fmtAdviceMoney(
              oos.estimatedLostRevenue > 0
                  ? oos.estimatedLostRevenue
                  : oos.avgDailyUnits * oos.product.sellPrice,
            ),
          ),
          product: oos.product,
          actionType: AdviceActionType.addToStockIn,
        ),
      );
    }

    // 2. Urgent / Warning: Incoming purchase cost increased & margin is squeezed.
    final incoming = incomingPriceAnalytics(filter: SalesDateFilter.all);
    var marginDropAdded = 0;
    for (final item in incoming) {
      if (!item.isPriceUp || item.previousCost == null) continue;
      final prod = findProductById(item.productId);
      if (prod == null || !prod.isActive) continue;
      final margin = prod.marginPercent;
      if (margin < 22 || prod.sellPrice <= item.latestCost) {
        advices.add(
          DailyProductAdvice(
            id: 'cost_up_${prod.id}',
            severity: prod.sellPrice <= item.latestCost
                ? AdviceSeverity.urgent
                : AdviceSeverity.warning,
            title: s.adviceMarginDropTitle(prod.name),
            body: s.adviceMarginDropBody(
              _fmtAdviceMoney(item.previousCost!),
              _fmtAdviceMoney(item.latestCost),
              margin.toStringAsFixed(0),
            ),
            product: prod,
            actionType: AdviceActionType.editPrice,
          ),
        );
        marginDropAdded += 1;
        if (marginDropAdded >= 5) break;
      }
    }

    // 2.5 Urgent / Warning: Products with expiring or expired shelf life.
    final expiring = expiringProducts(withinDays: 30, now: now);
    for (final prod in expiring.take(5)) {
      final days = prod.daysUntilExpiry(now: now)!;
      final exp = prod.expiryDate!;
      final dateStr =
          '${exp.day.toString().padLeft(2, '0')}.${exp.month.toString().padLeft(2, '0')}.${exp.year}';
      advices.add(
        DailyProductAdvice(
          id: 'exp_${prod.id}',
          severity: days <= 7 ? AdviceSeverity.urgent : AdviceSeverity.warning,
          title: days < 0
              ? s.adviceExpiredTitle(prod.name)
              : s.adviceExpiringTitle(prod.name),
          body: s.adviceExpiringBody(prod.stock, dateStr, days),
          product: prod,
          actionType: AdviceActionType.editPrice,
        ),
      );
    }

    // 3. Warning: Low or negative margin on active in-stock products.
    final lowMarginProducts = active
        .where(
          (p) =>
              p.stock > 0 &&
              p.costPrice > 0 &&
              p.marginPercent < 12 &&
              !advices.any((a) => a.product?.id == p.id),
        )
        .toList()
      ..sort((a, b) => a.marginPercent.compareTo(b.marginPercent));
    for (final prod in lowMarginProducts.take(5)) {
      advices.add(
        DailyProductAdvice(
          id: 'low_margin_${prod.id}',
          severity: prod.sellPrice <= prod.costPrice
              ? AdviceSeverity.urgent
              : AdviceSeverity.warning,
          title: s.adviceLowMarginTitle(prod.name),
          body: s.adviceLowMarginBody(
            _fmtAdviceMoney(prod.costPrice),
            _fmtAdviceMoney(prod.sellPrice),
            prod.marginPercent.toStringAsFixed(0),
          ),
          product: prod,
          actionType: AdviceActionType.editPrice,
        ),
      );
    }

    // 4. Warning: Fast-moving products running low on stock (30-day velocity).
    final cutoff30 = now.subtract(const Duration(days: 30));
    final units30 = <String, double>{};
    for (final sale in sales) {
      if (sale.createdAt.isBefore(cutoff30)) continue;
      for (final item in sale.items) {
        if (item.quantity <= 0) continue;
        units30[item.productId] = (units30[item.productId] ?? 0) + item.quantity;
      }
    }
    final lowStockHits = active
        .where((p) => p.isLowStock && (units30[p.id] ?? 0) > 0)
        .toList()
      ..sort((a, b) => (units30[b.id] ?? 0).compareTo(units30[a.id] ?? 0));
    for (final prod in lowStockHits.take(5)) {
      final dailyPace = (units30[prod.id] ?? 1) / 30.0;
      final estDays = (prod.stock / dailyPace).ceil().clamp(1, 90);
      advices.add(
        DailyProductAdvice(
          id: 'low_hit_${prod.id}',
          severity: AdviceSeverity.warning,
          title: s.adviceLowStockHitTitle(prod.name),
          body: s.adviceLowStockHitBody(prod.stock, estDays),
          product: prod,
          actionType: AdviceActionType.addToStockIn,
        ),
      );
    }

    // 5. Opportunity: Dead stock (0 sales in 30 days) with highest frozen capital.
    if (sales.isNotEmpty) {
      final deadStock = active
          .where(
            (p) =>
                p.stock > 0 &&
                p.inventoryValue > 0 &&
                (units30[p.id] ?? 0) == 0,
          )
          .toList()
        ..sort((a, b) => b.inventoryValue.compareTo(a.inventoryValue));
      for (final prod in deadStock.take(5)) {
        advices.add(
          DailyProductAdvice(
            id: 'dead_${prod.id}',
            severity: AdviceSeverity.opportunity,
            title: s.adviceDeadStockTitle(prod.name),
            body: s.adviceDeadStockBody(
              prod.stock,
              _fmtAdviceMoney(prod.inventoryValue),
            ),
            product: prod,
            actionType: AdviceActionType.openProduct,
          ),
        );
      }
    }

    // 6. Info: Peak weekday reminder (if today or tomorrow is the strongest weekday).
    final weekdays = salesByWeekday(SalesDateFilter.all);
    final activeWeekdays = weekdays.where((w) => w.ordersCount > 0).toList();
    if (activeWeekdays.length >= 3) {
      activeWeekdays.sort((a, b) => b.revenue.compareTo(a.revenue));
      final peakDay = activeWeekdays.first.key;
      final tomorrowDay = (now.weekday % 7) + 1;
      if (peakDay == now.weekday || peakDay == tomorrowDay) {
        final topHits = topSellingProducts(SalesDateFilter.all)
            .take(3)
            .map((e) => e.productName)
            .join(', ');
        if (topHits.isNotEmpty) {
          advices.add(
            DailyProductAdvice(
              id: 'peak_day_$peakDay',
              severity: AdviceSeverity.info,
              title: s.advicePeakDayTitle(s.weekdayFull(peakDay)),
              body: s.advicePeakDayBody(topHits),
            ),
          );
        }
      }
    }

    // 7. Opportunity: Missing regular/wholesale customers (usually buy every 1-2 weeks, quiet >= 28 days).
    final salesByCustomer = <String, ({String name, List<DateTime> dates, double spent})>{};
    for (final sale in sales) {
      final rawName = sale.customerName.trim();
      final key = rawName.toLowerCase();
      if (rawName.isEmpty || key == 'unknown') continue;
      final prev = salesByCustomer[key];
      if (prev == null) {
        salesByCustomer[key] = (
          name: rawName,
          dates: [sale.createdAt],
          spent: sale.total,
        );
      } else {
        prev.dates.add(sale.createdAt);
        salesByCustomer[key] = (
          name: prev.name,
          dates: prev.dates,
          spent: prev.spent + sale.total,
        );
      }
    }

    final missingCustomers = <({
      String key,
      String name,
      int daysSince,
      int avgGapDays,
      double spent,
      bool isVip,
    })>[];
    for (final entry in salesByCustomer.entries) {
      final dates = entry.value.dates..sort();
      final cust = findCustomerByName(entry.value.name);
      final isVip = cust != null &&
          (cust.segment == CustomerSegment.regular ||
              cust.segment == CustomerSegment.wholesale);
      final minOrders = isVip ? 2 : 3;
      if (dates.length < minOrders) continue;

      final daysSince = now.difference(dates.last).inDays;
      if (daysSince < 28 || daysSince > 180) continue;

      final recentDates =
          dates.length > 6 ? dates.sublist(dates.length - 6) : dates;
      final spanDays =
          recentDates.last.difference(recentDates.first).inDays;
      final avgGapDays = spanDays / (recentDates.length - 1);
      if (avgGapDays < 1 || avgGapDays > 21) continue;
      if (daysSince < avgGapDays * 2) continue;

      missingCustomers.add((
        key: entry.key,
        name: entry.value.name,
        daysSince: daysSince,
        avgGapDays: avgGapDays.round().clamp(1, 21),
        spent: entry.value.spent,
        isVip: isVip,
      ));
    }
    missingCustomers.sort((a, b) {
      if (a.isVip != b.isVip) return a.isVip ? -1 : 1;
      return b.spent.compareTo(a.spent);
    });
    for (final mc in missingCustomers.take(3)) {
      advices.add(
        DailyProductAdvice(
          id: 'missing_cust_${mc.key.hashCode}',
          severity: AdviceSeverity.opportunity,
          title: s.adviceMissingCustomerTitle(mc.name),
          body: s.adviceMissingCustomerBody(
            mc.daysSince,
            mc.avgGapDays,
            _fmtAdviceMoney(mc.spent),
          ),
          customerName: mc.name,
          customerPhone: customerPhoneByName(mc.name),
          whatsappMessage: s.missingCustomerWhatsAppMsg(
            customerName: mc.name,
            shopName: _shopName,
          ),
          actionType: AdviceActionType.messageCustomer,
        ),
      );
    }

    // 8. Info: Products missing barcodes.
    final noBarcode = active.where((p) => p.sku.trim().isEmpty).toList();
    if (noBarcode.isNotEmpty) {
      advices.add(
        DailyProductAdvice(
          id: 'no_barcode_${noBarcode.first.id}',
          severity: AdviceSeverity.info,
          title: s.adviceMissingBarcodeTitle(noBarcode.length),
          body: s.adviceMissingBarcodeBody(noBarcode.first.name),
          product: noBarcode.first,
          actionType: AdviceActionType.barcodeLabel,
        ),
      );
    }

    final result = List<DailyProductAdvice>.unmodifiable(advices);
    _cachedDailyAdvices = result;
    _cachedDailyAdvicesKey = cacheKey;
    return result;
  }

  /// Picks today's featured advice deterministically based on the calendar date,
  /// prioritizing urgent items while rotating daily so the banner stays fresh.
  DailyProductAdvice? featuredDailyAdvice([List<DailyProductAdvice>? cached]) {
    final list = cached ?? dailyProductAdvices();
    if (list.isEmpty) return null;
    final urgent =
        list.where((a) => a.severity == AdviceSeverity.urgent).toList();
    final pool = urgent.isNotEmpty ? urgent : list;
    final now = DateTime.now();
    final daySeed = now.year * 1000 + now.month * 32 + now.day;
    return pool[daySeed % pool.length];
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
                currencyCode: record.currencyCode,
                exchangeRate: record.exchangeRate,
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
      var totalUnits = 0.0;
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
          product.nomenclature.trim().toLowerCase() == normalized ||
          product.extraBarcodes
              .any((b) => b.trim().toLowerCase() == normalized)) {
        return product;
      }
    }
    return null;
  }

  Future<Product?> attachBarcodeToProduct(
    String productId,
    String rawBarcode,
  ) async {
    final code = InputNormalizer.normalizeBarcode(rawBarcode);
    if (code.isEmpty) return null;
    final existing = findProductBySku(code);
    if (existing != null) {
      return existing.id == productId ? existing : null;
    }
    final index = _products.indexWhere((p) => p.id == productId);
    if (index < 0) return null;
    final product = _products[index];
    final updated = product.sku.trim().isEmpty
        ? product.copyWith(sku: code, updatedAt: DateTime.now())
        : product.copyWith(
            extraBarcodes: [...product.extraBarcodes, code],
            updatedAt: DateTime.now(),
          );
    await updateProduct(updated);
    return findProductById(productId) ?? updated;
  }

  static int computeEan13CheckDigit(String first12) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final digit = first12.codeUnitAt(i) - 48;
      sum += i.isEven ? digit : digit * 3;
    }
    return (10 - (sum % 10)) % 10;
  }

  static bool isValidEan13(String raw) {
    final code = raw.trim();
    if (code.length != 13) return false;
    for (var i = 0; i < 13; i++) {
      final c = code.codeUnitAt(i);
      if (c < 48 || c > 57) return false;
    }
    final expected = computeEan13CheckDigit(code.substring(0, 12));
    return (code.codeUnitAt(12) - 48) == expected;
  }

  /// Generates a unique, valid GS1 internal-use EAN-13 barcode.
  /// Prefixes in 200-299 are reserved for in-store / internal numbering.
  /// Defaults: '200' for unit SKU, '201' for pack, '202' for box.
  String generateUniqueEan13({String prefix = '200'}) {
    final cleanPrefix = prefix.replaceAll(RegExp(r'[^0-9]'), '');
    final pfx = cleanPrefix.length >= 3
        ? cleanPrefix.substring(0, 3)
        : cleanPrefix.padRight(3, '0');
    final existing = <String>{};
    for (final p in _products) {
      if (p.sku.trim().isNotEmpty) existing.add(p.sku.trim());
      if (p.packBarcode.trim().isNotEmpty) existing.add(p.packBarcode.trim());
      if (p.boxBarcode.trim().isNotEmpty) existing.add(p.boxBarcode.trim());
    }
    final rng = Random();
    for (var attempt = 0; attempt < 500; attempt++) {
      final buf = StringBuffer(pfx);
      for (var i = 0; i < 9; i++) {
        buf.write(rng.nextInt(10));
      }
      final first12 = buf.toString();
      final candidate = '$first12${computeEan13CheckDigit(first12)}';
      if (!existing.contains(candidate)) {
        return candidate;
      }
    }
    final fallbackTail = (DateTime.now().microsecondsSinceEpoch % 1000000000)
        .toString()
        .padLeft(9, '0');
    final first12 = '$pfx$fallbackTail';
    return '$first12${computeEan13CheckDigit(first12)}';
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
    String imagePath = '',
    required double costPrice,
    required double sellPrice,
    double wholesalePrice = 0,
    int wholesaleMinQty = 0,
    required double stock,
    int lowStockThreshold = 5,
    DateTime? expiryDate,
  }) async {
    final now = DateTime.now();
    final cleanStock = stock < 0 ? 0.0 : stock;
    final normCategory = InputNormalizer.normalizeDisplayName(category);
    final product = Product(
      id: _nextId('prd'),
      name: InputNormalizer.normalizeDisplayName(name),
      category: normCategory.isEmpty ? 'General' : normCategory,
      sku: InputNormalizer.normalizeBarcode(sku),
      nomenclature: InputNormalizer.normalizeDisplayName(nomenclature),
      printName: InputNormalizer.normalizeDisplayName(printName),
      packQty: InputNormalizer.normalizeDisplayName(packQty),
      boxQty: InputNormalizer.normalizeDisplayName(boxQty),
      packBarcode: InputNormalizer.normalizeBarcode(packBarcode),
      boxBarcode: InputNormalizer.normalizeBarcode(boxBarcode),
      unitWeight: InputNormalizer.normalizeDisplayName(unitWeight),
      unit: InputNormalizer.normalizeDisplayName(unit),
      imagePath: imagePath.trim(),
      costPrice: costPrice,
      sellPrice: sellPrice,
      wholesalePrice: wholesalePrice < 0 ? 0 : wholesalePrice,
      wholesaleMinQty: wholesaleMinQty < 0 ? 0 : wholesaleMinQty,
      stock: cleanStock,
      lowStockThreshold: lowStockThreshold < 0 ? 0 : lowStockThreshold,
      expiryDate: expiryDate,
      outOfStockSince: cleanStock <= 0 ? now : null,
      updatedAt: now,
    );
    _products.insert(0, product);
    _recordProductCreated(product, 'create');
    _incrementFeatureUsageInMemory(FeatureUsageKeys.productAdd);
    notifyListeners();
    await _persist();
    return product;
  }

  List<Product> expiringProducts({int withinDays = 30, DateTime? now}) {
    final ref = now ?? DateTime.now();
    final list = products
        .where(
          (p) =>
              p.stock > 0 && p.isExpiringOrExpired(withinDays: withinDays, now: ref),
        )
        .toList()
      ..sort((a, b) {
        final da = a.daysUntilExpiry(now: ref) ?? 999999;
        final db = b.daysUntilExpiry(now: ref) ?? 999999;
        return da.compareTo(db);
      });
    return list;
  }

  Future<void> updateProduct(Product updated, {DateTime? at}) async {
    final index = _products.indexWhere((p) => p.id == updated.id);
    if (index == -1) return;
    final before = _products[index];
    final now = at ?? DateTime.now();
    final next = _applyStockOutTracking(
      before,
      updated.copyWith(updatedAt: now),
      now,
    );
    _products[index] = next;
    _recordProductChange(before, next, 'edit', now: now);
    _incrementFeatureUsageInMemory(FeatureUsageKeys.productEdit);
    if (!updated.isActive) {
      _cart.remove(updated.id);
      _cartCustomPrices.remove(updated.id);
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
        final next = current.copyWith(
          category: cleanCategory,
          updatedAt: now,
        );
        _products[i] = next;
        _recordProductChange(current, next, 'edit');
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
    String currencyCode = '',
    double? exchangeRate,
    required List<StockInItem> items,
    bool recordAsExpense = true,
    bool isCredit = false,
    double paidAmount = 0,
  }) async {
    if (items.isEmpty) return;
    final now = DateTime.now();

    for (final item in items) {
      if (item.quantity <= 0) continue;
      final index = _products.indexWhere((p) => p.id == item.productId);
      if (index != -1) {
        final current = _products[index];
        final next = _applyStockOutTracking(
          current,
          current.copyWith(
            stock: current.stock + item.quantity,
            costPrice: item.unitCost > 0 ? item.unitCost : current.costPrice,
            sellPrice: (item.newSellPrice != null && item.newSellPrice! > 0)
                ? item.newSellPrice!
                : current.sellPrice,
            updatedAt: now,
          ),
          now,
        );
        _products[index] = next;
        _recordProductChange(current, next, 'stock_in');
        if ((next.sellPrice - current.sellPrice).abs() > 0.009 &&
            !_priceTagQueue.contains(current.id)) {
          _priceTagQueue.add(current.id);
        }
      }
    }

    final cleanRate =
        (exchangeRate != null && exchangeRate > 0) ? exchangeRate : null;
    final rawTotalCost = items.fold(0.0, (sum, i) => sum + i.lineTotal);
    final resolvedPaid =
        isCredit ? paidAmount.clamp(0.0, rawTotalCost) : rawTotalCost;
    final record = StockInRecord(
      id: _nextId('in'),
      supplierName: supplierName.trim(),
      currencyCode: cleanRate != null ? currencyCode.trim().toUpperCase() : '',
      exchangeRate: cleanRate,
      items: items,
      isCredit: isCredit,
      paidAmount: isCredit ? resolvedPaid : 0,
      paidAt: (isCredit && resolvedPaid >= rawTotalCost - 0.009) ? now : null,
      paymentHistory: (isCredit && resolvedPaid > 0.009)
          ? [SupplierDebtPayment(amount: resolvedPaid, paidAt: now)]
          : const [],
      createdAt: now,
    );
    _stockIns.insert(0, record);
    _stockInDraft = null;

    final expenseAmount = isCredit ? resolvedPaid : record.totalCost;
    if (recordAsExpense && expenseAmount > 0.009) {
      final label = supplierName.trim().isEmpty
          ? 'Stock-in (${record.totalUnits})'
          : 'Stock-in: ${supplierName.trim()}';
      _expenses.insert(
        0,
        Expense(
          id: _nextId('exp'),
          title: label,
          category: ExpenseCategory.purchase,
          amount: expenseAmount,
          createdAt: now,
        ),
      );
    }

    notifyListeners();
    await _persist();
  }

  Future<void> recordSupplierPayment(
    String stockInId,
    double amount, {
    bool recordAsExpense = true,
  }) async {
    if (amount <= 0) return;
    final index = _stockIns.indexWhere((s) => s.id == stockInId);
    if (index == -1) return;
    final rec = _stockIns[index];
    if (rec.isPaid) return;

    final currentPaid = rec.effectivePaidAmount;
    final nextPaid = (currentPaid + amount).clamp(0.0, rec.totalCost);
    final applied = nextPaid - currentPaid;
    if (applied <= 0.009) return;

    final now = DateTime.now();
    final history = List<SupplierDebtPayment>.from(rec.paymentHistory)
      ..add(SupplierDebtPayment(amount: applied, paidAt: now));
    _stockIns[index] = rec.copyWith(
      isCredit: true,
      paidAmount: nextPaid,
      paidAt: nextPaid >= rec.totalCost - 0.009 ? now : null,
      paymentHistory: history,
    );

    if (recordAsExpense) {
      _expenses.insert(
        0,
        Expense(
          id: _nextId('exp'),
          title: strings.supplierDebtRepaymentTitle(rec.supplierName),
          category: ExpenseCategory.purchase,
          amount: applied,
          createdAt: now,
        ),
      );
    }

    notifyListeners();
    await _persist();
  }

  Future<void> markStockInPaid(
    String stockInId, {
    bool recordAsExpense = true,
  }) async {
    final index = _stockIns.indexWhere((s) => s.id == stockInId);
    if (index == -1) return;
    final rec = _stockIns[index];
    if (rec.isPaid) return;
    await recordSupplierPayment(
      stockInId,
      rec.remainingDebt,
      recordAsExpense: recordAsExpense,
    );
  }

  Future<void> markAllSupplierDebtsPaid(
    String supplierName, {
    bool recordAsExpense = true,
  }) async {
    final target = supplierName.trim().toLowerCase();
    final now = DateTime.now();
    var totalApplied = 0.0;
    var changed = false;

    for (var i = 0; i < _stockIns.length; i++) {
      final rec = _stockIns[i];
      if (rec.isPaid) continue;
      if (rec.supplierName.trim().toLowerCase() != target) continue;
      final applied = rec.remainingDebt;
      if (applied <= 0.009) continue;
      final history = List<SupplierDebtPayment>.from(rec.paymentHistory)
        ..add(SupplierDebtPayment(amount: applied, paidAt: now));
      _stockIns[i] = rec.copyWith(
        isCredit: true,
        paidAmount: rec.totalCost,
        paidAt: now,
        paymentHistory: history,
      );
      totalApplied += applied;
      changed = true;
    }

    if (changed && recordAsExpense && totalApplied > 0.009) {
      _expenses.insert(
        0,
        Expense(
          id: _nextId('exp'),
          title: strings.supplierDebtRepaymentTitle(supplierName),
          category: ExpenseCategory.purchase,
          amount: totalApplied,
          createdAt: now,
        ),
      );
    }

    if (changed) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> recordStockInDiscrepancy({
    required String stockInId,
    required Map<
            String,
            ({
              StockInDiscrepancyType? type,
              double qty,
              String note,
            })>
        discrepancies,
    bool deductFromStock = true,
  }) async {
    final index = _stockIns.indexWhere((s) => s.id == stockInId);
    if (index == -1) return;
    final rec = _stockIns[index];
    final now = DateTime.now();
    var changed = false;
    final nextItems = <StockInItem>[];

    for (final item in rec.items) {
      final entry = discrepancies[item.productId];
      if (entry == null) {
        nextItems.add(item);
        continue;
      }
      final cleanQty = entry.qty < 0 ? 0.0 : entry.qty;
      final hasNew = entry.type != null && cleanQty > 0.0005;
      final cleanNote = hasNew ? entry.note.trim() : '';

      final oldQty = item.hasDiscrepancy ? item.discrepancyQty : 0.0;
      final newQty = hasNew ? cleanQty : 0.0;

      if (deductFromStock) {
        final delta = newQty - oldQty;
        if (delta.abs() > 0.0005) {
          final productIndex =
              _products.indexWhere((p) => p.id == item.productId);
          if (productIndex != -1) {
            final current = _products[productIndex];
            final nextStock = current.stock - delta;
            final next = _applyStockOutTracking(
              current,
              current.copyWith(
                stock: nextStock < 0 ? 0.0 : nextStock,
                updatedAt: now,
              ),
              now,
            );
            _products[productIndex] = next;
            _recordProductChange(current, next, 'stock_in_discrepancy');
          }
        }
      }

      if (hasNew) {
        if (item.discrepancyType != entry.type ||
            (item.discrepancyQty - cleanQty).abs() > 0.0005 ||
            item.discrepancyNote != cleanNote) {
          changed = true;
        }
        nextItems.add(
          item.copyWith(
            discrepancyType: entry.type,
            discrepancyQty: cleanQty,
            discrepancyNote: cleanNote,
          ),
        );
      } else {
        if (item.hasDiscrepancy) {
          changed = true;
        }
        nextItems.add(item.copyWith(clearDiscrepancy: true));
      }
    }

    if (!changed) return;
    _stockIns[index] = rec.copyWith(items: nextItems);
    notifyListeners();
    await _persist();
  }

  Future<void> repeatStockIn(StockInRecord record) async {
    final quantities = <String, double>{};
    final unitCosts = <String, double>{};
    final sellPrices = <String, double>{};
    for (final item in record.items) {
      if (item.quantity <= 0) continue;
      final product = findProductById(item.productId);
      if (product == null || !product.isActive) continue;
      quantities[product.id] = (quantities[product.id] ?? 0) + item.quantity;
      unitCosts[product.id] = item.unitCost;
      sellPrices[product.id] =
          (item.newSellPrice != null && item.newSellPrice! > 0)
              ? item.newSellPrice!
              : product.sellPrice;
    }
    await saveStockInDraft(
      StockInDraft(
        supplierName: record.supplierName,
        currencyCode: record.currencyCode,
        exchangeRate: record.exchangeRate,
        recordAsExpense: true,
        quantities: quantities,
        unitCosts: unitCosts,
        sellPrices: sellPrices,
      ),
    );
  }

  Future<void> deleteStockIn(String stockInId) async {
    final idx = _stockIns.indexWhere((s) => s.id == stockInId);
    if (idx == -1) return;
    final record = _stockIns.removeAt(idx);
    final now = DateTime.now();

    for (final item in record.items) {
      if (item.quantity <= 0) continue;
      final productIndex = _products.indexWhere((p) => p.id == item.productId);
      if (productIndex != -1) {
        final current = _products[productIndex];
        final nextStock = current.stock - item.quantity;
        final next = _applyStockOutTracking(
          current,
          current.copyWith(
            stock: nextStock < 0 ? 0 : nextStock,
            updatedAt: now,
          ),
          now,
        );
        _products[productIndex] = next;
        _recordProductChange(current, next, 'stock_in_delete');
      }
    }

    _expenses.removeWhere(
      (e) =>
          e.category == ExpenseCategory.purchase &&
          (e.amount - record.totalCost).abs() < 0.01 &&
          e.createdAt.difference(record.createdAt).inSeconds.abs() <= 2,
    );

    notifyListeners();
    await _persist();
  }

  Future<int> applyStocktake(Map<String, double> actualCounts) async {
    var adjusted = 0;
    final now = DateTime.now();
    for (final entry in actualCounts.entries) {
      final index = _products.indexWhere((p) => p.id == entry.key);
      if (index == -1) continue;
      final cleanCount = entry.value < 0 ? 0.0 : entry.value;
      if (_products[index].stock != cleanCount) {
        final before = _products[index];
        final next = _applyStockOutTracking(
          before,
          before.copyWith(
            stock: cleanCount,
            updatedAt: now,
          ),
          now,
        );
        _products[index] = next;
        _recordProductChange(before, next, 'stocktake');
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
        _recordProductStatusChange(
          current,
          strings.statusActiveLabel,
          strings.statusArchivedLabel,
          'archive',
        );
        _cart.remove(current.id);
        moved += 1;
      }
    }
    if (moved >= 2) {
      _bulkDeleteAuthorized = true;
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
    final current = _products[index];
    _products[index] = current.copyWith(
      clearArchivedAt: true,
      clearTrashedAt: true,
      updatedAt: DateTime.now(),
    );
    _recordProductStatusChange(
      current,
      strings.statusArchivedLabel,
      strings.statusActiveLabel,
      'restore',
    );
    notifyListeners();
    await _persist();
  }

  Future<int> restoreAllProductsFromArchive() async {
    final now = DateTime.now();
    var restored = 0;
    for (var i = 0; i < _products.length; i++) {
      if (_products[i].isArchived) {
        final current = _products[i];
        _products[i] = current.copyWith(
          clearArchivedAt: true,
          clearTrashedAt: true,
          updatedAt: now,
        );
        _recordProductStatusChange(
          current,
          strings.statusArchivedLabel,
          strings.statusActiveLabel,
          'restore',
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
        final oldStatus = current.isArchived
            ? strings.statusArchivedLabel
            : strings.statusActiveLabel;
        _products[i] = current.copyWith(
          trashedAt: now,
          updatedAt: now,
        );
        _recordProductStatusChange(
          current,
          oldStatus,
          strings.statusTrashedLabel,
          'trash',
        );
        _cart.remove(current.id);
        moved += 1;
      }
    }
    if (moved >= 2) {
      _bulkDeleteAuthorized = true;
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
    final current = _products[index];
    _products[index] = current.copyWith(
      clearArchivedAt: true,
      clearTrashedAt: true,
      updatedAt: DateTime.now(),
    );
    _recordProductStatusChange(
      current,
      strings.statusTrashedLabel,
      strings.statusActiveLabel,
      'restore',
    );
    notifyListeners();
    await _persist();
  }

  Future<int> restoreAllProductsFromTrash() async {
    final now = DateTime.now();
    var restored = 0;
    for (var i = 0; i < _products.length; i++) {
      if (_products[i].isTrashed) {
        final current = _products[i];
        _products[i] = current.copyWith(
          clearArchivedAt: true,
          clearTrashedAt: true,
          updatedAt: now,
        );
        _recordProductStatusChange(
          current,
          strings.statusTrashedLabel,
          strings.statusActiveLabel,
          'restore',
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
        _recordProductStatusChange(
          current,
          strings.statusTrashedLabel,
          strings.statusArchivedLabel,
          'archive',
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
        _recordProductStatusChange(
          current,
          strings.statusArchivedLabel,
          strings.statusActiveLabel,
          'restore',
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
        _recordProductStatusChange(
          current,
          strings.statusTrashedLabel,
          strings.statusActiveLabel,
          'restore',
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
    if (removed >= 2) {
      _bulkDeleteAuthorized = true;
    }
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

  bool _autoWholesaleByCustomer = false;
  bool get wholesaleCartMode => _wholesaleCartMode;

  void setWholesaleCartMode(bool enabled) {
    _autoWholesaleByCustomer = false;
    if (_wholesaleCartMode == enabled) return;
    _wholesaleCartMode = enabled;
    if (enabled) {
      trackFeatureUsage(FeatureUsageKeys.wholesaleMode);
    }
    notifyListeners();
  }

  /// Automatically enables wholesale pricing when [customerName] belongs to a
  /// `CustomerSegment.wholesale` customer, and reverts it if switched away
  /// from a wholesale customer (when it was auto-enabled).
  CustomerSegment? applyCustomerSegmentForCart(String customerName) {
    final clean = customerName.trim();
    if (clean.isEmpty) {
      if (_autoWholesaleByCustomer) {
        _autoWholesaleByCustomer = false;
        if (_wholesaleCartMode) {
          _wholesaleCartMode = false;
          notifyListeners();
        }
      }
      return null;
    }
    final existing = findCustomerByName(clean);
    if (existing == null) {
      if (_autoWholesaleByCustomer) {
        _autoWholesaleByCustomer = false;
        if (_wholesaleCartMode) {
          _wholesaleCartMode = false;
          notifyListeners();
        }
      }
      return null;
    }
    if (existing.segment == CustomerSegment.wholesale) {
      if (!_wholesaleCartMode) {
        _wholesaleCartMode = true;
        _autoWholesaleByCustomer = true;
        trackFeatureUsage(FeatureUsageKeys.wholesaleMode);
        notifyListeners();
      }
    } else if (_autoWholesaleByCustomer) {
      _autoWholesaleByCustomer = false;
      if (_wholesaleCartMode) {
        _wholesaleCartMode = false;
        notifyListeners();
      }
    }
    return existing.segment;
  }

  Sale? lastSaleForCustomer(String customerName) {
    final list = salesForCustomer(customerName);
    if (list.isEmpty) return null;
    for (final s in list) {
      if (s.items.isNotEmpty) return s;
    }
    return list.first;
  }

  ({int addedLines, int skippedCount}) repeatSaleToCart(
    Sale sale, {
    bool replaceCart = true,
  }) {
    if (replaceCart) {
      _cart.clear();
      _cartCustomPrices.clear();
    }
    var addedLines = 0;
    var skippedCount = 0;
    for (final item in sale.items) {
      final product = findProductById(item.productId);
      if (product == null || !product.isActive) {
        skippedCount += 1;
        continue;
      }
      final existingQty = replaceCart ? 0.0 : (_cart[product.id] ?? 0.0);
      final targetQty = canSellNegativeStock
          ? existingQty + item.quantity
          : (existingQty + item.quantity).clamp(0.0, product.stock);
      if (targetQty <= existingQty + 0.0005) {
        skippedCount += 1;
        continue;
      }
      _cart[product.id] = targetQty;
      addedLines += 1;
    }
    if (sale.customerName.trim().isNotEmpty) {
      applyCustomerSegmentForCart(sale.customerName);
    }
    notifyListeners();
    return (addedLines: addedLines, skippedCount: skippedCount);
  }

  bool isWholesaleDisabledFor(String productId) =>
      _wholesaleDisabledProducts.contains(productId);

  void setWholesaleDisabledFor(String productId, bool disabled) {
    final changed = disabled
        ? _wholesaleDisabledProducts.add(productId)
        : _wholesaleDisabledProducts.remove(productId);
    if (changed) {
      notifyListeners();
    }
  }

  List<CartLine> get cartLines {
    final lines = <CartLine>[];
    for (final entry in _cart.entries) {
      final product = findProductById(entry.key) ?? _customCartProducts[entry.key];
      if (product != null && product.isActive && entry.value > 0) {
        lines.add(
          CartLine(
            product: product,
            quantity: entry.value,
            customUnitPrice: _cartCustomPrices[entry.key],
            useWholesalePrice: _wholesaleCartMode,
            wholesaleDisabled: _wholesaleDisabledProducts.contains(entry.key),
          ),
        );
      }
    }
    return lines;
  }

  double get cartItemCount =>
      _cart.values.fold(0.0, (sum, quantity) => sum + quantity);

  double get cartSubtotal =>
      cartLines.fold(0.0, (sum, line) => sum + line.lineTotal);

  double get cartTotalCost =>
      cartLines.fold(0.0, (sum, line) => sum + line.lineCost);

  double get cartEstimatedProfit =>
      cartLines.fold(0.0, (sum, line) => sum + line.lineProfit);

  Map<String, Map<String, int>> _ensureCoOccurrenceMatrix() {
    final topId = _sales.isNotEmpty ? _sales.first.id : '';
    if (_cachedCoOccurrence != null &&
        _cachedCoOccurrenceSalesCount == _sales.length &&
        _cachedCoOccurrenceTopSaleId == topId) {
      return _cachedCoOccurrence!;
    }
    final matrix = <String, Map<String, int>>{};
    for (final sale in _sales) {
      if (!sale.isActive || sale.items.length < 2) continue;
      final ids = sale.items.map((i) => i.productId).toSet().toList();
      if (ids.length < 2) continue;
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final a = ids[i];
          final b = ids[j];
          final mapA = matrix.putIfAbsent(a, () => {});
          mapA[b] = (mapA[b] ?? 0) + 1;
          final mapB = matrix.putIfAbsent(b, () => {});
          mapB[a] = (mapB[a] ?? 0) + 1;
        }
      }
    }
    _cachedCoOccurrence = matrix;
    _cachedCoOccurrenceSalesCount = _sales.length;
    _cachedCoOccurrenceTopSaleId = topId;
    return matrix;
  }

  List<Product> frequentlyBoughtTogetherForCart({int limit = 3}) {
    if (_cart.isEmpty) return const [];
    final inCartIds = _cart.keys.toSet();
    final matrix = _ensureCoOccurrenceMatrix();
    final scores = <String, int>{};

    for (final cartId in inCartIds) {
      final neighbors = matrix[cartId];
      if (neighbors == null) continue;
      for (final entry in neighbors.entries) {
        if (inCartIds.contains(entry.key)) continue;
        scores[entry.key] = (scores[entry.key] ?? 0) + entry.value;
      }
    }
    if (scores.isEmpty) return const [];

    final candidates = <({Product product, int score})>[];
    for (final entry in scores.entries) {
      final p = findProductById(entry.key);
      if (p == null || !p.isActive) continue;
      if (!canSellNegativeStock && p.stock <= 0) continue;
      candidates.add((product: p, score: entry.value));
    }
    candidates.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.product.name.toLowerCase().compareTo(b.product.name.toLowerCase());
    });
    return candidates.take(limit).map((e) => e.product).toList();
  }

  bool get hasBelowCostCartItems => cartLines.any(
        (line) =>
            line.product.costPrice > 0 &&
            line.unitPrice + 0.009 < line.product.costPrice,
      );

  bool isSaleBelowCost({double discount = 0}) {
    if (hasBelowCostCartItems) return true;
    final totalCost = cartTotalCost;
    if (totalCost <= 0) return false;
    final finalTotal = (cartSubtotal - discount).clamp(0.0, double.infinity);
    return finalTotal + 0.009 < totalCost;
  }

  double cartQuantityFor(String productId) => _cart[productId] ?? 0;

  bool addToCart(String productId, {double quantity = 1}) {
    final product = findProductById(productId);
    if (product == null || !product.isActive || quantity <= 0) {
      return false;
    }
    final existing = _cart[productId] ?? 0;
    final next = existing + quantity;
    if (!canSellNegativeStock && (product.stock <= 0 || next > product.stock)) {
      return false;
    }
    _cart[productId] = next;
    notifyListeners();
    return true;
  }

  String addCustomCartItem({
    required double price,
    String name = '',
    double quantity = 1,
  }) {
    if (price <= 0 || quantity <= 0) return '';
    final id = _nextId('custom');
    final cleanName = name.trim().isEmpty
        ? strings.customPosItemDefaultName
        : InputNormalizer.normalizeDisplayName(name);
    _customCartProducts[id] = Product(
      id: id,
      name: cleanName,
      category: '',
      costPrice: 0,
      sellPrice: price,
      stock: 999999,
      updatedAt: DateTime.now(),
    );
    _cart[id] = quantity;
    notifyListeners();
    return id;
  }

  void setCartQuantity(String productId, double quantity) {
    final custom = _customCartProducts[productId];
    if (custom != null) {
      if (quantity <= 0) {
        _cart.remove(productId);
        _cartCustomPrices.remove(productId);
        _customCartProducts.remove(productId);
      } else {
        _cart[productId] = quantity;
      }
      notifyListeners();
      return;
    }
    final product = findProductById(productId);
    if (product == null || !product.isActive || quantity <= 0) {
      _cart.remove(productId);
      _cartCustomPrices.remove(productId);
      _wholesaleDisabledProducts.remove(productId);
      notifyListeners();
      return;
    }
    if (!canSellNegativeStock) {
      if (product.stock <= 0) {
        _cart.remove(productId);
        _cartCustomPrices.remove(productId);
        _wholesaleDisabledProducts.remove(productId);
        notifyListeners();
        return;
      }
      _cart[productId] = quantity > product.stock ? product.stock : quantity;
    } else {
      _cart[productId] = quantity;
    }
    notifyListeners();
  }

  void setCartItemPrice(String productId, double? price) {
    final product = findProductById(productId) ?? _customCartProducts[productId];
    if (product == null || price == null || price <= 0) {
      _cartCustomPrices.remove(productId);
      notifyListeners();
      return;
    }
    final qty = _cart[productId] ?? 0;
    final wholesaleDisabled = _wholesaleDisabledProducts.contains(productId);
    final effectiveWholesale = !wholesaleDisabled &&
        product.hasWholesalePrice &&
        (_wholesaleCartMode || product.isAutoWholesaleForQty(qty));
    final defaultPrice =
        effectiveWholesale ? product.wholesalePrice : product.sellPrice;
    if (!canGiveDiscounts && price + 0.009 < defaultPrice) {
      return;
    }
    if ((price - defaultPrice).abs() < 0.009) {
      _cartCustomPrices.remove(productId);
    } else {
      _cartCustomPrices[productId] = price;
    }
    notifyListeners();
  }

  ({
    Map<String, double> quantities,
    Map<String, double> customPrices,
    Map<String, Product> customProducts,
    bool wholesaleMode,
  }) captureCartSnapshot() {
    return (
      quantities: Map<String, double>.from(_cart),
      customPrices: Map<String, double>.from(_cartCustomPrices),
      customProducts: Map<String, Product>.from(_customCartProducts),
      wholesaleMode: _wholesaleCartMode,
    );
  }

  void restoreCartSnapshot(
    ({
      Map<String, double> quantities,
      Map<String, double> customPrices,
      Map<String, Product> customProducts,
      bool wholesaleMode,
    }) snapshot,
  ) {
    _cart
      ..clear()
      ..addAll(snapshot.quantities);
    _cartCustomPrices
      ..clear()
      ..addAll(snapshot.customPrices);
    _customCartProducts
      ..clear()
      ..addAll(snapshot.customProducts);
    _wholesaleCartMode = snapshot.wholesaleMode;
    notifyListeners();
  }

  void clearCart() {
    if (_cart.isEmpty &&
        _customCartProducts.isEmpty &&
        !_wholesaleCartMode &&
        _wholesaleDisabledProducts.isEmpty) {
      return;
    }
    _cart.clear();
    _cartCustomPrices.clear();
    _customCartProducts.clear();
    _wholesaleDisabledProducts.clear();
    _wholesaleCartMode = false;
    _autoWholesaleByCustomer = false;
    notifyListeners();
  }

  Future<Sale?> completeSale({
    PaymentMethod paymentMethod = PaymentMethod.cash,
    PaymentMethod? secondaryPaymentMethod,
    double secondaryAmount = 0,
    String customerName = '',
    String customerPhone = '',
    CustomerSegment? customerSegment,
    double discount = 0,
    String discountReason = '',
    double? paidAmount,
    DateTime? dueDate,
    String? ownerPinAttempt,
  }) async {
    final lines = cartLines;
    if (lines.isEmpty) return null;

    final checkDiscount = discount < 0 ? 0.0 : discount;
    if (_cashierMode &&
        hasOwnerPin &&
        isSaleBelowCost(discount: checkDiscount)) {
      if (ownerPinAttempt == null || !verifyOwnerPin(ownerPinAttempt)) {
        return null;
      }
    }

    if (!canSellNegativeStock) {
      for (final line in lines) {
        if (line.quantity > line.product.stock) {
          return null;
        }
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
    final cleanDiscount = (!canGiveDiscounts || discount < 0) ? 0.0 : discount;
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

    final cleanCustomerName = InputNormalizer.normalizeDisplayName(customerName);
    final cleanCustomerPhone = InputNormalizer.normalizePhone(customerPhone);

    final sale = Sale(
      id: _nextId('sal'),
      items: saleItems,
      paymentMethod: paymentMethod,
      secondaryPaymentMethod: hasValidSplit ? secondaryPaymentMethod : null,
      secondaryAmount: hasValidSplit ? secondaryAmount : 0,
      customerName: cleanCustomerName,
      customerPhone: cleanCustomerPhone,
      sellerName: _activeSeller,
      discount: cleanDiscount,
      discountReason: cleanDiscount > 0.009 ? discountReason.trim() : '',
      paidAmount: resolvedPaid,
      dueDate: paymentMethod == PaymentMethod.postPay ? dueDate : null,
      paidAt: resolvedPaid >= total ? now : null,
      paymentHistory: (paymentMethod == PaymentMethod.postPay && resolvedPaid > 0)
          ? [DebtPayment(amount: resolvedPaid, paidAt: now)]
          : const [],
      createdAt: now,
    );

    if (cleanCustomerName.isNotEmpty) {
      _hiddenCustomerSuggestions.remove(cleanCustomerName.toLowerCase());
      final normCustomerKey = InputNormalizer.normalizeNameKey(cleanCustomerName);
      final existingIdx = _customers.indexWhere((c) {
        if (cleanCustomerPhone.isNotEmpty &&
            InputNormalizer.normalizePhone(c.phone) == cleanCustomerPhone) {
          return true;
        }
        return InputNormalizer.normalizeNameKey(c.name) == normCustomerKey;
      });
      if (existingIdx != -1) {
        final existing = _customers[existingIdx];
        final phoneChanged = cleanCustomerPhone.isNotEmpty &&
            existing.phone.trim() != cleanCustomerPhone;
        final segmentChanged =
            customerSegment != null && existing.segment != customerSegment;
        if (phoneChanged || segmentChanged) {
          _customers[existingIdx] = existing.copyWith(
            phone: phoneChanged ? cleanCustomerPhone : null,
            segment: segmentChanged ? customerSegment : null,
          );
        }
      } else {
        _customers.add(
          Customer(
            id: _nextId('cus'),
            name: cleanCustomerName,
            phone: cleanCustomerPhone,
            segment: customerSegment ?? CustomerSegment.retail,
            createdAt: now,
          ),
        );
        _customers.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      }
    }

    for (final line in lines) {
      final index = _products.indexWhere((p) => p.id == line.product.id);
      if (index != -1) {
        final current = _products[index];
        final nextStock = current.stock - line.quantity;
        _products[index] = _applyStockOutTracking(
          current,
          current.copyWith(
            stock: nextStock,
            updatedAt: now,
          ),
          now,
        );
        if (nextStock < 0) {
          _negativeStockReminders[current.id] = 5;
        }
      }
    }

    _sales.insert(0, sale);
    _cart.clear();
    _cartCustomPrices.clear();
    _customCartProducts.clear();
    _wholesaleDisabledProducts.clear();
    _wholesaleCartMode = false;
    _incrementFeatureUsageInMemory(FeatureUsageKeys.saleComplete);
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
    required Map<String, double> returnQuantities,
    double customRefundAmount = 0,
    List<({Product product, double quantity, double? customUnitPrice})> exchangeItems = const [],
    bool returnToStock = true,
    PaymentMethod? settlementMethod,
    String returnReason = '',
  }) async {
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) return;
    final sale = _sales[index];
    final now = DateTime.now();
    final cleanReason = returnReason.trim();

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
            _products[productIndex] = _applyStockOutTracking(
              current,
              current.copyWith(
                stock: current.stock + retQty,
                updatedAt: now,
              ),
              now,
            );
          }
        } else {
          defectCostTotal += item.unitCost * retQty;
          updatedDefectItems.add(
            DefectWriteOffItem(
              productId: item.productId,
              productName: item.productName,
              quantity: retQty.toDouble(),
              unitCost: item.unitCost,
              reason: cleanReason,
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

      _products[productIndex] = _applyStockOutTracking(
        current,
        current.copyWith(
          stock: current.stock - takeQty,
          updatedAt: now,
        ),
        now,
      );
      exchangeValue += unitPrice * takeQty;
      exchangeParts.add('${current.name} × $takeQty');

      final existingIdx = updatedItems.indexWhere(
        (i) =>
            i.productId == current.id &&
            (i.unitPrice - unitPrice).abs() < 0.009 &&
            (i.unitCost - current.costPrice).abs() < 0.009,
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

    final combinedReason = cleanReason.isEmpty
        ? sale.returnReason
        : (sale.returnReason.isEmpty
            ? cleanReason
            : (sale.returnReason.contains(cleanReason)
                ? sale.returnReason
                : '${sale.returnReason} • $cleanReason'));

    _sales[index] = sale.copyWith(
      items: updatedItems,
      discount: newDiscount,
      cashAdjustments: updatedAdjustments,
      defectItems: updatedDefectItems,
      refundedAmount: nextRefundedAmount,
      returnedMoneyTotal: sale.returnedMoneyTotal + moneyReturned,
      refundNote: noteParts.join(' • '),
      returnReason: combinedReason,
      paidAmount: nextPaidAmount,
    );
    if (!returnToStock && defectCostTotal > 0.009) {
      final defectNote = [
        returnedParts.join(', '),
        if (cleanReason.isNotEmpty) cleanReason,
      ].join(' • ');
      _expenses.insert(
        0,
        Expense(
          id: _nextId('exp'),
          title: strings.defectWriteOffTitle(sale.receiptCode),
          category: ExpenseCategory.other,
          amount: defectCostTotal,
          note: defectNote,
          createdAt: now,
        ),
      );
    }
    _incrementFeatureUsageInMemory(FeatureUsageKeys.returnExchange);
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

  Future<bool> archiveSale(String saleId, {String? ownerPinAttempt}) async {
    if (!_canMutateOrDeleteSale(ownerPinAttempt)) return false;
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) return false;
    _sales[index] = _sales[index].copyWith(
      archivedAt: DateTime.now(),
      clearTrashedAt: true,
    );
    notifyListeners();
    await _persist();
    return true;
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

  Future<bool> moveSaleToTrash(String saleId, {String? ownerPinAttempt}) async {
    if (!_canMutateOrDeleteSale(ownerPinAttempt)) return false;
    final index = _sales.indexWhere((s) => s.id == saleId);
    if (index == -1) return false;
    final sale = _sales[index];
    if (sale.isTrashed) return false;
    final now = DateTime.now();

    for (final item in sale.items) {
      final productIndex = _products.indexWhere((p) => p.id == item.productId);
      if (productIndex != -1) {
        final current = _products[productIndex];
        _products[productIndex] = _applyStockOutTracking(
          current,
          current.copyWith(
            stock: current.stock + item.quantity,
            updatedAt: now,
          ),
          now,
        );
      }
    }

    _sales[index] = sale.copyWith(trashedAt: now);
    notifyListeners();
    await _persist();
    return true;
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
        _products[productIndex] = _applyStockOutTracking(
          current,
          current.copyWith(
            stock: current.stock - item.quantity,
            updatedAt: now,
          ),
          now,
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
        _products[productIndex] = _applyStockOutTracking(
          current,
          current.copyWith(
            stock: current.stock - item.quantity,
            updatedAt: now,
          ),
          now,
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

  Future<bool> deleteSalePermanently(
    String saleId, {
    String? ownerPinAttempt,
  }) async {
    if (!_canMutateOrDeleteSale(ownerPinAttempt)) return false;
    final before = _sales.length;
    _sales.removeWhere((s) => s.id == saleId);
    if (_sales.length == before) return false;
    notifyListeners();
    await _persist();
    return true;
  }

  Future<bool> voidSale(String saleId, {String? ownerPinAttempt}) =>
      moveSaleToTrash(saleId, ownerPinAttempt: ownerPinAttempt);

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
    _incrementFeatureUsageInMemory(FeatureUsageKeys.expenseAdd);
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

  Future<void> emptyTrash({String? ownerPinAttempt}) async {
    _products.removeWhere((p) => p.isTrashed);
    if (_canMutateOrDeleteSale(ownerPinAttempt)) {
      _sales.removeWhere((s) => s.isTrashed);
    }
    _expenses.removeWhere((e) => e.isTrashed);
    _bulkDeleteAuthorized = true;
    notifyListeners();
    await _persist();
  }

  /// Permanently removes trashed products, sales, and expenses whose
  /// `trashedAt` timestamp is older than [_trashRetentionDays].
  int purgeExpiredTrash({DateTime? now}) {
    if (_trashRetentionDays <= 0) return 0;
    final cutoff =
        (now ?? DateTime.now()).subtract(Duration(days: _trashRetentionDays));
    var removed = 0;

    final expiredProductIds = _products
        .where((p) => p.isTrashed && p.trashedAt!.isBefore(cutoff))
        .map((p) => p.id)
        .toSet();
    if (expiredProductIds.isNotEmpty) {
      _products.removeWhere((p) => expiredProductIds.contains(p.id));
      for (final id in expiredProductIds) {
        _cart.remove(id);
        _cartCustomPrices.remove(id);
      }
      removed += expiredProductIds.length;
    }

    final beforeSales = _sales.length;
    _sales.removeWhere((s) => s.isTrashed && s.trashedAt!.isBefore(cutoff));
    removed += beforeSales - _sales.length;

    final beforeExpenses = _expenses.length;
    _expenses.removeWhere((e) => e.isTrashed && e.trashedAt!.isBefore(cutoff));
    removed += beforeExpenses - _expenses.length;

    return removed;
  }

  int? daysUntilAutoPurge(DateTime? trashedAt, {DateTime? now}) {
    if (_trashRetentionDays <= 0 || trashedAt == null) return null;
    final expiresAt = trashedAt.add(Duration(days: _trashRetentionDays));
    final diff = expiresAt.difference(now ?? DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  Future<int> setTrashRetentionDays(int days) async {
    await ensureArchiveAndTrashLoaded();
    final clean = days < 0 ? 0 : days;
    final changed = _trashRetentionDays != clean;
    _trashRetentionDays = clean;
    final purged = purgeExpiredTrash();
    if (changed || purged > 0) {
      notifyListeners();
      await _persist();
    }
    return purged;
  }

  List<({int year, int salesCount, int unpaidSalesCount, int stockInsCount})>
      get archivablePastYears {
    final currentYear = DateTime.now().year;
    final byYear = <int, ({int sales, int unpaid, int stockIns})>{};

    for (final s in _sales) {
      final y = s.createdAt.year;
      if (y >= currentYear || s.id.startsWith('yrsum_')) continue;
      final prev = byYear[y] ?? (sales: 0, unpaid: 0, stockIns: 0);
      byYear[y] = (
        sales: prev.sales + 1,
        unpaid: prev.unpaid + (s.isPaid ? 0 : 1),
        stockIns: prev.stockIns,
      );
    }
    for (final r in _stockIns) {
      final y = r.createdAt.year;
      if (y >= currentYear || r.id.startsWith('yrsum_')) continue;
      final prev = byYear[y] ?? (sales: 0, unpaid: 0, stockIns: 0);
      byYear[y] = (
        sales: prev.sales,
        unpaid: prev.unpaid,
        stockIns: prev.stockIns + 1,
      );
    }

    final list = byYear.entries
        .map(
          (e) => (
            year: e.key,
            salesCount: e.value.sales,
            unpaidSalesCount: e.value.unpaid,
            stockInsCount: e.value.stockIns,
          ),
        )
        .toList()
      ..sort((a, b) => b.year.compareTo(a.year));
    return list;
  }

  List<Sale> rawSalesForYear(int year) => _sales
      .where((s) => s.createdAt.year == year && !s.id.startsWith('yrsum_'))
      .toList(growable: false);

  List<StockInRecord> rawStockInsForYear(int year) => _stockIns
      .where((r) => r.createdAt.year == year && !r.id.startsWith('yrsum_'))
      .toList(growable: false);

  Future<
      ({
        int compressedSales,
        int compressedStockIns,
        int keptUnpaidSales,
        int monthlySummariesCreated,
      })> archiveAndCompressYear(int year) async {
    await ensureFullHistoryLoaded();
    if (year >= DateTime.now().year) {
      return (
        compressedSales: 0,
        compressedStockIns: 0,
        keptUnpaidSales: 0,
        monthlySummariesCreated: 0,
      );
    }

    final eligibleSales = _sales
        .where(
          (s) =>
              s.createdAt.year == year &&
              !s.id.startsWith('yrsum_') &&
              s.isPaid,
        )
        .toList();
    final keptUnpaidSales = _sales
        .where(
          (s) =>
              s.createdAt.year == year &&
              !s.id.startsWith('yrsum_') &&
              !s.isPaid,
        )
        .length;
    final eligibleStockIns = _stockIns
        .where((r) => r.createdAt.year == year && !r.id.startsWith('yrsum_'))
        .toList();

    if (eligibleSales.isEmpty && eligibleStockIns.isEmpty) {
      return (
        compressedSales: 0,
        compressedStockIns: 0,
        keptUnpaidSales: keptUnpaidSales,
        monthlySummariesCreated: 0,
      );
    }

    var summariesCreated = 0;

    // Group & compress sales by month
    final salesByMonth = <int, List<Sale>>{};
    for (final s in eligibleSales) {
      salesByMonth.putIfAbsent(s.createdAt.month, () => []).add(s);
    }
    final compressedSaleIds = eligibleSales.map((s) => s.id).toSet();
    _sales.removeWhere((s) => compressedSaleIds.contains(s.id));

    for (final entry in salesByMonth.entries) {
      final month = entry.key;
      final mm = month.toString().padLeft(2, '0');
      final summaryId = 'yrsum_sal_${year}_$mm';
      final existingIdx = _sales.indexWhere((s) => s.id == summaryId);
      final existing = existingIdx != -1 ? _sales[existingIdx] : null;

      var totalRevenue = existing?.total ?? 0.0;
      var totalCost = existing?.totalCost ?? 0.0;
      var totalDiscount = existing?.discount ?? 0.0;
      var totalUnits = existing != null ? existing.totalUnits : 0;
      var ordersCount = entry.value.length;

      for (final s in entry.value) {
        totalRevenue += s.total;
        totalCost += s.totalCost;
        totalDiscount += s.discount;
        totalUnits += s.totalUnits;
      }

      final qty = totalUnits > 0 ? totalUnits.toDouble() : 1.0;
      final unitCost = totalCost / qty;
      final unitPrice = (totalRevenue + totalDiscount) / qty;
      final lastDay = DateTime(year, month + 1, 0, 23, 59);

      final summarySale = Sale(
        id: summaryId,
        items: [
          SaleItem(
            productId: 'yrsum_$year',
            productName: 'Итоги $mm.$year ($ordersCount чек.)',
            quantity: qty,
            unitCost: unitCost,
            unitPrice: unitPrice,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
        discount: totalDiscount,
        paidAmount: totalRevenue,
        paidAt: lastDay,
        createdAt: lastDay,
      );
      if (existingIdx != -1) {
        _sales[existingIdx] = summarySale;
      } else {
        _sales.add(summarySale);
        summariesCreated += 1;
      }
    }

    // Group & compress stock-ins by month
    final stockInsByMonth = <int, List<StockInRecord>>{};
    for (final r in eligibleStockIns) {
      stockInsByMonth.putIfAbsent(r.createdAt.month, () => []).add(r);
    }
    final compressedStockInIds = eligibleStockIns.map((r) => r.id).toSet();
    _stockIns.removeWhere((r) => compressedStockInIds.contains(r.id));

    for (final entry in stockInsByMonth.entries) {
      final month = entry.key;
      final mm = month.toString().padLeft(2, '0');
      final summaryId = 'yrsum_in_${year}_$mm';
      final existingIdx = _stockIns.indexWhere((r) => r.id == summaryId);
      final existing = existingIdx != -1 ? _stockIns[existingIdx] : null;

      var totalCost = existing?.totalCost ?? 0.0;
      var totalUnits = existing?.totalUnits ?? 0;
      final invoicesCount = entry.value.length;

      for (final r in entry.value) {
        totalCost += r.totalCost;
        totalUnits += r.totalUnits;
      }

      final qty = totalUnits > 0 ? totalUnits.toDouble() : 1.0;
      final unitCost = totalCost / qty;
      final lastDay = DateTime(year, month + 1, 0, 23, 59);

      final summaryRecord = StockInRecord(
        id: summaryId,
        supplierName: 'Итоги приходов $mm.$year ($invoicesCount накл.)',
        items: [
          StockInItem(
            productId: 'yrsum_in_$year',
            productName: 'Приходы $mm.$year ($invoicesCount накл.)',
            quantity: qty,
            unitCost: unitCost,
          ),
        ],
        createdAt: lastDay,
      );
      if (existingIdx != -1) {
        _stockIns[existingIdx] = summaryRecord;
      } else {
        _stockIns.add(summaryRecord);
        summariesCreated += 1;
      }
    }

    _sales.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _stockIns.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _bulkDeleteAuthorized = true;
    notifyListeners();
    await _persist();

    return (
      compressedSales: eligibleSales.length,
      compressedStockIns: eligibleStockIns.length,
      keptUnpaidSales: keptUnpaidSales,
      monthlySummariesCreated: summariesCreated,
    );
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

({
  Map<String, String> changedCompressed,
  List<String> removedSections,
  Map<String, String> newHashes,
}) _prepareCloudBackupDelta(
  ({
    ShopDataSnapshot snapshot,
    Map<String, String> prevHashes,
    bool forceFull,
  }) args,
) {
  final sections = GoogleSheetsService.buildBackupSectionJsons(args.snapshot);
  final newHashes = <String, String>{};
  final changedCompressed = <String, String>{};

  for (final entry in sections.entries) {
    final hash = GoogleSheetsService.hashText(entry.value);
    newHashes[entry.key] = hash;
    if (args.forceFull || args.prevHashes[entry.key] != hash) {
      changedCompressed[entry.key] =
          GoogleSheetsService.compressSection(entry.value);
    }
  }

  final removedSections = args.prevHashes.keys
      .where((k) => !sections.containsKey(k))
      .toList(growable: false);

  return (
    changedCompressed: changedCompressed,
    removedSections: removedSections,
    newHashes: newHashes,
  );
}
