import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../state/shop_controller.dart';
import '../widgets/analytics_sheet.dart';
import '../widgets/currency_calculator_dialog.dart';
import '../widgets/customers_sheet.dart';
import '../widgets/debtors_sheet.dart';
import '../widgets/defect_report_sheet.dart';
import '../widgets/formatters.dart';
import '../widgets/invoices_history_sheet.dart';
import '../widgets/receipt_barcode.dart';
import '../widgets/receipt_sheet.dart';
import '../widgets/settings_button.dart';
import 'barcode_scanner_screen.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key, required this.controller});

  final ShopController controller;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  SalesDateFilter _filter = SalesDateFilter.today;
  bool _unpaidOnly = false;
  bool _returnsOnly = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
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


  void _openDebtorsSheet() {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.debtors);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DebtorsSheet(controller: widget.controller),
    );
  }

  void _openCustomersSheet() {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.customers);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CustomersSheet(controller: widget.controller),
    );
  }

  void _openAnalyticsSheet() {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.analytics);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AnalyticsSheet(
        controller: widget.controller,
        filter: _filter,
      ),
    );
  }

  void _openInvoicesHistorySheet() {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.invoicesHistory);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => InvoicesHistorySheet(
        controller: widget.controller,
        initialFilter: InvoiceHistoryFilter.all,
      ),
    );
  }

  void _openDefectReportSheet() {
    widget.controller.trackFeatureUsage(FeatureUsageKeys.defectReport);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DefectReportSheet(
        controller: widget.controller,
        initialFilter: _filter,
      ),
    );
  }

  Future<void> _showSaleDetails(Sale sale) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _SaleDetailSheet(
        controller: widget.controller,
        saleId: sale.id,
      ),
    );
    if (!mounted) return;
    if (result == 'trashed') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.strings.saleVoidedMsg)),
      );
    } else if (result == 'archived') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.strings.movedToArchiveMsg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;
        final isCashier = widget.controller.cashierMode;
        final periodSales = widget.controller.filteredSales(_filter);
        final returnsCount = periodSales.where((s) => s.hasReturn).length;
        final totalReturnsAmount = periodSales.fold(
          0.0,
          (sum, s) => sum + s.returnedMoneyTotal,
        );
        final allFilteredSales = widget.controller.filteredSales(
          _filter,
          unpaidOnly: _unpaidOnly,
          returnsOnly: _returnsOnly,
        );
        final phoneByCustomer = <String, String>{};
        for (final c in widget.controller.customers) {
          final key = c.name.trim().toLowerCase();
          if (key.isNotEmpty && c.phone.trim().isNotEmpty) {
            phoneByCustomer[key] = c.phone.trim();
          }
        }
        final q = _query.trim().toLowerCase();
        final compactQ = q.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
        final sales = q.isEmpty
            ? allFilteredSales
            : allFilteredSales.where((sale) {
                final phone =
                    phoneByCustomer[sale.customerName.trim().toLowerCase()] ?? '';
                final payLabel = sale.isSplitPayment
                    ? '${strings.paymentMethodLabel(sale.paymentMethod.name)} ${strings.paymentMethodLabel(sale.secondaryPaymentMethod!.name)}'
                    : strings.paymentMethodLabel(sale.paymentMethod.name);
                final fields = <String>[
                  sale.id,
                  sale.receiptCode,
                  sale.customerName,
                  phone,
                  sale.total.toStringAsFixed(0),
                  sale.total.toStringAsFixed(2),
                  formatMoney(sale.total, currency),
                  if (sale.remainingDebt > 0)
                    sale.remainingDebt.toStringAsFixed(0),
                  formatDateTime(sale.createdAt),
                  payLabel,
                  for (final item in sale.items) item.productName,
                ];
                for (final f in fields) {
                  final lower = f.toLowerCase();
                  if (lower.contains(q)) return true;
                  if (compactQ.isNotEmpty && lower.replaceAll(RegExp(r'[\s\-\(\)\+]'), '').contains(compactQ)) {
                    return true;
                  }
                }
                return false;
              }).toList();
        final revenue = sales.fold(0.0, (sum, s) => sum + s.total);
        final cost = sales.fold(0.0, (sum, s) => sum + s.totalCost);
        final profit = sales.fold(0.0, (sum, s) => sum + s.profit);
        final unpaidCount = widget.controller.unpaidSales.length;
        final totalDebt = widget.controller.totalUnpaidDebt;
        final breakdown = widget.controller.paymentBreakdown(_filter);

        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            title: Text(strings.salesAndProfit),
            actions: [
              IconButton(
                tooltip: strings.customersBtn,
                onPressed: _openCustomersSheet,
                icon: Badge(
                  isLabelVisible: widget.controller.customers.isNotEmpty,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  label: Text('${widget.controller.customers.length}'),
                  child: const Icon(Icons.contacts_outlined),
                ),
              ),
              SettingsButton(controller: widget.controller),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SegmentedButton<SalesDateFilter>(
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
                  onSelectionChanged: (selection) {
                    setState(() => _filter = selection.first);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChip(
                              label: Text(
                                strings.unpaidOnlyChip(
                                  unpaidCount,
                                  formatMoney(totalDebt, currency),
                                ),
                              ),
                              selected: _unpaidOnly,
                              onSelected: (selected) {
                                setState(() => _unpaidOnly = selected);
                              },
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: Text(
                                strings.returnsFilterChip(
                                  returnsCount,
                                  formatMoney(totalReturnsAmount, currency),
                                ),
                              ),
                              selected: _returnsOnly,
                              onSelected: (selected) {
                                setState(() => _returnsOnly = selected);
                              },
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(Icons.people_outline, size: 18),
                              label: Text(
                                '${strings.debtorsSummaryBtn} (${widget.controller.debtors.length})',
                              ),
                              onPressed: _openDebtorsSheet,
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(Icons.contacts_outlined, size: 18),
                              label: Text(
                                '${strings.customersBtn} (${widget.controller.customers.length})',
                              ),
                              onPressed: _openCustomersSheet,
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(Icons.bar_chart_outlined, size: 18),
                              label: Text(strings.analyticsBtn),
                              onPressed: _openAnalyticsSheet,
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                              label: Text(strings.invoiceHistoryTitle),
                              onPressed: _openInvoicesHistorySheet,
                            ),
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(Icons.report_problem_outlined, size: 18),
                              label: Text(strings.defectReportBtn),
                              onPressed: _openDefectReportSheet,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryStat(
                                label: strings.ordersLabel,
                                value: '${sales.length}',
                              ),
                            ),
                            Expanded(
                              child: _SummaryStat(
                                label: strings.revenueLabel,
                                value: formatMoney(revenue, currency),
                              ),
                            ),
                            if (!isCashier) ...[
                              Expanded(
                                child: _SummaryStat(
                                  label: strings.costLabel,
                                  value: formatMoney(cost, currency),
                                ),
                              ),
                              Expanded(
                                child: _SummaryStat(
                                  label: strings.profitLabel,
                                  value: formatMoney(profit, currency),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (returnsCount > 0 || totalReturnsAmount > 0.009) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${strings.returnsSummaryLabel} ($returnsCount)',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                '-${formatMoney(totalReturnsAmount, currency)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.error,
                                    ),
                              ),
                            ],
                          ),
                        ],
                        const Divider(height: 16),
                        Text(
                          strings.cashRegisterTitle,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            for (final method in PaymentMethod.values)
                              if ((breakdown[method] ?? 0).abs() > 0.009)
                                Text(
                                  '${strings.paymentMethodLabel(method.name)}: ${formatMoney(breakdown[method] ?? 0, currency)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: strings.searchInvoicesHint,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_query.isNotEmpty)
                          IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                        IconButton(
                          tooltip: strings.scanReceiptBarcodeTooltip,
                          onPressed: () async {
                            widget.controller.trackFeatureUsage(
                              FeatureUsageKeys.barcodeScan,
                            );
                            final scanned = await Navigator.of(context).push<String>(
                              MaterialPageRoute<String>(
                                builder: (_) => BarcodeScannerScreen(strings: strings),
                              ),
                            );
                            if (scanned == null || scanned.trim().isEmpty || !mounted) {
                              return;
                            }
                            final code = scanned.trim();
                            final codeLower = code.toLowerCase();
                            setState(() {
                              _searchCtrl.text = code;
                              _query = code;
                            });
                            final exactMatches = widget.controller.sales
                                .where(
                                  (s) =>
                                      s.receiptCode.toLowerCase() == codeLower ||
                                      s.id.toLowerCase() == codeLower,
                                )
                                .toList();
                            if (exactMatches.length == 1) {
                              await _showSaleDetails(exactMatches.first);
                            }
                          },
                          icon: const Icon(Icons.qr_code_scanner),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: sales.isEmpty
                    ? Center(
                        child: Text(
                          strings.noSalesForFilter(
                            _filterLabel(strings, _filter),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          16 + MediaQuery.viewInsetsOf(context).bottom,
                        ),
                        itemCount: sales.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final sale = sales[index];
                          final subtitleParts = [
                            '№${sale.receiptCode}',
                            formatDateTime(sale.createdAt),
                            sale.isSplitPayment
                                ? '${strings.paymentMethodLabel(sale.paymentMethod.name)} + ${strings.paymentMethodLabel(sale.secondaryPaymentMethod!.name)}'
                                : strings.paymentMethodLabel(sale.paymentMethod.name),
                            strings.unitsShort(sale.totalUnits),
                            if (sale.customerName.isNotEmpty) sale.customerName,
                          ];

                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              onTap: () => _showSaleDetails(sale),
                              title: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    formatMoney(sale.total, currency),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: sale.isPaid
                                          ? Colors.green.shade100
                                          : Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      sale.isPaid
                                          ? strings.paidBadge
                                          : strings.unpaidBadge(
                                              formatMoney(
                                                sale.remainingDebt,
                                                currency,
                                              ),
                                            ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  if (sale.refundNote.isNotEmpty ||
                                      sale.refundedAmount > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .errorContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        strings.returnedBadge,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onErrorContainer,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(subtitleParts.join(' • ')),
                              trailing: isCashier
                                  ? null
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '+${formatMoney(sale.profit, currency)}',
                                          style: TextStyle(
                                            color: sale.profit >= 0
                                                ? Colors.green.shade700
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(strings.profitLabel),
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

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
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
    );
  }
}

class _SaleDetailSheet extends StatelessWidget {
  const _SaleDetailSheet({
    required this.controller,
    required this.saleId,
  });

  final ShopController controller;
  final String saleId;

  Future<void> _promptPartialPayment(BuildContext context, Sale sale) async {
    final strings = controller.strings;
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _PartialPaymentDialog(
        title: strings.addPayment,
        hintLabel: strings.paymentAmountHint,
        cancelLabel: strings.cancel,
        confirmLabel: strings.confirm,
        initialAmount: sale.remainingDebt.toStringAsFixed(0),
      ),
    );

    if (amount != null && amount > 0) {
      await controller.recordSalePayment(sale.id, amount);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.paymentRecorded)),
        );
      }
    }
  }

  Future<void> _promptChangePaymentMethod(BuildContext context, Sale sale) async {
    final strings = controller.strings;
    final result = await showDialog<_PaymentEditResult>(
      context: context,
      builder: (_) => _ChangePaymentDialog(
        strings: strings,
        currency: controller.currency,
        sale: sale,
      ),
    );
    if (result == null || !context.mounted) return;
    await controller.updateSalePaymentMethod(
      sale.id,
      paymentMethod: result.primaryMethod,
      secondaryPaymentMethod: result.secondaryMethod,
      secondaryAmount: result.secondaryAmount,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.paymentMethodUpdatedMsg)),
      );
    }
  }

  Future<void> _promptReturnOrExchange(BuildContext context, Sale sale) async {
    final applied = await showDialog<bool>(
      context: context,
      builder: (_) => _ReturnExchangeDialog(
        controller: controller,
        sale: sale,
      ),
    );
    if (applied == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.strings.returnSavedMsg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final strings = controller.strings;
        final currency = controller.currency;
        final isCashier = controller.cashierMode;
        final sale = controller.sales.cast<Sale?>().firstWhere(
              (s) => s?.id == saleId,
              orElse: () => null,
            );
        if (sale == null) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.receiptNumberLabel(sale.receiptCode),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        sale.isSplitPayment
                            ? '${strings.paymentMethodLabel(sale.paymentMethod.name)} (${formatMoney(sale.primaryPaymentAmount, currency)}) + ${strings.paymentMethodLabel(sale.secondaryPaymentMethod!.name)} (${formatMoney(sale.secondaryAmount, currency)})'
                            : strings.paymentMethodLabel(sale.paymentMethod.name),
                        style: Theme.of(context).textTheme.labelLarge,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  formatDateTime(sale.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (sale.customerName.isNotEmpty)
                  Text(
                    strings.customerLabel(sale.customerName),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (sale.customerPhone.isNotEmpty)
                  Text(
                    '${strings.shopPhoneLabel}: ${sale.customerPhone}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (sale.dueDate != null)
                  Text(
                    strings.dueDateValue(formatDate(sale.dueDate!)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (sale.refundNote.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${strings.returnedBadge}: ${sale.refundNote}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                if (sale.returnReason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${strings.returnReasonPrefix}: ${sale.returnReason}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ),
                const Divider(height: 20),
                for (final item in sale.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${item.productName} (${item.quantity} × ${formatMoney(item.unitPrice, currency)})',
                              ),
                            ),
                            Text(formatMoney(item.lineTotal, currency)),
                          ],
                        ),
                        if (!isCashier)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              '${strings.costShort}: ${formatMoney(item.unitCost, currency)}  •  '
                              '${strings.profitLabel}: ${item.lineProfit >= 0 ? '+' : ''}${formatMoney(item.lineProfit, currency)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: item.lineProfit >= 0
                                        ? Colors.green.shade700
                                        : Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (sale.discount > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          sale.discountReason.isNotEmpty
                              ? '${strings.discountLabel} (${sale.discountReason})'
                              : strings.discountLabel,
                        ),
                      ),
                      Text('-${formatMoney(sale.discount, currency)}'),
                    ],
                  ),
                ],
                const Divider(height: 20),
                if (!isCashier) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        strings.costLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        formatMoney(sale.totalCost, currency),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        isCashier
                            ? strings.totalDue
                            : strings.totalWithProfit(
                                formatMoney(sale.profit, currency),
                              ),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMoney(sale.total, currency),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (!sale.isPaid || sale.paymentMethod == PaymentMethod.postPay) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(strings.paidAmountLabel),
                      Text(formatMoney(sale.paidAmount, currency)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        strings.remainingDebtLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        formatMoney(sale.remainingDebt, currency),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: sale.isPaid
                              ? Colors.green.shade700
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                  if (sale.paymentHistory.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      strings.debtRepaymentsHeader,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    for (final p in sale.paymentHistory)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatDateTime(p.paidAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              '+${formatMoney(p.amount, currency)}',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
                const SizedBox(height: 12),
                ReceiptBarcodeWidget(code: sale.receiptCode),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => ReceiptSheet(
                        controller: controller,
                        sale: sale,
                      ),
                    );
                  },
                  icon: const Icon(Icons.share_outlined),
                  label: Text('${strings.shareWhatsAppBtn} / PDF'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      _promptChangePaymentMethod(context, sale),
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(strings.changePaymentMethodAction),
                ),
                if (!isCashier && sale.items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _promptReturnOrExchange(context, sale),
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: Text(strings.returnOrExchangeAction),
                  ),
                ],
                if (!sale.isPaid) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              _promptPartialPayment(context, sale),
                          child: Text(
                            strings.addPayment,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            await controller.markSalePaid(sale.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(strings.paymentRecorded)),
                              );
                            }
                          },
                          child: Text(
                            strings.markAsPaid,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!isCashier) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await controller.archiveSale(sale.id);
                            if (context.mounted) {
                              Navigator.of(context).pop('archived');
                            }
                          },
                          icon: const Icon(Icons.archive_outlined),
                          label: Text(
                            strings.archiveAction,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await controller.moveSaleToTrash(sale.id);
                            if (context.mounted) {
                              Navigator.of(context).pop('trashed');
                            }
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            strings.moveToTrashAction,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PartialPaymentDialog extends StatefulWidget {
  const _PartialPaymentDialog({
    required this.title,
    required this.hintLabel,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.initialAmount,
  });

  final String title;
  final String hintLabel;
  final String cancelLabel;
  final String confirmLabel;
  final String initialAmount;

  @override
  State<_PartialPaymentDialog> createState() => _PartialPaymentDialogState();
}

class _PartialPaymentDialogState extends State<_PartialPaymentDialog> {
  late final TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.initialAmount);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: TextField(
          controller: _amountController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: widget.hintLabel,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            final parsed = double.tryParse(value.trim());
            Navigator.of(context).pop(parsed);
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
            final parsed = double.tryParse(_amountController.text.trim());
            Navigator.of(context).pop(parsed);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _PaymentEditResult {
  const _PaymentEditResult({
    required this.primaryMethod,
    this.secondaryMethod,
    this.secondaryAmount = 0,
  });

  final PaymentMethod primaryMethod;
  final PaymentMethod? secondaryMethod;
  final double secondaryAmount;
}

class _ChangePaymentDialog extends StatefulWidget {
  const _ChangePaymentDialog({
    required this.strings,
    required this.currency,
    required this.sale,
  });

  final AppStrings strings;
  final AppCurrency currency;
  final Sale sale;

  @override
  State<_ChangePaymentDialog> createState() => _ChangePaymentDialogState();
}

class _ChangePaymentDialogState extends State<_ChangePaymentDialog> {
  late PaymentMethod _primaryMethod;
  late bool _splitPayment;
  late PaymentMethod _secondaryMethod;
  late final TextEditingController _primarySplitCtrl;

  @override
  void initState() {
    super.initState();
    _primaryMethod = widget.sale.paymentMethod;
    _splitPayment = widget.sale.isSplitPayment;
    _secondaryMethod = widget.sale.secondaryPaymentMethod ??
        PaymentMethod.values.firstWhere(
          (m) => m != PaymentMethod.postPay && m != _primaryMethod,
          orElse: () => PaymentMethod.kaspiQr,
        );
    final initPrimary = _splitPayment
        ? widget.sale.primaryPaymentAmount
        : (widget.sale.total / 2).roundToDouble();
    _primarySplitCtrl = TextEditingController(
      text: initPrimary.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _primarySplitCtrl.dispose();
    super.dispose();
  }

  double get _primarySplit {
    final raw = _primarySplitCtrl.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw) ?? 0;
    return parsed.clamp(0.0, widget.sale.total);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final total = widget.sale.total;
    final isPostPay = _primaryMethod == PaymentMethod.postPay;
    final secondaryAmount = (_splitPayment && !isPostPay)
        ? (total - _primarySplit).clamp(0.0, total)
        : 0.0;

    return AlertDialog(
      title: Text(strings.changePaymentMethodAction),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final method in PaymentMethod.values)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(strings.paymentMethodLabel(method.name)),
                    selected: _primaryMethod == method,
                    onSelected: (_) {
                      setState(() {
                        _primaryMethod = method;
                        if (method == PaymentMethod.postPay) {
                          _splitPayment = false;
                        } else if (_secondaryMethod == method) {
                          _secondaryMethod = PaymentMethod.values.firstWhere(
                            (m) => m != PaymentMethod.postPay && m != method,
                          );
                        }
                      });
                    },
                  ),
                if (!isPostPay)
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.call_split, size: 16),
                    label: Text(strings.splitPaymentLabel),
                    selected: _splitPayment,
                    onSelected: (v) {
                      setState(() {
                        _splitPayment = v;
                        if (v && _secondaryMethod == _primaryMethod) {
                          _secondaryMethod = PaymentMethod.values.firstWhere(
                            (m) =>
                                m != PaymentMethod.postPay &&
                                m != _primaryMethod,
                          );
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
                        method != _primaryMethod)
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
                      controller: _primarySplitCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: strings.firstMethodAmountLabel(
                          strings.paymentMethodLabel(_primaryMethod.name),
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
                      _primarySplitCtrl.text = (total / 2).round().toString();
                      setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                strings.remainingMethodAmountLabel(
                  strings.paymentMethodLabel(_secondaryMethod.name),
                  formatMoney(secondaryAmount, widget.currency),
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _PaymentEditResult(
              primaryMethod: _primaryMethod,
              secondaryMethod: (_splitPayment && secondaryAmount > 0.009)
                  ? _secondaryMethod
                  : null,
              secondaryAmount: secondaryAmount,
            ),
          ),
          child: Text(strings.saveChanges),
        ),
      ],
    );
  }
}

class _ReturnExchangeDialog extends StatefulWidget {
  const _ReturnExchangeDialog({
    required this.controller,
    required this.sale,
  });

  final ShopController controller;
  final Sale sale;

  @override
  State<_ReturnExchangeDialog> createState() => _ReturnExchangeDialogState();
}

class _ReturnExchangeDialogState extends State<_ReturnExchangeDialog> {
  bool _isExchange = false;
  bool _returnToStock = true;
  late PaymentMethod _settlementMethod;
  late final Map<String, int> _returnQty;
  final Map<String, int> _exchangeQty = {};
  final Map<String, double> _exchangePrices = {};
  final _refundAmountCtrl = TextEditingController();
  final _productSearchCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  String _productQuery = '';

  @override
  void initState() {
    super.initState();
    _settlementMethod = widget.sale.paymentMethod == PaymentMethod.postPay
        ? PaymentMethod.cash
        : widget.sale.paymentMethod;
    _returnQty = {for (final item in widget.sale.items) item.productId: 0};
  }

  @override
  void dispose() {
    _refundAmountCtrl.dispose();
    _productSearchCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  double get _discountRatio {
    final sub = widget.sale.subtotal;
    if (sub <= 0) return 1.0;
    return ((sub - widget.sale.discount) / sub).clamp(0.0, 1.0);
  }

  double get _returnedItemsTotal {
    var sum = 0.0;
    for (final item in widget.sale.items) {
      sum += item.unitPrice * (_returnQty[item.productId] ?? 0);
    }
    return sum * _discountRatio;
  }

  double get _exchangeItemsTotal {
    var sum = 0.0;
    for (final entry in _exchangeQty.entries) {
      if (entry.value <= 0) continue;
      final p = widget.controller.findProductById(entry.key);
      if (p != null) {
        final price = _exchangePrices[entry.key] ?? p.sellPrice;
        sum += price * entry.value;
      }
    }
    return sum;
  }

  void _syncRefundText() {
    final val = _returnedItemsTotal.clamp(0.0, widget.sale.paidAmount);
    _refundAmountCtrl.text = val > 0
        ? (val == val.roundToDouble() ? val.toStringAsFixed(0) : val.toStringAsFixed(2))
        : '';
  }

  Future<void> _openCalculator() async {
    final strings = widget.controller.strings;
    final initial = double.tryParse(
      _refundAmountCtrl.text.trim().replaceAll(',', '.'),
    );
    final result = await showCurrencyCalculatorDialog(
      context,
      strings: strings,
      targetCurrency: widget.controller.currency,
      initialValue: initial,
    );
    if (result != null && result > 0 && mounted) {
      setState(() {
        _refundAmountCtrl.text = result == result.roundToDouble()
            ? result.toStringAsFixed(0)
            : result.toStringAsFixed(2);
      });
    }
  }

  Future<void> _submit() async {
    final hasReturnedItems = _returnQty.values.any((q) => q > 0);
    final customRefund = double.tryParse(
          _refundAmountCtrl.text.trim().replaceAll(',', '.'),
        ) ??
        0.0;
    final exchangeList = <({Product product, int quantity, double? customUnitPrice})>[];
    if (_isExchange) {
      for (final entry in _exchangeQty.entries) {
        if (entry.value <= 0) continue;
        final p = widget.controller.findProductById(entry.key);
        if (p != null) {
          exchangeList.add((
            product: p,
            quantity: entry.value,
            customUnitPrice: _exchangePrices[entry.key],
          ));
        }
      }
      if (!hasReturnedItems || exchangeList.isEmpty) return;
    } else {
      if (!hasReturnedItems && customRefund <= 0) return;
    }

    await widget.controller.processSaleReturnOrExchange(
      saleId: widget.sale.id,
      returnQuantities: _returnQty,
      customRefundAmount: _isExchange ? 0 : customRefund,
      exchangeItems: exchangeList,
      returnToStock: _returnToStock,
      settlementMethod: _settlementMethod,
      returnReason: _reasonCtrl.text,
    );
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final q = _productQuery.trim().toLowerCase();
    final availableProducts = widget.controller.products.where((p) {
      if (p.stock <= 0) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.packBarcode.toLowerCase().contains(q) ||
          p.boxBarcode.toLowerCase().contains(q);
    }).toList();

    final diff = _exchangeItemsTotal - _returnedItemsTotal;
    final hasReturnedItems = _returnQty.values.any((qty) => qty > 0);
    final maxRefund = widget.sale.paidAmount;
    final customRefund = double.tryParse(
          _refundAmountCtrl.text.trim().replaceAll(',', '.'),
        ) ??
        0.0;
    final exceedsPaid = !_isExchange && customRefund > maxRefund + 0.009;
    final canSubmit = _isExchange
        ? (hasReturnedItems && _exchangeQty.values.any((qty) => qty > 0))
        : (!exceedsPaid && (hasReturnedItems || customRefund > 0));

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Text(strings.returnOrExchangeAction),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(
                      strings.returnTab,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(
                      strings.exchangeTab,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {_isExchange},
                onSelectionChanged: (sel) {
                  setState(() => _isExchange = sel.first);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.itemsToReturnLabel,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        for (final item in widget.sale.items) {
                          _returnQty[item.productId] = item.quantity;
                        }
                        _syncRefundText();
                      });
                    },
                    child: Text(strings.returnAllBtn),
                  ),
                ],
              ),
              for (final item in widget.sale.items) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.productName}\n${formatMoney(item.unitPrice, currency)} × ${item.quantity}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: (_returnQty[item.productId] ?? 0) > 0
                          ? () {
                              setState(() {
                                _returnQty[item.productId] =
                                    (_returnQty[item.productId] ?? 0) - 1;
                                _syncRefundText();
                              });
                            }
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '${_returnQty[item.productId] ?? 0}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: (_returnQty[item.productId] ?? 0) < item.quantity
                          ? () {
                              setState(() {
                                _returnQty[item.productId] =
                                    (_returnQty[item.productId] ?? 0) + 1;
                                _syncRefundText();
                              });
                            }
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
              if (hasReturnedItems) ...[
                const SizedBox(height: 8),
                Text(
                  strings.returnConditionLabel,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text(
                        strings.returnToStockOption,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text(
                        strings.returnAsDefectOption,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  selected: {_returnToStock},
                  onSelectionChanged: (sel) {
                    setState(() => _returnToStock = sel.first);
                  },
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _reasonCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: strings.returnReasonLabel,
                  prefixIcon: const Icon(Icons.comment_outlined, size: 18),
                  suffixIcon: _reasonCtrl.text.trim().isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _reasonCtrl.clear();
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
                  for (final preset in (_returnToStock
                      ? strings.returnReasonPresets
                      : strings.defectReasonPresets))
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(preset),
                      selected: _reasonCtrl.text.trim() == preset,
                      onSelected: (selected) {
                        setState(() {
                          _reasonCtrl.text = selected ? preset : '';
                        });
                      },
                    ),
                ],
              ),
              if (!_isExchange) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _refundAmountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: strings.refundAmountLabel,
                    helperText: [
                      strings.maxRefundLimitLabel(formatMoney(maxRefund, currency)),
                      if (widget.sale.discount > 0) strings.discountAppliedNote,
                    ].join(' • '),
                    errorText: exceedsPaid
                        ? strings.refundExceedsPaidError(
                            formatMoney(maxRefund, currency),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: strings.currencyCalculatorTitle,
                      onPressed: _openCalculator,
                      icon: const Icon(Icons.calculate_outlined),
                    ),
                  ),
                ),
              ] else ...[
                const Divider(height: 18),
                Text(
                  strings.replacementProductLabel,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _productSearchCtrl,
                  onChanged: (v) => setState(() => _productQuery = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: strings.searchGoodsHint,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_productQuery.isNotEmpty)
                          IconButton(
                            onPressed: () {
                              _productSearchCtrl.clear();
                              setState(() => _productQuery = '');
                            },
                            icon: const Icon(Icons.clear, size: 18),
                          ),
                        IconButton(
                          tooltip: strings.scanBarcodeTitle,
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final scanned = await Navigator.of(context).push<String>(
                              MaterialPageRoute<String>(
                                builder: (_) => BarcodeScannerScreen(strings: strings),
                              ),
                            );
                            if (scanned == null || scanned.trim().isEmpty || !mounted) {
                              return;
                            }
                            final product = widget.controller.findProductBySku(scanned);
                            if (product == null) {
                              setState(() {
                                _productSearchCtrl.text = scanned.trim();
                                _productQuery = scanned.trim();
                              });
                              messenger.showSnackBar(
                                SnackBar(content: Text(strings.skuNotFoundMsg(scanned.trim()))),
                              );
                              return;
                            }
                            if (product.stock <= 0) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(strings.outOfStockMsg(product.name))),
                              );
                              return;
                            }
                            final currentQty = _exchangeQty[product.id] ?? 0;
                            if (currentQty >= product.stock) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(strings.onlyLeftMsg(product.stock))),
                              );
                              return;
                            }
                            setState(() {
                              _exchangeQty[product.id] = currentQty + 1;
                              _productSearchCtrl.text = product.name;
                              _productQuery = product.name;
                            });
                          },
                          icon: const Icon(Icons.qr_code_scanner, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: availableProducts.length,
                    itemBuilder: (context, index) {
                      final p = availableProducts[index];
                      final qty = _exchangeQty[p.id] ?? 0;
                      final unitPrice = _exchangePrices[p.id] ?? p.sellPrice;
                      final hasCustomPrice = _exchangePrices[p.id] != null &&
                          (_exchangePrices[p.id]! - p.sellPrice).abs() > 0.009;
                      return Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () async {
                                final nextPrice = await showCurrencyCalculatorDialog(
                                  context,
                                  strings: strings,
                                  targetCurrency: currency,
                                  productName: p.name,
                                  initialValue: unitPrice,
                                );
                                if (nextPrice != null && nextPrice > 0 && mounted) {
                                  setState(() => _exchangePrices[p.id] = nextPrice);
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.name,
                                      style: Theme.of(context).textTheme.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          '${formatMoney(unitPrice, currency)} (${p.stock})',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: hasCustomPrice
                                                    ? Theme.of(context).colorScheme.primary
                                                    : null,
                                                fontWeight: hasCustomPrice
                                                    ? FontWeight.w700
                                                    : null,
                                                decoration: TextDecoration.underline,
                                              ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 13,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: qty > 0
                                ? () => setState(() => _exchangeQty[p.id] = qty - 1)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline, size: 18),
                          ),
                          Text('$qty'),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: qty < p.stock
                                ? () => setState(() => _exchangeQty[p.id] = qty + 1)
                                : null,
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    diff > 0.009
                        ? strings.exchangeDiffPayLabel(formatMoney(diff, currency))
                        : diff < -0.009
                            ? strings.exchangeDiffRefundLabel(formatMoney(-diff, currency))
                            : strings.exchangeEvenLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
              if ((_isExchange && diff.abs() > 0.009) ||
                  (!_isExchange && (customRefund > 0 || hasReturnedItems))) ...[
                const SizedBox(height: 10),
                Text(
                  (_isExchange && diff > 0.009)
                      ? strings.extraPaymentMethodLabel
                      : strings.refundMethodLabel,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final method in PaymentMethod.values)
                      if (method != PaymentMethod.postPay)
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(strings.paymentMethodLabel(method.name)),
                          selected: _settlementMethod == method,
                          onSelected: (_) {
                            setState(() => _settlementMethod = method);
                          },
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
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          child: Text(strings.confirm),
        ),
      ],
    );
  }
}
