import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product.dart';
import '../services/export_service.dart';
import '../services/input_normalizer.dart';
import '../services/sheet_export_helper.dart';
import '../state/shop_controller.dart';
import '../widgets/attach_barcode_sheet.dart';
import '../widgets/barcode_label_sheet.dart';
import '../widgets/price_tag_queue_sheet.dart';
import '../widgets/purchase_order_sheet.dart';
import '../widgets/catalog_health_sheet.dart';
import '../widgets/currency_calculator_dialog.dart';
import '../widgets/daily_advice_sheet.dart';
import '../widgets/formatters.dart';
import '../widgets/frozen_cash_sheet.dart';
import '../widgets/pin_confirm_dialog.dart';
import '../widgets/price_list_sheet.dart';
import '../widgets/product_form_sheet.dart';
import '../widgets/product_thumbnail.dart';
import '../widgets/settings_button.dart';
import '../widgets/stock_in_sheet.dart';
import '../widgets/stocktake_sheet.dart';
import '../widgets/suppliers_sheet.dart';
import '../widgets/voice_search_button.dart';
import 'barcode_scanner_screen.dart';

enum _StockFilter { all, inStock, inMinus, lowStock, outOfStock, expiring }

enum _ProductSort {
  newest,
  priceDesc,
  priceAsc,
  stockDesc,
  stockAsc,
  mostSold,
  nameAsc,
  marginDesc,
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.controller});

  final ShopController controller;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  String _searchQuery = '';
  String? _selectedCategory;
  _StockFilter _stockFilter = _StockFilter.all;
  _ProductSort _sortBy = _ProductSort.newest;
  bool _controlsVisible = true;
  bool _showSummaryHeader = false;
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};
  String? _dismissedAdviceDayKey;
  int _adviceCycleOffset = 0;

  String get _todayKey {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  @override
  void initState() {
    super.initState();
    final savedCat = widget.controller.inventorySelectedCategory;
    _selectedCategory = savedCat.isEmpty ? null : savedCat;
    _sortBy = _ProductSort.values.firstWhere(
      (e) => e.name == widget.controller.inventorySort,
      orElse: () => _ProductSort.newest,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  void _setSelectedCategory(String? category) {
    setState(() => _selectedCategory = category);
    widget.controller.setInventoryViewPreferences(
      category: category,
      updateCategory: true,
    );
  }

  void _selectSort(_ProductSort sort) {
    setState(() => _sortBy = sort);
    widget.controller.setInventoryViewPreferences(sort: sort.name);
    if (_listScrollController.hasClients && _listScrollController.offset > 0) {
      _listScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.metrics.pixels <= 12) {
      if (!_controlsVisible) {
        setState(() => _controlsVisible = true);
      }
      return false;
    }
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.reverse &&
          _controlsVisible &&
          notification.metrics.pixels > 24) {
        setState(() => _controlsVisible = false);
      } else if (notification.direction == ScrollDirection.forward &&
          !_controlsVisible) {
        setState(() => _controlsVisible = true);
      }
    }
    return false;
  }


  String _sortOptionLabel(_ProductSort sort, dynamic strings) {
    switch (sort) {
      case _ProductSort.newest:
        return strings.sortNewest;
      case _ProductSort.priceDesc:
        return strings.sortPriceDesc;
      case _ProductSort.priceAsc:
        return strings.sortPriceAsc;
      case _ProductSort.stockDesc:
        return strings.sortStockDesc;
      case _ProductSort.stockAsc:
        return strings.sortStockAsc;
      case _ProductSort.mostSold:
        return strings.sortMostSold;
      case _ProductSort.nameAsc:
        return strings.sortNameAsc;
      case _ProductSort.marginDesc:
        return strings.sortMarginDesc;
    }
  }

  List<Product> _filteredProducts(Map<String, double> soldUnitsByProduct) {
    final query = _searchQuery.trim().toLowerCase();
    final list = widget.controller.products.where((product) {
      if (_selectedCategory != null && product.category != _selectedCategory) {
        return false;
      }
      switch (_stockFilter) {
        case _StockFilter.all:
          break;
        case _StockFilter.inStock:
          if (product.stock <= 0) return false;
        case _StockFilter.inMinus:
          if (product.stock >= 0) return false;
        case _StockFilter.lowStock:
          if (!product.isLowStock && !product.isOutOfStock) return false;
        case _StockFilter.outOfStock:
          if (product.stock > 0) return false;
        case _StockFilter.expiring:
          if (product.stock <= 0 ||
              !product.isExpiringOrExpired(withinDays: 30)) {
            return false;
          }
      }
      if (query.isEmpty) return true;
      return InputNormalizer.matchesProductSearch(product, _searchQuery);
    }).toList();

    switch (_sortBy) {
      case _ProductSort.newest:
        if (_stockFilter == _StockFilter.expiring) {
          list.sort((a, b) {
            final da = a.daysUntilExpiry() ?? 999999;
            final db = b.daysUntilExpiry() ?? 999999;
            return da.compareTo(db);
          });
        }
        break;
      case _ProductSort.priceDesc:
        list.sort((a, b) => b.sellPrice.compareTo(a.sellPrice));
      case _ProductSort.priceAsc:
        list.sort((a, b) => a.sellPrice.compareTo(b.sellPrice));
      case _ProductSort.stockDesc:
        list.sort((a, b) => b.stock.compareTo(a.stock));
      case _ProductSort.stockAsc:
        list.sort((a, b) => a.stock.compareTo(b.stock));
      case _ProductSort.mostSold:
        list.sort((a, b) {
          final cmp = (soldUnitsByProduct[b.id] ?? 0)
              .compareTo(soldUnitsByProduct[a.id] ?? 0);
          if (cmp != 0) return cmp;
          return b.sellPrice.compareTo(a.sellPrice);
        });
      case _ProductSort.nameAsc:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _ProductSort.marginDesc:
        list.sort((a, b) => b.marginPercent.compareTo(a.marginPercent));
    }
    return list;
  }

  Future<void> _openProductForm({
    Product? existing,
    Product? template,
    String? initialSku,
  }) async {
    final result = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ProductFormSheet(
        controller: widget.controller,
        existing: existing,
        template: template,
        initialSku: initialSku,
        initialCategory: existing == null ? _selectedCategory : null,
        initialStock: template != null ? 0 : 10,
      ),
    );
    if (result != null && mounted) {
      final strings = widget.controller.strings;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? strings.productAdded : strings.productUpdated,
          ),
        ),
      );
    }
  }

  Future<void> _openQuickEdit(Product product) async {
    final strings = widget.controller.strings;
    final result = await showDialog<_QuickEditResult>(
      context: context,
      builder: (_) => _QuickEditProductDialog(
        strings: strings,
        currency: widget.controller.currency,
        product: product,
      ),
    );
    if (result == null || !mounted) return;
    if (result.openFullForm) {
      await _openProductForm(existing: product);
      return;
    }
    await widget.controller.updateProduct(
      product.copyWith(
        sellPrice: result.sellPrice,
        costPrice: result.costPrice,
        wholesalePrice: result.wholesalePrice,
        wholesaleMinQty: result.wholesaleMinQty,
        stock: result.stock,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.productUpdated)),
      );
    }
  }

  void _showProductHistory(Product product) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProductHistorySheet(
        controller: widget.controller,
        product: product,
      ),
    );
  }

  void _showBarcodeLabel(Product product) {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.barcodeLabel);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BarcodeLabelSheet(
        controller: widget.controller,
        product: product,
      ),
    );
  }

  void _openPriceTagQueue() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PriceTagQueueSheet(controller: widget.controller),
    );
  }

  void _openPurchaseOrder() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PurchaseOrderSheet(controller: widget.controller),
    );
  }

  void _openDailyAdvice() {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.dailyAdvice);
    final strings = widget.controller.strings;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DailyAdviceSheet(
        controller: widget.controller,
        onAddToStockIn: (product) async {
          final totalQty =
              await widget.controller.addProductToStockInDraft(product);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                strings.scannedAddedToStockInMsg(1, product.name, totalQty),
              ),
            ),
          );
        },
        onEditPrice: (product) => _openQuickEdit(product),
        onOpenBarcodeLabel: (product) => _showBarcodeLabel(product),
        onOpenProduct: (product) => _showProductHistory(product),
      ),
    );
  }

  Future<void> _openBarcodeLookup() async {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.barcodeScan);
    final strings = widget.controller.strings;
    final sku = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => BarcodeScannerScreen(strings: strings),
      ),
    );

    if (sku == null || sku.trim().isEmpty || !mounted) return;
    final found = widget.controller.findProductBySku(sku);
    if (found != null) {
      if (widget.controller.cashierMode) {
        _searchController.text = found.sku;
        setState(() => _searchQuery = found.sku);
      } else {
        await _openProductForm(existing: found);
      }
    } else if (!widget.controller.cashierMode) {
      final code = sku.trim();
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetCtx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.skuNotFoundMsg(code),
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(sheetCtx).pop('attach'),
                  icon: const Icon(Icons.link),
                  label: Text(strings.attachBarcodeToExistingBtn),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(sheetCtx).pop('create'),
                  icon: const Icon(Icons.add),
                  label: Text(strings.createNewProductBtn),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted) return;
      if (action == 'attach') {
        await showAttachBarcodeSheet(
          context,
          controller: widget.controller,
          barcode: code,
        );
      } else if (action == 'create') {
        await _openProductForm(initialSku: code);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.skuNotFoundMsg(sku.trim()))),
      );
    }
  }

  Future<void> _openStockIn() async {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.stockIn);
    final beforeQueueCount = widget.controller.priceTagQueueProducts.length;
    final units = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StockInSheet(controller: widget.controller),
    );
    if (units != null && units > 0 && mounted) {
      final addedToPrint = widget.controller.priceTagQueueProducts.length -
          beforeQueueCount;
      final latestRecord = widget.controller.stockIns.isNotEmpty
          ? widget.controller.stockIns.first
          : null;
      final invoiceProducts = [
        if (latestRecord != null)
          for (final item in latestRecord.items)
            if (widget.controller.findProductById(item.productId) != null)
              widget.controller.findProductById(item.productId)!,
      ];
      final strings = widget.controller.strings;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            addedToPrint > 0
                ? '${strings.stockInSavedMsg(units)} • ${strings.addedToPriceTagQueueNotice(addedToPrint)}'
                : strings.stockInSavedMsg(units),
          ),
          action: invoiceProducts.isNotEmpty
              ? SnackBarAction(
                  label: strings.printInvoicePriceTagsBtn,
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => BatchPriceTagsSheet(
                        controller: widget.controller,
                        products: invoiceProducts,
                      ),
                    );
                  },
                )
              : (addedToPrint > 0
                  ? SnackBarAction(
                      label: strings.priceTagQueueTitle,
                      onPressed: _openPriceTagQueue,
                    )
                  : null),
        ),
      );
    }
  }

  Future<void> _openStocktake() async {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.stocktake);
    final changed = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StocktakeSheet(
        controller: widget.controller,
        initialCategory: _selectedCategory,
      ),
    );
    if (changed != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.controller.strings.stocktakeAppliedMsg(changed)),
        ),
      );
    }
  }

  Future<void> _confirmMoveToTrash(Product product) async {
    final strings = widget.controller.strings;
    final messenger = ScaffoldMessenger.of(context);
    await widget.controller.moveProductToTrash(product.id);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(strings.movedToTrashMsg),
        action: SnackBarAction(
          label: strings.undoAction,
          onPressed: () =>
              widget.controller.restoreTrashedProducts([product.id]),
        ),
      ),
    );
  }

  void _enterSelectionMode([String? initialId]) {
    setState(() {
      _selectionMode = true;
      if (initialId != null) {
        _selectedIds.add(initialId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  Future<String?> _promptArchiveOrTrashDestination(
    String title,
    int count,
  ) {
    final strings = widget.controller.strings;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(strings.chooseDestinationBody(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).pop('archive'),
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: Text(strings.archiveAction),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop('trash'),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(strings.moveToTrashAction),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmMoveSelectedToArchive() async {
    if (_selectedIds.isEmpty) return;
    final strings = widget.controller.strings;
    final messenger = ScaffoldMessenger.of(context);
    final ids = List<String>.from(_selectedIds);
    final moved = await widget.controller.archiveProducts(ids);
    _exitSelectionMode();
    if (mounted && moved > 0) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(strings.movedCountToArchiveMsg(moved)),
          action: SnackBarAction(
            label: strings.undoAction,
            onPressed: () => widget.controller.unarchiveProducts(ids),
          ),
        ),
      );
    }
  }

  Future<void> _confirmMoveSelectedToTrash() async {
    if (_selectedIds.isEmpty) return;
    final strings = widget.controller.strings;
    final messenger = ScaffoldMessenger.of(context);
    final ids = List<String>.from(_selectedIds);
    final moved = await widget.controller.moveProductsToTrash(ids);
    _exitSelectionMode();
    if (mounted && moved > 0) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(strings.movedCountToTrashMsg(moved)),
          action: SnackBarAction(
            label: strings.undoAction,
            onPressed: () => widget.controller.restoreTrashedProducts(ids),
          ),
        ),
      );
    }
  }



  Future<void> _confirmDeleteSpecificGroup(String targetCategory) async {
    final strings = widget.controller.strings;
    final count = widget.controller.products
        .where((p) => p.category == targetCategory)
        .length;
    if (count == 0) {
      await widget.controller.deleteEmptyCategory(targetCategory);
      if (_selectedCategory == targetCategory) {
        _setSelectedCategory(null);
      }
      return;
    }

    final destination = await _promptArchiveOrTrashDestination(
      targetCategory,
      count,
    );
    if (destination == null) return;

    if (destination == 'archive') {
      final moved = await widget.controller.archiveCategory(targetCategory);
      if (_selectedCategory == targetCategory) {
        _setSelectedCategory(null);
      }
      if (mounted && moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.movedCountToArchiveMsg(moved))),
        );
      }
    } else {
      final moved = await widget.controller.moveCategoryToTrash(targetCategory);
      if (_selectedCategory == targetCategory) {
        _setSelectedCategory(null);
      }
      if (mounted && moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.movedCountToTrashMsg(moved))),
        );
      }
    }
  }



  Future<String?> _promptTargetGroup({String? excludeCategory}) {
    final strings = widget.controller.strings;
    final categories = widget.controller.categories
        .where((c) => c != excludeCategory)
        .toList();
    return showDialog<String>(  
      context: context,
      builder: (context) => _TargetGroupDialog(
        title: strings.chooseTargetGroupTitle,
        newGroupHint: strings.newGroupHint,
        exampleHint: strings.newGroupExampleHint,
        cancelLabel: strings.cancel,
        confirmLabel: strings.createAndMoveAction,
        categories: categories,
      ),
    );
  }

  Future<void> _moveSingleProductToGroup(Product product) async {
    final strings = widget.controller.strings;
    final target = await _promptTargetGroup(excludeCategory: product.category);
    if (target == null || target.trim().isEmpty) return;
    final moved = await widget.controller.moveProductsToCategory(
      [product.id],
      target,
    );
    if (mounted && moved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.movedCountToGroupMsg(moved, target.trim()))),
      );
    }
  }

  Future<void> _moveSelectedToGroup() async {
    if (_selectedIds.isEmpty) return;
    final strings = widget.controller.strings;
    final target = await _promptTargetGroup(excludeCategory: _selectedCategory);
    if (target == null || target.trim().isEmpty) return;
    final moved = await widget.controller.moveProductsToCategory(
      _selectedIds,
      target,
    );
    _exitSelectionMode();
    if (mounted && moved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.movedCountToGroupMsg(moved, target.trim()))),
      );
    }
  }

  Future<void> _promptMoveGroupToGroup() async {
    final strings = widget.controller.strings;
    final categories = widget.controller.categories;
    if (categories.isEmpty) return;

    String? fromCategory = _selectedCategory;
    fromCategory ??= await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(strings.moveGroupAction),
          children: [
            for (final cat in categories)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(cat),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(cat)),
                    Text(
                      '${widget.controller.products.where((p) => p.category == cat).length}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    if (fromCategory == null || !mounted) return;

    final toCategory = await _promptTargetGroup(excludeCategory: fromCategory);
    if (toCategory == null || toCategory.trim().isEmpty) return;

    final moved = await widget.controller.moveCategoryToCategory(
      fromCategory,
      toCategory,
    );
    if (_selectedCategory == fromCategory) {
      _setSelectedCategory(toCategory.trim());
    }
    if (mounted && moved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.movedCountToGroupMsg(moved, toCategory.trim())),
        ),
      );
    }
  }

  Future<void> _promptCreateGroup() async {
    final strings = widget.controller.strings;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NewGroupDialog(
        title: strings.createGroupTitle,
        label: strings.groupNameLabel,
        hint: strings.newGroupExampleHint,
        cancelLabel: strings.cancel,
        confirmLabel: strings.saveChanges,
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final created = await widget.controller.createCategory(name);
    if (created != null && mounted) {
      _setSelectedCategory(created);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.groupCreatedMsg(created))),
      );
    }
  }

  void _showProductsBreakdown() {
    final strings = widget.controller.strings;
    final products = widget.controller.products;
    final counts = <String, int>{};
    final units = <String, double>{};
    for (final p in products) {
      final cat = p.category.trim().isEmpty ? 'General' : p.category.trim();
      counts[cat] = (counts[cat] ?? 0) + 1;
      units[cat] = (units[cat] ?? 0) + p.stock;
    }
    final sortedCats = counts.keys.toList()
      ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${strings.productsLabel}: ${products.length} (${strings.unitsCount(widget.controller.totalStockUnits)})',
              style: Theme.of(sheetCtx).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sortedCats.length + 1,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  if (index == 0) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.allCategory),
                      trailing: Text(
                        '${products.length} • ${strings.unitsCount(widget.controller.totalStockUnits)}',
                      ),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _setSelectedCategory(null);
                      },
                    );
                  }
                  final cat = sortedCats[index - 1];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(cat),
                    trailing: Text(
                      '${counts[cat] ?? 0} • ${strings.unitsCount(units[cat] ?? 0)}',
                    ),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _setSelectedCategory(cat);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStockValueBreakdown() {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.stockValue);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetCtx) => _StockValueBreakdownSheet(
        controller: widget.controller,
        onSelectCategory: (cat) {
          Navigator.of(sheetCtx).pop();
          _setSelectedCategory(cat);
        },
      ),
    );
  }

  void _showTodayProfitBreakdown() {
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final todaySales = widget.controller.todaySales;

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.todayProfitLabel,
              style: Theme.of(sheetCtx).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${strings.ordersLabel}: ${todaySales.length}  •  '
              '${strings.revenueLabel}: ${formatMoney(widget.controller.todayRevenue, currency)}  •  '
              '${strings.profitLabel}: ${formatMoney(widget.controller.todayProfit, currency)}',
              style: Theme.of(sheetCtx).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (todaySales.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  strings.noSalesForFilter(strings.filterToday),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: todaySales.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final sale = todaySales[index];
                    final title = sale.customerName.trim().isNotEmpty
                        ? sale.customerName.trim()
                        : strings.paymentMethodLabel(sale.paymentMethod.name);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(title),
                      subtitle: Text(
                        '${formatDateTime(sale.createdAt)} • ${strings.unitsShort(sale.totalUnits)}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatMoney(sale.total, currency),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '+${formatMoney(sale.profit, currency)}',
                            style: Theme.of(sheetCtx).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }


  void _openChangeHistory() {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.changeHistory);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProductChangeHistorySheet(
        controller: widget.controller,
        onOpenProduct: (product) => _openQuickEdit(product),
      ),
    );
  }



  void _openCatalogHealth() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CatalogHealthSheet(
        controller: widget.controller,
        onEditProduct: (product) => _openProductForm(existing: product),
      ),
    );
  }

  void _openSuppliersDirectory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SuppliersSheet(controller: widget.controller),
    );
  }

  void _openPriceList() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PriceListSheet(
        controller: widget.controller,
        initialCategory: _selectedCategory,
      ),
    );
  }

  void _openFrozenCash() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FrozenCashSheet(
        controller: widget.controller,
        onEditPrice: (product) => _openQuickEdit(product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.openStockInRequested) {
          widget.controller.clearOpenStockInRequest();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openStockIn();
          });
        }
        final strings = widget.controller.strings;
        final soldUnitsByProduct = widget.controller.soldUnitsByProduct;
        final daysLeftByProduct =
            widget.controller.estimatedDaysOfStockByProduct();
        final products = _filteredProducts(soldUnitsByProduct);
        final showControls =
            _controlsVisible || _selectionMode || products.isEmpty;
        final categories = widget.controller.categories;
        final categoryCounts = <String, int>{};
        for (final p in widget.controller.products) {
          final cat = p.category.trim();
          if (cat.isNotEmpty) {
            categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
          }
        }
        final groupProducts = (_selectedCategory == null
                ? widget.controller.products
                : widget.controller.products
                    .where((p) => p.category == _selectedCategory))
            .toList();
        var inStockCount = 0;
        var inMinusCount = 0;
        var outOfStockCount = 0;
        var groupLowStockCount = 0;
        var expiringCount = 0;
        for (final p in groupProducts) {
          if (p.stock > 0) {
            inStockCount += 1;
            if (p.isExpiringOrExpired(withinDays: 30)) {
              expiringCount += 1;
            }
          } else {
            outOfStockCount += 1;
            if (p.stock < 0) {
              inMinusCount += 1;
            }
          }
          if (p.isLowStock || p.isOutOfStock) {
            groupLowStockCount += 1;
          }
        }
        final isCashier = widget.controller.cashierMode;
        if (isCashier && _selectionMode) {
          _selectionMode = false;
          _selectedIds.clear();
        }
        if (_selectedCategory != null &&
            !categories.contains(_selectedCategory)) {
          _selectedCategory = null;
        }
        final visibleIds = products.map((p) => p.id).toList();
        final allVisibleSelected = visibleIds.isNotEmpty &&
            visibleIds.every((id) => _selectedIds.contains(id));
        final dailyAdvices = isCashier
            ? const <DailyProductAdvice>[]
            : widget.controller.dailyProductAdvices();
        final baseFeaturedAdvice = isCashier
            ? null
            : widget.controller.featuredDailyAdvice(dailyAdvices);
        DailyProductAdvice? featuredAdvice = baseFeaturedAdvice;
        int? activeAdviceNumber;
        if (featuredAdvice != null && dailyAdvices.isNotEmpty) {
          final baseIndex = dailyAdvices.indexWhere(
            (a) => a.id == baseFeaturedAdvice!.id,
          );
          final start = baseIndex >= 0 ? baseIndex : 0;
          final idx = (start + _adviceCycleOffset) % dailyAdvices.length;
          featuredAdvice = dailyAdvices[idx];
          if (_adviceCycleOffset > 0) {
            activeAdviceNumber = idx + 1;
          }
        }

        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: _selectionMode
              ? AppBar(
                  leading: IconButton(
                    onPressed: _exitSelectionMode,
                    icon: const Icon(Icons.close),
                  ),
                  title: Text(strings.selectedCountLabel(_selectedIds.length)),
                  actions: [
                    TextButton(
                      onPressed: visibleIds.isEmpty
                          ? null
                          : () {
                              setState(() {
                                if (allVisibleSelected) {
                                  _selectedIds.removeAll(visibleIds);
                                } else {
                                  _selectedIds.addAll(visibleIds);
                                }
                              });
                            },
                      child: Text(
                        allVisibleSelected
                            ? strings.clearSelection
                            : strings.selectAllVisible,
                      ),
                    ),
                    IconButton(
                      tooltip: strings.moveToGroupAction,
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : _moveSelectedToGroup,
                      icon: const Icon(Icons.drive_file_move_outlined),
                    ),
                    IconButton(
                      tooltip: strings.archiveAction,
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : _confirmMoveSelectedToArchive,
                      icon: const Icon(Icons.archive_outlined),
                    ),
                    IconButton(
                      tooltip: strings.deleteSelectedAction,
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : _confirmMoveSelectedToTrash,
                      icon: Icon(
                        Icons.delete_outline,
                        color: _selectedIds.isEmpty
                            ? null
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                )
              : AppBar(
                  title: Text(strings.shopInventory),
                  actions: [
                    if (!isCashier &&
                        widget.controller.priceTagQueueProducts.isNotEmpty)
                      IconButton(
                        tooltip: strings.priceTagQueueTitle,
                        onPressed: _openPriceTagQueue,
                        icon: Badge(
                          backgroundColor:
                              Theme.of(context).colorScheme.tertiary,
                          label: Text(
                            '${widget.controller.priceTagQueueProducts.length}',
                          ),
                          child: const Icon(Icons.sell_outlined),
                        ),
                      ),

                    if (!isCashier)
                      PopupMenuButton<String>(
                        icon: Badge(
                          isLabelVisible: widget.controller.hasStockInDraft ||
                              widget.controller.hasStocktakeDraft,
                          child: const Icon(Icons.more_vert),
                        ),
                        onSelected: (value) {
                          if (value == 'stock_in') _openStockIn();
                          if (value == 'stocktake') _openStocktake();
                          if (value == 'purchase_order') _openPurchaseOrder();
                          if (value == 'price_list') _openPriceList();
                          if (value == 'suppliers') _openSuppliersDirectory();
                          if (value == 'daily_advice') _openDailyAdvice();
                          if (value == 'frozen_cash') _openFrozenCash();
                          if (value == 'change_history') _openChangeHistory();
                          if (value == 'toggle_summary') {
                            setState(
                              () => _showSummaryHeader = !_showSummaryHeader,
                            );
                          }
                          if (value == 'select') _enterSelectionMode();
                          if (value == 'catalog_health') {
                            _openCatalogHealth();
                          }
                          if (value == 'new_group') _promptCreateGroup();
                          if (value == 'move_group') _promptMoveGroupToGroup();
                        },
                        itemBuilder: (context) => [
                          if (widget.controller.products.isNotEmpty) ...[
                            PopupMenuItem(
                              value: 'stock_in',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.local_shipping_outlined,
                                ),
                                title: Text(
                                  widget.controller.hasStockInDraft
                                      ? (widget.controller.stockInDraft!
                                                  .totalUnits >
                                              0
                                          ? '${strings.stockInBtn} (${formatQty(widget.controller.stockInDraft!.totalUnits)})'
                                          : '${strings.stockInBtn} •')
                                      : strings.stockInBtn,
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'stocktake',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.fact_check_outlined),
                                title: Text(
                                  widget.controller.hasStocktakeDraft
                                      ? (widget.controller.stocktakeDraft!
                                              .counts.isNotEmpty
                                          ? '${strings.stocktakeBtn} (${widget.controller.stocktakeDraft!.counts.length})'
                                          : '${strings.stocktakeBtn} •')
                                      : strings.stocktakeBtn,
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'purchase_order',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading:
                                    const Icon(Icons.shopping_bag_outlined),
                                title: Builder(
                                  builder: (_) {
                                    final count = widget.controller
                                        .buildPurchaseOrderSuggestions()
                                        .length;
                                    return Text(
                                      count > 0
                                          ? '${strings.purchaseOrderBtn} ($count)'
                                          : strings.purchaseOrderBtn,
                                    );
                                  },
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'price_list',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.list_alt_outlined),
                                title: Text(strings.sendPriceListBtn),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'suppliers',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.storefront_outlined),
                                title: Text(
                                  widget.controller.totalSupplierDebt > 0.009
                                      ? '${strings.suppliersDirectoryBtn} • ${formatMoney(widget.controller.totalSupplierDebt, widget.controller.currency)}'
                                      : strings.suppliersDirectoryBtn,
                                ),
                              ),
                            ),
                            const PopupMenuDivider(),
                          ],
                          if (widget.controller.products.isNotEmpty)
                            PopupMenuItem(
                              value: 'daily_advice',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.tips_and_updates_outlined,
                                ),
                                title: Text(
                                  dailyAdvices.isNotEmpty
                                      ? '${strings.dailyAdviceTitle} (${dailyAdvices.length})'
                                      : strings.dailyAdviceTitle,
                                ),
                              ),
                            ),
                          if (widget.controller.products.isNotEmpty)
                            PopupMenuItem(
                              value: 'frozen_cash',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.savings_outlined,
                                ),
                                title: Text(strings.frozenCashBtn),
                              ),
                            ),
                          PopupMenuItem(
                            value: 'change_history',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.history),
                              title: Text(
                                widget.controller.productChanges.isNotEmpty
                                    ? '${strings.changeHistoryBtn} (${widget.controller.productChanges.length})'
                                    : strings.changeHistoryBtn,
                              ),
                            ),
                          ),
                          if (widget.controller.products.isNotEmpty)
                            PopupMenuItem(
                              value: 'toggle_summary',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  _showSummaryHeader
                                      ? Icons.unfold_less
                                      : Icons.unfold_more,
                                ),
                                title: Text(
                                  _showSummaryHeader
                                      ? strings.hideSummaryHeaderTooltip
                                      : strings.showSummaryHeaderTooltip,
                                ),
                              ),
                            ),
                          const PopupMenuDivider(),
                          if (widget.controller.products.isNotEmpty)
                            PopupMenuItem(
                              value: 'select',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.checklist),
                                title: Text(strings.selectItemsBtn),
                              ),
                            ),

                          if (widget.controller.products.isNotEmpty)
                            PopupMenuItem(
                              value: 'catalog_health',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.health_and_safety_outlined,
                                ),
                                title: Text(strings.catalogHealthBtn),
                              ),
                            ),
                          PopupMenuItem(
                            value: 'new_group',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.create_new_folder_outlined,
                              ),
                              title: Text(strings.newGroupBtn),
                            ),
                          ),
                          if (widget.controller.products.isNotEmpty) ...[
                            PopupMenuItem(
                              value: 'move_group',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.drive_file_move_outlined,
                                ),
                                title: Text(strings.moveGroupAction),
                              ),
                            ),
                          ],
                        ],
                      ),
                    SettingsButton(controller: widget.controller),
                  ],
                ),
          floatingActionButton: (isCashier || _selectionMode)
              ? null
              : AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  offset: showControls ? Offset.zero : const Offset(0, 1.6),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: showControls ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !showControls,
                      child: FloatingActionButton.extended(
                        onPressed: () => _openProductForm(),
                        icon: const Icon(Icons.add),
                        label: Text(strings.addGood),
                      ),
                    ),
                  ),
                ),
          body: Column(
            children: [
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: (showControls && _showSummaryHeader)
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isCashier)
                              _InventorySummaryStrip(
                                controller: widget.controller,
                                onTapProducts: _showProductsBreakdown,
                                onTapStockValue: _showStockValueBreakdown,
                                onTapTodayProfit: _showTodayProfitBreakdown,
                              ),
                            if (!isCashier &&
                                featuredAdvice != null &&
                                _dismissedAdviceDayKey != _todayKey &&
                                _searchQuery.isEmpty &&
                                !_selectionMode)
                              DailyAdviceBanner(
                                controller: widget.controller,
                                featured: featuredAdvice,
                                totalCount: dailyAdvices.length,
                                currentIndex: activeAdviceNumber,
                                onTapOpenAll: _openDailyAdvice,
                                onDoubleTapNext: () {
                                  if (dailyAdvices.length <= 1) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(strings.noOtherAdviceMsg),
                                      ),
                                    );
                                    return;
                                  }
                                  HapticFeedback.lightImpact();
                                  setState(() {
                                    _adviceCycleOffset =
                                        (_adviceCycleOffset + 1) %
                                        dailyAdvices.length;
                                  });
                                },
                                onDismissToday: () => setState(
                                  () => _dismissedAdviceDayKey = _todayKey,
                                ),
                              ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          hintText: strings.searchGoodsHint,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_searchQuery.isNotEmpty)
                                IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                              VoiceSearchButton(
                                strings: strings,
                                language: widget.controller.language,
                                onResult: (text) {
                                  _searchController.text = text;
                                  _searchController.selection =
                                      TextSelection.collapsed(
                                    offset: text.length,
                                  );
                                  setState(() => _searchQuery = text);
                                },
                              ),
                            ],
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    PopupMenuButton<_ProductSort>(
                      tooltip: strings.sortLabel,
                      initialValue: _sortBy,
                      onSelected: _selectSort,
                      itemBuilder: (_) => [
                        for (final option in [
                          _ProductSort.newest,
                          _ProductSort.priceDesc,
                          _ProductSort.priceAsc,
                          _ProductSort.stockDesc,
                          _ProductSort.stockAsc,
                          _ProductSort.mostSold,
                          _ProductSort.nameAsc,
                          if (!isCashier) _ProductSort.marginDesc,
                        ])
                          CheckedPopupMenuItem<_ProductSort>(
                            value: option,
                            checked: _sortBy == option,
                            child: Text(_sortOptionLabel(option, strings)),
                          ),
                      ],
                      child: Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(
                          color: _sortBy != _ProductSort.newest
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Icon(
                          Icons.swap_vert_rounded,
                          color: _sortBy != _ProductSort.newest
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: strings.scanBarcodeTitle,
                      onPressed: _openBarcodeLookup,
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                  ],
                ),
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: showControls
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isCashier &&
                                !_selectionMode &&
                                widget.controller.products.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.tonalIcon(
                                        onPressed: _openStockIn,
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.local_shipping_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          widget.controller.hasStockInDraft
                                              ? (widget.controller.stockInDraft!
                                                          .totalUnits >
                                                      0
                                                  ? '${strings.stockInBtn} (${formatQty(widget.controller.stockInDraft!.totalUnits)})'
                                                  : '${strings.stockInBtn} •')
                                              : strings.stockInBtn,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _openStocktake,
                                        style: OutlinedButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.fact_check_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          widget.controller.hasStocktakeDraft
                                              ? (widget.controller
                                                      .stocktakeDraft!
                                                      .counts
                                                      .isNotEmpty
                                                  ? '${strings.stocktakeBtn} (${widget.controller.stocktakeDraft!.counts.length})'
                                                  : '${strings.stocktakeBtn} •')
                                              : strings.stocktakeBtn,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          '${strings.allCategory} (${widget.controller.products.length})',
                        ),
                        selected: _selectedCategory == null,
                        onSelected: (_) => _setSelectedCategory(null),
                      ),
                    ),
                    for (final category in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onLongPress: (!isCashier && !_selectionMode)
                              ? () => _confirmDeleteSpecificGroup(category)
                              : null,
                          child: ChoiceChip(
                            label: Text(
                              '$category (${categoryCounts[category] ?? 0})',
                            ),
                            selected: _selectedCategory == category,
                            onSelected: (_) => _setSelectedCategory(category),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (_sortBy != _ProductSort.newest)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          avatar: const Icon(Icons.swap_vert_rounded, size: 16),
                          label: Text(_sortOptionLabel(_sortBy, strings)),
                          onDeleted: () => _selectSort(_ProductSort.newest),
                          onPressed: () => _selectSort(_ProductSort.newest),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(strings.inStockFilter(inStockCount)),
                        selected: _stockFilter == _StockFilter.inStock,
                        onSelected: (selected) => setState(
                          () => _stockFilter = selected
                              ? _StockFilter.inStock
                              : _StockFilter.all,
                        ),
                      ),
                    ),
                    if (inMinusCount > 0 ||
                        _stockFilter == _StockFilter.inMinus)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: inMinusCount > 0
                              ? Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.error,
                                )
                              : null,
                          label: Text(
                            strings.inMinusFilter(inMinusCount),
                            style: inMinusCount > 0
                                ? TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  )
                                : null,
                          ),
                          selected: _stockFilter == _StockFilter.inMinus,
                          onSelected: (selected) => setState(
                            () => _stockFilter = selected
                                ? _StockFilter.inMinus
                                : _StockFilter.all,
                          ),
                        ),
                      ),
                    if (outOfStockCount > 0 ||
                        _stockFilter == _StockFilter.outOfStock)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(strings.outOfStockFilter(outOfStockCount)),
                          selected: _stockFilter == _StockFilter.outOfStock,
                          onSelected: (selected) => setState(
                            () => _stockFilter = selected
                                ? _StockFilter.outOfStock
                                : _StockFilter.all,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(strings.lowStockFilter(groupLowStockCount)),
                        selected: _stockFilter == _StockFilter.lowStock,
                        onSelected: (selected) => setState(
                          () => _stockFilter = selected
                              ? _StockFilter.lowStock
                              : _StockFilter.all,
                        ),
                      ),
                    ),
                    if (expiringCount > 0 ||
                        _stockFilter == _StockFilter.expiring)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: Icon(
                            Icons.event_busy_outlined,
                            size: 16,
                            color: Colors.deepOrange.shade700,
                          ),
                          label: Text(strings.expiringFilter(expiringCount)),
                          selected: _stockFilter == _StockFilter.expiring,
                          onSelected: (selected) => setState(
                            () => _stockFilter = selected
                                ? _StockFilter.expiring
                                : _StockFilter.all,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: widget.controller.products.isEmpty
                    ? _EmptyInventoryView(
                        controller: widget.controller,
                        onAddProduct: () => _openProductForm(),
                        onLoadSample: () => widget.controller.loadSampleData(),
                      )
                    : products.isEmpty
                        ? Center(child: Text(strings.noGoodsMatch))
                        : NotificationListener<ScrollNotification>(
                            onNotification: _handleScrollNotification,
                            child: ListView.separated(
                              controller: _listScrollController,
                              padding: EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                (showControls ? 88 : 16) +
                                    MediaQuery.viewInsetsOf(context).bottom,
                              ),
                            itemCount: products.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final product = products[index];
                              return _ProductCard(
                                controller: widget.controller,
                                product: product,
                                soldUnits: _sortBy == _ProductSort.mostSold
                                    ? (soldUnitsByProduct[product.id] ?? 0)
                                    : null,
                                daysLeft: daysLeftByProduct[product.id],
                                isCashier: isCashier,
                                selectionMode: _selectionMode,
                                selected: _selectedIds.contains(product.id),
                                onToggleSelect: () =>
                                    _toggleSelected(product.id),
                                onLongPress: isCashier
                                    ? null
                                    : () => _enterSelectionMode(product.id),
                                onEdit: () =>
                                    _openProductForm(existing: product),
                                onQuickEdit: () => _openQuickEdit(product),
                                onDuplicate: () =>
                                    _openProductForm(template: product),
                                onHistory: () => _showProductHistory(product),
                                onBarcodeLabel: () => _showBarcodeLabel(product),
                                onAddToStockIn: () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  final totalQty = await widget.controller
                                      .addProductToStockInDraft(product);
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          strings.scannedAddedToStockInMsg(
                                            1,
                                            product.name,
                                            totalQty,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                                onAddToCart: () {
                                  if (product.stock <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          strings.outOfStockMsg(product.name),
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  final ok = widget.controller
                                      .addToCart(product.id);
                                  if (!ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          strings.onlyLeftMsg(product.stock),
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  final qty = widget.controller
                                      .cartQuantityFor(product.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        strings.addedToCartMsg(
                                          product.name,
                                          qty,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                onArchive: () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  await widget.controller
                                      .archiveProduct(product.id);
                                  if (mounted) {
                                    messenger.hideCurrentSnackBar();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        duration: const Duration(seconds: 4),
                                        content: Text(strings.movedToArchiveMsg),
                                        action: SnackBarAction(
                                          label: strings.undoAction,
                                          onPressed: () => widget.controller
                                              .unarchiveProduct(product.id),
                                        ),
                                      ),
                                    );
                                  }
                                },
                                onMoveToGroup: () =>
                                    _moveSingleProductToGroup(product),
                                onMoveToTrash: () =>
                                    _confirmMoveToTrash(product),
                              );
                            },
                          ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StockValueBreakdownSheet extends StatefulWidget {
  const _StockValueBreakdownSheet({
    required this.controller,
    required this.onSelectCategory,
  });

  final ShopController controller;
  final ValueChanged<String> onSelectCategory;

  @override
  State<_StockValueBreakdownSheet> createState() =>
      _StockValueBreakdownSheetState();
}

class _StockValueBreakdownSheetState extends State<_StockValueBreakdownSheet> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;
        final products = widget.controller.products;
        final snapshots = widget.controller.inventorySnapshots;
        final totalCost = widget.controller.totalInventoryCostValue;
        final totalSell = widget.controller.totalPotentialRevenue;

        final costByCat = <String, double>{};
        final sellByCat = <String, double>{};
        for (final p in products) {
          final cat = p.category.trim().isEmpty ? 'General' : p.category.trim();
          costByCat[cat] = (costByCat[cat] ?? 0.0) + p.inventoryValue;
          sellByCat[cat] = (sellByCat[cat] ?? 0.0) + p.potentialRevenue;
        }
        final sortedCats = costByCat.keys.toList()
          ..sort((a, b) => (costByCat[b] ?? 0).compareTo(costByCat[a] ?? 0));

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.stockValueLabel,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '${strings.costBasisLabel}: ${formatMoney(totalCost, currency)}  •  '
                '${strings.sellValueLabel}: ${formatMoney(totalSell, currency)}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                '${strings.profitLabel}: ${formatMoney(totalSell - totalCost, currency)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text(
                      strings.byCategoriesTab,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text(
                      snapshots.isEmpty
                          ? strings.byMonthsTab
                          : '${strings.byMonthsTab} (${snapshots.length})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const SizedBox(height: 10),
              if (_tab == 0)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sortedCats.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final cat = sortedCats[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(cat),
                        subtitle: Text(
                          '${strings.sellValueLabel}: ${formatMoney(sellByCat[cat] ?? 0, currency)}',
                        ),
                        trailing: Text(
                          formatMoney(costByCat[cat] ?? 0, currency),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        onTap: () => widget.onSelectCategory(cat),
                      );
                    },
                  ),
                )
              else ...[
                FilledButton.tonalIcon(
                  onPressed: products.isEmpty
                      ? null
                      : () async {
                          await widget.controller
                              .captureMonthlyInventorySnapshot(
                            forceUpdateCurrentMonth: true,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(strings.snapshotUpdatedMsg)),
                          );
                        },
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: Text(strings.updateCurrentMonthSnapshotBtn),
                ),
                const SizedBox(height: 6),
                Text(
                  strings.snapshotAutoNote,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (snapshots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      strings.noMonthlySnapshotsMsg,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: snapshots.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final snap = snapshots[index];
                        final prev = index + 1 < snapshots.length
                            ? snapshots[index + 1]
                            : null;
                        String? deltaText;
                        Color? deltaColor;
                        if (prev != null) {
                          final diff = snap.costValue - prev.costValue;
                          if (diff.abs() > 0.009) {
                            final sign = diff > 0 ? '+' : '−';
                            final pctStr = prev.costValue > 0.009
                                ? ' (${diff > 0 ? '+' : ''}${((diff / prev.costValue) * 100).toStringAsFixed(1)}%)'
                                : '';
                            deltaText =
                                '$sign${formatMoney(diff.abs(), currency)}$pctStr';
                            deltaColor = diff > 0
                                ? Colors.green.shade700
                                : theme.colorScheme.error;
                          }
                        }
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${strings.monthFull(snap.month)} ${snap.year}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${strings.snapshotItemsUnits(snap.productsCount, snap.totalUnits)} • '
                            '${strings.sellValueLabel}: ${formatMoney(snap.sellValue, currency)}\n'
                            '${strings.snapshotCapturedLabel(formatDateTime(snap.capturedAt))}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatMoney(snap.costValue, currency),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (deltaText != null)
                                Text(
                                  deltaText,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: deltaColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InventorySummaryStrip extends StatelessWidget {
  const _InventorySummaryStrip({
    required this.controller,
    this.onTapProducts,
    this.onTapStockValue,
    this.onTapTodayProfit,
  });

  final ShopController controller;
  final VoidCallback? onTapProducts;
  final VoidCallback? onTapStockValue;
  final VoidCallback? onTapTodayProfit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = controller.strings;
    final currency = controller.currency;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _MetricTile(
              label: strings.productsLabel,
              value: '${controller.products.length}',
              subtitle: strings.unitsCount(controller.totalStockUnits),
              color: theme.colorScheme.primaryContainer,
              onTap: onTapProducts,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MetricTile(
              label: strings.stockValueLabel,
              value: formatMoney(controller.totalInventoryCostValue, currency),
              subtitle: strings.costBasisLabel,
              color: theme.colorScheme.secondaryContainer,
              onTap: onTapStockValue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MetricTile(
              label: strings.todayProfitLabel,
              value: formatMoney(controller.todayProfit, currency),
              subtitle: strings.revSubtitle(
                formatMoney(controller.todayRevenue, currency),
              ),
              color: theme.colorScheme.tertiaryContainer,
              onTap: onTapTodayProfit,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.controller,
    required this.product,
    this.soldUnits,
    this.daysLeft,
    required this.isCashier,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelect,
    this.onLongPress,
    required this.onEdit,
    this.onQuickEdit,
    this.onDuplicate,
    this.onHistory,
    this.onBarcodeLabel,
    this.onAddToStockIn,
    this.onAddToCart,
    required this.onMoveToGroup,
    required this.onArchive,
    required this.onMoveToTrash,
  });

  final ShopController controller;
  final Product product;
  final double? soldUnits;
  final int? daysLeft;
  final bool isCashier;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onLongPress;
  final VoidCallback onEdit;
  final VoidCallback? onQuickEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onHistory;
  final VoidCallback? onBarcodeLabel;
  final VoidCallback? onAddToStockIn;
  final VoidCallback? onAddToCart;
  final VoidCallback onMoveToGroup;
  final VoidCallback onArchive;
  final VoidCallback onMoveToTrash;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = controller.strings;
    final currency = controller.currency;
    final Color badgeColor;
    final String stockLabel;

    final oosDays = product.currentOutOfStockDays;
    if (product.stock < 0) {
      badgeColor = theme.colorScheme.errorContainer;
      stockLabel = oosDays > 0
          ? '${strings.outOfStock} (${product.stock}) • ${strings.daysShort(oosDays)}'
          : '${strings.outOfStock} (${product.stock})';
    } else if (product.isOutOfStock) {
      badgeColor = theme.colorScheme.errorContainer;
      stockLabel = oosDays > 0
          ? '${strings.outOfStock} • ${strings.daysShort(oosDays)}'
          : strings.outOfStock;
    } else if (product.isLowStock || (daysLeft != null && daysLeft! <= 4)) {
      badgeColor = Colors.amber.shade100;
      final base = product.isLowStock
          ? strings.lowStockBadge(product.stock)
          : strings.inStockBadge(product.stock);
      stockLabel = daysLeft != null
          ? '$base • ${strings.approxDaysLeftShort(daysLeft!)}'
          : base;
    } else {
      badgeColor = Colors.green.shade100;
      final base = strings.inStockBadge(product.stock);
      stockLabel = daysLeft != null
          ? '$base • ${strings.approxDaysLeftShort(daysLeft!)}'
          : base;
    }

    return Card(
      margin: EdgeInsets.zero,
      color: selectionMode && selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: selectionMode ? onToggleSelect : (isCashier ? null : onQuickEdit),
        onLongPress: selectionMode ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (selectionMode)
                    Checkbox(
                      value: selected,
                      onChanged: (_) => onToggleSelect?.call(),
                    ),
                  if (product.imagePath.trim().isNotEmpty) ...[
                    ProductThumbnail(
                      imagePath: product.imagePath,
                      size: 46,
                      onTap: () => showProductPhotoPreview(
                        context,
                        title: product.name,
                        imagePath: product.imagePath,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onLongPress: () async {
                          await Clipboard.setData(
                            ClipboardData(text: product.name),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(strings.copiedToClipboardMsg),
                              ),
                            );
                          }
                        },
                        child: Text(
                          product.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (product.category.isNotEmpty)
                        Text(
                          product.category,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (product.expiryDate != null)
                        Builder(builder: (context) {
                          final exp = product.expiryDate!;
                          final days = product.daysUntilExpiry()!;
                          final dateStr =
                              '${exp.day.toString().padLeft(2, '0')}.${exp.month.toString().padLeft(2, '0')}.${exp.year}';
                          final isExpired = days < 0;
                          final isUrgent = days <= 30;
                          final label = isExpired
                              ? '${strings.expiredBadge} ($dateStr) • ${strings.sellFirstHint}'
                              : (days == 0
                                  ? '${strings.expiresTodayBadge} ($dateStr) • ${strings.sellFirstHint}'
                                  : (isUrgent
                                      ? '${strings.expiresInDaysBadge(days, dateStr)} • ${strings.sellFirstHint}'
                                      : strings.expiryDateShortBadge(dateStr)));
                          return Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isExpired
                                    ? theme.colorScheme.error
                                    : (isUrgent
                                        ? Colors.deepOrange.shade700
                                        : theme.colorScheme.onSurfaceVariant),
                                fontWeight: isUrgent
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        stockLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (soldUnits != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          strings.soldUnitsBadge(soldUnits!),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${strings.sellShort}: ${formatMoney(product.sellPrice, currency)}'
                    '${product.hasWholesalePrice ? '  •  ${strings.wholesaleShort}: ${formatMoney(product.wholesalePrice, currency)}${product.wholesaleMinQty > 0 ? ' (${strings.wholesaleFromQtyBadge(product.wholesaleMinQty)})' : ''}' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (!isCashier) ...[
                  IconButton(
                    tooltip: strings.edit,
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'to_stock_in') onAddToStockIn?.call();
                      if (value == 'to_cart') onAddToCart?.call();
                      if (value == 'edit') onEdit();
                      if (value == 'duplicate') onDuplicate?.call();
                      if (value == 'history') onHistory?.call();
                      if (value == 'barcode') onBarcodeLabel?.call();
                      if (value == 'move_group') onMoveToGroup();
                      if (value == 'archive') onArchive();
                      if (value == 'trash') onMoveToTrash();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'to_stock_in',
                        child: Text(strings.addToStockInAction),
                      ),
                      PopupMenuItem(
                        value: 'to_cart',
                        child: Text(strings.addToCartAction),
                      ),
                      PopupMenuItem(value: 'edit', child: Text(strings.edit)),
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text(strings.duplicateAction),
                      ),
                      PopupMenuItem(
                        value: 'barcode',
                        child: Text(strings.barcodeLabelAction),
                      ),
                      PopupMenuItem(
                        value: 'history',
                        child: Text(strings.productHistoryAction),
                      ),
                      PopupMenuItem(
                        value: 'move_group',
                        child: Text(strings.moveToGroupAction),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(strings.archiveAction),
                      ),
                      PopupMenuItem(
                        value: 'trash',
                        child: Text(
                          strings.moveToTrashAction,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _EmptyInventoryView extends StatelessWidget {
  const _EmptyInventoryView({
    required this.controller,
    required this.onAddProduct,
    required this.onLoadSample,
  });

  final ShopController controller;
  final VoidCallback onAddProduct;
  final VoidCallback onLoadSample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = controller.strings;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              strings.emptyInventoryTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              strings.emptyInventoryBody,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onAddProduct,
                  icon: const Icon(Icons.add),
                  label: Text(strings.addFirstGood),
                ),
                OutlinedButton(
                  onPressed: onLoadSample,
                  child: Text(strings.loadSampleData),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetGroupDialog extends StatefulWidget {
  const _TargetGroupDialog({
    required this.title,
    required this.newGroupHint,
    required this.exampleHint,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.categories,
  });

  final String title;
  final String newGroupHint;
  final String exampleHint;
  final String cancelLabel;
  final String confirmLabel;
  final List<String> categories;

  @override
  State<_TargetGroupDialog> createState() => _TargetGroupDialogState();
}

class _TargetGroupDialogState extends State<_TargetGroupDialog> {
  late final TextEditingController _groupCtrl;

  @override
  void initState() {
    super.initState();
    _groupCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _groupCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _groupCtrl,
                decoration: InputDecoration(
                  labelText: widget.newGroupHint,
                  hintText: widget.exampleHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.of(context).pop(value.trim());
                  }
                },
              ),
              if (widget.categories.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final cat in widget.categories)
                      ActionChip(
                        label: Text(cat),
                        onPressed: () => Navigator.of(context).pop(cat),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () {
            final val = _groupCtrl.text.trim();
            if (val.isNotEmpty) {
              Navigator.of(context).pop(val);
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _NewGroupDialog extends StatefulWidget {
  const _NewGroupDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final String label;
  final String hint;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<_NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends State<_NewGroupDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(context).pop(value.trim());
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () {
            final val = _ctrl.text.trim();
            if (val.isNotEmpty) {
              Navigator.of(context).pop(val);
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _QuickEditResult {
  const _QuickEditResult({
    this.openFullForm = false,
    this.sellPrice = 0,
    this.costPrice = 0,
    this.wholesalePrice = 0,
    this.wholesaleMinQty = 0,
    this.stock = 0,
  });

  final bool openFullForm;
  final double sellPrice;
  final double costPrice;
  final double wholesalePrice;
  final int wholesaleMinQty;
  final double stock;
}

class _QuickEditProductDialog extends StatefulWidget {
  const _QuickEditProductDialog({
    required this.strings,
    required this.currency,
    required this.product,
  });

  final dynamic strings;
  final dynamic currency;
  final Product product;

  @override
  State<_QuickEditProductDialog> createState() => _QuickEditProductDialogState();
}

class _QuickEditProductDialogState extends State<_QuickEditProductDialog> {
  late final TextEditingController _sellCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _wholesaleCtrl;
  late final TextEditingController _wholesaleMinQtyCtrl;
  late final TextEditingController _stockCtrl;

  @override
  void initState() {
    super.initState();
    _sellCtrl = TextEditingController(
      text: widget.product.sellPrice.toStringAsFixed(0),
    );
    _costCtrl = TextEditingController(
      text: widget.product.costPrice.toStringAsFixed(0),
    );
    _wholesaleCtrl = TextEditingController(
      text: widget.product.wholesalePrice > 0
          ? widget.product.wholesalePrice.toStringAsFixed(0)
          : '',
    );
    _wholesaleMinQtyCtrl = TextEditingController(
      text: widget.product.wholesaleMinQty > 0
          ? '${widget.product.wholesaleMinQty}'
          : '',
    );
    _stockCtrl = TextEditingController(text: '${widget.product.stock}');
  }

  @override
  void dispose() {
    _sellCtrl.dispose();
    _costCtrl.dispose();
    _wholesaleCtrl.dispose();
    _wholesaleMinQtyCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCalculator(
    TextEditingController target, {
    bool integerMode = false,
  }) async {
    final initial = double.tryParse(target.text.trim().replaceAll(',', '.'));
    final result = await showCurrencyCalculatorDialog(
      context,
      strings: widget.strings,
      targetCurrency: widget.currency,
      productName: widget.product.name,
      initialValue: initial,
      integerMode: integerMode,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (integerMode) {
        target.text = '${result.round()}';
      } else {
        target.text = result == result.roundToDouble()
            ? result.toStringAsFixed(0)
            : result.toStringAsFixed(2);
      }
    });
  }

  void _save() {
    final sell = double.tryParse(_sellCtrl.text.trim().replaceAll(',', '.'));
    final cost = double.tryParse(_costCtrl.text.trim().replaceAll(',', '.'));
    final wholesaleRaw = _wholesaleCtrl.text.trim().replaceAll(',', '.');
    final wholesale =
        wholesaleRaw.isEmpty ? 0.0 : double.tryParse(wholesaleRaw);
    final minQtyRaw = _wholesaleMinQtyCtrl.text.trim();
    final wholesaleMinQty =
        minQtyRaw.isEmpty ? 0 : int.tryParse(minQtyRaw);
    final stock = parseQty(_stockCtrl.text);
    if (sell == null ||
        sell < 0 ||
        cost == null ||
        cost < 0 ||
        wholesale == null ||
        wholesale < 0 ||
        wholesaleMinQty == null ||
        wholesaleMinQty < 0 ||
        stock == null ||
        stock < 0) {
      return;
    }
    Navigator.of(context).pop(
      _QuickEditResult(
        sellPrice: sell,
        costPrice: cost,
        wholesalePrice: wholesale,
        wholesaleMinQty: wholesaleMinQty,
        stock: stock,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 16, 12),
      title: Text(strings.quickEditTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sellCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: strings.sellPriceRequired,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: strings.currencyCalculatorTitle,
                        onPressed: () => _openCalculator(_sellCtrl),
                        icon: const Icon(Icons.calculate_outlined, size: 18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: strings.costPriceRequired,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: strings.currencyCalculatorTitle,
                        onPressed: () => _openCalculator(_costCtrl),
                        icon: const Icon(Icons.calculate_outlined, size: 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _wholesaleCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: strings.wholesaleShort,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: strings.currencyCalculatorTitle,
                        onPressed: () => _openCalculator(_wholesaleCtrl),
                        icon: const Icon(Icons.calculate_outlined, size: 18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _wholesaleMinQtyCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: strings.wholesaleMinQtyLabel,
                      hintText: '5',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _stockCtrl,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: strings.stockQtyRequired,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: strings.currencyCalculatorTitle,
                  onPressed: () =>
                      _openCalculator(_stockCtrl, integerMode: true),
                  icon: const Icon(Icons.calculate_outlined, size: 18),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          onPressed: () => Navigator.of(context).pop(
            const _QuickEditResult(openFullForm: true),
          ),
          child: Text(strings.allFieldsAction),
        ),
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(strings.saveChanges),
        ),
      ],
    );
  }
}

class _ProductHistorySheet extends StatefulWidget {
  const _ProductHistorySheet({
    required this.controller,
    required this.product,
  });

  final ShopController controller;
  final Product product;

  @override
  State<_ProductHistorySheet> createState() => _ProductHistorySheetState();
}

class _ProductHistorySheetState extends State<_ProductHistorySheet> {
  late List<ProductChangeEntry> _priceHistory;

  @override
  void initState() {
    super.initState();
    _priceHistory = widget.controller.priceChangesForProduct(widget.product.id);
    widget.controller
        .loadPriceChangesForProduct(widget.product.id)
        .then((loaded) {
      if (!mounted) return;
      setState(() => _priceHistory = loaded);
    });
  }

  String? _formatPriceDelta(String oldVal, String newVal) {
    final oldNum = double.tryParse(oldVal.replaceAll(',', '.').trim());
    final newNum = double.tryParse(newVal.replaceAll(',', '.').trim());
    if (oldNum == null || newNum == null) return null;
    final delta = newNum - oldNum;
    if (delta.abs() <= 0.009) return null;
    final sign = delta > 0 ? '+' : '−';
    final absStr = delta.abs() == delta.abs().roundToDouble()
        ? delta.abs().toStringAsFixed(0)
        : delta.abs().toStringAsFixed(2);
    if (oldNum > 0.009) {
      final pct = (delta / oldNum) * 100;
      final pctStr = pct.abs() >= 10
          ? pct.toStringAsFixed(0)
          : pct.toStringAsFixed(1);
      return '$sign$absStr (${delta > 0 ? '+' : ''}$pctStr%)';
    }
    return '$sign$absStr';
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final product = widget.product;
    final theme = Theme.of(context);
    final strings = controller.strings;
    final currency = controller.currency;
    final priceHistory = _priceHistory;

    final incoming = <({
      DateTime date,
      String supplier,
      String rateLabel,
      double qty,
      double cost,
    })>[];
    var totalInUnits = 0.0;
    var totalInSpend = 0.0;
    for (final rec in controller.stockIns) {
      for (final item in rec.items) {
        if (item.productId == product.id && item.quantity > 0) {
          incoming.add((
            date: rec.createdAt,
            supplier: rec.supplierName,
            rateLabel: rec.exchangeRateLabel,
            qty: item.quantity,
            cost: item.unitCost,
          ));
          totalInUnits += item.quantity;
          totalInSpend += item.lineTotal;
        }
      }
    }

    final outgoing = <({
      DateTime date,
      String customer,
      double qty,
      double price,
      double cost,
      double profit,
    })>[];
    var totalOutUnits = 0.0;
    var totalOutRev = 0.0;
    var totalOutProfit = 0.0;
    final isCashier = controller.cashierMode;
    for (final sale in controller.sales) {
      for (final item in sale.items) {
        if (item.productId == product.id && item.quantity > 0) {
          outgoing.add((
            date: sale.createdAt,
            customer: sale.customerName,
            qty: item.quantity,
            price: item.unitPrice,
            cost: item.unitCost,
            profit: item.lineProfit,
          ));
          totalOutUnits += item.quantity;
          totalOutRev += item.lineTotal;
          totalOutProfit += item.lineProfit;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            product.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${strings.stockInBtn}: ${strings.unitsShort(totalInUnits)} (${formatMoney(totalInSpend, currency)})  •  '
            '${strings.salesHistoryHeader}: ${strings.unitsShort(totalOutUnits)} (${formatMoney(totalOutRev, currency)}'
            '${!isCashier && totalOutUnits > 0 ? ', ${strings.profitLabel}: ${totalOutProfit >= 0 ? '+' : ''}${formatMoney(totalOutProfit, currency)}' : ''})',
            style: theme.textTheme.bodySmall,
          ),
          if (product.isOutOfStock || product.totalOutOfStockDays > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                strings.oosSummaryLine(
                  product.currentOutOfStockDays,
                  product.cumulativeOutOfStockDays,
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: product.isOutOfStock
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (priceHistory.isEmpty && incoming.isEmpty && outgoing.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text(strings.noProductHistoryMsg)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (priceHistory.isNotEmpty) ...[
                      Text(
                        '${strings.priceHistory5YearsHeader} (${priceHistory.length})',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final entry in priceHistory)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        formatDateTime(entry.createdAt),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      strings.changeSourceLabel(entry.source),
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                for (final f in entry.fields
                                    .where((x) => x.kind == 'price'))
                                  Builder(
                                    builder: (_) {
                                      final deltaStr = _formatPriceDelta(
                                        f.oldValue,
                                        f.newValue,
                                      );
                                      final isUp = deltaStr != null &&
                                          deltaStr.startsWith('+');
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 2,
                                        ),
                                        child: Wrap(
                                          spacing: 6,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              '${f.label}: ${f.oldValue} → ${f.newValue}',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (deltaStr != null)
                                              Text(
                                                deltaStr,
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: isUp
                                                      ? Colors.green.shade700
                                                      : theme.colorScheme.error,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                    ],
                    if (incoming.isNotEmpty) ...[
                      Text(
                        '${strings.stockInsHeader} (${incoming.length})',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final e in incoming.take(25))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.local_shipping_outlined, size: 20),
                          title: Text(
                            e.supplier.trim().isNotEmpty
                                ? e.supplier.trim()
                                : strings.stockInBtn,
                          ),
                          subtitle: Text(
                            e.rateLabel.isNotEmpty
                                ? '${formatDateTime(e.date)} • ${e.rateLabel}'
                                : formatDateTime(e.date),
                          ),
                          trailing: Text(
                            '+${e.qty} × ${formatMoney(e.cost, currency)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                    if (outgoing.isNotEmpty) ...[
                      Text(
                        '${strings.salesHistoryHeader} (${outgoing.length})',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final s in outgoing.take(25))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.point_of_sale, size: 20),
                          title: Text(
                            s.customer.trim().isNotEmpty
                                ? s.customer.trim()
                                : strings.saleReceipt,
                          ),
                          subtitle: Text(
                            isCashier
                                ? formatDateTime(s.date)
                                : '${formatDateTime(s.date)} • ${strings.costShort}: ${formatMoney(s.cost, currency)} • ${s.profit >= 0 ? '+' : ''}${formatMoney(s.profit, currency)}',
                          ),
                          trailing: Text(
                            '-${s.qty} × ${formatMoney(s.price, currency)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductChangeHistorySheet extends StatefulWidget {
  const _ProductChangeHistorySheet({
    required this.controller,
    required this.onOpenProduct,
  });

  final ShopController controller;
  final ValueChanged<Product> onOpenProduct;

  @override
  State<_ProductChangeHistorySheet> createState() =>
      _ProductChangeHistorySheetState();
}

class _ProductChangeHistorySheetState extends State<_ProductChangeHistorySheet> {
  static const int _pageSize = 60;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String _kindFilter = 'all';
  String _sourceFilter = 'all';
  SalesDateFilter _dateFilter = SalesDateFilter.all;
  int _visibleLimit = _pageSize;
  late List<ProductChangeEntry> _allEntries;

  @override
  void initState() {
    super.initState();
    _allEntries = List<ProductChangeEntry>.from(widget.controller.productChanges);
    widget.controller
        .loadProductChanges(days: ShopController.changeHistoryRetentionDays)
        .then((loaded) {
      if (!mounted) return;
      setState(() => _allEntries = loaded);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesDateFilter(DateTime dt) {
    final now = DateTime.now();
    switch (_dateFilter) {
      case SalesDateFilter.today:
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      case SalesDateFilter.last7Days:
        final cutoff = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
        return !dt.isBefore(cutoff);
      case SalesDateFilter.all:
        return true;
    }
  }

  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String _resolveKey(ProductChangeField f, dynamic strings) {
    if (f.key.isNotEmpty) return f.key;
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

  String _currentFieldValue(
    Product product,
    ProductChangeField f,
    dynamic strings,
  ) {
    final key = _resolveKey(f, strings);
    switch (key) {
      case 'sellPrice':
        return _fmtNum(product.sellPrice);
      case 'costPrice':
        return _fmtNum(product.costPrice);
      case 'wholesalePrice':
        return _fmtNum(product.wholesalePrice);
      case 'wholesaleMinQty':
        return '${product.wholesaleMinQty}';
      case 'stock':
        return '${product.stock}';
      case 'unitWeight':
        return product.unitWeight.trim().isEmpty ? '—' : product.unitWeight.trim();
      case 'name':
        return product.name;
      case 'category':
        return product.category;
      case 'sku':
        return product.sku.trim().isEmpty ? '—' : product.sku.trim();
      case 'lowStockThreshold':
        return '${product.lowStockThreshold}';
      case 'unit':
        return product.unit.trim().isEmpty ? '—' : product.unit.trim();
      case 'packQty':
        return product.packQty.trim().isEmpty ? '—' : product.packQty.trim();
      case 'boxQty':
        return product.boxQty.trim().isEmpty ? '—' : product.boxQty.trim();
      case 'packBarcode':
        return product.packBarcode.trim().isEmpty ? '—' : product.packBarcode.trim();
      case 'boxBarcode':
        return product.boxBarcode.trim().isEmpty ? '—' : product.boxBarcode.trim();
      case 'nomenclature':
        return product.nomenclature.trim().isEmpty ? '—' : product.nomenclature.trim();
      case 'printName':
        return product.printName.trim().isEmpty ? '—' : product.printName.trim();
      default:
        return f.newValue;
    }
  }

  Future<void> _confirmRevert(ProductChangeEntry entry, Product product) async {
    final strings = widget.controller.strings;
    final theme = Theme.of(context);
    final diffs = <({
      ProductChangeField field,
      String currentVal,
      String targetVal,
      ({String text, Color color})? delta,
    })>[];

    for (final f in entry.fields) {
      final currentVal = _currentFieldValue(product, f, strings);
      final targetVal = f.oldValue;
      if (currentVal == targetVal) continue;
      final previewField = ProductChangeField(
        key: f.key,
        kind: f.kind,
        label: f.label,
        oldValue: currentVal,
        newValue: targetVal,
      );
      diffs.add((
        field: f,
        currentVal: currentVal,
        targetVal: targetVal,
        delta: _buildDeltaInfo(previewField, theme),
      ));
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.revertConfirmTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.productName,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                strings.revertPreviewHeader(
                  strings.changeSourceLabel(entry.source),
                  formatDateTime(entry.createdAt),
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              if (diffs.isEmpty)
                Text(
                  strings.revertAlreadyMatchesMsg,
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final d in diffs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${d.field.label}: ${d.currentVal} → ${d.targetVal}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (d.delta != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: d.delta!.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              d.delta!.text,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: d.delta!.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel),
          ),
          if (diffs.isNotEmpty)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(strings.revertAction),
            ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await widget.controller.revertProductChange(
      entry.id,
      fallbackEntry: entry,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? strings.revertedMsg : strings.productUnavailableMsg),
      ),
    );
    if (ok) {
      final reloaded = await widget.controller.loadProductChanges(
        days: ShopController.changeHistoryRetentionDays,
      );
      if (mounted) setState(() => _allEntries = reloaded);
    }
  }

  Future<void> _promptDownloadHistory() async {
    final strings = widget.controller.strings;
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(strings.downloadHistoryTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(7),
            child: Text(strings.filter7Days),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(30),
            child: Text(strings.period30Days),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(365),
            child: Text(strings.period1Year),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(730),
            child: Text(strings.period2Years),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(1827),
            child: Text(strings.period5Years),
          ),
        ],
      ),
    );
    if (days == null || !mounted) return;
    final entries = await widget.controller.loadProductChanges(days: days);
    if (!mounted) return;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.noChangesForPeriodMsg)),
      );
      return;
    }
    final csv = ExportService.buildProductChangesCsvWithBom(entries, strings);
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final bytes = Uint8List.fromList(utf8.encode(csv));
    await Share.shareXFiles([
      XFile.fromData(
        bytes,
        name: 'change_history_${days}d_$stamp.csv',
        mimeType: 'text/csv',
      ),
    ]);
  }

  Future<void> _promptClearHistory() async {
    final strings = widget.controller.strings;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.clearHistoryTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('30d'),
            child: Text(strings.clearOlder30DaysAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('all'),
            child: Text(strings.clearAllAction),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (widget.controller.hasOwnerPin) {
      final pin = await showPinProtectedDeleteDialog(
        context,
        controller: widget.controller,
        title: strings.clearHistoryTitle,
        body: choice == '30d'
            ? strings.clearOlder30DaysAction
            : strings.clearAllAction,
        confirmLabel: strings.confirm,
      );
      if (pin == null || !mounted) return;
    }
    final removed = await widget.controller.clearProductChanges(
      olderThanDays: choice == '30d' ? 30 : null,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.clearedHistoryCountMsg(removed))),
    );
    final reloaded = await widget.controller.loadProductChanges(
      days: ShopController.changeHistoryRetentionDays,
    );
    if (mounted) setState(() => _allEntries = reloaded);
  }

  String _formatDeltaNum(double delta) {
    final absVal = delta.abs();
    final numStr = absVal == absVal.roundToDouble()
        ? absVal.toStringAsFixed(0)
        : absVal.toStringAsFixed(2);
    return delta > 0 ? '+$numStr' : '−$numStr';
  }

  ({String text, Color color})? _buildDeltaInfo(
    ProductChangeField field,
    ThemeData theme,
  ) {
    if (field.kind != 'price' && field.kind != 'stock') return null;
    final oldNum = double.tryParse(field.oldValue.replaceAll(',', '.').trim());
    final newNum = double.tryParse(field.newValue.replaceAll(',', '.').trim());
    if (oldNum == null || newNum == null) return null;
    final delta = newNum - oldNum;
    if (delta.abs() <= 0.009) return null;

    final buffer = StringBuffer(_formatDeltaNum(delta));
    if (field.kind == 'price' && oldNum > 0.009) {
      final pct = (delta / oldNum) * 100;
      final pctStr = pct.abs() >= 10
          ? pct.toStringAsFixed(0)
          : pct.toStringAsFixed(1);
      buffer.write(' (${delta > 0 ? '+' : ''}$pctStr%)');
    }
    final color = delta > 0
        ? Colors.green.shade700
        : theme.colorScheme.error;
    return (text: buffer.toString(), color: color);
  }

  String _bucketTitle(DateTime dt, dynamic strings) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final weekStart = todayStart.subtract(const Duration(days: 6));
    if (!dt.isBefore(todayStart)) return strings.filterToday;
    if (!dt.isBefore(yesterdayStart)) return strings.yesterdayLabel;
    if (!dt.isBefore(weekStart)) return strings.thisWeekLabel;
    return strings.earlierLabel;
  }

  String _formatTimeOnly(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final entries = _allEntries.where((e) {
      if (!_matchesDateFilter(e.createdAt)) return false;
      if (_kindFilter != 'all' && !e.hasKind(_kindFilter)) return false;
      if (_sourceFilter != 'all' && e.source != _sourceFilter) return false;
      if (q.isEmpty) return true;
      return e.productName.toLowerCase().contains(q) ||
          e.fields.any((f) => f.label.toLowerCase().contains(q));
    }).toList();

    final displayedEntries = entries.length > _visibleLimit
        ? entries.sublist(0, _visibleLimit)
        : entries;
    final remainingEntries = entries.length - displayedEntries.length;

    final List<({String? header, ProductChangeEntry? entry})> rows = [];
    String? lastBucket;
    for (final entry in displayedEntries) {
      final bucket = _bucketTitle(entry.createdAt, strings);
      if (bucket != lastBucket) {
        rows.add((header: bucket, entry: null));
        lastBucket = bucket;
      }
      rows.add((header: null, entry: entry));
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.90,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.changeHistoryBtn,
                    style: theme.textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_allEntries.isNotEmpty) ...[
                  IconButton(
                    tooltip: strings.copyTsvShortBtn,
                    onPressed: () {
                      final tsv = SheetExportHelper.buildTsv(
                        SheetExportSection.changes,
                        widget.controller,
                      );
                      Clipboard.setData(ClipboardData(text: tsv));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(strings.copiedForSheetsMsg)),
                      );
                    },
                    icon: const Icon(Icons.content_copy),
                  ),
                  IconButton(
                    tooltip: strings.downloadHistoryBtn,
                    onPressed: _promptDownloadHistory,
                    icon: const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    tooltip: strings.clearHistoryBtn,
                    onPressed: _promptClearHistory,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                ],
                IconButton(
                  tooltip: strings.close,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() {
                _query = v;
                _visibleLimit = _pageSize;
              }),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: strings.searchGoodsHint,
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.clear),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<SalesDateFilter>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: SalesDateFilter.today,
                  label: Text(
                    strings.filterToday,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: SalesDateFilter.last7Days,
                  label: Text(
                    strings.filter7Days,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: SalesDateFilter.all,
                  label: Text(
                    strings.filterAll,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {_dateFilter},
              onSelectionChanged: (val) =>
                  setState(() => _dateFilter = val.first),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final item in [
                    ('all', strings.allCategory),
                    ('price', strings.filterPrice),
                    ('stock', strings.filterStock),
                    ('weight', strings.filterWeight),
                    ('other', strings.filterOther),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(item.$2),
                        selected: _kindFilter == item.$1,
                        onSelected: (_) => setState(() => _kindFilter = item.$1),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final item in [
                    ('all', strings.allSourcesLabel),
                    ('edit', strings.changeSourceLabel('edit')),
                    ('create', strings.changeSourceLabel('create')),
                    ('stock_in', strings.changeSourceLabel('stock_in')),
                    ('stock_in_delete', strings.changeSourceLabel('stock_in_delete')),
                    ('stocktake', strings.changeSourceLabel('stocktake')),
                    ('sync', strings.changeSourceLabel('sync')),
                    ('archive', strings.changeSourceLabel('archive')),
                    ('trash', strings.changeSourceLabel('trash')),
                    ('restore', strings.changeSourceLabel('restore')),
                    ('revert', strings.changeSourceLabel('revert')),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(item.$2),
                        selected: _sourceFilter == item.$1,
                        onSelected: (_) =>
                            setState(() => _sourceFilter = item.$1),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text(strings.noChangesYetMsg))
                  : ListView.builder(
                      itemCount: rows.length + (remainingEntries > 0 ? 1 : 0),
                      itemBuilder: (_, index) {
                        if (index >= rows.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 12),
                            child: OutlinedButton.icon(
                              onPressed: () => setState(
                                () => _visibleLimit += _pageSize,
                              ),
                              icon: const Icon(Icons.expand_more),
                              label: Text(
                                strings.showMoreCountBtn(remainingEntries),
                              ),
                            ),
                          );
                        }
                        final row = rows[index];
                        if (row.header != null) {
                          return Padding(
                            padding: EdgeInsets.only(
                              top: index == 0 ? 4 : 12,
                              bottom: 6,
                              left: 2,
                            ),
                            child: Text(
                              row.header!,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          );
                        }
                        final entry = row.entry!;
                        final product = widget.controller
                            .findProductById(entry.productId);
                        final isActive =
                            product != null && product.isActive;
                        final bucket = _bucketTitle(entry.createdAt, strings);
                        final isRecentDay = bucket == strings.filterToday ||
                            bucket == strings.yesterdayLabel;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            margin: EdgeInsets.zero,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                if (isActive) {
                                  Navigator.of(context).pop();
                                  widget.onOpenProduct(product);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text(strings.productUnavailableMsg),
                                    ),
                                  );
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            entry.productName,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            strings.changeSourceLabel(
                                              entry.source,
                                            ),
                                            style: theme.textTheme.labelSmall,
                                          ),
                                        ),
                                        if (isActive) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.chevron_right,
                                            size: 18,
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isRecentDay
                                          ? _formatTimeOnly(entry.createdAt)
                                          : formatDateTime(entry.createdAt),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    for (final f in entry.fields)
                                      Builder(
                                        builder: (_) {
                                          final deltaInfo =
                                              _buildDeltaInfo(f, theme);
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 3,
                                            ),
                                            child: Wrap(
                                              spacing: 6,
                                              runSpacing: 2,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  '${f.label}: ${f.oldValue} → ${f.newValue}',
                                                  style: theme
                                                      .textTheme.bodySmall,
                                                ),
                                                if (deltaInfo != null)
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 1,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: deltaInfo.color
                                                          .withValues(
                                                        alpha: 0.12,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        6,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      deltaInfo.text,
                                                      style: theme
                                                          .textTheme.labelSmall
                                                          ?.copyWith(
                                                        color: deltaInfo.color,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    if (isActive &&
                                        entry.source != 'revert' &&
                                        entry.source != 'create' &&
                                        entry.source != 'archive' &&
                                        entry.source != 'trash' &&
                                        entry.source != 'restore')
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          style: TextButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 0,
                                            ),
                                          ),
                                          onPressed: () =>
                                              _confirmRevert(entry, product),
                                          icon: const Icon(
                                            Icons.undo,
                                            size: 16,
                                          ),
                                          label: Text(strings.revertAction),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


