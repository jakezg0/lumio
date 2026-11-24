import 'dart:io';

import 'package:flutter/material.dart';

class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({
    super.key,
    required this.imagePath,
    this.size = 48,
    this.borderRadius = 10,
    this.onTap,
  });

  final String imagePath;
  final double size;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clean = imagePath.trim();
    final hasFile = clean.isNotEmpty && File(clean).existsSync();

    final content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasFile
          ? Image.file(
              File(clean),
              fit: BoxFit.cover,
              cacheWidth: (size * 2.5).round(),
              errorBuilder: (_, _, _) => Icon(
                Icons.inventory_2_outlined,
                size: size * 0.48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Icon(
              Icons.inventory_2_outlined,
              size: size * 0.48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
    );

    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(borderRadius),
      onTap: onTap,
      child: content,
    );
  }
}

Future<void> showProductPhotoPreview(
  BuildContext context, {
  required String title,
  required String imagePath,
}) async {
  final clean = imagePath.trim();
  if (clean.isEmpty || !File(clean).existsSync()) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.65,
            ),
            child: Image.file(
              File(clean),
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    ),
  );
}
