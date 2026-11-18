import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/export_service.dart';
import '../state/shop_controller.dart';

class BackupExportSheet extends StatelessWidget {
  const BackupExportSheet({super.key, required this.controller});

  final ShopController controller;

  Future<void> _exportAndCopy(
    BuildContext context, {
    required String filename,
    required String content,
  }) async {
    final strings = controller.strings;
    await Clipboard.setData(ClipboardData(text: content));
    try {
      final path = await ExportService.saveExportFile(filename, content);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.savedToPathMsg(path))),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.copiedToClipboardMsg)),
        );
      }
    }
  }

  Future<void> _promptRestoreJson(BuildContext context) async {
    final strings = controller.strings;
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => _RestoreJsonDialog(
        title: strings.restoreJsonBackup,
        hintLabel: strings.pasteBackupJsonHint,
        cancelLabel: strings.cancel,
        confirmLabel: strings.confirm,
      ),
    );

    if (raw == null || raw.trim().isEmpty) return;
    try {
      final snapshot = ExportService.parseBackupJson(raw);
      await controller.restoreFromSnapshot(snapshot);
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.backupRestoredMsg)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.invalidBackupMsg)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = controller.strings;
    final stamp = DateTime.now().toIso8601String().split('T').first;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.backupAndExport,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _exportAndCopy(
              context,
              filename: 'goods_$stamp.csv',
              content: ExportService.buildProductsCsv(controller.products),
            ),
            icon: const Icon(Icons.table_chart_outlined),
            label: Text(strings.exportProductsCsv),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _exportAndCopy(
              context,
              filename: 'sales_$stamp.csv',
              content: ExportService.buildSalesCsv(controller.sales),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(strings.exportSalesCsv),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _exportAndCopy(
              context,
              filename: 'shop_backup_$stamp.json',
              content: ExportService.buildBackupJson(
                controller.createBackupSnapshot(),
              ),
            ),
            icon: const Icon(Icons.save_alt_outlined),
            label: Text(strings.exportJsonBackup),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _promptRestoreJson(context),
            icon: const Icon(Icons.restore_page_outlined),
            label: Text(strings.restoreJsonBackup),
          ),
        ],
        ),
      ),
    );
  }
}

class _RestoreJsonDialog extends StatefulWidget {
  const _RestoreJsonDialog({
    required this.title,
    required this.hintLabel,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final String hintLabel;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<_RestoreJsonDialog> createState() => _RestoreJsonDialogState();
}

class _RestoreJsonDialogState extends State<_RestoreJsonDialog> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: TextField(
          controller: _textController,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: widget.hintLabel,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_textController.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
