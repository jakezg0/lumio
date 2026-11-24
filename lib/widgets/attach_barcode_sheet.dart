import 'package:flutter/material.dart';

import '../models/product.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';

Future<Product?> showAttachBarcodeSheet(
  BuildContext context, {
  required ShopController controller,
  required String barcode,
}) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AttachBarcodeSheet(
      controller: controller,
      barcode: barcode.trim(),
    ),
  );
}

class _AttachBarcodeSheet extends StatefulWidget {
  const _AttachBarcodeSheet({
    required this.controller,
    required this.barcode,
  });

  final ShopController controller;
  final String barcode;

  @override
  State<_AttachBarcodeSheet> createState() => _AttachBarcodeSheetState();
}

class _AttachBarcodeSheetState extends State<_AttachBarcodeSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _saving = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _attachTo(Product product) async {
    if (_saving) return;
    setState(() => _saving = true);
    final strings = widget.controller.strings;
    final existing = widget.controller.findProductBySku(widget.barcode);
    if (existing != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.barcodeAlreadyLinkedMsg(existing.name))),
      );
      Navigator.of(context).pop(existing);
      return;
    }

    final updated = await widget.controller.attachBarcodeToProduct(
      product.id,
      widget.barcode,
    );
    if (!mounted) return;
    if (updated != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.barcodeLinkedMsg(widget.barcode, updated.name)),
        ),
      );
    }
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final products = widget.controller.products.where((p) {
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.nomenclature.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
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
            Text(
              strings.attachBarcodeTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.qr_code_2, size: 18),
                label: Text(strings.attachBarcodeSubtitle(widget.barcode)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: strings.searchGoodsHint,
                isDense: true,
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: products.isEmpty
                  ? Center(child: Text(strings.noMatchingProducts))
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: products.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final p = products[index];
                        final subtitleParts = <String>[
                          p.category,
                          if (p.sku.trim().isNotEmpty) 'SKU: ${p.sku}',
                          formatMoney(p.sellPrice, widget.controller.currency),
                        ];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          title: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            subtitleParts.join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.link),
                          onTap: _saving ? null : () => _attachTo(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
