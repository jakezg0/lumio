import 'package:flutter/material.dart';

import '../models/stock_in.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';
import 'stock_in_sheet.dart';

class SuppliersSheet extends StatefulWidget {
  const SuppliersSheet({super.key, required this.controller});

  final ShopController controller;

  @override
  State<SuppliersSheet> createState() => _SuppliersSheetState();
}

class _SuppliersSheetState extends State<SuppliersSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showBestPricesTab = false;
  bool _debtOnly = false;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _showPaySupplierDialog(StockInRecord inv) async {
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final amountCtrl = TextEditingController(
      text: inv.remainingDebt == inv.remainingDebt.roundToDouble()
          ? inv.remainingDebt.toStringAsFixed(0)
          : inv.remainingDebt.toStringAsFixed(2),
    );
    var recordAsExpense = true;

    final confirmed = await showDialog<({double amount, bool asExpense})>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text(strings.paySupplierDebtTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${inv.supplierName.isEmpty ? strings.unspecifiedSupplierLabel : inv.supplierName} • '
                  '${strings.remainingDebtLabel}: ${formatMoney(inv.remainingDebt, currency)}',
                  style: Theme.of(dialogCtx).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onTap: () => selectAllText(amountCtrl),
                  decoration: InputDecoration(
                    labelText: strings.paymentAmountHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  value: recordAsExpense,
                  onChanged: (v) =>
                      setDialogState(() => recordAsExpense = v ?? true),
                  title: Text(strings.recordAsExpenseLabel),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(
                  amountCtrl.text.trim().replaceAll(',', '.'),
                );
                if (parsed == null || parsed <= 0) return;
                Navigator.of(dialogCtx).pop(
                  (amount: parsed, asExpense: recordAsExpense),
                );
              },
              child: Text(strings.confirm),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
    if (confirmed == null || !mounted) return;
    await widget.controller.recordSupplierPayment(
      inv.id,
      confirmed.amount,
      recordAsExpense: confirmed.asExpense,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.paymentRecorded)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;
        final q = _query.trim().toLowerCase();
        final allSuppliers = widget.controller.buildSupplierDirectory();
        final debtSuppliersCount =
            allSuppliers.where((s) => s.totalDebt > 0.009).length;
        final totalSupplierDebt = widget.controller.totalSupplierDebt;

        final suppliers = allSuppliers.where((s) {
          if (_debtOnly && s.totalDebt <= 0.009) return false;
          if (q.isEmpty) return true;
          final displayName = s.name.isEmpty
              ? strings.unspecifiedSupplierLabel.toLowerCase()
              : s.name.toLowerCase();
          if (displayName.contains(q)) return true;
          return s.invoices.any(
            (inv) => inv.items.any(
              (item) => item.productName.toLowerCase().contains(q),
            ),
          );
        }).toList();

        final cheapestList = widget.controller
            .buildCheapestSupplierByProduct()
            .where((item) {
          if (q.isEmpty) return true;
          if (item.productName.toLowerCase().contains(q)) return true;
          return item.quotes.any(
            (quote) => quote.supplierName.toLowerCase().contains(q),
          );
        }).toList();

        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.96,
          expand: false,
          builder: (context, scrollController) => Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.storefront_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.suppliersDirectoryTitle,
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
                if (totalSupplierDebt > 0.009) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 18,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings.supplierDebtTotalLabel(
                              formatMoney(totalSupplierDebt, currency),
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(
                        '${strings.suppliersTabLabel} (${suppliers.length})',
                      ),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(strings.cheapestSupplierTabLabel),
                    ),
                  ],
                  selected: {_showBestPricesTab},
                  onSelectionChanged: (sel) {
                    setState(() => _showBestPricesTab = sel.first);
                  },
                ),
                if (!_showBestPricesTab &&
                    (debtSuppliersCount > 0 || _debtOnly)) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        strings.supplierDebtOnlyFilter(debtSuppliersCount),
                      ),
                      selected: _debtOnly,
                      onSelected: (v) => setState(() => _debtOnly = v),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: strings.searchSuppliersHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: !_showBestPricesTab
                      ? (suppliers.isEmpty
                          ? Center(
                              child: Text(
                                strings.suppliersEmptyMsg,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: suppliers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final s = suppliers[index];
                                final hasDebt = s.totalDebt > 0.009;
                                final displayName = s.name.isEmpty
                                    ? strings.unspecifiedSupplierLabel
                                    : s.name;
                                return Card(
                                  margin: EdgeInsets.zero,
                                  clipBehavior: Clip.antiAlias,
                                  child: ExpansionTile(
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            displayName,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        if (hasDebt)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme
                                                  .colorScheme.errorContainer,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              strings.supplierDebtBadge(
                                                formatMoney(
                                                  s.totalDebt,
                                                  currency,
                                                ),
                                              ),
                                              style: theme
                                                  .textTheme.labelSmall
                                                  ?.copyWith(
                                                color: theme.colorScheme
                                                    .onErrorContainer,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      '${strings.supplierStatsSummary(s.invoicesCount, s.uniqueProductsCount)} • ${formatMoney(s.totalSpend, currency)}',
                                    ),
                                    trailing: Text(
                                      formatDateTime(s.lastDeliveryAt)
                                          .split(' ')
                                          .first,
                                      style: theme.textTheme.labelSmall,
                                    ),
                                    childrenPadding: const EdgeInsets.fromLTRB(
                                      14,
                                      0,
                                      14,
                                      12,
                                    ),
                                    children: [
                                      if (hasDebt) ...[
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: FilledButton.tonalIcon(
                                            onPressed: () async {
                                              await widget.controller
                                                  .markAllSupplierDebtsPaid(
                                                s.name,
                                              );
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                  this.context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      strings.paymentRecorded,
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.done_all,
                                              size: 18,
                                            ),
                                            label: Text(strings.payAllAction),
                                          ),
                                        ),
                                      ],
                                      for (final inv in s.invoices) ...[
                                        const Divider(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${formatDateTime(inv.createdAt)} • ${formatMoney(inv.totalCost, currency)}',
                                                    style: theme
                                                        .textTheme.labelMedium
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  if (!inv.isPaid)
                                                    Text(
                                                      [
                                                        strings.unpaidBadge(
                                                          formatMoney(
                                                            inv.remainingDebt,
                                                            currency,
                                                          ),
                                                        ),
                                                        if (inv
                                                                .effectivePaidAmount >
                                                            0.009)
                                                          '${strings.paidAmountLabel}: ${formatMoney(inv.effectivePaidAmount, currency)}',
                                                      ].join(' • '),
                                                      style: theme
                                                          .textTheme.labelSmall
                                                          ?.copyWith(
                                                        color: theme
                                                            .colorScheme.error,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    )
                                                  else if (inv.isCredit)
                                                    Text(
                                                      strings.debtPaidBadge,
                                                      style: theme
                                                          .textTheme.labelSmall
                                                          ?.copyWith(
                                                        color: Colors
                                                            .green.shade700,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            TextButton.icon(
                                              onPressed: () async {
                                                await widget.controller
                                                    .repeatStockIn(inv);
                                                if (!mounted) return;
                                                await showModalBottomSheet<
                                                    double>(
                                                  context: this.context,
                                                  isScrollControlled: true,
                                                  useSafeArea: true,
                                                  builder: (_) => StockInSheet(
                                                    controller:
                                                        widget.controller,
                                                  ),
                                                );
                                                if (mounted) {
                                                  Navigator.of(this.context)
                                                      .pop();
                                                }
                                              },
                                              icon: const Icon(
                                                Icons.replay,
                                                size: 16,
                                              ),
                                              label: Text(
                                                strings.repeatStockInBtn,
                                              ),
                                            ),
                                          ],
                                        ),
                                        for (final item in inv.items)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 2,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    item.productName,
                                                    style: theme
                                                        .textTheme.bodySmall,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${formatQty(item.quantity)} × ${formatMoney(item.unitCost, currency)}',
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (inv.paymentHistory.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 2,
                                            children: [
                                              for (final pay
                                                  in inv.paymentHistory)
                                                Text(
                                                  '✓ ${formatDateTime(pay.paidAt).split(' ').first}: ${formatMoney(pay.amount, currency)}',
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                    color:
                                                        Colors.green.shade800,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                        if (!inv.isPaid) ...[
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _showPaySupplierDialog(
                                                    inv,
                                                  ),
                                                  icon: const Icon(
                                                    Icons.payments_outlined,
                                                    size: 16,
                                                  ),
                                                  label: Text(
                                                    strings.addPayment,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: FilledButton.tonalIcon(
                                                  onPressed: () async {
                                                    await widget.controller
                                                        .markStockInPaid(
                                                      inv.id,
                                                    );
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                        this.context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            strings
                                                                .paymentRecorded,
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  icon: const Icon(
                                                    Icons.check,
                                                    size: 16,
                                                  ),
                                                  label: Text(
                                                    strings.markAsPaid,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ))
                      : (cheapestList.isEmpty
                          ? Center(
                              child: Text(
                                strings.cheapestSupplierEmptyMsg,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: cheapestList.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final item = cheapestList[index];
                                return Card(
                                  margin: EdgeInsets.zero,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.productName,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.green.shade200,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.verified_outlined,
                                                size: 16,
                                                color: Colors.green.shade800,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  '${strings.cheapestLastTimeLabel}: ${item.cheapestSupplier}',
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    color:
                                                        Colors.green.shade900,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                formatMoney(
                                                  item.cheapestPrice,
                                                  currency,
                                                ),
                                                style: theme
                                                    .textTheme.titleSmall
                                                    ?.copyWith(
                                                  color: Colors.green.shade900,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (item.quotes.length > 1) ...[
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              for (final q
                                                  in item.quotes.skip(1))
                                                Text(
                                                  '${q.supplierName}: ${formatMoney(q.lastPrice, currency)}',
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
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
                            )),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
