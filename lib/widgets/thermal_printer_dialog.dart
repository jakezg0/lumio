import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../l10n/app_strings.dart';
import '../services/thermal_printer_service.dart';

Future<ThermalPrinterConfig?> showThermalPrinterSetupDialog(
  BuildContext context, {
  required AppStrings strings,
  String shopName = '',
}) {
  return showDialog<ThermalPrinterConfig>(
    context: context,
    builder: (_) => _ThermalPrinterSetupDialog(
      strings: strings,
      shopName: shopName,
    ),
  );
}

Future<void> printBytesOrSetupPrinter(
  BuildContext context, {
  required AppStrings strings,
  required String shopName,
  required List<int> Function(ThermalPrinterConfig config) buildBytes,
}) async {
  var config = await ThermalPrinterService.loadConfig();
  if (!config.isConfigured) {
    if (!context.mounted) return;
    final selected = await showThermalPrinterSetupDialog(
      context,
      strings: strings,
      shopName: shopName,
    );
    if (selected == null || !selected.isConfigured) return;
    config = selected;
  }

  final ok = await ThermalPrinterService.printBytes(buildBytes(config));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(ok ? strings.printSuccessMsg : strings.printFailedMsg),
    ),
  );
}

class _ThermalPrinterSetupDialog extends StatefulWidget {
  const _ThermalPrinterSetupDialog({
    required this.strings,
    required this.shopName,
  });

  final AppStrings strings;
  final String shopName;

  @override
  State<_ThermalPrinterSetupDialog> createState() =>
      _ThermalPrinterSetupDialogState();
}

class _ThermalPrinterSetupDialogState
    extends State<_ThermalPrinterSetupDialog> {
  List<BluetoothInfo> _devices = const [];
  ThermalPrinterConfig _config = const ThermalPrinterConfig();
  bool _loading = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await ThermalPrinterService.loadConfig();
    final devices = await ThermalPrinterService.getPairedPrinters();
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _devices = devices;
      _loading = false;
    });
  }

  Future<void> _testPrint() async {
    if (!_config.isConfigured || _testing) return;
    setState(() => _testing = true);
    await ThermalPrinterService.saveConfig(_config);
    final ok = await ThermalPrinterService.printBytes(
      ThermalPrinterService.buildTestPageEscPos(
        shopName: widget.shopName,
        is80mm: _config.is80mm,
      ),
    );
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? widget.strings.printSuccessMsg : widget.strings.printFailedMsg,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      title: Text(strings.selectPrinterTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.paperWidthLabel,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('58 мм')),
                  ButtonSegment(value: true, label: Text('80 мм')),
                ],
                selected: {_config.is80mm},
                onSelectionChanged: (sel) {
                  setState(() => _config = _config.copyWith(is80mm: sel.first));
                },
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_devices.isEmpty)
                Text(
                  strings.noPairedPrintersMsg,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                for (final d in _devices)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _config.macAddress == d.macAdress
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(d.name.isEmpty ? d.macAdress : d.name),
                    subtitle: Text(d.macAdress),
                    onTap: () {
                      setState(() {
                        _config = _config.copyWith(
                          macAddress: d.macAdress,
                          name: d.name,
                        );
                      });
                    },
                  ),
            ],
          ),
        ),
      ),
      actions: [
        if (_config.isConfigured)
          TextButton(
            onPressed: _testing ? null : _testPrint,
            child: Text(strings.testPrintBtn),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _config.isConfigured
              ? () async {
                  await ThermalPrinterService.saveConfig(_config);
                  if (context.mounted) {
                    Navigator.of(context).pop(_config);
                  }
                }
              : null,
          child: Text(strings.saveChanges),
        ),
      ],
    );
  }
}
