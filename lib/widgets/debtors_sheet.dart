import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/shop_controller.dart';
import '../widgets/formatters.dart';

class DebtorsSheet extends StatefulWidget {
  const DebtorsSheet({super.key, required this.controller});

  final ShopController controller;

  @override
  State<DebtorsSheet> createState() => _DebtorsSheetState();
}

class _DebtorsSheetState extends State<DebtorsSheet> {
  bool _showAllHistory = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;
        final debtors = _showAllHistory
            ? widget.controller.allDebtCustomers
            : widget.controller.debtors;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      strings.debtorsSummaryBtn,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatMoney(widget.controller.totalUnpaidDebt, currency),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(
                      '${strings.activeDebtorsFilter} (${widget.controller.debtors.length})',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(
                      '${strings.allDebtCustomersFilter} (${widget.controller.allDebtCustomers.length})',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {_showAllHistory},
                onSelectionChanged: (val) =>
                    setState(() => _showAllHistory = val.first),
              ),
              const SizedBox(height: 12),
              if (debtors.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(strings.noDebtorsMsg)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 460),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: debtors.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final debtor = debtors[index];
                      final dueText = debtor.earliestDueDate != null
                          ? formatDate(debtor.earliestDueDate!)
                          : null;
                      final displaySales = _showAllHistory
                          ? debtor.allDebtSales
                          : debtor.sales;
                      final hasDebt = debtor.totalDebt > 0.009;

                      return Card(
                        margin: EdgeInsets.zero,
                        color: debtor.hasOverdue
                            ? Theme.of(context)
                                .colorScheme
                                .errorContainer
                                .withValues(alpha: 0.35)
                            : null,
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
                                  debtor.customerName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (debtor.hasOverdue)
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
                                    strings.overdueBadge,
                                    style:
                                        Theme.of(context).textTheme.labelSmall,
                                  ),
                                )
                              else if (!hasDebt)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    strings.debtPaidBadge,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: Colors.green.shade900),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (debtor.phone.isNotEmpty)
                                InkWell(
                                  onTap: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: debtor.phone),
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
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.phone_outlined,
                                          size: 14,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          debtor.phone,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              Text(
                                strings.debtPurchasesCountLabel(
                                  debtor.totalDebtPurchasesCount,
                                  debtor.sales.length,
                                ),
                              ),
                              if (hasDebt)
                                Text(
                                  '${formatMoney(debtor.totalDebt, currency)}'
                                  '${dueText != null ? ' • ${strings.dueDateValue(dueText)}' : ''}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                          trailing: hasDebt
                              ? FilledButton.tonal(
                                  onPressed: () async {
                                    await widget.controller
                                        .markAllCustomerDebtsPaid(
                                      debtor.customerName,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(strings.paymentRecorded),
                                        ),
                                      );
                                    }
                                  },
                                  child: Text(strings.payAllAction),
                                )
                              : null,
                          children: [
                            for (final sale in displaySales)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${formatDateTime(sale.createdAt)} • #${sale.receiptCode} • ${formatMoney(sale.total, currency)}',
                                ),
                                subtitle: Text(
                                  sale.isPaid
                                      ? strings.paidBadge
                                      : '${strings.paidAmountLabel}: ${formatMoney(sale.paidAmount, currency)} • '
                                          '${strings.remainingDebtLabel}: ${formatMoney(sale.remainingDebt, currency)}',
                                ),
                              ),
                            if (debtor.repayments.isNotEmpty) ...[
                              const Divider(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  strings.debtRepaymentsHeader,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              for (final p in debtor.repayments)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${formatDateTime(p.date)} • #${p.receiptCode}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
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
