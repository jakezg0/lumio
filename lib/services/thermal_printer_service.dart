import 'dart:convert';
import 'dart:io';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../l10n/app_strings.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../widgets/formatters.dart';

class ThermalPrinterConfig {
  const ThermalPrinterConfig({
    this.macAddress = '',
    this.name = '',
    this.is80mm = false,
  });

  final String macAddress;
  final String name;
  final bool is80mm;

  bool get isConfigured => macAddress.trim().isNotEmpty;
  int get charsPerLine => is80mm ? 48 : 32;

  ThermalPrinterConfig copyWith({
    String? macAddress,
    String? name,
    bool? is80mm,
  }) {
    return ThermalPrinterConfig(
      macAddress: macAddress ?? this.macAddress,
      name: name ?? this.name,
      is80mm: is80mm ?? this.is80mm,
    );
  }

  Map<String, dynamic> toJson() => {
        'macAddress': macAddress,
        'name': name,
        'is80mm': is80mm,
      };

  factory ThermalPrinterConfig.fromJson(Map<String, dynamic> json) {
    return ThermalPrinterConfig(
      macAddress: (json['macAddress'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      is80mm: json['is80mm'] == true,
    );
  }
}

class ThermalPrinterService {
  ThermalPrinterService._();

  static ThermalPrinterConfig _cachedConfig = const ThermalPrinterConfig();
  static bool _loaded = false;

  static File _configFile() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final dir = home != null && home.isNotEmpty
        ? Directory('$home/.small_shop_inventory')
        : Directory('${Directory.systemTemp.path}/small_shop_inventory');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File('${dir.path}/thermal_printer.json');
  }

  static Future<ThermalPrinterConfig> loadConfig() async {
    if (_loaded) return _cachedConfig;
    try {
      final file = _configFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _cachedConfig = ThermalPrinterConfig.fromJson(decoded);
        }
      }
    } catch (_) {}
    _loaded = true;
    return _cachedConfig;
  }

  static Future<void> saveConfig(ThermalPrinterConfig config) async {
    _cachedConfig = config;
    _loaded = true;
    try {
      final file = _configFile();
      await file.writeAsString(jsonEncode(config.toJson()));
    } catch (_) {}
  }

  static Future<List<BluetoothInfo>> getPairedPrinters() async {
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> printBytes(List<int> bytes) async {
    final config = await loadConfig();
    if (!config.isConfigured) return false;
    try {
      var connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        connected = await PrintBluetoothThermal.connect(
          macPrinterAddress: config.macAddress,
        );
      }
      if (!connected) return false;
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {
      return false;
    }
  }

  /// Encodes UTF-8 string into single-byte CP866 for ESC/POS thermal printers.
  static List<int> encodeCp866(String text) {
    final out = <int>[];
    for (final rune in text.runes) {
      if (rune >= 0x20 && rune <= 0x7E) {
        out.add(rune);
      } else if (rune == 0x0A || rune == 0x0D) {
        out.add(rune);
      } else if (rune >= 0x0410 && rune <= 0x042F) {
        // А..Я -> 0x80..0x9F
        out.add(0x80 + (rune - 0x0410));
      } else if (rune >= 0x0430 && rune <= 0x043F) {
        // а..п -> 0xA0..0xAF
        out.add(0xA0 + (rune - 0x0430));
      } else if (rune >= 0x0440 && rune <= 0x044F) {
        // р..я -> 0xE0..0xEF
        out.add(0xE0 + (rune - 0x0440));
      } else if (rune == 0x0401) {
        // Ё
        out.add(0xF0);
      } else if (rune == 0x0451) {
        // ё
        out.add(0xF1);
      } else if (rune == 0x2116) {
        // №
        out.add(0xFC);
      } else if (rune == 0x20B8) {
        // ₸ -> T
        out.add(0x54);
      } else if (rune == 0x20BD) {
        // ₽ -> R
        out.add(0x52);
      } else if (rune == 0x00A0) {
        out.add(0x20);
      } else if (rune == 0x2022) {
        // • -> *
        out.add(0x2A);
      } else if (rune == 0x2014 || rune == 0x2013 || rune == 0x2212) {
        // —, –, − -> -
        out.add(0x2D);
      } else if (rune == 0x00D7) {
        // × -> x
        out.add(0x78);
      } else {
        // Kazakh / extended Cyrillic fallbacks
        const kkMap = <int, int>{
          0x04D8: 0x80, // Ә -> А
          0x04D9: 0xA0, // ә -> а
          0x04E8: 0x8E, // Ө -> О
          0x04E9: 0xAE, // ө -> о
          0x04AE: 0x93, // Ү -> У
          0x04AF: 0xE3, // ү -> у
          0x04B0: 0x93, // Ұ -> У
          0x04B1: 0xE3, // ұ -> у
          0x049A: 0x8A, // Қ -> К
          0x049B: 0xAA, // қ -> к
          0x0492: 0x83, // Ғ -> Г
          0x0493: 0xA3, // ғ -> г
          0x04A2: 0x8D, // Ң -> Н
          0x04A3: 0xAD, // ң -> н
          0x04BA: 0x95, // Һ -> Х
          0x04BB: 0xE5, // һ -> х
          0x0406: 0x88, // І -> И
          0x0456: 0xA8, // і -> и
        };
        out.add(kkMap[rune] ?? 0x3F);
      }
    }
    return out;
  }

  static String _lrLine(String left, String right, int width) {
    final l = left.trim();
    final r = right.trim();
    if (l.length + r.length + 1 <= width) {
      final spaces = width - l.length - r.length;
      return '$l${' ' * spaces}$r';
    }
    final maxLeft = (width - r.length - 1).clamp(1, width);
    final cutLeft = l.length > maxLeft ? l.substring(0, maxLeft) : l;
    final spaces = (width - cutLeft.length - r.length).clamp(1, width);
    return '$cutLeft${' ' * spaces}$r';
  }

  static List<int> _initCp866() => [
        0x1B, 0x40, // ESC @ (init)
        0x1B, 0x74, 0x11, // ESC t 17 (CP866)
      ];

  static List<int> _alignLeft() => [0x1B, 0x61, 0x00];
  static List<int> _alignCenter() => [0x1B, 0x61, 0x01];
  static List<int> _boldOn() => [0x1B, 0x45, 0x01];
  static List<int> _boldOff() => [0x1B, 0x45, 0x00];
  static List<int> _sizeNormal() => [0x1D, 0x21, 0x00];
  static List<int> _sizeDouble() => [0x1D, 0x21, 0x11];

  static List<int> _barcodeCode128(String code) {
    final clean = code.trim();
    if (clean.isEmpty) return const [];
    final data = utf8.encode('{B$clean');
    return [
      0x1D, 0x68, 52, // height
      0x1D, 0x77, 2, // width
      0x1D, 0x48, 2, // HRI below
      0x1D, 0x6B, 73, data.length, // GS k 73 len (CODE128)
      ...data,
    ];
  }

  static List<int> buildReceiptEscPos({
    required Sale sale,
    required AppStrings strings,
    required AppCurrency currency,
    required bool is80mm,
    String shopName = '',
    String shopAddress = '',
    String shopPhone = '',
    String receiptFooter = '',
  }) {
    final width = is80mm ? 48 : 32;
    final sep = '-' * width;
    final bytes = <int>[..._initCp866()];

    void line(String s) {
      bytes.addAll(encodeCp866('$s\n'));
    }

    bytes.addAll(_alignCenter());
    if (shopName.trim().isNotEmpty) {
      bytes.addAll(_boldOn());
      bytes.addAll(_sizeDouble());
      line(shopName.trim());
      bytes.addAll(_sizeNormal());
      bytes.addAll(_boldOff());
    }
    if (shopAddress.trim().isNotEmpty) line(shopAddress.trim());
    if (shopPhone.trim().isNotEmpty) line(shopPhone.trim());

    bytes.addAll(_alignLeft());
    line(sep);
    line('${strings.saleReceipt} #${sale.receiptCode}');
    line(formatDateTime(sale.createdAt));
    if (sale.sellerName.trim().isNotEmpty) {
      line('${strings.sellerLabel}: ${sale.sellerName.trim()}');
    }
    if (sale.customerName.trim().isNotEmpty) {
      line('${strings.customerLabel}: ${sale.customerName.trim()}');
    }
    line(sep);

    for (final item in sale.items) {
      line(item.productName);
      final left =
          '  ${formatQty(item.quantity)} x ${formatMoney(item.unitPrice, currency)}';
      final right = formatMoney(item.lineTotal, currency);
      line(_lrLine(left, right, width));
    }

    line(sep);
    if (sale.discount > 0.009) {
      line(
        _lrLine(
          strings.discountLabel,
          '-${formatMoney(sale.discount, currency)}',
          width,
        ),
      );
    }
    bytes.addAll(_boldOn());
    line(_lrLine(strings.totalDue, formatMoney(sale.total, currency), width));
    bytes.addAll(_boldOff());

    final payStr = sale.isSplitPayment
        ? '${strings.paymentMethodLabel(sale.paymentMethod.name)} + ${strings.paymentMethodLabel(sale.secondaryPaymentMethod!.name)}'
        : strings.paymentMethodLabel(sale.paymentMethod.name);
    line(payStr);

    if (!sale.isPaid) {
      line(
        _lrLine(
          strings.paidAmountLabel,
          formatMoney(sale.paidAmount, currency),
          width,
        ),
      );
      line(
        _lrLine(
          strings.remainingDebtLabel,
          formatMoney(sale.remainingDebt, currency),
          width,
        ),
      );
    }

    if (receiptFooter.trim().isNotEmpty) {
      line(sep);
      bytes.addAll(_alignCenter());
      line(receiptFooter.trim());
    }

    if (sale.receiptCode.trim().isNotEmpty) {
      bytes.addAll(_alignCenter());
      bytes.addAll(encodeCp866('\n'));
      bytes.addAll(_barcodeCode128(sale.receiptCode));
    }

    bytes.addAll(encodeCp866('\n\n\n'));
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]); // GS V B 0 (partial cut if supported)
    return bytes;
  }

  static List<int> buildPriceTagEscPos({
    required Product product,
    required AppCurrency currency,
    required bool is80mm,
    String code = '',
    String shopName = '',
  }) {
    final bytes = <int>[..._initCp866(), ..._alignCenter()];

    void line(String s) {
      bytes.addAll(encodeCp866('$s\n'));
    }

    if (shopName.trim().isNotEmpty) {
      line(shopName.trim());
    }
    final displayName = product.printName.trim().isNotEmpty
        ? product.printName.trim()
        : product.name.trim();
    bytes.addAll(_boldOn());
    line(displayName);
    bytes.addAll(_sizeDouble());
    line(formatMoney(product.sellPrice, currency));
    bytes.addAll(_sizeNormal());
    bytes.addAll(_boldOff());

    final cleanCode = code.trim().isNotEmpty
        ? code.trim()
        : (product.sku.trim().isNotEmpty
            ? product.sku.trim()
            : product.packBarcode.trim());
    if (cleanCode.isNotEmpty) {
      bytes.addAll(_barcodeCode128(cleanCode));
    }

    bytes.addAll(encodeCp866('\n\n\n'));
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]);
    return bytes;
  }

  static List<int> buildTestPageEscPos({
    required String shopName,
    required bool is80mm,
  }) {
    final width = is80mm ? 48 : 32;
    final sep = '-' * width;
    final bytes = <int>[..._initCp866(), ..._alignCenter(), ..._boldOn()];
    bytes.addAll(encodeCp866('${shopName.trim().isEmpty ? 'Lumio' : shopName.trim()}\n'));
    bytes.addAll(_boldOff());
    bytes.addAll(encodeCp866('Bluetooth ESC/POS (${is80mm ? '80mm' : '58mm'})\n'));
    bytes.addAll(encodeCp866('$sep\n'));
    bytes.addAll(encodeCp866('Тест кириллицы: АБВГД абывгд 12345\n'));
    bytes.addAll(encodeCp866('$sep\n\n\n'));
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]);
    return bytes;
  }
}
