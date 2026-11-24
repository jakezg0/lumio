import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/export_service.dart';
import '../state/shop_controller.dart';

class PriceListSheet extends StatefulWidget {
  const PriceListSheet({
    super.key,
    required this.controller,
    this.initialCategory,
  });

  final ShopController controller;
  final String? initialCategory;

  @override
  State<PriceListSheet> createState() => _PriceListSheetState();
}

class _PriceListSheetState extends State<PriceListSheet> {
  String? _selectedCategory;
  bool _inStockOnly = true;
  bool _newArrivalsOnly = false;
  bool _includeWholesale = true;
  bool _includeStock = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCategory?.trim();
    if (initial != null &&
        initial.isNotEmpty &&
        widget.controller.categories.contains(initial)) {
      _selectedCategory = initial;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = widget.controller.strings;
    final categories = widget.controller.categories;

    final priceText = ExportService.buildPriceListText(
      products: widget.controller.products,
      strings: strings,
      currency: widget.controller.currency,
      category: _selectedCategory,
      inStockOnly: _inStockOnly,
      newArrivalsOnly: _newArrivalsOnly,
      includeWholesale: _includeWholesale,
      includeStock: _includeStock,
      shopName: widget.controller.shopName,
      shopPhone: widget.controller.shopPhone,
    );

    final itemCount = priceText.isEmpty
        ? 0
        : priceText
            .split('\n')
            .where((line) => RegExp(r'^\d+\.\s').hasMatch(line))
            .length;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.priceListTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(strings.allCategory),
                    selected: _selectedCategory == null,
                    onSelected: (_) => setState(() => _selectedCategory = null),
                  ),
                ),
                for (final cat in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: _selectedCategory == cat,
                      onSelected: (_) =>
                          setState(() => _selectedCategory = cat),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilterChip(
                label: Text(strings.inStockFilter(
                  widget.controller.products.where((p) => p.stock > 0).length,
                )),
                selected: _inStockOnly,
                onSelected: (v) => setState(() => _inStockOnly = v),
              ),
              FilterChip(
                label: Text(strings.newArrivalsOnlyLabel),
                selected: _newArrivalsOnly,
                onSelected: (v) => setState(() => _newArrivalsOnly = v),
              ),
              FilterChip(
                label: Text(strings.includeWholesalePricesLabel),
                selected: _includeWholesale,
                onSelected: (v) => setState(() => _includeWholesale = v),
              ),
              FilterChip(
                label: Text(strings.includeStockCountLabel),
                selected: _includeStock,
                onSelected: (v) => setState(() => _includeStock = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (itemCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                strings.priceListCountLabel(itemCount),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: priceText.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        strings.priceListEmptyMsg,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: SelectableText(
                      priceText,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: priceText.isEmpty
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(
                            ClipboardData(text: priceText),
                          );
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(strings.copiedToClipboardMsg),
                            ),
                          );
                        },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(strings.copyTextBtn),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: priceText.isEmpty
                      ? null
                      : () => Share.share(
                            priceText,
                            subject: strings.priceListTitle,
                          ),
                  icon: const Icon(Icons.share, size: 18),
                  label: Text(strings.shareWhatsAppBtn),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
