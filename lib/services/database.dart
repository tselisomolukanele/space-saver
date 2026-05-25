import 'dart:io';
import 'dart:developer';

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
    List<String> keys = ['path', 'album'];
    String placeholders = List.filled(keys.length, '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT hash, value, key FROM album WHERE key IN ($placeholders)',
      keys,
    );

    final Map<String, List<FileEntry>> tagEntries = {};
    final Map<String, List<String>> hashDirectories = {};
    final Map<String, List<String>> hashAlbums = {};
    for (final row in rows) {
      final value = row['value'] as String;
      final hash = row['hash'] as String;
      final key = row['key'] as String;
      log('Processing row: hash=${hash.substring(0, 6)}, key=$key, value=$value', level: 500);
      if (key == 'path') {
        log('Processing ${hash.substring(0, 6)} for path $value', level: 500);
        final directory = path_package.dirname(value);
        if (hashAlbums.containsKey(hash)) {
          log('Hash ${hash.substring(0, 6)} already has albums', level: 500);
          for (var album in hashAlbums[hash]!) {
            tagEntries[album]!
            .where((e) => e.hash == hash)
            .forEach((entry) {
              log('Updating entry for hash ${hash.substring(0, 6)} with path $value and directory $directory', level: 500);
              entry.path = value;
              entry.directory = directory;
            });
          }

          continue;
        } else {
          log('Hash ${hash.substring(0, 6)} has no albums, creating new directory entry in path $value in directory $directory', level: 500); 
          final entry = FileEntry(hash: hash, path: value, directory: directory);
          tagEntries.putIfAbsent(directory, () => []).add(entry);
          hashDirectories.putIfAbsent(hash, () => []).add(directory);
        }
      } else if (key == 'album') {
        log('Processing ${hash.substring(0, 6)} for album $value', level: 500);
        if (hashDirectories.containsKey(hash)) {
          log('Hash ${hash.substring(0, 6)} already has directories', level: 500);
          FileEntry foundEntry 
            = (tagEntries[hashDirectories[hash]!.first] 
              ?.firstWhere((e) => e.hash == hash))!;
        
          for (var dir in hashDirectories[hash]!) {
            tagEntries[dir]
            ?.where((e) => e.hash == hash)
            .forEach((e) => e.absolete = true);
          }

          // hashDirectories.remove(hash);

          tagEntries.putIfAbsent(value, () => []).add(FileEntry(hash: foundEntry.hash, path: foundEntry.path, directory: foundEntry.directory));
          hashAlbums.putIfAbsent(hash, () => []).add(value);
        } else {
          log('Hash ${hash.substring(0, 6)} has no directories, creating new entry for album $value', level: 500);
          tagEntries.putIfAbsent(value, () => []).add(FileEntry(hash: hash, path: '', directory: ''));
          hashAlbums.putIfAbsent(hash, () => []).add(value);
        }
      }
    }

    // Remove obsolete entries
    for (var entries in tagEntries.values) {
      entries.removeWhere((e) => e.absolete);
    }

    return tagEntries;
  }
}

class FileEntry {
  final String hash;
  String path;
  String directory;
  bool absolete = false;

  FileEntry({required this.hash, required this.path, required this.directory});
}
