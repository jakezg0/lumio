import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product.dart';
import '../services/export_service.dart';
import '../state/shop_controller.dart';
import 'barcode_label_sheet.dart';
import 'formatters.dart';

class PriceTagQueueSheet extends StatelessWidget {
  const PriceTagQueueSheet({super.key, required this.controller});

  final ShopController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final strings = controller.strings;
        final currency = controller.currency;
        final theme = Theme.of(context);
        final items = controller.priceTagQueueProducts;

        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                    const Icon(Icons.sell_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${strings.priceTagQueueTitle} (${items.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (items.isNotEmpty)
                      TextButton(
                        onPressed: () => controller.clearPriceTagQueue(),
                        child: Text(strings.clearPriceTagQueueBtn),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            strings.priceTagQueueEmpty,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final product = items[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              title: Text(
                                product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  formatMoney(product.sellPrice, currency),
                                  if (product.sku.trim().isNotEmpty)
                                    product.sku.trim(),
                                ].join(' • '),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton.filledTonal(
                                    tooltip: strings.barcodeLabelAction,
                                    onPressed: () {
                                      showModalBottomSheet<void>(
                                        context: context,
                                        isScrollControlled: true,
                                        useSafeArea: true,
                                        builder: (_) => BarcodeLabelSheet(
                                          controller: controller,
                                          product: product,
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.print_outlined,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    tooltip: strings.markPrintedAction,
                                    onPressed: () => controller
                                        .markPriceTagPrinted(product.id),
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => BatchPriceTagsSheet(
                          controller: controller,
                          products: items,
                        ),
                      );
                    },
                    icon: const Icon(Icons.print_outlined),
                    label: Text(
                      '${strings.printAllPriceTagsBtn} (${items.length})',
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class BatchPriceTagsSheet extends StatefulWidget {
  const BatchPriceTagsSheet({
    super.key,
    required this.controller,
    required this.products,
    this.title,
  });

  final ShopController controller;
  final List<Product> products;
  final String? title;

  @override
  State<BatchPriceTagsSheet> createState() => _BatchPriceTagsSheetState();
}

class _BatchPriceTagsSheetState extends State<BatchPriceTagsSheet> {
  bool _isThermal58x40 = false;
  bool _showShopName = true;
  bool _exporting = false;

  Future<void> _exportBatchPdf() async {
    if (widget.products.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await ExportService.buildBatchPriceTagsPdfBytes(
        products: widget.products,
        currency: widget.controller.currency,
        isThermal58x40: _isThermal58x40,
        showPrice: true,
        shopName: _showShopName ? widget.controller.shopName : '',
      );
      final formatTag = _isThermal58x40 ? '58x40' : 'A4';
      final stamp = DateTime.now().toIso8601String().split('T').first;
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: 'price_tags_${stamp}_$formatTag.pdf',
          mimeType: 'application/pdf',
        ),
      ]);
      for (final p in widget.products) {
        await widget.controller.markPriceTagPrinted(p.id);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final items = widget.products;

    return DraggableScrollableSheet(
      initialChildSize: 0.70,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                const Icon(Icons.sell_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.title ?? strings.batchPriceTagsTitle} (${items.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('A4 (3×8)')),
                ButtonSegment(value: true, label: Text('58×40')),
              ],
              selected: {_isThermal58x40},
              onSelectionChanged: (sel) {
                setState(() => _isThermal58x40 = sel.first);
              },
            ),
            if (widget.controller.shopName.trim().isNotEmpty)
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(widget.controller.shopName),
                value: _showShopName,
                onChanged: (v) => setState(() => _showShopName = v),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = items[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        formatMoney(product.sellPrice, currency),
                        if (product.sku.trim().isNotEmpty) product.sku.trim(),
                      ].join(' • '),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _exporting || items.isEmpty ? null : _exportBatchPdf,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text('${strings.printAllPriceTagsBtn} (${items.length})'),
            ),
          ],
        ),
      ),
    );
  }
}
