import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_package;
import 'package:flutter/services.dart' show rootBundle;

class DatabaseHelper {
  static const _dbName = 'albums.db';
  static const _dbVersion = 1;
  static Database? _db;

  static Future<Database> initDB() async {
    if (_db != null) return _db!;
    final databasesPath = await getDatabasesPath();
    final path = '$databasesPath${Platform.pathSeparator}$_dbName';
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        final sql = await rootBundle.loadString('assets/sql/init_album.sql');
        await db.execute(sql);
      },
    );
    return _db!;
  }

  static Future<Map<String, List<FileEntry>>> getFilesByDirectory() async {
    final db = await initDB();
    final rows = await db.rawQuery(
      'SELECT hash, value FROM album WHERE key = ?',
      ['path'],
    );

    final Map<String, List<FileEntry>> grouped = {};
    for (final row in rows) {
      final path = row['value'] as String?;
      final hash = row['hash'] as String?;
      if (path == null || hash == null) continue;

      final directory = path_package.dirname(path);
      final entry = FileEntry(hash: hash, path: path, directory: directory);
      grouped.putIfAbsent(directory, () => []).add(entry);
    }

    return grouped;
  }
}

class FileEntry {
  final String hash;
  final String path;
  final String directory;

  FileEntry({required this.hash, required this.path, required this.directory});
}
