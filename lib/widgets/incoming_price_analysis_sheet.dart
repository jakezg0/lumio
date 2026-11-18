import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';

enum _PriceTrendFilter { all, up, down }

class IncomingPriceAnalysisSheet extends StatefulWidget {
  const IncomingPriceAnalysisSheet({
    super.key,
    required this.controller,
    required this.initialFilter,
  });

  final ShopController controller;
  final SalesDateFilter initialFilter;

  @override
  State<IncomingPriceAnalysisSheet> createState() =>
      _IncomingPriceAnalysisSheetState();
}

class _IncomingPriceAnalysisSheetState
    extends State<IncomingPriceAnalysisSheet> {
  late SalesDateFilter _dateFilter;
  _PriceTrendFilter _trendFilter = _PriceTrendFilter.all;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _dateFilter = widget.initialFilter;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _filterLabel(AppStrings strings, SalesDateFilter filter) {
    switch (filter) {
      case SalesDateFilter.today:
        return strings.filterToday;
      case SalesDateFilter.last7Days:
        return strings.filter7Days;
      case SalesDateFilter.all:
        return strings.filterAll;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;
        final allItems = widget.controller.incomingPriceAnalytics(
          filter: _dateFilter,
        );

        final totalSpend =
            allItems.fold(0.0, (sum, item) => sum + item.totalSpend);
        final upCount = allItems.where((i) => i.isPriceUp).length;
        final downCount = allItems.where((i) => i.isPriceDown).length;

        final q = _query.trim().toLowerCase();
        final items = allItems.where((item) {
          if (_trendFilter == _PriceTrendFilter.up && !item.isPriceUp) {
            return false;
          }
          if (_trendFilter == _PriceTrendFilter.down && !item.isPriceDown) {
            return false;
          }
          if (q.isEmpty) return true;
          final matchesName = item.productName.toLowerCase().contains(q);
          final matchesSupplier = item.entries.any(
            (e) => e.supplierName.toLowerCase().contains(q),
          );
          return matchesName || matchesSupplier;
        }).toList();

        final bottomInset = MediaQuery.of(context).viewInsets.bottom;

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      strings.incomingPricesTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    formatMoney(totalSpend, currency),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<SalesDateFilter>(
                segments: [
                  for (final option in SalesDateFilter.values)
                    ButtonSegment(
                      value: option,
                      label: Text(_filterLabel(strings, option)),
                    ),
                ],
                selected: {_dateFilter},
                onSelectionChanged: (selection) {
                  setState(() => _dateFilter = selection.first);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: strings.searchGoodsHint,
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
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('${strings.allCategory} (${allItems.length})'),
                    selected: _trendFilter == _PriceTrendFilter.all,
                    onSelected: (_) =>
                        setState(() => _trendFilter = _PriceTrendFilter.all),
                  ),
                  ChoiceChip(
                    label: Text('${strings.priceUpFilter} ($upCount)'),
                    selected: _trendFilter == _PriceTrendFilter.up,
                    onSelected: (_) =>
                        setState(() => _trendFilter = _PriceTrendFilter.up),
                  ),
                  ChoiceChip(
                    label: Text('${strings.priceDownFilter} ($downCount)'),
                    selected: _trendFilter == _PriceTrendFilter.down,
                    onSelected: (_) =>
                        setState(() => _trendFilter = _PriceTrendFilter.down),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(strings.noIncomingPricesMsg)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final margin = item.marginPercentAtLatest;
                      final Color? badgeColor;
                      final Color? textColor;
                      final String deltaText;

                      if (item.isPriceUp) {
                        badgeColor =
                            Theme.of(context).colorScheme.errorContainer;
                        textColor = Theme.of(context).colorScheme.error;
                        deltaText =
                            '↑ +${formatMoney(item.priceDelta, currency)} (+${item.priceDeltaPercent.toStringAsFixed(1)}%)';
                      } else if (item.isPriceDown) {
                        badgeColor = Colors.green.shade100;
                        textColor = Colors.green.shade800;
                        deltaText =
                            '↓ ${formatMoney(item.priceDelta, currency)} (${item.priceDeltaPercent.toStringAsFixed(1)}%)';
                      } else {
                        badgeColor = null;
                        textColor = null;
                        deltaText = '';
                      }

                      return Card(
                        margin: EdgeInsets.zero,
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            12,
                            0,
                            12,
                            12,
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.productName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (deltaText.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeColor,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    deltaText,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: textColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '${strings.latestCostLabel}: ${formatMoney(item.latestCost, currency)} • '
                            '${strings.avgCostLabel}: ${formatMoney(item.avgCost, currency)}\n'
                            '${strings.unitsShort(item.totalUnits)} • '
                            '${strings.totalSpendLabel}: ${formatMoney(item.totalSpend, currency)}'
                            '${margin != null ? ' • ${strings.marginShort}: ${margin.toStringAsFixed(0)}%' : ''}',
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${strings.minMaxCostLabel}: ${formatMoney(item.minCost, currency)} / ${formatMoney(item.maxCost, currency)}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  if (item.currentSellPrice != null)
                                    Text(
                                      '${strings.sellShort}: ${formatMoney(item.currentSellPrice!, currency)}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            const Divider(height: 8),
                            for (final entry in item.entries)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${formatDateTime(entry.createdAt)}'
                                        '${entry.supplierName.isNotEmpty ? ' • ${entry.supplierName}' : ''}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                    Text(
                                      '${entry.quantity} × ${formatMoney(entry.unitCost, currency)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
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
    },
  );
}
}
