import 'dart:io';

import 'package:sqflite/sqflite.dart';
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
}
