import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/product.dart';
import '../services/catalog_health_service.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';

class CatalogHealthSheet extends StatefulWidget {
  const CatalogHealthSheet({
    super.key,
    required this.controller,
    required this.onEditProduct,
  });

  final ShopController controller;
  final ValueChanged<Product> onEditProduct;

  @override
  State<CatalogHealthSheet> createState() => _CatalogHealthSheetState();
}

class _CatalogHealthSheetState extends State<CatalogHealthSheet> {
  CatalogHealthIssueType? _selectedType;

  String _typeLabel(CatalogHealthIssueType type, AppStrings strings) {
    switch (type) {
      case CatalogHealthIssueType.emptyName:
        return strings.healthEmptyName;
      case CatalogHealthIssueType.zeroPrice:
        return strings.healthZeroPrice;
      case CatalogHealthIssueType.sellBelowCost:
        return strings.healthSellBelowCost;
      case CatalogHealthIssueType.duplicateBarcode:
        return strings.healthDuplicateBarcode;
      case CatalogHealthIssueType.negativeStock:
        return strings.healthNegativeStock;
    }
  }

  IconData _typeIcon(CatalogHealthIssueType type) {
    switch (type) {
      case CatalogHealthIssueType.emptyName:
        return Icons.title;
      case CatalogHealthIssueType.zeroPrice:
        return Icons.money_off;
      case CatalogHealthIssueType.sellBelowCost:
        return Icons.trending_down;
      case CatalogHealthIssueType.duplicateBarcode:
        return Icons.qr_code_2;
      case CatalogHealthIssueType.negativeStock:
        return Icons.exposure_neg_1;
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
        final allIssues =
            CatalogHealthService.analyze(widget.controller.products);
        final counts = <CatalogHealthIssueType, int>{};
        for (final issue in allIssues) {
          counts[issue.type] = (counts[issue.type] ?? 0) + 1;
        }
        final filtered = _selectedType == null
            ? allIssues
            : allIssues.where((i) => i.type == _selectedType).toList();

        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.85,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        allIssues.isEmpty
                            ? strings.catalogHealthBtn
                            : strings.catalogHealthIssuesCount(allIssues.length),
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
                if (allIssues.isNotEmpty)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              '${strings.allCategory} (${allIssues.length})',
                            ),
                            selected: _selectedType == null,
                            onSelected: (_) =>
                                setState(() => _selectedType = null),
                          ),
                        ),
                        for (final type in CatalogHealthIssueType.values)
                          if ((counts[type] ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  '${_typeLabel(type, strings)} (${counts[type]})',
                                ),
                                selected: _selectedType == type,
                                onSelected: (_) =>
                                    setState(() => _selectedType = type),
                              ),
                            ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: allIssues.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_outlined,
                                size: 52,
                                color: Colors.green.shade600,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                strings.catalogHealthOkMsg,
                                style: theme.textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            final issue = filtered[index];
                            final p = issue.product;
                            final title = p.name.trim().isEmpty
                                ? '(${strings.healthEmptyName})'
                                : p.name;
                            final subtitle = switch (issue.type) {
                              CatalogHealthIssueType.sellBelowCost =>
                                '${strings.costShort}: ${formatMoney(p.costPrice, currency)} → ${strings.sellShort}: ${formatMoney(p.sellPrice, currency)}',
                              CatalogHealthIssueType.zeroPrice =>
                                '${strings.sellShort}: ${formatMoney(p.sellPrice, currency)}',
                              CatalogHealthIssueType.duplicateBarcode =>
                                '${strings.duplicateMatchBarcode}: ${issue.detail}',
                              CatalogHealthIssueType.negativeStock =>
                                strings.stockCountLabel(p.stock),
                              CatalogHealthIssueType.emptyName => p.category,
                            };

                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      theme.colorScheme.errorContainer,
                                  child: Icon(
                                    _typeIcon(issue.type),
                                    color: theme.colorScheme.onErrorContainer,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${_typeLabel(issue.type, strings)} • $subtitle',
                                ),
                                trailing: IconButton(
                                  tooltip: strings.edit,
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => widget.onEditProduct(p),
                                ),
                                onTap: () => widget.onEditProduct(p),
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
