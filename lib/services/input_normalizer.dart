import '../models/product.dart';

/// Unified normalization and validation helpers for names, phones, and barcodes
/// across manual input, table/CSV import, and Google Sheets sync.
class InputNormalizer {
  const InputNormalizer._();

  /// Trims leading/trailing whitespace and collapses multiple internal spaces/tabs
  /// into a single space.
  static String normalizeDisplayName(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Normalizes a product or entity name for case-insensitive duplicate matching.
  static String normalizeNameKey(String raw) {
    return normalizeDisplayName(raw).toLowerCase().replaceAll('ё', 'е');
  }

  /// Trims and removes all whitespace from a barcode / SKU string.
  static String normalizeBarcode(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), '').trim();
  }

  /// Normalizes customer phone numbers to a canonical format so variants like
  /// `+7 (701) 123-45-67`, `8 701 123 45 67`, `87011234567`, and `7011234567`
  /// all resolve to `+77011234567`.
  static String normalizePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    // Kazakhstan / Russia (+7 / 8) 10- or 11-digit numbers
    if (digits.length == 11 &&
        (digits.startsWith('8') || digits.startsWith('7'))) {
      return '+7${digits.substring(1)}';
    }
    if (digits.length == 10 && digits.startsWith('7')) {
      return '+7$digits';
    }
    if (hasPlus && digits.length >= 7) {
      return '+$digits';
    }
    return digits;
  }

  /// Checks strict uniqueness between SKU, Pack Barcode, and Box Barcode on a
  /// single product. Returns a list of conflicting field pairs (empty if valid).
  static List<({String fieldA, String fieldB, String barcode})>
      findIntraProductBarcodeConflicts({
    required String sku,
    required String packBarcode,
    required String boxBarcode,
  }) {
    final normSku = normalizeBarcode(sku);
    final normPack = normalizeBarcode(packBarcode);
    final normBox = normalizeBarcode(boxBarcode);
    final conflicts = <({String fieldA, String fieldB, String barcode})>[];

    if (normSku.isNotEmpty &&
        normPack.isNotEmpty &&
        normSku.toLowerCase() == normPack.toLowerCase()) {
      conflicts.add((fieldA: 'sku', fieldB: 'pack', barcode: normSku));
    }
    if (normSku.isNotEmpty &&
        normBox.isNotEmpty &&
        normSku.toLowerCase() == normBox.toLowerCase()) {
      conflicts.add((fieldA: 'sku', fieldB: 'box', barcode: normSku));
    }
    if (normPack.isNotEmpty &&
        normBox.isNotEmpty &&
        normPack.toLowerCase() == normBox.toLowerCase()) {
      conflicts.add((fieldA: 'pack', fieldB: 'box', barcode: normPack));
    }
    return conflicts;
  }

  static const Map<String, String> _enToRuLayout = {
    'q': 'й',
    'w': 'ц',
    'e': 'у',
    'r': 'к',
    't': 'е',
    'y': 'н',
    'u': 'г',
    'i': 'ш',
    'o': 'щ',
    'p': 'з',
    '[': 'х',
    ']': 'ъ',
    'a': 'ф',
    's': 'ы',
    'd': 'в',
    'f': 'а',
    'g': 'п',
    'h': 'р',
    'j': 'о',
    'k': 'л',
    'l': 'д',
    ';': 'ж',
    '\'': 'э',
    'z': 'я',
    'x': 'ч',
    'c': 'с',
    'v': 'м',
    'b': 'и',
    'n': 'т',
    'm': 'ь',
    ',': 'б',
    '.': 'ю',
    '/': '.',
    '`': 'ё',
  };

  static final Map<String, String> _ruToEnLayout = {
    for (final e in _enToRuLayout.entries) e.value: e.key,
  };

  static String normalizeSearchText(String raw) {
    return raw
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll('×', 'x')
        .replaceAll('х', 'x')
        .replaceAll('*', 'x')
        .replaceAll(',', '.');
  }

  static String _compactSearchText(String normalized) {
    return normalized.replaceAll(RegExp(r'[\s\-_/]+'), '');
  }

  /// Converts text typed in the wrong keyboard layout (EN <-> RU).
  static String swapKeyboardLayout(String input) {
    final lower = input.toLowerCase();
    var latinCount = 0;
    var cyrillicCount = 0;
    for (final rune in lower.runes) {
      if (rune >= 97 && rune <= 122) latinCount++;
      if ((rune >= 1072 && rune <= 1103) || rune == 1105) cyrillicCount++;
    }
    final map = latinCount >= cyrillicCount ? _enToRuLayout : _ruToEnLayout;
    final buf = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }

  /// Matches a product against [rawQuery], supporting:
  /// - multi-token text search across name, category, SKU, nomenclature, barcodes;
  /// - trailing 4+ digits barcode lookup (e.g. "4821");
  /// - automatic EN <-> RU keyboard layout correction.
  static bool matchesProductSearch(Product product, String rawQuery) {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) return true;

    final codes = <String>[
      product.sku,
      product.packBarcode,
      product.boxBarcode,
      ...product.extraBarcodes,
    ]
        .map((c) => normalizeBarcode(c).toLowerCase())
        .where((c) => c.isNotEmpty)
        .toList();

    final digitsOnly = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^\d{4,}$').hasMatch(digitsOnly)) {
      for (final code in codes) {
        if (code.endsWith(digitsOnly) || code.contains(digitsOnly)) {
          return true;
        }
      }
    }

    final haystack = normalizeSearchText(
      [
        product.name,
        product.category,
        product.sku,
        product.nomenclature,
        product.printName,
        product.packBarcode,
        product.boxBarcode,
        ...product.extraBarcodes,
      ].join(' '),
    );
    final compactHaystack = _compactSearchText(haystack);

    bool matchTokens(String candidate) {
      final norm = normalizeSearchText(candidate.trim());
      final tokens = norm.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      if (tokens.isEmpty) return true;
      return tokens.every((t) {
        if (haystack.contains(t)) return true;
        final compactT = _compactSearchText(t);
        return compactT.isNotEmpty && compactHaystack.contains(compactT);
      });
    }

    if (matchTokens(trimmed)) return true;
    final swapped = swapKeyboardLayout(trimmed);
    if (swapped != trimmed.toLowerCase() && matchTokens(swapped)) {
      return true;
    }
    return false;
  }
}
