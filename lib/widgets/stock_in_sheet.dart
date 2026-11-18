import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product.dart';
import '../models/stock_in.dart';
import '../screens/barcode_scanner_screen.dart';
import '../services/export_service.dart';
import '../state/shop_controller.dart';
import 'currency_calculator_dialog.dart';
import 'formatters.dart';
import 'product_form_sheet.dart';

enum _DeliverySplitMode { perUnit, byValue, byWeight }

class StockInSheet extends StatefulWidget {
  const StockInSheet({super.key, required this.controller});

  final ShopController controller;

  @override
  State<StockInSheet> createState() => _StockInSheetState();
}

class _StockInSheetState extends State<StockInSheet> {
  final _supplierController = TextEditingController();
  final _searchController = TextEditingController();
  final Map<String, int> _quantities = {};
  final Map<String, double> _unitCosts = {};
  final Map<String, double> _sellPrices = {};
  final Map<String, TextEditingController> _costControllers = {};
  final Map<String, TextEditingController> _sellControllers = {};
  final Map<String, TextEditingController> _qtyControllers = {};
  String _searchQuery = '';
  bool _recordAsExpense = true;
  String? _lastScannedId;
  String? _scanFeedback;
  bool _scanError = false;
  String? _notFoundSku;
  String _lastCalcCurrency = 'USD';
  String _lastCalcRate = '';
  bool _addedOnly = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.controller.stockInDraft;
    if (draft != null) {
      _supplierController.text = draft.supplierName;
      _recordAsExpense = draft.recordAsExpense;
    }
    for (final p in widget.controller.products) {
      final draftQty = draft?.quantities[p.id] ?? 0;
      final draftCost = draft?.unitCosts[p.id] ?? p.costPrice;
      final draftSell = draft?.sellPrices[p.id] ?? p.sellPrice;
      if (draftQty > 0) {
        _quantities[p.id] = draftQty;
      }
      _unitCosts[p.id] = draftCost;
      _sellPrices[p.id] = draftSell;
      _costControllers[p.id] = TextEditingController(
        text: draftCost > 0
            ? draftCost.toStringAsFixed(
                draftCost == draftCost.roundToDouble() ? 0 : 2,
              )
            : '',
      );
      _sellControllers[p.id] = TextEditingController(
        text: draftSell > 0
            ? draftSell.toStringAsFixed(
                draftSell == draftSell.roundToDouble() ? 0 : 2,
              )
            : '',
      );
      _qtyControllers[p.id] = TextEditingController(text: '$draftQty');
    }
  }

  @override
  void dispose() {
    _supplierController.dispose();
    _searchController.dispose();
    for (final c in _costControllers.values) {
      c.dispose();
    }
    for (final c in _sellControllers.values) {
      c.dispose();
    }
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _persistDraft() {
    final activeQty = <String, int>{};
    final activeCosts = <String, double>{};
    final activeSells = <String, double>{};
    for (final entry in _quantities.entries) {
      if (entry.value > 0) {
        activeQty[entry.key] = entry.value;
        final cost = _unitCosts[entry.key];
        if (cost != null) {
          activeCosts[entry.key] = cost;
        }
        final sell = _sellPrices[entry.key];
        if (sell != null) {
          activeSells[entry.key] = sell;
        }
      }
    }
    widget.controller.saveStockInDraft(
      StockInDraft(
        supplierName: _supplierController.text,
        recordAsExpense: _recordAsExpense,
        quantities: activeQty,
        unitCosts: activeCosts,
        sellPrices: activeSells,
      ),
    );
  }

  Future<void> _clearDraft() async {
    _supplierController.clear();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _recordAsExpense = true;
      _quantities.clear();
      _lastScannedId = null;
      _scanFeedback = null;
      _scanError = false;
      _notFoundSku = null;
      for (final p in widget.controller.products) {
        _unitCosts[p.id] = p.costPrice;
        _sellPrices[p.id] = p.sellPrice;
        _costControllers[p.id]?.text =
            p.costPrice > 0 ? p.costPrice.toStringAsFixed(0) : '';
        _sellControllers[p.id]?.text =
            p.sellPrice > 0 ? p.sellPrice.toStringAsFixed(0) : '';
        _qtyControllers[p.id]?.text = '0';
      }
    });
    await widget.controller.clearStockInDraft();
  }

  void _setQuantity(String productId, int nextQty) {
    final clean = nextQty < 0 ? 0 : nextQty;
    _quantities[productId] = clean;
    final ctrl = _qtyControllers[productId];
    if (ctrl != null && ctrl.text != '$clean') {
      ctrl.text = '$clean';
    }
    _persistDraft();
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
    final found = widget.controller.findProductBySku(code);
    if (found == null) {
      final msg = strings.skuNotFoundMsg(code.trim());
      setState(() {
        _notFoundSku = code.trim();
        _scanFeedback = msg;
        _scanError = true;
      });
      return ScanBatchFeedback(found: false, message: msg);
    }

    final delta = _scanIncrementFor(
      code,
      found.packQty,
      found.boxQty,
      found.packBarcode,
      found.boxBarcode,
    );
    final nextQty = (_quantities[found.id] ?? 0) + delta;
    final msg = strings.scannedAddedToStockInMsg(delta, found.name, nextQty);
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _notFoundSku = null;
      _setQuantity(found.id, nextQty);
      _lastScannedId = found.id;
      _scanFeedback = msg;
      _scanError = false;
    });
    return ScanBatchFeedback(found: true, message: msg);
  }

  Future<void> _scanBarcode() async {
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

  Future<void> _createProductFromStockIn({
    String? initialSku,
    String? initialName,
  }) async {
    final created = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductFormSheet(
        controller: widget.controller,
        initialSku: initialSku,
        initialName: initialName,
        initialStock: 0,
      ),
    );
    if (created == null || !mounted) return;
    final strings = widget.controller.strings;
    _unitCosts[created.id] = created.costPrice;
    _sellPrices[created.id] = created.sellPrice;
    _costControllers[created.id] = TextEditingController(
      text: created.costPrice > 0 ? created.costPrice.toStringAsFixed(0) : '',
    );
    _sellControllers[created.id] = TextEditingController(
      text: created.sellPrice > 0 ? created.sellPrice.toStringAsFixed(0) : '',
    );
    _qtyControllers[created.id] = TextEditingController(text: '1');
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _notFoundSku = null;
      _quantities[created.id] = 1;
      _lastScannedId = created.id;
      _scanFeedback = strings.scannedAddedToStockInMsg(1, created.name, 1);
      _scanError = false;
    });
    _persistDraft();
  }

  Future<void> _openCurrencyCalculator({Product? product}) async {
    final result = await showCurrencyCalculatorDialog(
      context,
      strings: widget.controller.strings,
      targetCurrency: widget.controller.currency,
      productName: product?.name,
      initialValue: product != null ? _unitCosts[product.id] : null,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (product != null) {
        _unitCosts[product.id] = result;
        final ctrl = _costControllers[product.id];
        if (ctrl != null) {
          ctrl.text = result == result.roundToDouble()
              ? result.toStringAsFixed(0)
              : result.toStringAsFixed(2);
        }
        _persistDraft();
      }
    });
  }

  Future<void> _openQtyCalculator(Product product) async {
    final current = (_quantities[product.id] ?? 0).toDouble();
    final result = await showCurrencyCalculatorDialog(
      context,
      strings: widget.controller.strings,
      targetCurrency: widget.controller.currency,
      productName: product.name,
      initialValue: current,
      integerMode: true,
    );
    if (result == null || !mounted) return;
    setState(() => _setQuantity(product.id, result.round()));
  }

  Future<void> _openSellCalculator(Product product) async {
    final result = await showCurrencyCalculatorDialog(
      context,
      strings: widget.controller.strings,
      targetCurrency: widget.controller.currency,
      productName: product.name,
      initialValue: _sellPrices[product.id] ?? product.sellPrice,
    );
    if (result == null || !mounted) return;
    setState(() {
      _sellPrices[product.id] = result;
      final ctrl = _sellControllers[product.id];
      if (ctrl != null) {
        ctrl.text = result == result.roundToDouble()
            ? result.toStringAsFixed(0)
            : result.toStringAsFixed(2);
      }
      _persistDraft();
    });
  }

  double _parseUnitWeight(String raw) {
    final cleaned = raw.trim().replaceAll(',', '.');
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(cleaned);
    if (match == null) return 0.0;
    return double.tryParse(match.group(1)!) ?? 0.0;
  }

  Future<void> _openDeliveryDistribution(
    int totalUnits,
    double totalCost,
  ) async {
    if (totalUnits <= 0) return;
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final activeProducts = widget.controller.products
        .where((p) => (_quantities[p.id] ?? 0) > 0)
        .toList();
    var totalWeight = 0.0;
    for (final p in activeProducts) {
      totalWeight += (_quantities[p.id] ?? 0) * _parseUnitWeight(p.unitWeight);
    }

    final res = await showDialog<_DeliveryDialogResult>(
      context: context,
      builder: (_) => _DistributeDeliveryDialog(
        strings: strings,
        currency: currency,
        totalUnits: totalUnits,
        totalGoodsCost: totalCost,
        totalWeight: totalWeight,
      ),
    );
    if (res == null || res.amount <= 0 || !mounted) return;

    final effectiveMode = (res.mode == _DeliverySplitMode.byWeight && totalWeight <= 0) ||
            (res.mode == _DeliverySplitMode.byValue && totalCost <= 0)
        ? _DeliverySplitMode.perUnit
        : res.mode;

    setState(() {
      for (final p in activeProducts) {
        final qty = _quantities[p.id] ?? 0;
        if (qty <= 0) continue;
        final baseCost = _unitCosts[p.id] ?? p.costPrice;
        double addPerUnit;
        switch (effectiveMode) {
          case _DeliverySplitMode.perUnit:
            addPerUnit = res.amount / totalUnits;
          case _DeliverySplitMode.byValue:
            addPerUnit = res.amount * (baseCost / totalCost);
          case _DeliverySplitMode.byWeight:
            final w = _parseUnitWeight(p.unitWeight);
            addPerUnit = w > 0 ? res.amount * (w / totalWeight) : 0.0;
        }
        final nextCost = ((baseCost + addPerUnit) * 100).roundToDouble() / 100;
        _unitCosts[p.id] = nextCost;
        final ctrl = _costControllers[p.id];
        if (ctrl != null) {
          ctrl.text = nextCost == nextCost.roundToDouble()
              ? nextCost.toStringAsFixed(0)
              : nextCost.toStringAsFixed(2);
        }
      }
      _scanFeedback = strings.deliveryAppliedMsg(
        formatMoney(res.amount, currency),
      );
      _scanError = false;
    });
    _persistDraft();
  }

  StockInRecord _buildPreviewRecord() {
    final items = <StockInItem>[];
    for (final p in widget.controller.products) {
      final qty = _quantities[p.id] ?? 0;
      if (qty > 0) {
        items.add(
          StockInItem(
            productId: p.id,
            productName: p.name,
            quantity: qty,
            unitCost: _unitCosts[p.id] ?? p.costPrice,
          ),
        );
      }
    }
    return StockInRecord(
      id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
      supplierName: _supplierController.text.trim(),
      items: items,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _shareInvoiceWhatsApp() async {
    final record = _buildPreviewRecord();
    if (record.items.isEmpty) return;
    final strings = widget.controller.strings;
    final text = ExportService.buildStockInText(
      record,
      strings,
      widget.controller.currency,
      shopName: widget.controller.shopName,
    );
    await Share.share(text, subject: strings.stockInInvoiceTitle);
  }

  Future<void> _shareInvoicePdf() async {
    final record = _buildPreviewRecord();
    if (record.items.isEmpty) return;
    final strings = widget.controller.strings;
    final path = await ExportService.saveStockInPdf(
      record,
      strings,
      widget.controller.currency,
      shopName: widget.controller.shopName,
    );
    await Share.shareXFiles([XFile(path)], subject: strings.stockInInvoiceTitle);
  }

  Future<void> _submit() async {
    final items = <StockInItem>[];
    for (final p in widget.controller.products) {
      final qty = _quantities[p.id] ?? 0;
      if (qty > 0) {
        final nextSell = _sellPrices[p.id];
        items.add(
          StockInItem(
            productId: p.id,
            productName: p.name,
            quantity: qty,
            unitCost: _unitCosts[p.id] ?? p.costPrice,
            newSellPrice: (nextSell != null &&
                    nextSell > 0 &&
                    (nextSell - p.sellPrice).abs() > 0.009)
                ? nextSell
                : null,
          ),
        );
      }
    }
    if (items.isEmpty) return;

    await widget.controller.receiveStock(
      supplierName: _supplierController.text,
      items: items,
      recordAsExpense: _recordAsExpense,
    );
    if (mounted) {
      final totalUnits = items.fold(0, (s, i) => s + i.quantity);
      Navigator.of(context).pop(totalUnits);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final allProducts = widget.controller.products;
    final recentSuppliers = widget.controller.recentSuppliers;
    final addedItemsCount =
        allProducts.where((p) => (_quantities[p.id] ?? 0) > 0).length;
    final query = _searchQuery.trim().toLowerCase();
    final products = allProducts.where((p) {
      if (_addedOnly && (_quantities[p.id] ?? 0) <= 0) return false;
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          p.sku.toLowerCase().contains(query) ||
          p.packBarcode.toLowerCase().contains(query) ||
          p.boxBarcode.toLowerCase().contains(query) ||
          p.nomenclature.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) {
        if (a.id == _lastScannedId && b.id != _lastScannedId) return -1;
        if (b.id == _lastScannedId && a.id != _lastScannedId) return 1;
        final aAdded = (_quantities[a.id] ?? 0) > 0;
        final bAdded = (_quantities[b.id] ?? 0) > 0;
        if (aAdded != bAdded) return aAdded ? -1 : 1;
        return 0;
      });
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    var totalUnits = 0;
    var totalCost = 0.0;
    for (final p in allProducts) {
      final qty = _quantities[p.id] ?? 0;
      if (qty > 0) {
        totalUnits += qty;
        totalCost += qty * (_unitCosts[p.id] ?? p.costPrice);
      }
    }

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
                  strings.stockInBtn,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (totalUnits > 0 || _supplierController.text.trim().isNotEmpty)
                IconButton(
                  tooltip: strings.clearDraftAction,
                  onPressed: _clearDraft,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              IconButton.filledTonal(
                tooltip: strings.distributeDeliveryTitle,
                onPressed: totalUnits > 0
                    ? () => _openDeliveryDistribution(totalUnits, totalCost)
                    : null,
                icon: const Icon(Icons.local_shipping_outlined),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: strings.currencyCalculatorTitle,
                onPressed: () => _openCurrencyCalculator(),
                icon: const Icon(Icons.calculate_outlined),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _supplierController,
            onChanged: (_) {
              setState(() {});
              _persistDraft();
            },
            decoration: InputDecoration(
              labelText: strings.supplierNameHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (recentSuppliers.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recentSuppliers.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, idx) {
                  final s = recentSuppliers[idx];
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(s),
                    onPressed: () {
                      _supplierController.text = s;
                      setState(() {});
                      _persistDraft();
                    },
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
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
                onPressed: _scanBarcode,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ],
          ),
          if (_scanFeedback != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _scanError
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _scanFeedback!,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _scanError
                            ? Theme.of(context).colorScheme.onErrorContainer
                            : Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  if (_scanError && _notFoundSku != null)
                    TextButton.icon(
                      onPressed: () => _createProductFromStockIn(
                        initialSku: _notFoundSku,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(strings.addProductBtn),
                    ),
                ],
              ),
            ),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            value: _recordAsExpense,
            onChanged: (v) {
              setState(() => _recordAsExpense = v ?? true);
              _persistDraft();
            },
            title: Text(strings.recordAsExpenseLabel),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (addedItemsCount > 0 || _addedOnly)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(strings.addedOnlyFilter(addedItemsCount)),
                  selected: _addedOnly,
                  onSelected: (v) => setState(() => _addedOnly = v),
                ),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: products.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          strings.noGoodsMatch,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            final raw = _searchController.text.trim();
                            final isBarcode = raw.length >= 6 &&
                                raw.runes.every((c) => c >= 48 && c <= 57);
                            _createProductFromStockIn(
                              initialSku: isBarcode ? raw : null,
                              initialName: isBarcode || raw.isEmpty ? null : raw,
                            );
                          },
                          icon: const Icon(Icons.add),
                          label: Text(strings.addNewGood),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
              shrinkWrap: true,
              itemCount: products.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final p = products[index];
                final qty = _quantities[p.id] ?? 0;
                final unitCost = _unitCosts[p.id] ?? p.costPrice;
                final costDiff = unitCost - p.costPrice;
                final costCtrl = _costControllers[p.id]!;
                final sellCtrl = _sellControllers[p.id]!;
                final qtyCtrl = _qtyControllers[p.id]!;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${strings.stockCountLabel(p.stock)} • ${strings.costShort}: ${formatMoney(p.costPrice, currency)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: qty > 0
                                    ? () => setState(
                                          () => _setQuantity(p.id, qty - 1),
                                        )
                                    : null,
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              SizedBox(
                                width: 54,
                                child: TextField(
                                  controller: qtyCtrl,
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  onTap: () => qtyCtrl.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: qtyCtrl.text.length,
                                  ),
                                  onChanged: (v) {
                                    final parsed = int.tryParse(v.trim());
                                    setState(() {
                                      _quantities[p.id] =
                                          (parsed == null || parsed < 0)
                                              ? 0
                                              : parsed;
                                    });
                                    _persistDraft();
                                  },
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(
                                  () => _setQuantity(p.id, qty + 1),
                                ),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: strings.currencyCalculatorTitle,
                                onPressed: () => _openQtyCalculator(p),
                                icon: const Icon(Icons.calculate_outlined, size: 20),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (qty > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 150,
                                child: TextField(
                                  controller: costCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  onChanged: (v) {
                                    final parsed = double.tryParse(v.trim());
                                    if (parsed != null && parsed >= 0) {
                                      setState(() => _unitCosts[p.id] = parsed);
                                      _persistDraft();
                                    }
                                  },
                                  decoration: InputDecoration(
                                    labelText: strings.unitCostLabel,
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: strings.currencyCalculatorTitle,
                                onPressed: () =>
                                    _openCurrencyCalculator(product: p),
                                icon: const Icon(Icons.calculate_outlined),
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 6),
                              if (costDiff.abs() > 0.009)
                                Text(
                                  costDiff > 0
                                      ? '↑ +${formatMoney(costDiff, currency)}'
                                      : '↓ ${formatMoney(costDiff, currency)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: costDiff > 0
                                        ? Theme.of(context).colorScheme.error
                                        : Colors.green.shade700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (qty > 0)
                        Builder(
                          builder: (context) {
                            final currentSell = _sellPrices[p.id] ?? p.sellPrice;
                            final newMargin = currentSell > 0
                                ? ((currentSell - unitCost) / currentSell) * 100
                                : 0.0;
                            final canKeepMarkup = p.costPrice > 0 &&
                                p.sellPrice > 0 &&
                                unitCost > 0 &&
                                costDiff.abs() > 0.009;
                            final suggestedSell = canKeepMarkup
                                ? (unitCost * (p.sellPrice / p.costPrice))
                                    .roundToDouble()
                                : 0.0;
                            final showKeepChip = canKeepMarkup &&
                                (currentSell - suggestedSell).abs() >= 1;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  SizedBox(
                                    width: 155,
                                    child: TextField(
                                      controller: sellCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      onChanged: (v) {
                                        final parsed = double.tryParse(v.trim());
                                        if (parsed != null && parsed >= 0) {
                                          setState(
                                            () => _sellPrices[p.id] = parsed,
                                          );
                                          _persistDraft();
                                        }
                                      },
                                      decoration: InputDecoration(
                                        labelText: strings.newSellPriceLabel,
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                        suffixIcon: IconButton(
                                          tooltip: strings.currencyCalculatorTitle,
                                          onPressed: () =>
                                              _openSellCalculator(p),
                                          icon: const Icon(
                                            Icons.calculate_outlined,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${strings.marginShort}: ${newMargin.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: newMargin < 15
                                          ? Theme.of(context).colorScheme.error
                                          : Colors.green.shade700,
                                    ),
                                  ),
                                  if (showKeepChip)
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      avatar: const Icon(
                                        Icons.trending_up,
                                        size: 16,
                                      ),
                                      label: Text(
                                        strings.keepMarkupAction(
                                          formatMoney(suggestedSell, currency),
                                        ),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _sellPrices[p.id] = suggestedSell;
                                          sellCtrl.text = suggestedSell
                                              .toStringAsFixed(0);
                                        });
                                        _persistDraft();
                                      },
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: totalUnits > 0 ? _submit : null,
            child: Text(
              totalUnits > 0
                  ? '${strings.receiveStockAction} ($totalUnits • ${formatMoney(totalCost, currency)})'
                  : strings.receiveStockAction,
            ),
          ),
          if (totalUnits > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareInvoiceWhatsApp,
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _shareInvoicePdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('PDF'),
                  ),
                ),
              ],
            ),
          ],
          ],
        ),
      ),
    );
  }
}

class _CalcResult {
  const _CalcResult({
    required this.currencyCode,
    required this.rateText,
    required this.unitCost,
  });

  final String currencyCode;
  final String rateText;
  final double unitCost;
}

class _CurrencyCostCalculatorDialog extends StatefulWidget {
  const _CurrencyCostCalculatorDialog({
    required this.strings,
    required this.targetCurrency,
    required this.initialCurrency,
    required this.initialRate,
    this.productName,
  });

  final dynamic strings;
  final dynamic targetCurrency;
  final String initialCurrency;
  final String initialRate;
  final String? productName;

  @override
  State<_CurrencyCostCalculatorDialog> createState() =>
      _CurrencyCostCalculatorDialogState();
}

class _CurrencyCostCalculatorDialogState
    extends State<_CurrencyCostCalculatorDialog> {
  late String _currencyCode;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _extraCtrl;

  static const _currencies = ['USD', 'CNY', 'RUB', 'EUR'];

  @override
  void initState() {
    super.initState();
    _currencyCode = widget.initialCurrency;
    _priceCtrl = TextEditingController();
    _rateCtrl = TextEditingController(text: widget.initialRate);
    _extraCtrl = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _rateCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  double get _calculated {
    final price =
        double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final rate =
        double.tryParse(_rateCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final extra =
        double.tryParse(_extraCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final res = price * rate + extra;
    return res < 0 ? 0 : res;
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final total = _calculated;
    return AlertDialog(
      title: Text(strings.currencyCalculatorTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.productName != null) ...[
              Text(
                widget.productName!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 6,
              children: [
                for (final code in _currencies)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(code),
                    selected: _currencyCode == code,
                    onSelected: (_) => setState(() => _currencyCode = code),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _priceCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: strings.foreignPriceLabel(_currencyCode),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: strings.exchangeRateLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _extraCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: strings.extraPerUnitLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                strings.calculatedUnitCostLabel(
                  formatMoney(total, widget.targetCurrency),
                ),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: total > 0
              ? () => Navigator.of(context).pop(
                    _CalcResult(
                      currencyCode: _currencyCode,
                      rateText: _rateCtrl.text.trim(),
                      unitCost: total,
                    ),
                  )
              : null,
          child: Text(strings.applyAction),
        ),
      ],
    );
  }
}

class _DeliveryDialogResult {
  const _DeliveryDialogResult({required this.amount, required this.mode});

  final double amount;
  final _DeliverySplitMode mode;
}

class _DistributeDeliveryDialog extends StatefulWidget {
  const _DistributeDeliveryDialog({
    required this.strings,
    required this.currency,
    required this.totalUnits,
    required this.totalGoodsCost,
    required this.totalWeight,
  });

  final dynamic strings;
  final dynamic currency;
  final int totalUnits;
  final double totalGoodsCost;
  final double totalWeight;

  @override
  State<_DistributeDeliveryDialog> createState() =>
      _DistributeDeliveryDialogState();
}

class _DistributeDeliveryDialogState extends State<_DistributeDeliveryDialog> {
  late final TextEditingController _amountCtrl;
  _DeliverySplitMode _mode = _DeliverySplitMode.perUnit;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double get _amount =>
      double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final amount = _amount;
    return AlertDialog(
      title: Text(strings.distributeDeliveryTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${strings.unitsCount(widget.totalUnits)} • ${formatMoney(widget.totalGoodsCost, widget.currency)}'
              '${widget.totalWeight > 0 ? ' • ${widget.totalWeight.toStringAsFixed(1)} kg' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: strings.deliveryTotalAmountLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(strings.splitPerUnit),
                  selected: _mode == _DeliverySplitMode.perUnit,
                  onSelected: (_) =>
                      setState(() => _mode = _DeliverySplitMode.perUnit),
                ),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(strings.splitByValue),
                  selected: _mode == _DeliverySplitMode.byValue,
                  onSelected: (_) =>
                      setState(() => _mode = _DeliverySplitMode.byValue),
                ),
                if (widget.totalWeight > 0)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(strings.splitByWeight),
                    selected: _mode == _DeliverySplitMode.byWeight,
                    onSelected: (_) =>
                        setState(() => _mode = _DeliverySplitMode.byWeight),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: amount > 0
              ? () => Navigator.of(context).pop(
                    _DeliveryDialogResult(amount: amount, mode: _mode),
                  )
              : null,
          child: Text(strings.applyAction),
        ),
      ],
    );
  }
}
