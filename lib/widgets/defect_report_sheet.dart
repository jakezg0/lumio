import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_strings.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';

class DefectReportSheet extends StatefulWidget {
  const DefectReportSheet({
    super.key,
    required this.controller,
    this.initialFilter = SalesDateFilter.all,
  });

  final ShopController controller;
  final SalesDateFilter initialFilter;

  @override
  State<DefectReportSheet> createState() => _DefectReportSheetState();
}

class _DefectReportSheetState extends State<DefectReportSheet> {
  late SalesDateFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
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

  Future<void> _shareReport(
    BuildContext context,
    List<({String receiptCode, dynamic item})> entries,
    int totalUnits,
    double totalCost,
  ) async {
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final lines = <String>[
      if (widget.controller.shopName.trim().isNotEmpty)
        widget.controller.shopName.trim(),
      '${strings.defectReportTitle} (${_filterLabel(strings, _filter)})',
      '---',
      for (final e in entries)
        '• ${e.item.productName}: ${e.item.quantity} × ${formatMoney(e.item.unitCost, currency)} = ${formatMoney(e.item.lineCost, currency)} (${formatDateTime(e.item.createdAt)}, №${e.receiptCode})',
      '---',
      '${strings.unitsShort(totalUnits)} • ${strings.totalDefectCostLabel}: ${formatMoney(totalCost, currency)}',
    ];
    await Share.share(lines.join('\n'), subject: strings.defectReportTitle);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;
        final entries = widget.controller.defectWriteOffs(_filter);
        final totalUnits = entries.fold(0, (sum, e) => sum + e.item.quantity);
        final totalCost = entries.fold(0.0, (sum, e) => sum + e.item.lineCost);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.defectReportTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              SegmentedButton<SalesDateFilter>(
                showSelectedIcon: false,
                segments: [
                  for (final option in SalesDateFilter.values)
                    ButtonSegment(
                      value: option,
                      label: Text(
                        _filterLabel(strings, option),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                selected: {_filter},
                onSelectionChanged: (sel) =>
                    setState(() => _filter = sel.first),
              ),
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        strings.unitsShort(totalUnits),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        '${strings.totalDefectCostLabel}: ${formatMoney(totalCost, currency)}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text(strings.noDefectsMsg)),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final item = entry.item;
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          title: Text(
                            item.productName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${item.quantity} × ${formatMoney(item.unitCost, currency)} • ${formatDateTime(item.createdAt)} • №${entry.receiptCode}',
                          ),
                          trailing: Text(
                            formatMoney(item.lineCost, currency),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (entries.isNotEmpty) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _shareReport(
                    context,
                    entries,
                    totalUnits,
                    totalCost,
                  ),
                  icon: const Icon(Icons.share_outlined),
                  label: Text(strings.shareDefectReportBtn),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
