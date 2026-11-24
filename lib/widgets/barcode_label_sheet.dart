import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product.dart';
import '../services/export_service.dart';
import '../services/thermal_printer_service.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';
import 'receipt_barcode.dart';
import 'thermal_printer_dialog.dart';

/// Visual barcode widget supporting true GS1 EAN-13 (with guard bars & parity)
/// and falling back to Code 39 for custom alphanumeric SKUs.
class ProductBarcodeWidget extends StatelessWidget {
  const ProductBarcodeWidget({
    super.key,
    required this.code,
    this.height = 64,
    this.compact = false,
  });

  final String code;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    if (!ShopController.isValidEan13(trimmed)) {
      return ReceiptBarcodeWidget(
        code: trimmed,
        height: compact ? 40 : height,
      );
    }

    final formatted =
        '${trimmed[0]}  ${trimmed.substring(1, 7)}  ${trimmed.substring(7, 13)}';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 6 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: compact ? 44 : height,
            width: double.infinity,
            child: CustomPaint(
              painter: _Ean13Painter(trimmed),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatted,
              style: TextStyle(
                color: Colors.black87,
                fontSize: compact ? 11 : 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ean13Painter extends CustomPainter {
  _Ean13Painter(this.digits);

  final String digits;

  static const List<String> _lCodes = [
    '0001101',
    '0011001',
    '0010011',
    '0111101',
    '0100011',
    '0110001',
    '0101111',
    '0111011',
    '0110111',
    '0001011',
  ];

  static const List<String> _gCodes = [
    '0100111',
    '0110011',
    '0011011',
    '0100001',
    '0011101',
    '0111001',
    '0000101',
    '0010001',
    '0001001',
    '0010111',
  ];

  static const List<String> _rCodes = [
    '1110010',
    '1100110',
    '1101100',
    '1000010',
    '1011100',
    '1001110',
    '1010000',
    '1000100',
    '1001000',
    '1110100',
  ];

  static const List<String> _parity = [
    'LLLLLL',
    'LLGLGG',
    'LLGGLG',
    'LLGGGL',
    'LGLLGG',
    'LGGLLG',
    'LGGGLL',
    'LGLGLG',
    'LGLGGL',
    'LGGLGL',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (digits.length != 13) return;
    final first = digits.codeUnitAt(0) - 48;
    if (first < 0 || first > 9) return;

    final buf = StringBuffer('101'); // Left guard (3 modules)
    final pPattern = _parity[first];
    for (var i = 0; i < 6; i++) {
      final d = digits.codeUnitAt(i + 1) - 48;
      buf.write(pPattern[i] == 'L' ? _lCodes[d] : _gCodes[d]);
    }
    buf.write('01010'); // Center guard (5 modules)
    for (var i = 7; i < 13; i++) {
      final d = digits.codeUnitAt(i) - 48;
      buf.write(_rCodes[d]);
    }
    buf.write('101'); // Right guard (3 modules)

    final bits = buf.toString(); // Exactly 95 modules
    const quietModules = 14; // 7 left + 7 right quiet zone
    final totalModules = bits.length + quietModules;
    final moduleWidth = (size.width / totalModules).clamp(1.0, 3.2);
    final drawWidth = bits.length * moduleWidth;
    final startX = ((size.width - drawWidth) / 2).clamp(0.0, size.width);

    final paint = Paint()..color = Colors.black;
    final shortHeight = size.height * 0.88;

    for (var i = 0; i < bits.length; i++) {
      if (bits[i] != '1') continue;
      final isGuard = i < 3 || (i >= 45 && i < 50) || i >= 92;
      canvas.drawRect(
        Rect.fromLTWH(
          startX + i * moduleWidth,
          0,
          moduleWidth + 0.15,
          isGuard ? size.height : shortHeight,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Ean13Painter oldDelegate) =>
      oldDelegate.digits != digits;
}

class BarcodeLabelSheet extends StatefulWidget {
  const BarcodeLabelSheet({
    super.key,
    required this.controller,
    required this.product,
  });

  final ShopController controller;
  final Product product;

  @override
  State<BarcodeLabelSheet> createState() => _BarcodeLabelSheetState();
}

class _BarcodeLabelSheetState extends State<BarcodeLabelSheet> {
  late Product _product;
  String _selectedSlot = 'sku';
  bool _isThermal58x40 = true;
  int _copies = 1;
  bool _showPrice = true;
  bool _showShopName = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    if (_product.sku.trim().isNotEmpty) {
      _selectedSlot = 'sku';
    } else if (_product.packBarcode.trim().isNotEmpty) {
      _selectedSlot = 'pack';
    } else if (_product.boxBarcode.trim().isNotEmpty) {
      _selectedSlot = 'box';
    }
  }

  String get _activeCode {
    switch (_selectedSlot) {
      case 'pack':
        return _product.packBarcode.trim();
      case 'box':
        return _product.boxBarcode.trim();
      default:
        return _product.sku.trim();
    }
  }

  Future<void> _generateAndSaveEan13() async {
    final prefix = _selectedSlot == 'pack'
        ? '201'
        : (_selectedSlot == 'box' ? '202' : '200');
    final generated = widget.controller.generateUniqueEan13(prefix: prefix);
    final updated = switch (_selectedSlot) {
      'pack' => _product.copyWith(packBarcode: generated),
      'box' => _product.copyWith(boxBarcode: generated),
      _ => _product.copyWith(sku: generated),
    };
    await widget.controller.updateProduct(updated);
    if (!mounted) return;
    setState(() => _product = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.controller.strings.barcodeGeneratedMsg(generated)),
      ),
    );
  }

  Future<void> _exportPdf() async {
    final code = _activeCode;
    if (code.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await ExportService.buildBarcodeLabelsPdfBytes(
        product: _product,
        code: code,
        currency: widget.controller.currency,
        isThermal58x40: _isThermal58x40,
        copies: _copies,
        showPrice: _showPrice,
        shopName: _showShopName ? widget.controller.shopName : '',
      );
      final formatTag = _isThermal58x40 ? '58x40' : 'A4';
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: 'barcode_${code}_$formatTag.pdf',
          mimeType: 'application/pdf',
        ),
      ]);
      await widget.controller.markPriceTagPrinted(_product.id);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final code = _activeCode;
    final isEan = ShopController.isValidEan13(code);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.barcodeLabelTitle,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_product.name} • ${formatMoney(_product.sellPrice, currency)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 'sku',
                  label: Text(
                    strings.barcodeTypeSku,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: 'pack',
                  label: Text(
                    strings.barcodeTypePack,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: 'box',
                  label: Text(
                    strings.barcodeTypeBox,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {_selectedSlot},
              onSelectionChanged: (sel) =>
                  setState(() => _selectedSlot = sel.first),
            ),
            const SizedBox(height: 12),
            if (code.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.qr_code_2_rounded,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.noBarcodeYetMsg,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _generateAndSaveEan13,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(strings.generateAndSaveBarcodeBtn),
                    ),
                  ],
                ),
              ),
            ] else ...[
              ProductBarcodeWidget(code: code, height: 72),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isEan
                          ? Colors.green.shade100
                          : theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isEan ? strings.ean13ValidBadge : strings.customCodeBadge,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(strings.copiedToClipboardMsg),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: Text(strings.copyTextBtn),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _generateAndSaveEan13,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(strings.generateBarcodeAction),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text(
                      strings.labelFormatThermal,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text(
                      strings.labelFormatA4,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {_isThermal58x40},
                onSelectionChanged: (sel) => setState(() {
                  _isThermal58x40 = sel.first;
                  if (!_isThermal58x40 && _copies == 1) {
                    _copies = 24;
                  }
                }),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.labelCountLabel,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: _copies > 1
                        ? () => setState(() => _copies -= 1)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    visualDensity: VisualDensity.compact,
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$_copies',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _copies < 120
                        ? () => setState(() => _copies += 1)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final preset in [1, 6, 12, 24, 48])
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('$preset'),
                      selected: _copies == preset,
                      onSelected: (_) => setState(() => _copies = preset),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(strings.showPriceOnLabel),
                    selected: _showPrice,
                    onSelected: (v) => setState(() => _showPrice = v),
                  ),
                  if (widget.controller.shopName.trim().isNotEmpty)
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(strings.showShopNameOnLabel),
                      selected: _showShopName,
                      onSelected: (v) => setState(() => _showShopName = v),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await printBytesOrSetupPrinter(
                    context,
                    strings: strings,
                    shopName: widget.controller.shopName,
                    buildBytes: (cfg) =>
                        ThermalPrinterService.buildPriceTagEscPos(
                      product: _product,
                      currency: widget.controller.currency,
                      is80mm: cfg.is80mm,
                      code: code,
                      shopName: _showShopName ? widget.controller.shopName : '',
                    ),
                  );
                  await widget.controller.markPriceTagPrinted(_product.id);
                },
                icon: const Icon(Icons.print_outlined),
                label: Text(strings.thermalPrintBtn),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _exporting ? null : _exportPdf,
                icon: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(strings.shareBarcodePdfBtn),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
