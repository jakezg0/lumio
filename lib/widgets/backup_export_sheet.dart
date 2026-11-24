import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_strings.dart';
import '../models/product.dart';
import '../services/catalog_health_service.dart';
import '../services/daily_local_backup_service.dart';
import '../services/export_service.dart';
import '../services/google_sheets_service.dart';
import '../services/inventory_storage.dart';
import '../services/sheet_export_helper.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';

Future<void> shareJsonBackupOutsidePhone(
  BuildContext context,
  ShopController controller,
) async {
  await controller.ensureFullHistoryLoaded();
  final strings = controller.strings;
  final stamp = DateTime.now().toIso8601String().split('T').first;
  final jsonContent = ExportService.buildBackupJson(
    controller.createBackupSnapshot(),
  );
  final bytes = Uint8List.fromList(utf8.encode(jsonContent));
  await Share.shareXFiles(
    [
      XFile.fromData(
        bytes,
        name: 'lumio_backup_$stamp.json',
        mimeType: 'application/json',
      ),
    ],
    subject: 'Lumio Backup ($stamp)',
  );
  await controller.markExternalBackupSaved();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.externalBackupOpenedMsg)),
    );
  }
}

Future<bool> confirmAndRollbackRestore(
  BuildContext context,
  ShopController controller,
) async {
  final strings = controller.strings;
  final savedAt = controller.preRestoreBackupAt;
  final prettyDate = savedAt != null ? formatDateTime(savedAt) : null;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.restore),
      title: Text(strings.rollbackRestoreTitle),
      content: Text(strings.rollbackRestoreBody(prettyDate)),
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
  if (confirmed != true) return false;
  final ok = await controller.rollbackToPreRestoreBackup();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? strings.rollbackRestoredMsg : strings.noPreRestoreBackupMsg,
        ),
      ),
    );
  }
  return ok;
}

class BackupExportSheet extends StatelessWidget {
  const BackupExportSheet({
    super.key,
    required this.controller,
    this.initiallyExpandManualBackup = false,
  });

  final ShopController controller;
  final bool initiallyExpandManualBackup;

  @override
  Widget build(BuildContext context) {
    return GoogleSheetsSheet(
      controller: controller,
      initiallyExpandManualBackup: initiallyExpandManualBackup,
    );
  }
}

class _ManualBackupExportSection extends StatelessWidget {
  const _ManualBackupExportSection({required this.controller});

  final ShopController controller;

  Future<void> _exportAndCopy(
    BuildContext context, {
    required String filename,
    required String content,
    String? customCopiedMsg,
  }) async {
    final strings = controller.strings;
    await Clipboard.setData(ClipboardData(text: content));
    try {
      final path = await ExportService.saveExportFile(filename, content);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(customCopiedMsg ?? strings.savedToPathMsg(path))),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(customCopiedMsg ?? strings.copiedToClipboardMsg)),
        );
      }
    }
  }

  Future<void> _shareCsv(
    BuildContext context, {
    required String filename,
    required String content,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    await Share.shareXFiles([
      XFile.fromData(
        bytes,
        name: filename,
        mimeType: 'text/csv',
      ),
    ]);
  }

  Future<void> _openTableImportSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TableImportSheet(controller: controller),
    );
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
    final ShopDataSnapshot snapshot;
    try {
      snapshot = ExportService.parseBackupJson(raw);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.invalidBackupMsg)),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final includeSettings = await showDialog<bool>(
      context: context,
      builder: (_) => _RestoreScopeDialog(
        strings: strings,
        title: strings.restoreScopeTitle,
      ),
    );
    if (includeSettings == null) return;

    await controller.restoreFromSnapshot(
      snapshot,
      includeSettings: includeSettings,
    );
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${strings.backupRestoredMsg}. ${strings.preRestoreBackupSavedNote}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = controller.strings;
    final stamp = DateTime.now().toIso8601String().split('T').first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
            FilledButton.icon(
              onPressed: () => _exportAndCopy(
                context,
                filename: 'goods_sheets_$stamp.tsv',
                content: ExportService.buildProductsReadableTsv(controller.products),
                customCopiedMsg: strings.copiedForSheetsMsg,
              ),
              icon: const Icon(Icons.content_copy),
              label: Text(strings.copyForGoogleSheetsBtn),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _shareCsv(
                context,
                filename: 'goods_readable_$stamp.csv',
                content: ExportService.buildProductsReadableCsvWithBom(
                  controller.products,
                ),
              ),
              icon: const Icon(Icons.ios_share),
              label: Text(strings.shareReadableCsvBtn),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _exportAndCopy(
                context,
                filename: 'import_template.tsv',
                content: ExportService.buildImportTemplateTsv(),
                customCopiedMsg: strings.copiedTemplateMsg,
              ),
              icon: const Icon(Icons.description_outlined),
              label: Text(strings.copyImportTemplateBtn),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => _openTableImportSheet(context),
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(strings.importFromTableBtn),
            ),
            const Divider(height: 24),
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
            FilledButton.icon(
              onPressed: () => shareJsonBackupOutsidePhone(context, controller),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(strings.saveBackupOutsidePhoneBtn),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () async {
                await controller.ensureFullHistoryLoaded();
                if (!context.mounted) return;
                await _exportAndCopy(
                  context,
                  filename: 'shop_backup_$stamp.json',
                  content: ExportService.buildBackupJson(
                    controller.createBackupSnapshot(),
                  ),
                );
              },
              icon: const Icon(Icons.save_alt_outlined),
              label: Text(strings.exportJsonBackup),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _promptRestoreJson(context),
              icon: const Icon(Icons.restore_page_outlined),
              label: Text(strings.restoreJsonBackup),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final restored = await showDialog<bool>(
                  context: context,
                  builder: (_) =>
                      _DailyLocalBackupsDialog(controller: controller),
                );
                if (restored == true && context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.history_toggle_off),
              label: Text(strings.dailyLocalBackupsBtn),
            ),
            if (controller.hasPreRestoreBackup) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final ok = await confirmAndRollbackRestore(context, controller);
                  if (ok && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.undo, size: 18),
                label: Text(strings.rollbackLastRestoreBtn),
              ),
            ],
            if (!controller.cashierMode) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _YearEndArchiveDialog(controller: controller),
                ),
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text(strings.yearEndArchiveBtn),
              ),
            ],
      ],
    );
  }
}

class _DailyLocalBackupsDialog extends StatefulWidget {
  const _DailyLocalBackupsDialog({required this.controller});

  final ShopController controller;

  @override
  State<_DailyLocalBackupsDialog> createState() =>
      _DailyLocalBackupsDialogState();
}

class _DailyLocalBackupsDialogState extends State<_DailyLocalBackupsDialog> {
  late Future<List<DailyBackupEntry>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.listDailyLocalBackups();
  }

  void _reload() {
    setState(() { _future = widget.controller.listDailyLocalBackups(); });
  }

  Future<void> _saveNow() async {
    final strings = widget.controller.strings;
    setState(() => _busy = true);
    try {
      await widget.controller.createDailyLocalBackupNow();
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.dailyBackupSavedMsg)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreEntry(DailyBackupEntry entry) async {
    final strings = widget.controller.strings;
    final includeSettings = await showDialog<bool>(
      context: context,
      builder: (_) => _RestoreScopeDialog(
        strings: strings,
        title: strings.restoreScopeTitle,
      ),
    );
    if (includeSettings == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final ok = await widget.controller.restoreFromDailyLocalBackup(
        entry,
        includeSettings: includeSettings,
      );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${strings.backupRestoredMsg}. ${strings.preRestoreBackupSavedNote}',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.invalidBackupMsg)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    return AlertDialog(
      title: Text(strings.dailyLocalBackupsTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.dailyLocalBackupsDesc,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _saveNow,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(strings.saveDailyBackupNowBtn),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<DailyBackupEntry>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final items = snapshot.data ?? const <DailyBackupEntry>[];
                  if (items.isEmpty) {
                    return Text(strings.noDailyLocalBackupsMsg);
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in items)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.archive_outlined),
                            title: Text(entry.dateKey),
                            subtitle: Text(
                              '${formatDateTime(entry.modifiedAt)} • ${(entry.sizeBytes / 1024).toStringAsFixed(1)} KB',
                            ),
                            trailing: IconButton(
                              tooltip: strings.restoreAction,
                              onPressed: _busy ? null : () => _restoreEntry(entry),
                              icon: const Icon(Icons.restore),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(strings.close),
        ),
      ],
    );
  }
}

class _YearEndArchiveDialog extends StatefulWidget {
  const _YearEndArchiveDialog({required this.controller});

  final ShopController controller;

  @override
  State<_YearEndArchiveDialog> createState() => _YearEndArchiveDialogState();
}

class _YearEndArchiveDialogState extends State<_YearEndArchiveDialog> {
  bool _busy = false;
  String? _status;

  Future<void> _exportYear(int year, {required bool compress}) async {
    final ctrl = widget.controller;
    final strings = ctrl.strings;
    final rawSales = ctrl.rawSalesForYear(year);
    final rawStockIns = ctrl.rawStockInsForYear(year);

    setState(() {
      _busy = true;
      _status = null;
    });

    try {
      final saved = await ExportService.saveYearArchiveFiles(
        year: year,
        sales: rawSales,
        stockIns: rawStockIns,
        currency: ctrl.currency,
      );
      await Share.shareXFiles(
        [
          XFile(saved.jsonPath, mimeType: 'application/json'),
          XFile(saved.csvPath, mimeType: 'text/csv'),
        ],
        subject: 'Lumio Archive $year',
      );
      if (compress) {
        final res = await ctrl.archiveAndCompressYear(year);
        if (!mounted) return;
        final msg = StringBuffer(
          strings.yearCompressedMsg(
            year,
            res.compressedSales,
            res.compressedStockIns,
          ),
        );
        if (res.keptUnpaidSales > 0) {
          msg.write(' ${strings.unpaidDebtsKeptNote(res.keptUnpaidSales)}');
        }
        setState(() => _status = msg.toString());
      } else {
        if (!mounted) return;
        setState(() => _status = strings.savedToPathMsg(saved.jsonPath));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final strings = ctrl.strings;
    final years = ctrl.archivablePastYears;

    return AlertDialog(
      title: Text(strings.yearEndArchiveTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.yearEndArchiveDesc,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (years.isEmpty)
                Text(strings.noPastYearsToArchiveMsg)
              else
                for (final y in years)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            strings.yearSummaryLine(
                              y.year,
                              y.salesCount,
                              y.stockInsCount,
                            ),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (y.unpaidSalesCount > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              strings.unpaidDebtsKeptNote(y.unpaidSalesCount),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _exportYear(y.year, compress: false),
                            icon: const Icon(Icons.download_outlined, size: 18),
                            label: Text(strings.exportArchiveOnlyBtn),
                          ),
                          const SizedBox(height: 6),
                          FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _exportYear(y.year, compress: true),
                            icon: const Icon(Icons.compress, size: 18),
                            label: Text(strings.exportAndCompressYearBtn),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (_status != null) ...[
                const SizedBox(height: 8),
                Text(
                  _status!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(strings.close),
        ),
      ],
    );
  }
}

class _TableImportSheet extends StatefulWidget {
  const _TableImportSheet({required this.controller});

  final ShopController controller;

  @override
  State<_TableImportSheet> createState() => _TableImportSheetState();
}

class _TableImportSheetState extends State<_TableImportSheet> {
  final TextEditingController _inputController = TextEditingController();
  final GoogleSheetsService _syncService = const GoogleSheetsService();

  SheetSyncPreview? _preview;
  List<CatalogHealthIssue> _healthIssues = const [];
  String? _error;
  bool _includeNew = true;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      setState(() {
        _inputController.text = data!.text!;
        _error = null;
      });
    }
  }

  void _copyTemplate() {
    Clipboard.setData(
      ClipboardData(text: ExportService.buildImportTemplateTsv()),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.controller.strings.copiedTemplateMsg)),
    );
  }

  void _checkImport() {
    final strings = widget.controller.strings;
    final parsed = ExportService.parseTabularProducts(_inputController.text);
    if (parsed.isEmpty) {
      setState(() {
        _preview = null;
        _healthIssues = const [];
        _error = strings.importNoRowsMsg;
      });
      return;
    }

    final preview = _syncService.buildPreview(
      localProducts: widget.controller.products,
      remoteProducts: parsed,
      strings: strings,
      currency: widget.controller.currency,
    );
    final healthIssues = CatalogHealthService.analyze(parsed);
    setState(() {
      _preview = preview;
      _healthIssues = healthIssues;
      _includeNew = true;
      _error = preview.conflicts.isEmpty && preview.onlyInSheet.isEmpty
          ? strings.syncNoDifferencesMsg
          : null;
    });
  }

  Future<void> _applyImport() async {
    final preview = _preview;
    if (preview == null) return;
    final strings = widget.controller.strings;

    final updated = <Product>[];
    for (final c in preview.conflicts) {
      if (c.resolution == ConflictResolution.useSheet) {
        updated.add(c.remoteProduct);
      }
    }
    final added = _includeNew ? preview.onlyInSheet : const <Product>[];

    await widget.controller.applySyncedProducts(
      updatedProducts: updated,
      newProducts: added,
    );

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.importCompletedMsg(updated.length, added.length),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final preview = _preview;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.importFromTableBtn,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  TextField(
                    controller: _inputController,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: strings.pasteTableHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste, size: 18),
                        label: const Text('Вставить'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _copyTemplate,
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: Text(strings.copyImportTemplateBtn),
                      ),
                      FilledButton.icon(
                        onPressed: _checkImport,
                        icon: const Icon(Icons.search, size: 18),
                        label: Text(strings.checkImportBtn),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                  if (_healthIssues.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Card(
                      margin: EdgeInsets.zero,
                      color: theme.colorScheme.errorContainer
                          .withValues(alpha: 0.55),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.importHealthWarningTitle(
                                _healthIssues.length,
                              ),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (final issue in _healthIssues.take(8))
                              Text(
                                '• ${issue.product.name}: ${switch (issue.type) { CatalogHealthIssueType.emptyName => strings.healthEmptyName, CatalogHealthIssueType.zeroPrice => strings.healthZeroPrice, CatalogHealthIssueType.sellBelowCost => strings.healthSellBelowCost, CatalogHealthIssueType.duplicateBarcode => '${strings.healthDuplicateBarcode} (${issue.detail})', CatalogHealthIssueType.negativeStock => '${strings.healthNegativeStock} (${issue.detail})' }}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (preview != null &&
                      (preview.conflicts.isNotEmpty ||
                          preview.onlyInSheet.isNotEmpty)) ...[
                    const SizedBox(height: 12),
                    if (preview.conflicts.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        children: [
                          Chip(
                            backgroundColor: theme.colorScheme.errorContainer,
                            label: Text(
                              strings.syncConflictsCount(
                                preview.conflicts.length,
                              ),
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          ActionChip(
                            label: Text(strings.allFromSheetBtn),
                            onPressed: () => setState(() {
                              for (final c in preview.conflicts) {
                                c.resolution = ConflictResolution.useSheet;
                              }
                            }),
                          ),
                          ActionChip(
                            label: Text(strings.allFromPhoneBtn),
                            onPressed: () => setState(() {
                              for (final c in preview.conflicts) {
                                c.resolution = ConflictResolution.keepLocal;
                              }
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final conflict in preview.conflicts)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  conflict.localProduct.name,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                for (final diff in conflict.diffs)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '${diff.fieldLabel}: ${diff.localValue} → ${diff.remoteValue}'
                                      '${diff.deltaLabel != null ? ' (${diff.deltaLabel})' : ''}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    ChoiceChip(
                                      label: Text(strings.useSheetValueBtn),
                                      selected: conflict.resolution ==
                                          ConflictResolution.useSheet,
                                      onSelected: (_) => setState(
                                        () => conflict.resolution =
                                            ConflictResolution.useSheet,
                                      ),
                                    ),
                                    ChoiceChip(
                                      label: Text(strings.keepPhoneValueBtn),
                                      selected: conflict.resolution ==
                                          ConflictResolution.keepLocal,
                                      onSelected: (_) => setState(
                                        () => conflict.resolution =
                                            ConflictResolution.keepLocal,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    if (preview.onlyInSheet.isNotEmpty)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _includeNew,
                        onChanged: (v) =>
                            setState(() => _includeNew = v ?? true),
                        title: Text(
                          strings.syncNewFromSheetCount(
                            preview.onlyInSheet.length,
                          ),
                        ),
                        subtitle: Text(
                          preview.onlyInSheet
                              .take(3)
                              .map(
                                (p) =>
                                    '${p.name} (${formatMoney(p.sellPrice, currency)}, ${p.stock})',
                              )
                              .join('\n'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _applyImport,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(strings.applySyncBtn),
                    ),
                  ],
                ],
              ),
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

class GoogleSheetsSheet extends StatefulWidget {
  const GoogleSheetsSheet({
    super.key,
    required this.controller,
    this.initiallyExpandManualBackup = false,
  });

  final ShopController controller;
  final bool initiallyExpandManualBackup;

  @override
  State<GoogleSheetsSheet> createState() => _GoogleSheetsSheetState();
}

class _GoogleSheetsSheetState extends State<GoogleSheetsSheet> {
  final GoogleSheetsService _service = const GoogleSheetsService();
  late final TextEditingController _urlController;
  late final TextEditingController _secretController;
  late final Map<SheetExportSection, TextEditingController>
      _sectionTabControllers;

  bool _busy = false;
  String? _error;
  String? _statusMessage;
  String? _progressText;
  SheetSyncPreview? _preview;
  bool _includeNewFromSheet = true;
  bool _includeNewOnPhone = true;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: widget.controller.googleSheetsUrl,
    );
    _secretController = TextEditingController(
      text: widget.controller.googleSheetsSecret,
    );
    final strings = widget.controller.strings;
    _sectionTabControllers = {
      for (final section in SheetExportSection.values)
        section: TextEditingController(
          text: SheetExportHelper.defaultTabName(section, strings),
        ),
    };
  }

  @override
  void dispose() {
    _urlController.dispose();
    _secretController.dispose();
    for (final ctrl in _sectionTabControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _saveConfig() async {
    await widget.controller.setGoogleSheetsConfig(
      url: _urlController.text,
      secret: _secretController.text,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.strings.savedMsg)),
      );
    }
  }

  Future<void> _copyScript() async {
    await Clipboard.setData(
      const ClipboardData(text: GoogleSheetsService.appsScriptTemplate),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.strings.copiedToClipboardMsg)),
      );
    }
  }

  Future<void> _checkAndCompare() async {
    final strings = widget.controller.strings;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = strings.enterSheetsUrlMsg);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      await widget.controller.setGoogleSheetsConfig(
        url: url,
        secret: _secretController.text,
      );
      final remoteProducts = await _service.fetchProducts(
        url,
        secret: _secretController.text,
      );
      final preview = _service.buildPreview(
        localProducts: widget.controller.products,
        remoteProducts: remoteProducts,
        strings: strings,
        currency: widget.controller.currency,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _includeNewFromSheet = true;
        _includeNewOnPhone = true;
        if (!preview.hasChanges && preview.localDuplicates.isEmpty) {
          _statusMessage = strings.syncNoDifferencesMsg;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pushAllToSheet({
    bool allowShrinkOverride = false,
    bool allowTimestampOverride = false,
  }) async {
    final strings = widget.controller.strings;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = strings.enterSheetsUrlMsg);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _statusMessage = null;
      _progressText = '0 / ${widget.controller.products.length}';
    });

    try {
      await widget.controller.setGoogleSheetsConfig(
        url: url,
        secret: _secretController.text,
      );
      if (!allowShrinkOverride && !widget.controller.isBulkDeleteAuthorized) {
        final localAnomaly =
            widget.controller.detectCloudBackupShrinkAnomaly();
        if (localAnomaly != null) {
          throw localAnomaly;
        }
        if (widget.controller.lastCloudBackupProductsCount < 0 ||
            widget.controller.products.length <= 3) {
          final remoteProducts = await _service.fetchProducts(
            url,
            secret: _secretController.text,
          );
          final remoteAnomaly =
              widget.controller.detectRemoteCatalogShrinkAnomaly(
            GoogleSheetsService.deduplicateProducts(remoteProducts).length,
          );
          if (remoteAnomaly != null) {
            throw remoteAnomaly;
          }
        }
      }
      if (!allowTimestampOverride) {
        final meta = await _service.fetchCloudBackupMeta(
          url,
          secret: _secretController.text,
        );
        final tsConflict = widget.controller.detectCloudNewerThanLocal(
          remoteBackupUpdatedAt: meta.updatedAt,
          remoteCatalogUpdatedAt: meta.catalogUpdatedAt,
        );
        if (tsConflict != null) {
          throw tsConflict;
        }
      }
      final pushedCount = await _service.pushProducts(
        url,
        widget.controller.products,
        secret: _secretController.text,
        onProgress: (sent, total) {
          if (mounted) {
            setState(() => _progressText = '$sent / $total');
          }
        },
      );
      await widget.controller.markCloudCatalogPushed();
      if (!mounted) return;
      setState(() {
        _preview = null;
        _progressText = null;
        _statusMessage = '${strings.syncCompletedMsg} ($pushedCount)';
      });
    } on CloudBackupShrinkException catch (e) {
      if (!mounted) return;
      setState(() {
        _progressText = null;
        _error = '$e';
      });
      final retry = await _confirmShrinkOverride(e);
      if (retry && mounted) {
        await _pushAllToSheet(
          allowShrinkOverride: true,
          allowTimestampOverride: allowTimestampOverride,
        );
      }
    } on CloudTimestampConflictException catch (e) {
      if (!mounted) return;
      setState(() {
        _progressText = null;
        _error = '$e';
      });
      final retry = await _confirmTimestampOverride(e);
      if (retry && mounted) {
        await _pushAllToSheet(
          allowShrinkOverride: allowShrinkOverride,
          allowTimestampOverride: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _progressText = null;
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _applySync() async {
    final preview = _preview;
    if (preview == null) return;
    final strings = widget.controller.strings;
    final url = _urlController.text.trim();

    setState(() {
      _busy = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      final updatedProducts = <Product>[];
      for (final conflict in preview.conflicts) {
        if (conflict.resolution == ConflictResolution.useSheet) {
          updatedProducts.add(conflict.remoteProduct);
        }
      }
      final newProducts = _includeNewFromSheet
          ? preview.onlyInSheet
          : const <Product>[];

      if (updatedProducts.isNotEmpty || newProducts.isNotEmpty) {
        await widget.controller.applySyncedProducts(
          updatedProducts: updatedProducts,
          newProducts: newProducts,
        );
      }

      final toPush = _includeNewOnPhone
          ? widget.controller.products
          : widget.controller.products
              .where(
                (p) => !preview.onlyOnPhone.any((only) => only.id == p.id),
              )
              .toList();

      final pushedCount = await _service.pushProducts(
        url,
        toPush,
        secret: _secretController.text,
      );
      widget.controller.recordSheetCatalogBaseline();

      if (!mounted) return;
      setState(() {
        _preview = null;
        _statusMessage = '${strings.syncCompletedMsg} ($pushedCount)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _setAllConflicts(ConflictResolution resolution) {
    final preview = _preview;
    if (preview == null) return;
    setState(() {
      for (final c in preview.conflicts) {
        c.resolution = resolution;
      }
    });
  }

  Future<void> _copySectionTsv(SheetExportSection section) async {
    final tsv = SheetExportHelper.buildTsv(section, widget.controller);
    await Clipboard.setData(ClipboardData(text: tsv));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.strings.copiedForSheetsMsg)),
      );
    }
  }

  Future<void> _pushSectionToSheet(SheetExportSection section) async {
    final strings = widget.controller.strings;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = strings.enterSheetsUrlMsg);
      return;
    }
    final tabCtrl = _sectionTabControllers[section]!;
    final sheetName = tabCtrl.text.trim().isEmpty
        ? SheetExportHelper.defaultTabName(section, strings)
        : tabCtrl.text.trim();
    final table = SheetExportHelper.buildTable(section, widget.controller);

    setState(() {
      _busy = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      await widget.controller.setGoogleSheetsConfig(
        url: url,
        secret: _secretController.text,
      );
      final pushed = await _service.pushTable(
        webAppUrl: url,
        sheetName: sheetName,
        headers: table.headers,
        rows: table.rows,
        secret: _secretController.text,
      );
      if (!mounted) return;
      final msg = strings.sectionUploadedMsg(sheetName, pushed);
      setState(() {
        _statusMessage = msg;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pushAllSectionsToSheets() async {
    final strings = widget.controller.strings;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = strings.enterSheetsUrlMsg);
      return;
    }

    const sections = SheetExportSection.values;
    setState(() {
      _busy = true;
      _error = null;
      _statusMessage = null;
      _progressText = '0 / ${sections.length}';
    });

    try {
      await widget.controller.setGoogleSheetsConfig(
        url: url,
        secret: _secretController.text,
      );
      var done = 0;
      const maxParallel = 4;
      for (var i = 0; i < sections.length; i += maxParallel) {
        final end = (i + maxParallel < sections.length)
            ? i + maxParallel
            : sections.length;
        final batch = sections.sublist(i, end);
        await Future.wait(batch.map((section) async {
          final tabCtrl = _sectionTabControllers[section]!;
          final sheetName = tabCtrl.text.trim().isEmpty
              ? SheetExportHelper.defaultTabName(section, strings)
              : tabCtrl.text.trim();
          final table = SheetExportHelper.buildTable(section, widget.controller);
          await _service.pushTable(
            webAppUrl: url,
            sheetName: sheetName,
            headers: table.headers,
            rows: table.rows,
            secret: _secretController.text,
          );
          done += 1;
          if (mounted) {
            setState(() {
              _progressText = '$done / ${sections.length}: $sheetName';
            });
          }
        }));
      }
      if (!mounted) return;
      setState(() {
        _progressText = null;
        _statusMessage = strings.allSectionsUploadedMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.allSectionsUploadedMsg)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _progressText = null;
        _error = '$e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progressText = null;
        });
      }
    }
  }

  Future<bool> _confirmShrinkOverride(CloudBackupShrinkException e) async {
    final strings = widget.controller.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(ctx).colorScheme.error,
        ),
        title: Text(strings.cloudBackupShrinkWarningTitle),
        content: Text(e.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.cloudBackupOverrideBtn),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<bool> _confirmTimestampOverride(
    CloudTimestampConflictException e,
  ) async {
    final strings = widget.controller.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.schedule_send_outlined,
          color: Theme.of(ctx).colorScheme.error,
        ),
        title: Text(
          e.isCloudNewer
              ? strings.cloudNewerWarningTitle
              : strings.localNewerWarningTitle,
        ),
        content: Text(e.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              e.isCloudNewer
                  ? strings.overwriteCloudAnywayBtn
                  : strings.restoreOlderCloudAnywayBtn,
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _pushCatalogAndAllSections({
    bool allowShrinkOverride = false,
    bool allowTimestampOverride = false,
  }) async {
    final strings = widget.controller.strings;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = strings.enterSheetsUrlMsg);
      return;
    }

    const sections = SheetExportSection.values;
    setState(() {
      _busy = true;
      _error = null;
      _statusMessage = null;
      _progressText = 'Catalog: 0 / ${widget.controller.products.length}';
    });

    try {
      await widget.controller.setGoogleSheetsConfig(
        url: url,
        secret: _secretController.text,
      );
      final totalSteps = sections.length + 2;
      var doneSteps = 0;
      // Validate & upload _Backup first so Catalog and section tabs are never
      // overwritten if shrink / empty-over-populated / timestamp protection triggers.
      await widget.controller.syncCloudBackupDelta(
        forceFull: true,
        syncReadableSheets: false,
        allowShrinkOverride: allowShrinkOverride,
        allowTimestampOverride: allowTimestampOverride,
      );
      doneSteps += 1;
      if (mounted) {
        setState(() => _progressText = '$doneSteps / $totalSteps: Backup');
      }
      final tasks = <Future<void> Function()>[
        () async {
          await _service.pushProducts(
            url,
            widget.controller.products,
            secret: _secretController.text,
          );
          doneSteps += 1;
          if (mounted) {
            setState(() => _progressText = '$doneSteps / $totalSteps: Catalog');
          }
        },
        for (final section in sections)
          () async {
            final tabCtrl = _sectionTabControllers[section]!;
            final sheetName = tabCtrl.text.trim().isEmpty
                ? SheetExportHelper.defaultTabName(section, strings)
                : tabCtrl.text.trim();
            final table =
                SheetExportHelper.buildTable(section, widget.controller);
            await _service.pushTable(
              webAppUrl: url,
              sheetName: sheetName,
              headers: table.headers,
              rows: table.rows,
              secret: _secretController.text,
            );
            doneSteps += 1;
            if (mounted) {
              setState(
                () => _progressText = '$doneSteps / $totalSteps: $sheetName',
              );
            }
          },
      ];
      const maxParallel = 4;
      for (var i = 0; i < tasks.length; i += maxParallel) {
        final end =
            (i + maxParallel < tasks.length) ? i + maxParallel : tasks.length;
        await Future.wait(tasks.sublist(i, end).map((t) => t()));
      }
      if (!mounted) return;
      setState(() {
        _preview = null;
        _progressText = null;
        _statusMessage = strings.allCatalogAndSectionsSyncedMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.allCatalogAndSectionsSyncedMsg)),
      );
    } on CloudBackupShrinkException catch (e) {
      if (!mounted) return;
      setState(() {
        _progressText = null;
        _error = '$e';
      });
      final retry = await _confirmShrinkOverride(e);
      if (retry && mounted) {
        await _pushCatalogAndAllSections(
          allowShrinkOverride: true,
          allowTimestampOverride: allowTimestampOverride,
        );
      }
    } on CloudTimestampConflictException catch (e) {
      if (!mounted) return;
      setState(() {
        _progressText = null;
        _error = '$e';
      });
      final retry = await _confirmTimestampOverride(e);
      if (retry && mounted) {
        await _pushCatalogAndAllSections(
          allowShrinkOverride: allowShrinkOverride,
          allowTimestampOverride: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _progressText = null;
        _error = '$e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progressText = null;
        });
      }
    }
  }

  Future<void> _restoreAllFromSheets({bool usePrevious = false}) async {
    final strings = widget.controller.strings;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = strings.enterSheetsUrlMsg);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      await widget.controller.setGoogleSheetsConfig(
        url: url,
        secret: _secretController.text,
      );
      final res = await _service.fetchCloudBackup(
        url,
        secret: _secretController.text,
        usePreviousBackup: usePrevious,
      );
      if (!mounted) return;
      if (res.snapshot == null) {
        final emptyMsg = usePrevious
            ? strings.noPrevCloudBackupMsg
            : strings.noCloudBackupMsg;
        setState(() => _error = emptyMsg);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(emptyMsg)),
        );
        return;
      }

      final remoteDate = DateTime.tryParse((res.updatedAt ?? '').trim());
      final localNewerConflict = widget.controller.detectLocalNewerThanCloud(
        remoteBackupUpdatedAt: remoteDate,
      );
      if (localNewerConflict != null) {
        final proceed = await _confirmTimestampOverride(localNewerConflict);
        if (!proceed || !mounted) return;
      }

      String? prettyDate = res.updatedAt;
      if (prettyDate != null && prettyDate.isNotEmpty && remoteDate != null) {
        prettyDate = formatDateTime(remoteDate);
      }

      final includeSettings = await showDialog<bool>(
        context: context,
        builder: (_) => _RestoreScopeDialog(
          strings: strings,
          title: strings.restoreAllConfirmTitle,
          description: strings.restoreAllConfirmBody(prettyDate),
        ),
      );
      if (includeSettings == null || !mounted) return;

      await widget.controller.restoreFromSnapshot(
        res.snapshot!,
        includeSettings: includeSettings,
      );
      if (!mounted) return;
      final doneMsg =
          '${strings.backupRestoredMsg}. ${strings.preRestoreBackupSavedNote}';
      setState(() {
        _preview = null;
        _statusMessage = doneMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(doneMsg)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final currency = widget.controller.currency;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final preview = _preview;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.syncAndBackupTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: strings.close,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_sync_outlined,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.autoSyncGoogleSheetsSection,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: strings.sheetsWebAppUrlLabel,
                      hintText: 'https://...',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _secretController,
                    decoration: InputDecoration(
                      labelText: strings.sheetsSecretLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _saveConfig,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: Text(strings.saveChanges),
                      ),
                      OutlinedButton.icon(
                        onPressed: _copyScript,
                        icon: const Icon(Icons.code, size: 18),
                        label: Text(strings.copyAppsScriptBtn),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _checkAndCompare,
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.sync),
                          label: Text(
                            strings.checkAndSyncBtn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _busy ? null : _pushAllToSheet,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: Text(
                            _progressText != null
                                ? _progressText!
                                : strings.pushAllToSheetsBtn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _pushCatalogAndAllSections,
                    icon: const Icon(Icons.sync_alt),
                    label: Text(
                      _progressText != null
                          ? _progressText!
                          : strings.syncAllCatalogAndSectionsBtn,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _restoreAllFromSheets(),
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: Text(strings.restoreAllFromSheetsBtn),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _restoreAllFromSheets(usePrevious: true),
                    icon: const Icon(Icons.history, size: 18),
                    label: Text(strings.restorePrevFromSheetsBtn),
                  ),
                  if (widget.controller.hasPreRestoreBackup)
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final ok = await confirmAndRollbackRestore(
                                context,
                                widget.controller,
                              );
                              if (ok && mounted) {
                                setState(() {
                                  _preview = null;
                                  _error = null;
                                  _statusMessage = strings.rollbackRestoredMsg;
                                });
                              }
                            },
                      icon: const Icon(Icons.undo, size: 18),
                      label: Text(strings.rollbackLastRestoreBtn),
                    ),
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) {
                      final lastRaw = widget.controller.lastAutoBackupAt;
                      final lastErr = widget.controller.lastAutoBackupError;
                      final inProgress = widget.controller.autoBackupInProgress;
                      final pending = widget.controller.pendingSync;
                      String subtitle = strings.autoBackupHint;
                      if (inProgress) {
                        subtitle = '${strings.autoBackupHint}\nОтправка изменений...';
                      } else if (pending) {
                        subtitle =
                            '${strings.autoBackupHint}\n${strings.pendingSyncStatus}';
                      } else if (lastRaw.isNotEmpty) {
                        final dt = DateTime.tryParse(lastRaw);
                        if (dt != null) {
                          subtitle =
                              '${strings.autoBackupHint}\n${strings.lastAutoBackupStatus(formatDateTime(dt))}';
                        }
                      }
                      return Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: lastErr.isNotEmpty
                                ? theme.colorScheme.error
                                : theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SwitchListTile(
                              dense: true,
                              secondary: inProgress
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.cloud_done_outlined),
                              title: Text(strings.autoBackupLabel),
                              subtitle: Text(subtitle),
                              value: widget.controller.autoBackupEnabled,
                              onChanged: (v) =>
                                  widget.controller.setAutoBackupEnabled(v),
                            ),
                            if (lastErr.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Text(
                                  'Ошибка автобэкапа: $lastErr',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                              child: OutlinedButton.icon(
                                onPressed: (_busy || inProgress)
                                    ? null
                                    : () async {
                                        final url = _urlController.text.trim();
                                        if (url.isEmpty) {
                                          setState(() => _error =
                                              strings.enterSheetsUrlMsg);
                                          return;
                                        }
                                        setState(() {
                                          _busy = true;
                                          _error = null;
                                          _statusMessage = null;
                                        });
                                        try {
                                          await widget.controller
                                              .setGoogleSheetsConfig(
                                            url: url,
                                            secret: _secretController.text,
                                          );
                                          final sent = await widget.controller
                                              .syncCloudBackupDelta(
                                            forceFull: false,
                                          );
                                          if (!context.mounted) return;
                                          final msg = sent > 0
                                              ? 'Автобэкап выполнен (обновлено блоков: $sent)'
                                              : 'Все изменения уже сохранены в _Backup';
                                          setState(() => _statusMessage = msg);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(content: Text(msg)),
                                          );
                                        } on CloudBackupShrinkException catch (e) {
                                          if (!context.mounted) return;
                                          setState(() => _error = '$e');
                                          final retry =
                                              await _confirmShrinkOverride(e);
                                          if (retry && context.mounted) {
                                            final sent = await widget.controller
                                                .syncCloudBackupDelta(
                                              forceFull: false,
                                              allowShrinkOverride: true,
                                            );
                                            if (!context.mounted) return;
                                            final msg = sent > 0
                                                ? 'Автобэкап выполнен (обновлено блоков: $sent)'
                                                : 'Все изменения уже сохранены в _Backup';
                                            setState(() {
                                              _error = null;
                                              _statusMessage = msg;
                                            });
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(content: Text(msg)),
                                            );
                                          }
                                        } on CloudTimestampConflictException catch (e) {
                                          if (!context.mounted) return;
                                          setState(() => _error = '$e');
                                          final retry =
                                              await _confirmTimestampOverride(
                                            e,
                                          );
                                          if (retry && context.mounted) {
                                            final sent = await widget.controller
                                                .syncCloudBackupDelta(
                                              forceFull: false,
                                              allowTimestampOverride: true,
                                            );
                                            if (!context.mounted) return;
                                            final msg = sent > 0
                                                ? 'Автобэкап выполнен (обновлено блоков: $sent)'
                                                : 'Все изменения уже сохранены в _Backup';
                                            setState(() {
                                              _error = null;
                                              _statusMessage = msg;
                                            });
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(content: Text(msg)),
                                            );
                                          }
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          setState(() => _error = '$e');
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(content: Text('$e')),
                                          );
                                        } finally {
                                          if (mounted) {
                                            setState(() => _busy = false);
                                          }
                                        }
                                      },
                                icon: const Icon(Icons.backup_outlined, size: 18),
                                label: const Text('Проверить / отправить бэкап сейчас'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      dense: true,
                      leading: const Icon(Icons.tab_outlined, size: 20),
                      title: Text(
                        strings.exportSectionsHeader,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _pushAllSectionsToSheets,
                          icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                          label: Text(
                            _progressText != null
                                ? _progressText!
                                : strings.uploadAllSectionsBtn,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final section in SheetExportSection.values)
                          Builder(
                            builder: (_) {
                              final table = SheetExportHelper.buildTable(
                                section,
                                widget.controller,
                              );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '${SheetExportHelper.sectionTitle(section, strings)} (${table.rows.length})',
                                      style: theme.textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller:
                                                _sectionTabControllers[section],
                                            decoration: InputDecoration(
                                              labelText:
                                                  strings.sheetTabNameLabel,
                                              border:
                                                  const OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        IconButton.outlined(
                                          tooltip: strings.copyTsvShortBtn,
                                          onPressed: () =>
                                              _copySectionTsv(section),
                                          icon: const Icon(
                                            Icons.content_copy,
                                            size: 18,
                                          ),
                                        ),
                                        FilledButton.tonal(
                                          onPressed: _busy
                                              ? null
                                              : () =>
                                                  _pushSectionToSheet(section),
                                          child: Text(strings.uploadToSheetBtn),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  if (preview != null &&
                      (preview.hasChanges ||
                          preview.localDuplicates.isNotEmpty)) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (preview.sheetDuplicates.isNotEmpty)
                          Chip(
                            avatar: Icon(
                              Icons.content_copy_rounded,
                              size: 18,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            backgroundColor: theme.colorScheme.errorContainer,
                            label: Text(
                              strings.sheetDuplicatesCount(
                                preview.sheetDuplicates.length,
                              ),
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (preview.localDuplicates.isNotEmpty)
                          Chip(
                            avatar: Icon(
                              Icons.phone_android,
                              size: 18,
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                            backgroundColor:
                                theme.colorScheme.tertiaryContainer,
                            label: Text(
                              strings.phoneDuplicatesCount(
                                preview.localDuplicates.length,
                              ),
                              style: TextStyle(
                                color: theme.colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (preview.conflicts.isNotEmpty)
                          Chip(
                            avatar: const Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                            ),
                            backgroundColor: theme.colorScheme.errorContainer,
                            label: Text(
                              strings.syncConflictsCount(
                                preview.conflicts.length,
                              ),
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (preview.onlyInSheet.isNotEmpty)
                          Chip(
                            label: Text(
                              strings.syncNewFromSheetCount(
                                preview.onlyInSheet.length,
                              ),
                            ),
                          ),
                        if (preview.onlyOnPhone.isNotEmpty)
                          Chip(
                            label: Text(
                              strings.syncNewOnPhoneCount(
                                preview.onlyOnPhone.length,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (preview.sheetDuplicates.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: theme.colorScheme.errorContainer
                            .withValues(alpha: 0.45),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.sheetDuplicatesCount(
                                  preview.sheetDuplicates.length,
                                ),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                strings.sheetDuplicatesCleanedNote,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final dup in preview.sheetDuplicates)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '• ${dup.product.name} (${strings.rowNumberLabel(dup.rowNumber)} = ${strings.rowNumberLabel(dup.firstRowNumber)}, ${dup.reason})',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (preview.localDuplicates.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: theme.colorScheme.tertiaryContainer
                            .withValues(alpha: 0.45),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.phoneDuplicatesCount(
                                  preview.localDuplicates.length,
                                ),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final group in preview.localDuplicates) ...[
                                Text(
                                  group.reason,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                for (final p in group.products)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '• ${p.name} (${formatMoney(p.sellPrice, currency)}, ${strings.stockCountLabel(p.stock)})',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: strings.moveToTrashAction,
                                        visualDensity: VisualDensity.compact,
                                        icon: Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                          color: theme.colorScheme.error,
                                        ),
                                        onPressed: _busy
                                            ? null
                                            : () async {
                                                await widget.controller
                                                    .moveProductToTrash(p.id);
                                                if (mounted) {
                                                  await _checkAndCompare();
                                                }
                                              },
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 6),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (preview.conflicts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            label: Text(strings.allFromSheetBtn),
                            onPressed: () =>
                                _setAllConflicts(ConflictResolution.useSheet),
                          ),
                          ActionChip(
                            label: Text(strings.allFromPhoneBtn),
                            onPressed: () =>
                                _setAllConflicts(ConflictResolution.keepLocal),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final conflict in preview.conflicts)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  conflict.localProduct.name,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                for (final diff in conflict.diffs)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                diff.fieldLabel,
                                                style: theme
                                                    .textTheme.labelMedium
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                '${strings.phoneLabel}: ${diff.localValue}  →  ${strings.sheetLabel}: ${diff.remoteValue}',
                                                style:
                                                    theme.textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (diff.deltaLabel != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme
                                                  .secondaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              diff.deltaLabel!,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: theme.colorScheme
                                                    .onSecondaryContainer,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    ChoiceChip(
                                      label: Text(strings.useSheetValueBtn),
                                      selected: conflict.resolution ==
                                          ConflictResolution.useSheet,
                                      onSelected: (_) => setState(
                                        () => conflict.resolution =
                                            ConflictResolution.useSheet,
                                      ),
                                    ),
                                    ChoiceChip(
                                      label: Text(strings.keepPhoneValueBtn),
                                      selected: conflict.resolution ==
                                          ConflictResolution.keepLocal,
                                      onSelected: (_) => setState(
                                        () => conflict.resolution =
                                            ConflictResolution.keepLocal,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    if (preview.onlyInSheet.isNotEmpty) ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _includeNewFromSheet,
                        onChanged: (v) => setState(
                          () => _includeNewFromSheet = v ?? true,
                        ),
                        title: Text(
                          strings.syncNewFromSheetCount(
                            preview.onlyInSheet.length,
                          ),
                        ),
                        subtitle: Text(
                          preview.onlyInSheet
                              .take(3)
                              .map(
                                (p) =>
                                    '${p.name} (${formatMoney(p.sellPrice, currency)}, ${p.stock})',
                              )
                              .join('\n'),
                        ),
                      ),
                    ],
                    if (preview.onlyOnPhone.isNotEmpty) ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _includeNewOnPhone,
                        onChanged: (v) => setState(
                          () => _includeNewOnPhone = v ?? true,
                        ),
                        title: Text(
                          strings.syncNewOnPhoneCount(
                            preview.onlyOnPhone.length,
                          ),
                        ),
                        subtitle: Text(
                          preview.onlyOnPhone
                              .take(3)
                              .map(
                                (p) =>
                                    '${p.name} (${formatMoney(p.sellPrice, currency)}, ${p.stock})',
                              )
                              .join('\n'),
                        ),
                      ),
                    ],
                    if (preview.hasChanges) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _busy ? null : _applySync,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(strings.applySyncBtn),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      initiallyExpanded: widget.initiallyExpandManualBackup,
                      leading: const Icon(Icons.import_export, size: 22),
                      title: Text(
                        strings.manualBackupExportSection,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        strings.manualBackupExportSubtitle,
                        style: theme.textTheme.bodySmall,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      children: [
                        _ManualBackupExportSection(controller: widget.controller),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestoreScopeDialog extends StatefulWidget {
  const _RestoreScopeDialog({
    required this.strings,
    required this.title,
    this.description,
  });

  final AppStrings strings;
  final String title;
  final String? description;

  @override
  State<_RestoreScopeDialog> createState() => _RestoreScopeDialogState();
}

class _RestoreScopeDialogState extends State<_RestoreScopeDialog> {
  bool _includeSettings = false;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.description != null && widget.description!.isNotEmpty) ...[
              Text(widget.description!),
              const SizedBox(height: 12),
            ],
            RadioGroup<bool>(
              groupValue: _includeSettings,
              onChanged: (v) {
                if (v != null) setState(() => _includeSettings = v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: Text(strings.restoreDataOnlyOption),
                    subtitle: Text(strings.restoreDataOnlyHint),
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    title: Text(strings.restoreAllWithSettingsOption),
                    subtitle: Text(strings.restoreAllWithSettingsHint),
                  ),
                ],
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
          onPressed: () => Navigator.of(context).pop(_includeSettings),
          child: Text(strings.confirm),
        ),
      ],
    );
  }
}
