import 'package:flutter/material.dart';

import '../state/shop_controller.dart';

/// Shows a confirmation dialog for irreversible deletions.
///
/// When [controller.hasOwnerPin] is true, the user must enter the valid Owner
/// PIN before the confirm action succeeds. Returns the verified PIN (or `''`
/// when no PIN is configured), or `null` if cancelled.
Future<String?> showPinProtectedDeleteDialog(
  BuildContext context, {
  required ShopController controller,
  required String title,
  required String body,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PinProtectedDeleteDialog(
      controller: controller,
      title: title,
      body: body,
      confirmLabel: confirmLabel,
    ),
  );
}

class _PinProtectedDeleteDialog extends StatefulWidget {
  const _PinProtectedDeleteDialog({
    required this.controller,
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  final ShopController controller;
  final String title;
  final String body;
  final String confirmLabel;

  @override
  State<_PinProtectedDeleteDialog> createState() =>
      _PinProtectedDeleteDialogState();
}

class _PinProtectedDeleteDialogState extends State<_PinProtectedDeleteDialog> {
  final TextEditingController _pinCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final strings = widget.controller.strings;
    if (!widget.controller.hasOwnerPin) {
      Navigator.of(context).pop('');
      return;
    }
    final pin = _pinCtrl.text.trim();
    if (!widget.controller.verifyOwnerPin(pin)) {
      setState(() => _error = strings.wrongPinMsg);
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final theme = Theme.of(context);
    final requiresPin = widget.controller.hasOwnerPin;

    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: theme.colorScheme.error,
      ),
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.body),
            if (requiresPin) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _pinCtrl,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: strings.enterOwnerPinToConfirm,
                  hintText: strings.enterPinHint,
                  errorText: _error,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
