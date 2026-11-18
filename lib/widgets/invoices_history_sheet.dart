import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sale.dart';
import '../models/stock_in.dart';
import '../screens/barcode_scanner_screen.dart';
import '../services/export_service.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';
import 'receipt_sheet.dart';

enum InvoiceHistoryFilter {
  all,
  sales,
  stockIns,
}

class InvoicesHistorySheet extends StatefulWidget {
  const InvoicesHistorySheet({
    super.key,
    required this.controller,
    this.initialFilter = InvoiceHistoryFilter.all,
  });

  final ShopController controller;
  final InvoiceHistoryFilter initialFilter;

  @override
  State<InvoicesHistorySheet> createState() => _InvoicesHistorySheetState();
}

class _InvoicesHistorySheetState extends State<InvoicesHistorySheet> {
  final _searchCtrl = TextEditingController();
  late InvoiceHistoryFilter _typeFilter;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.initialFilter;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesQuery(String rawQuery, List<String> fields) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final compactQ = q.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    for (final field in fields) {
      final lower = field.toLowerCase();
      if (lower.contains(q)) return true;
      if (compactQ.isNotEmpty) {
        final compactField = lower.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
        if (compactField.contains(compactQ)) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final currency = widget.controller.currency;

        final phoneByCustomer = <String, String>{};
        for (final c in widget.controller.customers) {
          final nameKey = c.name.trim().toLowerCase();
          if (nameKey.isNotEmpty && c.phone.trim().isNotEmpty) {
            phoneByCustomer[nameKey] = c.phone.trim();
          }
        }

        final entries = <_InvoiceEntry>[];

        if (_typeFilter != InvoiceHistoryFilter.stockIns) {
          for (final sale in widget.controller.sales) {
            final customerKey = sale.customerName.trim().toLowerCase();
            final phone = phoneByCustomer[customerKey] ?? '';
            final paymentLabel = sale.isSplitPayment
                ? '${strings.paymentMethodLabel(sale.paymentMethod.name)} ${strings.paymentMethodLabel(sale.secondaryPaymentMethod!.name)}'
                : strings.paymentMethodLabel(sale.paymentMethod.name);
            final fields = <String>[
              sale.id,
              sale.receiptCode,
              sale.customerName,
              phone,
              sale.total.toStringAsFixed(0),
              sale.total.toStringAsFixed(2),
              formatMoney(sale.total, currency),
              if (sale.remainingDebt > 0) sale.remainingDebt.toStringAsFixed(0),
              formatDateTime(sale.createdAt),
              paymentLabel,
              for (final item in sale.items) item.productName,
            ];
            if (_matchesQuery(_query, fields)) {
              entries.add(
                _InvoiceEntry(
                  createdAt: sale.createdAt,
                  sale: sale,
                  customerPhone: phone,
                ),
              );
            }
          }
        }

        if (_typeFilter != InvoiceHistoryFilter.sales) {
          for (final inv in widget.controller.stockIns) {
            final fields = <String>[
              inv.id,
              inv.supplierName,
              inv.totalCost.toStringAsFixed(0),
              inv.totalCost.toStringAsFixed(2),
              formatMoney(inv.totalCost, currency),
              formatDateTime(inv.createdAt),
              for (final item in inv.items) item.productName,
            ];
            if (_matchesQuery(_query, fields)) {
              entries.add(
                _InvoiceEntry(
                  createdAt: inv.createdAt,
                  stockIn: inv,
                ),
              );
            }
          }
        }

        entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    strings.invoiceHistoryTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${entries.length}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<InvoiceHistoryFilter>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: InvoiceHistoryFilter.all,
                    label: Text(
                      strings.allCategory,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: InvoiceHistoryFilter.sales,
                    label: Text(
                      strings.saleInvoicesTab,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: InvoiceHistoryFilter.stockIns,
                    label: Text(
                      strings.stockInInvoicesTab,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {_typeFilter},
                onSelectionChanged: (sel) {
                  setState(() => _typeFilter = sel.first);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: strings.searchInvoicesHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_query.isNotEmpty)
                        IconButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                      IconButton(
                        tooltip: strings.scanReceiptBarcodeTooltip,
                        onPressed: () async {
                          final scanned = await Navigator.of(context).push<String>(
                            MaterialPageRoute<String>(
                              builder: (_) => BarcodeScannerScreen(strings: strings),
                            ),
                          );
                          if (scanned != null && scanned.trim().isNotEmpty && mounted) {
                            setState(() {
                              _searchCtrl.text = scanned.trim();
                              _query = scanned.trim();
                            });
                          }
                        },
                        icon: const Icon(Icons.qr_code_scanner),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      _query.trim().isNotEmpty
                          ? strings.noInvoicesMatchMsg
                          : strings.noInvoicesMsg,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.55,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      if (entry.sale != null) {
                        final sale = entry.sale!;
                        final customerDisplay = [
                          if (sale.customerName.isNotEmpty) sale.customerName,
                          if (entry.customerPhone.isNotEmpty)
                            entry.customerPhone,
                        ].join(' • ');
                        final payLabel = sale.isSplitPayment
                            ? '${strings.paymentMethodLabel(sale.paymentMethod.name)} + ${strings.paymentMethodLabel(sale.secondaryPaymentMethod!.name)}'
                            : strings.paymentMethodLabel(sale.paymentMethod.name);

                        return Card(
                          margin: EdgeInsets.zero,
                          child: ExpansionTile(
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    customerDisplay.isNotEmpty
                                        ? customerDisplay
                                        : strings.saleInvoicesTab,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  formatMoney(sale.total, currency),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '${sale.receiptCode} • ${formatDateTime(sale.createdAt)} • $payLabel • '
                              '${sale.isPaid ? strings.paidBadge : strings.unpaidBadge(formatMoney(sale.remainingDebt, currency))}',
                            ),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            children: [
                              for (final item in sale.items)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${item.productName} (${item.quantity} × ${formatMoney(item.unitPrice, currency)})',
                                        ),
                                      ),
                                      Text(formatMoney(item.lineTotal, currency)),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 8),
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    useSafeArea: true,
                                    builder: (_) => ReceiptSheet(
                                      controller: widget.controller,
                                      sale: sale,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.share_outlined, size: 18),
                                label: Text('${strings.shareWhatsAppBtn} / PDF'),
                              ),
                            ],
                          ),
                        );
                      }

                      final inv = entry.stockIn!;
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ExpansionTile(
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  inv.supplierName.isEmpty
                                      ? strings.stockInBtn
                                      : inv.supplierName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formatMoney(inv.totalCost, currency),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${strings.stockInInvoicesTab} • ${formatDateTime(inv.createdAt)} • ${strings.unitsShort(inv.totalUnits)}',
                          ),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          children: [
                            for (final item in inv.items)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.productName} (${item.quantity} × ${formatMoney(item.unitCost, currency)})',
                                      ),
                                    ),
                                    Text(formatMoney(item.lineTotal, currency)),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final text = ExportService.buildStockInText(
                                        inv,
                                        strings,
                                        currency,
                                        shopName: widget.controller.shopName,
                                      );
                                      await Share.share(
                                        text,
                                        subject: strings.stockInInvoiceTitle,
                                      );
                                    },
                                    icon: const Icon(Icons.share, size: 18),
                                    label: const Text('WhatsApp'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    onPressed: () async {
                                      final path =
                                          await ExportService.saveStockInPdf(
                                        inv,
                                        strings,
                                        currency,
                                        shopName: widget.controller.shopName,
                                      );
                                      await Share.shareXFiles(
                                        [XFile(path)],
                                        subject: strings.stockInInvoiceTitle,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('PDF'),
                                  ),
                                ),
                              ],
                            ),
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

class _InvoiceEntry {
  const _InvoiceEntry({
    required this.createdAt,
    this.sale,
    this.customerPhone = '',
    this.stockIn,
  });

  final DateTime createdAt;
  final Sale? sale;
  final String customerPhone;
  final StockInRecord? stockIn;
}
