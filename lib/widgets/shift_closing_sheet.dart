import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/sale.dart';
import '../services/whatsapp_launcher.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';

class ShiftClosingSheet extends StatefulWidget {
  const ShiftClosingSheet({super.key, required this.controller});

  final ShopController controller;

  @override
  State<ShiftClosingSheet> createState() => _ShiftClosingSheetState();
}

class _ShiftClosingSheetState extends State<ShiftClosingSheet> {
  final _openingFloatCtrl = TextEditingController();
  final _actualCashCtrl = TextEditingController();

  @override
  void dispose() {
    _openingFloatCtrl.dispose();
    _actualCashCtrl.dispose();
    super.dispose();
  }

  double? _parseNumber(String raw) {
    final clean = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (clean.isEmpty) return null;
    return double.tryParse(clean);
  }

  Future<void> _promptCashMovement({required bool isDeposit}) async {
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          isDeposit ? strings.cashDepositTitle : strings.cashWithdrawalTitle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: strings.expenseAmountLabel,
                suffixText: currency.symbol,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: strings.cashMovementNoteHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(strings.confirm),
          ),
        ],
      ),
    );
    final amount = _parseNumber(amountCtrl.text) ?? 0.0;
    final note = noteCtrl.text.trim();
    amountCtrl.dispose();
    noteCtrl.dispose();
    if (confirmed == true && amount > 0) {
      await widget.controller.addCashDrawerMovement(
        isDeposit: isDeposit,
        amount: amount,
        note: note,
      );
    }
  }

  String _buildReportText({
    required AppStrings strings,
    required AppCurrency currency,
    required bool isCashier,
    required String shopName,
    required DateTime now,
    required int ordersCount,
    required double revenue,
    required double cost,
    required double profit,
    required Map<PaymentMethod, double> breakdown,
    required int returnsCount,
    required double returnsTotal,
    required int expensesCount,
    required double expensesTotal,
    required double openingFloat,
    required double depositsTotal,
    required double withdrawalsTotal,
    required double expectedCash,
    required double? actualCash,
    required Map<String, ({int count, double revenue, int returnsCount, double returnsTotal})> bySeller,
  }) {
    final buf = StringBuffer();
    final titleShop = shopName.trim().isNotEmpty ? ' — ${shopName.trim()}' : '';
    buf.writeln('${strings.shiftClosingTitle}$titleShop');
    buf.writeln(formatDateTime(now));
    buf.writeln('');
    buf.writeln('${strings.ordersLabel}: $ordersCount');
    buf.writeln('${strings.revenueLabel}: ${formatMoney(revenue, currency)}');

    if (!isCashier) {
      buf.writeln('${strings.costLabel}: ${formatMoney(cost, currency)}');
      buf.writeln('${strings.profitLabel}: ${formatMoney(profit, currency)}');
    }

    buf.writeln('');
    buf.writeln('${strings.shiftPaymentBreakdownHeader}:');
    var hasAnyPayment = false;
    for (final method in PaymentMethod.values) {
      final val = breakdown[method] ?? 0.0;
      if (val.abs() > 0.009) {
        hasAnyPayment = true;
        buf.writeln(
          '• ${strings.paymentMethodLabel(method.name)}: ${formatMoney(val, currency)}',
        );
      }
    }
    if (!hasAnyPayment) {
      buf.writeln('• ${formatMoney(0, currency)}');
    }

    if (returnsCount > 0 || returnsTotal > 0.009) {
      buf.writeln('');
      buf.writeln(
        '${strings.returnsSummaryLabel} ($returnsCount): -${formatMoney(returnsTotal, currency)}',
      );
    }

    if (bySeller.isNotEmpty) {
      buf.writeln('');
      buf.writeln('${strings.shiftBySellerHeader}:');
      for (final entry in bySeller.entries) {
        final s = entry.value;
        final retSuffix = s.returnsCount > 0
            ? ' (${strings.returnsSummaryLabel} ${s.returnsCount}: -${formatMoney(s.returnsTotal, currency)})'
            : '';
        buf.writeln(
          '• ${entry.key}: ${s.count} • ${formatMoney(s.revenue, currency)}$retSuffix',
        );
      }
    }

    buf.writeln('');
    buf.writeln(
      '${strings.totalExpensesLabel} ($expensesCount): ${formatMoney(expensesTotal, currency)}',
    );

    buf.writeln('');
    buf.writeln('${strings.shiftCashReconciliationHeader}:');
    if (openingFloat > 0.009) {
      buf.writeln(
        '• ${strings.shiftOpeningFloatLabel}: ${formatMoney(openingFloat, currency)}',
      );
    }
    if (depositsTotal > 0.009) {
      buf.writeln(
        '• ${strings.cashDepositsLabel}: +${formatMoney(depositsTotal, currency)}',
      );
    }
    if (withdrawalsTotal > 0.009) {
      buf.writeln(
        '• ${strings.cashWithdrawalsLabel}: -${formatMoney(withdrawalsTotal, currency)}',
      );
    }
    buf.writeln(
      '• ${strings.shiftExpectedCashLabel}: ${formatMoney(expectedCash, currency)}',
    );

    if (actualCash != null) {
      buf.writeln(
        '• ${strings.shiftActualCashLabel}: ${formatMoney(actualCash, currency)}',
      );
      final diff = actualCash - expectedCash;
      if (diff.abs() < 0.01) {
        buf.writeln('• ${strings.shiftExactMatchLabel}');
      } else if (diff > 0) {
        buf.writeln(
          '• ${strings.shiftSurplusLabel(formatMoney(diff, currency))}',
        );
      } else {
        buf.writeln(
          '• ${strings.shiftShortageLabel(formatMoney(-diff, currency))}',
        );
      }
    }

    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;
        final isCashier = widget.controller.cashierMode;
        final theme = Theme.of(context);

        final now = DateTime.now();
        final todaySales =
            widget.controller.filteredSales(SalesDateFilter.today);
        final ordersCount = todaySales.length;
        final revenue = todaySales.fold(0.0, (sum, s) => sum + s.total);
        final cost = todaySales.fold(0.0, (sum, s) => sum + s.totalCost);
        final profit = todaySales.fold(0.0, (sum, s) => sum + s.profit);
        final breakdown =
            widget.controller.paymentBreakdown(SalesDateFilter.today);

        final returnsCount = todaySales.where((s) => s.hasReturn).length;
        final returnsTotal = todaySales.fold(
          0.0,
          (sum, s) => sum + s.returnedMoneyTotal,
        );

        final todayExpenses =
            widget.controller.filteredExpenses(SalesDateFilter.today);
        final expensesCount = todayExpenses.length;
        final expensesTotal =
            widget.controller.totalExpensesFor(SalesDateFilter.today);

        final cashSales = breakdown[PaymentMethod.cash] ?? 0.0;
        final openingFloat =
            (_parseNumber(_openingFloatCtrl.text) ?? 0.0).clamp(0.0, 1e12);
        final movements = widget.controller.todayCashDrawerMovements;
        final depositsTotal = widget.controller.todayCashDepositsTotal;
        final withdrawalsTotal = widget.controller.todayCashWithdrawalsTotal;
        final expectedCash = openingFloat +
            cashSales +
            depositsTotal -
            withdrawalsTotal -
            expensesTotal;
        final actualCash = _parseNumber(_actualCashCtrl.text);
        final diff = actualCash != null ? actualCash - expectedCash : null;

        final bySeller = <String, ({int count, double revenue, int returnsCount, double returnsTotal})>{};
        final hasNamedSeller = todaySales.any((s) => s.sellerName.trim().isNotEmpty);
        if (hasNamedSeller) {
          for (final s in todaySales) {
            final key = s.sellerName.trim().isEmpty
                ? strings.unspecifiedSellerLabel
                : s.sellerName.trim();
            final prev = bySeller[key] ??
                (count: 0, revenue: 0.0, returnsCount: 0, returnsTotal: 0.0);
            bySeller[key] = (
              count: prev.count + 1,
              revenue: prev.revenue + s.total,
              returnsCount: prev.returnsCount + (s.hasReturn ? 1 : 0),
              returnsTotal: prev.returnsTotal + s.returnedMoneyTotal,
            );
          }
        }

        final reportText = _buildReportText(
          strings: strings,
          currency: currency,
          isCashier: isCashier,
          shopName: widget.controller.shopName,
          now: now,
          ordersCount: ordersCount,
          revenue: revenue,
          cost: cost,
          profit: profit,
          breakdown: breakdown,
          returnsCount: returnsCount,
          returnsTotal: returnsTotal,
          expensesCount: expensesCount,
          expensesTotal: expensesTotal,
          openingFloat: openingFloat,
          depositsTotal: depositsTotal,
          withdrawalsTotal: withdrawalsTotal,
          expectedCash: expectedCash,
          actualCash: actualCash,
          bySeller: bySeller,
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.point_of_sale_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.shiftClosingTitle,
                            style: theme.textTheme.titleLarge,
                          ),
                          Text(
                            formatDate(now),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: strings.close,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (isCashier) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.visibility_off_outlined,
                          size: 18,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings.shiftCashierHiddenNote,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _ShiftStat(
                                label: strings.ordersLabel,
                                value: '$ordersCount',
                              ),
                            ),
                            Expanded(
                              child: _ShiftStat(
                                label: strings.revenueLabel,
                                value: formatMoney(revenue, currency),
                              ),
                            ),
                            if (!isCashier) ...[
                              Expanded(
                                child: _ShiftStat(
                                  label: strings.costLabel,
                                  value: formatMoney(cost, currency),
                                ),
                              ),
                              Expanded(
                                child: _ShiftStat(
                                  label: strings.profitLabel,
                                  value: formatMoney(profit, currency),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const Divider(height: 18),
                        Text(
                          strings.shiftPaymentBreakdownHeader,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (ordersCount == 0)
                          Text(
                            strings.shiftNoSalesTodayNote,
                            style: theme.textTheme.bodySmall,
                          )
                        else
                          for (final method in PaymentMethod.values)
                            if ((breakdown[method] ?? 0).abs() > 0.009)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      strings.paymentMethodLabel(method.name),
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    Text(
                                      formatMoney(
                                        breakdown[method] ?? 0,
                                        currency,
                                      ),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        const Divider(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${strings.returnsSummaryLabel} ($returnsCount)',
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              returnsTotal > 0.009
                                  ? '-${formatMoney(returnsTotal, currency)}'
                                  : formatMoney(0, currency),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: returnsTotal > 0.009
                                    ? theme.colorScheme.error
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${strings.totalExpensesLabel} ($expensesCount)',
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              formatMoney(expensesTotal, currency),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (bySeller.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            strings.shiftBySellerHeader,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final entry in bySeller.entries)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${entry.key} (${entry.value.count})',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        formatMoney(
                                          entry.value.revenue,
                                          currency,
                                        ),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (entry.value.returnsCount > 0)
                                        Text(
                                          '${strings.returnsSummaryLabel} (${entry.value.returnsCount}): -${formatMoney(entry.value.returnsTotal, currency)}',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: theme.colorScheme.error,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          strings.shiftCashReconciliationHeader,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _openingFloatCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: strings.shiftOpeningFloatLabel,
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixText: currency.symbol,
                            suffixIcon: _openingFloatCtrl.text.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      _openingFloatCtrl.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.clear, size: 18),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _promptCashMovement(isDeposit: true),
                                icon: const Icon(Icons.add, size: 18),
                                label: Text(strings.cashDepositBtn),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _promptCashMovement(isDeposit: false),
                                icon: const Icon(Icons.remove, size: 18),
                                label: Text(strings.cashWithdrawalBtn),
                              ),
                            ),
                          ],
                        ),
                        if (movements.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (final m in movements)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    m.isDeposit
                                        ? Icons.south_west
                                        : Icons.north_east,
                                    size: 16,
                                    color: m.isDeposit
                                        ? Colors.green.shade700
                                        : theme.colorScheme.error,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${m.isDeposit ? '+' : '-'}${formatMoney(m.amount, currency)}${m.note.isNotEmpty ? ' • ${m.note}' : ''}',
                                      style: theme.textTheme.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: () => widget.controller
                                        .deleteCashDrawerMovement(m.id),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    strings.shiftExpectedCashLabel,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    formatMoney(expectedCash, currency),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                strings.shiftCashFormulaHintFull,
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _actualCashCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: strings.shiftActualCashLabel,
                            hintText: strings.shiftActualCashHint,
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixText: currency.symbol,
                            suffixIcon: _actualCashCtrl.text.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      _actualCashCtrl.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.clear, size: 18),
                                  )
                                : null,
                          ),
                        ),
                        if (diff != null) ...[
                          const SizedBox(height: 10),
                          _CashDiffBanner(
                            diff: diff,
                            currency: currency,
                            strings: strings,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          await WhatsAppLauncher.openChatOrShare(
                            phone: widget.controller.shopPhone,
                            message: reportText,
                            subject: strings.shiftClosingTitle,
                          );
                        },
                        icon: const Icon(Icons.share_outlined),
                        label: Text(
                          strings.shareWhatsAppBtn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: strings.copyTextBtn,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: reportText),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(strings.copiedToClipboardMsg),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_outlined),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShiftStat extends StatelessWidget {
  const _ShiftStat({required this.label, required this.value});

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

class _CashDiffBanner extends StatelessWidget {
  const _CashDiffBanner({
    required this.diff,
    required this.currency,
    required this.strings,
  });

  final double diff;
  final AppCurrency currency;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final isExact = diff.abs() < 0.01;
    final isSurplus = diff > 0;
    final Color bg;
    final Color fg;
    final IconData icon;
    final String text;

    if (isExact) {
      bg = Colors.green.shade100;
      fg = Colors.green.shade900;
      icon = Icons.check_circle_outline;
      text = strings.shiftExactMatchLabel;
    } else if (isSurplus) {
      bg = Colors.blue.shade100;
      fg = Colors.blue.shade900;
      icon = Icons.trending_up;
      text = strings.shiftSurplusLabel(formatMoney(diff, currency));
    } else {
      bg = Colors.red.shade100;
      fg = Colors.red.shade900;
      icon = Icons.warning_amber_rounded;
      text = strings.shiftShortageLabel(formatMoney(-diff, currency));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
