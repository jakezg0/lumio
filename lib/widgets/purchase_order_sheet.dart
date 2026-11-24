import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/export_service.dart';
import '../services/whatsapp_launcher.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';

class PurchaseOrderSheet extends StatefulWidget {
  const PurchaseOrderSheet({super.key, required this.controller});

  final ShopController controller;

  @override
  State<PurchaseOrderSheet> createState() => _PurchaseOrderSheetState();
}

class _PurchaseOrderSheetState extends State<PurchaseOrderSheet> {
  final TextEditingController _supplierCtrl = TextEditingController();
  final TextEditingController _supplierPhoneCtrl = TextEditingController();
  final Map<String, double> _quantities = {};
  final Map<String, TextEditingController> _qtyControllers = {};
  late List<
      ({
        Product product,
        double suggestedQty,
        String lastSupplier,
        int? daysLeft,
      })> _suggestions;
  String? _selectedSupplierFilter;

  @override
  void initState() {
    super.initState();
    _suggestions = widget.controller.buildPurchaseOrderSuggestions();
    for (final s in _suggestions) {
      _quantities[s.product.id] = s.suggestedQty;
      _qtyControllers[s.product.id] = TextEditingController(
        text: formatQty(s.suggestedQty),
      );
    }
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _supplierPhoneCtrl.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _setQty(String productId, double value) {
    final clean = value < 0 ? 0.0 : value;
    _quantities[productId] = clean;
    final ctrl = _qtyControllers[productId];
    final formatted = formatQty(clean);
    if (ctrl != null && ctrl.text != formatted) {
      ctrl.text = formatted;
    }
    setState(() {});
  }

  Future<void> _sendToWhatsApp(
    List<
        ({
          Product product,
          double suggestedQty,
          String lastSupplier,
          int? daysLeft,
        })> visible,
  ) async {
    final items = <({Product product, double quantity})>[];
    for (final entry in visible) {
      final qty = _quantities[entry.product.id] ?? 0;
      if (qty > 0) {
        items.add((product: entry.product, quantity: qty));
      }
    }
    if (items.isEmpty) return;
    final strings = widget.controller.strings;
    final supplierName = _supplierCtrl.text.trim().isNotEmpty
        ? _supplierCtrl.text.trim()
        : (_selectedSupplierFilter ?? '');
    final text = ExportService.buildPurchaseOrderText(
      items,
      strings,
      supplierName: supplierName,
      shopName: widget.controller.shopName,
      shopAddress: widget.controller.shopAddress,
      shopPhone: widget.controller.shopPhone,
    );
    await WhatsAppLauncher.openChatOrShare(
      phone: _supplierPhoneCtrl.text.trim(),
      message: text,
      subject: strings.purchaseOrderTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final theme = Theme.of(context);
    final suppliers = _suggestions
        .map((s) => s.lastSupplier)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final visible = _selectedSupplierFilter == null
        ? _suggestions
        : _suggestions
            .where((s) => s.lastSupplier == _selectedSupplierFilter)
            .toList();
    final selectedCount = visible
        .where((s) => (_quantities[s.product.id] ?? 0) > 0)
        .length;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
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
            Row(
              children: [
                const Icon(Icons.shopping_bag_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${strings.purchaseOrderBtn} (${_suggestions.length})',
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
            if (_suggestions.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    strings.purchaseOrderEmpty,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else ...[
              TextField(
                controller: _supplierCtrl,
                decoration: InputDecoration(
                  hintText: strings.supplierOptionalHint,
                  prefixIcon: const Icon(Icons.local_shipping_outlined),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _supplierPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: strings.supplierPhoneOptionalHint,
                  prefixIcon: const Icon(Icons.phone_outlined),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (suppliers.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(strings.allSuppliersFilter),
                          selected: _selectedSupplierFilter == null,
                          onSelected: (_) =>
                              setState(() => _selectedSupplierFilter = null),
                        ),
                      ),
                      for (final sup in suppliers)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(sup),
                            selected: _selectedSupplierFilter == sup,
                            onSelected: (_) => setState(() {
                              _selectedSupplierFilter = sup;
                              _supplierCtrl.text = sup;
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = visible[index];
                    final p = item.product;
                    final qty = _quantities[p.id] ?? 0;
                    final qtyCtrl = _qtyControllers[p.id]!;
                    final subtitleParts = [
                      strings.stockCountLabel(p.stock),
                      if (item.daysLeft != null)
                        strings.approxDaysLeftShort(item.daysLeft!),
                      if (item.lastSupplier.isNotEmpty) item.lastSupplier,
                    ];
                    final isUrgent =
                        p.stock <= 0 || (item.daysLeft != null && item.daysLeft! <= 4);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitleParts.join(' • '),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: p.stock <= 0
                                        ? theme.colorScheme.error
                                        : isUrgent
                                            ? Colors.amber.shade900
                                            : theme.colorScheme.onSurfaceVariant,
                                    fontWeight:
                                        isUrgent ? FontWeight.w600 : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                qty > 0 ? () => _setQty(p.id, qty - 1) : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          SizedBox(
                            width: 64,
                            child: TextField(
                              controller: qtyCtrl,
                              textAlign: TextAlign.center,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onChanged: (v) {
                                final parsed = parseQty(v);
                                setState(() {
                                  _quantities[p.id] =
                                      (parsed == null || parsed < 0)
                                          ? 0
                                          : parsed;
                                });
                              },
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _setQty(p.id, qty + 1),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed:
                    selectedCount == 0 ? null : () => _sendToWhatsApp(visible),
                icon: const Icon(Icons.send_outlined),
                label: Text('${strings.shareWhatsAppBtn} ($selectedCount)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
