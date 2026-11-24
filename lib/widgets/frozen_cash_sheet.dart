import 'package:flutter/material.dart';

import '../models/product.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';

enum _FrozenCashRange { days30Plus, days30To60, days60Plus }

class FrozenCashSheet extends StatefulWidget {
  const FrozenCashSheet({
    super.key,
    required this.controller,
    required this.onEditPrice,
  });

  final ShopController controller;
  final void Function(Product product) onEditPrice;

  @override
  State<FrozenCashSheet> createState() => _FrozenCashSheetState();
}

class _FrozenCashSheetState extends State<FrozenCashSheet> {
  _FrozenCashRange _range = _FrozenCashRange.days30Plus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;

        final (minDays, maxDays) = switch (_range) {
          _FrozenCashRange.days30Plus => (30, null),
          _FrozenCashRange.days30To60 => (30, 60),
          _FrozenCashRange.days60Plus => (60, null),
        };

        final summary = widget.controller.frozenCashSummary(
          minIdleDays: minDays,
          maxIdleDays: maxDays,
          limit: 10,
        );
        final items = summary.items;

        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.84,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.savings_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.frozenCashTitle,
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: strings.close,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  strings.frozenCashSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(strings.frozenCashFilter30Plus),
                      selected: _range == _FrozenCashRange.days30Plus,
                      onSelected: (_) => setState(
                        () => _range = _FrozenCashRange.days30Plus,
                      ),
                    ),
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(strings.frozenCashFilter30To60),
                      selected: _range == _FrozenCashRange.days30To60,
                      onSelected: (_) => setState(
                        () => _range = _FrozenCashRange.days30To60,
                      ),
                    ),
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(strings.frozenCashFilter60Plus),
                      selected: _range == _FrozenCashRange.days60Plus,
                      onSelected: (_) => setState(
                        () => _range = _FrozenCashRange.days60Plus,
                      ),
                    ),
                  ],
                ),
                if (summary.totalCount > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.ac_unit_rounded,
                          size: 20,
                          color: Colors.amber.shade900,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings.frozenCashTotalLabel(
                              formatMoney(summary.totalFrozenValue, currency),
                              summary.totalCount,
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 48,
                                  color: Colors.green.shade700,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  strings.frozenCashEmptyMsg,
                                  style: theme.textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final p = item.product;
                            return Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${index + 1}. ${p.name}',
                                                style: theme
                                                    .textTheme.titleSmall
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${p.category.isNotEmpty ? '${p.category} • ' : ''}'
                                                '${strings.stockCountLabel(p.stock)} • '
                                                '${strings.sellShort}: ${formatMoney(p.sellPrice, currency)}',
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
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme.errorContainer,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            formatMoney(
                                              item.frozenValue,
                                              currency,
                                            ),
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                              color: theme.colorScheme
                                                  .onErrorContainer,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.schedule_outlined,
                                          size: 14,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          strings.frozenCashDaysIdle(
                                            item.daysWithoutSales,
                                            item.hasEverSold,
                                          ),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade50,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            strings.frozenCashHintBadge,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: Colors.teal.shade900,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton.tonalIcon(
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          widget.onEditPrice(p);
                                        },
                                        icon: const Icon(
                                          Icons.local_offer_outlined,
                                          size: 16,
                                        ),
                                        label:
                                            Text(strings.frozenCashActionBtn),
                                      ),
                                    ),
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
