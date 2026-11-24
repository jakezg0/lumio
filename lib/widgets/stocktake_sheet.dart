import 'package:flutter/material.dart';

import '../models/stock_in.dart';
import '../screens/barcode_scanner_screen.dart';
import '../state/shop_controller.dart';
import 'attach_barcode_sheet.dart';
import 'currency_calculator_dialog.dart';
import 'formatters.dart';
import 'voice_search_button.dart';

class StocktakeSheet extends StatefulWidget {
  const StocktakeSheet({
    super.key,
    required this.controller,
    this.initialCategory,
  });

  final ShopController controller;
  final String? initialCategory;

  @override
  State<StocktakeSheet> createState() => _StocktakeSheetState();
}

class _StocktakeSheetState extends State<StocktakeSheet> {
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _countedIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;
  bool _countFromZero = false;
  bool _uncountedOnly = false;
  bool _discrepanciesOnly = false;
  String? _lastScannedId;
  String? _scanFeedback;
  bool _scanError = false;
  bool _filtersExpanded = false;

  @override
  void initState() {
    super.initState();
    final draft = widget.controller.stocktakeDraft;
    if (draft != null && draft.hasContent) {
      _countFromZero = draft.countFromZero;
      _countedIds.addAll(draft.countedIds);
      _selectedCategory = draft.selectedCategory ?? widget.initialCategory;
    } else {
      _selectedCategory = widget.initialCategory;
    }

    for (final p in widget.controller.products) {
      final draftCount = draft?.counts[p.id];
      final initialText = draftCount != null
          ? '$draftCount'
          : (_countFromZero && !_countedIds.contains(p.id)
              ? '0'
              : '${p.stock}');
      _controllers[p.id] = TextEditingController(text: initialText);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _persistDraft() {
    final counts = <String, double>{};
    for (final p in widget.controller.products) {
      final parsed = parseQty(_controllers[p.id]?.text ?? '');
      if (parsed == null) continue;
      if (_countedIds.contains(p.id) || (parsed - p.stock).abs() > 0.0005) {
        counts[p.id] = parsed;
      }
    }
    widget.controller.saveStocktakeDraft(
      StocktakeDraft(
        counts: counts,
        countedIds: _countedIds.toList(),
        countFromZero: _countFromZero,
        selectedCategory: _selectedCategory,
      ),
    );
  }

  Future<void> _clearDraft() async {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _countFromZero = false;
      _uncountedOnly = false;
      _discrepanciesOnly = false;
      _countedIds.clear();
      _lastScannedId = null;
      _scanFeedback = null;
      _scanError = false;
      for (final p in widget.controller.products) {
        _controllers[p.id]?.text = '${p.stock}';
      }
    });
    await widget.controller.clearStocktakeDraft();
  }

  void _toggleCountFromZero(bool enabled) {
    setState(() {
      _countFromZero = enabled;
      if (!enabled) {
        _uncountedOnly = false;
      }
      for (final p in widget.controller.products) {
        if (_countedIds.contains(p.id)) continue;
        final ctrl = _controllers[p.id];
        if (ctrl != null) {
          ctrl.text = enabled ? '0' : '${p.stock}';
        }
      }
    });
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
        _scanFeedback = msg;
        _scanError = true;
      });
      return ScanBatchFeedback(
        found: false,
        message: msg,
        notFoundCode: code.trim(),
      );
    }

    final delta = _scanIncrementFor(
      code,
      found.packQty,
      found.boxQty,
      found.packBarcode,
      found.boxBarcode,
    );
    final ctrl = _controllers.putIfAbsent(
      found.id,
      () => TextEditingController(
        text: _countFromZero ? '0' : formatQty(found.stock),
      ),
    );
    final currentActual = parseQty(ctrl.text) ??
        (_countFromZero && !_countedIds.contains(found.id) ? 0.0 : found.stock);
    final nextActual = currentActual + delta;
    ctrl.text = formatQty(nextActual);

    final msg = strings.scannedAddedToStocktakeMsg(delta, found.name, nextActual);
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      if (_selectedCategory != null && found.category != _selectedCategory) {
        _selectedCategory = null;
      }
      _countedIds.add(found.id);
      _lastScannedId = found.id;
      _scanFeedback = msg;
      _scanError = false;
    });
    _persistDraft();
    return ScanBatchFeedback(found: true, message: msg);
  }

  Future<void> _scanBarcode() async {
    final strings = widget.controller.strings;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (scanCtx) => BarcodeScannerScreen(
          strings: strings,
          onContinuousScan: _handleContinuousScan,
          onAttachBarcode: (code) async {
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

  Future<void> _apply() async {
    final counts = <String, double>{};
    for (final p in widget.controller.products) {
      if (_countFromZero && !_countedIds.contains(p.id)) continue;
      final parsed = parseQty(_controllers[p.id]?.text ?? '');
      if (parsed != null) {
        counts[p.id] = parsed;
      }
    }
    final changed = await widget.controller.applyStocktake(counts);
    if (mounted) {
      Navigator.of(context).pop(changed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final allProducts = widget.controller.products;
    final categories = widget.controller.categories;
    final categoryCounts = <String, int>{};
    var changedCount = 0;
    var uncountedInScope = 0;
    var diffCostSum = 0.0;
    var diffSellSum = 0.0;

    for (final p in allProducts) {
      final cat = p.category.trim();
      if (cat.isNotEmpty) {
        categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
      }
      if (!_countFromZero || _countedIds.contains(p.id)) {
        final actual =
            parseQty(_controllers[p.id]?.text ?? '') ?? p.stock;
        final diff = actual - p.stock;
        if (diff != 0) {
          changedCount += 1;
          diffCostSum += diff * p.costPrice;
          diffSellSum += diff * p.sellPrice;
        }
      }
      if ((_selectedCategory == null || p.category == _selectedCategory) &&
          !_countedIds.contains(p.id)) {
        uncountedInScope += 1;
      }
    }
    if (_selectedCategory != null && !categories.contains(_selectedCategory)) {
      _selectedCategory = null;
    }

    final query = _searchQuery.trim().toLowerCase();
    final products = allProducts.where((p) {
      if (_selectedCategory != null && p.category != _selectedCategory) {
        return false;
      }
      if (_uncountedOnly && _countedIds.contains(p.id)) {
        return false;
      }
      if (_discrepanciesOnly) {
        if (_countFromZero && !_countedIds.contains(p.id)) return false;
        final actual =
            parseQty(_controllers[p.id]?.text ?? '') ?? p.stock;
        if ((actual - p.stock).abs() < 0.0005) return false;
      }
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          p.category.toLowerCase().contains(query) ||
          p.sku.toLowerCase().contains(query) ||
          p.nomenclature.toLowerCase().contains(query) ||
          p.packBarcode.toLowerCase().contains(query) ||
          p.boxBarcode.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) {
        if (a.id == _lastScannedId && b.id != _lastScannedId) return -1;
        if (b.id == _lastScannedId && a.id != _lastScannedId) return 1;
        if (_countFromZero) {
          final aUncounted = !_countedIds.contains(a.id);
          final bUncounted = !_countedIds.contains(b.id);
          if (aUncounted != bUncounted) return aUncounted ? -1 : 1;
        }
        return 0;
      });

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasAnyDraft = widget.controller.hasStocktakeDraft ||
        changedCount > 0 ||
        _countFromZero ||
        _countedIds.isNotEmpty;

    final filterSummary = [
      _selectedCategory ?? strings.allCategory,
      if (_countFromZero) strings.countFromZeroLabel,
      if (changedCount > 0) strings.discrepanciesOnlyFilter(changedCount),
    ].join(' • ');

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.90,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.stocktakeBtn,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (hasAnyDraft)
                  IconButton(
                    tooltip: strings.clearDraftAction,
                    onPressed: _clearDraft,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
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
                                  TextSelection.collapsed(offset: text.length);
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
                  onPressed: _scanBarcode,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ],
            ),
            if (_scanFeedback != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _scanError
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _scanFeedback!,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _scanError
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () =>
                  setState(() => _filtersExpanded = !_filtersExpanded),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tune, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        filterSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      _filtersExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: !_filtersExpanded
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              FilterChip(
                                visualDensity: VisualDensity.compact,
                                avatar: const Icon(Icons.restart_alt, size: 18),
                                label: Text(strings.countFromZeroLabel),
                                selected: _countFromZero,
                                onSelected: _toggleCountFromZero,
                              ),
                              FilterChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  strings.discrepanciesOnlyFilter(changedCount),
                                ),
                                selected: _discrepanciesOnly,
                                onSelected: (v) => setState(() {
                                  _discrepanciesOnly = v;
                                  if (v) _uncountedOnly = false;
                                }),
                              ),
                              if (_countFromZero)
                                FilterChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    strings.uncountedOnlyFilter(
                                      uncountedInScope,
                                    ),
                                  ),
                                  selected: _uncountedOnly,
                                  onSelected: (v) => setState(() {
                                    _uncountedOnly = v;
                                    if (v) _discrepanciesOnly = false;
                                  }),
                                ),
                            ],
                          ),
                          if (categories.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 40,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(
                                        '${strings.allCategory} (${allProducts.length})',
                                      ),
                                      selected: _selectedCategory == null,
                                      onSelected: (_) {
                                        setState(
                                          () => _selectedCategory = null,
                                        );
                                        _persistDraft();
                                      },
                                    ),
                                  ),
                                  for (final cat in categories)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text(
                                          '$cat (${categoryCounts[cat] ?? 0})',
                                        ),
                                        selected: _selectedCategory == cat,
                                        onSelected: (_) {
                                          setState(
                                            () => _selectedCategory = cat,
                                          );
                                          _persistDraft();
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: products.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text(strings.noGoodsMatch)),
                    )
                  : ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final p = products[index];
                        final ctrl = _controllers[p.id]!;
                        final isCounted = _countedIds.contains(p.id);
                        final actual = parseQty(ctrl.text) ??
                            (_countFromZero && !isCounted ? 0.0 : p.stock);
                        final diff = actual - p.stock;
                        final diffLabel = diff > 0 ? '+${formatQty(diff)}' : formatQty(diff);

                        return Row(
                          children: [
                            if (_countFromZero)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: isCounted
                                    ? strings.countedBadge
                                    : strings.uncountedBadge,
                                onPressed: () {
                                  setState(() {
                                    if (!_countedIds.add(p.id)) {
                                      _countedIds.remove(p.id);
                                      ctrl.text = '0';
                                    }
                                  });
                                  _persistDraft();
                                },
                                icon: Icon(
                                  isCounted
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: isCounted
                                      ? Colors.green.shade700
                                      : theme.colorScheme.outline,
                                ),
                              ),
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
                                    _countFromZero && !isCounted
                                        ? '${strings.stockCountLabel(p.stock)} • ${strings.uncountedBadge}'
                                        : '${strings.stockCountLabel(p.stock)} (${diff == 0 ? '0' : diffLabel})',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: (_countFromZero && !isCounted) ||
                                              diff < 0
                                          ? theme.colorScheme.error
                                          : (diff > 0
                                              ? Colors.green.shade700
                                              : null),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 88,
                              child: TextField(
                                controller: ctrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onTap: () => selectAllText(ctrl),
                                onChanged: (_) {
                                  setState(() => _countedIds.add(p.id));
                                  _persistDraft();
                                },
                                decoration: InputDecoration(
                                  labelText: strings.actualStockLabel,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: strings.currencyCalculatorTitle,
                              onPressed: () async {
                                final initial = double.tryParse(
                                  ctrl.text.trim().replaceAll(',', '.'),
                                );
                                final result = await showCurrencyCalculatorDialog(
                                  context,
                                  strings: strings,
                                  targetCurrency: currency,
                                  productName: p.name,
                                  initialValue: initial,
                                  integerMode: true,
                                );
                                if (result != null && mounted) {
                                  setState(() {
                                    ctrl.text = '${result.round()}';
                                    _countedIds.add(p.id);
                                  });
                                  _persistDraft();
                                }
                              },
                              icon: const Icon(Icons.calculate_outlined, size: 20),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (changedCount > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: diffCostSum < 0
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.discrepancySummaryLabel(changedCount),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: diffCostSum < 0
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${strings.costBasisLabel}: ${diffCostSum > 0 ? '+' : ''}${formatMoney(diffCostSum, currency)}  •  '
                      '${strings.sellValueLabel}: ${diffSellSum > 0 ? '+' : ''}${formatMoney(diffSellSum, currency)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: diffCostSum < 0
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: allProducts.isEmpty ? null : _apply,
              child: Text(
                changedCount > 0
                    ? '${strings.applyStocktakeAction} ($changedCount)'
                    : strings.applyStocktakeAction,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
