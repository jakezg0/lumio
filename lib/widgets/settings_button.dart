import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../screens/archive_trash_screen.dart';
import '../state/shop_controller.dart';
import 'backup_export_sheet.dart';

class SettingsButton extends StatelessWidget {
  const SettingsButton({
    super.key,
    required this.controller,
  });

  final ShopController controller;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: controller.strings.settingsTitle,
      onPressed: () => _showSettingsDialog(context),
      icon: Icon(
        controller.cashierMode ? Icons.lock_outline : Icons.settings_outlined,
      ),
    );
  }

  Future<void> _openShopProfileDialog(BuildContext context) async {
    final strings = controller.strings;
    final result = await showDialog<_ShopProfileResult>(
      context: context,
      builder: (_) => _ShopProfileDialog(
        title: strings.shopProfileBtn,
        nameLabel: strings.shopNameLabel,
        addressLabel: strings.shopAddressLabel,
        phoneLabel: strings.shopPhoneLabel,
        footerLabel: strings.receiptFooterLabel,
        cancelLabel: strings.cancel,
        saveLabel: strings.saveChanges,
        initialName: controller.shopName,
        initialAddress: controller.shopAddress,
        initialPhone: controller.shopPhone,
        initialFooter: controller.receiptFooter,
      ),
    );

    if (result == null) return;
    await controller.updateShopProfile(
      shopName: result.name,
      shopAddress: result.address,
      shopPhone: result.phone,
      receiptFooter: result.footer,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.savedMsg)),
      );
    }
  }

  Future<void> _openPinSetupDialog(BuildContext context) async {
    final strings = controller.strings;
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _PinPromptDialog(
        title: strings.setOwnerPinBtn,
        hintLabel: strings.enterPinHint,
        cancelLabel: strings.cancel,
        confirmLabel: strings.saveChanges,
        initialPin: controller.ownerPin,
      ),
    );
    if (pin == null) return;
    await controller.setOwnerPin(pin);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.pinUpdatedMsg)),
      );
    }
  }

  Future<void> _toggleCashierMode(BuildContext dialogContext) async {
    final strings = controller.strings;
    if (!controller.cashierMode) {
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      await controller.enterCashierMode();
      return;
    }

    if (!controller.hasOwnerPin) {
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      await controller.exitCashierMode('');
      return;
    }

    final attempt = await showDialog<String>(
      context: dialogContext,
      builder: (_) => _PinPromptDialog(
        title: strings.unlockOwnerMode,
        hintLabel: strings.enterPinHint,
        cancelLabel: strings.cancel,
        confirmLabel: strings.confirm,
        autofocus: true,
      ),
    );

    if (attempt == null) return;
    final ok = await controller.exitCashierMode(attempt);
    if (ok) {
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    } else if (dialogContext.mounted) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(strings.wrongPinMsg)),
      );
    }
  }

  Future<void> _showSettingsDialog(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final strings = controller.strings;
          final isCashier = controller.cashierMode;
          final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.settingsTitle,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: strings.close,
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.languageLabel,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(strings.autoLanguageLabel),
                        selected: controller.followSystemLanguage,
                        onSelected: (_) => controller.setFollowSystemLanguage(),
                      ),
                      for (final lang in AppLanguage.values)
                        ChoiceChip(
                          label: Text(lang.displayName),
                          selected: !controller.followSystemLanguage &&
                              controller.language == lang,
                          onSelected: (_) => controller.setLanguage(lang),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings.currencyLabel,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final currency in AppCurrency.values)
                        ChoiceChip(
                          label: Text('${currency.code} (${currency.symbol})'),
                          selected: controller.currency == currency,
                          onSelected: (_) => controller.setCurrency(currency),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: () => _toggleCashierMode(sheetContext),
                    icon: Icon(
                      isCashier
                          ? Icons.lock_open_outlined
                          : Icons.lock_outline,
                    ),
                    label: Text(
                      isCashier
                          ? strings.unlockOwnerMode
                          : strings.switchToCashier,
                    ),
                  ),
                  if (!isCashier) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ArchiveTrashScreen(controller: controller),
                          ),
                        );
                      },
                      icon: const Icon(Icons.archive_outlined),
                      label: Text(
                        (controller.archiveCount + controller.trashCount) > 0
                            ? '${strings.archiveAndTrash} (${controller.archiveCount + controller.trashCount})'
                            : strings.archiveAndTrash,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _openPinSetupDialog(sheetContext),
                      icon: const Icon(Icons.pin_outlined),
                      label: Text(strings.setOwnerPinBtn),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _openShopProfileDialog(sheetContext),
                      icon: const Icon(Icons.storefront_outlined),
                      label: Text(strings.shopProfileBtn),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) =>
                              BackupExportSheet(controller: controller),
                        );
                      },
                      icon: const Icon(Icons.import_export),
                      label: Text(strings.backupAndExport),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PinPromptDialog extends StatefulWidget {
  const _PinPromptDialog({
    required this.title,
    required this.hintLabel,
    required this.cancelLabel,
    required this.confirmLabel,
    this.initialPin = '',
    this.autofocus = false,
  });

  final String title;
  final String hintLabel;
  final String cancelLabel;
  final String confirmLabel;
  final String initialPin;
  final bool autofocus;

  @override
  State<_PinPromptDialog> createState() => _PinPromptDialogState();
}

class _PinPromptDialogState extends State<_PinPromptDialog> {
  late final TextEditingController _pinCtrl;

  @override
  void initState() {
    super.initState();
    _pinCtrl = TextEditingController(text: widget.initialPin);
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _pinCtrl,
        autofocus: widget.autofocus,
        keyboardType: TextInputType.number,
        obscureText: true,
        decoration: InputDecoration(
          labelText: widget.hintLabel,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_pinCtrl.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _ShopProfileResult {
  const _ShopProfileResult({
    required this.name,
    required this.address,
    required this.phone,
    required this.footer,
  });

  final String name;
  final String address;
  final String phone;
  final String footer;
}

class _ShopProfileDialog extends StatefulWidget {
  const _ShopProfileDialog({
    required this.title,
    required this.nameLabel,
    required this.addressLabel,
    required this.phoneLabel,
    required this.footerLabel,
    required this.cancelLabel,
    required this.saveLabel,
    required this.initialName,
    required this.initialAddress,
    required this.initialPhone,
    required this.initialFooter,
  });

  final String title;
  final String nameLabel;
  final String addressLabel;
  final String phoneLabel;
  final String footerLabel;
  final String cancelLabel;
  final String saveLabel;
  final String initialName;
  final String initialAddress;
  final String initialPhone;
  final String initialFooter;

  @override
  State<_ShopProfileDialog> createState() => _ShopProfileDialogState();
}

class _ShopProfileDialogState extends State<_ShopProfileDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addrCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _footerCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _addrCtrl = TextEditingController(text: widget.initialAddress);
    _phoneCtrl = TextEditingController(text: widget.initialPhone);
    _footerCtrl = TextEditingController(text: widget.initialFooter);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _phoneCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: widget.nameLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addrCtrl,
              decoration: InputDecoration(
                labelText: widget.addressLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneCtrl,
              decoration: InputDecoration(
                labelText: widget.phoneLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _footerCtrl,
              decoration: InputDecoration(
                labelText: widget.footerLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _ShopProfileResult(
              name: _nameCtrl.text,
              address: _addrCtrl.text,
              phone: _phoneCtrl.text,
              footer: _footerCtrl.text,
            ),
          ),
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}
