import 'package:flutter/material.dart';

import '../services/inventory_storage.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';

class FeatureUsageSheet extends StatefulWidget {
  const FeatureUsageSheet({
    super.key,
    required this.controller,
  });

  final ShopController controller;

  @override
  State<FeatureUsageSheet> createState() => _FeatureUsageSheetState();
}

enum _UsageFilter { all, used, unused }

class _FeatureMeta {
  const _FeatureMeta({
    required this.key,
    required this.group,
    required this.icon,
  });

  final String key;
  final String group;
  final IconData icon;
}

class _FeatureUsageSheetState extends State<FeatureUsageSheet> {
  _UsageFilter _filter = _UsageFilter.all;

  static const List<_FeatureMeta> _catalog = [
    _FeatureMeta(
      key: FeatureUsageKeys.tabGoods,
      group: 'tabs',
      icon: Icons.inventory_2_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.tabSell,
      group: 'tabs',
      icon: Icons.point_of_sale_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.tabSales,
      group: 'tabs',
      icon: Icons.receipt_long_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.tabExpenses,
      group: 'tabs',
      icon: Icons.account_balance_wallet_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.barcodeScan,
      group: 'goods',
      icon: Icons.qr_code_scanner,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.barcodeLabel,
      group: 'goods',
      icon: Icons.qr_code_2,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.stockIn,
      group: 'goods',
      icon: Icons.local_shipping_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.stocktake,
      group: 'goods',
      icon: Icons.fact_check_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.productAdd,
      group: 'goods',
      icon: Icons.add_box_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.productEdit,
      group: 'goods',
      icon: Icons.edit_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.changeHistory,
      group: 'goods',
      icon: Icons.history,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.dailyAdvice,
      group: 'goods',
      icon: Icons.tips_and_updates_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.stockValue,
      group: 'goods',
      icon: Icons.account_balance_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.duplicateCheck,
      group: 'goods',
      icon: Icons.copy_all_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.saleComplete,
      group: 'pos',
      icon: Icons.check_circle_outline,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.holdSale,
      group: 'pos',
      icon: Icons.pause_circle_outline,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.wholesaleMode,
      group: 'pos',
      icon: Icons.storefront_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.returnExchange,
      group: 'sales',
      icon: Icons.assignment_return_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.debtors,
      group: 'sales',
      icon: Icons.people_outline,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.customers,
      group: 'sales',
      icon: Icons.contacts_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.analytics,
      group: 'sales',
      icon: Icons.bar_chart_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.invoicesHistory,
      group: 'sales',
      icon: Icons.description_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.defectReport,
      group: 'sales',
      icon: Icons.report_problem_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.expenseAdd,
      group: 'expenses',
      icon: Icons.remove_circle_outline,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.incomingPrices,
      group: 'expenses',
      icon: Icons.trending_up,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.googleSheets,
      group: 'settings',
      icon: Icons.table_chart_outlined,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.backupExport,
      group: 'settings',
      icon: Icons.import_export,
    ),
    _FeatureMeta(
      key: FeatureUsageKeys.archiveTrash,
      group: 'settings',
      icon: Icons.archive_outlined,
    ),
  ];

  Future<void> _confirmReset() async {
    final strings = widget.controller.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.featureUsageResetTitle),
        content: Text(strings.featureUsageResetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.resetAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.controller.clearFeatureUsage();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.featureUsageResetDoneMsg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.88;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final strings = widget.controller.strings;
        final usageMap = widget.controller.featureUsage;

        final entries = <({_FeatureMeta meta, FeatureUsageStat stat})>[
          for (final meta in _catalog)
            (
              meta: meta,
              stat: usageMap[meta.key] ?? const FeatureUsageStat(count: 0),
            ),
        ];

        entries.sort((a, b) {
          final cmp = b.stat.count.compareTo(a.stat.count);
          if (cmp != 0) return cmp;
          final aTime = a.stat.lastUsedAt;
          final bTime = b.stat.lastUsedAt;
          if (aTime != null && bTime != null) {
            return bTime.compareTo(aTime);
          }
          if (bTime != null) return 1;
          if (aTime != null) return -1;
          return 0;
        });

        final totalTaps =
            entries.fold<int>(0, (sum, e) => sum + e.stat.count);
        final usedCount = entries.where((e) => e.stat.count > 0).length;
        final unusedCount = entries.length - usedCount;
        final maxCount =
            entries.isEmpty ? 0 : entries.first.stat.count;

        final visible = entries.where((e) {
          switch (_filter) {
            case _UsageFilter.all:
              return true;
            case _UsageFilter.used:
              return e.stat.count > 0;
            case _UsageFilter.unused:
              return e.stat.count == 0;
          }
        }).toList();

        return SizedBox(
          height: sheetHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.featureUsageTitle,
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (totalTaps > 0)
                      IconButton(
                        tooltip: strings.resetAction,
                        onPressed: _confirmReset,
                        icon: const Icon(Icons.restart_alt),
                      ),
                    IconButton(
                      tooltip: strings.close,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryMetric(
                        label: strings.featureUsageTotalLabel,
                        value: '$totalTaps',
                        color: theme.colorScheme.primaryContainer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryMetric(
                        label: strings.featureUsageUsedLabel,
                        value: '$usedCount / ${entries.length}',
                        color: theme.colorScheme.secondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryMetric(
                        label: strings.featureUsageUnusedLabel,
                        value: '$unusedCount',
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SegmentedButton<_UsageFilter>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: _UsageFilter.all,
                      label: Text(
                        '${strings.featureUsageFilterAll} (${entries.length})',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ButtonSegment(
                      value: _UsageFilter.used,
                      label: Text(
                        '${strings.featureUsageFilterUsed} ($usedCount)',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ButtonSegment(
                      value: _UsageFilter.unused,
                      label: Text(
                        '${strings.featureUsageFilterUnused} ($unusedCount)',
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
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    strings.featureUsageHintNote,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            strings.featureUsageEmptyFilterMsg,
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      : ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, index) {
                            final item = visible[index];
                            final count = item.stat.count;
                            final isUsed = count > 0;
                            final ratio = (maxCount > 0 && isUsed)
                                ? (count / maxCount).clamp(0.05, 1.0)
                                : 0.0;
                            final sharePct = (totalTaps > 0 && isUsed)
                                ? ((count / totalTaps) * 100).round()
                                : 0;

                            return Card(
                              margin: EdgeInsets.zero,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          item.meta.icon,
                                          size: 20,
                                          color: isUsed
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme
                                                  .onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                strings.featureUsageName(
                                                  item.meta.key,
                                                ),
                                                style: theme
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(
                                                  fontWeight: isUsed
                                                      ? FontWeight.w600
                                                      : FontWeight.w400,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${strings.featureUsageGroupLabel(item.meta.group)} • '
                                                '${item.stat.lastUsedAt != null ? strings.featureUsageLastUsed(formatDateTime(item.stat.lastUsedAt!)) : strings.featureUsageNeverUsed}',
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isUsed
                                                ? theme.colorScheme
                                                    .primaryContainer
                                                : theme.colorScheme
                                                    .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            isUsed && sharePct > 0
                                                ? '$count ($sharePct%)'
                                                : '$count',
                                            style: theme
                                                .textTheme.labelMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: isUsed
                                                  ? theme.colorScheme
                                                      .onPrimaryContainer
                                                  : theme.colorScheme
                                                      .onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isUsed) ...[
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: ratio,
                                          minHeight: 5,
                                          backgroundColor: theme.colorScheme
                                              .surfaceContainerHighest,
                                        ),
                                      ),
                                    ],
                                  ],
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
      },
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
