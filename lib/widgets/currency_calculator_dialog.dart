import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'formatters.dart';

Future<double?> showCurrencyCalculatorDialog(
  BuildContext context, {
  required AppStrings strings,
  required AppCurrency targetCurrency,
  String? productName,
  double? initialValue,
  bool integerMode = false,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _CurrencyCalculatorDialog(
      strings: strings,
      targetCurrency: targetCurrency,
      productName: productName,
      initialValue: initialValue,
      integerMode: integerMode,
    ),
  );
}

class _CurrencyCalculatorDialog extends StatefulWidget {
  const _CurrencyCalculatorDialog({
    required this.strings,
    required this.targetCurrency,
    this.productName,
    this.initialValue,
    this.integerMode = false,
  });

  final AppStrings strings;
  final AppCurrency targetCurrency;
  final String? productName;
  final double? initialValue;
  final bool integerMode;

  @override
  State<_CurrencyCalculatorDialog> createState() =>
      _CurrencyCalculatorDialogState();
}

class _CurrencyCalculatorDialogState extends State<_CurrencyCalculatorDialog> {
  static String _lastCurrency = '';
  static final Map<String, String> _lastRates = {};

  late String _currencyCode;
  late final TextEditingController _exprCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _extraCtrl;

  static const _currencies = ['KZT', 'USD', 'RUB', 'CNY', 'EUR'];

  @override
  void initState() {
    super.initState();
    final targetCode = widget.targetCurrency.code;
    _currencyCode = widget.integerMode
        ? targetCode
        : (_lastCurrency.isNotEmpty ? _lastCurrency : targetCode);
    final initVal = widget.initialValue;
    final initText = (initVal != null && initVal > 0)
        ? (initVal == initVal.roundToDouble()
            ? initVal.toStringAsFixed(0)
            : initVal.toStringAsFixed(2))
        : '';
    _exprCtrl = TextEditingController(text: initText);
    if (initText.isNotEmpty) {
      _exprCtrl.selection =
          TextSelection(baseOffset: 0, extentOffset: initText.length);
    }
    _rateCtrl = TextEditingController(
      text: _currencyCode == targetCode ? '1' : (_lastRates[_currencyCode] ?? ''),
    );
    _extraCtrl = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _exprCtrl.dispose();
    _rateCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  double _evalExpression(String raw) {
    final cleaned = raw
        .replaceAll(' ', '')
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[×xXхХ✕✖∙⋅]'), '*')
        .replaceAll('÷', '/');
    if (cleaned.isEmpty) return 0;

    final tokens = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < cleaned.length; i++) {
      final ch = cleaned[i];
      final isUnaryMinus = ch == '-' &&
          (i == 0 || '+-*/'.contains(cleaned[i - 1]));
      if (!isUnaryMinus && '+-*/'.contains(ch)) {
        if (buf.isNotEmpty) {
          tokens.add(buf.toString());
          buf.clear();
        }
        tokens.add(ch);
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) {
      tokens.add(buf.toString());
    }
    if (tokens.isEmpty) return 0;

    // Trim trailing operator while user is still typing
    while (tokens.isNotEmpty && '+-*/'.contains(tokens.last)) {
      tokens.removeLast();
    }
    if (tokens.isEmpty) return 0;

    final values = <double>[];
    final ops = <String>[];
    for (final t in tokens) {
      if ('+-*/'.contains(t)) {
        ops.add(t);
      } else {
        final v = double.tryParse(t);
        if (v == null) return 0;
        values.add(v);
      }
    }
    if (values.isEmpty || values.length != ops.length + 1) return 0;

    // First pass: * and /
    final reducedVals = <double>[values[0]];
    final reducedOps = <String>[];
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      final rhs = values[i + 1];
      if (op == '*') {
        reducedVals[reducedVals.length - 1] *= rhs;
      } else if (op == '/') {
        reducedVals[reducedVals.length - 1] =
            rhs == 0 ? 0 : reducedVals.last / rhs;
      } else {
        reducedOps.add(op);
        reducedVals.add(rhs);
      }
    }

    // Second pass: + and -
    var acc = reducedVals[0];
    for (var i = 0; i < reducedOps.length; i++) {
      if (reducedOps[i] == '+') {
        acc += reducedVals[i + 1];
      } else {
        acc -= reducedVals[i + 1];
      }
    }
    return acc.isFinite ? acc : 0;
  }

  double get _calculated {
    final base = _evalExpression(_exprCtrl.text);
    final isSameCurrency = _currencyCode == widget.targetCurrency.code;
    if (widget.integerMode || isSameCurrency) {
      final extra =
          double.tryParse(_extraCtrl.text.trim().replaceAll(',', '.')) ?? 0;
      final res = base + extra;
      return res < 0 ? 0 : res;
    }
    final rate =
        double.tryParse(_rateCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final extra =
        double.tryParse(_extraCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final res = base * rate + extra;
    return res < 0 ? 0 : res;
  }

  void _insertOp(String op) {
    final text = _exprCtrl.text;
    final sel = _exprCtrl.selection;
    final pos = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(pos, end, op);
    _exprCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: pos + op.length),
    );
    setState(() {});
  }

  void _submit() {
    final total = _calculated;
    if (total <= 0 && !widget.integerMode) return;
    if (!widget.integerMode) {
      _lastCurrency = _currencyCode;
      if (_currencyCode != widget.targetCurrency.code &&
          _rateCtrl.text.trim().isNotEmpty) {
        _lastRates[_currencyCode] = _rateCtrl.text.trim();
      }
    }
    final result = widget.integerMode ? total.roundToDouble() : total;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final total = _calculated;
    final isSameCurrency = _currencyCode == widget.targetCurrency.code;
    final displayTotal = widget.integerMode
        ? '${total.round()}'
        : formatMoney(total, widget.targetCurrency);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Text(strings.currencyCalculatorTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.productName != null) ...[
              Text(
                widget.productName!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
            ],
            if (!widget.integerMode) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final code in _currencies)
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(code),
                      selected: _currencyCode == code,
                      onSelected: (_) {
                        setState(() {
                          _currencyCode = code;
                          if (code == widget.targetCurrency.code) {
                            _rateCtrl.text = '1';
                          } else {
                            _rateCtrl.text = _lastRates[code] ?? '';
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _exprCtrl,
              autofocus: true,
              keyboardType: TextInputType.text,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: widget.integerMode
                    ? strings.stockQtyRequired
                    : strings.foreignPriceLabel(_currencyCode),
                hintText: '100*5+50',
                suffixIcon: _exprCtrl.text.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _exprCtrl.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final op in const ['+', '-', '*', '/'])
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      op == '*' ? '× / *' : (op == '/' ? '÷ /' : op),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _insertOp(op),
                  ),
              ],
            ),
            if (!widget.integerMode && !isSameCurrency) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _rateCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: strings.exchangeRateLabel,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _extraCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: strings.extraPerUnitLabel,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.integerMode
                    ? '= $displayTotal'
                    : strings.calculatedUnitCostLabel(displayTotal),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: (total > 0 || widget.integerMode) ? _submit : null,
          child: Text(strings.applyAction),
        ),
      ],
    );
  }
}
