import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../l10n/app_strings.dart';
import '../screens/archive_trash_screen.dart';
import '../state/shop_controller.dart';
import 'backup_export_sheet.dart';
import 'feature_usage_sheet.dart';

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

  Future<bool> _authenticateWithDevice(
    BuildContext context, {
    String? reason,
  }) async {
    final strings = controller.strings;
    final auth = LocalAuthentication();
    try {
      final isSupported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      if (!isSupported && !canCheck) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.biometricUnavailableMsg)),
          );
        }
        return false;
      }
      return await auth.authenticate(
        localizedReason: reason ?? strings.biometricPromptReason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.biometricUnavailableMsg)),
        );
      }
      return false;
    }
  }

  Future<void> _recoverForgottenPin(
    BuildContext dialogContext, {
    bool closeSheetOnSuccess = true,
  }) async {
    final strings = controller.strings;
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: Text(strings.resetPinTitle),
        content: Text(strings.resetPinConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !dialogContext.mounted) return;
    final verified = await _authenticateWithDevice(
      dialogContext,
      reason: strings.resetPinPromptReason,
    );
    if (!verified) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text(strings.biometricFailedMsg)),
        );
      }
      return;
    }
    await controller.resetOwnerPinAndUnlock();
    if (dialogContext.mounted) {
      if (closeSheetOnSuccess) {
        Navigator.of(dialogContext).pop();
      }
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(content: Text(strings.pinResetSuccessMsg)),
      );
    }
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
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _ChangePinDialog(
        strings: strings,
        existingPin: controller.ownerPin,
      ),
    );
    if (result == null) return;
    if (result == _ChangePinDialog.forgotPinSentinel) {
      if (context.mounted) {
        await _recoverForgottenPin(context, closeSheetOnSuccess: false);
      }
      return;
    }
    await controller.setOwnerPin(result);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isEmpty ? strings.pinRemovedMsg : strings.pinUpdatedMsg,
          ),
        ),
      );
    }
  }

  Future<void> _toggleBiometricUnlock(
    BuildContext context,
    bool enable,
  ) async {
    if (!enable) {
      await controller.setUseBiometricUnlock(false);
      return;
    }
    final ok = await _authenticateWithDevice(context);
    if (ok) {
      await controller.setUseBiometricUnlock(true);
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

    if (!controller.hasOwnerAuth) {
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      await controller.exitCashierMode('');
      return;
    }

    if (controller.useBiometricUnlock) {
      final verified = await _authenticateWithDevice(dialogContext);
      if (verified) {
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        await controller.unlockOwnerByBiometrics();
        return;
      }
      if (!controller.hasOwnerPin) {
        if (dialogContext.mounted) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            SnackBar(content: Text(strings.biometricFailedMsg)),
          );
        }
        return;
      }
    }

    if (!dialogContext.mounted) return;
    final attempt = await showDialog<String>(
      context: dialogContext,
      builder: (_) => _PinPromptDialog(
        title: strings.unlockOwnerMode,
        hintLabel: strings.enterPinHint,
        cancelLabel: strings.cancel,
        confirmLabel: strings.confirm,
        autofocus: true,
        biometricBtnLabel:
            controller.useBiometricUnlock ? strings.useBiometricBtn : null,
        forgotPinBtnLabel: strings.forgotPinBtn,
      ),
    );

    if (attempt == null) return;
    if (attempt == _PinPromptDialog.forgotPinSentinel) {
      if (!dialogContext.mounted) return;
      await _recoverForgottenPin(dialogContext);
      return;
    }
    if (attempt == _PinPromptDialog.biometricSentinel) {
      if (!dialogContext.mounted) return;
      final verified = await _authenticateWithDevice(dialogContext);
      if (verified) {
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        await controller.unlockOwnerByBiometrics();
      }
      return;
    }

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
                  const SizedBox(height: 4),
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      dense: true,
                      leading: const Icon(Icons.language, size: 20),
                      title: Text(
                        '${strings.languageLabel}, ${strings.currencyLabel}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      subtitle: Text(
                        '${controller.followSystemLanguage ? '${controller.language == AppLanguage.en ? 'Auto' : 'Авто'} (${controller.language.code})' : controller.language.displayName} • ${controller.currency.symbol} ${controller.currency.code}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<AppLanguage?>(
                              showSelectedIcon: false,
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              segments: [
                                ButtonSegment<AppLanguage?>(
                                  value: null,
                                  label: Text(
                                    controller.language == AppLanguage.en
                                        ? 'Auto'
                                        : 'Авто',
                                  ),
                                ),
                                for (final lang in AppLanguage.values)
                                  ButtonSegment<AppLanguage?>(
                                    value: lang,
                                    label: Text(lang.code),
                                  ),
                              ],
                              selected: {
                                controller.followSystemLanguage
                                    ? null
                                    : controller.language,
                              },
                              onSelectionChanged: (val) {
                                final lang = val.first;
                                if (lang == null) {
                                  controller.setFollowSystemLanguage();
                                } else {
                                  controller.setLanguage(lang);
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            SegmentedButton<AppCurrency>(
                              showSelectedIcon: false,
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              segments: [
                                for (final currency in AppCurrency.values)
                                  ButtonSegment<AppCurrency>(
                                    value: currency,
                                    label: Text(
                                      '${currency.symbol} ${currency.code}',
                                    ),
                                  ),
                              ],
                              selected: {controller.currency},
                              onSelectionChanged: (val) =>
                                  controller.setCurrency(val.first),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings.accessSectionLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          dense: true,
                          leading: Icon(
                            isCashier
                                ? Icons.lock_open_outlined
                                : Icons.lock_outline,
                          ),
                          title: Text(
                            isCashier
                                ? strings.unlockOwnerMode
                                : strings.switchToCashier,
                          ),
                          subtitle: Text(
                            isCashier
                                ? strings.cashierModeActiveStatus
                                : strings.ownerModeActiveStatus,
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 20),
                          onTap: () => _toggleCashierMode(sheetContext),
                        ),
                        if (!isCashier) ...[
                          const Divider(height: 1),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.pin_outlined),
                            title: Text(strings.setOwnerPinBtn),
                            subtitle: Text(
                              controller.hasOwnerPin
                                  ? strings.pinIsSetStatus
                                  : strings.pinNotSetStatus,
                              style: TextStyle(
                                color: controller.hasOwnerPin
                                    ? Colors.green.shade700
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 20),
                            onTap: () => _openPinSetupDialog(sheetContext),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            dense: true,
                            secondary: const Icon(Icons.fingerprint),
                            title: Text(strings.biometricUnlockLabel),
                            subtitle: Text(strings.biometricUnlockHint),
                            value: controller.useBiometricUnlock,
                            onChanged: (v) =>
                                _toggleBiometricUnlock(sheetContext, v),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            dense: true,
                            secondary:
                                const Icon(Icons.exposure_neg_1_outlined),
                            title: Text(strings.allowNegativeStockLabel),
                            subtitle: Text(strings.allowNegativeStockHint),
                            value: controller.allowNegativeStock,
                            onChanged: controller.setAllowNegativeStock,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isCashier) ...[
                    const SizedBox(height: 14),
                    Text(
                      strings.shopAndDataSectionLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Card(
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.storefront_outlined),
                            title: Text(strings.shopProfileBtn),
                            subtitle: Text(
                              controller.shopPhone.isNotEmpty
                                  ? '${controller.shopName} • ${controller.shopPhone}'
                                  : controller.shopName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing:
                                const Icon(Icons.chevron_right, size: 20),
                            onTap: () => _openShopProfileDialog(sheetContext),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.table_chart_outlined),
                            title: Text(strings.googleSheetsBtn),
                            subtitle: Text(
                              controller.googleSheetsUrl.isNotEmpty
                                  ? strings.connectedStatus
                                  : strings.notConfiguredStatus,
                              style: TextStyle(
                                color: controller.googleSheetsUrl.isNotEmpty
                                    ? Colors.green.shade700
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                              ),
                            ),
                            trailing:
                                const Icon(Icons.chevron_right, size: 20),
                            onTap: () {
                              controller.trackFeatureUsage(
                                FeatureUsageKeys.googleSheets,
                              );
                              Navigator.of(sheetContext).pop();
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                builder: (_) =>
                                    GoogleSheetsSheet(controller: controller),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.import_export),
                            title: Text(strings.backupAndExport),
                            subtitle: Text(
                              'CSV / JSON • ${controller.products.length}',
                            ),
                            trailing:
                                const Icon(Icons.chevron_right, size: 20),
                            onTap: () {
                              controller.trackFeatureUsage(
                                FeatureUsageKeys.backupExport,
                              );
                              Navigator.of(sheetContext).pop();
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                builder: (_) =>
                                    BackupExportSheet(controller: controller),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.archive_outlined),
                            title: Text(strings.archiveAndTrash),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if ((controller.archiveCount +
                                        controller.trashCount) >
                                    0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${controller.archiveCount + controller.trashCount}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right, size: 20),
                              ],
                            ),
                            onTap: () {
                              controller.trackFeatureUsage(
                                FeatureUsageKeys.archiveTrash,
                              );
                              Navigator.of(sheetContext).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ArchiveTrashScreen(
                                    controller: controller,
                                  ),
                                ),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.insights_outlined),
                            title: Text(strings.featureUsageBtn),
                            subtitle: Text(
                              strings.featureUsageSubtitle(
                                controller.totalFeatureUsageCount,
                                controller.featureUsage.values
                                    .where((s) => s.count > 0)
                                    .length,
                                FeatureUsageKeys.all.length,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing:
                                const Icon(Icons.chevron_right, size: 20),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                builder: (_) =>
                                    FeatureUsageSheet(controller: controller),
                              );
                            },
                          ),
                        ],
                      ),
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
    this.biometricBtnLabel,
    this.forgotPinBtnLabel,
  });

  static const String biometricSentinel = '__USE_BIOMETRIC__';
  static const String forgotPinSentinel = '__FORGOT_PIN__';

  final String title;
  final String hintLabel;
  final String cancelLabel;
  final String confirmLabel;
  final String initialPin;
  final bool autofocus;
  final String? biometricBtnLabel;
  final String? forgotPinBtnLabel;

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
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
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
            if (widget.biometricBtnLabel != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(_PinPromptDialog.biometricSentinel),
                icon: const Icon(Icons.fingerprint),
                label: Text(widget.biometricBtnLabel!),
              ),
            ],
            if (widget.forgotPinBtnLabel != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => Navigator.of(context)
                      .pop(_PinPromptDialog.forgotPinSentinel),
                  icon: const Icon(Icons.lock_reset_outlined, size: 18),
                  label: Text(widget.forgotPinBtnLabel!),
                ),
              ),
            ],
          ],
        ),
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

class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog({
    required this.strings,
    required this.existingPin,
  });

  static const String forgotPinSentinel = '__FORGOT_PIN__';

  final AppStrings strings;
  final String existingPin;

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final TextEditingController _currentCtrl = TextEditingController();
  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  String? _error;

  bool get _hasExisting => widget.existingPin.isNotEmpty;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final s = widget.strings;
    if (_hasExisting && _currentCtrl.text.trim() != widget.existingPin) {
      setState(() => _error = s.wrongPinMsg);
      return;
    }
    final nextPin = _newCtrl.text.trim();
    final confirmPin = _confirmCtrl.text.trim();
    if (nextPin.isEmpty) {
      setState(() => _error = s.enterPinHint);
      return;
    }
    if (nextPin != confirmPin) {
      setState(() => _error = s.pinsDoNotMatchMsg);
      return;
    }
    Navigator.of(context).pop(nextPin);
  }

  void _remove() {
    final s = widget.strings;
    if (_hasExisting && _currentCtrl.text.trim() != widget.existingPin) {
      setState(() => _error = s.wrongPinMsg);
      return;
    }
    Navigator.of(context).pop('');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(_hasExisting ? s.changePinTitle : s.setOwnerPinBtn),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_hasExisting) ...[
              TextField(
                controller: _currentCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: s.currentPinLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _newCtrl,
              autofocus: !_hasExisting,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: InputDecoration(
                labelText: s.newPinLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: InputDecoration(
                labelText: s.confirmPinLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
            if (_hasExisting) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => Navigator.of(context)
                      .pop(_ChangePinDialog.forgotPinSentinel),
                  icon: const Icon(Icons.lock_reset_outlined, size: 18),
                  label: Text(s.forgotPinBtn),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_hasExisting)
          TextButton(
            onPressed: _remove,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(s.removePinAction),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(s.saveChanges),
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
