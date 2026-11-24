import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class ProductImageService {
  const ProductImageService._();

  static Directory resolveImagesDirectory({Directory? customDirectory}) {
    if (customDirectory != null) {
      if (!customDirectory.existsSync()) {
        customDirectory.createSync(recursive: true);
      }
      return customDirectory;
    }
    if (Platform.isAndroid) {
      String pkg = 'com.example.flutter_application_1';
      try {
        final raw = File('/proc/self/cmdline').readAsStringSync();
        final clean = raw.split('\x00').first.split(':').first.trim();
        if (clean.isNotEmpty) pkg = clean;
      } catch (_) {}
      for (final candidate in ['/data/user/0/$pkg', '/data/data/$pkg']) {
        if (Directory(candidate).existsSync()) {
          final dir = Directory('$candidate/files/product_images');
          if (!dir.existsSync()) dir.createSync(recursive: true);
          return dir;
        }
      }
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final baseDir = home != null && home.isNotEmpty
        ? Directory('$home/.small_shop_inventory/product_images')
        : Directory('${Directory.systemTemp.path}/small_shop_inventory/product_images');
    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
    }
    return baseDir;
  }

  static Future<String?> pickAndSaveThumbnail({
    required ImageSource source,
    String? productId,
    Directory? customDirectory,
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return null;
    return saveImageBytes(
      bytes,
      productId: productId,
      customDirectory: customDirectory,
    );
  }

  static Future<String> saveImageBytes(
    Uint8List bytes, {
    String? productId,
    Directory? customDirectory,
  }) async {
    final dir = resolveImagesDirectory(customDirectory: customDirectory);
    final safeId = (productId ?? 'prd')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final fileName =
        '${safeId.isEmpty ? 'prd' : safeId}_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final target = File('${dir.path}/$fileName');
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  static Future<void> deleteImageFile(String path) async {
    final clean = path.trim();
    if (clean.isEmpty) return;
    try {
      final file = File(clean);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
