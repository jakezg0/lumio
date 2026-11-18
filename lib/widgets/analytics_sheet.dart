import 'package:flutter/material.dart';

import '../state/shop_controller.dart';
import 'formatters.dart';

class AnalyticsSheet extends StatelessWidget {
  const AnalyticsSheet({
    super.key,
    required this.controller,
    required this.filter,
  });

  final ShopController controller;
  final SalesDateFilter filter;

  @override
  Widget build(BuildContext context) {
    final strings = controller.strings;
    final currency = controller.currency;
    final topProducts = controller.topSellingProducts(filter);
    final slowMovers = controller.slowMovingProducts(filter);
    final hideProfit = controller.cashierMode;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.analyticsBtn,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              strings.topSellingHeader,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            if (topProducts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(strings.noAnalyticsData),
              )
            else
              for (final stat in topProducts.take(10))
                ListTile(
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
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              for (final product in slowMovers.take(10))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(product.name),
                  subtitle: Text(
                    '${product.category} • ${strings.stockCountLabel(product.stock)}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
