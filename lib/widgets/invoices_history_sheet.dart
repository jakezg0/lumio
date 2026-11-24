import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_strings.dart';
import '../models/sale.dart';
import '../models/stock_in.dart';
import '../screens/barcode_scanner_screen.dart';
import '../services/export_service.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';
import 'price_tag_queue_sheet.dart';
import 'receipt_sheet.dart';
import 'stock_in_sheet.dart';

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
    this.initialDateFilter = SalesDateFilter.all,
  });

  final ShopController controller;
  final InvoiceHistoryFilter initialFilter;
  final SalesDateFilter initialDateFilter;

  @override
  State<InvoicesHistorySheet> createState() => _InvoicesHistorySheetState();
}

class _InvoicesHistorySheetState extends State<InvoicesHistorySheet> {
  final _searchCtrl = TextEditingController();
  late InvoiceHistoryFilter _typeFilter;
  late SalesDateFilter _dateFilter;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.initialFilter;
    _dateFilter = widget.initialDateFilter;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _dateFilterLabel(AppStrings strings, SalesDateFilter filter) {
    switch (filter) {
      case SalesDateFilter.today:
        return strings.filterToday;
      case SalesDateFilter.last7Days:
        return strings.filter7Days;
      case SalesDateFilter.all:
        return strings.filterAll;
    }
  }

  Future<void> _repeatStockIn(StockInRecord inv) async {
    await widget.controller.repeatStockIn(inv);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.pop();
    await showModalBottomSheet<int>(
      context: navigator.context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StockInSheet(controller: widget.controller),
    );
  }

  Future<void> _confirmDeleteStockIn(StockInRecord inv) async {
    final strings = widget.controller.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(strings.deleteStockInTitle),
        content: Text(strings.deleteStockInBody(inv.totalUnits)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.controller.deleteStockIn(inv.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.stockInDeletedMsg)),
      );
    }
  }

  Future<void> _showPaySupplierDialog(StockInRecord inv) async {
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final amountCtrl = TextEditingController(
      text: inv.remainingDebt == inv.remainingDebt.roundToDouble()
          ? inv.remainingDebt.toStringAsFixed(0)
          : inv.remainingDebt.toStringAsFixed(2),
    );
    var recordAsExpense = true;

    final confirmed = await showDialog<({double amount, bool asExpense})>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text(strings.paySupplierDebtTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${inv.supplierName.isEmpty ? strings.unspecifiedSupplierLabel : inv.supplierName} • '
                  '${strings.remainingDebtLabel}: ${formatMoney(inv.remainingDebt, currency)}',
                  style: Theme.of(dialogCtx).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onTap: () => selectAllText(amountCtrl),
                  decoration: InputDecoration(
                    labelText: strings.paymentAmountHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  value: recordAsExpense,
                  onChanged: (v) =>
                      setDialogState(() => recordAsExpense = v ?? true),
                  title: Text(strings.recordAsExpenseLabel),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(
                  amountCtrl.text.trim().replaceAll(',', '.'),
                );
                if (parsed == null || parsed <= 0) return;
                Navigator.of(dialogCtx).pop(
                  (amount: parsed, asExpense: recordAsExpense),
                );
              },
              child: Text(strings.confirm),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
    if (confirmed == null || !mounted) return;
    await widget.controller.recordSupplierPayment(
      inv.id,
      confirmed.amount,
      recordAsExpense: confirmed.asExpense,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.paymentRecorded)),
      );
    }
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
        var totalStockInCost = 0.0;
        var totalStockInUnits = 0.0;

        if (_typeFilter != InvoiceHistoryFilter.stockIns) {
          for (final sale in widget.controller.filteredSales(_dateFilter)) {
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
          for (final inv in widget.controller.filteredStockIns(_dateFilter)) {
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
              totalStockInCost += inv.totalCost;
              totalStockInUnits += inv.totalUnits;
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

        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.invoiceHistoryTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
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
                SegmentedButton<SalesDateFilter>(
                  showSelectedIcon: false,
                  segments: [
                    for (final option in SalesDateFilter.values)
                      ButtonSegment(
                        value: option,
                        label: Text(
                          _dateFilterLabel(strings, option),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  selected: {_dateFilter},
                  onSelectionChanged: (sel) {
                    setState(() => _dateFilter = sel.first);
                  },
                ),
                const SizedBox(height: 8),
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
                if (_typeFilter != InvoiceHistoryFilter.sales &&
                    totalStockInUnits > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${strings.totalPurchasesForPeriodLabel} (${strings.unitsShort(totalStockInUnits)})',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatMoney(totalStockInCost, currency),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              _query.trim().isNotEmpty
                                  ? strings.noInvoicesMatchMsg
                                  : strings.noInvoicesMsg,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.separated(
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
                            [
                              strings.stockInInvoicesTab,
                              formatDateTime(inv.createdAt),
                              strings.unitsShort(inv.totalUnits),
                              if (!inv.isPaid)
                                strings.unpaidBadge(
                                  formatMoney(inv.remainingDebt, currency),
                                )
                              else if (inv.isCredit)
                                strings.debtPaidBadge,
                            ].join(' • '),
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
                            if (!inv.isPaid) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _showPaySupplierDialog(inv),
                                      icon: const Icon(
                                        Icons.payments_outlined,
                                        size: 18,
                                      ),
                                      label: Text(strings.addPayment),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton.tonalIcon(
                                      onPressed: () async {
                                        await widget.controller
                                            .markStockInPaid(inv.id);
                                        if (mounted) {
                                          ScaffoldMessenger.of(this.context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                strings.paymentRecorded,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.check, size: 18),
                                      label: Text(strings.markAsPaid),
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _repeatStockIn(inv),
                                    icon: const Icon(Icons.replay, size: 18),
                                    label: Text(strings.repeatStockInBtn),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    final products = [
                                      for (final item in inv.items)
                                        if (widget.controller.findProductById(
                                              item.productId,
                                            ) !=
                                            null)
                                          widget.controller.findProductById(
                                            item.productId,
                                          )!,
                                    ];
                                    if (products.isEmpty) return;
                                    showModalBottomSheet<void>(
                                      context: context,
                                      isScrollControlled: true,
                                      useSafeArea: true,
                                      builder: (_) => BatchPriceTagsSheet(
                                        controller: widget.controller,
                                        products: products,
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.sell_outlined,
                                    size: 18,
                                  ),
                                  label: Text(strings.printInvoicePriceTagsBtn),
                                ),
                                const SizedBox(width: 8),
                                IconButton.outlined(
                                  tooltip: strings.delete,
                                  color: Theme.of(context).colorScheme.error,
                                  onPressed: () => _confirmDeleteStockIn(inv),
                                  icon: const Icon(Icons.delete_outline),
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
