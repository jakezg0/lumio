import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sale.dart';
import '../services/export_service.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';
import 'receipt_barcode.dart';

class ReceiptSheet extends StatelessWidget {
  const ReceiptSheet({
    super.key,
    required this.controller,
    required this.sale,
  });

  final ShopController controller;
  final Sale sale;

  Future<void> _shareText(BuildContext context) async {
    final text = ExportService.buildSaleReceiptText(
      sale,
      controller.strings,
      controller.currency,
      shopName: controller.shopName,
      shopAddress: controller.shopAddress,
      shopPhone: controller.shopPhone,
      receiptFooter: controller.receiptFooter,
    );
    await Share.share(text, subject: controller.strings.saleReceipt);
  }

  Future<void> _sharePdf(BuildContext context) async {
    final strings = controller.strings;
    final path = await ExportService.saveSaleReceiptPdf(
      sale,
      strings,
      controller.currency,
      shopName: controller.shopName,
      shopAddress: controller.shopAddress,
      shopPhone: controller.shopPhone,
      receiptFooter: controller.receiptFooter,
    );
    await Share.shareXFiles(
      [XFile(path)],
      subject: strings.saleReceipt,
    );
  }

  Future<void> _copyText(BuildContext context) async {
    final strings = controller.strings;
    final text = ExportService.buildSaleReceiptText(
      sale,
      strings,
      controller.currency,
      shopName: controller.shopName,
      shopAddress: controller.shopAddress,
      shopPhone: controller.shopPhone,
      receiptFooter: controller.receiptFooter,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.copiedToClipboardMsg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = controller.strings;
    final currency = controller.currency;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.shopName.trim().isNotEmpty)
              Text(
                controller.shopName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
            if (controller.shopAddress.trim().isNotEmpty)
              Text(
                controller.shopAddress,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            if (controller.shopPhone.trim().isNotEmpty)
              Text(
                controller.shopPhone,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  strings.receiptNumberLabel(sale.receiptCode),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  sale.isSplitPayment
                      ? '${strings.paymentMethodLabel(sale.paymentMethod.name)} + ${strings.paymentMethodLabel(sale.secondaryPaymentMethod!.name)}'
                      : strings.paymentMethodLabel(sale.paymentMethod.name),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            Text(
              formatDateTime(sale.createdAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (sale.hasReturn)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  strings.returnReceiptTitle,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            if (sale.customerName.isNotEmpty)
              Text(
                strings.customerLabel(sale.customerName),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const Divider(height: 20),
            for (final item in sale.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
            if (sale.discount > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(strings.discountLabel),
                  Text('-${formatMoney(sale.discount, currency)}'),
                ],
              ),
            ],
            if (sale.hasReturn) ...[
              const Divider(height: 20),
              Text(
                strings.returnHistoryHeader,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              if (sale.refundNote.isNotEmpty)
                for (final part in sale.refundNote.split(' • '))
                  Text(
                    part,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              if (sale.returnedMoneyTotal > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        strings.returnedAmountSummaryLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        formatMoney(sale.returnedMoneyTotal, currency),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  sale.hasReturn ? strings.updatedSaleTotalLabel : strings.totalDue,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  formatMoney(sale.total, currency),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (!sale.isPaid) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(strings.paidAmountLabel),
                  Text(formatMoney(sale.paidAmount, currency)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    strings.remainingDebtLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    formatMoney(sale.remainingDebt, currency),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
              if (sale.dueDate != null)
                Text(
                  strings.dueDateValue(formatDate(sale.dueDate!)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            if (controller.receiptFooter.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                controller.receiptFooter,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 12),
            ReceiptBarcodeWidget(code: sale.receiptCode),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _shareText(context),
              icon: const Icon(Icons.share),
              label: Text(strings.shareWhatsAppBtn),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _sharePdf(context),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(strings.sharePdfBtn),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyText(context),
                    icon: const Icon(Icons.copy),
                    label: Text(strings.copyTextBtn),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
