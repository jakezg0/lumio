import 'dart:convert';
import 'dart:io';

import '../l10n/app_strings.dart';
import '../models/customer.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/stock_in.dart';
import '../widgets/formatters.dart';
import 'export_service.dart';
import 'inventory_storage.dart';

enum ConflictResolution {
  useSheet,
  keepLocal,
}

class SyncFieldDiff {
  const SyncFieldDiff({
    required this.fieldLabel,
    required this.localValue,
    required this.remoteValue,
    this.deltaLabel,
  });

  final String fieldLabel;
  final String localValue;
  final String remoteValue;
  final String? deltaLabel;
}

class SyncConflict {
  SyncConflict({
    required this.localProduct,
    required this.remoteProduct,
    required this.diffs,
    this.resolution = ConflictResolution.useSheet,
  });

  final Product localProduct;
  final Product remoteProduct;
  final List<SyncFieldDiff> diffs;
  ConflictResolution resolution;
}

class SheetSyncPreview {
  const SheetSyncPreview({
    required this.conflicts,
    required this.onlyInSheet,
    required this.onlyOnPhone,
    required this.matchedCount,
  });

  final List<SyncConflict> conflicts;
  final List<Product> onlyInSheet;
  final List<Product> onlyOnPhone;
  final int matchedCount;

  bool get hasChanges =>
      conflicts.isNotEmpty || onlyInSheet.isNotEmpty || onlyOnPhone.isNotEmpty;
}

class GoogleSheetsSyncException implements Exception {
  const GoogleSheetsSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GoogleSheetsService {
  const GoogleSheetsService();

  static const String appsScriptTemplate = r'''
const SHEET_NAME = 'Catalog';
const SPREADSHEET_ID = ''; // Если скрипт создан отдельно на script.google.com, вставьте ID таблицы из URL
const SECRET = ''; // Необязательно: укажите такой же ключ, как в приложении

const HEADERS = [
  'id',
  'name',
  'category',
  'sku',
  'costPrice',
  'sellPrice',
  'stock',
  'lowStockThreshold',
  'packQty',
  'boxQty',
  'packBarcode',
  'boxBarcode',
  'unitWeight',
  'unit',
  'nomenclature',
  'printName',
  'updatedAt'
];

function getOrCreateSheet_() {
  const ss = SPREADSHEET_ID
    ? SpreadsheetApp.openById(SPREADSHEET_ID)
    : SpreadsheetApp.getActiveSpreadsheet();
  if (!ss) {
    throw new Error('Укажите SPREADSHEET_ID в скрипте или откройте Apps Script из самой Google Таблицы (Расширения -> Apps Script)');
  }
  let sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(SHEET_NAME);
  }
  if (sheet.getLastRow() === 0) {
    sheet.appendRow(HEADERS);
  }
  return sheet;
}

function checkSecret_(provided) {
  if (SECRET && String(provided || '') !== SECRET) {
    throw new Error('Invalid secret key');
  }
}

function jsonOut_(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

function doGet(e) {
  try {
    checkSecret_(e && e.parameter ? e.parameter.secret : '');
    if (e && e.parameter && e.parameter.action === 'backup') {
      const ss = SPREADSHEET_ID
        ? SpreadsheetApp.openById(SPREADSHEET_ID)
        : SpreadsheetApp.getActiveSpreadsheet();
      if (!ss) {
        throw new Error('Укажите SPREADSHEET_ID в скрипте или откройте Apps Script из самой Google Таблицы');
      }
      const bSheet = ss.getSheetByName('_Backup');
      if (!bSheet || bSheet.getLastRow() <= 1) {
        return jsonOut_({ ok: true, sections: {}, backupJson: '', updatedAt: '' });
      }
      const bValues = bSheet.getDataRange().getValues();
      const firstHeader = String(bValues[0][0] || '').trim();
      if (firstHeader === 'section') {
        const grouped = {};
        let latestAt = '';
        for (let i = 1; i < bValues.length; i++) {
          const r = bValues[i];
          const sec = String(r[0] || '').trim();
          if (!sec) continue;
          const ts = String(r[1] || '');
          if (ts > latestAt) latestAt = ts;
          if (!grouped[sec]) grouped[sec] = [];
          grouped[sec].push({ idx: Number(r[2] || 0), data: String(r[4] || '') });
        }
        const sections = {};
        Object.keys(grouped).forEach(sec => {
          grouped[sec].sort((a, b) => a.idx - b.idx);
          sections[sec] = grouped[sec].map(item => item.data).join('');
        });
        return jsonOut_({ ok: true, sections, updatedAt: latestAt });
      }
      const rows = [];
      let updatedAt = '';
      for (let i = 1; i < bValues.length; i++) {
        const r = bValues[i];
        if (!updatedAt && r[0]) updatedAt = String(r[0]);
        rows.push({ idx: Number(r[1] || 0), data: String(r[3] || '') });
      }
      rows.sort((a, b) => a.idx - b.idx);
      const backupJson = rows.map(r => r.data).join('');
      return jsonOut_({ ok: true, backupJson, updatedAt });
    }

    const sheet = getOrCreateSheet_();
    const values = sheet.getDataRange().getValues();
    if (values.length <= 1) {
      return jsonOut_({ ok: true, products: [] });
    }
    const headers = values[0].map(h => String(h).trim());
    const products = [];
    for (let i = 1; i < values.length; i++) {
      const row = values[i];
      const obj = {};
      let hasData = false;
      for (let c = 0; c < headers.length; c++) {
        const key = headers[c];
        if (!key) continue;
        const val = row[c];
        if (val !== '' && val !== null && val !== undefined) hasData = true;
        obj[key] = val;
      }
      if (hasData && String(obj.name || '').trim() !== '') {
        products.push(obj);
      }
    }
    return jsonOut_({ ok: true, products });
  } catch (err) {
    return jsonOut_({ ok: false, error: String(err) });
  }
}

function doPost(e) {
  try {
    const body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    checkSecret_(body.secret);

    if (body.action === 'saveBackupDelta' && body.sections && typeof body.sections === 'object') {
      const ss = SPREADSHEET_ID
        ? SpreadsheetApp.openById(SPREADSHEET_ID)
        : SpreadsheetApp.getActiveSpreadsheet();
      if (!ss) {
        throw new Error('Укажите SPREADSHEET_ID в скрипте или откройте Apps Script из самой Google Таблицы');
      }
      let bSheet = ss.getSheetByName('_Backup');
      if (!bSheet) {
        bSheet = ss.insertSheet('_Backup');
      }
      const bHeaders = ['section', 'updatedAt', 'chunkIndex', 'totalChunks', 'data'];
      const ts = String(body.updatedAt || new Date().toISOString());
      const incoming = body.sections;
      const incomingKeys = Object.keys(incoming);
      const removed = Array.isArray(body.removedSections) ? body.removedSections : [];
      const skipSet = {};
      incomingKeys.forEach(k => { skipSet[k] = true; });
      removed.forEach(k => { skipSet[String(k)] = true; });

      const keptRows = [];
      if (!body.resetAll && bSheet.getLastRow() > 1) {
        const existing = bSheet.getDataRange().getValues();
        if (String(existing[0][0] || '').trim() === 'section') {
          for (let i = 1; i < existing.length; i++) {
            const sec = String(existing[i][0] || '').trim();
            if (sec && !skipSet[sec]) {
              keptRows.push(existing[i].slice(0, 5));
            }
          }
        }
      }

      incomingKeys.forEach(sec => {
        const chunks = Array.isArray(incoming[sec]) ? incoming[sec] : [String(incoming[sec] || '')];
        const total = chunks.length;
        chunks.forEach((c, idx) => {
          keptRows.push([sec, ts, idx, total, String(c || '')]);
        });
      });

      bSheet.clearContents();
      bSheet.appendRow(bHeaders);
      if (keptRows.length > 0) {
        bSheet.getRange(2, 1, keptRows.length, bHeaders.length).setValues(keptRows);
      }
      return jsonOut_({ ok: true, action: 'saveBackupDelta', updatedSections: incomingKeys.length });
    }

    if (body.action === 'saveBackup' && Array.isArray(body.chunks)) {
      const ss = SPREADSHEET_ID
        ? SpreadsheetApp.openById(SPREADSHEET_ID)
        : SpreadsheetApp.getActiveSpreadsheet();
      if (!ss) {
        throw new Error('Укажите SPREADSHEET_ID в скрипте или откройте Apps Script из самой Google Таблицы');
      }
      let bSheet = ss.getSheetByName('_Backup');
      if (!bSheet) {
        bSheet = ss.insertSheet('_Backup');
      }
      bSheet.clearContents();
      const bHeaders = ['updatedAt', 'chunkIndex', 'totalChunks', 'data'];
      bSheet.appendRow(bHeaders);
      const ts = String(body.updatedAt || new Date().toISOString());
      const total = body.chunks.length;
      if (total > 0) {
        const bRows = body.chunks.map((c, idx) => [ts, idx, total, String(c || '')]);
        bSheet.getRange(2, 1, bRows.length, bHeaders.length).setValues(bRows);
      }
      return jsonOut_({ ok: true, action: 'saveBackup', chunks: total });
    }

    if (body.sheetName && Array.isArray(body.headers) && Array.isArray(body.rows)) {
      const ss = SPREADSHEET_ID
        ? SpreadsheetApp.openById(SPREADSHEET_ID)
        : SpreadsheetApp.getActiveSpreadsheet();
      if (!ss) {
        throw new Error('Укажите SPREADSHEET_ID в скрипте или откройте Apps Script из самой Google Таблицы');
      }
      const targetName = String(body.sheetName).trim() || 'Export';
      let targetSheet = ss.getSheetByName(targetName);
      if (!targetSheet) {
        targetSheet = ss.insertSheet(targetName);
      }
      if (!body.append) {
        targetSheet.clearContents();
        targetSheet.appendRow(body.headers);
      }
      if (body.rows.length > 0) {
        const startRow = targetSheet.getLastRow() + 1;
        targetSheet.getRange(startRow, 1, body.rows.length, body.headers.length).setValues(body.rows);
      }
      return jsonOut_({ ok: true, count: body.rows.length, sheetName: targetName });
    }

    const products = Array.isArray(body.products) ? body.products : [];
    const sheet = getOrCreateSheet_();
    if (!body.append) {
      sheet.clearContents();
      sheet.appendRow(HEADERS);
    }
    if (products.length > 0) {
      const rows = products.map(p => HEADERS.map(h => (p[h] !== undefined && p[h] !== null) ? p[h] : ''));
      const startRow = sheet.getLastRow() + 1;
      sheet.getRange(startRow, 1, rows.length, HEADERS.length).setValues(rows);
    }
    return jsonOut_({ ok: true, count: products.length });
  } catch (err) {
    return jsonOut_({ ok: false, error: String(err) });
  }
}
''';

  Uri _buildGetUri(String rawUrl, String secret) {
    final uri = Uri.parse(rawUrl.trim());
    if (secret.trim().isEmpty) return uri;
    final params = Map<String, String>.from(uri.queryParameters);
    params['secret'] = secret.trim();
    return uri.replace(queryParameters: params);
  }

  Future<List<Product>> fetchProducts(
    String webAppUrl, {
    String secret = '',
  }) async {
    final cleanUrl = webAppUrl.trim();
    if (cleanUrl.isEmpty) {
      throw const GoogleSheetsSyncException('URL is empty');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(_buildGetUri(cleanUrl, secret));
      request.followRedirects = true;
      request.maxRedirects = 6;
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleSheetsSyncException('HTTP ${response.statusCode}: $body');
      }
      if (body.trimLeft().startsWith('<')) {
        throw const GoogleSheetsSyncException(
          'Google вернул HTML вместо JSON. Проверьте, что в Apps Script в поле «Who has access» выбрано «Anyone».',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const GoogleSheetsSyncException('Invalid JSON response from Google Sheets');
      }
      if (decoded['ok'] != true) {
        throw GoogleSheetsSyncException(
          (decoded['error'] as String?) ?? 'Google Sheets script error',
        );
      }
      final rawList = decoded['products'] as List<dynamic>? ?? const [];
      final now = DateTime.now();
      return rawList
          .whereType<Map<String, dynamic>>()
          .map((row) => _productFromSheetRow(row, now))
          .where((p) => p.name.trim().isNotEmpty)
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  Future<int> pushProducts(
    String webAppUrl,
    List<Product> products, {
    String secret = '',
    void Function(int sent, int total)? onProgress,
  }) async {
    final cleanUrl = webAppUrl.trim();
    if (cleanUrl.isEmpty) {
      throw const GoogleSheetsSyncException('URL is empty');
    }
    const batchSize = 500;
    if (products.isEmpty) {
      await _pushBatch(cleanUrl, const [], secret: secret, append: false);
      onProgress?.call(0, 0);
      return 0;
    }
    var totalPushed = 0;
    for (var i = 0; i < products.length; i += batchSize) {
      final end =
          (i + batchSize < products.length) ? i + batchSize : products.length;
      final batch = products.sublist(i, end);
      await _pushBatch(
        cleanUrl,
        batch,
        secret: secret,
        append: i > 0,
      );
      totalPushed += batch.length;
      onProgress?.call(totalPushed, products.length);
    }
    return totalPushed;
  }

  static String buildTsv(List<String> headers, List<List<dynamic>> rows) {
    String cleanCell(dynamic val) {
      final s = '${val ?? ''}'.replaceAll('\t', ' ').replaceAll('\r', ' ').replaceAll('\n', ' ');
      return s;
    }

    final lines = <String>[
      headers.map(cleanCell).join('\t'),
      for (final row in rows) row.map(cleanCell).join('\t'),
    ];
    return lines.join('\n');
  }

  Future<int> pushTable({
    required String webAppUrl,
    required String sheetName,
    required List<String> headers,
    required List<List<dynamic>> rows,
    String secret = '',
    void Function(int sent, int total)? onProgress,
  }) async {
    final cleanUrl = webAppUrl.trim();
    if (cleanUrl.isEmpty) {
      throw const GoogleSheetsSyncException('URL is empty');
    }
    const batchSize = 500;
    if (rows.isEmpty) {
      await _postJsonPayload(
        cleanUrl,
        {
          'secret': secret.trim(),
          'sheetName': sheetName.trim(),
          'headers': headers,
          'append': false,
          'rows': const [],
        },
        expectSheetName: true,
      );
      onProgress?.call(0, 0);
      return 0;
    }
    var totalPushed = 0;
    for (var i = 0; i < rows.length; i += batchSize) {
      final end = (i + batchSize < rows.length) ? i + batchSize : rows.length;
      final batch = rows.sublist(i, end);
      await _postJsonPayload(
        cleanUrl,
        {
          'secret': secret.trim(),
          'sheetName': sheetName.trim(),
          'headers': headers,
          'append': i > 0,
          'rows': batch,
        },
        expectSheetName: true,
      );
      totalPushed += batch.length;
      onProgress?.call(totalPushed, rows.length);
    }
    return totalPushed;
  }

  static int _stableBucket(String id, int buckets) {
    var hash = 2166136261;
    for (var i = 0; i < id.length; i++) {
      hash ^= id.codeUnitAt(i);
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash % buckets;
  }

  static String hashText(String input) {
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (var i = 0; i < input.length; i++) {
      final c = input.codeUnitAt(i);
      h1 ^= c;
      h1 = (h1 * 16777619) & 0xffffffff;
      h2 ^= (c + i);
      h2 = (h2 * 16777619) & 0xffffffff;
    }
    return '${input.length}_${h1.toRadixString(16)}_${h2.toRadixString(16)}';
  }

  static String _monthKey(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    return '${dt.year}_$m';
  }

  static Map<String, String> buildBackupSectionJsons(ShopDataSnapshot snapshot) {
    final sections = <String, String>{};

    final productBuckets = <int, List<Map<String, dynamic>>>{};
    for (final p in snapshot.products) {
      final b = _stableBucket(p.id, 8);
      productBuckets.putIfAbsent(b, () => []).add(p.toJson());
    }
    for (final entry in productBuckets.entries) {
      sections['products_${entry.key}'] = jsonEncode(entry.value);
    }

    final salesByMonth = <String, List<Map<String, dynamic>>>{};
    for (final s in snapshot.sales) {
      final key = 'sales_${_monthKey(s.createdAt)}';
      salesByMonth.putIfAbsent(key, () => []).add(s.toJson());
    }
    for (final entry in salesByMonth.entries) {
      sections[entry.key] = jsonEncode(entry.value);
    }

    final changesByMonth = <String, List<Map<String, dynamic>>>{};
    for (final c in snapshot.productChanges) {
      final key = 'changes_${_monthKey(c.createdAt)}';
      changesByMonth.putIfAbsent(key, () => []).add(c.toJson());
    }
    for (final entry in changesByMonth.entries) {
      sections[entry.key] = jsonEncode(entry.value);
    }

    sections['expenses'] = jsonEncode(
      snapshot.expenses.map((e) => e.toJson()).toList(),
    );
    sections['customers'] = jsonEncode(
      snapshot.customers.map((c) => c.toJson()).toList(),
    );
    sections['stockIns'] = jsonEncode(
      snapshot.stockIns.map((s) => s.toJson()).toList(),
    );
    sections['meta'] = jsonEncode({
      'languageCode': snapshot.languageCode,
      'currencyCode': snapshot.currencyCode,
      'shopName': snapshot.shopName,
      'shopAddress': snapshot.shopAddress,
      'shopPhone': snapshot.shopPhone,
      'receiptFooter': snapshot.receiptFooter,
      'ownerPin': snapshot.ownerPin,
      'useBiometricUnlock': snapshot.useBiometricUnlock,
      'cashierMode': snapshot.cashierMode,
      'catalogSeeded': snapshot.catalogSeeded,
      'googleSheetsUrl': snapshot.googleSheetsUrl,
      'googleSheetsSecret': snapshot.googleSheetsSecret,
      'customCategories': snapshot.customCategories,
      'stockInDraft': snapshot.stockInDraft?.toJson(),
      'stocktakeDraft': snapshot.stocktakeDraft?.toJson(),
      'heldSales': snapshot.heldSales.map((h) => h.toJson()).toList(),
      'negativeStockReminders': snapshot.negativeStockReminders,
      'allowNegativeStock': snapshot.allowNegativeStock,
      'autoBackupEnabled': snapshot.autoBackupEnabled,
    });

    return sections;
  }

  static String compressSection(String rawJson) {
    final gzBytes = gzip.encode(utf8.encode(rawJson));
    return 'gz:${base64Encode(gzBytes)}';
  }

  static String decompressSection(String stored) {
    if (stored.startsWith('gz:')) {
      final gzBytes = base64Decode(stored.substring(3));
      return utf8.decode(gzip.decode(gzBytes));
    }
    return stored;
  }

  static List<String> _splitIntoChunks(String data, {int chunkSize = 40000}) {
    if (data.isEmpty) return const [''];
    final chunks = <String>[];
    for (var i = 0; i < data.length; i += chunkSize) {
      final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
      chunks.add(data.substring(i, end));
    }
    return chunks;
  }

  static ShopDataSnapshot parseSnapshotFromSections(
    Map<String, String> encodedSections,
  ) {
    final products = <Product>[];
    final sales = <Sale>[];
    final productChanges = <ProductChangeEntry>[];
    var expenses = <Expense>[];
    var customers = <Customer>[];
    var stockIns = <StockInRecord>[];
    var meta = <String, dynamic>{};

    for (final entry in encodedSections.entries) {
      final key = entry.key;
      final raw = decompressSection(entry.value);
      if (raw.trim().isEmpty) continue;
      final decoded = jsonDecode(raw);
      if (key.startsWith('products_') && decoded is List) {
        products.addAll(
          decoded
              .whereType<Map<String, dynamic>>()
              .map(Product.fromJson),
        );
      } else if (key.startsWith('sales_') && decoded is List) {
        sales.addAll(
          decoded
              .whereType<Map<String, dynamic>>()
              .map(Sale.fromJson),
        );
      } else if (key.startsWith('changes_') && decoded is List) {
        productChanges.addAll(
          decoded
              .whereType<Map<String, dynamic>>()
              .map(ProductChangeEntry.fromJson),
        );
      } else if (key == 'expenses' && decoded is List) {
        expenses = decoded
            .whereType<Map<String, dynamic>>()
            .map(Expense.fromJson)
            .toList();
      } else if (key == 'customers' && decoded is List) {
        customers = decoded
            .whereType<Map<String, dynamic>>()
            .map(Customer.fromJson)
            .toList();
      } else if (key == 'stockIns' && decoded is List) {
        stockIns = decoded
            .whereType<Map<String, dynamic>>()
            .map(StockInRecord.fromJson)
            .toList();
      } else if (key == 'meta' && decoded is Map<String, dynamic>) {
        meta = decoded;
      }
    }

    final rawCustomCats = meta['customCategories'] as List<dynamic>? ?? const [];
    final rawHeldSales = meta['heldSales'] as List<dynamic>? ?? const [];
    final rawReminders =
        meta['negativeStockReminders'] as Map<String, dynamic>? ?? const {};

    return ShopDataSnapshot(
      products: products,
      sales: sales,
      expenses: expenses,
      customers: customers,
      stockIns: stockIns,
      productChanges: productChanges,
      languageCode: (meta['languageCode'] as String?) ?? 'auto',
      currencyCode: (meta['currencyCode'] as String?) ?? 'kzt',
      shopName: (meta['shopName'] as String?) ?? 'Lumio',
      shopAddress: (meta['shopAddress'] as String?) ?? '',
      shopPhone: (meta['shopPhone'] as String?) ?? '',
      receiptFooter: (meta['receiptFooter'] as String?) ?? '',
      ownerPin: (meta['ownerPin'] as String?) ?? '',
      useBiometricUnlock: (meta['useBiometricUnlock'] as bool?) ?? false,
      cashierMode: (meta['cashierMode'] as bool?) ?? true,
      catalogSeeded: (meta['catalogSeeded'] as bool?) ?? true,
      googleSheetsUrl: (meta['googleSheetsUrl'] as String?) ?? '',
      googleSheetsSecret: (meta['googleSheetsSecret'] as String?) ?? '',
      customCategories: rawCustomCats.map((e) => '$e').toList(),
      stockInDraft: meta['stockInDraft'] is Map<String, dynamic>
          ? StockInDraft.fromJson(meta['stockInDraft'] as Map<String, dynamic>)
          : null,
      stocktakeDraft: meta['stocktakeDraft'] is Map<String, dynamic>
          ? StocktakeDraft.fromJson(
              meta['stocktakeDraft'] as Map<String, dynamic>,
            )
          : null,
      heldSales: rawHeldSales
          .whereType<Map<String, dynamic>>()
          .map(HeldSale.fromJson)
          .toList(),
      negativeStockReminders: rawReminders
          .map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0))
        ..removeWhere((_, v) => v <= 0),
      allowNegativeStock: (meta['allowNegativeStock'] as bool?) ?? true,
      autoBackupEnabled: (meta['autoBackupEnabled'] as bool?) ?? true,
    );
  }

  Future<int> pushBackupDelta({
    required String webAppUrl,
    required Map<String, String> changedCompressedSections,
    List<String> removedSections = const [],
    bool resetAll = false,
    String secret = '',
  }) async {
    final cleanUrl = webAppUrl.trim();
    if (cleanUrl.isEmpty) {
      throw const GoogleSheetsSyncException('URL is empty');
    }
    if (!resetAll &&
        changedCompressedSections.isEmpty &&
        removedSections.isEmpty) {
      return 0;
    }
    final payloadSections = <String, List<String>>{
      for (final entry in changedCompressedSections.entries)
        entry.key: _splitIntoChunks(entry.value),
    };
    await _postJsonPayload(
      cleanUrl,
      {
        'secret': secret.trim(),
        'action': 'saveBackupDelta',
        'resetAll': resetAll,
        'updatedAt': DateTime.now().toIso8601String(),
        'sections': payloadSections,
        if (removedSections.isNotEmpty) 'removedSections': removedSections,
      },
      expectAction: 'saveBackupDelta',
    );
    return changedCompressedSections.length;
  }

  Future<({ShopDataSnapshot? snapshot, String? updatedAt})> fetchCloudBackup(
    String webAppUrl, {
    String secret = '',
  }) async {
    final cleanUrl = webAppUrl.trim();
    if (cleanUrl.isEmpty) {
      throw const GoogleSheetsSyncException('URL is empty');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
    try {
      final baseUri = _buildGetUri(cleanUrl, secret);
      final params = Map<String, String>.from(baseUri.queryParameters);
      params['action'] = 'backup';
      final request = await client.getUrl(
        baseUri.replace(queryParameters: params),
      );
      request.followRedirects = true;
      request.maxRedirects = 6;
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleSheetsSyncException('HTTP ${response.statusCode}: $body');
      }
      if (body.trimLeft().startsWith('<')) {
        throw const GoogleSheetsSyncException(
          'Google вернул HTML вместо JSON. Проверьте, что в Apps Script в поле «Who has access» выбрано «Anyone».',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const GoogleSheetsSyncException(
          'Invalid JSON response from Google Sheets',
        );
      }
      if (decoded['ok'] != true) {
        throw GoogleSheetsSyncException(
          (decoded['error'] as String?) ?? 'Google Sheets script error',
        );
      }
      final updatedAt = (decoded['updatedAt'] as String?)?.trim();
      if (decoded['sections'] is Map<String, dynamic>) {
        final rawSections =
            (decoded['sections'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, '$v'),
        );
        if (rawSections.isEmpty) {
          return (snapshot: null, updatedAt: updatedAt);
        }
        return (
          snapshot: parseSnapshotFromSections(rawSections),
          updatedAt: updatedAt,
        );
      }
      if (decoded.containsKey('backupJson')) {
        final backupJson = (decoded['backupJson'] as String?) ?? '';
        if (backupJson.trim().isEmpty) {
          return (snapshot: null, updatedAt: updatedAt);
        }
        return (
          snapshot: ExportService.parseBackupJson(backupJson),
          updatedAt: updatedAt,
        );
      }
      throw const GoogleSheetsSyncException(
        'В Google Таблице всё ещё старая версия Apps Script. Скопируйте новый скрипт, сохраните и выберите «Управление развёртываниями -> Новая версия».',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _pushBatch(
    String cleanUrl,
    List<Product> batch, {
    required String secret,
    required bool append,
  }) async {
    await _postJsonPayload(
      cleanUrl,
      {
        'secret': secret.trim(),
        'append': append,
        'products': batch.map((p) => _productToSheetRow(p)).toList(),
      },
    );
  }

  Future<void> _postJsonPayload(
    String cleanUrl,
    Map<String, dynamic> bodyMap, {
    bool expectSheetName = false,
    String? expectAction,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 60);
    try {
      final uri = Uri.parse(cleanUrl);
      final payload = jsonEncode(bodyMap);
      final bytes = utf8.encode(payload);
      final request = await client.postUrl(uri);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
      var response = await request.close();

      // Google Apps Script Web Apps respond to POST with 302 redirect to script.googleusercontent.com
      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 303 ||
          response.statusCode == 307) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location != null && location.isNotEmpty) {
          final redirectUri = uri.resolve(location);
          final getReq = await client.getUrl(redirectUri);
          getReq.followRedirects = true;
          response = await getReq.close();
        }
      }

      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleSheetsSyncException('HTTP ${response.statusCode}: $body');
      }
      if (body.trimLeft().startsWith('<')) {
        throw const GoogleSheetsSyncException(
          'Google вернул HTML вместо JSON. Проверьте, что в Apps Script в поле «Who has access» выбрано «Anyone».',
        );
      }
      if (body.trim().isNotEmpty) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          if (decoded['ok'] == false) {
            throw GoogleSheetsSyncException(
              (decoded['error'] as String?) ?? 'Google Sheets script error',
            );
          }
          if ((expectSheetName && decoded['sheetName'] == null) ||
              (expectAction != null && decoded['action'] != expectAction)) {
            throw const GoogleSheetsSyncException(
              'В Google Таблице всё ещё работает старая версия Apps Script. Скопируйте новый скрипт, вставьте его в Apps Script, сохраните и выберите «Управление развёртываниями -> Новая версия».',
            );
          }
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  SheetSyncPreview buildPreview({
    required List<Product> localProducts,
    required List<Product> remoteProducts,
    required AppStrings strings,
    required AppCurrency currency,
  }) {
    final localById = <String, Product>{
      for (final p in localProducts) p.id: p,
    };
    final localBySku = <String, Product>{};
    for (final p in localProducts) {
      final sku = p.sku.trim().toLowerCase();
      if (sku.isNotEmpty && !localBySku.containsKey(sku)) {
        localBySku[sku] = p;
      }
    }

    final matchedLocalIds = <String>{};
    final conflicts = <SyncConflict>[];
    final onlyInSheet = <Product>[];
    var matchedCount = 0;

    for (final remote in remoteProducts) {
      Product? local;
      if (remote.id.trim().isNotEmpty && localById.containsKey(remote.id)) {
        local = localById[remote.id];
      } else {
        final sku = remote.sku.trim().toLowerCase();
        if (sku.isNotEmpty && localBySku.containsKey(sku)) {
          local = localBySku[sku];
        }
      }

      if (local == null) {
        onlyInSheet.add(remote);
        continue;
      }

      matchedLocalIds.add(local.id);
      matchedCount += 1;

      final normalizedRemote = remote.copyWith(id: local.id);
      final diffs = _computeDiffs(
        local: local,
        remote: normalizedRemote,
        strings: strings,
        currency: currency,
      );
      if (diffs.isNotEmpty) {
        conflicts.add(
          SyncConflict(
            localProduct: local,
            remoteProduct: normalizedRemote,
            diffs: diffs,
          ),
        );
      }
    }

    final onlyOnPhone = localProducts
        .where((p) => !matchedLocalIds.contains(p.id))
        .toList();

    return SheetSyncPreview(
      conflicts: conflicts,
      onlyInSheet: onlyInSheet,
      onlyOnPhone: onlyOnPhone,
      matchedCount: matchedCount,
    );
  }

  List<SyncFieldDiff> _computeDiffs({
    required Product local,
    required Product remote,
    required AppStrings strings,
    required AppCurrency currency,
  }) {
    final diffs = <SyncFieldDiff>[];

    if (local.name.trim() != remote.name.trim()) {
      diffs.add(
        SyncFieldDiff(
          fieldLabel: strings.productNameRequired.replaceAll(' *', ''),
          localValue: local.name,
          remoteValue: remote.name,
        ),
      );
    }
    if (local.category.trim() != remote.category.trim()) {
      diffs.add(
        SyncFieldDiff(
          fieldLabel: strings.categoryLabel,
          localValue: local.category,
          remoteValue: remote.category,
        ),
      );
    }
    if (local.sku.trim() != remote.sku.trim()) {
      diffs.add(
        SyncFieldDiff(
          fieldLabel: strings.skuLabel,
          localValue: local.sku.isEmpty ? '—' : local.sku,
          remoteValue: remote.sku.isEmpty ? '—' : remote.sku,
        ),
      );
    }
    if ((local.costPrice - remote.costPrice).abs() > 0.009) {
      final delta = remote.costPrice - local.costPrice;
      final sign = delta > 0 ? '+' : '-';
      diffs.add(
        SyncFieldDiff(
          fieldLabel: strings.costShort,
          localValue: formatMoney(local.costPrice, currency),
          remoteValue: formatMoney(remote.costPrice, currency),
          deltaLabel: '$sign${formatMoney(delta.abs(), currency)}',
        ),
      );
    }
    if ((local.sellPrice - remote.sellPrice).abs() > 0.009) {
      final delta = remote.sellPrice - local.sellPrice;
      final sign = delta > 0 ? '+' : '-';
      diffs.add(
        SyncFieldDiff(
          fieldLabel: strings.sellShort,
          localValue: formatMoney(local.sellPrice, currency),
          remoteValue: formatMoney(remote.sellPrice, currency),
          deltaLabel: '$sign${formatMoney(delta.abs(), currency)}',
        ),
      );
    }
    if (local.stock != remote.stock) {
      final delta = remote.stock - local.stock;
      final sign = delta > 0 ? '+' : '';
      diffs.add(
        SyncFieldDiff(
          fieldLabel: strings.stockQtyRequired.replaceAll(' *', ''),
          localValue: '${local.stock}',
          remoteValue: '${remote.stock}',
          deltaLabel: '$sign$delta',
        ),
      );
    }
    if (local.lowStockThreshold != remote.lowStockThreshold) {
      diffs.add(
        SyncFieldDiff(
          fieldLabel: strings.lowStockAlertLabel,
          localValue: '${local.lowStockThreshold}',
          remoteValue: '${remote.lowStockThreshold}',
        ),
      );
    }
    if (local.packBarcode.trim() != remote.packBarcode.trim()) {
      diffs.add(
        SyncFieldDiff(
          fieldLabel: strings.packBarcodeLabel,
          localValue: local.packBarcode.isEmpty ? '—' : local.packBarcode,
          remoteValue: remote.packBarcode.isEmpty ? '—' : remote.packBarcode,
        ),
      );
    }
    if (local.boxBarcode.trim() != remote.boxBarcode.trim()) {
      diffs.add(
        SyncFieldDiff(
          fieldLabel: strings.boxBarcodeLabel,
          localValue: local.boxBarcode.isEmpty ? '—' : local.boxBarcode,
          remoteValue: remote.boxBarcode.isEmpty ? '—' : remote.boxBarcode,
        ),
      );
    }
    if (local.unitWeight.trim() != remote.unitWeight.trim()) {
      diffs.add(
        SyncFieldDiff(
          fieldLabel: strings.unitWeightLabel,
          localValue: local.unitWeight.isEmpty ? '—' : local.unitWeight,
          remoteValue: remote.unitWeight.isEmpty ? '—' : remote.unitWeight,
        ),
      );
    }
    if (local.unit.trim() != remote.unit.trim()) {
      diffs.add(
        SyncFieldDiff(
          fieldLabel: strings.unitMeasureLabel,
          localValue: local.unit.isEmpty ? '—' : local.unit,
          remoteValue: remote.unit.isEmpty ? '—' : remote.unit,
        ),
      );
    }
    return diffs;
  }

  Map<String, dynamic> _productToSheetRow(Product p) {
    return {
      'id': p.id,
      'name': p.name,
      'category': p.category,
      'sku': p.sku,
      'costPrice': p.costPrice,
      'sellPrice': p.sellPrice,
      'stock': p.stock,
      'lowStockThreshold': p.lowStockThreshold,
      'packQty': p.packQty,
      'boxQty': p.boxQty,
      'packBarcode': p.packBarcode,
      'boxBarcode': p.boxBarcode,
      'unitWeight': p.unitWeight,
      'unit': p.unit,
      'nomenclature': p.nomenclature,
      'printName': p.printName,
      'updatedAt': p.updatedAt.toIso8601String(),
    };
  }

  Product _productFromSheetRow(Map<String, dynamic> row, DateTime fallbackNow) {
    double parseDouble(dynamic val) {
      if (val is num) return val.toDouble();
      final clean = '${val ?? ''}'.trim().replaceAll(' ', '').replaceAll(',', '.');
      return double.tryParse(clean) ?? 0.0;
    }

    int parseInt(dynamic val, {int fallback = 0}) {
      if (val is num) return val.round();
      final clean = '${val ?? ''}'.trim().replaceAll(' ', '');
      return int.tryParse(clean) ?? fallback;
    }

    String parseStr(dynamic val) => '${val ?? ''}'.trim();

    final cat = parseStr(row['category']);
    final updatedRaw = parseStr(row['updatedAt']);
    return Product(
      id: parseStr(row['id']),
      name: parseStr(row['name']),
      category: cat.isEmpty ? 'General' : cat,
      sku: parseStr(row['sku']),
      nomenclature: parseStr(row['nomenclature']),
      printName: parseStr(row['printName']),
      packQty: parseStr(row['packQty']),
      boxQty: parseStr(row['boxQty']),
      packBarcode: parseStr(row['packBarcode']),
      boxBarcode: parseStr(row['boxBarcode']),
      unitWeight: parseStr(row['unitWeight']),
      unit: parseStr(row['unit']),
      costPrice: parseDouble(row['costPrice']).clamp(0.0, double.infinity),
      sellPrice: parseDouble(row['sellPrice']).clamp(0.0, double.infinity),
      stock: parseInt(row['stock']).clamp(0, 9999999),
      lowStockThreshold: parseInt(row['lowStockThreshold'], fallback: 5).clamp(0, 999999),
      updatedAt: DateTime.tryParse(updatedRaw) ?? fallbackNow,
    );
  }
}
