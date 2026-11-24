import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/product.dart';
import '../screens/barcode_scanner_screen.dart';
import '../services/input_normalizer.dart';
import '../services/product_image_service.dart';
import '../state/shop_controller.dart';
import 'barcode_label_sheet.dart';
import 'currency_calculator_dialog.dart';
import 'formatters.dart';
import 'product_thumbnail.dart';

class ProductFormSheet extends StatefulWidget {
  const ProductFormSheet({
    super.key,
    required this.controller,
    this.existing,
    this.template,
    this.initialSku,
    this.initialName,
    this.initialCategory,
    this.initialStock = 10,
  });

  final ShopController controller;
  final Product? existing;
  final Product? template;
  final String? initialSku;
  final String? initialName;
  final String? initialCategory;
  final int initialStock;

  @override
  State<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _skuController;
  late final TextEditingController _nomenclatureController;
  late final TextEditingController _printNameController;
  late final TextEditingController _packQtyController;
  late final TextEditingController _boxQtyController;
  late final TextEditingController _packBarcodeController;
  late final TextEditingController _boxBarcodeController;
  late final TextEditingController _unitWeightController;
  late final TextEditingController _unitController;
  late final TextEditingController _costController;
  late final TextEditingController _sellController;
  late final TextEditingController _wholesaleController;
  late final TextEditingController _wholesaleMinQtyController;
  late final TextEditingController _stockController;
  late final TextEditingController _thresholdController;
  late List<String> _extraBarcodes;
  late String _imagePath;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    _extraBarcodes = List<String>.from(item?.extraBarcodes ?? const []);
    _imagePath = item?.imagePath ?? '';
    final tpl = item == null ? widget.template : null;
    _nameController = TextEditingController(
      text: item?.name ?? tpl?.name ?? widget.initialName ?? '',
    );
    _categoryController = TextEditingController(
      text: item?.category ?? tpl?.category ?? widget.initialCategory ?? 'General',
    );
    _skuController = TextEditingController(
      text: item?.sku ?? widget.initialSku ?? '',
    );
    _nomenclatureController =
        TextEditingController(text: item?.nomenclature ?? '');
    _printNameController = TextEditingController(text: item?.printName ?? '');
    _packQtyController =
        TextEditingController(text: item?.packQty ?? tpl?.packQty ?? '');
    _boxQtyController =
        TextEditingController(text: item?.boxQty ?? tpl?.boxQty ?? '');
    _packBarcodeController =
        TextEditingController(text: item?.packBarcode ?? '');
    _boxBarcodeController =
        TextEditingController(text: item?.boxBarcode ?? '');
    _unitWeightController = TextEditingController(
      text: item?.unitWeight ?? tpl?.unitWeight ?? '',
    );
    _unitController =
        TextEditingController(text: item?.unit ?? tpl?.unit ?? '');
    _costController = TextEditingController(
      text: item != null
          ? item.costPrice.toStringAsFixed(0)
          : (tpl != null ? tpl.costPrice.toStringAsFixed(0) : ''),
    );
    _sellController = TextEditingController(
      text: item != null
          ? item.sellPrice.toStringAsFixed(0)
          : (tpl != null ? tpl.sellPrice.toStringAsFixed(0) : ''),
    );
    final initialWholesale = item?.wholesalePrice ?? tpl?.wholesalePrice ?? 0;
    _wholesaleController = TextEditingController(
      text: initialWholesale > 0 ? initialWholesale.toStringAsFixed(0) : '',
    );
    final initialMinQty = item?.wholesaleMinQty ?? tpl?.wholesaleMinQty ?? 0;
    _wholesaleMinQtyController = TextEditingController(
      text: initialMinQty > 0 ? '$initialMinQty' : '',
    );
    _stockController = TextEditingController(
      text: item != null ? formatQty(item.stock) : '${widget.initialStock}',
    );
    _thresholdController = TextEditingController(
      text: item != null
          ? '${item.lowStockThreshold}'
          : '${tpl?.lowStockThreshold ?? 5}',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _skuController.dispose();
    _nomenclatureController.dispose();
    _printNameController.dispose();
    _packQtyController.dispose();
    _boxQtyController.dispose();
    _packBarcodeController.dispose();
    _boxBarcodeController.dispose();
    _unitWeightController.dispose();
    _unitController.dispose();
    _costController.dispose();
    _sellController.dispose();
    _wholesaleController.dispose();
    _wholesaleMinQtyController.dispose();
    _stockController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _scanIntoController(TextEditingController target) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) =>
            BarcodeScannerScreen(strings: widget.controller.strings),
      ),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    setState(() {
      target.text = code.trim();
    });
  }

  void _generateBarcodeIntoController(
    TextEditingController target, {
    required String prefix,
  }) {
    final code = widget.controller.generateUniqueEan13(prefix: prefix);
    setState(() {
      target.text = code;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.controller.strings.barcodeGeneratedMsg(code)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openCalculator(
    TextEditingController target, {
    bool integerMode = false,
  }) async {
    final initial = double.tryParse(target.text.trim().replaceAll(',', '.'));
    final result = await showCurrencyCalculatorDialog(
      context,
      strings: widget.controller.strings,
      targetCurrency: widget.controller.currency,
      productName: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      initialValue: initial,
      integerMode: integerMode,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (integerMode) {
        target.text = '${result.round()}';
      } else {
        target.text = result == result.roundToDouble()
            ? result.toStringAsFixed(0)
            : result.toStringAsFixed(2);
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final strings = widget.controller.strings;
    final normName = InputNormalizer.normalizeDisplayName(_nameController.text);
    final normCategory =
        InputNormalizer.normalizeDisplayName(_categoryController.text);
    final normSku = InputNormalizer.normalizeBarcode(_skuController.text);
    final normPackBarcode =
        InputNormalizer.normalizeBarcode(_packBarcodeController.text);
    final normBoxBarcode =
        InputNormalizer.normalizeBarcode(_boxBarcodeController.text);

    final selfConflicts = InputNormalizer.findIntraProductBarcodeConflicts(
      sku: normSku,
      packBarcode: normPackBarcode,
      boxBarcode: normBoxBarcode,
    );
    if (selfConflicts.isNotEmpty) {
      String fieldLabel(String key) => switch (key) {
            'sku' => strings.skuLabel,
            'pack' => strings.packBarcodeLabel,
            _ => strings.boxBarcodeLabel,
          };
      final c = selfConflicts.first;
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          icon: Icon(
            Icons.error_outline,
            color: Theme.of(dialogCtx).colorScheme.error,
          ),
          title: Text(strings.duplicateFoundTitle),
          content: Text(
            strings.barcodeSelfConflictError(
              fieldLabel(c.fieldA),
              fieldLabel(c.fieldB),
              c.barcode,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(strings.close),
            ),
          ],
        ),
      );
      return;
    }

    final existing = widget.existing;
    final duplicates = widget.controller.findDuplicateProducts(
      name: normName,
      sku: normSku,
      packBarcode: normPackBarcode,
      boxBarcode: normBoxBarcode,
      excludeProductId: existing?.id,
    );
    if (duplicates.isNotEmpty) {
      final strings = widget.controller.strings;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(dialogCtx).colorScheme.error,
          ),
          title: Text(strings.duplicateFoundTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.duplicateFoundBody),
                const SizedBox(height: 8),
                for (final dup in duplicates.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ${dup.product.name}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '  ${dup.reasons.join(', ')} • ${strings.stockCountLabel(dup.product.stock)}',
                          style: Theme.of(dialogCtx).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(strings.saveAnywayAction),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final cost = double.parse(_costController.text.trim());
    final sell = double.parse(_sellController.text.trim());
    final wholesaleRaw = _wholesaleController.text.trim().replaceAll(',', '.');
    final wholesale =
        wholesaleRaw.isEmpty ? 0.0 : (double.tryParse(wholesaleRaw) ?? 0.0);
    final minQtyRaw = _wholesaleMinQtyController.text.trim();
    final wholesaleMinQty =
        minQtyRaw.isEmpty ? 0 : (int.tryParse(minQtyRaw) ?? 0);
    final stock = parseQty(_stockController.text) ?? 0;
    final threshold = int.parse(_thresholdController.text.trim());

    final Product resultProduct;
    if (existing == null) {
      resultProduct = await widget.controller.addProduct(
        name: normName,
        category: normCategory,
        sku: normSku,
        nomenclature: InputNormalizer.normalizeDisplayName(
          _nomenclatureController.text,
        ),
        printName:
            InputNormalizer.normalizeDisplayName(_printNameController.text),
        packQty: InputNormalizer.normalizeDisplayName(_packQtyController.text),
        boxQty: InputNormalizer.normalizeDisplayName(_boxQtyController.text),
        packBarcode: normPackBarcode,
        boxBarcode: normBoxBarcode,
        unitWeight:
            InputNormalizer.normalizeDisplayName(_unitWeightController.text),
        unit: InputNormalizer.normalizeDisplayName(_unitController.text),
        imagePath: _imagePath,
        costPrice: cost,
        sellPrice: sell,
        wholesalePrice: wholesale,
        wholesaleMinQty: wholesaleMinQty,
        stock: stock,
        lowStockThreshold: threshold,
      );
    } else {
      resultProduct = existing.copyWith(
        name: normName,
        category: normCategory.isEmpty ? 'General' : normCategory,
        sku: normSku,
        nomenclature: InputNormalizer.normalizeDisplayName(
          _nomenclatureController.text,
        ),
        printName:
            InputNormalizer.normalizeDisplayName(_printNameController.text),
        packQty: InputNormalizer.normalizeDisplayName(_packQtyController.text),
        boxQty: InputNormalizer.normalizeDisplayName(_boxQtyController.text),
        packBarcode: normPackBarcode,
        boxBarcode: normBoxBarcode,
        unitWeight:
            InputNormalizer.normalizeDisplayName(_unitWeightController.text),
        unit: InputNormalizer.normalizeDisplayName(_unitController.text),
        imagePath: _imagePath,
        costPrice: cost,
        sellPrice: sell,
        wholesalePrice: wholesale < 0 ? 0 : wholesale,
        wholesaleMinQty: wholesaleMinQty < 0 ? 0 : wholesaleMinQty,
        stock: stock,
        lowStockThreshold: threshold,
        extraBarcodes: _extraBarcodes,
      );
      await widget.controller.updateProduct(resultProduct);
    }

    if (mounted) {
      Navigator.of(context).pop(resultProduct);
    }
  }

  String? _validateNonNegativeDouble(String? value, String label) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null || parsed < 0) {
      return widget.controller.strings.invalidNumber(label);
    }
    return null;
  }

  String? _validateNonNegativeInt(String? value, String label) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null || parsed < 0) {
      return widget.controller.strings.invalidNumber(label);
    }
    return null;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final savedPath = await ProductImageService.pickAndSaveThumbnail(
        source: source,
        productId: widget.existing?.id,
      );
      if (savedPath == null || !mounted) return;
      final old = _imagePath;
      setState(() => _imagePath = savedPath);
      if (old.isNotEmpty && old != widget.existing?.imagePath) {
        await ProductImageService.deleteImageFile(old);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.strings.photoPickFailedMsg)),
      );
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  String? _validateSignedQty(String? value, String label) {
    final parsed = parseQty(value ?? '');
    if (parsed == null) {
      return widget.controller.strings.invalidNumber(label);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.existing != null;
    final strings = widget.controller.strings;
    final categories = widget.controller.categories;
    final currentCat = _categoryController.text.trim();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? strings.editGood : strings.addNewGood,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                autofocus: !isEdit,
                decoration: InputDecoration(
                  labelText: strings.productNameRequired,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? strings.productNameError
                    : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onTap: () => selectAllText(_costController),
                      decoration: InputDecoration(
                        labelText: strings.costPriceRequired,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: strings.currencyCalculatorTitle,
                          onPressed: () => _openCalculator(_costController),
                          icon: const Icon(Icons.calculate_outlined),
                        ),
                      ),
                      validator: (v) =>
                          _validateNonNegativeDouble(v, strings.costShort),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _sellController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onTap: () => selectAllText(_sellController),
                      decoration: InputDecoration(
                        labelText: strings.sellPriceRequired,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: strings.currencyCalculatorTitle,
                          onPressed: () => _openCalculator(_sellController),
                          icon: const Icon(Icons.calculate_outlined),
                        ),
                      ),
                      validator: (v) =>
                          _validateNonNegativeDouble(v, strings.sellShort),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _stockController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                onTap: () => selectAllText(_stockController),
                decoration: InputDecoration(
                  labelText: strings.stockQtyRequired,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: strings.currencyCalculatorTitle,
                    onPressed: () => _openCalculator(
                      _stockController,
                      integerMode: false,
                    ),
                    icon: const Icon(Icons.calculate_outlined),
                  ),
                ),
                validator: (v) => _validateSignedQty(v, 'stock'),
              ),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                maintainState: true,
                initiallyExpanded: isEdit,
                title: Text(strings.moreOptionsBtn),
                childrenPadding: const EdgeInsets.only(top: 6, bottom: 8),
                children: [
                  Row(
                    children: [
                      ProductThumbnail(
                        imagePath: _imagePath,
                        size: 56,
                        borderRadius: 10,
                        onTap: _imagePath.isNotEmpty
                            ? () => showProductPhotoPreview(
                                  context,
                                  title: _nameController.text.trim().isNotEmpty
                                      ? _nameController.text.trim()
                                      : strings.productPhotoLabel,
                                  imagePath: _imagePath,
                                )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickingImage
                                  ? null
                                  : () => _pickPhoto(ImageSource.camera),
                              icon: const Icon(
                                Icons.photo_camera_outlined,
                                size: 18,
                              ),
                              label: Text(strings.cameraBtn),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickingImage
                                  ? null
                                  : () => _pickPhoto(ImageSource.gallery),
                              icon: const Icon(
                                Icons.photo_library_outlined,
                                size: 18,
                              ),
                              label: Text(strings.galleryBtn),
                            ),
                            if (_imagePath.isNotEmpty)
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => _imagePath = ''),
                                icon: const Icon(Icons.delete_outline, size: 18),
                                label: Text(strings.removePhotoBtn),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _categoryController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: strings.categoryLabel,
                            border: const OutlineInputBorder(),
                            suffixIcon: categories.isEmpty
                                ? null
                                : PopupMenuButton<String>(
                                    icon: const Icon(Icons.arrow_drop_down),
                                    onSelected: (cat) => setState(
                                      () => _categoryController.text = cat,
                                    ),
                                    itemBuilder: (_) => [
                                      for (final cat in categories)
                                        PopupMenuItem(
                                          value: cat,
                                          child: Text(cat),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _skuController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: strings.skuLabel,
                            border: const OutlineInputBorder(),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: strings.generateBarcodeAction,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      _generateBarcodeIntoController(
                                    _skuController,
                                    prefix: '200',
                                  ),
                                  icon: const Icon(Icons.auto_awesome, size: 20),
                                ),
                                IconButton(
                                  tooltip: strings.scanBarcodeTitle,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      _scanIntoController(_skuController),
                                  icon: const Icon(
                                    Icons.qr_code_scanner,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_skuController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ProductBarcodeWidget(
                      code: _skuController.text.trim(),
                      compact: true,
                    ),
                  ],
                  if (categories.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (_, index) {
                          final cat = categories[index];
                          return ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(cat),
                            selected: currentCat == cat,
                            onSelected: (_) => setState(
                              () => _categoryController.text = cat,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _wholesaleController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onTap: () => selectAllText(_wholesaleController),
                          decoration: InputDecoration(
                            labelText: strings.wholesalePriceLabel,
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: strings.currencyCalculatorTitle,
                              onPressed: () =>
                                  _openCalculator(_wholesaleController),
                              icon: const Icon(Icons.calculate_outlined),
                            ),
                          ),
                          validator: (v) {
                            final raw = (v ?? '').trim();
                            if (raw.isEmpty) return null;
                            return _validateNonNegativeDouble(
                              raw,
                              strings.wholesaleShort,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _wholesaleMinQtyController,
                          keyboardType: TextInputType.number,
                          onTap: () => selectAllText(_wholesaleMinQtyController),
                          decoration: InputDecoration(
                            labelText: strings.wholesaleMinQtyLabel,
                            hintText: '5',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final raw = (v ?? '').trim();
                            if (raw.isEmpty) return null;
                            return _validateNonNegativeInt(
                              raw,
                              strings.wholesaleMinQtyLabel,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _thresholdController,
                    keyboardType: TextInputType.number,
                    onTap: () => selectAllText(_thresholdController),
                    decoration: InputDecoration(
                      labelText: strings.lowStockAlertLabel,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        _validateNonNegativeInt(v, 'threshold'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _nomenclatureController,
                          decoration: InputDecoration(
                            labelText: strings.nomenclatureLabel,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _unitController,
                          decoration: InputDecoration(
                            labelText: strings.unitMeasureLabel,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _printNameController,
                    decoration: InputDecoration(
                      labelText: strings.printNameLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _packQtyController,
                          decoration: InputDecoration(
                            labelText: strings.packQtyLabel,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _boxQtyController,
                          decoration: InputDecoration(
                            labelText: strings.boxQtyLabel,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _unitWeightController,
                          decoration: InputDecoration(
                            labelText: strings.unitWeightLabel,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _packBarcodeController,
                          decoration: InputDecoration(
                            labelText: strings.packBarcodeLabel,
                            border: const OutlineInputBorder(),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: strings.generateBarcodeAction,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      _generateBarcodeIntoController(
                                    _packBarcodeController,
                                    prefix: '201',
                                  ),
                                  icon: const Icon(Icons.auto_awesome, size: 18),
                                ),
                                IconButton(
                                  tooltip: strings.scanBarcodeTitle,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _scanIntoController(
                                    _packBarcodeController,
                                  ),
                                  icon: const Icon(
                                    Icons.qr_code_scanner,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _boxBarcodeController,
                          decoration: InputDecoration(
                            labelText: strings.boxBarcodeLabel,
                            border: const OutlineInputBorder(),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: strings.generateBarcodeAction,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      _generateBarcodeIntoController(
                                    _boxBarcodeController,
                                    prefix: '202',
                                  ),
                                  icon: const Icon(Icons.auto_awesome, size: 18),
                                ),
                                IconButton(
                                  tooltip: strings.scanBarcodeTitle,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _scanIntoController(
                                    _boxBarcodeController,
                                  ),
                                  icon: const Icon(
                                    Icons.qr_code_scanner,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_extraBarcodes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        strings.extraBarcodesLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final code in _extraBarcodes)
                            InputChip(
                              avatar: const Icon(Icons.qr_code_2, size: 16),
                              label: Text(code),
                              onDeleted: () => setState(
                                () => _extraBarcodes.remove(code),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submit,
                child: Text(isEdit ? strings.saveChanges : strings.addProductBtn),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
