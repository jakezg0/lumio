import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';

enum _AnalyticsTab { top, time, season, oos }

class AnalyticsSheet extends StatefulWidget {
  const AnalyticsSheet({
    super.key,
    required this.controller,
    required this.filter,
  });

  final ShopController controller;
  final SalesDateFilter filter;

  @override
  State<AnalyticsSheet> createState() => _AnalyticsSheetState();
}

class _AnalyticsSheetState extends State<AnalyticsSheet> {
  _AnalyticsTab _tab = _AnalyticsTab.top;
  late SalesDateFilter _filter;
  int? _selectedYear;

  @override
  void initState() {
    super.initState();
    _filter = widget.filter;
  }

  String _formatHourRange(int hour) {
    final start = hour.toString().padLeft(2, '0');
    final end = ((hour + 1) % 24).toString().padLeft(2, '0');
    return '$start:00–$end:00';
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
    final theme = Theme.of(context);
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final hideProfit = widget.controller.cashierMode;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.86,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.analyticsBtn,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: strings.close,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_AnalyticsTab>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _AnalyticsTab.top,
                    label: Text(
                      strings.analyticsTopTab,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  ButtonSegment(
                    value: _AnalyticsTab.time,
                    label: Text(
                      strings.analyticsTimeTab,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  ButtonSegment(
                    value: _AnalyticsTab.season,
                    label: Text(
                      strings.analyticsSeasonTab,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  ButtonSegment(
                    value: _AnalyticsTab.oos,
                    label: Text(
                      strings.analyticsOosTab,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (sel) => setState(() => _tab = sel.first),
              ),
            ),
            if (_tab == _AnalyticsTab.top || _tab == _AnalyticsTab.time) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final option in SalesDateFilter.values)
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(_filterLabel(strings, option)),
                      selected: _filter == option,
                      onSelected: (_) => setState(() => _filter = option),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: switch (_tab) {
                  _AnalyticsTab.top => _buildTopTab(
                      context,
                      strings: strings,
                      currency: currency,
                      hideProfit: hideProfit,
                    ),
                  _AnalyticsTab.time => _buildTimeTab(
                      context,
                      strings: strings,
                      currency: currency,
                      hideProfit: hideProfit,
                    ),
                  _AnalyticsTab.season => _buildSeasonTab(
                      context,
                      strings: strings,
                      currency: currency,
                      hideProfit: hideProfit,
                    ),
                  _AnalyticsTab.oos => _buildOutOfStockTab(
                      context,
                      strings: strings,
                      currency: currency,
                      hideProfit: hideProfit,
                    ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopTab(
    BuildContext context, {
    required AppStrings strings,
    required AppCurrency currency,
    required bool hideProfit,
  }) {
    final theme = Theme.of(context);
    final topProducts = widget.controller.topSellingProducts(_filter);
    final slowMovers = widget.controller.slowMovingProducts(_filter);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.topSellingHeader,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        if (topProducts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(strings.noAnalyticsData),
          )
        else
          for (final stat in topProducts.take(15))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(stat.productName),
              subtitle: Text(
                hideProfit
                    ? '${strings.unitsShort(stat.unitsSold)} • ${formatMoney(stat.revenue, currency)}'
                    : '${strings.unitsShort(stat.unitsSold)} • ${formatMoney(stat.revenue, currency)} • ${strings.profitLabel}: ${formatMoney(stat.profit, currency)}',
              ),
            ),
        if (slowMovers.isNotEmpty) ...[
          const Divider(height: 20),
          Text(
            strings.slowMoversHeader,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          for (final product in slowMovers.take(15))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(product.name),
              subtitle: Text(
                '${product.category} • ${strings.stockCountLabel(product.stock)}',
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildTimeTab(
    BuildContext context, {
    required AppStrings strings,
    required AppCurrency currency,
    required bool hideProfit,
  }) {
    final theme = Theme.of(context);
    final weekdays = widget.controller.salesByWeekday(_filter);
    final hours = widget.controller.salesByHour(_filter);
    final hasAnySales = weekdays.any((w) => w.ordersCount > 0);

    if (!hasAnySales) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(strings.noAnalyticsData)),
      );
    }

    final peakWeekday = weekdays.reduce(
      (a, b) => b.revenue > a.revenue ? b : a,
    );
    final peakHour = hours.reduce(
      (a, b) => b.revenue > a.revenue ? b : a,
    );
    final maxWeekdayRev = weekdays.fold(
      0.0,
      (maxV, item) => item.revenue > maxV ? item.revenue : maxV,
    );
    final maxHourRev = hours.fold(
      0.0,
      (maxV, item) => item.revenue > maxV ? item.revenue : maxV,
    );
    final activeHours = hours.where((h) => h.ordersCount > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _HighlightBox(
                title: strings.peakWeekdayLabel,
                headline: strings.weekdayFull(peakWeekday.key),
                subtitle:
                    '${strings.ordersShort(peakWeekday.ordersCount)} • ${formatMoney(peakWeekday.revenue, currency)}',
                color: theme.colorScheme.primaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HighlightBox(
                title: strings.peakHourLabel,
                headline: _formatHourRange(peakHour.key),
                subtitle:
                    '${strings.ordersShort(peakHour.ordersCount)} • ${formatMoney(peakHour.revenue, currency)}',
                color: theme.colorScheme.secondaryContainer,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          strings.salesByWeekdayHeader,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (final w in weekdays)
          _BarStatRow(
            label: strings.weekdayShort(w.key),
            ratio: maxWeekdayRev > 0 ? (w.revenue / maxWeekdayRev) : 0.0,
            isPeak: w.key == peakWeekday.key && w.ordersCount > 0,
            valueText: formatMoney(w.revenue, currency),
            metaText: hideProfit
                ? '${strings.ordersShort(w.ordersCount)} • ${strings.unitsShort(w.unitsSold)}'
                : '${strings.ordersShort(w.ordersCount)} • ${strings.profitLabel}: ${formatMoney(w.profit, currency)}',
          ),
        const Divider(height: 24),
        Text(
          strings.salesByHourHeader,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (final h in activeHours)
          _BarStatRow(
            label: _formatHourRange(h.key),
            labelWidth: 88,
            ratio: maxHourRev > 0 ? (h.revenue / maxHourRev) : 0.0,
            isPeak: h.key == peakHour.key && h.ordersCount > 0,
            valueText: formatMoney(h.revenue, currency),
            metaText: hideProfit
                ? '${strings.ordersShort(h.ordersCount)} • ${strings.unitsShort(h.unitsSold)}'
                : '${strings.ordersShort(h.ordersCount)} • ${strings.profitLabel}: ${formatMoney(h.profit, currency)}',
          ),
      ],
    );
  }

  Widget _buildSeasonTab(
    BuildContext context, {
    required AppStrings strings,
    required AppCurrency currency,
    required bool hideProfit,
  }) {
    final theme = Theme.of(context);
    final years = widget.controller.salesYears;
    if (_selectedYear != null && !years.contains(_selectedYear)) {
      _selectedYear = null;
    }
    final months = widget.controller.salesByMonth(year: _selectedYear);
    final activeMonths = months.where((m) => m.ordersCount > 0).toList();

    if (activeMonths.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(strings.noAnalyticsData)),
      );
    }

    final peakMonth = activeMonths.reduce(
      (a, b) => b.revenue > a.revenue ? b : a,
    );
    final totalRevenue = activeMonths.fold(0.0, (sum, m) => sum + m.revenue);
    final avgMonthlyRevenue = totalRevenue / activeMonths.length;
    final maxMonthRev = peakMonth.revenue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (years.isNotEmpty) ...[
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(strings.allYearsLabel),
                    selected: _selectedYear == null,
                    onSelected: (_) => setState(() => _selectedYear = null),
                  ),
                ),
                for (final y in years)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('$y'),
                      selected: _selectedYear == y,
                      onSelected: (_) => setState(() => _selectedYear = y),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: _HighlightBox(
                title: strings.peakMonthLabel,
                headline: strings.monthFull(peakMonth.key),
                subtitle:
                    '${strings.ordersShort(peakMonth.ordersCount)} • ${formatMoney(peakMonth.revenue, currency)}',
                color: theme.colorScheme.primaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HighlightBox(
                title: strings.avgMonthLabel,
                headline: formatMoney(avgMonthlyRevenue, currency),
                subtitle: '${activeMonths.length} / 12',
                color: theme.colorScheme.tertiaryContainer,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          strings.salesByMonthHeader,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (final m in months)
          _BarStatRow(
            label: strings.monthShort(m.key),
            ratio: maxMonthRev > 0 ? (m.revenue / maxMonthRev) : 0.0,
            isPeak: m.key == peakMonth.key && m.ordersCount > 0,
            valueText: formatMoney(m.revenue, currency),
            metaText: m.ordersCount == 0
                ? '—'
                : (hideProfit
                    ? '${strings.ordersShort(m.ordersCount)} • ${strings.unitsShort(m.unitsSold)}'
                    : '${strings.ordersShort(m.ordersCount)} • ${strings.profitLabel}: ${formatMoney(m.profit, currency)}'),
          ),
      ],
    );
  }

  Widget _buildOutOfStockTab(
    BuildContext context, {
    required AppStrings strings,
    required AppCurrency currency,
    required bool hideProfit,
  }) {
    final theme = Theme.of(context);
    final items = widget.controller.outOfStockAnalytics();

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(strings.noOutOfStockMsg)),
      );
    }

    final currentlyOut = items.where((e) => e.product.isOutOfStock).toList();
    final maxCurrentDays = currentlyOut.fold(
      0,
      (maxV, e) => e.currentDays > maxV ? e.currentDays : maxV,
    );
    final totalLostRev = currentlyOut.fold(
      0.0,
      (sum, e) => sum + e.estimatedLostRevenue,
    );
    final totalLostProfit = currentlyOut.fold(
      0.0,
      (sum, e) => sum + e.estimatedLostProfit,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _HighlightBox(
                title: strings.outOfStockNowLabel,
                headline: '${currentlyOut.length}',
                subtitle: maxCurrentDays > 0
                    ? 'max ${strings.daysShort(maxCurrentDays)}'
                    : '0',
                color: theme.colorScheme.errorContainer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HighlightBox(
                title: strings.estimatedLostRevLabel,
                headline: formatMoney(totalLostRev, currency),
                subtitle: hideProfit
                    ? strings.productsLabel
                    : '${strings.profitLabel}: ${formatMoney(totalLostProfit, currency)}',
                color: theme.colorScheme.secondaryContainer,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '${strings.outOfStockHeader} (${items.length})',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (final stat in items.take(40))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              title: Text(
                stat.product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stat.product.isOutOfStock
                        ? '${stat.product.category} • ${strings.daysShort(stat.currentDays)} (${strings.oosTotalIdleShort(stat.totalDays)})'
                        : '${stat.product.category} • ${strings.stockCountLabel(stat.product.stock)} • ${strings.oosTotalIdleShort(stat.totalDays)}',
                  ),
                  if (stat.estimatedLostRevenue > 0.009)
                    Text(
                      strings.oosEstLossLine(
                        formatMoney(stat.estimatedLostRevenue, currency),
                        hideProfit
                            ? null
                            : formatMoney(stat.estimatedLostProfit, currency),
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              trailing: (!hideProfit && stat.product.isOutOfStock)
                  ? IconButton(
                      tooltip: strings.addToStockInAction,
                      icon: const Icon(Icons.local_shipping_outlined),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final totalQty = await widget.controller
                            .addProductToStockInDraft(stat.product);
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                strings.scannedAddedToStockInMsg(
                                  1,
                                  stat.product.name,
                                  totalQty,
                                ),
                              ),
                            ),
                          );
                        }
                      },
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

class _HighlightBox extends StatelessWidget {
  const _HighlightBox({
    required this.title,
    required this.headline,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String headline;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            headline,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _BarStatRow extends StatelessWidget {
  const _BarStatRow({
    required this.label,
    required this.ratio,
    required this.isPeak,
    required this.valueText,
    required this.metaText,
    this.labelWidth = 44,
  });

  final String label;
  final double ratio;
  final bool isPeak;
  final String valueText;
  final String metaText;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = ratio.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: labelWidth,
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: isPeak ? FontWeight.bold : FontWeight.w600,
                    color: isPeak ? theme.colorScheme.primary : null,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: clamped,
                    minHeight: 10,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: isPeak
                        ? theme.colorScheme.primary
                        : theme.colorScheme.secondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                valueText,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(left: labelWidth, top: 2),
            child: Text(
              metaText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
