import 'package:flutter/material.dart';

import '../models/product.dart';
import '../screens/barcode_scanner_screen.dart';
import '../state/shop_controller.dart';
import 'currency_calculator_dialog.dart';

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
  late final TextEditingController _stockController;
  late final TextEditingController _thresholdController;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
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
    _stockController = TextEditingController(
      text: item != null ? '${item.stock}' : '${widget.initialStock}',
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

    final cost = double.parse(_costController.text.trim());
    final sell = double.parse(_sellController.text.trim());
    final stock = int.parse(_stockController.text.trim());
    final threshold = int.parse(_thresholdController.text.trim());

    final existing = widget.existing;
    final Product resultProduct;
    if (existing == null) {
      resultProduct = await widget.controller.addProduct(
        name: _nameController.text,
        category: _categoryController.text,
        sku: _skuController.text,
        nomenclature: _nomenclatureController.text,
        printName: _printNameController.text,
        packQty: _packQtyController.text,
        boxQty: _boxQtyController.text,
        packBarcode: _packBarcodeController.text,
        boxBarcode: _boxBarcodeController.text,
        unitWeight: _unitWeightController.text,
        unit: _unitController.text,
        costPrice: cost,
        sellPrice: sell,
        stock: stock,
        lowStockThreshold: threshold,
      );
    } else {
      resultProduct = existing.copyWith(
        name: _nameController.text.trim(),
        category: _categoryController.text.trim().isEmpty
            ? 'General'
            : _categoryController.text.trim(),
        sku: _skuController.text.trim(),
        nomenclature: _nomenclatureController.text.trim(),
        printName: _printNameController.text.trim(),
        packQty: _packQtyController.text.trim(),
        boxQty: _boxQtyController.text.trim(),
        packBarcode: _packBarcodeController.text.trim(),
        boxBarcode: _boxBarcodeController.text.trim(),
        unitWeight: _unitWeightController.text.trim(),
        unit: _unitController.text.trim(),
        costPrice: cost,
        sellPrice: sell,
        stock: stock,
        lowStockThreshold: threshold,
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

  String? _validateSignedInt(String? value, String label) {
    final parsed = int.tryParse((value ?? '').trim());
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
                      decoration: InputDecoration(
                        labelText: strings.skuLabel,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: strings.scanBarcodeTitle,
                          onPressed: () =>
                              _scanIntoController(_skuController),
                          icon: const Icon(Icons.qr_code_scanner),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
                    child: TextFormField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
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
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stockController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: strings.stockQtyRequired,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: strings.currencyCalculatorTitle,
                          onPressed: () => _openCalculator(
                            _stockController,
                            integerMode: true,
                          ),
                          icon: const Icon(Icons.calculate_outlined),
                        ),
                      ),
                      validator: (v) => _validateSignedInt(v, 'stock'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _thresholdController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: strings.lowStockAlertLabel,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          _validateNonNegativeInt(v, 'threshold'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(strings.additionalDetailsLabel),
                childrenPadding: const EdgeInsets.only(top: 6, bottom: 8),
                children: [
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
                            suffixIcon: IconButton(
                              tooltip: strings.scanBarcodeTitle,
                              onPressed: () =>
                                  _scanIntoController(_packBarcodeController),
                              icon: const Icon(Icons.qr_code_scanner),
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
                            suffixIcon: IconButton(
                              tooltip: strings.scanBarcodeTitle,
                              onPressed: () =>
                                  _scanIntoController(_boxBarcodeController),
                              icon: const Icon(Icons.qr_code_scanner),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
