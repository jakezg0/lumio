import 'package:flutter/material.dart';

import '../models/product.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';
import 'product_form_sheet.dart';

class CatalogMaintenanceSheet extends StatelessWidget {
  const CatalogMaintenanceSheet({super.key, required this.controller});

  final ShopController controller;

  Future<String?> _promptArchiveOrTrashDestination(
    BuildContext context,
    String title,
    int count,
  ) {
    final strings = controller.strings;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(strings.chooseDestinationBody(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(dialogContext).pop('archive'),
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: Text(strings.archiveAction),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop('trash'),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(strings.moveToTrashAction),
          ),
        ],
      ),
    );
  }

  Future<void> _openDuplicateChecker(BuildContext context) async {
    controller.trackFeatureUsage(FeatureUsageKeys.duplicateCheck);
    final groups = controller.findLocalDuplicateGroups();
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.strings.noDuplicatesFoundMsg)),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LocalDuplicatesSheet(
        controller: controller,
        onEditProduct: (product) {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => ProductFormSheet(
              controller: controller,
              existing: product,
            ),
          );
        },
      ),
    );
  }

  Future<void> _promptDeleteGroupToTrash(BuildContext context) async {
    final strings = controller.strings;
    final categories = controller.categories;
    if (categories.isEmpty) return;

    final targetCategory = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(strings.chooseGroupToDelete),
        children: [
          for (final cat in categories)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(cat),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(cat)),
                  Text(
                    '${controller.products.where((p) => p.category == cat).length}',
                    style: Theme.of(dialogContext).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (targetCategory == null || !context.mounted) return;

    final count =
        controller.products.where((p) => p.category == targetCategory).length;
    if (count == 0) {
      await controller.deleteEmptyCategory(targetCategory);
      return;
    }

    final destination = await _promptArchiveOrTrashDestination(
      context,
      targetCategory,
      count,
    );
    if (destination == null || !context.mounted) return;

    if (destination == 'archive') {
      final moved = await controller.archiveCategory(targetCategory);
      if (context.mounted && moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.movedCountToArchiveMsg(moved))),
        );
      }
    } else {
      final moved = await controller.moveCategoryToTrash(targetCategory);
      if (context.mounted && moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.movedCountToTrashMsg(moved))),
        );
      }
    }
  }

  Future<void> _confirmMoveAllToTrash(BuildContext context) async {
    final strings = controller.strings;
    final count = controller.products.length;
    if (count == 0) return;

    final destination = await _promptArchiveOrTrashDestination(
      context,
      strings.chooseDestinationTitle,
      count,
    );
    if (destination == null || !context.mounted) return;

    if (destination == 'archive') {
      final moved = await controller.archiveAllProducts();
      if (context.mounted && moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.movedCountToArchiveMsg(moved))),
        );
      }
    } else {
      final moved = await controller.moveAllProductsToTrash();
      if (context.mounted && moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.movedCountToTrashMsg(moved))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final strings = controller.strings;
        final hasProducts = controller.products.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.catalogMaintenanceTitle,
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
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.copy_all_outlined),
                  title: Text(strings.duplicateCheckBtn),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  enabled: hasProducts,
                  onTap: hasProducts
                      ? () => _openDuplicateChecker(context)
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                strings.dangerBulkActionsTitle,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: theme.colorScheme.error.withValues(alpha: 0.4),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.folder_delete_outlined),
                      title: Text(strings.groupArchiveOrTrashAction),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      enabled: hasProducts && controller.categories.isNotEmpty,
                      onTap: hasProducts && controller.categories.isNotEmpty
                          ? () => _promptDeleteGroupToTrash(context)
                          : null,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.delete_sweep_outlined,
                        color: hasProducts
                            ? theme.colorScheme.error
                            : theme.disabledColor,
                      ),
                      title: Text(
                        strings.allArchiveOrTrashAction,
                        style: TextStyle(
                          color: hasProducts
                              ? theme.colorScheme.error
                              : theme.disabledColor,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      enabled: hasProducts,
                      onTap: hasProducts
                          ? () => _confirmMoveAllToTrash(context)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class LocalDuplicatesSheet extends StatelessWidget {
  const LocalDuplicatesSheet({
    super.key,
    required this.controller,
    required this.onEditProduct,
  });

  final ShopController controller;
  final ValueChanged<Product> onEditProduct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final strings = controller.strings;
        final currency = controller.currency;
        final groups = controller.findLocalDuplicateGroups();

        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.80,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.phoneDuplicatesCount(groups.length),
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
                Expanded(
                  child: groups.isEmpty
                      ? Center(child: Text(strings.noDuplicatesFoundMsg))
                      : ListView.separated(
                          itemCount: groups.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final group = groups[index];
                            return Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group.reason,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    for (final product in group.products)
                                      ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(product.name),
                                        subtitle: Text(
                                          [
                                            product.category,
                                            if (product.sku.isNotEmpty)
                                              'SKU: ${product.sku}',
                                            formatMoney(
                                              product.sellPrice,
                                              currency,
                                            ),
                                            strings.stockCountLabel(
                                              product.stock,
                                            ),
                                          ].join(' • '),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: strings.edit,
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 20,
                                              ),
                                              onPressed: () =>
                                                  onEditProduct(product),
                                            ),
                                            IconButton(
                                              tooltip:
                                                  strings.moveToTrashAction,
                                              icon: Icon(
                                                Icons.delete_outline,
                                                size: 20,
                                                color: theme.colorScheme.error,
                                              ),
                                              onPressed: () async {
                                                await controller
                                                    .moveProductToTrash(
                                                  product.id,
                                                );
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        strings
                                                            .movedToTrashMsg,
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
                                          ],
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
