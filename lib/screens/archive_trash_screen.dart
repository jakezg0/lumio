import 'package:flutter/material.dart';

import '../models/product.dart';
import '../state/shop_controller.dart';
import '../widgets/formatters.dart';

class ArchiveTrashScreen extends StatefulWidget {
  const ArchiveTrashScreen({super.key, required this.controller});

  final ShopController controller;

  @override
  State<ArchiveTrashScreen> createState() => _ArchiveTrashScreenState();
}

class _ArchiveTrashScreenState extends State<ArchiveTrashScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_handleTabChange);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging && _selectionMode) {
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
    } else {
      setState(() {});
    }
  }

  void _enterSelectionMode([String? initialId]) {
    setState(() {
      _selectionMode = true;
      if (initialId != null) {
        _selectedIds.add(initialId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  Future<void> _confirmEmptyTrash(BuildContext context) async {
    final strings = widget.controller.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.emptyTrashTitle),
        content: Text(strings.emptyTrashBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.emptyTrashAction),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.emptyTrash();
    }
  }

  Future<void> _moveSelectedTrashToArchive() async {
    if (_selectedIds.isEmpty) return;
    final strings = widget.controller.strings;
    final moved =
        await widget.controller.moveTrashedProductsToArchive(_selectedIds);
    _exitSelectionMode();
    if (mounted && moved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.movedCountToArchiveMsg(moved))),
      );
    }
  }

  Future<void> _restoreSelectedTrash() async {
    if (_selectedIds.isEmpty) return;
    final strings = widget.controller.strings;
    final restored =
        await widget.controller.restoreTrashedProducts(_selectedIds);
    _exitSelectionMode();
    if (mounted && restored > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.restoredMsg)),
      );
    }
  }

  Future<void> _deleteSelectedTrashForever() async {
    if (_selectedIds.isEmpty) return;
    await widget.controller.deleteTrashedProductsPermanently(_selectedIds);
    _exitSelectionMode();
  }

  Future<void> _restoreSelectedArchive() async {
    if (_selectedIds.isEmpty) return;
    final strings = widget.controller.strings;
    final restored = await widget.controller.unarchiveProducts(_selectedIds);
    _exitSelectionMode();
    if (mounted && restored > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.restoredMsg)),
      );
    }
  }

  Future<void> _moveSelectedArchiveToTrash() async {
    if (_selectedIds.isEmpty) return;
    final strings = widget.controller.strings;
    final moved = await widget.controller.moveProductsToTrash(_selectedIds);
    _exitSelectionMode();
    if (mounted && moved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.movedCountToTrashMsg(moved))),
      );
    }
  }

  Future<String?> _promptTargetFolder({String? excludeCategory}) {
    final strings = widget.controller.strings;
    final folderSet = <String>{
      ...widget.controller.categories,
      for (final p in widget.controller.archivedProducts)
        p.category.trim().isEmpty ? 'General' : p.category.trim(),
    };
    folderSet.remove(excludeCategory);
    final folders = folderSet.toList()..sort();
    return showDialog<String>(
      context: context,
      builder: (_) => _ArchiveTargetFolderDialog(
        title: strings.chooseTargetGroupTitle,
        newGroupHint: strings.newGroupHint,
        exampleHint: strings.newGroupExampleHint,
        cancelLabel: strings.cancel,
        confirmLabel: strings.createAndMoveAction,
        categories: folders,
      ),
    );
  }

  Future<void> _moveProductsToFolder(
    Iterable<String> productIds, {
    String? excludeCategory,
    bool exitSelection = false,
  }) async {
    final ids = productIds.toList();
    if (ids.isEmpty) return;
    final strings = widget.controller.strings;
    final target = await _promptTargetFolder(excludeCategory: excludeCategory);
    if (target == null || target.trim().isEmpty) return;
    final moved = await widget.controller.moveProductsToCategory(ids, target);
    if (exitSelection) _exitSelectionMode();
    if (mounted && moved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.movedCountToGroupMsg(moved, target.trim())),
        ),
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
        final archivedProducts = widget.controller.archivedProducts;
        final archivedSales = widget.controller.archivedSales;
        final trashedProducts = widget.controller.trashedProducts;
        final trashedSales = widget.controller.trashedSales;
        final trashedExpenses = widget.controller.trashedExpenses;

        final isTrashTab = _tabController.index == 1;
        final activeProductIds = (isTrashTab ? trashedProducts : archivedProducts)
            .map((p) => p.id)
            .toList();
        final allSelected = activeProductIds.isNotEmpty &&
            activeProductIds.every((id) => _selectedIds.contains(id));

        return Scaffold(
          appBar: _selectionMode
              ? AppBar(
                  leading: IconButton(
                    onPressed: _exitSelectionMode,
                    icon: const Icon(Icons.close),
                  ),
                  title: Text(strings.selectedCountLabel(_selectedIds.length)),
                  actions: [
                    TextButton(
                      onPressed: activeProductIds.isEmpty
                          ? null
                          : () {
                              setState(() {
                                if (allSelected) {
                                  _selectedIds.removeAll(activeProductIds);
                                } else {
                                  _selectedIds.addAll(activeProductIds);
                                }
                              });
                            },
                      child: Text(
                        allSelected
                            ? strings.clearSelection
                            : strings.selectAllVisible,
                      ),
                    ),
                    if (isTrashTab) ...[
                      IconButton(
                        tooltip: strings.archiveAction,
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : _moveSelectedTrashToArchive,
                        icon: const Icon(Icons.archive_outlined),
                      ),
                      IconButton(
                        tooltip: strings.restoreAction,
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : _restoreSelectedTrash,
                        icon: const Icon(Icons.restore_from_trash),
                      ),
                      IconButton(
                        tooltip: strings.deleteForeverAction,
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : _deleteSelectedTrashForever,
                        icon: const Icon(Icons.delete_forever_outlined),
                      ),
                    ] else ...[
                      IconButton(
                        tooltip: strings.moveToGroupAction,
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : () => _moveProductsToFolder(
                                  _selectedIds,
                                  exitSelection: true,
                                ),
                        icon: const Icon(Icons.drive_file_move_outlined),
                      ),
                      IconButton(
                        tooltip: strings.restoreAction,
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : _restoreSelectedArchive,
                        icon: const Icon(Icons.restore),
                      ),
                      IconButton(
                        tooltip: strings.moveToTrashAction,
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : _moveSelectedArchiveToTrash,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ],
                  bottom: TabBar(
                    controller: _tabController,
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.archive_outlined),
                        text:
                            '${strings.archiveTab} (${widget.controller.archiveCount})',
                      ),
                      Tab(
                        icon: const Icon(Icons.delete_outline),
                        text:
                            '${strings.trashTab} (${widget.controller.trashCount})',
                      ),
                    ],
                  ),
                )
              : AppBar(
                  title: Text(strings.archiveAndTrash),
                  actions: [
                    if (activeProductIds.isNotEmpty)
                      IconButton(
                        tooltip: strings.selectItemsBtn,
                        onPressed: () => _enterSelectionMode(),
                        icon: const Icon(Icons.checklist),
                      ),
                    if (widget.controller.trashCount > 0)
                      IconButton(
                        tooltip: strings.emptyTrashAction,
                        onPressed: () => _confirmEmptyTrash(context),
                        icon: const Icon(Icons.delete_forever_outlined),
                      ),
                  ],
                  bottom: TabBar(
                    controller: _tabController,
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.archive_outlined),
                        text:
                            '${strings.archiveTab} (${widget.controller.archiveCount})',
                      ),
                      Tab(
                        icon: const Icon(Icons.delete_outline),
                        text:
                            '${strings.trashTab} (${widget.controller.trashCount})',
                      ),
                    ],
                  ),
                ),
          body: TabBarView(
            controller: _tabController,
            children: [
              (archivedProducts.isEmpty && archivedSales.isEmpty)
                  ? Center(child: Text(strings.archiveEmpty))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (archivedProducts.isNotEmpty) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${strings.archivedProductsHeader} (${archivedProducts.length})',
                                  style: Theme.of(context).textTheme.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () async {
                                  final restored = await widget.controller
                                      .restoreAllProductsFromArchive();
                                  if (context.mounted && restored > 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(strings.restoredMsg),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.restore),
                                label: Text(strings.restoreAllFromTrashAction),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...() {
                            final grouped = <String, List<Product>>{};
                            for (final p in archivedProducts) {
                              final cat = p.category.trim().isEmpty
                                  ? 'General'
                                  : p.category.trim();
                              grouped.putIfAbsent(cat, () => []).add(p);
                            }
                            final sortedCats = grouped.keys.toList()
                              ..sort((a, b) => a
                                  .toLowerCase()
                                  .compareTo(b.toLowerCase()));
                            final theme = Theme.of(context);
                            return [
                              for (final cat in sortedCats)
                                Builder(
                                  builder: (ctx) {
                                    final items = grouped[cat]!;
                                    final itemIds =
                                        items.map((p) => p.id).toList();
                                    final allFolderSelected = itemIds.isNotEmpty &&
                                        itemIds.every(_selectedIds.contains);
                                    final totalUnits = items.fold<int>(
                                      0,
                                      (sum, p) => sum + p.stock,
                                    );
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      clipBehavior: Clip.antiAlias,
                                      child: ExpansionTile(
                                        key: PageStorageKey<String>(
                                          'archive_folder_$cat',
                                        ),
                                        leading: _selectionMode
                                            ? Checkbox(
                                                value: allFolderSelected,
                                                onChanged: (_) {
                                                  setState(() {
                                                    if (allFolderSelected) {
                                                      _selectedIds
                                                          .removeAll(itemIds);
                                                    } else {
                                                      _selectedIds
                                                          .addAll(itemIds);
                                                    }
                                                  });
                                                },
                                              )
                                            : Icon(
                                                Icons.folder_outlined,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                        title: Text(
                                          cat,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '${items.length} • ${strings.unitsCount(totalUnits)}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        trailing: _selectionMode
                                            ? null
                                            : PopupMenuButton<String>(
                                                onSelected: (value) async {
                                                  if (value == 'move') {
                                                    await _moveProductsToFolder(
                                                      itemIds,
                                                      excludeCategory: cat,
                                                    );
                                                  } else if (value ==
                                                      'restore') {
                                                    final restored = await widget
                                                        .controller
                                                        .unarchiveProducts(
                                                      itemIds,
                                                    );
                                                    if (ctx.mounted &&
                                                        restored > 0) {
                                                      ScaffoldMessenger.of(ctx)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            strings.restoredMsg,
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  } else if (value == 'trash') {
                                                    final moved = await widget
                                                        .controller
                                                        .moveProductsToTrash(
                                                      itemIds,
                                                    );
                                                    if (ctx.mounted &&
                                                        moved > 0) {
                                                      ScaffoldMessenger.of(ctx)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            strings
                                                                .movedCountToTrashMsg(
                                                              moved,
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  }
                                                },
                                                itemBuilder: (_) => [
                                                  PopupMenuItem(
                                                    value: 'move',
                                                    child: ListTile(
                                                      dense: true,
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                      leading: const Icon(
                                                        Icons
                                                            .drive_file_move_outlined,
                                                      ),
                                                      title: Text(
                                                        strings
                                                            .moveToGroupAction,
                                                      ),
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'restore',
                                                    child: ListTile(
                                                      dense: true,
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                      leading: const Icon(
                                                        Icons.restore,
                                                      ),
                                                      title: Text(
                                                        strings.restoreAction,
                                                      ),
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'trash',
                                                    child: ListTile(
                                                      dense: true,
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                      leading: Icon(
                                                        Icons.delete_outline,
                                                        color: theme
                                                            .colorScheme.error,
                                                      ),
                                                      title: Text(
                                                        strings
                                                            .moveToTrashAction,
                                                        style: TextStyle(
                                                          color: theme
                                                              .colorScheme
                                                              .error,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                        children: [
                                          const Divider(height: 1),
                                          for (final product in items)
                                            ListTile(
                                              dense: true,
                                              leading: _selectionMode
                                                  ? Checkbox(
                                                      value: _selectedIds
                                                          .contains(product.id),
                                                      onChanged: (_) =>
                                                          _toggleSelected(
                                                        product.id,
                                                      ),
                                                    )
                                                  : null,
                                              onTap: _selectionMode
                                                  ? () => _toggleSelected(
                                                        product.id,
                                                      )
                                                  : null,
                                              onLongPress: _selectionMode
                                                  ? null
                                                  : () => _enterSelectionMode(
                                                        product.id,
                                                      ),
                                              title: Text(product.name),
                                              subtitle: Text(
                                                '${formatMoney(product.sellPrice, currency)} • ${strings.stockCountLabel(product.stock)}',
                                              ),
                                              trailing: _selectionMode
                                                  ? null
                                                  : Wrap(
                                                      spacing: 0,
                                                      children: [
                                                        IconButton(
                                                          tooltip: strings
                                                              .moveToGroupAction,
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          onPressed: () =>
                                                              _moveProductsToFolder(
                                                            [product.id],
                                                            excludeCategory:
                                                                cat,
                                                          ),
                                                          icon: const Icon(
                                                            Icons
                                                                .drive_file_move_outlined,
                                                            size: 20,
                                                          ),
                                                        ),
                                                        IconButton(
                                                          tooltip: strings
                                                              .restoreAction,
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          onPressed: () async {
                                                            await widget
                                                                .controller
                                                                .unarchiveProduct(
                                                              product.id,
                                                            );
                                                            if (ctx.mounted) {
                                                              ScaffoldMessenger
                                                                      .of(ctx)
                                                                  .showSnackBar(
                                                                SnackBar(
                                                                  content: Text(
                                                                    strings
                                                                        .restoredMsg,
                                                                  ),
                                                                ),
                                                              );
                                                            }
                                                          },
                                                          icon: const Icon(
                                                            Icons.restore,
                                                            size: 20,
                                                          ),
                                                        ),
                                                        IconButton(
                                                          tooltip: strings
                                                              .moveToTrashAction,
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          onPressed: () => widget
                                                              .controller
                                                              .moveProductToTrash(
                                                            product.id,
                                                          ),
                                                          icon: const Icon(
                                                            Icons
                                                                .delete_outline,
                                                            size: 20,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ];
                          }(),
                          const SizedBox(height: 16),
                        ],
                        if (archivedSales.isNotEmpty) ...[
                          Text(
                            strings.archivedSalesHeader,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          for (final sale in archivedSales)
                            Card(
                              child: ListTile(
                                title: Text(formatMoney(sale.total, currency)),
                                subtitle: Text(
                                  '${formatDateTime(sale.createdAt)} • ${strings.unitsShort(sale.totalUnits)}',
                                ),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: strings.restoreAction,
                                      onPressed: () async {
                                        await widget.controller
                                            .unarchiveSale(sale.id);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                strings.restoredMsg,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.restore),
                                    ),
                                    IconButton(
                                      tooltip: strings.moveToTrashAction,
                                      onPressed: () => widget.controller
                                          .moveSaleToTrash(sale.id),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
              (trashedProducts.isEmpty &&
                      trashedSales.isEmpty &&
                      trashedExpenses.isEmpty)
                  ? Center(child: Text(strings.trashEmpty))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (trashedProducts.isNotEmpty) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${strings.trashedProductsHeader} (${trashedProducts.length})',
                                  style: Theme.of(context).textTheme.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () => _enterSelectionMode(),
                                icon: const Icon(Icons.checklist),
                                label: Text(strings.selectItemsBtn),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (final product in trashedProducts)
                            Card(
                              child: ListTile(
                                leading: _selectionMode
                                    ? Checkbox(
                                        value:
                                            _selectedIds.contains(product.id),
                                        onChanged: (_) =>
                                            _toggleSelected(product.id),
                                      )
                                    : null,
                                onTap: _selectionMode
                                    ? () => _toggleSelected(product.id)
                                    : null,
                                onLongPress: _selectionMode
                                    ? null
                                    : () => _enterSelectionMode(product.id),
                                title: Text(product.name),
                                subtitle: Text(
                                  '${product.category} • ${formatMoney(product.sellPrice, currency)} • ${strings.stockCountLabel(product.stock)}',
                                ),
                                trailing: _selectionMode
                                    ? null
                                    : Wrap(
                                        spacing: 0,
                                        children: [
                                          IconButton(
                                            tooltip: strings.archiveAction,
                                            onPressed: () async {
                                              await widget.controller
                                                  .moveTrashedProductToArchive(
                                                product.id,
                                              );
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      strings.movedToArchiveMsg,
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.archive_outlined,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: strings.restoreAction,
                                            onPressed: () async {
                                              await widget.controller
                                                  .restoreProductFromTrash(
                                                product.id,
                                              );
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      strings.restoredMsg,
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.restore_from_trash,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip:
                                                strings.deleteForeverAction,
                                            onPressed: () => widget.controller
                                                .deleteProductPermanently(
                                              product.id,
                                            ),
                                            icon: const Icon(
                                              Icons.delete_forever_outlined,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          const SizedBox(height: 16),
                        ],
                        if (trashedSales.isNotEmpty) ...[
                          Text(
                            strings.trashedSalesHeader,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          for (final sale in trashedSales)
                            Card(
                              child: ListTile(
                                title: Text(formatMoney(sale.total, currency)),
                                subtitle: Text(
                                  '${formatDateTime(sale.createdAt)} • ${strings.unitsShort(sale.totalUnits)}',
                                ),
                                trailing: Wrap(
                                  spacing: 0,
                                  children: [
                                    IconButton(
                                      tooltip: strings.archiveAction,
                                      onPressed: () async {
                                        await widget.controller
                                            .moveTrashedSaleToArchive(sale.id);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                strings.movedToArchiveMsg,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.archive_outlined),
                                    ),
                                    IconButton(
                                      tooltip: strings.restoreAction,
                                      onPressed: () async {
                                        await widget.controller
                                            .restoreSaleFromTrash(sale.id);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                strings.restoredMsg,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.restore_from_trash,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: strings.deleteForeverAction,
                                      onPressed: () => widget.controller
                                          .deleteSalePermanently(sale.id),
                                      icon: const Icon(
                                        Icons.delete_forever_outlined,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                        ],
                        if (trashedExpenses.isNotEmpty) ...[
                          Text(
                            strings.trashedExpensesHeader,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          for (final expense in trashedExpenses)
                            Card(
                              child: ListTile(
                                title: Text(expense.title),
                                subtitle: Text(
                                  '${formatMoney(expense.amount, currency)} • ${formatDateTime(expense.createdAt)}',
                                ),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: strings.restoreAction,
                                      onPressed: () async {
                                        await widget.controller
                                            .restoreExpenseFromTrash(
                                          expense.id,
                                        );
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                strings.restoredMsg,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.restore_from_trash,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: strings.deleteForeverAction,
                                      onPressed: () => widget.controller
                                          .deleteExpensePermanently(expense.id),
                                      icon: const Icon(
                                        Icons.delete_forever_outlined,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
            ],
          ),
        );
      },
    );
  }
}

class _ArchiveTargetFolderDialog extends StatefulWidget {
  const _ArchiveTargetFolderDialog({
    required this.title,
    required this.newGroupHint,
    required this.exampleHint,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.categories,
  });

  final String title;
  final String newGroupHint;
  final String exampleHint;
  final String cancelLabel;
  final String confirmLabel;
  final List<String> categories;

  @override
  State<_ArchiveTargetFolderDialog> createState() =>
      _ArchiveTargetFolderDialogState();
}

class _ArchiveTargetFolderDialogState
    extends State<_ArchiveTargetFolderDialog> {
  final TextEditingController _groupCtrl = TextEditingController();

  @override
  void dispose() {
    _groupCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _groupCtrl,
                decoration: InputDecoration(
                  labelText: widget.newGroupHint,
                  hintText: widget.exampleHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.of(context).pop(value.trim());
                  }
                },
              ),
              if (widget.categories.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final cat in widget.categories)
                      ActionChip(
                        avatar: const Icon(Icons.folder_outlined, size: 16),
                        label: Text(cat),
                        onPressed: () => Navigator.of(context).pop(cat),
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
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () {
            final val = _groupCtrl.text.trim();
            if (val.isNotEmpty) {
              Navigator.of(context).pop(val);
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
