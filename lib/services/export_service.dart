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
import 'input_normalizer.dart';
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
      'ID,Name,Category,Nomenclature,PrintName,PackQty,BoxQty,SKU,PackBarcode,BoxBarcode,UnitWeight,Unit,CostPrice,SellPrice,WholesalePrice,WholesaleMinQty,Stock,LowStockThreshold,UpdatedAt',
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
          p.wholesalePrice > 0 ? p.wholesalePrice.toStringAsFixed(2) : '',
          p.wholesaleMinQty > 0 ? '${p.wholesaleMinQty}' : '',
          '${p.stock}',
          '${p.lowStockThreshold}',
          p.updatedAt.toIso8601String(),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  static String _tsvClean(String value) {
    return value
        .replaceAll('\t', ' ')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
  }

  static String buildProductsReadableTsv(List<Product> products) {
    final buffer = StringBuffer();
    buffer.writeln(
      [
        'Название',
        'Категория',
        'Штрихкод (SKU)',
        'Закуп',
        'Цена',
        'Опт',
        'Остаток',
        'Порог',
        'Маржа %',
        'Сумма закупа',
        'Упаковка',
        'Коробка',
        'Штрихкод упаковки',
        'Штрихкод коробки',
        'ID',
      ].join('\t'),
    );
    for (final p in products) {
      buffer.writeln(
        [
          _tsvClean(p.name),
          _tsvClean(p.category),
          _tsvClean(p.sku),
          p.costPrice == p.costPrice.roundToDouble()
              ? p.costPrice.toStringAsFixed(0)
              : p.costPrice.toStringAsFixed(2),
          p.sellPrice == p.sellPrice.roundToDouble()
              ? p.sellPrice.toStringAsFixed(0)
              : p.sellPrice.toStringAsFixed(2),
          p.wholesalePrice > 0
              ? (p.wholesalePrice == p.wholesalePrice.roundToDouble()
                  ? p.wholesalePrice.toStringAsFixed(0)
                  : p.wholesalePrice.toStringAsFixed(2))
              : '',
          '${p.stock}',
          '${p.lowStockThreshold}',
          p.marginPercent.toStringAsFixed(1),
          p.inventoryValue == p.inventoryValue.roundToDouble()
              ? p.inventoryValue.toStringAsFixed(0)
              : p.inventoryValue.toStringAsFixed(2),
          _tsvClean(p.packQty),
          _tsvClean(p.boxQty),
          _tsvClean(p.packBarcode),
          _tsvClean(p.boxBarcode),
          _tsvClean(p.id),
        ].join('\t'),
      );
    }
    return buffer.toString();
  }

  static String buildProductsReadableCsvWithBom(List<Product> products) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      'Название;Категория;Штрихкод (SKU);Закуп;Цена;Опт;Остаток;Порог;Маржа %;Сумма закупа;Упаковка;Коробка;Штрихкод упаковки;Штрихкод коробки;ID',
    );
    for (final p in products) {
      String numStr(double v) =>
          v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
      buffer.writeln(
        [
          _csvEscape(p.name),
          _csvEscape(p.category),
          _csvEscape(p.sku),
          numStr(p.costPrice),
          numStr(p.sellPrice),
          p.wholesalePrice > 0 ? numStr(p.wholesalePrice) : '',
          '${p.stock}',
          '${p.lowStockThreshold}',
          p.marginPercent.toStringAsFixed(1),
          numStr(p.inventoryValue),
          _csvEscape(p.packQty),
          _csvEscape(p.boxQty),
          _csvEscape(p.packBarcode),
          _csvEscape(p.boxBarcode),
          _csvEscape(p.id),
        ].join(';'),
      );
    }
    return buffer.toString();
  }

  static String buildImportTemplateTsv() {
    final buffer = StringBuffer();
    buffer.writeln(
      'Название\tКатегория\tШтрихкод (SKU)\tЗакуп\tЦена\tОпт\tОстаток\tПорог',
    );
    buffer.writeln('Угол наружный 70мм Белый\tПлинтусы\t4601234567890\t200\t320\t280\t50\t5');
    buffer.writeln('Соединитель 85мм Белый\tКомплектующие\t4601234567891\t220\t350\t300\t30\t5');
    return buffer.toString();
  }

  static String buildProductChangesCsvWithBom(
    List<ProductChangeEntry> entries,
    AppStrings strings,
  ) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln('Дата;Товар;Источник;Поле;Было;Стало');
    for (final e in entries) {
      final dateStr = formatDateTime(e.createdAt);
      final sourceStr = strings.changeSourceLabel(e.source);
      for (final f in e.fields) {
        buffer.writeln(
          [
            _csvEscape(dateStr),
            _csvEscape(e.productName),
            _csvEscape(sourceStr),
            _csvEscape(f.label),
            _csvEscape(f.oldValue),
            _csvEscape(f.newValue),
          ].join(';'),
        );
      }
    }
    return buffer.toString();
  }

  static List<String> _splitDelimitedLine(String line, String delimiter) {
    if (delimiter == '\t') {
      return line.split('\t').map((e) => e.trim()).toList();
    }
    final result = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == delimiter && !inQuotes) {
        result.add(current.toString().trim());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    result.add(current.toString().trim());
    return result;
  }

  static List<Product> parseTabularProducts(String rawText) {
    final lines = rawText
        .replaceAll('\uFEFF', '')
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];

    final headerLine = lines.first;
    final delimiter = headerLine.contains('\t')
        ? '\t'
        : (headerLine.contains(';') ? ';' : ',');
    final rawHeaders = _splitDelimitedLine(headerLine, delimiter);

    String mapHeader(String h) {
      final k = h.toLowerCase().trim();
      if (k == 'id') return 'id';
      if (k == 'name' || k.contains('назван') || k.contains('атау') || k == 'товар') return 'name';
      if (k == 'category' || k.contains('катег') || k.contains('санат') || k == 'группа') return 'category';
      if (k == 'sku' || k.contains('штрихкод (sku)') || k == 'штрихкод' || k == 'артикул') return 'sku';
      if (k == 'costprice' || k == 'cost' || k.contains('закуп') || k.contains('себест') || k.contains('сатып')) return 'costPrice';
      if (k == 'wholesaleprice' || k == 'wholesale' || k == 'опт' || k.contains('оптов') || k.contains('көтерме')) return 'wholesalePrice';
      if (k == 'wholesaleminqty' || k.contains('опт от') || k.contains('көтерме (дана')) return 'wholesaleMinQty';
      if (k == 'sellprice' || k == 'price' || k == 'цена' || k.contains('цена прод') || k.contains('сату')) return 'sellPrice';
      if (k == 'stock' || k.contains('остаток') || k.contains('колич') || k.contains('қалдық')) return 'stock';
      if (k == 'lowstockthreshold' || k.contains('порог') || k.contains('шек')) return 'lowStockThreshold';
      if (k == 'packqty' || k == 'упаковка') return 'packQty';
      if (k == 'boxqty' || k == 'коробка') return 'boxQty';
      if (k == 'packbarcode' || k.contains('штрихкод упак')) return 'packBarcode';
      if (k == 'boxbarcode' || k.contains('штрихкод кор')) return 'boxBarcode';
      return '';
    }

    final mappedHeaders = rawHeaders.map(mapHeader).toList();
    final hasHeaderRow = mappedHeaders.contains('name');
    final startIndex = hasHeaderRow ? 1 : 0;
    final cols = hasHeaderRow
        ? mappedHeaders
        : ['name', 'category', 'sku', 'costPrice', 'sellPrice', 'stock', 'lowStockThreshold'];

    double parseNum(String? s) {
      final clean = (s ?? '').trim().replaceAll(' ', '').replaceAll(',', '.');
      return double.tryParse(clean) ?? 0.0;
    }

    int parseIntVal(String? s, {int fallback = 0}) {
      final clean = (s ?? '').trim().replaceAll(' ', '');
      return int.tryParse(clean) ?? fallback;
    }

    final now = DateTime.now();
    final products = <Product>[];
    for (var i = startIndex; i < lines.length; i++) {
      final cells = _splitDelimitedLine(lines[i], delimiter);
      final map = <String, String>{};
      for (var c = 0; c < cols.length && c < cells.length; c++) {
        if (cols[c].isNotEmpty) {
          map[cols[c]] = cells[c];
        }
      }
      final name = InputNormalizer.normalizeDisplayName(map['name'] ?? '');
      if (name.isEmpty) continue;
      final cat = InputNormalizer.normalizeDisplayName(map['category'] ?? '');
      products.add(
        Product(
          id: (map['id'] ?? '').trim(),
          name: name,
          category: cat.isEmpty ? 'General' : cat,
          sku: InputNormalizer.normalizeBarcode(map['sku'] ?? ''),
          packQty: InputNormalizer.normalizeDisplayName(map['packQty'] ?? ''),
          boxQty: InputNormalizer.normalizeDisplayName(map['boxQty'] ?? ''),
          packBarcode:
              InputNormalizer.normalizeBarcode(map['packBarcode'] ?? ''),
          boxBarcode:
              InputNormalizer.normalizeBarcode(map['boxBarcode'] ?? ''),
          costPrice: parseNum(map['costPrice']).clamp(0.0, double.infinity),
          sellPrice: parseNum(map['sellPrice']).clamp(0.0, double.infinity),
          wholesalePrice:
              parseNum(map['wholesalePrice']).clamp(0.0, double.infinity),
          wholesaleMinQty:
              parseIntVal(map['wholesaleMinQty']).clamp(0, 999999),
          stock: parseNum(map['stock']).clamp(0.0, 9999999.0),
          lowStockThreshold: parseIntVal(map['lowStockThreshold'], fallback: 5).clamp(0, 999999),
          updatedAt: now,
        ),
      );
    }
    return products;
  }

  static String buildSalesCsv(List<Sale> sales) {
    final buffer = StringBuffer();
    buffer.writeln(
      'ID,CreatedAt,Customer,PaymentMethod,Items,Subtotal,Discount,Total,TotalCost,PaidAmount,RemainingDebt,Profit',
    );
    for (final s in sales) {
      final itemsSummary = s.items
          .map(
            (i) =>
                '${i.productName} x${i.quantity} (sell:${i.unitPrice.toStringAsFixed(0)} cost:${i.unitCost.toStringAsFixed(0)})',
          )
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
          s.totalCost.toStringAsFixed(2),
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
      'useBiometricUnlock': snapshot.useBiometricUnlock,
      'cashierMode': snapshot.cashierMode,
      'products': snapshot.products.map((p) => p.toJson()).toList(),
      'sales': snapshot.sales.map((s) => s.toJson()).toList(),
      'expenses': snapshot.expenses.map((e) => e.toJson()).toList(),
      'customers': snapshot.customers.map((c) => c.toJson()).toList(),
      'stockIns': snapshot.stockIns.map((s) => s.toJson()).toList(),
      if (snapshot.inventorySnapshots.isNotEmpty)
        'inventorySnapshots':
            snapshot.inventorySnapshots.map((s) => s.toJson()).toList(),
      if (snapshot.featureUsage.isNotEmpty)
        'featureUsage': snapshot.featureUsage.map(
          (k, v) => MapEntry(k, v.toJson()),
        ),
    });
  }

  static ShopDataSnapshot parseBackupJson(String rawJson) {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final rawProducts = decoded['products'] as List<dynamic>? ?? const [];
    final rawSales = decoded['sales'] as List<dynamic>? ?? const [];
    final rawExpenses = decoded['expenses'] as List<dynamic>? ?? const [];
    final rawCustomers = decoded['customers'] as List<dynamic>? ?? const [];
    final rawStockIns = decoded['stockIns'] as List<dynamic>? ?? const [];
    final rawSnapshots =
        decoded['inventorySnapshots'] as List<dynamic>? ?? const [];
    final rawFeatureUsage =
        decoded['featureUsage'] as Map<String, dynamic>? ?? const {};
    final parsedFeatureUsage = <String, FeatureUsageStat>{};
    for (final entry in rawFeatureUsage.entries) {
      if (entry.value is Map<String, dynamic>) {
        final stat =
            FeatureUsageStat.fromJson(entry.value as Map<String, dynamic>);
        if (stat.count > 0) parsedFeatureUsage[entry.key] = stat;
      }
    }

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
      useBiometricUnlock: (decoded['useBiometricUnlock'] as bool?) ?? false,
      cashierMode: (decoded['cashierMode'] as bool?) ?? true,
      inventorySnapshots: rawSnapshots
          .whereType<Map<String, dynamic>>()
          .map(InventoryValueSnapshot.fromJson)
          .toList(),
      featureUsage: parsedFeatureUsage,
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

  static String buildCartEstimateText(
    List<
            ({
              String name,
              double quantity,
              double unitPrice,
              double lineTotal,
              bool isWholesale,
            })>
        items,
    AppStrings strings,
    AppCurrency currency, {
    String shopName = 'Lumio',
    String shopAddress = '',
    String shopPhone = '',
    DateTime? createdAt,
  }) {
    final dt = createdAt ?? DateTime.now();
    final total = items.fold<double>(0, (sum, i) => sum + i.lineTotal);
    final totalUnits = items.fold<double>(0, (sum, i) => sum + i.quantity);
    final lines = <String>[
      if (shopName.trim().isNotEmpty) '*${shopName.trim()}*',
      if (shopAddress.trim().isNotEmpty) shopAddress.trim(),
      if (shopPhone.trim().isNotEmpty) shopPhone.trim(),
      strings.estimateTitle,
      formatDateTime(dt),
      '---',
      for (var i = 0; i < items.length; i++)
        '${i + 1}. ${items[i].name}: ${formatQty(items[i].quantity)} × ${formatMoney(items[i].unitPrice, currency)} = ${formatMoney(items[i].lineTotal, currency)}',
      '---',
      strings.estimateItemsUnitsSummary(items.length, totalUnits),
      '*${strings.estimateTotalLabel}: ${formatMoney(total, currency)}*',
      strings.estimateDisclaimer,
    ];
    return lines.join('\n');
  }

  static String buildPurchaseOrderText(
    List<({Product product, double quantity})> items,
    AppStrings strings, {
    String supplierName = '',
    String shopName = 'Lumio',
    String shopAddress = '',
    String shopPhone = '',
    DateTime? createdAt,
  }) {
    final dt = createdAt ?? DateTime.now();
    final totalUnits = items.fold<double>(0, (sum, i) => sum + i.quantity);
    final lines = <String>[
      if (shopName.trim().isNotEmpty) '*${shopName.trim()}*',
      if (shopAddress.trim().isNotEmpty) shopAddress.trim(),
      if (shopPhone.trim().isNotEmpty) shopPhone.trim(),
      supplierName.trim().isNotEmpty
          ? '${strings.purchaseOrderTitle}: ${supplierName.trim()}'
          : strings.purchaseOrderTitle,
      formatDateTime(dt),
      '---',
      for (var i = 0; i < items.length; i++)
        () {
          final p = items[i].product;
          final qty = formatQty(items[i].quantity);
          final unit = p.unit.trim().isNotEmpty ? p.unit.trim() : '';
          final qtyStr = unit.isNotEmpty ? '$qty $unit' : qty;
          final skuSuffix = p.sku.trim().isNotEmpty ? ' (${p.sku.trim()})' : '';
          return '${i + 1}. ${p.name}$skuSuffix — $qtyStr';
        }(),
      '---',
      strings.estimateItemsUnitsSummary(items.length, totalUnits),
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

  static String buildSupplierClaimText(
    StockInRecord record,
    AppStrings strings,
    AppCurrency currency, {
    String shopName = 'Lumio',
    String shopPhone = '',
  }) {
    final discItems = record.discrepancyItems;
    if (discItems.isEmpty) return '';
    final lines = <String>[
      if (shopName.trim().isNotEmpty) '*${shopName.trim()}*',
      if (shopPhone.trim().isNotEmpty) shopPhone.trim(),
      strings.supplierClaimTitle,
      formatDateTime(record.createdAt),
      if (record.supplierName.trim().isNotEmpty)
        '${strings.supplierNameHint.split('(').first.trim()}: ${record.supplierName.trim()}',
      '---',
      for (var i = 0; i < discItems.length; i++)
        () {
          final item = discItems[i];
          final typeLabel = strings.discrepancyTypeLabel(
            item.discrepancyType!.name,
          );
          final notePart = item.discrepancyNote.trim().isNotEmpty
              ? ' (${item.discrepancyNote.trim()})'
              : '';
          return '${i + 1}. ${item.productName}: $typeLabel — ${formatQty(item.discrepancyQty)} × ${formatMoney(item.unitCost, currency)} = ${formatMoney(item.discrepancyCost, currency)}$notePart';
        }(),
      '---',
      '${strings.supplierClaimTotalLabel}: ${strings.unitsShort(record.totalDiscrepancyUnits)} • ${formatMoney(record.totalDiscrepancyCost, currency)}',
      strings.supplierClaimClosingNote,
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

  static bool _isValidEan13(String raw) {
    final code = raw.trim();
    if (code.length != 13) return false;
    var sum = 0;
    for (var i = 0; i < 13; i++) {
      final c = code.codeUnitAt(i);
      if (c < 48 || c > 57) return false;
      if (i < 12) {
        final d = c - 48;
        sum += i.isEven ? d : d * 3;
      }
    }
    return ((10 - (sum % 10)) % 10) == (code.codeUnitAt(12) - 48);
  }

  static Future<Uint8List> buildBarcodeLabelsPdfBytes({
    required Product product,
    required String code,
    required AppCurrency currency,
    required bool isThermal58x40,
    required int copies,
    bool showPrice = true,
    String shopName = '',
  }) async {
    final cleanCode = code.trim();
    final safeCopies = copies.clamp(1, 120);
    final unicodeFont = await _loadSystemUnicodeFont();
    final theme = unicodeFont != null
        ? pw.ThemeData.withFont(base: unicodeFont, bold: unicodeFont)
        : pw.ThemeData.base();

    final displayName = product.printName.trim().isNotEmpty
        ? product.printName.trim()
        : product.name.trim();
    final priceText = formatMoney(product.sellPrice, currency);
    final barcodeType =
        _isValidEan13(cleanCode) ? pw.Barcode.ean13() : pw.Barcode.code128();

    pw.Widget buildSingleLabel({
      required double barcodeWidth,
      required double barcodeHeight,
      required double titleFontSize,
      required double priceFontSize,
      required double shopFontSize,
      bool withBorder = false,
    }) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: withBorder
            ? pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              )
            : null,
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (shopName.trim().isNotEmpty)
              pw.Text(
                shopName.trim(),
                maxLines: 1,
                style: pw.TextStyle(
                  fontSize: shopFontSize,
                  color: PdfColors.grey700,
                ),
                textAlign: pw.TextAlign.center,
              ),
            pw.Text(
              displayName,
              maxLines: 2,
              style: pw.TextStyle(
                fontSize: titleFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
            if (showPrice)
              pw.Text(
                priceText,
                style: pw.TextStyle(
                  fontSize: priceFontSize,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            pw.BarcodeWidget(
              barcode: barcodeType,
              data: cleanCode,
              width: barcodeWidth,
              height: barcodeHeight,
              drawText: true,
              textStyle: const pw.TextStyle(fontSize: 7.5),
            ),
          ],
        ),
      );
    }

    final doc = pw.Document(theme: theme);
    if (isThermal58x40) {
      const pageFormat = PdfPageFormat(
        58 * PdfPageFormat.mm,
        40 * PdfPageFormat.mm,
        marginAll: 2.5 * PdfPageFormat.mm,
      );
      for (var i = 0; i < safeCopies; i++) {
        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (_) => buildSingleLabel(
              barcodeWidth: 46 * PdfPageFormat.mm,
              barcodeHeight: 15 * PdfPageFormat.mm,
              titleFontSize: 8.5,
              priceFontSize: 12,
              shopFontSize: 6.5,
            ),
          ),
        );
      }
    } else {
      const cols = 3;
      const rowsPerPage = 8;
      const perPage = cols * rowsPerPage;
      final totalPages = (safeCopies + perPage - 1) ~/ perPage;
      for (var page = 0; page < totalPages; page++) {
        final remaining = safeCopies - page * perPage;
        final pageCount = remaining > perPage ? perPage : remaining;
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
            build: (_) {
              final rowWidgets = <pw.Widget>[];
              for (var r = 0; r < rowsPerPage; r++) {
                final cells = <pw.Widget>[];
                for (var c = 0; c < cols; c++) {
                  final idx = r * cols + c;
                  cells.add(
                    pw.Expanded(
                      child: idx < pageCount
                          ? pw.Container(
                              height: 33 * PdfPageFormat.mm,
                              margin: const pw.EdgeInsets.all(1.5),
                              child: buildSingleLabel(
                                barcodeWidth: 50 * PdfPageFormat.mm,
                                barcodeHeight: 13 * PdfPageFormat.mm,
                                titleFontSize: 8,
                                priceFontSize: 10.5,
                                shopFontSize: 6,
                                withBorder: true,
                              ),
                            )
                          : pw.SizedBox(height: 33 * PdfPageFormat.mm),
                    ),
                  );
                }
                rowWidgets.add(pw.Row(children: cells));
              }
              return pw.Column(children: rowWidgets);
            },
          ),
        );
      }
    }

    return doc.save();
  }

  static Future<Uint8List> buildBatchPriceTagsPdfBytes({
    required List<Product> products,
    required AppCurrency currency,
    bool isThermal58x40 = false,
    bool showPrice = true,
    String shopName = '',
  }) async {
    final unicodeFont = await _loadSystemUnicodeFont();
    final theme = unicodeFont != null
        ? pw.ThemeData.withFont(base: unicodeFont, bold: unicodeFont)
        : pw.ThemeData.base();

    String resolveCode(Product p) {
      if (p.sku.trim().isNotEmpty) return p.sku.trim();
      if (p.packBarcode.trim().isNotEmpty) return p.packBarcode.trim();
      if (p.boxBarcode.trim().isNotEmpty) return p.boxBarcode.trim();
      return '';
    }

    pw.Widget buildTag(
      Product product, {
      required double barcodeWidth,
      required double barcodeHeight,
      required double titleFontSize,
      required double priceFontSize,
      required double shopFontSize,
      bool withBorder = false,
    }) {
      final displayName = product.printName.trim().isNotEmpty
          ? product.printName.trim()
          : product.name.trim();
      final priceText = formatMoney(product.sellPrice, currency);
      final code = resolveCode(product);
      final barcodeType =
          _isValidEan13(code) ? pw.Barcode.ean13() : pw.Barcode.code128();

      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: withBorder
            ? pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              )
            : null,
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (shopName.trim().isNotEmpty)
              pw.Text(
                shopName.trim(),
                maxLines: 1,
                style: pw.TextStyle(
                  fontSize: shopFontSize,
                  color: PdfColors.grey700,
                ),
                textAlign: pw.TextAlign.center,
              ),
            pw.Text(
              displayName,
              maxLines: 2,
              style: pw.TextStyle(
                fontSize: titleFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
            if (showPrice)
              pw.Text(
                priceText,
                style: pw.TextStyle(
                  fontSize: priceFontSize,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            if (code.isNotEmpty)
              pw.BarcodeWidget(
                barcode: barcodeType,
                data: code,
                width: barcodeWidth,
                height: barcodeHeight,
                drawText: true,
                textStyle: const pw.TextStyle(fontSize: 7.5),
              )
            else
              pw.SizedBox(height: barcodeHeight * 0.4),
          ],
        ),
      );
    }

    final doc = pw.Document(theme: theme);
    if (products.isEmpty) return doc.save();

    if (isThermal58x40) {
      const pageFormat = PdfPageFormat(
        58 * PdfPageFormat.mm,
        40 * PdfPageFormat.mm,
        marginAll: 2.5 * PdfPageFormat.mm,
      );
      for (final product in products) {
        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (_) => buildTag(
              product,
              barcodeWidth: 46 * PdfPageFormat.mm,
              barcodeHeight: 15 * PdfPageFormat.mm,
              titleFontSize: 8.5,
              priceFontSize: 12,
              shopFontSize: 6.5,
            ),
          ),
        );
      }
    } else {
      const cols = 3;
      const rowsPerPage = 8;
      const perPage = cols * rowsPerPage;
      final totalPages = (products.length + perPage - 1) ~/ perPage;
      for (var page = 0; page < totalPages; page++) {
        final start = page * perPage;
        final end = (start + perPage) > products.length
            ? products.length
            : (start + perPage);
        final pageItems = products.sublist(start, end);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
            build: (_) {
              final rowWidgets = <pw.Widget>[];
              for (var r = 0; r < rowsPerPage; r++) {
                final cells = <pw.Widget>[];
                for (var c = 0; c < cols; c++) {
                  final idx = r * cols + c;
                  cells.add(
                    pw.Expanded(
                      child: idx < pageItems.length
                          ? pw.Container(
                              height: 33 * PdfPageFormat.mm,
                              margin: const pw.EdgeInsets.all(1.5),
                              child: buildTag(
                                pageItems[idx],
                                barcodeWidth: 50 * PdfPageFormat.mm,
                                barcodeHeight: 13 * PdfPageFormat.mm,
                                titleFontSize: 8,
                                priceFontSize: 10.5,
                                shopFontSize: 6,
                                withBorder: true,
                              ),
                            )
                          : pw.SizedBox(height: 33 * PdfPageFormat.mm),
                    ),
                  );
                }
                rowWidgets.add(pw.Row(children: cells));
              }
              return pw.Column(children: rowWidgets);
            },
          ),
        );
      }
    }

    return doc.save();
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
    await writeTextFileAtomically(
      file,
      content,
      validateJson: filename.toLowerCase().endsWith('.json'),
    );
    return file.path;
  }

  static String buildYearArchiveJson({
    required int year,
    required List<Sale> sales,
    required List<StockInRecord> stockIns,
    required AppCurrency currency,
  }) {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'archiveType': 'year_end',
      'year': year,
      'currencyCode': currency.code,
      'exportedAt': DateTime.now().toIso8601String(),
      'salesCount': sales.length,
      'stockInsCount': stockIns.length,
      'sales': sales.map((s) => s.toJson()).toList(),
      'stockIns': stockIns.map((r) => r.toJson()).toList(),
    });
  }

  static String buildYearArchiveCsvWithBom({
    required int year,
    required List<Sale> sales,
    required List<StockInRecord> stockIns,
  }) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln('=== SALES $year ===');
    buffer.writeln(
      'ID;Date;Receipt;Customer;PaymentMethod;Items;Subtotal;Discount;Total;Cost;Paid;Debt;Profit',
    );
    for (final s in sales) {
      final itemsSummary = s.items
          .map(
            (i) =>
                '${i.productName} x${i.quantity} (${i.unitPrice.toStringAsFixed(0)})',
          )
          .join(', ');
      buffer.writeln(
        [
          _csvEscape(s.id),
          s.createdAt.toIso8601String(),
          _csvEscape(s.receiptCode),
          _csvEscape(s.customerName),
          _csvEscape(s.paymentMethod.name),
          _csvEscape(itemsSummary),
          s.subtotal.toStringAsFixed(2),
          s.discount.toStringAsFixed(2),
          s.total.toStringAsFixed(2),
          s.totalCost.toStringAsFixed(2),
          s.paidAmount.toStringAsFixed(2),
          s.remainingDebt.toStringAsFixed(2),
          s.profit.toStringAsFixed(2),
        ].join(';'),
      );
    }
    buffer.writeln();
    buffer.writeln('=== STOCK-IN INVOICES $year ===');
    buffer.writeln('ID;Date;Supplier;Currency;Rate;Units;TotalCost;Items');
    for (final r in stockIns) {
      final itemsSummary = r.items
          .map(
            (i) =>
                '${i.productName} x${i.quantity} (${i.unitCost.toStringAsFixed(0)})',
          )
          .join(', ');
      buffer.writeln(
        [
          _csvEscape(r.id),
          r.createdAt.toIso8601String(),
          _csvEscape(r.supplierName),
          _csvEscape(r.currencyCode),
          r.exchangeRate?.toStringAsFixed(2) ?? '',
          '${r.totalUnits}',
          r.totalCost.toStringAsFixed(2),
          _csvEscape(itemsSummary),
        ].join(';'),
      );
    }
    return buffer.toString();
  }

  static Future<({String jsonPath, String csvPath})> saveYearArchiveFiles({
    required int year,
    required List<Sale> sales,
    required List<StockInRecord> stockIns,
    required AppCurrency currency,
  }) async {
    final jsonContent = buildYearArchiveJson(
      year: year,
      sales: sales,
      stockIns: stockIns,
      currency: currency,
    );
    final csvContent = buildYearArchiveCsvWithBom(
      year: year,
      sales: sales,
      stockIns: stockIns,
    );
    final jsonPath = await saveExportFile(
      'lumio_archive_$year.json',
      jsonContent,
    );
    final csvPath = await saveExportFile(
      'lumio_archive_$year.csv',
      csvContent,
    );
    return (jsonPath: jsonPath, csvPath: csvPath);
  }

  static String buildPriceListText({
    required List<Product> products,
    required AppStrings strings,
    required AppCurrency currency,
    String? category,
    bool inStockOnly = true,
    bool newArrivalsOnly = false,
    bool includeWholesale = true,
    bool includeStock = false,
    String shopName = 'Lumio',
    String shopPhone = '',
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final cutoff = current.subtract(const Duration(days: 14));
    final cleanCategory = category?.trim();

    final filtered = products.where((p) {
      if (!p.isActive) return false;
      if (cleanCategory != null &&
          cleanCategory.isNotEmpty &&
          p.category.trim() != cleanCategory) {
        return false;
      }
      if (inStockOnly && p.stock <= 0) return false;
      if (newArrivalsOnly && p.updatedAt.isBefore(cutoff)) return false;
      return true;
    }).toList();

    if (filtered.isEmpty) return '';

    filtered.sort((a, b) {
      final catCmp = a.category.toLowerCase().compareTo(b.category.toLowerCase());
      if (catCmp != 0) return catCmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final lines = <String>[];
    if (shopName.trim().isNotEmpty) {
      lines.add('*${shopName.trim()}*');
    }
    if (shopPhone.trim().isNotEmpty) {
      lines.add(shopPhone.trim());
    }
    final title = (cleanCategory != null && cleanCategory.isNotEmpty)
        ? '${strings.priceListTitle} — $cleanCategory'
        : strings.priceListTitle;
    lines.add(title);
    lines.add(formatDate(current));
    lines.add('---');

    String formatLine(int idx, Product p) {
      final unitSuffix = p.unit.trim().isNotEmpty ? '/${p.unit.trim()}' : '';
      final sb = StringBuffer(
        '$idx. ${p.name} — ${formatMoney(p.sellPrice, currency)}$unitSuffix',
      );
      if (includeWholesale && p.hasWholesalePrice) {
        final minQtyPart = p.wholesaleMinQty > 0
            ? ' (${strings.wholesaleFromQtyBadge(p.wholesaleMinQty)})'
            : '';
        sb.write(
          ' | ${strings.wholesaleShort}: ${formatMoney(p.wholesalePrice, currency)}$minQtyPart',
        );
      }
      if (includeStock) {
        sb.write(' • ${formatQty(p.stock)}');
      }
      return sb.toString();
    }

    if (cleanCategory != null && cleanCategory.isNotEmpty) {
      for (var i = 0; i < filtered.length; i++) {
        lines.add(formatLine(i + 1, filtered[i]));
      }
    } else {
      final grouped = <String, List<Product>>{};
      for (final p in filtered) {
        final cat = p.category.trim().isEmpty ? 'General' : p.category.trim();
        grouped.putIfAbsent(cat, () => <Product>[]).add(p);
      }
      var firstGroup = true;
      for (final entry in grouped.entries) {
        if (!firstGroup) lines.add('');
        firstGroup = false;
        lines.add('*${entry.key}*');
        for (var i = 0; i < entry.value.length; i++) {
          lines.add(formatLine(i + 1, entry.value[i]));
        }
      }
    }

    return lines.join('\n');
  }
}
