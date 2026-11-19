import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../state/shop_controller.dart';
import '../widgets/currency_calculator_dialog.dart';
import '../widgets/formatters.dart';
import '../widgets/product_form_sheet.dart';
import '../widgets/receipt_sheet.dart';
import '../widgets/settings_button.dart';
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
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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

  String _compactForSearch(String normalized) {
    return normalized.replaceAll(RegExp(r'[\s\-_/]+'), '');
  }

  List<Product> _availableProducts() {
    final normalizedQuery = _normalizeForSearch(_searchQuery.trim());
    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final matches = widget.controller.products.where((product) {
      if (_inStockOnly && product.stock <= 0) {
        return false;
      }
      if (_selectedCategory != null && product.category != _selectedCategory) {
        return false;
      }
      if (tokens.isEmpty) return true;
      final haystack = _normalizeForSearch(
        [
          product.name,
          product.category,
          product.sku,
          product.nomenclature,
          product.printName,
          product.packBarcode,
          product.boxBarcode,
        ].join(' '),
      );
      final compactHaystack = _compactForSearch(haystack);
      return tokens.every((t) {
        if (haystack.contains(t)) return true;
        final compactT = _compactForSearch(t);
        return compactT.isNotEmpty && compactHaystack.contains(compactT);
      });
    }).toList();

    final soldUnits = <String, int>{};
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
    widget.controller.addToCart(product.id, quantity: delta);
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
    widget.controller.addToCart(product.id, quantity: delta);
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
    final strings = widget.controller.strings;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BarcodeScannerScreen(
          strings: strings,
          onContinuousScan: _handleContinuousScan,
        ),
      ),
    );
  }

  Future<void> _promptCartQuantity(Product product) async {
    final strings = widget.controller.strings;
    final current = widget.controller.cartQuantityFor(product.id);
    final entered = await showDialog<int>(
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
        ),
      );
    }
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _HeldSalesSheet(controller: widget.controller),
    );
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

        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            title: Text(strings.recordSaleTitle),
            actions: [
              if (widget.controller.heldSales.isNotEmpty)
                IconButton(
                  tooltip: strings.heldSalesTitle,
                  onPressed: _openHeldSales,
                  icon: Badge(
                    label: Text('${widget.controller.heldSales.length}'),
                    child: const Icon(Icons.pause_circle_outline),
                  ),
                ),
              SettingsButton(controller: widget.controller),
              if (cartCount > 0)
                TextButton(
                  onPressed: widget.controller.clearCart,
                  child: Text(strings.clearCart),
                ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
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
                      onPressed: _scanAndAddBySku,
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                  ],
                ),
              ),
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
              if (widget.controller.products.isNotEmpty)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
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
                            onSelected: (_) =>
                                setState(() => _selectedCategory = null),
                          ),
                        ),
                        for (final category in widget.controller.categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(category),
                              selected: _selectedCategory == category,
                              onSelected: (_) =>
                                  setState(() => _selectedCategory = category),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
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

                              return Card(
                                margin: EdgeInsets.zero,
                                color: inCart > 0
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.25)
                                    : null,
                                child: ListTile(
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
                                                  '$inCart',
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
              if (cartCount > 0)
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: Row(
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
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
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
                  ),
                ),
            ],
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
  final TextEditingController _paidNowController =
      TextEditingController(text: '0');
  final TextEditingController _cashReceivedController = TextEditingController();
  final TextEditingController _primarySplitController = TextEditingController();
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  bool _splitPayment = false;
  PaymentMethod _secondaryMethod = PaymentMethod.kaspiQr;
  DateTime? _dueDate;
  String? _customerError;
  String? _phoneError;

  @override
  void dispose() {
    _customerController.dispose();
    _phoneController.dispose();
    _discountController.dispose();
    _paidNowController.dispose();
    _cashReceivedController.dispose();
    _primarySplitController.dispose();
    super.dispose();
  }

  double get _discount {
    final parsed = double.tryParse(_discountController.text.trim()) ?? 0;
    return parsed < 0 ? 0 : parsed;
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

    final total = (widget.controller.cartSubtotal - _discount)
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
      discount: _discount,
      paidAmount: _paymentMethod == PaymentMethod.postPay ? _paidNow : null,
      dueDate: _paymentMethod == PaymentMethod.postPay ? _dueDate : null,
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
        final total = (subtotal - _discount).clamp(0.0, double.infinity);
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
                Text(
                  strings.checkout,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                for (final line in lines)
                  ListTile(
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
                            helper:
                                '${strings.sellShort}: ${formatMoney(line.product.sellPrice, currency)}',
                            initialValue: line.unitPrice,
                            defaultPrice: line.product.sellPrice,
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                '${formatMoney(line.unitPrice, currency)} × ${line.quantity} = ${formatMoney(line.lineTotal, currency)}',
                                style: line.hasCustomPrice
                                    ? TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
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
                            final entered = await showDialog<int>(
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
                            if (entered == null || !mounted) return;
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
                              '${line.quantity}',
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
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _openAddProductPicker,
                    icon: const Icon(Icons.add_shopping_cart, size: 18),
                    label: Text(strings.addProductToReceiptBtn),
                  ),
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
                    if (!isPostPay)
                      FilterChip(
                        avatar: const Icon(Icons.call_split, size: 16),
                        label: Text(strings.splitPaymentLabel),
                        selected: _splitPayment,
                        onSelected: (v) {
                          setState(() {
                            _splitPayment = v;
                            if (v) {
                              if (_secondaryMethod == _paymentMethod ||
                                  _secondaryMethod == PaymentMethod.postPay) {
                                _secondaryMethod = PaymentMethod.values
                                    .firstWhere(
                                  (m) =>
                                      m != PaymentMethod.postPay &&
                                      m != _paymentMethod,
                                );
                              }
                              if (_primarySplitController.text.trim().isEmpty) {
                                _primarySplitController.text =
                                    (total / 2).round().toString();
                              }
                            }
                          });
                        },
                      ),
                  ],
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
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(name),
                              selected: _customerController.text
                                      .trim()
                                      .toLowerCase() ==
                                  name.toLowerCase(),
                              onSelected: (selected) {
                                setState(() {
                                  _customerController.text =
                                      selected ? name : '';
                                  _customerError = null;
                                  if (selected) {
                                    _syncPhoneForCustomer(name);
                                  }
                                });
                              },
                            ),
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
                TextField(
                  controller: _discountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: strings.discountAmount,
                    suffixIcon: _discount > 0
                        ? IconButton(
                            onPressed: () {
                              _discountController.text = '0';
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (subtotal > 0) ...[
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final step = total >= 1000 ? 1000 : 100;
                      final roundedDown = (total ~/ step) * step.toDouble();
                      final canRound = roundedDown > 0 &&
                          (total - roundedDown).abs() >= 1;
                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final pct in const [5, 10, 15])
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              label: Text('-$pct%'),
                              onPressed: () {
                                final disc = (subtotal * pct / 100)
                                    .roundToDouble();
                                _discountController.text =
                                    disc.toStringAsFixed(0);
                                setState(() {});
                              },
                            ),
                          if (canRound)
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(
                                Icons.auto_fix_high,
                                size: 16,
                              ),
                              label: Text(
                                strings.roundTotalAction(
                                  formatMoney(roundedDown, currency),
                                ),
                              ),
                              onPressed: () {
                                final disc = (subtotal - roundedDown)
                                    .clamp(0.0, subtotal);
                                _discountController.text =
                                    disc.toStringAsFixed(0);
                                setState(() {});
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
                if (_paymentMethod == PaymentMethod.cash) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _cashReceivedController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
                      for (final bill in const [5000, 10000, 20000])
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
  final String cancelLabel;
  final String resetLabel;
  final String confirmLabel;

  @override
  State<_PriceInputDialog> createState() => _PriceInputDialogState();
}

class _PriceInputDialogState extends State<_PriceInputDialog> {
  late final TextEditingController _ctrl;

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
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
  final int initialValue;
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
    final text = '${widget.initialValue}';
    _ctrl = TextEditingController(text: text);
    _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_ctrl.text.trim());
    if (parsed != null && parsed >= 0) {
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
      integerMode: true,
    );
    if (result != null && mounted) {
      _ctrl.text = '${result.round()}';
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
          keyboardType: TextInputType.number,
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

  String _compact(String normalized) {
    return normalized.replaceAll(RegExp(r'[\\s\\-_/]+'), '');
  }

  List<Product> _filteredProducts() {
    final normQuery = _normalize(_query.trim());
    final tokens = normQuery
        .split(RegExp(r'\\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final matches = widget.controller.products.where((product) {
      if (tokens.isEmpty) return true;
      final haystack = _normalize(
        [
          product.name,
          product.category,
          product.sku,
          product.nomenclature,
          product.printName,
          product.packBarcode,
          product.boxBarcode,
        ].join(' '),
      );
      final compactHaystack = _compact(haystack);
      return tokens.every((t) {
        if (haystack.contains(t)) return true;
        final compactT = _compact(t);
        return compactT.isNotEmpty && compactHaystack.contains(compactT);
      });
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
                      TextButton.icon(
                        onPressed: _createNewProduct,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(strings.addNewGood),
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
                                          Text(
                                            '$inCart',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
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
