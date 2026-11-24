import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product.dart';
import '../state/shop_controller.dart';

String _severityLabel(AdviceSeverity severity, dynamic strings) {
  return switch (severity) {
    AdviceSeverity.urgent => strings.adviceSeverityUrgent as String,
    AdviceSeverity.warning => strings.adviceSeverityWarning as String,
    AdviceSeverity.opportunity => strings.adviceSeverityOpportunity as String,
    AdviceSeverity.info => strings.adviceSeverityInfo as String,
  };
}

String _formatSingleAdviceText(DailyProductAdvice item, dynamic strings) {
  final level = _severityLabel(item.severity, strings);
  return '[$level] ${item.title}\n${item.body}';
}

String _formatAllAdvicesText(
  List<DailyProductAdvice> advices,
  dynamic strings,
) {
  final stamp = DateTime.now().toIso8601String().split('T').first;
  final buf = StringBuffer()
    ..writeln('${strings.dailyAdviceTitle} ($stamp)')
    ..writeln();
  for (var i = 0; i < advices.length; i++) {
    final item = advices[i];
    final level = _severityLabel(item.severity, strings);
    buf.writeln('${i + 1}. [$level] ${item.title}');
    buf.writeln('   ${item.body}');
    if (i < advices.length - 1) buf.writeln();
  }
  return buf.toString().trimRight();
}

Future<void> _copySingleAdvice(
  BuildContext context,
  DailyProductAdvice item,
  dynamic strings,
) async {
  await Clipboard.setData(
    ClipboardData(text: _formatSingleAdviceText(item, strings)),
  );
  HapticFeedback.selectionClick();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(strings.adviceCopiedMsg as String)),
  );
}

Future<void> _shareSingleAdvice(
  DailyProductAdvice item,
  dynamic strings,
) async {
  await Share.share(
    _formatSingleAdviceText(item, strings),
    subject: strings.dailyAdviceBadge as String,
  );
}

Future<void> _shareAllAdvicesText(
  List<DailyProductAdvice> advices,
  dynamic strings,
) async {
  await Share.share(
    _formatAllAdvicesText(advices, strings),
    subject: strings.dailyAdviceTitle as String,
  );
}

Future<void> _exportAllAdvicesFile(
  List<DailyProductAdvice> advices,
  dynamic strings,
) async {
  final text = '\uFEFF${_formatAllAdvicesText(advices, strings)}';
  final stamp = DateTime.now().toIso8601String().split('T').first;
  final bytes = Uint8List.fromList(utf8.encode(text));
  await Share.shareXFiles(
    [
      XFile.fromData(
        bytes,
        name: 'daily_advice_$stamp.txt',
        mimeType: 'text/plain',
      ),
    ],
    subject: strings.dailyAdviceTitle as String,
  );
}

class DailyAdviceBanner extends StatefulWidget {
  const DailyAdviceBanner({
    super.key,
    required this.controller,
    required this.featured,
    required this.totalCount,
    required this.onTapOpenAll,
    required this.onDismissToday,
    this.onDoubleTapNext,
    this.currentIndex,
  });

  final ShopController controller;
  final DailyProductAdvice featured;
  final int totalCount;
  final VoidCallback onTapOpenAll;
  final VoidCallback onDismissToday;
  final VoidCallback? onDoubleTapNext;
  final int? currentIndex;

  @override
  State<DailyAdviceBanner> createState() => _DailyAdviceBannerState();
}

class _DailyAdviceBannerState extends State<DailyAdviceBanner> {
  static const _multiTapWindow = Duration(milliseconds: 420);

  Timer? _singleTapTimer;
  DateTime? _lastMultiTapAt;

  @override
  void dispose() {
    _singleTapTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onDoubleTapNext == null) {
      widget.onTapOpenAll();
      return;
    }

    final now = DateTime.now();

    // If the user is already tapping rapidly (3rd, 4th tap...), keep cycling.
    if (_lastMultiTapAt != null &&
        now.difference(_lastMultiTapAt!) <= _multiTapWindow) {
      _singleTapTimer?.cancel();
      _singleTapTimer = null;
      _lastMultiTapAt = now;
      widget.onDoubleTapNext!.call();
      return;
    }

    // Second tap within the window -> trigger next advice immediately.
    if (_singleTapTimer != null && _singleTapTimer!.isActive) {
      _singleTapTimer!.cancel();
      _singleTapTimer = null;
      _lastMultiTapAt = now;
      widget.onDoubleTapNext!.call();
      return;
    }

    // First tap -> wait briefly to see if a second tap follows.
    _singleTapTimer = Timer(_multiTapWindow, () {
      _singleTapTimer = null;
      if (mounted) {
        widget.onTapOpenAll();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = widget.controller.strings;
    final (bg, fg, icon) = _severityVisuals(widget.featured.severity, theme);
    final extra = widget.totalCount - 1;
    final counterLabel = widget.currentIndex != null && widget.totalCount > 1
        ? '${widget.currentIndex}/${widget.totalCount}'
        : (extra > 0 ? strings.dailyAdviceMoreLabel(extra) : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _handleTap,
          onLongPress: () {
            _singleTapTimer?.cancel();
            _singleTapTimer = null;
            _copySingleAdvice(context, widget.featured, strings);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              strings.dailyAdviceBadge,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (counterLabel != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '• $counterLabel',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: fg.withValues(alpha: 0.85),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        layoutBuilder: (currentChild, previousChildren) => Stack(
                          alignment: Alignment.centerLeft,
                          children: <Widget>[
                            ...previousChildren,
                            ?currentChild,
                          ],
                        ),
                        child: Text(
                          widget.featured.title,
                          key: ValueKey(widget.featured.id),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: strings.shareAdviceBtn,
                  onPressed: () =>
                      _shareSingleAdvice(widget.featured, strings),
                  icon: Icon(Icons.ios_share_outlined, size: 16, color: fg),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: strings.close,
                  onPressed: widget.onDismissToday,
                  icon: Icon(Icons.close, size: 16, color: fg),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DailyAdviceSheet extends StatefulWidget {
  const DailyAdviceSheet({
    super.key,
    required this.controller,
    required this.onAddToStockIn,
    required this.onEditPrice,
    required this.onOpenBarcodeLabel,
    required this.onOpenProduct,
  });

  final ShopController controller;
  final Future<void> Function(Product product) onAddToStockIn;
  final void Function(Product product) onEditPrice;
  final void Function(Product product) onOpenBarcodeLabel;
  final void Function(Product product) onOpenProduct;

  @override
  State<DailyAdviceSheet> createState() => _DailyAdviceSheetState();
}

class _DailyAdviceSheetState extends State<DailyAdviceSheet> {
  static const _doubleTapWindow = Duration(milliseconds: 450);

  final ScrollController _scrollController = ScrollController();
  int _rotationOffset = 0;
  DateTime? _lastCardTapAt;
  String? _lastCardTapId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _cycleAdvice(int count) {
    final strings = widget.controller.strings;
    if (count <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.noOtherAdviceMsg)),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _rotationOffset = (_rotationOffset + 1) % count;
    });
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _handleCardTap(String cardId, int count) {
    final now = DateTime.now();
    if (_lastCardTapId == cardId &&
        _lastCardTapAt != null &&
        now.difference(_lastCardTapAt!) <= _doubleTapWindow) {
      _lastCardTapAt = now;
      _cycleAdvice(count);
      return;
    }
    _lastCardTapId = cardId;
    _lastCardTapAt = now;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        final rawAdvices = widget.controller.dailyProductAdvices();
        final offset =
            rawAdvices.isEmpty ? 0 : _rotationOffset % rawAdvices.length;
        final advices = offset == 0
            ? rawAdvices
            : [
                ...rawAdvices.sublist(offset),
                ...rawAdvices.sublist(0, offset),
              ];

        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.dailyAdviceTitle,
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (advices.length > 1)
                      IconButton(
                        tooltip: strings.nextAdviceBtn,
                        onPressed: () => _cycleAdvice(advices.length),
                        icon: const Icon(Icons.autorenew_rounded),
                      ),
                    if (advices.isNotEmpty)
                      PopupMenuButton<String>(
                        tooltip: strings.exportAllAdvicesBtn,
                        icon: const Icon(Icons.ios_share_outlined),
                        onSelected: (value) async {
                          if (value == 'share_text') {
                            await _shareAllAdvicesText(advices, strings);
                          } else if (value == 'export_file') {
                            await _exportAllAdvicesFile(advices, strings);
                          } else if (value == 'copy_all') {
                            await Clipboard.setData(
                              ClipboardData(
                                text: _formatAllAdvicesText(advices, strings),
                              ),
                            );
                            HapticFeedback.selectionClick();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(strings.copiedToClipboardMsg),
                              ),
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'share_text',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.share_outlined),
                              title: Text(strings.shareAdviceTextAction),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'export_file',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.description_outlined),
                              title: Text(strings.exportAdviceFileAction),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'copy_all',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.content_copy_outlined),
                              title: Text(strings.copyAllAdvicesAction),
                            ),
                          ),
                        ],
                      ),
                    IconButton(
                      tooltip: strings.close,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (advices.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    strings.adviceGesturesHint,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: advices.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 48,
                                  color: Colors.green.shade700,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  strings.dailyAdviceAllGoodTitle,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  strings.dailyAdviceAllGoodBody,
                                  style: theme.textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: _scrollController,
                          itemCount: advices.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (ctx, index) {
                            final item = advices[index];
                            final (bg, fg, icon) =
                                _severityVisuals(item.severity, theme);
                            final severityText =
                                _severityLabel(item.severity, strings);
                            final actionBtnLabel = switch (item.actionType) {
                              AdviceActionType.addToStockIn =>
                                strings.addToStockInAction,
                              AdviceActionType.editPrice =>
                                strings.adviceUpdatePriceBtn,
                              AdviceActionType.barcodeLabel =>
                                strings.adviceGenerateBarcodeBtn,
                              AdviceActionType.openProduct =>
                                strings.adviceOpenProductBtn,
                              AdviceActionType.messageCustomer =>
                                strings.adviceWriteWhatsAppBtn,
                              AdviceActionType.none => null,
                            };

                            return Card(
                              margin: EdgeInsets.zero,
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () =>
                                    _handleCardTap(item.id, advices.length),
                                onLongPress: () =>
                                    _copySingleAdvice(context, item, strings),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: bg,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(icon, size: 14, color: fg),
                                                const SizedBox(width: 4),
                                                Text(
                                                  severityText,
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                    color: fg,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Spacer(),
                                          IconButton(
                                            tooltip: strings.copyTextBtn,
                                            onPressed: () => _copySingleAdvice(
                                              context,
                                              item,
                                              strings,
                                            ),
                                            icon: const Icon(
                                              Icons.content_copy_outlined,
                                              size: 18,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          IconButton(
                                            tooltip: strings.shareAdviceBtn,
                                            onPressed: () => _shareSingleAdvice(
                                              item,
                                              strings,
                                            ),
                                            icon: const Icon(
                                              Icons.ios_share_outlined,
                                              size: 18,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        item.title,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.body,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      if (actionBtnLabel != null &&
                                          (item.product != null ||
                                              item.actionType ==
                                                  AdviceActionType
                                                      .messageCustomer)) ...[
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: FilledButton.tonal(
                                            style: FilledButton.styleFrom(
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            onPressed: () async {
                                              if (item.actionType ==
                                                  AdviceActionType
                                                      .messageCustomer) {
                                                final msg =
                                                    item.whatsappMessage ??
                                                        item.body;
                                                await Share.share(
                                                  msg,
                                                  subject: item.customerName ??
                                                      strings.dailyAdviceBadge,
                                                );
                                                return;
                                              }
                                              final prod = item.product;
                                              if (prod == null) return;
                                              if (item.actionType ==
                                                  AdviceActionType
                                                      .addToStockIn) {
                                                await widget
                                                    .onAddToStockIn(prod);
                                                return;
                                              }
                                              Navigator.of(context).pop();
                                              switch (item.actionType) {
                                                case AdviceActionType.editPrice:
                                                  widget.onEditPrice(prod);
                                                case AdviceActionType
                                                      .barcodeLabel:
                                                  widget
                                                      .onOpenBarcodeLabel(prod);
                                                case AdviceActionType
                                                      .openProduct:
                                                  widget.onOpenProduct(prod);
                                                case AdviceActionType
                                                      .addToStockIn:
                                                case AdviceActionType
                                                      .messageCustomer:
                                                case AdviceActionType.none:
                                                  break;
                                              }
                                            },
                                            child: Text(actionBtnLabel),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

(Color, Color, IconData) _severityVisuals(
  AdviceSeverity severity,
  ThemeData theme,
) {
  switch (severity) {
    case AdviceSeverity.urgent:
      return (
        theme.colorScheme.errorContainer.withValues(alpha: 0.75),
        theme.colorScheme.onErrorContainer,
        Icons.priority_high_rounded,
      );
    case AdviceSeverity.warning:
      return (
        Colors.amber.shade100,
        Colors.amber.shade900,
        Icons.warning_amber_rounded,
      );
    case AdviceSeverity.opportunity:
      return (
        Colors.teal.shade50,
        Colors.teal.shade900,
        Icons.lightbulb_outline_rounded,
      );
    case AdviceSeverity.info:
      return (
        theme.colorScheme.primaryContainer.withValues(alpha: 0.75),
        theme.colorScheme.onPrimaryContainer,
        Icons.tips_and_updates_outlined,
      );
  }
}
