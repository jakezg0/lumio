import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/product.dart';
import '../state/shop_controller.dart';
import '../widgets/currency_calculator_dialog.dart';
import '../widgets/formatters.dart';
import '../widgets/product_form_sheet.dart';
import '../widgets/settings_button.dart';
import '../widgets/stock_in_sheet.dart';
import '../widgets/stocktake_sheet.dart';
import 'archive_trash_screen.dart';
import 'barcode_scanner_screen.dart';

enum _StockFilter { all, inStock, lowStock, outOfStock }

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.controller});

  final ShopController controller;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;
  _StockFilter _stockFilter = _StockFilter.all;
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _filteredProducts() {
    final query = _searchQuery.trim().toLowerCase();
    return widget.controller.products.where((product) {
      if (_selectedCategory != null && product.category != _selectedCategory) {
        return false;
      }
      switch (_stockFilter) {
        case _StockFilter.all:
          break;
        case _StockFilter.inStock:
          if (product.stock <= 0) return false;
        case _StockFilter.lowStock:
          if (!product.isLowStock && !product.isOutOfStock) return false;
        case _StockFilter.outOfStock:
          if (product.stock > 0) return false;
      }
      if (query.isEmpty) return true;
      return product.name.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query) ||
          product.sku.toLowerCase().contains(query) ||
          product.nomenclature.toLowerCase().contains(query) ||
          product.printName.toLowerCase().contains(query) ||
          product.packBarcode.toLowerCase().contains(query) ||
          product.boxBarcode.toLowerCase().contains(query);
    }).toList();
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

  Future<void> _openBarcodeLookup() async {
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
      await _openProductForm(initialSku: sku.trim());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.skuNotFoundMsg(sku.trim()))),
      );
    }
  }

  Future<void> _openStockIn() async {
    final units = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StockInSheet(controller: widget.controller),
    );
    if (units != null && units > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.strings.stockInSavedMsg(units))),
      );
    }
  }

  Future<void> _openStocktake() async {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteProductTitle),
        content: Text(strings.deleteProductBody(product.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.moveToTrashAction),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.moveProductToTrash(product.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.movedToTrashMsg)),
        );
      }
    }
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
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.chooseDestinationTitle),
        content: Text(strings.deleteBatchConfirmBody(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.archiveAction),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final moved = await widget.controller.archiveProducts(_selectedIds);
      _exitSelectionMode();
      if (mounted && moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.movedCountToArchiveMsg(moved))),
        );
      }
    }
  }

  Future<void> _confirmMoveSelectedToTrash() async {
    if (_selectedIds.isEmpty) return;
    final strings = widget.controller.strings;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteProductTitle),
        content: Text(strings.deleteBatchConfirmBody(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.moveToTrashAction),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final moved = await widget.controller.moveProductsToTrash(_selectedIds);
      _exitSelectionMode();
      if (mounted && moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.movedCountToTrashMsg(moved))),
        );
      }
    }
  }

  Future<void> _promptDeleteGroupToTrash() async {
    final strings = widget.controller.strings;
    final categories = widget.controller.categories;
    if (categories.isEmpty) return;

    String? targetCategory = _selectedCategory;
    if (targetCategory == null) {
      targetCategory = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(strings.chooseGroupToDelete),
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
    }
    if (targetCategory == null || !mounted) return;
    await _confirmDeleteSpecificGroup(targetCategory);
  }

  Future<void> _confirmDeleteSpecificGroup(String targetCategory) async {
    final strings = widget.controller.strings;
    final count = widget.controller.products
        .where((p) => p.category == targetCategory)
        .length;
    if (count == 0) {
      await widget.controller.deleteEmptyCategory(targetCategory);
      if (_selectedCategory == targetCategory) {
        setState(() => _selectedCategory = null);
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
        setState(() => _selectedCategory = null);
      }
      if (mounted && moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.movedCountToArchiveMsg(moved))),
        );
      }
    } else {
      final moved = await widget.controller.moveCategoryToTrash(targetCategory);
      if (_selectedCategory == targetCategory) {
        setState(() => _selectedCategory = null);
      }
      if (mounted && moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.movedCountToTrashMsg(moved))),
        );
      }
    }
  }

  Future<void> _confirmMoveAllToTrash() async {
    final strings = widget.controller.strings;
    final count = widget.controller.products.length;
    if (count == 0) return;

    final destination = await _promptArchiveOrTrashDestination(
      strings.chooseDestinationTitle,
      count,
    );
    if (destination == null) return;

    if (destination == 'archive') {
      final moved = await widget.controller.archiveAllProducts();
      _exitSelectionMode();
      if (mounted && moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.movedCountToArchiveMsg(moved))),
        );
      }
    } else {
      final moved = await widget.controller.moveAllProductsToTrash();
      _exitSelectionMode();
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
    if (fromCategory == null) {
      fromCategory = await showDialog<String>(
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
    }
    if (fromCategory == null || !mounted) return;

    final toCategory = await _promptTargetGroup(excludeCategory: fromCategory);
    if (toCategory == null || toCategory.trim().isEmpty) return;

    final moved = await widget.controller.moveCategoryToCategory(
      fromCategory,
      toCategory,
    );
    if (_selectedCategory == fromCategory) {
      setState(() => _selectedCategory = toCategory.trim());
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
      setState(() => _selectedCategory = created);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.groupCreatedMsg(created))),
      );
    }
  }

  void _showProductsBreakdown() {
    final strings = widget.controller.strings;
    final products = widget.controller.products;
    final counts = <String, int>{};
    final units = <String, int>{};
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
                        setState(() => _selectedCategory = null);
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
                      setState(() => _selectedCategory = cat);
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
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final products = widget.controller.products;
    final costByCat = <String, double>{};
    final sellByCat = <String, double>{};
    for (final p in products) {
      final cat = p.category.trim().isEmpty ? 'General' : p.category.trim();
      costByCat[cat] = (costByCat[cat] ?? 0.0) + p.inventoryValue;
      sellByCat[cat] = (sellByCat[cat] ?? 0.0) + p.potentialRevenue;
    }
    final sortedCats = costByCat.keys.toList()
      ..sort((a, b) => (costByCat[b] ?? 0).compareTo(costByCat[a] ?? 0));
    final totalCost = widget.controller.totalInventoryCostValue;
    final totalSell = widget.controller.totalPotentialRevenue;

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
              strings.stockValueLabel,
              style: Theme.of(sheetCtx).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${strings.costBasisLabel}: ${formatMoney(totalCost, currency)}  •  '
              '${strings.sellValueLabel}: ${formatMoney(totalSell, currency)}',
              style: Theme.of(sheetCtx).textTheme.bodySmall,
            ),
            Text(
              '${strings.profitLabel}: ${formatMoney(totalSell - totalCost, currency)}',
              style: Theme.of(sheetCtx).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
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
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      setState(() => _selectedCategory = cat);
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

  void _openArchiveTrash() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArchiveTrashScreen(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final products = _filteredProducts();
        final categories = widget.controller.categories;
        final categoryCounts = <String, int>{};
        for (final p in widget.controller.products) {
          final cat = p.category.trim();
          if (cat.isNotEmpty) {
            categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
          }
        }
        final groupProducts = _selectedCategory == null
            ? widget.controller.products
            : widget.controller.products
                .where((p) => p.category == _selectedCategory);
        var inStockCount = 0;
        var outOfStockCount = 0;
        var groupLowStockCount = 0;
        for (final p in groupProducts) {
          if (p.stock > 0) {
            inStockCount += 1;
          } else {
            outOfStockCount += 1;
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
        final archivedOrTrashed =
            widget.controller.archiveCount + widget.controller.trashCount;
        final visibleIds = products.map((p) => p.id).toList();
        final allVisibleSelected = visibleIds.isNotEmpty &&
            visibleIds.every((id) => _selectedIds.contains(id));

        return Scaffold(
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
                    if (!isCashier)
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'select') _enterSelectionMode();
                          if (value == 'new_group') _promptCreateGroup();
                          if (value == 'move_group') _promptMoveGroupToGroup();
                          if (value == 'group_archive_trash') {
                            _promptDeleteGroupToTrash();
                          }
                          if (value == 'all_archive_trash') {
                            _confirmMoveAllToTrash();
                          }
                        },
                        itemBuilder: (context) => [
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
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'group_archive_trash',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.folder_delete_outlined,
                                ),
                                title: Text(strings.groupArchiveOrTrashAction),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'all_archive_trash',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.delete_sweep_outlined,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                title: Text(
                                  strings.allArchiveOrTrashAction,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
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
              : FloatingActionButton.extended(
                  onPressed: () => _openProductForm(),
                  icon: const Icon(Icons.add),
                  label: Text(strings.addGood),
                ),
          body: Column(
            children: [
              if (!isCashier)
                _InventorySummaryStrip(
                  controller: widget.controller,
                  onTapProducts: _showProductsBreakdown,
                  onTapStockValue: _showStockValueBreakdown,
                  onTapTodayProfit: _showTodayProfitBreakdown,
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
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  icon: const Icon(Icons.clear),
                                )
                              : null,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: strings.scanBarcodeTitle,
                      onPressed: _openBarcodeLookup,
                      icon: const Icon(Icons.qr_code_scanner),
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
                    if (!isCashier && widget.controller.products.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.local_shipping_outlined, size: 18),
                          label: Text(
                            widget.controller.hasStockInDraft
                                ? (widget.controller.stockInDraft!.totalUnits > 0
                                    ? '${strings.stockInBtn} (${widget.controller.stockInDraft!.totalUnits})'
                                    : '${strings.stockInBtn} •')
                                : strings.stockInBtn,
                          ),
                          onPressed: _openStockIn,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.fact_check_outlined, size: 18),
                          label: Text(
                            widget.controller.hasStocktakeDraft
                                ? (widget.controller.stocktakeDraft!.counts.isNotEmpty
                                    ? '${strings.stocktakeBtn} (${widget.controller.stocktakeDraft!.counts.length})'
                                    : '${strings.stocktakeBtn} •')
                                : strings.stocktakeBtn,
                          ),
                          onPressed: _openStocktake,
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          '${strings.allCategory} (${widget.controller.products.length})',
                        ),
                        selected: _selectedCategory == null,
                        onSelected: (_) =>
                            setState(() => _selectedCategory = null),
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
                            onSelected: (_) =>
                                setState(() => _selectedCategory = category),
                          ),
                        ),
                      ),
                    if (!isCashier && !_selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(
                            Icons.create_new_folder_outlined,
                            size: 18,
                          ),
                          label: Text(strings.newGroupBtn),
                          onPressed: _promptCreateGroup,
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
                  ],
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
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                            itemCount: products.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final product = products[index];
                              return _ProductCard(
                                controller: widget.controller,
                                product: product,
                                isCashier: isCashier,
                                selectionMode: _selectionMode,
                                selected: _selectedIds.contains(product.id),
                                onToggleSelect: () =>
                                    _toggleSelected(product.id),
                                onLongPress: isCashier
                                    ? null
                                    : () => _enterSelectionMode(product.id),
                                onAdjustStock: (delta) =>
                                    widget.controller.adjustStock(
                                  product.id,
                                  delta,
                                ),
                                onEdit: () =>
                                    _openProductForm(existing: product),
                                onQuickEdit: () => _openQuickEdit(product),
                                onDuplicate: () =>
                                    _openProductForm(template: product),
                                onHistory: () => _showProductHistory(product),
                                onAddToStockIn: () async {
                                  final totalQty = await widget.controller
                                      .addProductToStockInDraft(product);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
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
                                  await widget.controller
                                      .archiveProduct(product.id);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(strings.movedToArchiveMsg),
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
    required this.isCashier,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelect,
    this.onLongPress,
    required this.onAdjustStock,
    required this.onEdit,
    this.onQuickEdit,
    this.onDuplicate,
    this.onHistory,
    this.onAddToStockIn,
    this.onAddToCart,
    required this.onMoveToGroup,
    required this.onArchive,
    required this.onMoveToTrash,
  });

  final ShopController controller;
  final Product product;
  final bool isCashier;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onLongPress;
  final ValueChanged<int> onAdjustStock;
  final VoidCallback onEdit;
  final VoidCallback? onQuickEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onHistory;
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

    if (product.isOutOfStock) {
      badgeColor = theme.colorScheme.errorContainer;
      stockLabel = strings.outOfStock;
    } else if (product.isLowStock) {
      badgeColor = Colors.amber.shade100;
      stockLabel = strings.lowStockBadge(product.stock);
    } else {
      badgeColor = Colors.green.shade100;
      stockLabel = strings.inStockBadge(product.stock);
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
                      Text(
                        [
                          product.category,
                          if (product.nomenclature.isNotEmpty)
                            '${strings.nomenclatureLabel}: ${product.nomenclature}',
                          if (product.sku.isNotEmpty) 'SKU: ${product.sku}',
                        ].join(' • '),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (product.packQty.isNotEmpty ||
                          product.boxQty.isNotEmpty ||
                          product.unitWeight.isNotEmpty ||
                          product.unit.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            [
                              if (product.packQty.isNotEmpty)
                                '${strings.packQtyLabel}: ${product.packQty}',
                              if (product.boxQty.isNotEmpty)
                                '${strings.boxQtyLabel}: ${product.boxQty}',
                              if (product.unitWeight.isNotEmpty)
                                '${strings.unitWeightLabel}: ${product.unitWeight}',
                              if (product.unit.isNotEmpty) product.unit,
                            ].join(' • '),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
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
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isCashier
                        ? '${strings.sellShort}: ${formatMoney(product.sellPrice, currency)}'
                        : '${strings.sellShort}: ${formatMoney(product.sellPrice, currency)}  •  '
                            '${strings.costShort}: ${formatMoney(product.costPrice, currency)}  •  '
                            '${strings.marginShort}: ${product.marginPercent.toStringAsFixed(0)}%',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (!isCashier) ...[
                  IconButton(
                    onPressed:
                        product.stock > 0 ? () => onAdjustStock(-1) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: () => onAdjustStock(1),
                    icon: const Icon(Icons.add_circle_outline),
                    visualDensity: VisualDensity.compact,
                  ),
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
      content: TextField(
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
  const _QuickEditResult({this.openFullForm = false, this.sellPrice = 0, this.costPrice = 0, this.stock = 0});

  final bool openFullForm;
  final double sellPrice;
  final double costPrice;
  final int stock;
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
    _stockCtrl = TextEditingController(text: '${widget.product.stock}');
  }

  @override
  void dispose() {
    _sellCtrl.dispose();
    _costCtrl.dispose();
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
    final stock = int.tryParse(_stockCtrl.text.trim());
    if (sell == null || sell < 0 || cost == null || cost < 0 || stock == null || stock < 0) {
      return;
    }
    Navigator.of(context).pop(
      _QuickEditResult(sellPrice: sell, costPrice: cost, stock: stock),
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
                  onPressed: () => _openCalculator(_stockCtrl, integerMode: true),
                  icon: const Icon(Icons.calculate_outlined, size: 18),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: () => Navigator.of(context).pop(
                const _QuickEditResult(openFullForm: true),
              ),
              child: Text(strings.allFieldsAction),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.cancel),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: _save,
              child: Text(strings.saveChanges),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProductHistorySheet extends StatelessWidget {
  const _ProductHistorySheet({
    required this.controller,
    required this.product,
  });

  final ShopController controller;
  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = controller.strings;
    final currency = controller.currency;

    final incoming = <({DateTime date, String supplier, int qty, double cost})>[];
    var totalInUnits = 0;
    var totalInSpend = 0.0;
    for (final rec in controller.stockIns) {
      for (final item in rec.items) {
        if (item.productId == product.id && item.quantity > 0) {
          incoming.add((
            date: rec.createdAt,
            supplier: rec.supplierName,
            qty: item.quantity,
            cost: item.unitCost,
          ));
          totalInUnits += item.quantity;
          totalInSpend += item.lineTotal;
        }
      }
    }

    final outgoing = <({DateTime date, String customer, int qty, double price})>[];
    var totalOutUnits = 0;
    var totalOutRev = 0.0;
    for (final sale in controller.sales) {
      for (final item in sale.items) {
        if (item.productId == product.id && item.quantity > 0) {
          outgoing.add((
            date: sale.createdAt,
            customer: sale.customerName,
            qty: item.quantity,
            price: item.unitPrice,
          ));
          totalOutUnits += item.quantity;
          totalOutRev += item.lineTotal;
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
            '${strings.stockInBtn}: ${strings.unitsShort(totalInUnits)} (${formatMoney(totalInSpend, currency)})  •  ${strings.salesHistoryHeader}: ${strings.unitsShort(totalOutUnits)} (${formatMoney(totalOutRev, currency)})',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (incoming.isEmpty && outgoing.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text(strings.noProductHistoryMsg)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                          subtitle: Text(formatDateTime(e.date)),
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
                          subtitle: Text(formatDateTime(s.date)),
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
