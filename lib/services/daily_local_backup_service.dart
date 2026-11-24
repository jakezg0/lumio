import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import 'export_service.dart';
import 'inventory_storage.dart';

class DailyBackupEntry {
  const DailyBackupEntry({
    required this.dateKey,
    required this.file,
    required this.modifiedAt,
    required this.sizeBytes,
  });

  final String dateKey;
  final File file;
  final DateTime modifiedAt;
  final int sizeBytes;
}

class DailyLocalBackupService {
  DailyLocalBackupService({
    this.customDirectory,
    this.maxBackups = 7,
  });

  final Directory? customDirectory;
  final int maxBackups;

  static const String _filePrefix = 'lumio_daily_';
  static const String _fileSuffix = '.json.gz';

  String _androidPackageName() {
    try {
      final raw = File('/proc/self/cmdline').readAsStringSync();
      final clean = raw.split('\x00').first.split(':').first.trim();
      if (clean.isNotEmpty) return clean;
    } catch (_) {}
    return 'com.example.flutter_application_1';
  }

  String _androidDataRoot(String pkg) {
    for (final candidate in ['/data/user/0/$pkg', '/data/data/$pkg']) {
      if (Directory(candidate).existsSync()) return candidate;
    }
    final tempDir = Directory.systemTemp;
    if (tempDir.path.endsWith('/cache') ||
        tempDir.path.endsWith('/code_cache')) {
      return tempDir.parent.path;
    }
    return tempDir.path;
  }

  Directory _resolveDirectory() {
    final customDir = customDirectory;
    if (customDir != null) {
      if (!customDir.existsSync()) {
        customDir.createSync(recursive: true);
      }
      return customDir;
    }
    if (Platform.isAndroid) {
      final pkg = _androidPackageName();
      final root = _androidDataRoot(pkg);
      final dir = Directory('$root/files/small_shop_inventory/daily_backups');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    }
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final dir = home != null && home.isNotEmpty
        ? Directory('$home/.small_shop_inventory/daily_backups')
        : Directory('${Directory.systemTemp.path}/small_shop_inventory/daily_backups');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static String formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  File _fileForDateKey(Directory dir, String dateKey) =>
      File('${dir.path}/$_filePrefix$dateKey$_fileSuffix');

  /// Saves a gzip-compressed JSON snapshot once per calendar day and rotates
  /// old backups so at most [maxBackups] (default 7) daily files remain.
  Future<bool> saveDailyBackupIfNeeded(
    ShopDataSnapshot snapshot, {
    DateTime? now,
    bool force = false,
  }) async {
    final dir = _resolveDirectory();
    final dateKey = formatDateKey(now ?? DateTime.now());
    final targetFile = _fileForDateKey(dir, dateKey);

    if (!force && await targetFile.exists() && await targetFile.length() > 0) {
      return false;
    }

    final compressed = await compute(_encodeAndGzipSnapshot, snapshot);
    final tmpFile = File('${targetFile.path}.tmp');
    try {
      await tmpFile.writeAsBytes(compressed, flush: true);
      await tmpFile.rename(targetFile.path);
    } catch (_) {
      try {
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {}
      rethrow;
    }

    await _rotateOldBackups(dir);
    return true;
  }

  Future<void> _rotateOldBackups(Directory dir) async {
    final entries = await listBackups();
    if (entries.length <= maxBackups) return;
    for (final old in entries.skip(maxBackups)) {
      try {
        if (await old.file.exists()) {
          await old.file.delete();
        }
      } catch (_) {
        // Best-effort cleanup of old rotated backups.
      }
    }
  }

  Future<List<DailyBackupEntry>> listBackups() async {
    final dir = _resolveDirectory();
    if (!await dir.exists()) return const [];
    final entries = <DailyBackupEntry>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_filePrefix) || !name.endsWith(_fileSuffix)) {
        continue;
      }
      final dateKey = name.substring(
        _filePrefix.length,
        name.length - _fileSuffix.length,
      );
      final stat = await entity.stat();
      if (stat.size <= 0) continue;
      entries.add(
        DailyBackupEntry(
          dateKey: dateKey,
          file: entity,
          modifiedAt: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    }
    entries.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    return entries;
  }

  Future<ShopDataSnapshot?> loadBackup(DailyBackupEntry entry) async {
    try {
      if (!await entry.file.exists()) return null;
      final bytes = await entry.file.readAsBytes();
      if (bytes.isEmpty) return null;
      return await compute(_gunzipAndDecodeSnapshot, bytes);
    } catch (_) {
      return null;
    }
  }
}

List<int> _encodeAndGzipSnapshot(ShopDataSnapshot snapshot) {
  final jsonStr = ExportService.buildBackupJson(snapshot);
  return gzip.encode(utf8.encode(jsonStr));
}

ShopDataSnapshot _gunzipAndDecodeSnapshot(List<int> gzBytes) {
  final jsonStr = utf8.decode(gzip.decode(gzBytes));
  return ExportService.parseBackupJson(jsonStr);
}
