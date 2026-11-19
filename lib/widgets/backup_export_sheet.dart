import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product.dart';
import '../services/export_service.dart';
import '../services/google_sheets_service.dart';
import '../services/sheet_export_helper.dart';
import '../state/shop_controller.dart';
import 'formatters.dart';

class BackupExportSheet extends StatelessWidget {
  const BackupExportSheet({super.key, required this.controller});

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
    setState(() {
      _preview = preview;
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
  const GoogleSheetsSheet({super.key, required this.controller});

  final ShopController controller;

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
        if (!preview.hasChanges) {
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

  Future<void> _pushAllToSheet() async {
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
      if (!mounted) return;
      setState(() {
        _preview = null;
        _progressText = null;
        _statusMessage = '${strings.syncCompletedMsg} ($pushedCount)';
      });
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
      for (var i = 0; i < sections.length; i++) {
        final section = sections[i];
        final tabCtrl = _sectionTabControllers[section]!;
        final sheetName = tabCtrl.text.trim().isEmpty
            ? SheetExportHelper.defaultTabName(section, strings)
            : tabCtrl.text.trim();
        if (mounted) {
          setState(() {
            _progressText = '${i + 1} / ${sections.length}: $sheetName';
          });
        }
        final table = SheetExportHelper.buildTable(section, widget.controller);
        await _service.pushTable(
          webAppUrl: url,
          sheetName: sheetName,
          headers: table.headers,
          rows: table.rows,
          secret: _secretController.text,
        );
        if (i < sections.length - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
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

  Future<void> _pushCatalogAndAllSections() async {
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
      await _service.pushProducts(
        url,
        widget.controller.products,
        secret: _secretController.text,
        onProgress: (sent, total) {
          if (mounted) {
            setState(() => _progressText = 'Catalog: $sent / $total');
          }
        },
      );
      for (var i = 0; i < sections.length; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final section = sections[i];
        final tabCtrl = _sectionTabControllers[section]!;
        final sheetName = tabCtrl.text.trim().isEmpty
            ? SheetExportHelper.defaultTabName(section, strings)
            : tabCtrl.text.trim();
        if (mounted) {
          setState(() {
            _progressText = '${i + 1} / ${sections.length}: $sheetName';
          });
        }
        final table = SheetExportHelper.buildTable(section, widget.controller);
        await _service.pushTable(
          webAppUrl: url,
          sheetName: sheetName,
          headers: table.headers,
          rows: table.rows,
          secret: _secretController.text,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) {
        setState(() => _progressText = 'Backup...');
      }
      await widget.controller.syncCloudBackupDelta(
        forceFull: true,
        syncReadableSheets: false,
      );
      if (!mounted) return;
      setState(() {
        _preview = null;
        _progressText = null;
        _statusMessage = strings.allCatalogAndSectionsSyncedMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.allCatalogAndSectionsSyncedMsg)),
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

  Future<void> _restoreAllFromSheets() async {
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
      );
      if (!mounted) return;
      if (res.snapshot == null) {
        setState(() => _error = strings.noCloudBackupMsg);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.noCloudBackupMsg)),
        );
        return;
      }

      String? prettyDate = res.updatedAt;
      if (prettyDate != null && prettyDate.isNotEmpty) {
        final parsed = DateTime.tryParse(prettyDate);
        if (parsed != null) {
          prettyDate = formatDateTime(parsed);
        }
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.restoreAllConfirmTitle),
          content: Text(strings.restoreAllConfirmBody(prettyDate)),
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
      if (confirmed != true || !mounted) return;

      await widget.controller.restoreFromSnapshot(res.snapshot!);
      if (!mounted) return;
      setState(() {
        _preview = null;
        _statusMessage = strings.backupRestoredMsg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.backupRestoredMsg)),
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
                    strings.googleSheetsBtn,
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
                          label: Text(strings.checkAndSyncBtn),
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
                    onPressed: _busy ? null : _restoreAllFromSheets,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: Text(strings.restoreAllFromSheetsBtn),
                  ),
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) {
                      final lastRaw = widget.controller.lastAutoBackupAt;
                      final lastErr = widget.controller.lastAutoBackupError;
                      final inProgress = widget.controller.autoBackupInProgress;
                      String subtitle = strings.autoBackupHint;
                      if (inProgress) {
                        subtitle = '${strings.autoBackupHint}\nОтправка изменений...';
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
                                          if (!mounted) return;
                                          final msg = sent > 0
                                              ? 'Автобэкап выполнен (обновлено блоков: $sent)'
                                              : 'Все изменения уже сохранены в _Backup';
                                          setState(() => _statusMessage = msg);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(content: Text(msg)),
                                          );
                                        } catch (e) {
                                          if (!mounted) return;
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
                  if (preview != null && preview.hasChanges) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
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
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _applySync,
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
