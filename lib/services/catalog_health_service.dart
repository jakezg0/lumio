import '../models/product.dart';
import 'input_normalizer.dart';

enum CatalogHealthIssueType {
  emptyName,
  zeroPrice,
  sellBelowCost,
  duplicateBarcode,
  negativeStock,
}

class CatalogHealthIssue {
  const CatalogHealthIssue({
    required this.product,
    required this.type,
    this.detail = '',
  });

  final Product product;
  final CatalogHealthIssueType type;
  final String detail;
}

class CatalogHealthService {
  const CatalogHealthService._();

  /// Analyzes [products] for data anomalies:
  /// - Empty product names
  /// - Zero sell price
  /// - Sell price lower than cost price
  /// - Duplicate barcodes across different products (or within the same product)
  /// - Stuck negative stock
  static List<CatalogHealthIssue> analyze(List<Product> products) {
    final issues = <CatalogHealthIssue>[];

    // Index normalized barcodes -> list of product indices
    final barcodeOwners = <String, List<int>>{};
    final barcodeDisplay = <String, String>{};
    for (var i = 0; i < products.length; i++) {
      final p = products[i];
      for (final raw in [p.sku, p.packBarcode, p.boxBarcode]) {
        final norm = InputNormalizer.normalizeBarcode(raw);
        final key = norm.toLowerCase();
        if (key.isEmpty) continue;
        barcodeDisplay.putIfAbsent(key, () => norm);
        final owners = barcodeOwners.putIfAbsent(key, () => []);
        if (!owners.contains(i)) {
          owners.add(i);
        }
      }
    }

    for (var i = 0; i < products.length; i++) {
      final p = products[i];

      if (InputNormalizer.normalizeDisplayName(p.name).isEmpty) {
        issues.add(
          CatalogHealthIssue(
            product: p,
            type: CatalogHealthIssueType.emptyName,
          ),
        );
      }

      if (p.sellPrice <= 0) {
        issues.add(
          CatalogHealthIssue(
            product: p,
            type: CatalogHealthIssueType.zeroPrice,
          ),
        );
      } else if (p.costPrice > 0 && p.sellPrice < p.costPrice) {
        issues.add(
          CatalogHealthIssue(
            product: p,
            type: CatalogHealthIssueType.sellBelowCost,
          ),
        );
      }

      if (p.stock < 0) {
        issues.add(
          CatalogHealthIssue(
            product: p,
            type: CatalogHealthIssueType.negativeStock,
            detail: '${p.stock}',
          ),
        );
      }

      final selfConflicts = InputNormalizer.findIntraProductBarcodeConflicts(
        sku: p.sku,
        packBarcode: p.packBarcode,
        boxBarcode: p.boxBarcode,
      );
      if (selfConflicts.isNotEmpty) {
        issues.add(
          CatalogHealthIssue(
            product: p,
            type: CatalogHealthIssueType.duplicateBarcode,
            detail: selfConflicts.first.barcode,
          ),
        );
      } else {
        for (final raw in [p.sku, p.packBarcode, p.boxBarcode]) {
          final key = InputNormalizer.normalizeBarcode(raw).toLowerCase();
          if (key.isEmpty) continue;
          final owners = barcodeOwners[key];
          if (owners != null && owners.length > 1) {
            issues.add(
              CatalogHealthIssue(
                product: p,
                type: CatalogHealthIssueType.duplicateBarcode,
                detail: barcodeDisplay[key] ?? raw.trim(),
              ),
            );
            break;
          }
        }
      }
    }

    return issues;
  }
}
