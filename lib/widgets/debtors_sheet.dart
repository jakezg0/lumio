import 'package:flutter/material.dart';

import '../state/shop_controller.dart';
import '../widgets/formatters.dart';

class DebtorsSheet extends StatelessWidget {
  const DebtorsSheet({super.key, required this.controller});

  final ShopController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final strings = controller.strings;
        final currency = controller.currency;
        final debtors = controller.debtors;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    strings.debtorsSummaryBtn,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    formatMoney(controller.totalUnpaidDebt, currency),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ],
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
                      final history = debtor.sales
                          .expand((s) => s.paymentHistory)
                          .toList()
                        ..sort((a, b) => b.paidAt.compareTo(a.paidAt));

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
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '${strings.ordersAndDue(debtor.sales.length, dueText)}\n'
                            '${formatMoney(debtor.totalDebt, currency)}',
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: () async {
                              await controller.markAllCustomerDebtsPaid(
                                debtor.customerName,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(strings.paymentRecorded),
                                  ),
                                );
                              }
                            },
                            child: Text(strings.payAllAction),
                          ),
                          children: [
                            for (final sale in debtor.sales)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${formatDateTime(sale.createdAt)} • ${formatMoney(sale.total, currency)}',
                                ),
                                subtitle: Text(
                                  '${strings.paidAmountLabel}: ${formatMoney(sale.paidAmount, currency)} • '
                                  '${strings.remainingDebtLabel}: ${formatMoney(sale.remainingDebt, currency)}',
                                ),
                              ),
                            if (history.isNotEmpty) ...[
                              const Divider(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  strings.paidAmountLabel,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                              for (final p in history)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        formatDateTime(p.paidAt),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
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
