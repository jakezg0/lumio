import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_strings.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../services/export_service.dart';
import '../services/input_normalizer.dart';
import '../state/shop_controller.dart';
import '../widgets/attach_barcode_sheet.dart';
import '../widgets/currency_calculator_dialog.dart';
import '../widgets/formatters.dart';
import '../widgets/hardware_barcode_listener.dart';
import '../widgets/pin_confirm_dialog.dart';
import '../widgets/product_form_sheet.dart';
import '../widgets/product_thumbnail.dart';
import '../widgets/receipt_sheet.dart';
import '../widgets/settings_button.dart';
import '../widgets/shift_closing_sheet.dart';
import '../widgets/voice_search_button.dart';
import 'barcode_scanner_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key, required this.controller});

  final ShopController controller;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String? _selectedCategory;
  bool _inStockOnly = false;
  final List<String> _recentQueries = [];

  @override
  void initState() {
    super.initState();
    final savedCat = widget.controller.posSelectedCategory;
    _selectedCategory = savedCat.isEmpty ? null : savedCat;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _setSelectedCategory(String? category) {
    setState(() => _selectedCategory = category);
    widget.controller.setPosSelectedCategory(category);
  }

  String _normalizeForSearch(String input) {
    return input
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll('×', 'x')
        .replaceAll('х', 'x')
        .replaceAll('*', 'x')
        .replaceAll(',', '.');
  }


  List<Product> _availableProducts() {
    final activeCategory = (_selectedCategory != null &&
            widget.controller.categories.contains(_selectedCategory))
        ? _selectedCategory
        : null;
    final normalizedQuery = _normalizeForSearch(_searchQuery.trim());
    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final matches = widget.controller.products.where((product) {
      if (_inStockOnly && product.stock <= 0) {
        return false;
      }
      if (activeCategory != null && product.category != activeCategory) {
        return false;
      }
      if (tokens.isEmpty) return true;
      return InputNormalizer.matchesProductSearch(product, _searchQuery);
    }).toList();

    final soldUnits = <String, double>{};
    for (final sale in widget.controller.sales) {
      for (final item in sale.items) {
        soldUnits[item.productId] =
            (soldUnits[item.productId] ?? 0) + item.quantity;
      }
    }

    matches.sort((a, b) {
      final aInStock = a.stock > 0 ? 1 : 0;
      final bInStock = b.stock > 0 ? 1 : 0;
      if (aInStock != bInStock) return bInStock.compareTo(aInStock);

      if (tokens.isNotEmpty) {
        final aName = _normalizeForSearch(a.name);
        final bName = _normalizeForSearch(b.name);
        final aStartsFull = aName.startsWith(normalizedQuery) ? 1 : 0;
        final bStartsFull = bName.startsWith(normalizedQuery) ? 1 : 0;
        if (aStartsFull != bStartsFull) {
          return bStartsFull.compareTo(aStartsFull);
        }
        final first = tokens.first;
        final aStartsFirst = aName.startsWith(first) ? 1 : 0;
        final bStartsFirst = bName.startsWith(first) ? 1 : 0;
        if (aStartsFirst != bStartsFirst) {
          return bStartsFirst.compareTo(aStartsFirst);
        }
      }

      final soldCmp =
          (soldUnits[b.id] ?? 0).compareTo(soldUnits[a.id] ?? 0);
      if (soldCmp != 0) return soldCmp;
      return 0;
    });

    return matches;
  }

  void _recordRecentQuery(String raw) {
    final clean = raw.trim();
    if (clean.length < 2) return;
    final lower = clean.toLowerCase();
    setState(() {
      _recentQueries.removeWhere((q) => q.toLowerCase() == lower);
      _recentQueries.insert(0, clean);
      if (_recentQueries.length > 5) {
        _recentQueries.removeRange(5, _recentQueries.length);
      }
    });
  }

  List<Product> _quickTopProducts() {
    final soldCounts = <String, double>{};
    for (final sale in widget.controller.sales) {
      for (final item in sale.items) {
        soldCounts[item.productId] =
            (soldCounts[item.productId] ?? 0) + item.quantity;
      }
    }
    final candidates = widget.controller.products.where((p) {
      return widget.controller.canSellNegativeStock || p.stock > 0;
    }).toList();
    candidates.sort((a, b) {
      final aSold = soldCounts[a.id] ?? 0;
      final bSold = soldCounts[b.id] ?? 0;
      final aNoCode = a.sku.trim().isEmpty &&
              a.packBarcode.trim().isEmpty &&
              a.boxBarcode.trim().isEmpty
          ? 1
          : 0;
      final bNoCode = b.sku.trim().isEmpty &&
              b.packBarcode.trim().isEmpty &&
              b.boxBarcode.trim().isEmpty
          ? 1
          : 0;
      final aScore = aSold + (aNoCode * 2.0);
      final bScore = bSold + (bNoCode * 2.0);
      if ((bScore - aScore).abs() > 0.001) {
        return bScore.compareTo(aScore);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return candidates.take(8).toList();
  }

  void _addProductToCart(Product product) {
    final strings = widget.controller.strings;
    final added = widget.controller.addToCart(product.id);
    if (added) {
      if (_searchQuery.trim().length >= 2) {
        _recordRecentQuery(_searchQuery);
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            product.stock <= 0
                ? strings.outOfStockMsg(product.name)
                : strings.onlyLeftMsg(product.stock),
          ),
        ),
      );
    }
  }

  int _scanIncrementFor(
    String rawCode,
    String packQty,
    String boxQty,
    String packBarcode,
    String boxBarcode,
  ) {
    final code = rawCode.trim().toLowerCase();
    if (code.isNotEmpty && code == boxBarcode.trim().toLowerCase()) {
      final parsed = int.tryParse(boxQty.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    if (code.isNotEmpty && code == packBarcode.trim().toLowerCase()) {
      final parsed = int.tryParse(packQty.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    return 1;
  }

  ScanBatchFeedback _handleContinuousScan(String code) {
    final strings = widget.controller.strings;
    final product = widget.controller.findProductBySku(code);
    if (product == null) {
      return ScanBatchFeedback(
        found: false,
        message: strings.skuNotFoundMsg(code.trim()),
        notFoundCode: code.trim(),
      );
    }
    final allowNegative = widget.controller.canSellNegativeStock;
    if (!allowNegative && product.stock <= 0) {
      return ScanBatchFeedback(
        found: false,
        message: strings.outOfStockMsg(product.name),
      );
    }
    final delta = _scanIncrementFor(
      code,
      product.packQty,
      product.boxQty,
      product.packBarcode,
      product.boxBarcode,
    );
    final existing = widget.controller.cartQuantityFor(product.id);
    if (!allowNegative && existing + delta > product.stock) {
      return ScanBatchFeedback(
        found: false,
        message: strings.onlyLeftMsg(product.stock),
      );
    }
    widget.controller.addToCart(product.id, quantity: delta.toDouble());
    return ScanBatchFeedback(
      found: true,
      message: strings.scannedAddedToCartMsg(
        delta,
        product.name,
        existing + delta,
      ),
    );
  }

  void _handleSearchSubmitted(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return;
    final strings = widget.controller.strings;
    Product? product = widget.controller.findProductBySku(code);
    if (product == null) {
      final normalizedCode = _normalizeForSearch(code);
      for (final p in widget.controller.products) {
        if (_normalizeForSearch(p.name) == normalizedCode) {
          product = p;
          break;
        }
      }
    }
    if (product == null) {
      _recordRecentQuery(code);
      return;
    }

    final allowNegative = widget.controller.canSellNegativeStock;
    if (!allowNegative && product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.outOfStockMsg(product.name))),
      );
      _searchFocusNode.requestFocus();
      return;
    }
    final delta = _scanIncrementFor(
      code,
      product.packQty,
      product.boxQty,
      product.packBarcode,
      product.boxBarcode,
    );
    final existing = widget.controller.cartQuantityFor(product.id);
    if (!allowNegative && existing + delta > product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.onlyLeftMsg(product.stock))),
      );
      _searchFocusNode.requestFocus();
      return;
    }
    widget.controller.addToCart(product.id, quantity: delta.toDouble());
    setState(() {
      _searchController.clear();
      _searchQuery = '';
    });
    _searchFocusNode.requestFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.scannedAddedToCartMsg(delta, product.name, existing + delta),
        ),
      ),
    );
  }

  Widget _buildHighlightedName(BuildContext context, String name) {
    const baseStyle = TextStyle(fontWeight: FontWeight.w600);
    final tokens = _normalizeForSearch(_searchQuery.trim())
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      return Text(name, style: baseStyle);
    }
    final normName = _normalizeForSearch(name);
    final highlighted = List<bool>.filled(name.length, false);
    for (final token in tokens) {
      var start = 0;
      while (true) {
        final idx = normName.indexOf(token, start);
        if (idx == -1) break;
        final end = (idx + token.length).clamp(0, name.length);
        for (var i = idx; i < end; i++) {
          highlighted[i] = true;
        }
        start = idx + token.length;
      }
    }
    if (!highlighted.any((h) => h)) {
      return Text(name, style: baseStyle);
    }
    final theme = Theme.of(context);
    final highlightStyle = baseStyle.copyWith(
      backgroundColor: theme.colorScheme.primaryContainer,
      color: theme.colorScheme.onPrimaryContainer,
      fontWeight: FontWeight.w700,
    );
    final spans = <TextSpan>[];
    var runStart = 0;
    var current = highlighted[0];
    for (var i = 1; i < name.length; i++) {
      if (highlighted[i] != current) {
        spans.add(
          TextSpan(
            text: name.substring(runStart, i),
            style: current ? highlightStyle : baseStyle,
          ),
        );
        runStart = i;
        current = highlighted[i];
      }
    }
    spans.add(
      TextSpan(
        text: name.substring(runStart),
        style: current ? highlightStyle : baseStyle,
      ),
    );
    return Text.rich(TextSpan(children: spans));
  }

  Future<void> _scanAndAddBySku() async {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.barcodeScan);
    final strings = widget.controller.strings;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (scanCtx) => BarcodeScannerScreen(
          strings: strings,
          onContinuousScan: _handleContinuousScan,
          batchCounterLabel: () =>
              strings.inReceiptCountLabel(widget.controller.cartItemCount),
          onAttachBarcode: widget.controller.cashierMode
              ? null
              : (code) async {
                  final linked = await showAttachBarcodeSheet(
                    scanCtx,
                    controller: widget.controller,
                    barcode: code,
                  );
                  return linked != null;
                },
        ),
      ),
    );
  }

  Future<void> _promptCartQuantity(Product product) async {
    final strings = widget.controller.strings;
    final current = widget.controller.cartQuantityFor(product.id);
    final entered = await showDialog<double>(
      context: context,
      builder: (_) => _QuantityInputDialog(
        strings: strings,
        currency: widget.controller.currency,
        title: product.name,
        label: strings.stockQtyRequired,
        helper: strings.stockCountLabel(product.stock),
        initialValue: current,
        cancelLabel: strings.cancel,
        confirmLabel: strings.applyAction,
      ),
    );
    if (entered == null || !mounted) return;
    if (!widget.controller.canSellNegativeStock && entered > product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.onlyLeftMsg(product.stock))),
      );
    }
    widget.controller.setCartQuantity(product.id, entered);
  }

  Future<void> _openCheckoutSheet() async {
    final completedSale = await showModalBottomSheet<Sale>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CheckoutSheet(controller: widget.controller),
    );
    if (completedSale != null && mounted) {
      final strings = widget.controller.strings;
      final currency = widget.controller.currency;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.saleRecordedMsg(
              formatMoney(completedSale.total, currency),
              completedSale.totalUnits,
            ),
          ),
        ),
      );
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ReceiptSheet(
          controller: widget.controller,
          sale: completedSale,
          onNewCustomer: () {
            _searchController.clear();
            setState(() {
              _searchQuery = '';
              _inStockOnly = false;
              _selectedCategory = null;
            });
            widget.controller.setPosSelectedCategory('');
            widget.controller.setWholesaleCartMode(false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _searchFocusNode.requestFocus();
              }
            });
          },
        ),
      );
    }
  }

  Future<void> _shareCartEstimate() async {
    final lines = widget.controller.cartLines;
    if (lines.isEmpty) return;
    final strings = widget.controller.strings;
    final text = ExportService.buildCartEstimateText(
      lines
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
      strings,
      widget.controller.currency,
      shopName: widget.controller.shopName,
      shopAddress: widget.controller.shopAddress,
      shopPhone: widget.controller.shopPhone,
    );
    await Share.share(text, subject: strings.estimateTitle);
  }

  void _clearCartWithUndo() {
    final prev = widget.controller.captureCartSnapshot();
    if (prev.quantities.isEmpty && !prev.wholesaleMode) return;
    widget.controller.clearCart();
    final strings = widget.controller.strings;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(strings.cartClearedMsg),
        action: SnackBarAction(
          label: strings.undoAction,
          onPressed: () => widget.controller.restoreCartSnapshot(prev),
        ),
      ),
    );
  }

  Future<void> _holdCurrentSale() async {
    if (widget.controller.cartItemCount == 0) return;
    final strings = widget.controller.strings;
    final label = await showDialog<String>(
      context: context,
      builder: (_) => _HoldSaleDialog(
        title: strings.holdSaleTitle,
        hint: strings.holdSaleLabelHint,
        cancelLabel: strings.cancel,
        confirmLabel: strings.holdSaleBtn,
      ),
    );
    if (label == null || !mounted) return;
    await widget.controller.holdCurrentCart(label: label);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.saleHeldMsg)),
      );
    }
  }

  void _openHeldSales() {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.holdSale);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _HeldSalesSheet(controller: widget.controller),
    );
  }

  Future<void> _showSellerPickerSheet() async {
    final nameCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final strings = widget.controller.strings;
          final sellers = widget.controller.sellers;
          final active = widget.controller.activeSeller;
          Future<void> submitNew() async {
            final text = nameCtrl.text.trim();
            if (text.isEmpty) return;
            await widget.controller.addSeller(text);
            nameCtrl.clear();
            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.viewInsetsOf(sheetCtx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.selectSellerTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: nameCtrl,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submitNew(),
                        decoration: InputDecoration(
                          hintText: strings.addSellerHint,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: submitNew,
                      child: Text(strings.addSellerBtn),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  dense: true,
                  leading: Icon(
                    active.isEmpty
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(strings.noSellerOption),
                  onTap: () async {
                    await widget.controller.setActiveSeller('');
                    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                  },
                ),
                for (final name in sellers)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      active == name
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(name),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => widget.controller.removeSeller(name),
                    ),
                    onTap: () async {
                      await widget.controller.setActiveSeller(name);
                      if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
    nameCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;
        final products = _availableProducts();
        final cartCount = widget.controller.cartItemCount;
        final isCashier = widget.controller.cashierMode;
        final activeSeller = widget.controller.activeSeller;

        return HardwareBarcodeListener(
          onBarcode: (code) {
            final feedback = _handleContinuousScan(code);
            HapticFeedback.mediumImpact();
            ScaffoldMessenger.of(context)..
              hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 2),
                  content: Text(feedback.message),
                ),
              );
          },
          child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            title: Text(strings.recordSaleTitle),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ActionChip(
                  avatar: const Icon(Icons.person_outline, size: 16),
                  label: Text(
                    activeSeller.isEmpty
                        ? strings.selectSellerShort
                        : activeSeller,
                    overflow: TextOverflow.ellipsis,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: _showSellerPickerSheet,
                ),
              ),
              if (widget.controller.heldSales.isNotEmpty)
                IconButton(
                  tooltip: strings.heldSalesTitle,
                  onPressed: _openHeldSales,
                  icon: Badge(
                    label: Text('${widget.controller.heldSales.length}'),
                    child: const Icon(Icons.pause_circle_outline),
                  ),
                ),
              IconButton(
                tooltip: strings.shiftClosingTitle,
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) =>
                        ShiftClosingSheet(controller: widget.controller),
                  );
                },
                icon: const Icon(Icons.summarize_outlined),
              ),
              SettingsButton(controller: widget.controller),
              if (cartCount > 0)
                TextButton(
                  onPressed: _clearCartWithUndo,
                  child: Text(strings.clearCart),
                ),
            ],
          ),
          body: Column(
            children: [
              const SizedBox(height: 4),
              if (_searchQuery.trim().isEmpty && _recentQueries.isNotEmpty)
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _recentQueries.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final recent = _recentQueries[index];
                      return InputChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.history, size: 16),
                        label: Text(recent),
                        onPressed: () {
                          setState(() {
                            _searchController.text = recent;
                            _searchController.selection =
                                TextSelection.collapsed(offset: recent.length);
                            _searchQuery = recent;
                          });
                        },
                        onDeleted: () {
                          setState(() => _recentQueries.removeAt(index));
                        },
                      );
                    },
                  ),
                ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: const Icon(Icons.bolt_outlined, size: 16),
                        label: Text(strings.customPosItemBtn),
                        onPressed: () => _showCustomPosItemDialog(
                          context,
                          widget.controller,
                        ),
                      ),
                    ),
                    if (widget.controller.products.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: const Icon(Icons.storefront_outlined, size: 16),
                          label: Text(strings.wholesaleModeChip),
                          selected: widget.controller.wholesaleCartMode,
                          onSelected: (selected) {
                            widget.controller.setWholesaleCartMode(selected);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(
                            strings.inStockFilter(
                              widget.controller.products
                                  .where((p) => p.stock > 0)
                                  .length,
                            ),
                          ),
                          selected: _inStockOnly,
                          onSelected: (selected) {
                            setState(() => _inStockOnly = selected);
                          },
                        ),
                      ),
                      if (widget.controller.categories.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(strings.allCategory),
                            selected: _selectedCategory == null,
                            onSelected: (_) => _setSelectedCategory(null),
                          ),
                        ),
                        for (final category in widget.controller.categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(category),
                              selected: _selectedCategory == category,
                              onSelected: (_) => _setSelectedCategory(category),
                            ),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
              if (_searchQuery.trim().isEmpty &&
                  _selectedCategory == null &&
                  widget.controller.products.isNotEmpty) ...[
                Builder(
                  builder: (context) {
                    final quickItems = _quickTopProducts();
                    if (quickItems.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            strings.quickPosItemsTitle,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 76,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: quickItems.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, idx) {
                                final item = quickItems[idx];
                                final inCart = widget.controller
                                    .cartQuantityFor(item.id);
                                final isWholesale = item.hasWholesalePrice &&
                                    (widget.controller.wholesaleCartMode ||
                                        item.isAutoWholesaleForQty(inCart));
                                final price = isWholesale
                                    ? item.wholesalePrice
                                    : item.sellPrice;
                                return SizedBox(
                                  width: 132,
                                  child: Material(
                                    color: inCart > 0
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        _addProductToCart(item);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              item.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  formatMoney(price, currency),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                ),
                                                if (inCart > 0)
                                                  Text(
                                                    '×${formatQty(inCart)}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .primary,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                  ),
                                              ],
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
                    );
                  },
                ),
              ],
              Expanded(
                child: widget.controller.products.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            strings.addGoodsFirst,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : products.isEmpty
                        ? Center(child: Text(strings.noMatchingProducts))
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              4,
                              16,
                              16 + MediaQuery.viewInsetsOf(context).bottom,
                            ),
                            itemCount: products.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final product = products[index];
                              final inCart =
                                  widget.controller.cartQuantityFor(product.id);
                              final canAdd = widget.controller.canSellNegativeStock ||
                                  (product.stock > 0 && inCart < product.stock);
                              final isWholesaleDisabled = widget.controller
                                  .isWholesaleDisabledFor(product.id);
                              final isAutoWholesale = !isWholesaleDisabled &&
                                  product.isAutoWholesaleForQty(inCart);
                              final isWholesale = !isWholesaleDisabled &&
                                  product.hasWholesalePrice &&
                                  (widget.controller.wholesaleCartMode ||
                                      isAutoWholesale);
                              final activePrice = isWholesale
                                  ? product.wholesalePrice
                                  : product.sellPrice;
                              final remainingForWholesale = (!isWholesaleDisabled &&
                                      product.hasAutoWholesale &&
                                      !isWholesale &&
                                      inCart > 0 &&
                                      inCart < product.wholesaleMinQty &&
                                      (widget.controller.canSellNegativeStock ||
                                          product.stock >=
                                              product.wholesaleMinQty))
                                  ? product.wholesaleMinQty - inCart
                                  : 0;

                              return Card(
                                margin: EdgeInsets.zero,
                                color: inCart > 0
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.25)
                                    : null,
                                child: ListTile(
                                  leading: product.imagePath.trim().isNotEmpty
                                      ? ProductThumbnail(
                                          imagePath: product.imagePath,
                                          size: 46,
                                          onTap: () => showProductPhotoPreview(
                                            context,
                                            title: product.name,
                                            imagePath: product.imagePath,
                                          ),
                                        )
                                      : null,
                                  onTap: canAdd
                                      ? () => _addProductToCart(product)
                                      : null,
                                  title: GestureDetector(
                                    onLongPress: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: product.name),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              strings.copiedToClipboardMsg,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: _buildHighlightedName(
                                      context,
                                      product.name,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${formatMoney(activePrice, currency)}'
                                        '${isWholesale ? ' (${strings.wholesaleShort})' : (product.hasWholesalePrice ? ' • ${strings.wholesaleShort}: ${formatMoney(product.wholesalePrice, currency)}${product.wholesaleMinQty > 0 ? ' (${strings.wholesaleFromQtyBadge(product.wholesaleMinQty)})' : ''}' : '')}'
                                        '  •  ${strings.stockCountLabel(product.stock)}'
                                        '${inCart > 0 ? '  •  ${strings.inCartLabel(inCart)}' : ''}',
                                      ),
                                      if (product.stock > 0 &&
                                          product.isExpiringOrExpired(
                                            withinDays: 30,
                                          ))
                                        Builder(builder: (context) {
                                          final exp = product.expiryDate!;
                                          final days =
                                              product.daysUntilExpiry()!;
                                          final dateStr =
                                              '${exp.day.toString().padLeft(2, '0')}.${exp.month.toString().padLeft(2, '0')}';
                                          final label = days < 0
                                              ? '${strings.expiredBadge} ($dateStr)'
                                              : (days == 0
                                                  ? strings.expiresTodayBadge
                                                  : strings.expiresInDaysBadge(
                                                      days,
                                                      dateStr,
                                                    ));
                                          return Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              '⚠ $label — ${strings.sellFirstHint}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: days <= 0
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .error
                                                    : Colors.deepOrange.shade700,
                                              ),
                                            ),
                                          );
                                        }),
                                      if (remainingForWholesale > 0)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: ActionChip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            avatar: const Icon(
                                              Icons.local_offer_outlined,
                                              size: 14,
                                            ),
                                            label: Text(
                                              strings.addMoreForWholesaleBtn(
                                                remainingForWholesale,
                                                formatMoney(
                                                  product.wholesalePrice,
                                                  currency,
                                                ),
                                              ),
                                            ),
                                            onPressed: () => widget.controller
                                                .setCartQuantity(
                                              product.id,
                                              product.wholesaleMinQty.toDouble(),
                                            ),
                                          ),
                                        ),
                                      if (inCart > 0 &&
                                          product.hasWholesalePrice &&
                                          (isWholesale || isWholesaleDisabled))
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: ActionChip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            avatar: Icon(
                                              isWholesaleDisabled
                                                  ? Icons.local_offer_outlined
                                                  : Icons.money_off,
                                              size: 14,
                                            ),
                                            label: Text(
                                              isWholesaleDisabled
                                                  ? strings.restoreWholesaleBtn
                                                  : strings
                                                      .noWholesaleDiscountBtn,
                                            ),
                                            onPressed: () => widget.controller
                                                .setWholesaleDisabledFor(
                                              product.id,
                                              !isWholesaleDisabled,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: inCart > 0
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () => widget.controller
                                                  .setCartQuantity(
                                                product.id,
                                                inCart - 1,
                                              ),
                                              icon: const Icon(
                                                Icons.remove_circle_outline,
                                              ),
                                            ),
                                            InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              onTap: () =>
                                                  _promptCartQuantity(product),
                                              child: Container(
                                                constraints:
                                                    const BoxConstraints(
                                                  minWidth: 38,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .outlineVariant,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  formatQty(inCart),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: canAdd
                                                  ? () => _addProductToCart(
                                                        product,
                                                      )
                                                  : null,
                                              icon: const Icon(
                                                Icons.add_circle_outline,
                                              ),
                                            ),
                                          ],
                                        )
                                      : (product.stock <= 0
                                          ? Text(
                                              strings.outShort,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .error,
                                                  ),
                                            )
                                          : null),
                                ),
                              );
                            },
                          ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    10,
                    16,
                    12 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              textInputAction: TextInputAction.search,
                              onChanged: (value) =>
                                  setState(() => _searchQuery = value),
                              onSubmitted: _handleSearchSubmitted,
                              decoration: InputDecoration(
                                hintText: strings.searchPosHint,
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
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: strings.scanBarcodeTitle,
                            onPressed: _scanAndAddBySku,
                            icon: const Icon(Icons.qr_code_scanner),
                          ),
                        ],
                      ),
                      if (cartCount > 0) ...[
                        Builder(
                          builder: (context) {
                            final upsell = widget.controller
                                .frequentlyBoughtTogetherForCart(limit: 3);
                            if (upsell.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: SizedBox(
                                height: 34,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    Center(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(right: 6),
                                        child: Text(
                                          strings.frequentlyBoughtWithLabel,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                    ),
                                    for (final item in upsell)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 6),
                                        child: ActionChip(
                                          visualDensity: VisualDensity.compact,
                                          avatar: const Icon(
                                            Icons.add,
                                            size: 14,
                                          ),
                                          label: Text(
                                            '${item.name} • ${formatMoney(item.sellPrice, currency)}',
                                          ),
                                          onPressed: () {
                                            HapticFeedback.selectionClick();
                                            _addProductToCart(item);
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    strings.cartSummary(
                                      cartCount,
                                      formatMoney(
                                        widget.controller.cartSubtotal,
                                        currency,
                                      ),
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  if (!isCashier)
                                    Text(
                                      strings.estProfit(
                                        formatMoney(
                                          widget.controller.cartEstimatedProfit,
                                          currency,
                                        ),
                                      ),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              tooltip: strings.sendEstimateBtn,
                              onPressed: _shareCartEstimate,
                              icon: const Icon(Icons.request_quote_outlined),
                            ),
                            const SizedBox(width: 6),
                            IconButton.filledTonal(
                              tooltip: strings.holdSaleBtn,
                              onPressed: _holdCurrentSale,
                              icon: const Icon(Icons.pause_circle_outline),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _openCheckoutSheet,
                              icon: const Icon(Icons.point_of_sale),
                              label: Text(strings.checkout),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }
}

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({required this.controller});

  final ShopController controller;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _discountController =
      TextEditingController(text: '0');
  final TextEditingController _discountPercentController =
      TextEditingController();
  final TextEditingController _discountReasonController =
      TextEditingController();
  final TextEditingController _paidNowController =
      TextEditingController(text: '0');
  final TextEditingController _cashReceivedController = TextEditingController();
  final TextEditingController _primarySplitController = TextEditingController();
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  CustomerSegment _customerSegment = CustomerSegment.retail;
  bool _splitPayment = false;
  PaymentMethod _secondaryMethod = PaymentMethod.kaspiQr;
  DateTime? _dueDate;
  String? _customerError;
  String? _phoneError;
  bool _discountDrivenByPercent = false;
  double _lastSubtotal = -1;

  @override
  void dispose() {
    _customerController.dispose();
    _phoneController.dispose();
    _discountController.dispose();
    _discountPercentController.dispose();
    _discountReasonController.dispose();
    _paidNowController.dispose();
    _cashReceivedController.dispose();
    _primarySplitController.dispose();
    super.dispose();
  }

  double get _discount {
    final raw = _discountController.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw) ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  double get _discountPercent {
    final raw = _discountPercentController.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw) ?? 0;
    return parsed.clamp(0.0, 100.0);
  }

  String _formatPercent(double pct) {
    if (pct <= 0.009) return '';
    if ((pct - pct.roundToDouble()).abs() < 0.05) {
      return pct.round().toString();
    }
    return pct.toStringAsFixed(1);
  }

  void _onDiscountAmountChanged(double subtotal) {
    _discountDrivenByPercent = false;
    if (subtotal > 0 && _discount > 0) {
      final pct = (_discount / subtotal * 100).clamp(0.0, 100.0);
      _discountPercentController.text = _formatPercent(pct);
    } else {
      _discountPercentController.clear();
    }
    setState(() {});
  }

  void _onDiscountPercentChanged(double subtotal) {
    final raw = _discountPercentController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) {
      _discountDrivenByPercent = false;
      _discountController.text = '0';
      setState(() {});
      return;
    }
    final parsed = double.tryParse(raw);
    if (parsed == null) {
      setState(() {});
      return;
    }
    final clamped = parsed.clamp(0.0, 100.0);
    _discountDrivenByPercent = clamped > 0;
    final disc = (subtotal * clamped / 100).roundToDouble();
    _discountController.text = disc > 0 ? disc.toStringAsFixed(0) : '0';
    setState(() {});
  }

  void _applyPresetPercent(int pct, double subtotal) {
    _discountDrivenByPercent = true;
    _discountPercentController.text = '$pct';
    final disc = (subtotal * pct / 100).roundToDouble();
    _discountController.text = disc.toStringAsFixed(0);
    setState(() {});
  }

  void _clearDiscount() {
    _discountDrivenByPercent = false;
    _discountController.text = '0';
    _discountPercentController.clear();
    _discountReasonController.clear();
    setState(() {});
  }

  double get _paidNow {
    final parsed = double.tryParse(_paidNowController.text.trim()) ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  double get _cashReceived {
    final raw = _cashReceivedController.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw) ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  double _primarySplitFor(double total) {
    final raw = _primarySplitController.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw) ?? (total / 2).roundToDouble();
    return parsed.clamp(0.0, total);
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _openAddProductPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddProductToCheckoutSheet(controller: widget.controller),
    );
  }

  void _syncPhoneForCustomer(String name) {
    final knownPhone = widget.controller.customerPhoneByName(name);
    if (knownPhone.isNotEmpty) {
      _phoneController.text = knownPhone;
      _phoneError = null;
    }
    final seg = widget.controller.applyCustomerSegmentForCart(name);
    if (seg != null) {
      _customerSegment = seg;
    }
  }

  Future<void> _editCustomerRecommendation(String name) async {
    final strings = widget.controller.strings;
    final existingPhone = widget.controller.customerPhoneByName(name);
    final result = await showDialog<({String name, String phone})>(
      context: context,
      builder: (_) => _EditCustomerRecommendationDialog(
        strings: strings,
        initialName: name,
        initialPhone: existingPhone,
      ),
    );
    if (result == null || !mounted) return;
    final newName = result.name.trim();
    if (newName.isEmpty) return;
    final wasSelected =
        _customerController.text.trim().toLowerCase() == name.toLowerCase();
    await widget.controller.renameCustomerRecommendation(
      oldName: name,
      newName: newName,
      phone: result.phone,
    );
    if (!mounted) return;
    if (wasSelected) {
      setState(() {
        _customerController.text = newName;
        _customerError = null;
        if (result.phone.trim().isNotEmpty) {
          _phoneController.text = result.phone.trim();
          _phoneError = null;
        }
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.customerUpdatedMsg)),
    );
  }

  Future<void> _deleteCustomerRecommendation(String name) async {
    final strings = widget.controller.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.deleteCustomerRecommendationTitle),
        content: Text(strings.deleteCustomerRecommendationBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final wasSelected =
        _customerController.text.trim().toLowerCase() == name.toLowerCase();
    await widget.controller.deleteCustomerRecommendation(name);
    if (!mounted) return;
    if (wasSelected) {
      setState(() {
        _customerController.clear();
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.customerRemovedMsg)),
    );
  }

  Future<void> _completeSale() async {
    final strings = widget.controller.strings;
    if (_paymentMethod == PaymentMethod.postPay) {
      var hasError = false;
      if (_customerController.text.trim().isEmpty) {
        _customerError = strings.enterCustomerName;
        hasError = true;
      }
      final digitsCount =
          _phoneController.text.replaceAll(RegExp(r'[^0-9+]'), '').length;
      if (digitsCount < 5) {
        _phoneError = strings.enterCustomerPhone;
        hasError = true;
      }
      if (hasError) {
        setState(() {});
        return;
      }
    }

    final effectiveDiscount =
        widget.controller.canGiveDiscounts ? _discount : 0.0;
    final isBelowCost =
        widget.controller.isSaleBelowCost(discount: effectiveDiscount);
    String? verifiedPin;
    if (isBelowCost &&
        widget.controller.cashierMode &&
        widget.controller.hasOwnerPin) {
      final loss = (widget.controller.cartTotalCost -
              (widget.controller.cartSubtotal - effectiveDiscount)
                  .clamp(0.0, double.infinity))
          .clamp(0.0, double.infinity);
      final lossText = formatMoney(loss, widget.controller.currency);
      verifiedPin = await showPinProtectedDeleteDialog(
        context,
        controller: widget.controller,
        title: strings.belowCostPinDialogTitle,
        body: loss > 0.009
            ? '${strings.belowCostSaleWarning(lossText)}\n${strings.belowCostPinRequiredNote}'
            : strings.belowCostPinRequiredNote,
        confirmLabel: strings.confirmBelowCostAction,
      );
      if (verifiedPin == null || !mounted) return;
    }

    final total = (widget.controller.cartSubtotal - effectiveDiscount)
        .clamp(0.0, double.infinity);
    final primarySplit = _primarySplitFor(total);
    final secondaryAmount = (_splitPayment && _paymentMethod != PaymentMethod.postPay)
        ? (total - primarySplit).clamp(0.0, total)
        : 0.0;

    final sale = await widget.controller.completeSale(
      paymentMethod: _paymentMethod,
      secondaryPaymentMethod: (_splitPayment && secondaryAmount > 0.009)
          ? _secondaryMethod
          : null,
      secondaryAmount: secondaryAmount,
      customerName: _customerController.text,
      customerPhone: _phoneController.text,
      customerSegment: _customerController.text.trim().isNotEmpty
          ? _customerSegment
          : null,
      discount: effectiveDiscount,
      discountReason: effectiveDiscount > 0 ? _discountReasonController.text : '',
      paidAmount: _paymentMethod == PaymentMethod.postPay ? _paidNow : null,
      dueDate: _paymentMethod == PaymentMethod.postPay ? _dueDate : null,
      ownerPinAttempt: verifiedPin,
    );
    if (mounted) {
      Navigator.of(context).pop(sale);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;
        final lines = widget.controller.cartLines;
        final subtotal = widget.controller.cartSubtotal;
        if (_discountDrivenByPercent &&
            _lastSubtotal >= 0 &&
            (subtotal - _lastSubtotal).abs() > 0.009) {
          final recalculated = (subtotal * _discountPercent / 100).roundToDouble();
          _discountController.text =
              recalculated > 0 ? recalculated.toStringAsFixed(0) : '0';
        }
        _lastSubtotal = subtotal;
        final canGiveDiscounts = widget.controller.canGiveDiscounts;
        final effectiveDiscount = canGiveDiscounts ? _discount : 0.0;
        final total = (subtotal - effectiveDiscount).clamp(0.0, double.infinity);
        final isPostPay = _paymentMethod == PaymentMethod.postPay;
        final customerNames = widget.controller.recentCustomerNames;
        final customerQuery = _customerController.text.trim().toLowerCase();
        final matchingCustomers = customerQuery.isEmpty
            ? customerNames
            : customerNames
                .where((n) => n.toLowerCase().contains(customerQuery))
                .toList();
        final primarySplit = _primarySplitFor(total);
        final secondarySplit = (total - primarySplit).clamp(0.0, total);
        final cashTarget = _splitPayment ? primarySplit : total;

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.checkout,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.storefront_outlined, size: 15),
                      label: Text(strings.wholesaleModeChip),
                      selected: widget.controller.wholesaleCartMode,
                      onSelected: (v) =>
                          widget.controller.setWholesaleCartMode(v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final line in lines)
                  Dismissible(
                    key: ValueKey('cart_line_${line.product.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    onDismissed: (_) {
                      final removedQty = line.quantity;
                      final productId = line.product.id;
                      final productName = line.product.name;
                      widget.controller.setCartQuantity(productId, 0);
                      final messenger = ScaffoldMessenger.of(context);
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 4),
                          content: Text(productName),
                          action: SnackBarAction(
                            label: strings.undoAction,
                            onPressed: () => widget.controller.setCartQuantity(
                              productId,
                              removedQty,
                            ),
                          ),
                        ),
                      );
                    },
                    child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(line.product.name),
                    subtitle: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () async {
                        final nextPrice = await showDialog<double>(
                          context: context,
                          builder: (_) => _PriceInputDialog(
                            strings: strings,
                            currency: currency,
                            title: line.product.name,
                            label: strings.customPriceLabel,
                            helper: line.product.hasWholesalePrice
                                ? '${strings.sellShort}: ${formatMoney(line.product.sellPrice, currency)} • ${strings.wholesaleShort}: ${formatMoney(line.product.wholesalePrice, currency)}'
                                : '${strings.sellShort}: ${formatMoney(line.product.sellPrice, currency)}',
                            initialValue: line.unitPrice,
                            defaultPrice: line.defaultUnitPrice,
                            costPrice: line.product.costPrice,
                            allowDiscount: canGiveDiscounts,
                            cancelLabel: strings.cancel,
                            resetLabel: strings.resetAction,
                            confirmLabel: strings.applyAction,
                          ),
                        );
                        if (nextPrice == null || !mounted) return;
                        widget.controller.setCartItemPrice(
                          line.product.id,
                          nextPrice,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    '${formatMoney(line.unitPrice, currency)}'
                                    '${line.isWholesalePriceApplied ? ' (${line.isAutoWholesaleApplied && !widget.controller.wholesaleCartMode ? strings.autoWholesaleActiveBadge(line.product.wholesaleMinQty) : strings.wholesaleAppliedBadge})' : ''}'
                                    ' × ${line.quantity} = ${formatMoney(line.lineTotal, currency)}',
                                    style: (line.hasCustomPrice ||
                                            line.isWholesalePriceApplied)
                                        ? TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontWeight: FontWeight.w600,
                                          )
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.edit_outlined,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ),
                            if (line.product.costPrice > 0 &&
                                line.unitPrice + 0.009 < line.product.costPrice)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  strings.belowCostPriceWarning,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            if (line.product.hasAutoWholesale &&
                                !line.isWholesalePriceApplied &&
                                line.quantity < line.product.wholesaleMinQty &&
                                (widget.controller.canSellNegativeStock ||
                                    line.product.stock >=
                                        line.product.wholesaleMinQty))
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: const Icon(
                                    Icons.local_offer_outlined,
                                    size: 14,
                                  ),
                                  label: Text(
                                    strings.addMoreForWholesaleBtn(
                                      line.product.wholesaleMinQty -
                                          line.quantity,
                                      formatMoney(
                                        line.product.wholesalePrice,
                                        currency,
                                      ),
                                    ),
                                  ),
                                  onPressed: () =>
                                      widget.controller.setCartQuantity(
                                    line.product.id,
                                    line.product.wholesaleMinQty.toDouble(),
                                  ),
                                ),
                              ),
                            if (line.product.hasWholesalePrice &&
                                !line.hasCustomPrice &&
                                (line.isWholesalePriceApplied ||
                                    line.wholesaleDisabled))
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(
                                    line.wholesaleDisabled
                                        ? Icons.local_offer_outlined
                                        : Icons.money_off,
                                    size: 14,
                                  ),
                                  label: Text(
                                    line.wholesaleDisabled
                                        ? strings.restoreWholesaleBtn
                                        : strings.noWholesaleDiscountBtn,
                                  ),
                                  onPressed: () =>
                                      widget.controller.setWholesaleDisabledFor(
                                    line.product.id,
                                    !line.wholesaleDisabled,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => widget.controller.setCartQuantity(
                            line.product.id,
                            line.quantity - 1,
                          ),
                          icon: const Icon(Icons.remove),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            final entered = await showDialog<double>(
                              context: context,
                              builder: (_) => _QuantityInputDialog(
                                strings: strings,
                                currency: currency,
                                title: line.product.name,
                                label: strings.stockQtyRequired,
                                helper: strings.stockCountLabel(
                                  line.product.stock,
                                ),
                                initialValue: line.quantity,
                                cancelLabel: strings.cancel,
                                confirmLabel: strings.applyAction,
                              ),
                            );
                            if (entered == null || !context.mounted) return;
                            if (!widget.controller.canSellNegativeStock &&
                                entered > line.product.stock) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    strings.onlyLeftMsg(line.product.stock),
                                  ),
                                ),
                              );
                            }
                            widget.controller.setCartQuantity(
                              line.product.id,
                              entered,
                            );
                          },
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 36),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              formatQty(line.quantity),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: (widget.controller.canSellNegativeStock ||
                                  line.quantity < line.product.stock)
                              ? () => widget.controller.setCartQuantity(
                                    line.product.id,
                                    line.quantity + 1,
                                  )
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                  ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _openAddProductPicker,
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: Text(strings.addProductToReceiptBtn),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showCustomPosItemDialog(
                        context,
                        widget.controller,
                      ),
                      icon: const Icon(Icons.bolt_outlined, size: 18),
                      label: Text(strings.customPosItemBtn),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final method in PaymentMethod.values)
                      ChoiceChip(
                        label: Text(strings.paymentMethodLabel(method.name)),
                        selected: _paymentMethod == method,
                        onSelected: (_) {
                          setState(() {
                            _paymentMethod = method;
                            if (method == PaymentMethod.postPay) {
                              _splitPayment = false;
                            } else {
                              _customerError = null;
                              if (_secondaryMethod == method) {
                                _secondaryMethod = PaymentMethod.values
                                    .firstWhere(
                                  (m) =>
                                      m != PaymentMethod.postPay &&
                                      m != method,
                                );
                              }
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    dense: true,
                    maintainState: true,
                    initiallyExpanded: isPostPay ||
                        _splitPayment ||
                        effectiveDiscount > 0 ||
                        _customerError != null ||
                        _phoneError != null,
                    leading: const Icon(Icons.tune, size: 20),
                    title: Text(
                      strings.checkoutMoreOptionsTitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    children: [
                      if (!isPostPay)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilterChip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.call_split, size: 16),
                            label: Text(strings.splitPaymentLabel),
                            selected: _splitPayment,
                            onSelected: (v) {
                              setState(() {
                                _splitPayment = v;
                                if (v) {
                                  if (_secondaryMethod == _paymentMethod ||
                                      _secondaryMethod ==
                                          PaymentMethod.postPay) {
                                    _secondaryMethod = PaymentMethod.values
                                        .firstWhere(
                                      (m) =>
                                          m != PaymentMethod.postPay &&
                                          m != _paymentMethod,
                                    );
                                  }
                                  if (_primarySplitController.text
                                      .trim()
                                      .isEmpty) {
                                    _primarySplitController.text =
                                        (total / 2).round().toString();
                                  }
                                }
                              });
                            },
                          ),
                        ),
                if (_splitPayment && !isPostPay) ...[
                  const SizedBox(height: 10),
                  Text(
                    strings.secondPaymentMethodLabel,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final method in PaymentMethod.values)
                        if (method != PaymentMethod.postPay &&
                            method != _paymentMethod)
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(strings.paymentMethodLabel(method.name)),
                            selected: _secondaryMethod == method,
                            onSelected: (_) =>
                                setState(() => _secondaryMethod = method),
                          ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _primarySplitController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: strings.firstMethodAmountLabel(
                              strings.paymentMethodLabel(_paymentMethod.name),
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text('50%'),
                        onPressed: () {
                          _primarySplitController.text =
                              (total / 2).round().toString();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.remainingMethodAmountLabel(
                      strings.paymentMethodLabel(_secondaryMethod.name),
                      formatMoney(secondarySplit, currency),
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                if (matchingCustomers.isNotEmpty) ...[
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final name in matchingCustomers)
                          Builder(
                            builder: (context) {
                              final isSelected = _customerController.text
                                      .trim()
                                      .toLowerCase() ==
                                  name.toLowerCase();
                              final scheme = Theme.of(context).colorScheme;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Material(
                                  color: isSelected
                                      ? scheme.secondaryContainer
                                      : scheme.surfaceContainerLow,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: isSelected
                                          ? scheme.secondary
                                          : scheme.outlineVariant,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _customerController.text =
                                                isSelected ? '' : name;
                                            _customerError = null;
                                            if (isSelected) {
                                              _customerSegment =
                                                  CustomerSegment.retail;
                                              widget.controller
                                                  .applyCustomerSegmentForCart(
                                                '',
                                              );
                                            } else {
                                              _syncPhoneForCustomer(name);
                                            }
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            10,
                                            6,
                                            4,
                                            6,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isSelected) ...[
                                                Icon(
                                                  Icons.check,
                                                  size: 15,
                                                  color: scheme
                                                      .onSecondaryContainer,
                                                ),
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelLarge
                                                    ?.copyWith(
                                                      color: isSelected
                                                          ? scheme
                                                              .onSecondaryContainer
                                                          : scheme.onSurface,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () =>
                                            _editCustomerRecommendation(name),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 6,
                                          ),
                                          child: Icon(
                                            Icons.edit_outlined,
                                            size: 15,
                                            color: isSelected
                                                ? scheme.onSecondaryContainer
                                                : scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () =>
                                            _deleteCustomerRecommendation(name),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            4,
                                            6,
                                            8,
                                            6,
                                          ),
                                          child: Icon(
                                            Icons.close,
                                            size: 15,
                                            color: isSelected
                                                ? scheme.onSecondaryContainer
                                                : scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _customerController,
                  onChanged: (val) {
                    setState(() {
                      if (_customerError != null) {
                        _customerError = null;
                      }
                      _syncPhoneForCustomer(val);
                    });
                  },
                  decoration: InputDecoration(
                    labelText: isPostPay
                        ? strings.customerNameRequiredForDebt
                        : strings.customerNameOptional,
                    errorText: _customerError,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (_customerController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final seg in CustomerSegment.values)
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(strings.customerSegmentLabel(seg.name)),
                          selected: _customerSegment == seg,
                          onSelected: (_) {
                            setState(() => _customerSegment = seg);
                            widget.controller.setWholesaleCartMode(
                              seg == CustomerSegment.wholesale,
                            );
                          },
                        ),
                    ],
                  ),
                  if (widget.controller.lastSaleForCustomer(
                        _customerController.text,
                      ) !=
                      null) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.replay, size: 16),
                        label: Text(strings.repeatOrderBtn),
                        onPressed: () {
                          final lastSale = widget.controller
                              .lastSaleForCustomer(_customerController.text);
                          if (lastSale == null) return;
                          final res =
                              widget.controller.repeatSaleToCart(lastSale);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                res.addedLines == 0
                                    ? strings.noAvailableItemsToRepeatMsg
                                    : (res.skippedCount > 0
                                        ? strings.orderRepeatedPartialMsg(
                                            res.addedLines,
                                            res.skippedCount,
                                          )
                                        : strings.orderRepeatedToCartMsg(
                                            res.addedLines,
                                          )),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
                if (isPostPay) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) {
                      if (_phoneError != null) {
                        setState(() => _phoneError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: strings.customerPhoneRequiredForDebt,
                      errorText: _phoneError,
                      prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (!canGiveDiscounts)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.block,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings.discountsDisabledNote,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _discountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => _onDiscountAmountChanged(subtotal),
                          decoration: InputDecoration(
                            labelText: strings.discountAmount,
                            suffixIcon: _discount > 0
                                ? IconButton(
                                    onPressed: _clearDiscount,
                                    icon: const Icon(Icons.clear, size: 18),
                                  )
                                : null,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _discountPercentController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => _onDiscountPercentChanged(subtotal),
                          decoration: InputDecoration(
                            labelText: strings.discountPercentLabel,
                            suffixText: '%',
                            suffixIcon:
                                _discountPercentController.text.trim().isNotEmpty
                                    ? IconButton(
                                        onPressed: _clearDiscount,
                                        icon: const Icon(Icons.clear, size: 18),
                                      )
                                    : null,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (subtotal > 0) ...[
                    const SizedBox(height: 6),
                    Builder(
                      builder: (context) {
                        final roundTargets = <double>[];
                        void tryAddRoundTarget(int step) {
                          final target = (total ~/ step) * step.toDouble();
                          if (target > 0 &&
                              (total - target).abs() >= 1 &&
                              !roundTargets.any((t) => (t - target).abs() < 1)) {
                            roundTargets.add(target);
                          }
                        }

                        if (total >= 500) {
                          tryAddRoundTarget(500);
                        }
                        if (total >= 1000) {
                          tryAddRoundTarget(1000);
                        }
                        if (roundTargets.isEmpty && total >= 100) {
                          tryAddRoundTarget(100);
                        }

                        return Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final pct in const [5, 10, 15])
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: Text('-$pct%'),
                                onPressed: () =>
                                    _applyPresetPercent(pct, subtotal),
                              ),
                            for (final target in roundTargets)
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                avatar: const Icon(
                                  Icons.auto_fix_high,
                                  size: 16,
                                ),
                                label: Text(
                                  strings.roundTotalAction(
                                    formatMoney(target, currency),
                                  ),
                                ),
                                onPressed: () {
                                  final disc =
                                      (subtotal - target).clamp(0.0, subtotal);
                                  _discountDrivenByPercent = false;
                                  _discountController.text =
                                      disc.toStringAsFixed(0);
                                  final pct = subtotal > 0
                                      ? (disc / subtotal * 100).clamp(0.0, 100.0)
                                      : 0.0;
                                  _discountPercentController.text =
                                      _formatPercent(pct);
                                  setState(() {});
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                  if (_discount > 0) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _discountReasonController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: strings.discountReasonLabel,
                        prefixIcon: const Icon(Icons.label_outline, size: 18),
                        suffixIcon:
                            _discountReasonController.text.trim().isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      _discountReasonController.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.clear, size: 18),
                                  )
                                : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final preset in strings.discountReasonPresets)
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(preset),
                            selected: _discountReasonController.text.trim() ==
                                preset,
                            onSelected: (selected) {
                              setState(() {
                                _discountReasonController.text =
                                    selected ? preset : '';
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ],
                    ],
                  ),
                ),
                if (_paymentMethod == PaymentMethod.cash) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _cashReceivedController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onTap: () => selectAllText(_cashReceivedController),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: strings.cashReceivedLabel,
                      suffixIcon: _cashReceivedController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _cashReceivedController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(strings.exactCashBtn),
                        onPressed: () {
                          _cashReceivedController.text =
                              cashTarget == cashTarget.roundToDouble()
                                  ? cashTarget.toStringAsFixed(0)
                                  : cashTarget.toStringAsFixed(2);
                          setState(() {});
                        },
                      ),
                      for (final bill in const [2000, 5000, 10000, 20000])
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(formatMoney(bill.toDouble(), currency)),
                          onPressed: () {
                            _cashReceivedController.text = '$bill';
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                  if (_cashReceivedController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final diff = _cashReceived - cashTarget;
                        final isShort = diff < 0;
                        final theme = Theme.of(context);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isShort
                                ? theme.colorScheme.errorContainer
                                : theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isShort
                                    ? strings.shortAmountLabel
                                    : strings.changeDueLabel,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isShort
                                      ? theme.colorScheme.onErrorContainer
                                      : theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              Text(
                                formatMoney(diff.abs(), currency),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isShort
                                      ? theme.colorScheme.onErrorContainer
                                      : theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
                if (isPostPay) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _paidNowController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: strings.paidNowOptional,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickDueDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                      _dueDate == null
                          ? strings.selectDueDate
                          : '${strings.dueDateLabel}: ${formatDate(_dueDate!)}',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      strings.totalDue,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      formatMoney(total, currency),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                if (widget.controller.isSaleBelowCost(discount: effectiveDiscount)) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color:
                              Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            () {
                              final loss = (widget.controller.cartTotalCost -
                                      total)
                                  .clamp(0.0, double.infinity);
                              final base = loss > 0.009
                                  ? strings.belowCostSaleWarning(
                                      formatMoney(loss, currency),
                                    )
                                  : strings.belowCostPriceWarning;
                              if (widget.controller.cashierMode &&
                                  widget.controller.hasOwnerPin) {
                                return '$base ${strings.belowCostPinRequiredNote}';
                              }
                              return base;
                            }(),
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: lines.isEmpty ? null : _completeSale,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(strings.completeSale),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HoldSaleDialog extends StatefulWidget {
  const _HoldSaleDialog({
    required this.title,
    required this.hint,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final String hint;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<_HoldSaleDialog> createState() => _HoldSaleDialogState();
}

class _HoldSaleDialogState extends State<_HoldSaleDialog> {
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
            labelText: widget.hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _PriceInputDialog extends StatefulWidget {
  const _PriceInputDialog({
    required this.strings,
    required this.currency,
    required this.title,
    required this.label,
    required this.helper,
    required this.initialValue,
    required this.defaultPrice,
    this.costPrice = 0,
    this.allowDiscount = true,
    required this.cancelLabel,
    required this.resetLabel,
    required this.confirmLabel,
  });

  final AppStrings strings;
  final AppCurrency currency;
  final String title;
  final String label;
  final String helper;
  final double initialValue;
  final double defaultPrice;
  final double costPrice;
  final bool allowDiscount;
  final String cancelLabel;
  final String resetLabel;
  final String confirmLabel;

  @override
  State<_PriceInputDialog> createState() => _PriceInputDialogState();
}

class _PriceInputDialogState extends State<_PriceInputDialog> {
  late final TextEditingController _ctrl;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final text = widget.initialValue == widget.initialValue.roundToDouble()
        ? widget.initialValue.toStringAsFixed(0)
        : widget.initialValue.toStringAsFixed(2);
    _ctrl = TextEditingController(text: text);
    _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed =
        double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    if (parsed != null && parsed > 0) {
      if (!widget.allowDiscount && parsed + 0.009 < widget.defaultPrice) {
        setState(() => _errorText = widget.strings.discountsDisabledNote);
        return;
      }
      Navigator.of(context).pop(parsed);
    }
  }

  Future<void> _openCalculator() async {
    final initial = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    final result = await showCurrencyCalculatorDialog(
      context,
      strings: widget.strings,
      targetCurrency: widget.currency,
      productName: widget.title,
      initialValue: initial,
    );
    if (result != null && mounted) {
      _ctrl.text = result == result.roundToDouble()
          ? result.toStringAsFixed(0)
          : result.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentVal = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
    final isBelowCost = widget.costPrice > 0 &&
        currentVal != null &&
        currentVal > 0 &&
        currentVal + 0.009 < widget.costPrice;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onTap: () => selectAllText(_ctrl),
              onChanged: (_) => setState(() => _errorText = null),
              decoration: InputDecoration(
                labelText: widget.label,
                helperText: widget.helper,
                errorText: _errorText,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: widget.strings.currencyCalculatorTitle,
                  onPressed: _openCalculator,
                  icon: const Icon(Icons.calculate_outlined),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (isBelowCost) ...[
              const SizedBox(height: 8),
              Text(
                widget.strings.belowCostPriceWarning,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(widget.defaultPrice),
          child: Text(widget.resetLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _QuantityInputDialog extends StatefulWidget {
  const _QuantityInputDialog({
    required this.strings,
    required this.currency,
    required this.title,
    required this.label,
    required this.helper,
    required this.initialValue,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final AppStrings strings;
  final AppCurrency currency;
  final String title;
  final String label;
  final String helper;
  final double initialValue;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<_QuantityInputDialog> createState() => _QuantityInputDialogState();
}

class _QuantityInputDialogState extends State<_QuantityInputDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final text = formatQty(widget.initialValue);
    _ctrl = TextEditingController(text: text);
    _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = parseQty(_ctrl.text);
    if (parsed != null && parsed >= 0) {
      Navigator.of(context).pop(parsed);
    }
  }

  Future<void> _openCalculator() async {
    final initial = parseQty(_ctrl.text);
    final result = await showCurrencyCalculatorDialog(
      context,
      strings: widget.strings,
      targetCurrency: widget.currency,
      productName: widget.title,
      initialValue: initial,
      integerMode: false,
    );
    if (result != null && mounted) {
      _ctrl.text = formatQty(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onTap: () => selectAllText(_ctrl),
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.helper,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              tooltip: widget.strings.currencyCalculatorTitle,
              onPressed: _openCalculator,
              icon: const Icon(Icons.calculate_outlined),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _HeldSalesSheet extends StatelessWidget {
  const _HeldSalesSheet({required this.controller});

  final ShopController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final strings = controller.strings;
        final currency = controller.currency;
        final held = controller.heldSales;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.heldSalesTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (held.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    strings.noGoodsMatch,
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: held.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final item = held[index];
                      var estTotal = 0.0;
                      final names = <String>[];
                      for (final entry in item.quantities.entries) {
                        final p = controller.findProductById(entry.key);
                        if (p != null) {
                          estTotal += p.sellPrice * entry.value;
                          names.add('${p.name} ×${entry.value}');
                        }
                      }
                      final title = item.label.trim().isNotEmpty
                          ? item.label.trim()
                          : '${strings.holdSaleTitle} • ${formatDateTime(item.createdAt)}';
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          title: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${strings.unitsShort(item.totalUnits)} • ${formatMoney(estTotal, currency)}'
                            '${names.isNotEmpty ? '\n${names.take(2).join(', ')}${names.length > 2 ? '…' : ''}' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FilledButton.tonal(
                                onPressed: () async {
                                  await controller.resumeHeldSale(item.id);
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                                child: Text(strings.resumeSaleAction),
                              ),
                              IconButton(
                                onPressed: () =>
                                    controller.deleteHeldSale(item.id),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
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

class _AddProductToCheckoutSheet extends StatefulWidget {
  const _AddProductToCheckoutSheet({required this.controller});

  final ShopController controller;

  @override
  State<_AddProductToCheckoutSheet> createState() =>
      _AddProductToCheckoutSheetState();
}

class _AddProductToCheckoutSheetState extends State<_AddProductToCheckoutSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll('×', 'x')
        .replaceAll('х', 'x')
        .replaceAll('*', 'x')
        .replaceAll(',', '.');
  }


  List<Product> _filteredProducts() {
    final normQuery = _normalize(_query.trim());
    final tokens = normQuery
        .split(RegExp(r'\\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final matches = widget.controller.products.where((product) {
      if (tokens.isEmpty) return true;
      return InputNormalizer.matchesProductSearch(product, _query);
    }).toList();

    matches.sort((a, b) {
      final aInStock = a.stock > 0 ? 1 : 0;
      final bInStock = b.stock > 0 ? 1 : 0;
      if (aInStock != bInStock) return bInStock.compareTo(aInStock);
      if (tokens.isNotEmpty) {
        final aName = _normalize(a.name);
        final bName = _normalize(b.name);
        final aStarts = aName.startsWith(normQuery) ? 1 : 0;
        final bStarts = bName.startsWith(normQuery) ? 1 : 0;
        if (aStarts != bStarts) return bStarts.compareTo(aStarts);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return matches;
  }

  void _addOne(Product product) {
    final strings = widget.controller.strings;
    final ok = widget.controller.addToCart(product.id);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            product.stock <= 0
                ? strings.outOfStockMsg(product.name)
                : strings.onlyLeftMsg(product.stock),
          ),
        ),
      );
    }
  }

  void _handleSubmitted(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return;
    final product = widget.controller.findProductBySku(code);
    if (product != null) {
      _addOne(product);
      setState(() {
        _searchController.clear();
        _query = '';
      });
    }
  }

  Future<void> _openScanner() async {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.barcodeScan);
    final strings = widget.controller.strings;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BarcodeScannerScreen(
          strings: strings,
          onContinuousScan: (code) {
            final product = widget.controller.findProductBySku(code);
            if (product == null) {
              return ScanBatchFeedback(
                found: false,
                message: strings.skuNotFoundMsg(code.trim()),
              );
            }
            final allowNegative = widget.controller.canSellNegativeStock;
            if (!allowNegative && product.stock <= 0) {
              return ScanBatchFeedback(
                found: false,
                message: strings.outOfStockMsg(product.name),
              );
            }
            final existing = widget.controller.cartQuantityFor(product.id);
            if (!allowNegative && existing + 1 > product.stock) {
              return ScanBatchFeedback(
                found: false,
                message: strings.onlyLeftMsg(product.stock),
              );
            }
            widget.controller.addToCart(product.id);
            return ScanBatchFeedback(
              found: true,
              message: strings.scannedAddedToCartMsg(
                1,
                product.name,
                existing + 1,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _createNewProduct() async {
    final created = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductFormSheet(
        controller: widget.controller,
        initialName: _query.trim().isEmpty ? null : _query.trim(),
        initialStock: 10,
      ),
    );
    if (created != null && mounted) {
      widget.controller.addToCart(created.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.88;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;
        final items = _filteredProducts();
        final isCashier = widget.controller.cashierMode;

        return SizedBox(
          height: sheetHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.addProductToReceiptBtn,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isCashier)
                      IconButton.filledTonal(
                        tooltip: strings.addNewGood,
                        onPressed: _createNewProduct,
                        icon: const Icon(Icons.add, size: 20),
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(strings.doneAction),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: (v) => setState(() => _query = v),
                        onSubmitted: _handleSubmitted,
                        decoration: InputDecoration(
                          hintText: strings.searchPosHint,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
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
                      onPressed: _openScanner,
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(strings.noMatchingProducts),
                                if (!isCashier) ...[
                                  const SizedBox(height: 10),
                                  FilledButton.tonalIcon(
                                    onPressed: _createNewProduct,
                                    icon: const Icon(Icons.add),
                                    label: Text(strings.addNewGood),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, index) {
                            final product = items[index];
                            final inCart =
                                widget.controller.cartQuantityFor(product.id);
                            final canAdd = widget.controller.canSellNegativeStock ||
                                (product.stock > 0 && inCart < product.stock);
                            return Card(
                              margin: EdgeInsets.zero,
                              color: inCart > 0
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.25)
                                  : null,
                              child: ListTile(
                                onTap: canAdd ? () => _addOne(product) : null,
                                title: Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${formatMoney(product.sellPrice, currency)}  •  '
                                  '${strings.stockCountLabel(product.stock)}'
                                  '${inCart > 0 ? '  •  ${strings.inCartLabel(inCart)}' : ''}',
                                ),
                                trailing: inCart > 0
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () => widget.controller
                                                .setCartQuantity(
                                              product.id,
                                              inCart - 1,
                                            ),
                                            icon: const Icon(
                                              Icons.remove_circle_outline,
                                            ),
                                          ),
                                          InkWell(
                                            borderRadius: BorderRadius.circular(8),
                                            onTap: () async {
                                              final messenger = ScaffoldMessenger.of(context);
                                              final entered = await showDialog<double>(
                                                context: context,
                                                builder: (_) => _QuantityInputDialog(
                                                  strings: strings,
                                                  currency: currency,
                                                  title: product.name,
                                                  label: strings.stockQtyRequired,
                                                  helper: strings.stockCountLabel(product.stock),
                                                  initialValue: inCart,
                                                  cancelLabel: strings.cancel,
                                                  confirmLabel: strings.applyAction,
                                                ),
                                              );
                                              if (entered == null || !mounted) return;
                                              if (!widget.controller.canSellNegativeStock && entered > product.stock) {
                                                messenger.showSnackBar(
                                                  SnackBar(content: Text(strings.onlyLeftMsg(product.stock))),
                                                );
                                              }
                                              widget.controller.setCartQuantity(product.id, entered);
                                            },
                                            child: Container(
                                              constraints: const BoxConstraints(minWidth: 34),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Theme.of(context).colorScheme.outlineVariant,
                                                ),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                formatQty(inCart),
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: canAdd
                                                ? () => _addOne(product)
                                                : null,
                                            icon: const Icon(
                                              Icons.add_circle_outline,
                                            ),
                                          ),
                                        ],
                                      )
                                    : (product.stock <= 0
                                        ? Text(
                                            strings.outShort,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error,
                                                ),
                                          )
                                        : null),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EditCustomerRecommendationDialog extends StatefulWidget {
  const _EditCustomerRecommendationDialog({
    required this.strings,
    required this.initialName,
    required this.initialPhone,
  });

  final AppStrings strings;
  final String initialName;
  final String initialPhone;

  @override
  State<_EditCustomerRecommendationDialog> createState() =>
      _EditCustomerRecommendationDialogState();
}

class _EditCustomerRecommendationDialogState
    extends State<_EditCustomerRecommendationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Text(strings.editCustomerTitle),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: strings.customerNameOptional,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? strings.enterCustomerName
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: strings.shopPhoneLabel,
                  prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(strings.saveChanges),
        ),
      ],
    );
  }
}

Future<void> _showCustomPosItemDialog(
  BuildContext context,
  ShopController controller,
) async {
  final strings = controller.strings;
  final currency = controller.currency;
  final priceCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final nameCtrl = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(strings.customPosItemTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: priceCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onTap: () => selectAllText(priceCtrl),
              decoration: InputDecoration(
                labelText: strings.sellPriceRequired,
                suffixText: currency.symbol,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onTap: () => selectAllText(qtyCtrl),
              decoration: InputDecoration(
                labelText: strings.stockQtyRequired,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.of(dialogCtx).pop(true),
              decoration: InputDecoration(
                labelText: strings.customPosItemNameHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          child: Text(strings.addToReceiptAction),
        ),
      ],
    ),
  );
  final price = parseQty(priceCtrl.text) ?? 0.0;
  final qty = parseQty(qtyCtrl.text) ?? 1.0;
  final name = nameCtrl.text;
  priceCtrl.dispose();
  qtyCtrl.dispose();
  nameCtrl.dispose();
  if (confirmed == true && price > 0 && qty > 0) {
    controller.addCustomCartItem(price: price, name: name, quantity: qty);
  }
}
