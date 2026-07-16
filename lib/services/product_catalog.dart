import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/barcode_utils.dart';
import '../models/product.dart';

class ProductCatalog {
  static const _assetPath = 'assets/product_catalog.json';
  static const _versionKey = 'product_catalog_version';

  Database? _database;
  int _productCount = 0;
  int _ambiguousBarcodeCount = 0;

  int get productCount => _productCount;
  int get ambiguousBarcodeCount => _ambiguousBarcodeCount;

  Database get _db {
    final database = _database;
    if (database == null) {
      throw StateError('Product catalog is not initialized');
    }
    return database;
  }

  Future<void> initialize() async {
    final databasePath = path.join(
      await getDatabasesPath(),
      'ascona_product_catalog.db',
    );
    _database = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE products (
            barcode TEXT NOT NULL,
            name TEXT NOT NULL,
            name_search TEXT NOT NULL,
            PRIMARY KEY (barcode, name)
          )
        ''');
        await database.execute(
          'CREATE INDEX products_name_search_idx ON products(name_search)',
        );
      },
    );

    final raw = await rootBundle.loadString(_assetPath);
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    final version = payload['version'] as String? ?? 'unknown';
    final preferences = await SharedPreferences.getInstance();
    final installedVersion = preferences.getString(_versionKey);
    final existingCount = Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM products'),
        ) ??
        0;

    if (installedVersion != version || existingCount == 0) {
      final items = payload['items'] as List<dynamic>? ?? const [];
      await _db.transaction((transaction) async {
        await transaction.delete('products');
        final batch = transaction.batch();
        for (final item in items) {
          final map = item as Map<String, dynamic>;
          final barcode = normalizeProductBarcode(map['code'] as String? ?? '');
          final name = (map['name'] as String? ?? '').trim();
          if (barcode.isEmpty || name.isEmpty) continue;
          batch.insert(
            'products',
            {
              'barcode': barcode,
              'name': name,
              'name_search': name.toLowerCase(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
      });
      await preferences.setString(_versionKey, version);
    }

    await _loadStats();
  }

  Future<void> _loadStats() async {
    _productCount = Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM products'),
        ) ??
        0;
    _ambiguousBarcodeCount = Sqflite.firstIntValue(
          await _db.rawQuery('''
            SELECT COUNT(*) FROM (
              SELECT barcode FROM products
              GROUP BY barcode HAVING COUNT(*) > 1
            )
          '''),
        ) ??
        0;
  }

  Future<List<Product>> findByBarcode(String value) async {
    final barcode = normalizeProductBarcode(value);
    if (barcode.isEmpty) return const [];
    final rows = await _db.query(
      'products',
      columns: ['barcode', 'name'],
      where: 'barcode = ?',
      whereArgs: [barcode],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => Product(
            barcode: row['barcode'] as String,
            name: row['name'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<List<Product>> searchByName(String value, {int limit = 30}) async {
    final tokens = value
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 2)
        .take(5)
        .toList();
    if (tokens.isEmpty) return const [];

    final where = List.filled(tokens.length, 'name_search LIKE ?').join(' AND ');
    final rows = await _db.query(
      'products',
      columns: ['barcode', 'name'],
      where: where,
      whereArgs: tokens.map((token) => '%$token%').toList(),
      orderBy: 'name COLLATE NOCASE',
      limit: limit,
    );
    return rows
        .map(
          (row) => Product(
            barcode: row['barcode'] as String,
            name: row['name'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

