import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/app_strings.dart';
import '../models/customer.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/stock_in.dart';
import '../widgets/formatters.dart';
import 'inventory_storage.dart';

class ExportService {
  const ExportService._();

  static String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n')) {
      return '"$escaped"';
    }
    return escaped;
  }

  static String buildProductsCsv(List<Product> products) {
    final buffer = StringBuffer();
    buffer.writeln(
      'ID,Name,Category,Nomenclature,PrintName,PackQty,BoxQty,SKU,PackBarcode,BoxBarcode,UnitWeight,Unit,CostPrice,SellPrice,Stock,LowStockThreshold,UpdatedAt',
    );
    for (final p in products) {
      buffer.writeln(
        [
          _csvEscape(p.id),
          _csvEscape(p.name),
          _csvEscape(p.category),
          _csvEscape(p.nomenclature),
          _csvEscape(p.printName),
          _csvEscape(p.packQty),
          _csvEscape(p.boxQty),
          _csvEscape(p.sku),
          _csvEscape(p.packBarcode),
          _csvEscape(p.boxBarcode),
          _csvEscape(p.unitWeight),
          _csvEscape(p.unit),
          p.costPrice.toStringAsFixed(2),
          p.sellPrice.toStringAsFixed(2),
          '${p.stock}',
          '${p.lowStockThreshold}',
          p.updatedAt.toIso8601String(),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  static String buildSalesCsv(List<Sale> sales) {
    final buffer = StringBuffer();
    buffer.writeln(
      'ID,CreatedAt,Customer,PaymentMethod,Items,Subtotal,Discount,Total,PaidAmount,RemainingDebt,Profit',
    );
    for (final s in sales) {
      final itemsSummary = s.items
          .map((i) => '${i.productName} x${i.quantity}')
          .join('; ');
      buffer.writeln(
        [
          _csvEscape(s.id),
          s.createdAt.toIso8601String(),
          _csvEscape(s.customerName),
          _csvEscape(s.paymentMethod.name),
          _csvEscape(itemsSummary),
          s.subtotal.toStringAsFixed(2),
          s.discount.toStringAsFixed(2),
          s.total.toStringAsFixed(2),
          s.paidAmount.toStringAsFixed(2),
          s.remainingDebt.toStringAsFixed(2),
          s.profit.toStringAsFixed(2),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  static String buildBackupJson(ShopDataSnapshot snapshot) {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'languageCode': snapshot.languageCode,
      'currencyCode': snapshot.currencyCode,
      'shopName': snapshot.shopName,
      'shopAddress': snapshot.shopAddress,
      'shopPhone': snapshot.shopPhone,
      'receiptFooter': snapshot.receiptFooter,
      'ownerPin': snapshot.ownerPin,
      'cashierMode': snapshot.cashierMode,
      'products': snapshot.products.map((p) => p.toJson()).toList(),
      'sales': snapshot.sales.map((s) => s.toJson()).toList(),
      'expenses': snapshot.expenses.map((e) => e.toJson()).toList(),
      'customers': snapshot.customers.map((c) => c.toJson()).toList(),
      'stockIns': snapshot.stockIns.map((s) => s.toJson()).toList(),
    });
  }

  static ShopDataSnapshot parseBackupJson(String rawJson) {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final rawProducts = decoded['products'] as List<dynamic>? ?? const [];
    final rawSales = decoded['sales'] as List<dynamic>? ?? const [];
    final rawExpenses = decoded['expenses'] as List<dynamic>? ?? const [];
    final rawCustomers = decoded['customers'] as List<dynamic>? ?? const [];
    final rawStockIns = decoded['stockIns'] as List<dynamic>? ?? const [];

    return ShopDataSnapshot(
      products: rawProducts
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList(),
      sales: rawSales
          .map((e) => Sale.fromJson(e as Map<String, dynamic>))
          .toList(),
      expenses: rawExpenses
          .map((e) => Expense.fromJson(e as Map<String, dynamic>))
          .toList(),
      customers: rawCustomers
          .map((e) => Customer.fromJson(e as Map<String, dynamic>))
          .toList(),
      stockIns: rawStockIns
          .map((e) => StockInRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      languageCode: (decoded['languageCode'] as String?) ?? 'en',
      currencyCode: (decoded['currencyCode'] as String?) ?? 'kzt',
      shopName: (decoded['shopName'] as String?) ?? 'Lumio',
      shopAddress: (decoded['shopAddress'] as String?) ?? '',
      shopPhone: (decoded['shopPhone'] as String?) ?? '',
      receiptFooter: (decoded['receiptFooter'] as String?) ?? '',
      ownerPin: (decoded['ownerPin'] as String?) ?? '',
      cashierMode: (decoded['cashierMode'] as bool?) ?? false,
    );
  }

  static String buildSaleReceiptText(
    Sale sale,
    AppStrings strings,
    AppCurrency currency, {
    String shopName = 'Lumio',
    String shopAddress = '',
    String shopPhone = '',
    String receiptFooter = '',
  }) {
    final lines = <String>[
      if (shopName.trim().isNotEmpty) shopName.trim(),
      if (shopAddress.trim().isNotEmpty) shopAddress.trim(),
      if (shopPhone.trim().isNotEmpty) shopPhone.trim(),
      strings.receiptNumberLabel(sale.receiptCode),
      if (sale.hasReturn) strings.returnReceiptTitle,
      formatDateTime(sale.createdAt),
      if (sale.customerName.isNotEmpty) strings.customerLabel(sale.customerName),
      '---',
      for (final item in sale.items)
        '${item.productName}: ${item.quantity} × ${formatMoney(item.unitPrice, currency)} = ${formatMoney(item.lineTotal, currency)}',
      if (sale.hasReturn) ...[
        if (sale.items.isNotEmpty) '---',
        strings.returnHistoryHeader,
        if (sale.refundNote.isNotEmpty)
          for (final part in sale.refundNote.split(' • ')) '  $part',
        if (sale.returnedMoneyTotal > 0)
          '${strings.returnedAmountSummaryLabel}: ${formatMoney(sale.returnedMoneyTotal, currency)}',
      ],
      '---',
      if (sale.discount > 0)
        '${strings.discountLabel}: -${formatMoney(sale.discount, currency)}',
      '${sale.hasReturn ? strings.updatedSaleTotalLabel : strings.totalDue}: ${formatMoney(sale.total, currency)}',
      sale.isSplitPayment
          ? '${strings.paymentMethodLabel(sale.paymentMethod.name)} (${formatMoney(sale.primaryPaymentAmount, currency)}) + ${strings.paymentMethodLabel(sale.secondaryPaymentMethod!.name)} (${formatMoney(sale.secondaryAmount, currency)})'
          : strings.paymentMethodLabel(sale.paymentMethod.name),
      if (!sale.isPaid) ...[
        '${strings.paidAmountLabel}: ${formatMoney(sale.paidAmount, currency)}',
        '${strings.remainingDebtLabel}: ${formatMoney(sale.remainingDebt, currency)}',
        if (sale.dueDate != null)
          strings.dueDateValue(formatDate(sale.dueDate!)),
      ],
      if (receiptFooter.trim().isNotEmpty) ...[
        '---',
        receiptFooter.trim(),
      ],
    ];
    return lines.join('\n');
  }

  static Future<pw.Font?> _loadSystemUnicodeFont() async {
    const candidates = [
      '/system/fonts/Roboto-Regular.ttf',
      '/system/fonts/NotoSans-Regular.ttf',
      '/Library/Fonts/Arial Unicode.ttf',
    ];
    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        return pw.Font.ttf(ByteData.sublistView(bytes));
      }
    }
    return null;
  }

  static Future<Uint8List> buildSaleReceiptPdfBytes(
    Sale sale,
    AppStrings strings,
    AppCurrency currency, {
    String shopName = 'Lumio',
    String shopAddress = '',
    String shopPhone = '',
    String receiptFooter = '',
  }) async {
    final unicodeFont = await _loadSystemUnicodeFont();
    final theme = unicodeFont != null
        ? pw.ThemeData.withFont(base: unicodeFont, bold: unicodeFont)
        : pw.ThemeData.base();

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(14),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (shopName.trim().isNotEmpty)
              pw.Text(
                shopName.trim(),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            if (shopAddress.trim().isNotEmpty)
              pw.Text(
                shopAddress.trim(),
                style: const pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            if (shopPhone.trim().isNotEmpty)
              pw.Text(
                shopPhone.trim(),
                style: const pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            pw.SizedBox(height: 8),
            pw.Text(
              strings.receiptNumberLabel(sale.receiptCode),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            if (sale.hasReturn)
              pw.Text(
                strings.returnReceiptTitle,
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            pw.Text(
              formatDateTime(sale.createdAt),
              style: const pw.TextStyle(fontSize: 9),
            ),
            if (sale.customerName.isNotEmpty)
              pw.Text(
                strings.customerLabel(sale.customerName),
                style: const pw.TextStyle(fontSize: 9),
              ),
            pw.Divider(),
            for (final item in sale.items)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${item.productName} (${item.quantity} × ${formatMoney(item.unitPrice, currency)})',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ),
                    pw.Text(
                      formatMoney(item.lineTotal, currency),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
            if (sale.hasReturn) ...[
              if (sale.items.isNotEmpty) pw.Divider(),
              pw.Text(
                strings.returnHistoryHeader,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              if (sale.refundNote.isNotEmpty)
                for (final part in sale.refundNote.split(' • '))
                  pw.Text(
                    part,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
              if (sale.returnedMoneyTotal > 0)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        strings.returnedAmountSummaryLabel,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        formatMoney(sale.returnedMoneyTotal, currency),
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            pw.Divider(),
            if (sale.discount > 0)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    strings.discountLabel,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    '-${formatMoney(sale.discount, currency)}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  sale.hasReturn ? strings.updatedSaleTotalLabel : strings.totalDue,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  formatMoney(sale.total, currency),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              sale.isSplitPayment
                  ? '${strings.paymentMethodLabel(sale.paymentMethod.name)} (${formatMoney(sale.primaryPaymentAmount, currency)}) + ${strings.paymentMethodLabel(sale.secondaryPaymentMethod!.name)} (${formatMoney(sale.secondaryAmount, currency)})'
                  : strings.paymentMethodLabel(sale.paymentMethod.name),
              style: const pw.TextStyle(fontSize: 9),
            ),
            if (!sale.isPaid) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                '${strings.paidAmountLabel}: ${formatMoney(sale.paidAmount, currency)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                '${strings.remainingDebtLabel}: ${formatMoney(sale.remainingDebt, currency)}',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (sale.dueDate != null)
                pw.Text(
                  strings.dueDateValue(formatDate(sale.dueDate!)),
                  style: const pw.TextStyle(fontSize: 9),
                ),
            ],
            if (receiptFooter.trim().isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.Text(
                receiptFooter.trim(),
                style: const pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            ],
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: sale.receiptCode,
                width: 150,
                height: 36,
                drawText: true,
                textStyle: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static Future<String> saveSaleReceiptPdf(
    Sale sale,
    AppStrings strings,
    AppCurrency currency, {
    String shopName = 'Lumio',
    String shopAddress = '',
    String shopPhone = '',
    String receiptFooter = '',
  }) async {
    final bytes = await buildSaleReceiptPdfBytes(
      sale,
      strings,
      currency,
      shopName: shopName,
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      receiptFooter: receiptFooter,
    );
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final baseDir = home != null && home.isNotEmpty
        ? Directory('$home/.small_shop_inventory/receipts')
        : Directory('${Directory.systemTemp.path}/small_shop_inventory/receipts');
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    final file = File('${baseDir.path}/receipt_${sale.id}.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static String buildStockInText(
    StockInRecord record,
    AppStrings strings,
    AppCurrency currency, {
    String shopName = 'Lumio',
  }) {
    final lines = <String>[
      if (shopName.trim().isNotEmpty) shopName.trim(),
      strings.stockInInvoiceTitle,
      formatDateTime(record.createdAt),
      if (record.supplierName.trim().isNotEmpty)
        '${strings.supplierNameHint.split('(').first.trim()}: ${record.supplierName.trim()}',
      '---',
      for (final item in record.items)
        '${item.productName}: ${item.quantity} × ${formatMoney(item.unitCost, currency)} = ${formatMoney(item.lineTotal, currency)}',
      '---',
      '${strings.unitsShort(record.totalUnits)} • ${formatMoney(record.totalCost, currency)}',
    ];
    return lines.join('\n');
  }

  static Future<Uint8List> buildStockInPdfBytes(
    StockInRecord record,
    AppStrings strings,
    AppCurrency currency, {
    String shopName = 'Lumio',
  }) async {
    final unicodeFont = await _loadSystemUnicodeFont();
    final theme = unicodeFont != null
        ? pw.ThemeData.withFont(base: unicodeFont, bold: unicodeFont)
        : pw.ThemeData.base();

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (shopName.trim().isNotEmpty)
              pw.Text(
                shopName.trim(),
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            pw.SizedBox(height: 4),
            pw.Text(
              strings.stockInInvoiceTitle,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              formatDateTime(record.createdAt),
              style: const pw.TextStyle(fontSize: 10),
            ),
            if (record.supplierName.trim().isNotEmpty)
              pw.Text(
                '${strings.supplierNameHint.split('(').first.trim()}: ${record.supplierName.trim()}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            pw.Divider(),
            for (final item in record.items)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${item.productName} (${item.quantity} × ${formatMoney(item.unitCost, currency)})',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                    pw.Text(
                      formatMoney(item.lineTotal, currency),
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  strings.unitsShort(record.totalUnits),
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  formatMoney(record.totalCost, currency),
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static Future<String> saveStockInPdf(
    StockInRecord record,
    AppStrings strings,
    AppCurrency currency, {
    String shopName = 'Lumio',
  }) async {
    final bytes = await buildStockInPdfBytes(
      record,
      strings,
      currency,
      shopName: shopName,
    );
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final baseDir = home != null && home.isNotEmpty
        ? Directory('$home/.small_shop_inventory/receipts')
        : Directory('${Directory.systemTemp.path}/small_shop_inventory/receipts');
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    final file = File('${baseDir.path}/stockin_${record.id}.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<String> saveExportFile(String filename, String content) async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final baseDir = home != null && home.isNotEmpty
        ? Directory('$home/.small_shop_inventory/exports')
        : Directory('${Directory.systemTemp.path}/small_shop_inventory/exports');
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    final file = File('${baseDir.path}/$filename');
    await file.writeAsString(content);
    return file.path;
  }
}
