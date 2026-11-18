import 'package:flutter/material.dart';

class ReceiptBarcodeWidget extends StatelessWidget {
  const ReceiptBarcodeWidget({
    super.key,
    required this.code,
    this.height = 48,
  });

  final String code;
  final double height;

  @override
  Widget build(BuildContext context) {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _Code39Painter(normalized),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            normalized,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _Code39Painter extends CustomPainter {
  _Code39Painter(this.data);

  final String data;

  static const Map<String, String> _patterns = {
    '0': 'nnnwwnwnn',
    '1': 'wnnwnnnnw',
    '2': 'nnwwnnnnw',
    '3': 'wnwwnnnnn',
    '4': 'nnnwwnnnw',
    '5': 'wnnwwnnnn',
    '6': 'nnwwwnnnn',
    '7': 'nnnwnnwnw',
    '8': 'wnnwnnwnn',
    '9': 'nnwwnnwnn',
    'A': 'wnnnnwnnw',
    'B': 'nnwnnwnnw',
    'C': 'wnwnnwnnn',
    'D': 'nnnnwwnnw',
    'E': 'wnnnwwnnn',
    'F': 'nnwnwwnnn',
    'G': 'nnnnnwwnw',
    'H': 'wnnnnwwnn',
    'I': 'nnwnnwwnn',
    'J': 'nnnnwwwnn',
    'K': 'wnnnnnnww',
    'L': 'nnwnnnnww',
    'M': 'wnwnnnnwn',
    'N': 'nnnnwnnww',
    'O': 'wnnnwnnwn',
    'P': 'nnwnwnnwn',
    'Q': 'nnnnnnwww',
    'R': 'wnnnnnwwn',
    'S': 'nnwnnnwwn',
    'T': 'nnnnwnwwn',
    'U': 'wwnnnnnnw',
    'V': 'nwwnnnnnw',
    'W': 'wwwnnnnnn',
    'X': 'nwnnwnnnw',
    'Y': 'wwnnwnnnn',
    'Z': 'nwwnwnnnn',
    '-': 'nwnnnnwnw',
    '.': 'wwnnnnwnn',
    ' ': 'nwwnnnwnn',
    '*': 'nwnnwnwnn',
    '\$': 'nwnwnwnnn',
    '/': 'nwnwnnnwn',
    '+': 'nwnnnwnwn',
    '%': 'nnnwnwnwn',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final full = '*$data*';
    final encoded = <String>[];
    for (var i = 0; i < full.length; i++) {
      final p = _patterns[full[i]];
      if (p != null) {
        encoded.add(p);
      }
    }
    if (encoded.isEmpty) return;

    const wideRatio = 2.5;
    // Each char has 9 elements (3 wide, 6 narrow) + 1 narrow inter-character gap.
    var totalUnits = 0.0;
    for (var c = 0; c < encoded.length; c++) {
      final pattern = encoded[c];
      for (var i = 0; i < pattern.length; i++) {
        totalUnits += pattern[i] == 'w' ? wideRatio : 1.0;
      }
      if (c < encoded.length - 1) {
        totalUnits += 1.0;
      }
    }

    final unitWidth = (size.width / totalUnits).clamp(1.0, 4.0);
    final totalDrawWidth = totalUnits * unitWidth;
    var x = (size.width - totalDrawWidth) / 2;
    if (x < 0) x = 0;

    final paint = Paint()..color = Colors.black;

    for (var c = 0; c < encoded.length; c++) {
      final pattern = encoded[c];
      for (var i = 0; i < pattern.length; i++) {
        final w = (pattern[i] == 'w' ? wideRatio : 1.0) * unitWidth;
        if (i.isEven) {
          canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
        }
        x += w;
      }
      if (c < encoded.length - 1) {
        x += unitWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Code39Painter oldDelegate) =>
      oldDelegate.data != data;
}
